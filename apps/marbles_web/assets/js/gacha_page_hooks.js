import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

const GACHA_SKIP_CONFIRM_KEY = "gachaSkipConfirm";

const TRACK_GLB_URL = "/3d/tracks/savage_speedway_s1.glb";

/** Textured sphere radius (matches dev sandbox style: native sphere + map). */
const GACHA_MARBLE_RADIUS = 0.52;

const rarityColor = (rarity) => {
  if (rarity >= 3) return 0xffc857;
  if (rarity === 2) return 0x8fd3ff;
  return 0xd1d5db;
};

const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

const easeInOutQuad = (t) =>
  t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;

const textureUrlFromResult = (entry) =>
  entry?.texture_url || entry?.textureUrl || null;

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

const trackSpawnTopLeftWorld = (trackRoot, radius) => {
  trackRoot.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(trackRoot);
  const margin = radius * 2.2;
  const x = box.min.x + margin;
  const z = box.max.z - margin;
  const y = box.max.y + radius * 6 + 0.08;
  return { x, y, z };
};

const trackRevealRestPoint = (trackRoot, radius) => {
  trackRoot.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(trackRoot);
  const c = box.getCenter(new THREE.Vector3());
  const y = Math.max(-0.35, box.min.y + radius * 2.2);
  return new THREE.Vector3(c.x, y, c.z);
};

const GachaPage = {
  mounted() {
    const saved =
      window.localStorage.getItem(GACHA_SKIP_CONFIRM_KEY) === "true";
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
    this.revealPaused = false;
    this.revealOverlayEl = null;
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
    this.introFrom = new THREE.Vector3(0, 26, 0.35);
    this.introTo = new THREE.Vector3(0, 2.2, 6);
    this.driftDelta = new THREE.Vector3(-2.35, 0, 0.65);
    this.driftFrom = new THREE.Vector3();
    this.driftTo = new THREE.Vector3();
    this.finalCameraPosition = new THREE.Vector3();
    this.introLookAt = new THREE.Vector3(0, 0, 0);
    this.trackRoot = null;
    this.marbleRoot = null;
    this.marbleMotion = null;
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
      @keyframes gacha-reveal-glow {
        0%, 100% { text-shadow: 0 0 8px rgba(255,255,255,0.35), 0 0 24px rgba(99,102,241,0.45); }
        50% { text-shadow: 0 0 16px rgba(255,255,255,0.55), 0 0 40px rgba(99,102,241,0.65); }
      }
      @keyframes gacha-reveal-shimmer {
        0% { transform: translateX(-100%); opacity: 0; }
        20% { opacity: 0.9; }
        100% { transform: translateX(200%); opacity: 0; }
      }
    `;
    this.el.appendChild(style);
  },

  ensureRevealOverlay() {
    if (this.revealOverlayEl) return;
    const wrap = document.createElement("div");
    wrap.dataset.gachaRevealOverlay = "";
    wrap.className =
      "pointer-events-none absolute inset-0 z-20 flex flex-col items-center justify-center gap-3 p-6 opacity-0 transition-opacity duration-500 bg-transparent";
    wrap.innerHTML = `
      <div class="relative max-w-lg text-center">
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
    this.revealNameEl = wrap.querySelector("[data-gacha-reveal-name]");
    this.revealRarityEl = wrap.querySelector("[data-gacha-reveal-rarity]");
  },

  hideRevealOverlay(forceRemove = false) {
    this.revealPaused = false;
    if (!this.revealOverlayEl) return;
    this.revealOverlayEl.classList.add("pointer-events-none", "opacity-0");
    this.revealOverlayEl.classList.remove(
      "pointer-events-auto",
      "cursor-pointer",
    );
    if (forceRemove) {
      this.revealOverlayEl.remove();
      this.revealOverlayEl = null;
      this.revealNameEl = null;
      this.revealRarityEl = null;
    }
  },

  rarityLabelClass(rarity) {
    const r = Number(rarity) || 1;
    if (r >= 3)
      return "text-amber-300 drop-shadow-[0_0_12px_rgba(251,191,36,0.55)]";
    if (r === 2)
      return "text-sky-300 drop-shadow-[0_0_12px_rgba(125,211,252,0.5)]";
    return "text-slate-200 drop-shadow-[0_0_8px_rgba(255,255,255,0.25)]";
  },

  showRevealOverlay(entry) {
    this.ensureRevealOverlay();
    const name = entry?.name || "Marble";
    const rarity = Number(entry?.rarity) || 1;
    const stars = "★".repeat(Math.min(5, Math.max(1, rarity)));
    this.revealNameEl.textContent = name;
    this.revealRarityEl.textContent = `${stars}  Rarity ${rarity}`;
    this.revealRarityEl.className = `relative mt-2 text-lg font-semibold tracking-wide sm:text-xl ${this.rarityLabelClass(rarity)}`;
    const ra = this.revealRarityEl;
    ra.style.animation = "none";
    void ra.offsetWidth;
    ra.style.animation =
      "gacha-reveal-pop 0.72s cubic-bezier(0.22, 1, 0.36, 1) 0.08s both";
    const nm = this.revealNameEl;
    nm.style.animation = "none";
    void nm.offsetWidth;
    nm.style.animation =
      "gacha-reveal-pop 0.65s cubic-bezier(0.22, 1, 0.36, 1) both, gacha-reveal-glow 2.4s ease-in-out infinite";
    this.revealOverlayEl.classList.remove("pointer-events-none", "opacity-0");
    this.revealOverlayEl.classList.add("pointer-events-auto", "cursor-pointer");
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
      const t = Math.min(
        1,
        (performance.now() - this.marbleMotion.t0) / this.marbleMotion.duration,
      );
      const e = 1 - (1 - t) * (1 - t);
      this.marbleRoot.position.lerpVectors(
        this.marbleMotion.spawn,
        this.marbleMotion.rest,
        e,
      );
      this.marbleRoot.position.y += 0.22 * Math.sin(t * Math.PI);
      this.marbleRoot.rotation.z = 0.42 * Math.sin(t * Math.PI * 1.5);
      this.marbleRoot.rotation.y += 0.055;
      if (t >= 1) {
        this.marbleRoot.position.copy(this.marbleMotion.rest);
        this.marbleRoot.rotation.set(0, 0, 0);
        this.marbleMotion = null;
        this.revealPaused = true;
        this.showRevealOverlay(this.currentRevealEntry);
      }
    } else if (this.marbleRoot && !this.introActive && !this.revealPaused) {
      this.marbleRoot.rotation.y += 0.018;
      this.marbleRoot.rotation.x += 0.008;
    }

    if (this.renderer) {
      this.renderer.render(this.scene, this.camera);
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
        this.introSegment = "drift";
        this.introStartedAt = now;
        this.driftFrom.copy(this.camera.position);
        this.driftTo.copy(this.introTo).add(this.driftDelta);
        this.pushEvent("gacha_animation_progress", {
          phase: "intro_drift",
          index: 0,
          total: this.results.length,
        });
      }
    } else if (this.introSegment === "drift") {
      const elapsed = now - this.introStartedAt;
      const u = Math.min(1, elapsed / this.introDriftMs);
      const e = easeInOutQuad(u);
      this.camera.position.lerpVectors(this.driftFrom, this.driftTo, e);
      this.camera.lookAt(this.introLookAt);
      if (u >= 1) {
        this.finalCameraPosition.copy(this.camera.position);
        this.introSegment = null;
        this.introActive = false;
        this.beginCountdown();
      }
    }
  },

  start(payload) {
    this.clearTimers();
    this.preloadGen += 1;
    const gen = this.preloadGen;
    this.introActive = false;
    this.introSegment = null;
    this.marbleMotion = null;
    this.revealPaused = false;
    this.hideRevealOverlay(true);
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

    this.finalCameraPosition.copy(this.introTo).add(this.driftDelta);

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
      ...new Set(
        results
          .map((r) => canonicalTextureUrl(textureUrlFromResult(r)))
          .filter(Boolean),
      ),
    ];
    await Promise.all(urls.map((u) => this.ensureTextureCached(u, gen)));
  },

  loadTrackGltfPromise(gen) {
    return new Promise((resolve, reject) => {
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
          const box = new THREE.Box3().setFromObject(root);
          const c = box.getCenter(new THREE.Vector3());
          this.introLookAt.set(c.x, Math.min(c.y + 0.4, 1.2), c.z);
          resolve();
        },
        undefined,
        () => {
          if (gen === this.preloadGen) {
            this.introLookAt.set(0, 0, 0);
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
          this.configureMarbleTexture(tex);
          this.textureCache.set(key, tex);
          resolve();
        },
        undefined,
        () => resolve(),
      );
    });
  },

  configureMarbleTexture(tex) {
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.flipY = true;
    tex.wrapS = THREE.ClampToEdgeWrapping;
    tex.wrapT = THREE.ClampToEdgeWrapping;
    tex.minFilter = THREE.LinearMipmapLinearFilter;
    tex.magFilter = THREE.LinearFilter;
    tex.generateMipmaps = true;
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

  beginCountdown() {
    if (!this.currentPayload || this.stage === "done") return;
    this.stage = "countdown";
    this.pushEvent("gacha_animation_progress", {
      phase: "countdown",
      index: 0,
      total: this.results.length,
    });

    const countdownTimer = window.setTimeout(() => {
      this.runReveal();
    }, 900);

    this.activeTimers.push(countdownTimer);
  },

  runReveal() {
    this.stage = "reveal";
    this.revealPaused = false;
    this.hideRevealOverlay();
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

  showMarble(entry, _resultIndex) {
    if (!this.webglReady) return;

    this.revealPaused = false;
    this.hideRevealOverlay();
    this.currentRevealEntry = entry;

    this.disposeObject3D(this.marbleRoot, { keepTextures: true });
    this.marbleRoot = null;
    this.marbleMotion = null;

    const radius = GACHA_MARBLE_RADIUS;
    const url = canonicalTextureUrl(textureUrlFromResult(entry));
    const cached = url && this.textureCache.get(url);

    let material;
    if (cached) {
      material = new THREE.MeshBasicMaterial({
        map: cached,
        color: 0xffffff,
      });
    } else {
      material = new THREE.MeshStandardMaterial({
        color: rarityColor(entry.rarity || 1),
        metalness: 0.5,
        roughness: 0.35,
        emissive: rarityColor(entry.rarity || 1),
        emissiveIntensity: 0.14,
      });
    }

    const mesh = new THREE.Mesh(
      new THREE.SphereGeometry(radius, 40, 40),
      material,
    );

    if (url && !cached) {
      this.textureLoader.load(
        url,
        (loaded) => {
          this.configureMarbleTexture(loaded);
          this.textureCache.set(url, loaded);
          if (this.marbleRoot !== mesh) {
            loaded.dispose();
            return;
          }
          const prev = mesh.material;
          mesh.material = new THREE.MeshBasicMaterial({
            map: loaded,
            color: 0xffffff,
          });
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
    this.startMarbleMotion(mesh);
  },

  startMarbleMotion(root) {
    const radius = GACHA_MARBLE_RADIUS;
    let spawn;
    let rest;
    if (this.trackRoot) {
      const a = trackSpawnTopLeftWorld(this.trackRoot, radius);
      spawn = new THREE.Vector3(a.x, a.y, a.z);
      rest = trackRevealRestPoint(this.trackRoot, radius);
    } else {
      spawn = new THREE.Vector3(4.1, 1.55, -2.35);
      rest = new THREE.Vector3(0, 0.28, 0);
    }
    root.position.copy(spawn);
    this.marbleMotion = { spawn, rest, t0: performance.now(), duration: 560 };
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
    this.clearTimers();
    this.disposeCinematicResources();
    this.complete();
  },

  complete() {
    this.introActive = false;
    this.introSegment = null;
    this.stage = "done";
    this.revealPaused = false;
    this.hideRevealOverlay(true);
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
