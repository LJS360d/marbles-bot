import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

const GACHA_SKIP_CONFIRM_KEY = "gachaSkipConfirm";

const TRACK_GLB_URL = "/3d/pull/pull.glb";

/** Textured sphere radius for pull cinematic marbles. */
const GACHA_MARBLE_RADIUS = 0.25;

const rarityColor = (rarity) => {
  if (rarity >= 3) return 0xffc857;
  if (rarity === 2) return 0x8fd3ff;
  return 0xd1d5db;
};

const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

const easeInOutQuad = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);

const waitMs = (ms, registerTimer, isStale) =>
  new Promise((resolve) => {
    if (isStale()) {
      resolve(false);
      return;
    }
    const id = window.setTimeout(() => {
      resolve(!isStale());
    }, ms);
    registerTimer(id);
  });

const LIGHT_OFF_COLOR = new THREE.Color(0x1f2937);
const LIGHT_RED_COLOR = new THREE.Color(0xef4444);
const LIGHT_GREEN_COLOR = new THREE.Color(0x22c55e);
const LIGHT_GOLD_COLOR = new THREE.Color(0xfbbf24);
const LIGHT_WARNING_COLOR = new THREE.Color(0xf97316);

const maxRarityInResults = (results) =>
  (results || []).reduce((acc, row) => Math.max(acc, Number(row?.rarity) || 1), 1);

const seededRandom = (seed) => {
  let s = seed >>> 0;
  return () => {
    s = (1664525 * s + 1013904223) >>> 0;
    return s / 0x100000000;
  };
};

const textureUrlFromResult = (entry) => entry?.texture_url || entry?.textureUrl || null;

const canonicalTextureUrl = (url) => {
  if (!url || typeof url !== "string") return null;
  try {
    return new URL(url, window.location.href).href;
  } catch {
    return url;
  }
};

const clearMaterialTextureRefs = (m) => {
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

function applyMarbleTextureSettings(tex) {
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.flipY = true;
  tex.wrapS = THREE.ClampToEdgeWrapping;
  tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.generateMipmaps = true;
}

function isAtlasTexture(texture) {
  const w = texture?.image?.width || 0;
  const h = texture?.image?.height || 0;
  return h > 0 && w >= h * 1.9;
}

function atlasToEquirect(texture, cacheKey, mappedTextureCache) {
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

function buildMarbleMaterial(texture, cacheKey, mappedTextureCache) {
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

const GachaPage = {
  mounted() {
    const saved = window.localStorage.getItem(GACHA_SKIP_CONFIRM_KEY) === "true";
    this.pushEvent("gacha_pref_loaded", { skip_confirm: saved });

    this.changeHandler = (event) => {
      if (!event.target.matches("[data-gacha-skip-confirm]")) return;

      if (event.target.checked) {
        window.localStorage.setItem(GACHA_SKIP_CONFIRM_KEY, "true");
      } else {
        window.localStorage.removeItem(GACHA_SKIP_CONFIRM_KEY);
      }
    };

    this.el.addEventListener("change", this.changeHandler);
  },

  destroyed() {
    if (this.changeHandler) {
      this.el.removeEventListener("change", this.changeHandler);
    }
  },
};

const GachaCinematic = {
  mounted() {
    this.webglReady = false;
    this.activeTimers = [];
    this.animationFrame = null;
    this.currentPayload = null;
    this.results = [];
    this.currentIndex = 0;
    this.stage = "idle";
    this.preloadGen = 0;
    this.textureCache = new Map();
    this.mappedTextureCache = new Map();
    this.revealPaused = false;
    this.revealOverlayEl = null;
    this.legendaryOverlayEl = null;
    this.resizeHandler = () => this.resizeRenderer();
    this._onRevealAdvance = (e) => {
      if (this.stage !== "reveal" || !this.revealPaused) return;
      e.preventDefault();
      e.stopPropagation();
      this.advanceRevealOnClick();
    };
    this.introActive = false;
    this.introSegment = null;
    this.introStartedAt = 0;
    this.introDurationMs = 2400;
    this.introDriftMs = 720;
    this.marbleCameraPanMs = 820;
    this.introFrom = new THREE.Vector3(0, 26, 0.35);
    this.introTo = new THREE.Vector3(0, 2.2, 6);
    this.driftFrom = new THREE.Vector3();
    this.driftTo = new THREE.Vector3();
    this.finalCameraPosition = new THREE.Vector3();
    this.introLookAt = new THREE.Vector3(0, 0, 0);
    this.marbleLookAt = new THREE.Vector3(0, 0, 0);
    this.trackRoot = null;
    this.marbleRoot = null;
    this.marbleMotion = null;
    this.raceLights = [];
    this.raceLightFocus = null;
    this.marbleSpawnPoint = null;
    this.startLinePoint = null;
    this.trackRollY = null;
    this.sequenceId = 0;
    this.gltfLoader = new GLTFLoader();
    this.textureLoader = new THREE.TextureLoader();
    this.gltfLoader.setCrossOrigin("anonymous");
    this.textureLoader.setCrossOrigin("anonymous");

    this.setupScene();
    this.ensureRevealStyles();
    this.el.addEventListener("click", this._onRevealAdvance);
    window.addEventListener("resize", this.resizeHandler);

    this.handleEvent("gacha_animation_start", (payload) => {
      this.start(payload);
    });

    this.handleEvent("gacha_animation_skip", () => {
      this.finishEarly();
    });
  },

  destroyed() {
    this.clearTimers();
    this.preloadGen += 1;
    this.disposeCinematicResources();
    window.removeEventListener("resize", this.resizeHandler);
    this.el.removeEventListener("click", this._onRevealAdvance);
  },

  disposeCinematicResources() {
    this.introActive = false;
    this.introSegment = null;
    this.marbleMotion = null;
    this.raceLights = [];
    this.raceLightFocus = null;
    this.marbleSpawnPoint = null;
    this.startLinePoint = null;
    this.trackRollY = null;
    this.revealPaused = false;
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
    if (this.marbleRoot && this.scene) {
      this.disposeObject3D(this.marbleRoot, { keepTextures: true });
    }
    this.marbleRoot = null;
    if (this.trackRoot && this.scene) {
      this.disposeObject3D(this.trackRoot);
    }
    this.trackRoot = null;
    this.disposeTextureCache();
    this.hideRevealOverlay(true);
    this.hideLegendaryOverlay(true);
    this.removeRevealStyles();
    this.hideLoadingOverlay(true);
    this.disposeSceneRemainder();
    if (this.renderer) {
      this.renderer.dispose();
      if (this.renderer.domElement.parentNode === this.el) {
        this.el.removeChild(this.renderer.domElement);
      }
      this.renderer = null;
    }
    this.scene = null;
    this.camera = null;
    this.webglReady = false;
  },

  removeRevealStyles() {
    const st = this.el.querySelector("[data-gacha-reveal-styles]");
    if (st) st.remove();
  },

  disposeSceneRemainder() {
    if (!this.scene) return;
    this.scene.traverse((obj) => {
      if (obj.geometry) {
        obj.geometry.dispose();
      }
      if (obj.material) {
        const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
        mats.forEach((m) => {
          if (m && m.map) m.map.dispose();
          m?.dispose?.();
        });
      }
    });
    this.scene.clear();
  },

  ensureLoadingOverlay() {
    let el = this.el.querySelector("[data-gacha-cinematic-loading]");
    if (!el) {
      el = document.createElement("div");
      el.dataset.gachaCinematicLoading = "";
      el.className =
        "pointer-events-auto absolute inset-0 z-30 flex flex-col items-center justify-center gap-4 bg-black/75 text-white";
      el.innerHTML = `
        <div
          class="h-12 w-12 rounded-full border-2 border-white/20 border-t-white animate-spin"
          aria-hidden="true"
        ></div>
        <p class="text-sm font-medium tracking-wide text-white/90">Loading scene…</p>
      `;
      this.el.appendChild(el);
    }
    return el;
  },

  showLoadingOverlay() {
    const el = this.ensureLoadingOverlay();
    el.classList.remove("hidden");
  },

  hideLoadingOverlay(forceRemove = false) {
    const el = this.el.querySelector("[data-gacha-cinematic-loading]");
    if (!el) return;
    if (forceRemove) {
      el.remove();
    } else {
      el.classList.add("hidden");
    }
  },

  disposeTextureCache() {
    if (!this.textureCache) return;
    for (const tex of this.textureCache.values()) {
      tex.dispose();
    }
    this.textureCache.clear();
    if (this.mappedTextureCache) {
      for (const tex of this.mappedTextureCache.values()) {
        tex.dispose();
      }
      this.mappedTextureCache.clear();
    }
  },

  ensureRevealStyles() {
    if (this.el.querySelector("[data-gacha-reveal-styles]")) return;
    const style = document.createElement("style");
    style.dataset.gachaRevealStyles = "";
    style.textContent = `
      @keyframes gacha-reveal-pop {
        0% { opacity: 0; transform: scale(0.82) translateY(12px); filter: blur(10px); }
        55% { opacity: 1; transform: scale(1.05) translateY(0); filter: blur(0); }
        100% { opacity: 1; transform: scale(1) translateY(0); filter: blur(0); }
      }
      @keyframes gacha-reveal-flash {
        0% { opacity: 0; transform: scale(0.9); }
        25% { opacity: 0.95; transform: scale(1.12); }
        100% { opacity: 0; transform: scale(1.35); }
      }
      @keyframes gacha-reveal-glow {
        0%, 100% { text-shadow: 0 0 8px rgba(255,255,255,0.35), 0 0 24px rgba(99,102,241,0.45); }
        50% { text-shadow: 0 0 16px rgba(255,255,255,0.55), 0 0 40px rgba(99,102,241,0.65); }
      }
      @keyframes gacha-reveal-shimmer {
        0% { transform: translateX(-100%); opacity: 0; }
        20% { opacity: 0.9; }
        100% { transform: translateX(200%); opacity: 0; }
      }
      @keyframes gacha-legendary-flicker {
        0%, 12%, 100% { opacity: 0; }
        5%, 9%, 25%, 39%, 60% { opacity: 0.72; }
        18%, 31%, 52%, 73% { opacity: 0.1; }
      }
      @keyframes gacha-legendary-stars {
        0% { transform: scale(0.4); opacity: 0; filter: blur(8px); }
        60% { transform: scale(1.12); opacity: 1; filter: blur(0); }
        100% { transform: scale(1); opacity: 0.95; filter: blur(0); }
      }
    `;
    this.el.appendChild(style);
  },

  ensureLegendaryOverlay() {
    if (this.legendaryOverlayEl) return;
    const wrap = document.createElement("div");
    wrap.dataset.gachaLegendaryOverlay = "";
    wrap.className =
      "pointer-events-none absolute inset-0 z-30 opacity-0 transition-opacity duration-150";
    wrap.innerHTML = `
      <div data-gacha-legendary-flicker class="absolute inset-0 bg-black opacity-0"></div>
      <div class="absolute inset-0 flex flex-col items-center justify-center gap-5 px-6 text-center">
        <img
          data-gacha-legendary-logo
          alt="Team logo"
          class="hidden h-28 w-28 rounded-full border border-amber-200/60 bg-black/35 p-2 shadow-[0_0_34px_rgba(251,191,36,0.45)]"
        />
        <p
          data-gacha-legendary-stars
          class="text-5xl font-bold tracking-[0.32em] text-amber-300 drop-shadow-[0_0_20px_rgba(251,191,36,0.8)] opacity-0"
        >
          ★★★
        </p>
      </div>
    `;
    this.el.appendChild(wrap);
    this.legendaryOverlayEl = wrap;
    this.legendaryLogoEl = wrap.querySelector("[data-gacha-legendary-logo]");
    this.legendaryFlickerEl = wrap.querySelector("[data-gacha-legendary-flicker]");
    this.legendaryStarsEl = wrap.querySelector("[data-gacha-legendary-stars]");
  },

  hideLegendaryOverlay(forceRemove = false) {
    if (!this.legendaryOverlayEl) return;
    this.legendaryOverlayEl.classList.add("opacity-0");
    if (forceRemove) {
      this.legendaryOverlayEl.remove();
      this.legendaryOverlayEl = null;
      this.legendaryLogoEl = null;
      this.legendaryFlickerEl = null;
      this.legendaryStarsEl = null;
    }
  },

  ensureRevealOverlay() {
    if (this.revealOverlayEl) return;
    const wrap = document.createElement("div");
    wrap.dataset.gachaRevealOverlay = "";
    wrap.className =
      "pointer-events-none absolute inset-0 z-20 p-6 opacity-0 transition-opacity duration-500 bg-transparent";
    wrap.innerHTML = `
      <div data-gacha-reveal-card class="pointer-events-none absolute left-1/2 top-1/2 max-w-lg -translate-x-1/2 -translate-y-1/2 text-center">
        <div
          data-gacha-reveal-flash
          class="pointer-events-none absolute inset-0 rounded-full bg-white/40 blur-2xl opacity-0"
        ></div>
        <div
          class="pointer-events-none absolute inset-x-0 top-1/2 h-px -translate-y-6 overflow-hidden rounded-full opacity-70"
          aria-hidden="true"
        >
          <div
            data-gacha-reveal-shimmer
            class="h-full w-1/3 bg-gradient-to-r from-transparent via-white/80 to-transparent"
            style="animation: gacha-reveal-shimmer 2.2s ease-in-out infinite;"
          ></div>
        </div>
        <p
          data-gacha-reveal-name
          class="relative text-3xl font-bold tracking-tight text-white sm:text-4xl"
          style="animation: gacha-reveal-pop 0.65s cubic-bezier(0.22, 1, 0.36, 1) both, gacha-reveal-glow 2.4s ease-in-out infinite;"
        ></p>
        <p
          data-gacha-reveal-rarity
          class="relative mt-2 text-lg font-semibold tracking-wide sm:text-xl"
        ></p>
      </div>
    `;
    this.el.appendChild(wrap);
    this.revealOverlayEl = wrap;
    this.revealCardEl = wrap.querySelector("[data-gacha-reveal-card]");
    this.revealNameEl = wrap.querySelector("[data-gacha-reveal-name]");
    this.revealRarityEl = wrap.querySelector("[data-gacha-reveal-rarity]");
  },

  hideRevealOverlay(forceRemove = false) {
    this.revealPaused = false;
    if (!this.revealOverlayEl) return;
    this.revealOverlayEl.classList.add("pointer-events-none", "opacity-0");
    this.revealOverlayEl.classList.remove("pointer-events-auto", "cursor-pointer");
    if (forceRemove) {
      this.revealOverlayEl.remove();
      this.revealOverlayEl = null;
      this.revealCardEl = null;
      this.revealNameEl = null;
      this.revealRarityEl = null;
    }
  },

  updateRevealOverlayPosition() {
    if (!this.revealOverlayEl || !this.revealCardEl || !this.marbleRoot || !this.camera) return;
    const p = this.marbleRoot.position.clone().project(this.camera);
    const w = Math.max(this.el.clientWidth, 1);
    const h = Math.max(this.el.clientHeight, 1);
    let x = (p.x * 0.5 + 0.5) * w;
    let y = (-p.y * 0.5 + 0.5) * h + 74;
    x = Math.max(120, Math.min(w - 120, x));
    y = Math.max(70, Math.min(h - 60, y));
    this.revealCardEl.style.left = `${x}px`;
    this.revealCardEl.style.top = `${y}px`;
  },

  rarityLabelClass(rarity) {
    const r = Number(rarity) || 1;
    if (r >= 3) return "text-amber-300 drop-shadow-[0_0_12px_rgba(251,191,36,0.55)]";
    if (r === 2) return "text-sky-300 drop-shadow-[0_0_12px_rgba(125,211,252,0.5)]";
    return "text-slate-200 drop-shadow-[0_0_8px_rgba(255,255,255,0.25)]";
  },

  showRevealOverlay(entry) {
    this.ensureRevealOverlay();
    const name = entry?.name || "Marble";
    const rarity = Number(entry?.rarity) || 1;
    const stars = "★".repeat(Math.min(5, Math.max(1, rarity)));
    this.revealNameEl.textContent = name;
    this.revealRarityEl.textContent = stars;
    this.revealRarityEl.className = `relative mt-2 text-lg font-semibold tracking-wide sm:text-xl ${this.rarityLabelClass(rarity)}`;
    const fx = this.revealOverlayEl.querySelector("[data-gacha-reveal-flash]");
    if (fx) {
      fx.style.animation = "none";
      void fx.offsetWidth;
      fx.style.animation = "gacha-reveal-flash 0.42s ease-out both";
    }
    const ra = this.revealRarityEl;
    ra.style.animation = "none";
    void ra.offsetWidth;
    ra.style.animation = "gacha-reveal-pop 0.72s cubic-bezier(0.22, 1, 0.36, 1) 0.08s both";
    const nm = this.revealNameEl;
    nm.style.animation = "none";
    void nm.offsetWidth;
    nm.style.animation =
      "gacha-reveal-pop 0.65s cubic-bezier(0.22, 1, 0.36, 1) both, gacha-reveal-glow 2.4s ease-in-out infinite";
    this.revealOverlayEl.classList.remove("pointer-events-none", "opacity-0");
    this.revealOverlayEl.classList.add("pointer-events-auto", "cursor-pointer");
    this.updateRevealOverlayPosition();
    this.pushEvent("gacha_animation_progress", {
      phase: "reveal",
      index: this.currentIndex + 1,
      total: this.results.length,
    });
  },

  advanceRevealOnClick() {
    if (this.stage !== "reveal" || !this.revealPaused) return;
    this.hideRevealOverlay();
    this.currentIndex += 1;
    if (this.currentIndex >= this.results.length) {
      this.complete();
      return;
    }
    const entry = this.results[this.currentIndex];
    this.showMarble(entry, this.currentIndex);
  },

  setupScene() {
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x080b12);

    this.camera = new THREE.PerspectiveCamera(
      60,
      this.el.clientWidth / Math.max(this.el.clientHeight, 1),
      0.1,
      200,
    );
    this.camera.position.copy(this.introTo);
    this.camera.lookAt(this.introLookAt);

    const ambient = new THREE.AmbientLight(0xffffff, 0.55);
    this.scene.add(ambient);

    const keyLight = new THREE.DirectionalLight(0xffffff, 1.15);
    keyLight.position.set(8, 18, 10);
    this.scene.add(keyLight);

    const rim = new THREE.DirectionalLight(0x6b9cff, 0.35);
    rim.position.set(-10, 6, -8);
    this.scene.add(rim);

    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(48, 48),
      new THREE.MeshStandardMaterial({
        color: 0x0b1220,
        roughness: 0.96,
        metalness: 0.05,
      }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -1.2;
    floor.receiveShadow = true;
    this.scene.add(floor);

    const grid = new THREE.GridHelper(40, 40, 0x1e293b, 0x0f172a);
    grid.position.y = -1.19;
    this.scene.add(grid);

    try {
      this.renderer = new THREE.WebGLRenderer({ antialias: true });
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      this.renderer.outputColorSpace = THREE.SRGBColorSpace;
      this.resizeRenderer();
      this.el.appendChild(this.renderer.domElement);
      this.webglReady = true;
      this.renderLoop();
    } catch {
      this.webglReady = false;
    }
  },

  renderLoop() {
    if (!this.renderer || !this.scene || !this.camera) {
      this.animationFrame = null;
      return;
    }
    this.animationFrame = requestAnimationFrame(() => this.renderLoop());

    if (this.introActive) {
      this.updateIntroCamera();
    }

    if (this.marbleRoot && this.marbleMotion) {
      const now = performance.now();
      const motion = this.marbleMotion;
      const baseT = Math.min(1, (now - motion.t0) / motion.duration);
      const e = easeOutCubic(baseT);
      let pos;
      if (!motion.crossed && baseT >= motion.crossAt) {
        motion.crossed = true;
        motion.freezeUntil = now + 220;
        this.showRevealOverlay(this.currentRevealEntry);
      }
      if (motion.freezeUntil && now < motion.freezeUntil) {
        const crossPos = new THREE.Vector3().lerpVectors(
          motion.spawn,
          motion.end,
          easeOutCubic(motion.crossAt),
        );
        pos = crossPos;
      } else {
        pos = new THREE.Vector3().lerpVectors(motion.spawn, motion.end, e);
      }
      this.marbleRoot.position.copy(pos);
      this.marbleRoot.position.y += 0.028 * Math.sin(baseT * Math.PI * 2.2);
      this.marbleRoot.rotation.z = 0.2 * Math.sin(baseT * Math.PI * 4.5);
      this.marbleRoot.rotation.y += motion.spinStep;

      if (baseT >= 1) {
        this.marbleRoot.position.copy(motion.end);
        this.marbleMotion = null;
        this.revealPaused = true;
      }
    } else if (this.marbleRoot && !this.introActive && !this.revealPaused) {
      this.marbleRoot.rotation.y += 0.018;
      this.marbleRoot.rotation.x += 0.008;
    }

    if (this.renderer) {
      this.renderer.render(this.scene, this.camera);
    }

    if (this.revealPaused) {
      this.updateRevealOverlayPosition();
    }
  },

  updateIntroCamera() {
    const now = performance.now();

    if (this.introSegment === "vertical") {
      const elapsed = now - this.introStartedAt;
      const u = Math.min(1, elapsed / this.introDurationMs);
      const e = easeOutCubic(u);
      this.camera.position.lerpVectors(this.introFrom, this.introTo, e);
      this.camera.lookAt(this.introLookAt);
      if (u >= 1) {
        this.introSegment = null;
        this.introActive = false;
        this.finalCameraPosition.copy(this.camera.position);
        this.beginLightsSequence();
      }
    } else if (this.introSegment === "marble_pan") {
      const elapsed = now - this.introStartedAt;
      const u = Math.min(1, elapsed / this.marbleCameraPanMs);
      const e = easeInOutQuad(u);
      this.camera.position.lerpVectors(this.driftFrom, this.driftTo, e);
      this.camera.lookAt(this.marbleLookAt);
      if (u >= 1) {
        this.finalCameraPosition.copy(this.camera.position);
        this.introSegment = null;
        this.introActive = false;
        this.runReveal();
      }
    }
  },

  start(payload) {
    this.clearTimers();
    this.preloadGen += 1;
    this.sequenceId += 1;
    const gen = this.preloadGen;
    this.introActive = false;
    this.introSegment = null;
    this.marbleMotion = null;
    this.raceLights = [];
    this.raceLightFocus = null;
    this.marbleSpawnPoint = null;
    this.startLinePoint = null;
    this.trackRollY = null;
    this.revealPaused = false;
    this.hideRevealOverlay(true);
    this.hideLegendaryOverlay(true);
    this.currentPayload = payload;
    this.results = payload.results || [];
    this.currentIndex = 0;
    this.stage = "loading";

    if (!this.renderer || !this.scene || !this.camera) {
      this.setupScene();
    }

    this.disposeObject3D(this.marbleRoot, { keepTextures: true });
    this.marbleRoot = null;

    this.disposeTextureCache();

    this.disposeObject3D(this.trackRoot);
    this.trackRoot = null;

    this.finalCameraPosition.copy(this.introTo);

    this.camera.position.copy(this.introFrom);
    this.camera.lookAt(this.introLookAt);

    this.showLoadingOverlay();

    this.preloadPullAssets(payload, gen)
      .catch(() => {})
      .finally(() => {
        if (gen !== this.preloadGen) return;
        this.hideLoadingOverlay();
        if (!this.currentPayload) return;
        this.beginIntroSequence();
      });
  },

  beginIntroSequence() {
    if (!this.currentPayload || this.stage === "done") return;
    this.stage = "intro";
    this.pushEvent("gacha_animation_progress", {
      phase: "intro",
      index: 0,
      total: this.results.length,
    });

    this.introSegment = "vertical";
    this.introStartedAt = performance.now();
    this.introActive = true;
  },

  async preloadPullAssets(payload, gen) {
    if (!this.webglReady || gen !== this.preloadGen) return;

    const results = payload.results || [];

    await this.loadTrackGltfPromise(gen);
    if (gen !== this.preloadGen) return;

    const urls = [
      ...new Set(results.map((r) => canonicalTextureUrl(textureUrlFromResult(r))).filter(Boolean)),
    ];
    await Promise.all(urls.map((u) => this.ensureTextureCached(u, gen)));
  },

  loadTrackGltfPromise(gen) {
    return new Promise((resolve) => {
      this.gltfLoader.load(
        TRACK_GLB_URL,
        (gltf) => {
          if (gen !== this.preloadGen) {
            gltf.scene.traverse((child) => {
              if (child.isMesh) {
                child.geometry?.dispose?.();
                const mat = child.material;
                if (Array.isArray(mat)) {
                  mat.forEach((m) => {
                    m.map?.dispose?.();
                    m?.dispose?.();
                  });
                } else {
                  mat.map?.dispose?.();
                  mat?.dispose?.();
                }
              }
            });
            resolve();
            return;
          }
          const root = gltf.scene;
          this.fitTrackToScene(root);
          this.scene.add(root);
          this.trackRoot = root;
          this.captureRaceLights(root);
          this.configureStageAnchors();
          resolve();
        },
        undefined,
        () => {
          if (gen === this.preloadGen) {
            this.introLookAt.set(0, 0, 0);
            this.marbleLookAt.set(0, 0, 0);
          }
          resolve();
        },
      );
    });
  },

  ensureTextureCached(url, gen) {
    const key = canonicalTextureUrl(url);
    if (!key || this.textureCache.has(key)) {
      return Promise.resolve();
    }

    return new Promise((resolve) => {
      this.textureLoader.load(
        key,
        (tex) => {
          if (gen !== this.preloadGen) {
            tex.dispose();
            resolve();
            return;
          }
          applyMarbleTextureSettings(tex);
          this.textureCache.set(key, tex);
          resolve();
        },
        undefined,
        () => resolve(),
      );
    });
  },

  fitTrackToScene(root) {
    root.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(root);
    const size = box.getSize(new THREE.Vector3());
    const maxXZ = Math.max(size.x, size.z, 0.001);
    const target = 22;
    const s = target / maxXZ;
    root.scale.setScalar(s);
    root.updateMatrixWorld(true);
    const b2 = new THREE.Box3().setFromObject(root);
    const c = b2.getCenter(new THREE.Vector3());
    root.position.x -= c.x;
    root.position.z -= c.z;
    root.updateMatrixWorld(true);
    const b3 = new THREE.Box3().setFromObject(root);
    root.position.y = -1.2 - b3.min.y;
  },

  captureRaceLights(root) {
    const out = [];
    root.traverse((obj) => {
      if (!obj?.isMesh || typeof obj.name !== "string") return;
      const match = obj.name.match(/^light_(\d+)_(\d+)$/);
      if (!match) return;
      const worldCenter = this.meshWorldCenter(obj);
      const sourceMat = Array.isArray(obj.material) ? obj.material[0] : obj.material;
      const clonedMat = sourceMat?.clone ? sourceMat.clone() : sourceMat;
      if (Array.isArray(obj.material)) {
        obj.material = [clonedMat];
      } else {
        obj.material = clonedMat;
      }
      const row = Number(match[1]);
      const col = Number(match[2]);
      const mat = Array.isArray(obj.material) ? obj.material[0] : obj.material;
      out.push({
        mesh: obj,
        row,
        col,
        center: worldCenter,
        baseColor: mat?.color?.clone?.() || new THREE.Color(0x666666),
        baseEmissive: mat?.emissive?.clone?.() || new THREE.Color(0x000000),
      });
    });
    out.sort((a, b) => a.col - b.col || a.row - b.row);
    this.raceLights = out;
    this.setAllRaceLightsOff();
  },

  meshWorldCenter(mesh) {
    if (!mesh?.geometry) {
      return mesh?.getWorldPosition(new THREE.Vector3()) || new THREE.Vector3();
    }
    if (!mesh.geometry.boundingBox) {
      mesh.geometry.computeBoundingBox();
    }
    const localCenter = new THREE.Vector3();
    mesh.geometry.boundingBox.getCenter(localCenter);
    return mesh.localToWorld(localCenter);
  },

  configureStageAnchors() {
    if (!this.trackRoot) return;
    this.trackRoot.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(this.trackRoot);
    const stageCenter = box.getCenter(new THREE.Vector3());

    if (this.raceLights.length === 0) {
      this.introLookAt.set(stageCenter.x, stageCenter.y, stageCenter.z);
      this.marbleLookAt.copy(this.introLookAt);
      return;
    }

    const avgLight = new THREE.Vector3();
    this.raceLights.forEach((l) => avgLight.add(l.center));
    avgLight.multiplyScalar(1 / this.raceLights.length);

    const minRow = this.raceLights.reduce((acc, l) => Math.min(acc, l.row), Infinity);
    const startRowLights = this.raceLights.filter((l) => l.row === minRow);
    const startLine = new THREE.Vector3();
    startRowLights.forEach((l) => startLine.add(l.center));
    startLine.multiplyScalar(1 / Math.max(1, startRowLights.length));
    this.startLinePoint = startLine.clone();

    const farZ =
      Math.abs(box.min.z - startLine.z) > Math.abs(box.max.z - startLine.z) ? box.min.z : box.max.z;
    const tunnelDir = new THREE.Vector3(0, 0, Math.sign(farZ - startLine.z) || -1);
    const cameraDir = tunnelDir.clone().multiplyScalar(-1);

    this.introLookAt.copy(startLine).add(new THREE.Vector3(0, 0.25, 0));
    this.introTo.copy(startLine).addScaledVector(cameraDir, 2.6);
    this.introTo.y = startLine.y + 1.22;
    this.introFrom.set(this.introTo.x, this.introTo.y + 20.5, this.introTo.z);

    this.marbleLookAt.copy(startLine).addScaledVector(tunnelDir, 1.1);
    this.driftFrom.copy(this.introTo);
    this.driftTo
      .copy(this.introTo)
      .addScaledVector(cameraDir, 0.72)
      .add(new THREE.Vector3(0, -2, 0));
    this.finalCameraPosition.copy(this.driftTo);

    const tunnelDepth = Math.max(1.0, Math.abs(farZ - startLine.z));
    const spawnDistance = Math.max(1.8, tunnelDepth * 0.78);
    const rollY = startLine.y - 0.9;
    this.trackRollY = rollY;
    this.marbleSpawnPoint = startLine
      .clone()
      .addScaledVector(tunnelDir, spawnDistance)
      .setY(rollY + 0.04);
    this.raceLightFocus = avgLight.clone();
  },

  setRaceLightState(light, color, emissiveIntensity = 0.6) {
    const mat = Array.isArray(light.mesh.material) ? light.mesh.material[0] : light.mesh.material;
    if (!mat) return;
    if (mat.color) mat.color.copy(color);
    if (mat.emissive) mat.emissive.copy(color);
    mat.emissiveIntensity = emissiveIntensity;
    mat.needsUpdate = true;
  },

  setAllRaceLightsOff() {
    this.raceLights.forEach((light) => {
      this.setRaceLightState(light, LIGHT_OFF_COLOR, 0.05);
    });
  },

  registerTimer(timerId) {
    this.activeTimers.push(timerId);
  },

  beginLightsSequence() {
    if (!this.currentPayload || this.stage === "done") return;
    this.stage = "lights";
    this.pushEvent("gacha_animation_progress", {
      phase: "lights",
      index: 0,
      total: this.results.length,
    });

    const seq = this.sequenceId;
    this.playRaceLightAnimation(maxRarityInResults(this.results), seq)
      .then((ok) => {
        if (!ok || seq !== this.sequenceId || this.stage === "done") return;
        this.beginMarbleCameraPan();
      })
      .catch(() => {
        if (seq !== this.sequenceId || this.stage === "done") return;
        this.beginMarbleCameraPan();
      });
  },

  async playRaceLightAnimation(highestRarity, seq) {
    const stale = () => seq !== this.sequenceId || this.stage === "done";
    if (stale()) return false;
    const strategy = this.getLightAnimationStrategy(highestRarity);
    return strategy(stale);
  },

  getLightAnimationStrategy(highestRarity) {
    const strategies = {
      1: (stale) => this.playBasicRaceLightAnimation(stale),
      2: (stale) => this.playSpiralRaceLightAnimation(stale),
      3: (stale) => this.playChaosGoldRaceLightAnimation(stale),
    };
    return strategies[Math.min(3, Math.max(1, highestRarity))] || strategies[1];
  },

  getRaceLightGridBounds() {
    if (!this.raceLights.length) return null;
    const rows = this.raceLights.map((l) => l.row);
    const cols = this.raceLights.map((l) => l.col);
    return {
      minRow: Math.min(...rows),
      maxRow: Math.max(...rows),
      minCol: Math.min(...cols),
      maxCol: Math.max(...cols),
    };
  },

  spiralCoords(minRow, maxRow, minCol, maxCol) {
    const out = [];
    let top = minRow;
    let bottom = maxRow;
    let left = minCol;
    let right = maxCol;
    while (top <= bottom && left <= right) {
      for (let c = left; c <= right; c += 1) out.push([top, c]);
      top += 1;
      for (let r = top; r <= bottom; r += 1) out.push([r, right]);
      right -= 1;
      if (top <= bottom) {
        for (let c = right; c >= left; c -= 1) out.push([bottom, c]);
        bottom -= 1;
      }
      if (left <= right) {
        for (let r = bottom; r >= top; r -= 1) out.push([r, left]);
        left += 1;
      }
    }
    return out;
  },

  async playBasicRaceLightAnimation(isStale) {
    if (!this.raceLights.length) {
      return waitMs(380, (id) => this.registerTimer(id), isStale);
    }

    this.setAllRaceLightsOff();
    const cols = [...new Set(this.raceLights.map((l) => l.col))].sort((a, b) => a - b);

    for (const col of cols) {
      if (isStale()) return false;
      this.raceLights
        .filter((l) => l.col === col)
        .forEach((light) => this.setRaceLightState(light, LIGHT_RED_COLOR, 0.75));
      const ok = await waitMs(290, (id) => this.registerTimer(id), isStale);
      if (!ok) return false;
    }

    if (!(await waitMs(260, (id) => this.registerTimer(id), isStale))) return false;
    this.raceLights.forEach((light) => this.setRaceLightState(light, LIGHT_GREEN_COLOR, 1.05));
    if (!(await waitMs(420, (id) => this.registerTimer(id), isStale))) return false;
    return true;
  },

  async playSpiralRaceLightAnimation(isStale) {
    if (!this.raceLights.length) {
      return waitMs(380, (id) => this.registerTimer(id), isStale);
    }
    this.setAllRaceLightsOff();
    const bounds = this.getRaceLightGridBounds();
    if (!bounds) return false;

    const baseOrder = this.spiralCoords(
      bounds.minRow,
      bounds.maxRow,
      bounds.minCol,
      bounds.maxCol,
    );
    const reverse = this.sequenceId % 2 === 1;
    const order = reverse ? [...baseOrder].reverse() : baseOrder;

    for (const [row, col] of order) {
      if (isStale()) return false;
      const target = this.raceLights.find((l) => l.row === row && l.col === col);
      if (target) this.setRaceLightState(target, LIGHT_RED_COLOR, 0.86);
      const ok = await waitMs(175, (id) => this.registerTimer(id), isStale);
      if (!ok) return false;
    }

    if (!(await waitMs(180, (id) => this.registerTimer(id), isStale))) return false;
    this.raceLights.forEach((light) => this.setRaceLightState(light, LIGHT_GREEN_COLOR, 1.06));
    if (!(await waitMs(360, (id) => this.registerTimer(id), isStale))) return false;
    return true;
  },

  async playChaosGoldRaceLightAnimation(isStale) {
    if (!this.raceLights.length) {
      return waitMs(380, (id) => this.registerTimer(id), isStale);
    }
    this.setAllRaceLightsOff();
    const rand = seededRandom((this.sequenceId + 1) * 1337 + this.results.length * 17);
    const order = [...this.raceLights]
      .map((l, idx) => ({ l, idx, r: rand() }))
      .sort((a, b) => a.r - b.r)
      .map((x) => x.l);

    for (let i = 0; i < order.length; i += 1) {
      if (isStale()) return false;
      const light = order[i];
      const crashTone = rand() > 0.55 ? LIGHT_RED_COLOR : LIGHT_WARNING_COLOR;
      this.setRaceLightState(light, crashTone, 0.9 + rand() * 0.35);

      if (i > 1 && i % 3 === 0) {
        const pulseLight = order[Math.floor(rand() * i)];
        this.setRaceLightState(pulseLight, LIGHT_RED_COLOR, 0.45);
      }
      const ok = await waitMs(110 + Math.floor(rand() * 70), (id) => this.registerTimer(id), isStale);
      if (!ok) return false;
    }

    for (let pass = 0; pass < 6; pass += 1) {
      if (isStale()) return false;
      const chaotic = order.filter((_l, idx) => (idx + pass) % 2 === 0);
      chaotic.forEach((l) =>
        this.setRaceLightState(l, pass % 2 === 0 ? LIGHT_WARNING_COLOR : LIGHT_RED_COLOR, 1.12),
      );
      const reverse = order.filter((_l, idx) => (idx + pass) % 2 !== 0);
      reverse.forEach((l) =>
        this.setRaceLightState(l, pass % 2 === 0 ? LIGHT_RED_COLOR : LIGHT_WARNING_COLOR, 0.78),
      );
      if (!(await waitMs(130, (id) => this.registerTimer(id), isStale))) return false;
    }

    if (!(await waitMs(1120, (id) => this.registerTimer(id), isStale))) return false;
    order.forEach((l) => this.setRaceLightState(l, LIGHT_OFF_COLOR, 0.06));
    if (!(await waitMs(120, (id) => this.registerTimer(id), isStale))) return false;

    order.forEach((l) => this.setRaceLightState(l, LIGHT_GOLD_COLOR, 1.2));
    if (!(await waitMs(620, (id) => this.registerTimer(id), isStale))) return false;
    return true;
  },

  beginMarbleCameraPan() {
    if (!this.currentPayload || this.stage === "done") return;
    this.stage = "marble_camera";
    this.pushEvent("gacha_animation_progress", {
      phase: "marble_camera",
      index: 0,
      total: this.results.length,
    });
    this.introSegment = "marble_pan";
    this.introStartedAt = performance.now();
    this.introActive = true;
    this.driftFrom.copy(this.camera.position);
  },

  runReveal() {
    this.stage = "reveal";
    this.revealPaused = false;
    this.hideRevealOverlay();
    this.hideLegendaryOverlay();
    this.pushEvent("gacha_animation_progress", {
      phase: "reveal",
      index: 0,
      total: this.results.length,
    });
    if (this.results.length === 0) {
      this.complete();
      return;
    }
    this.currentIndex = 0;
    this.showMarble(this.results[0], 0);
  },

  async showMarble(entry, _resultIndex) {
    if (!this.webglReady) return;

    this.revealPaused = false;
    this.hideRevealOverlay();
    this.hideLegendaryOverlay();
    this.currentRevealEntry = entry;

    const seq = this.sequenceId;
    const introOk = await this.playThreeStarPreIntro(entry, seq);
    if (!introOk || seq !== this.sequenceId || this.stage === "done") return;

    this.disposeObject3D(this.marbleRoot, { keepTextures: true });
    this.marbleRoot = null;
    this.marbleMotion = null;

    const radius = GACHA_MARBLE_RADIUS;
    const url = canonicalTextureUrl(textureUrlFromResult(entry));
    const cached = url && this.textureCache.get(url);

    let material;
    if (cached) {
      material = buildMarbleMaterial(cached, url, this.mappedTextureCache);
    } else {
      material = new THREE.MeshStandardMaterial({
        color: rarityColor(entry.rarity || 1),
        metalness: 0.5,
        roughness: 0.35,
        emissive: rarityColor(entry.rarity || 1),
        emissiveIntensity: 0.14,
      });
    }

    const mesh = new THREE.Mesh(new THREE.SphereGeometry(radius, 40, 40), material);

    if (url && !cached) {
      this.textureLoader.load(
        url,
        (loaded) => {
          if (this.marbleRoot !== mesh) {
            loaded.dispose();
            return;
          }
          applyMarbleTextureSettings(loaded);
          this.textureCache.set(url, loaded);
          const prev = mesh.material;
          mesh.material = buildMarbleMaterial(loaded, url, this.mappedTextureCache);
          if (prev && typeof prev.dispose === "function") {
            prev.dispose();
          }
        },
        undefined,
        () => {},
      );
    }

    this.scene.add(mesh);
    this.marbleRoot = mesh;
    this.startMarbleMotion(mesh, entry);
  },

  async playThreeStarPreIntro(entry, seq) {
    const rarity = Number(entry?.rarity) || 1;
    if (rarity < 3) return true;
    const stale = () => seq !== this.sequenceId || this.stage === "done";
    if (stale()) return false;

    this.ensureLegendaryOverlay();
    const overlay = this.legendaryOverlayEl;
    const logo = this.legendaryLogoEl;
    const flicker = this.legendaryFlickerEl;
    const stars = this.legendaryStarsEl;
    if (!overlay || !flicker || !stars) return true;

    const teamLogo = entry?.team_logo_url || entry?.teamLogoUrl || null;
    if (logo) {
      if (teamLogo) {
        logo.src = teamLogo;
        logo.classList.remove("hidden");
      } else {
        logo.removeAttribute("src");
        logo.classList.add("hidden");
      }
    }

    overlay.classList.remove("opacity-0");
    flicker.style.animation = "none";
    flicker.style.opacity = "0";
    stars.style.animation = "none";
    stars.style.opacity = "0";
    void overlay.offsetWidth;
    flicker.style.animation = "gacha-legendary-flicker 680ms steps(1,end) 2";
    if (!(await waitMs(290, (id) => this.registerTimer(id), stale))) return false;
    flicker.style.animation = "none";
    flicker.style.opacity = "1";
    if (!(await waitMs(280, (id) => this.registerTimer(id), stale))) return false;
    stars.style.animation = "gacha-legendary-stars 620ms cubic-bezier(0.22, 1, 0.36, 1) both";
    if (!(await waitMs(1110, (id) => this.registerTimer(id), stale))) return false;
    overlay.classList.add("opacity-0");
    flicker.style.opacity = "0";
    if (!(await waitMs(120, (id) => this.registerTimer(id), stale))) return false;
    return true;
  },

  startMarbleMotion(root, entry) {
    const radius = GACHA_MARBLE_RADIUS;
    const rollY = Number.isFinite(this.trackRollY) ? this.trackRollY : this.introLookAt.y + radius * 0.9;
    const spawn =
      this.marbleSpawnPoint?.clone() ||
      new THREE.Vector3(this.introLookAt.x + 3, rollY + 0.04, this.introLookAt.z - 9);
    const end =
      this.startLinePoint?.clone().setY(rollY) ||
      new THREE.Vector3(this.introLookAt.x, rollY, this.introLookAt.z);

    root.position.copy(spawn);
    const rarity = Number(entry?.rarity) || 1;
    const duration = Math.max(290, 390 - rarity * 22);
    this.marbleMotion = {
      spawn,
      end,
      t0: performance.now(),
      duration,
      crossAt: 0.78,
      crossed: false,
      freezeUntil: 0,
      spinStep: 0.24,
    };
  },

  disposeObject3D(obj, opts = {}) {
    if (!obj) return;
    const keepTextures = opts.keepTextures === true;
    if (this.scene) {
      this.scene.remove(obj);
    }
    obj.traverse((child) => {
      if (child.isMesh) {
        child.geometry?.dispose?.();
        const mat = child.material;
        if (Array.isArray(mat)) {
          mat.forEach((m) => {
            if (keepTextures) {
              clearMaterialTextureRefs(m);
            } else {
              m.map?.dispose?.();
            }
            m?.dispose?.();
          });
        } else {
          if (keepTextures) {
            clearMaterialTextureRefs(mat);
          } else {
            mat.map?.dispose?.();
          }
          mat?.dispose?.();
        }
      }
    });
  },

  finishEarly() {
    if (!this.currentPayload) return;

    this.preloadGen += 1;
    this.sequenceId += 1;
    this.clearTimers();
    this.disposeCinematicResources();
    this.complete();
  },

  complete() {
    this.introActive = false;
    this.introSegment = null;
    this.stage = "done";
    this.revealPaused = false;
    this.setAllRaceLightsOff();
    this.hideRevealOverlay(true);
    this.hideLegendaryOverlay(true);
    this.pushEvent("gacha_animation_done", {});
  },

  clearTimers() {
    this.activeTimers.forEach((timerId) => {
      window.clearTimeout(timerId);
      window.clearInterval(timerId);
    });
    this.activeTimers = [];
  },

  resizeRenderer() {
    if (!this.renderer || !this.camera) return;

    const width = Math.max(this.el.clientWidth, 1);
    const height = Math.max(this.el.clientHeight, 1);

    this.renderer.setSize(width, height);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  },
};

export { GachaPage, GachaCinematic };
