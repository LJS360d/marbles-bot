import * as THREE from "three";

export const TRACK_GLB_URL = "/3d/pull/pull.glb";

/** Textured sphere radius for pull cinematic marbles. */
export const GACHA_MARBLE_RADIUS = 0.25;

export const rarityColor = (rarity) => {
  if (rarity >= 3) return 0xffc857;
  if (rarity === 2) return 0x8fd3ff;
  return 0xd1d5db;
};

export const LIGHT_OFF_COLOR = new THREE.Color(0x1f2937);
export const LIGHT_RED_COLOR = new THREE.Color(0xef4444);
export const LIGHT_GREEN_COLOR = new THREE.Color(0x22c55e);
export const LIGHT_GOLD_COLOR = new THREE.Color(0xfbbf24);
export const LIGHT_WARNING_COLOR = new THREE.Color(0xf97316);

export const maxRarityInResults = (results) =>
  (results || []).reduce((acc, row) => Math.max(acc, Number(row?.rarity) || 1), 1);

export const seededRandom = (seed) => {
  let s = seed >>> 0;
  return () => {
    s = (1664525 * s + 1013904223) >>> 0;
    return s / 0x100000000;
  };
};

export const textureUrlFromResult = (entry) => entry?.texture_url || entry?.textureUrl || null;

export const canonicalTextureUrl = (url) => {
  if (!url || typeof url !== "string") return null;
  try {
    return new URL(url, window.location.href).href;
  } catch {
    return url;
  }
};

export const clearMaterialTextureRefs = (m) => {
  if (!m || typeof m !== "object") return;
  for (const k of Object.keys(m)) {
    try {
      const v = m[k];
      if (v && typeof v === "object" && v.isTexture) {
        m[k] = null;
      }
    } catch {
      /* ignore */
    }
  }
};

export function applyMarbleTextureSettings(tex) {
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.flipY = true;
  tex.wrapS = THREE.ClampToEdgeWrapping;
  tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.generateMipmaps = true;
}

export function isAtlasTexture(texture) {
  const w = texture?.image?.width || 0;
  const h = texture?.image?.height || 0;
  return h > 0 && w >= h * 1.9;
}

export function atlasToEquirect(texture, cacheKey, mappedTextureCache) {
  const hit = mappedTextureCache.get(cacheKey);
  if (hit) return hit;

  const srcImage = texture?.image;
  const sw = srcImage?.width || 0;
  const sh = srcImage?.height || 0;
  if (sw <= 0 || sh <= 0) return texture;

  const srcCanvas = document.createElement("canvas");
  srcCanvas.width = sw;
  srcCanvas.height = sh;
  const srcCtx = srcCanvas.getContext("2d", { willReadFrequently: true });
  srcCtx.drawImage(srcImage, 0, 0, sw, sh);
  const srcData = srcCtx.getImageData(0, 0, sw, sh).data;

  const outCanvas = document.createElement("canvas");
  outCanvas.width = sw;
  outCanvas.height = sh;
  const outCtx = outCanvas.getContext("2d");
  const outImage = outCtx.createImageData(sw, sh);
  const out = outImage.data;

  const r = sh * 0.5;
  const safeR = Math.max(2, r - 4);
  const cy = sh * 0.5;
  const frontCx = sw * 0.25;
  const backCx = sw * 0.75;

  const sample = (sx, sy) => {
    const ix = Math.max(0, Math.min(sw - 1, Math.round(sx)));
    const iy = Math.max(0, Math.min(sh - 1, Math.round(sy)));
    const i = (iy * sw + ix) * 4;
    return [srcData[i], srcData[i + 1], srcData[i + 2], srcData[i + 3]];
  };

  for (let y = 0; y < sh; y += 1) {
    const v = (y + 0.5) / sh;
    const lat = (0.5 - v) * Math.PI;
    const sinLat = Math.sin(lat);
    const cosLat = Math.cos(lat);

    for (let x = 0; x < sw; x += 1) {
      const u = (x + 0.5) / sw;
      const lon = (u - 0.5) * Math.PI * 2.0;
      const nx = Math.sin(lon) * cosLat;
      const ny = sinLat;
      const nz = Math.cos(lon) * cosLat;

      let cx = frontCx;
      let localX = nx;
      if (nz < 0.0) {
        cx = backCx;
        localX = -nx;
      }

      let sx = cx + localX * safeR;
      let sy = cy - ny * safeR;
      let dx = sx - cx;
      let dy = sy - cy;
      const d2 = dx * dx + dy * dy;
      const di = (y * sw + x) * 4;

      if (d2 > safeR * safeR) {
        const invLen = 1.0 / Math.sqrt(d2);
        dx = dx * invLen * safeR;
        dy = dy * invLen * safeR;
        sx = cx + dx;
        sy = cy + dy;
      }

      let [pr, pg, pb, pa] = sample(sx, sy);
      if (pa < 32) {
        const sx2 = cx + localX * Math.max(1, safeR - 8);
        const sy2 = cy - ny * Math.max(1, safeR - 8);
        [pr, pg, pb, pa] = sample(sx2, sy2);
      }
      out[di + 0] = pr;
      out[di + 1] = pg;
      out[di + 2] = pb;
      out[di + 3] = 255;
    }
  }

  const seamBand = Math.max(4, Math.floor(sw / 256));
  for (let y = 0; y < sh; y += 1) {
    const i0 = (y * sw + 0) * 4;
    const i1 = (y * sw + (sw - 1)) * 4;
    const avg = [
      ((out[i0 + 0] + out[i1 + 0]) * 0.5) | 0,
      ((out[i0 + 1] + out[i1 + 1]) * 0.5) | 0,
      ((out[i0 + 2] + out[i1 + 2]) * 0.5) | 0,
      ((out[i0 + 3] + out[i1 + 3]) * 0.5) | 0,
    ];
    for (let k = 0; k < 4; k += 1) {
      out[i0 + k] = avg[k];
      out[i1 + k] = avg[k];
    }

    for (let b = 1; b <= seamBand; b += 1) {
      const t = b / (seamBand + 1);
      const il = (y * sw + b) * 4;
      const ir = (y * sw + (sw - 1 - b)) * 4;
      for (let k = 0; k < 4; k += 1) {
        out[il + k] = (out[il + k] * (1 - t) + avg[k] * t) | 0;
        out[ir + k] = (out[ir + k] * (1 - t) + avg[k] * t) | 0;
      }
    }
  }

  outCtx.putImageData(outImage, 0, 0);
  const mapped = new THREE.CanvasTexture(outCanvas);
  applyMarbleTextureSettings(mapped);
  mapped.wrapS = THREE.RepeatWrapping;
  mapped.wrapT = THREE.ClampToEdgeWrapping;
  mappedTextureCache.set(cacheKey, mapped);
  return mapped;
}

export function buildMarbleMaterial(texture, cacheKey, mappedTextureCache) {
  if (isAtlasTexture(texture)) {
    const mapped = atlasToEquirect(texture, cacheKey, mappedTextureCache);
    return new THREE.MeshBasicMaterial({
      map: mapped,
      color: 0xffffff,
      transparent: false,
    });
  }
  return new THREE.MeshBasicMaterial({
    map: texture,
    color: 0xffffff,
    transparent: true,
  });
}
