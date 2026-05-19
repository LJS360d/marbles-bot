import gsap from "gsap";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import {
  TRACK_GLB_URL,
  GACHA_MARBLE_RADIUS,
  rarityColor,
  LIGHT_OFF_COLOR,
  maxRarityInResults,
  textureUrlFromResult,
  canonicalTextureUrl,
  clearMaterialTextureRefs,
  applyMarbleTextureSettings,
  buildMarbleMaterial,
} from "./gacha_cinematic_shared.js";
import { buildRaceLightsTimeline } from "./gacha_cinematic_race_lights.js";

const {
  Scene,
  Color,
  PerspectiveCamera,
  AmbientLight,
  DirectionalLight,
  Mesh,
  PlaneGeometry,
  MeshStandardMaterial,
  GridHelper,
  SphereGeometry,
  Vector3,
  Box3,
  TextureLoader,
  WebGLRenderer,
  SRGBColorSpace,
} = THREE;

/** Normalized distance along roll for constant-acceleration-from-rest (s ∝ t²). */
const distanceRatioAccel = (t) => {
  const u = Math.min(1, Math.max(0, t));
  return u * u;
};

/**
 * GSAP gacha cinematic (WebGLRenderer). Race lights timeline lives in a small module.
 */
const GachaCinematic = {
  mounted() {
    this.webglReady = false;
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
    this.marbleRollProxy = null;
    this.sequenceTimeline = null;
    this.resizeHandler = () => this.resizeRenderer();
    this._onRevealAdvance = (e) => {
      if (this.stage !== "reveal" || !this.revealPaused) return;
      e.preventDefault();
      e.stopPropagation();
      this.advanceRevealFromUser();
    };
    this._onRevealAdvanceKey = (e) => {
      if (e.code !== "Space" && e.key !== " ") return;
      if (this.stage !== "reveal" || !this.revealPaused) return;
      e.preventDefault();
      e.stopPropagation();
      this.advanceRevealFromUser();
    };
    this.introDurationMs = 2400;
    this.trackPanMs = 900;
    this.lightsCameraPos = new Vector3();
    this.lightsCameraLookAt = new Vector3();
    this.trackCameraPos = new Vector3();
    this.trackCameraLookAt = new Vector3();
    this.introFrom = new Vector3(0, 26, 0.35);
    this.introTo = new Vector3(0, 2.2, 6);
    this.driftFrom = new Vector3();
    this.driftTo = new Vector3();
    this.finalCameraPosition = new Vector3();
    this.introLookAt = new Vector3(0, 0, 0);
    this.marbleLookAt = new Vector3(0, 0, 0);
    this.trackRoot = null;
    this.marbleRoot = null;
    this.raceLights = [];
    this.raceLightFocus = null;
    this.marbleSpawnPoint = null;
    this.startLinePoint = null;
    this.trackRollY = null;
    this.sequenceId = 0;
    this.gltfLoader = new GLTFLoader();
    this.textureLoader = new TextureLoader();
    this.gltfLoader.setCrossOrigin("anonymous");
    this.textureLoader.setCrossOrigin("anonymous");

    this.setupScene();
    this.ensureRevealStyles();
    this.el.addEventListener("click", this._onRevealAdvance);
    window.addEventListener("keydown", this._onRevealAdvanceKey);
    window.addEventListener("resize", this.resizeHandler);
    this.initRenderer();

    this.handleEvent("gacha_animation_start", (payload) => {
      this.startWhenReady(payload);
    });
    this.handleEvent("gacha_animation_skip", () => {
      this.finishEarly();
    });
  },

  destroyed() {
    this.preloadGen += 1;
    this.killSequenceTimeline();
    this.disposeCinematicResources();
    window.removeEventListener("resize", this.resizeHandler);
    window.removeEventListener("keydown", this._onRevealAdvanceKey);
    this.el.removeEventListener("click", this._onRevealAdvance);
  },

  lightCtx() {
    return {
      getRaceLights: () => this.raceLights,
      getSequenceId: () => this.sequenceId,
      getResults: () => this.results,
      setRaceLightState: (l, c, i) => this.setRaceLightState(l, c, i),
      setAllRaceLightsOff: () => this.setAllRaceLightsOff(),
    };
  },

  initRenderer() {
    if (this.renderer) return;
    try {
      const renderer = new WebGLRenderer({
        antialias: true,
        powerPreference: "high-performance",
        alpha: false,
      });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      renderer.outputColorSpace = SRGBColorSpace;
      this.resizeRendererWith(renderer);
      const canvas = renderer.domElement;
      canvas.style.display = "block";
      canvas.style.width = "100%";
      canvas.style.height = "100%";
      this.el.appendChild(canvas);
      this.renderer = renderer;
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
    if (this.marbleRoot && this.revealPaused) {
      this.marbleRoot.rotation.y += 0.024;
      this.marbleRoot.rotation.x = 0;
      this.marbleRoot.rotation.z = 0;
    }
    this.renderer.render(this.scene, this.camera);
    if (this.revealPaused) this.updateRevealOverlayPosition();
  },

  startWhenReady(payload) {
    if (!this.scene || !this.camera) this.setupScene();
    if (!this.renderer) this.initRenderer();
    this.start(payload);
  },

  killSequenceTimeline() {
    if (this.sequenceTimeline) {
      this.sequenceTimeline.kill();
      this.sequenceTimeline = null;
    }
    if (this.camera) gsap.killTweensOf(this.camera.position);
    if (this.marbleRollProxy) gsap.killTweensOf(this.marbleRollProxy);
    this.marbleRollProxy = null;
    if (this.marbleRoot) gsap.killTweensOf(this.marbleRoot.position);
    const legendEls = [this.legendaryOverlayEl, this.legendaryFlickerEl, this.legendaryStarsEl].filter(
      Boolean,
    );
    if (legendEls.length) gsap.killTweensOf(legendEls);
  },

  disposeCinematicResources() {
    this.killSequenceTimeline();
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
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) {
        const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
        mats.forEach((m) => {
          if (m?.map) m.map.dispose();
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
      el.innerHTML = `<div class="h-12 w-12 rounded-full border-2 border-white/20 border-t-white animate-spin" aria-hidden="true"></div>`;
      this.el.appendChild(el);
    }
    return el;
  },

  showLoadingOverlay() {
    this.ensureLoadingOverlay().classList.remove("hidden");
  },

  hideLoadingOverlay(forceRemove = false) {
    const el = this.el.querySelector("[data-gacha-cinematic-loading]");
    if (!el) return;
    if (forceRemove) el.remove();
    else el.classList.add("hidden");
  },

  disposeTextureCache() {
    if (!this.textureCache) return;
    for (const tex of this.textureCache.values()) tex.dispose();
    this.textureCache.clear();
    if (this.mappedTextureCache) {
      for (const tex of this.mappedTextureCache.values()) tex.dispose();
      this.mappedTextureCache.clear();
    }
  },

  ensureRevealStyles() {
    if (this.el.querySelector("[data-gacha-reveal-styles]")) return;
    const style = document.createElement("style");
    style.dataset.gachaRevealStyles = "";
    style.textContent = `
      @keyframes gacha-reveal-pop{0%{opacity:0;transform:scale(0.82) translateY(12px);filter:blur(10px)}55%{opacity:1;transform:scale(1.05) translateY(0);filter:blur(0)}100%{opacity:1;transform:scale(1) translateY(0);filter:blur(0)}}
      @keyframes gacha-reveal-flash{0%{opacity:0;transform:scale(0.9)}25%{opacity:0.95;transform:scale(1.12)}100%{opacity:0;transform:scale(1.35)}}
      @keyframes gacha-reveal-glow{0%,100%{text-shadow:0 0 8px rgba(255,255,255,0.35),0 0 24px rgba(99,102,241,0.45)}50%{text-shadow:0 0 16px rgba(255,255,255,0.55),0 0 40px rgba(99,102,241,0.65)}}
      @keyframes gacha-reveal-shimmer{0%{transform:translateX(-100%);opacity:0}20%{opacity:0.9}100%{transform:translateX(200%);opacity:0}}
      @keyframes gacha-legendary-flicker{0%,12%,100%{opacity:0}5%,9%,25%,39%,60%{opacity:0.72}18%,31%,52%,73%{opacity:0.1}}
      @keyframes gacha-legendary-stars{0%{transform:scale(0.4);opacity:0;filter:blur(8px)}60%{transform:scale(1.12);opacity:1;filter:blur(0)}100%{transform:scale(1);opacity:0.95;filter:blur(0)}}
    `;
    this.el.appendChild(style);
  },

  ensureLegendaryOverlay() {
    if (this.legendaryOverlayEl) return;
    const wrap = document.createElement("div");
    wrap.dataset.gachaLegendaryOverlay = "";
    wrap.className = "pointer-events-none absolute inset-0 z-30 opacity-0 transition-opacity duration-150";
    wrap.innerHTML = `<div data-gacha-legendary-flicker class="absolute inset-0 bg-black opacity-0"></div><div class="absolute inset-0 flex flex-col items-center justify-center gap-5 px-6 text-center"><img data-gacha-legendary-logo alt="Team logo" class="hidden h-28 w-28 rounded-full border border-amber-200/60 bg-black/35 p-2 shadow-[0_0_34px_rgba(251,191,36,0.45)]"/><p data-gacha-legendary-stars class="text-5xl font-bold tracking-[0.32em] text-amber-300 drop-shadow-[0_0_20px_rgba(251,191,36,0.8)] opacity-0">★★★</p></div>`;
    this.el.appendChild(wrap);
    this.legendaryOverlayEl = wrap;
    this.legendaryLogoEl = wrap.querySelector("[data-gacha-legendary-logo]");
    this.legendaryFlickerEl = wrap.querySelector("[data-gacha-legendary-flicker]");
    this.legendaryStarsEl = wrap.querySelector("[data-gacha-legendary-stars]");
  },

  hideLegendaryOverlay(forceRemove = false) {
    if (!this.legendaryOverlayEl) return;
    gsap.killTweensOf(
      [this.legendaryOverlayEl, this.legendaryFlickerEl, this.legendaryStarsEl].filter(Boolean),
    );
    if (this.legendaryFlickerEl) {
      this.legendaryFlickerEl.style.animation = "none";
      this.legendaryFlickerEl.style.opacity = "0";
    }
    if (this.legendaryStarsEl) {
      this.legendaryStarsEl.style.animation = "none";
    }
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
    wrap.innerHTML = `<div data-gacha-reveal-card class="pointer-events-none absolute left-1/2 top-1/2 max-w-lg -translate-x-1/2 -translate-y-1/2 text-center"><div data-gacha-reveal-flash class="pointer-events-none absolute inset-0 rounded-full bg-white/40 blur-2xl opacity-0"></div><div class="pointer-events-none absolute inset-x-0 top-1/2 h-px -translate-y-6 overflow-hidden rounded-full opacity-70" aria-hidden="true"><div data-gacha-reveal-shimmer class="h-full w-1/3 bg-gradient-to-r from-transparent via-white/80 to-transparent" style="animation:gacha-reveal-shimmer 2.2s ease-in-out infinite"></div></div><p data-gacha-reveal-name class="relative text-3xl font-bold tracking-tight text-white sm:text-4xl" style="animation:gacha-reveal-pop 0.65s cubic-bezier(0.22,1,0.36,1) both,gacha-reveal-glow 2.4s ease-in-out infinite"></p><p data-gacha-reveal-rarity class="relative mt-2 text-lg font-semibold tracking-wide sm:text-xl"></p></div>`;
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

  advanceRevealFromUser() {
    if (this.stage !== "reveal" || !this.revealPaused) return;
    this.hideRevealOverlay();
    const outgoing = this.marbleRoot;
    if (outgoing && this.scene) {
      this.disposeObject3D(outgoing, { keepTextures: true });
      if (this.marbleRoot === outgoing) this.marbleRoot = null;
    }
    this.revealPaused = false;
    const isLast = this.currentIndex >= this.results.length - 1;
    if (isLast) {
      this.complete();
      return;
    }
    this.showNextMarble();
  },

  showNextMarble() {
    this.currentIndex += 1;
    void this.showMarble(this.results[this.currentIndex], this.currentIndex);
  },

  setupScene() {
    this.scene = new Scene();
    this.scene.background = new Color(0x080b12);
    this.camera = new PerspectiveCamera(
      60,
      this.el.clientWidth / Math.max(this.el.clientHeight, 1),
      0.1,
      200,
    );
    this.camera.position.copy(this.introTo);
    this.camera.lookAt(this.introLookAt);
    this.scene.add(new AmbientLight(0xffffff, 0.55));
    const keyLight = new DirectionalLight(0xffffff, 1.15);
    keyLight.position.set(8, 18, 10);
    this.scene.add(keyLight);
    const rim = new DirectionalLight(0x6b9cff, 0.35);
    rim.position.set(-10, 6, -8);
    this.scene.add(rim);
    const floor = new Mesh(
      new PlaneGeometry(48, 48),
      new MeshStandardMaterial({ color: 0x0b1220, roughness: 0.96, metalness: 0.05 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -1.2;
    this.scene.add(floor);
    const grid = new GridHelper(40, 40, 0x1e293b, 0x0f172a);
    grid.position.y = -1.19;
    this.scene.add(grid);
  },

  start(payload) {
    this.killSequenceTimeline();
    this.preloadGen += 1;
    this.sequenceId += 1;
    const gen = this.preloadGen;
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
    if (!this.webglReady || !this.renderer || !this.scene || !this.camera) {
      this.hideLoadingOverlay();
      this.complete();
      return;
    }
    this.resumeStartAfterRenderer(gen, payload);
  },

  resumeStartAfterRenderer(gen, payload) {
    if (gen !== this.preloadGen || !this.renderer || !this.scene || !this.camera) return;
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
        this.beginSequencedIntro();
      });
  },

  beginSequencedIntro() {
    if (!this.currentPayload || this.stage === "done") return;
    const seq = this.sequenceId;
    this.killSequenceTimeline();
    const stale = () => seq !== this.sequenceId || this.stage === "done";
    const master = gsap.timeline({
      onKill: () => {
        if (this.sequenceTimeline === master) this.sequenceTimeline = null;
      },
    });
    this.sequenceTimeline = master;
    this.stage = "intro";
    this.pushEvent("gacha_animation_progress", { phase: "intro", index: 0, total: this.results.length });
    this.camera.position.copy(this.introFrom);
    this.camera.lookAt(this.lightsCameraLookAt);
    master.to(this.camera.position, {
      x: this.lightsCameraPos.x,
      y: this.lightsCameraPos.y,
      z: this.lightsCameraPos.z,
      duration: this.introDurationMs / 1000,
      ease: "power3.out",
      onUpdate: () => {
        if (!stale()) this.camera.lookAt(this.lightsCameraLookAt);
      },
    });
    master.add(() => {
      if (stale()) return;
      this.finalCameraPosition.copy(this.camera.position);
    });
    master.add(() => {
      if (stale()) return;
      this.stage = "lights";
      this.pushEvent("gacha_animation_progress", { phase: "lights", index: 0, total: this.results.length });
    });
    master.add(buildRaceLightsTimeline(gsap, this.lightCtx(), maxRarityInResults(this.results), stale));
    master.add(() => {
      if (stale()) return;
      this.stage = "marble_camera";
      this.pushEvent("gacha_animation_progress", {
        phase: "marble_camera",
        index: 0,
        total: this.results.length,
      });
    });
    master.to(this.camera.position, {
      x: this.trackCameraPos.x,
      y: this.trackCameraPos.y,
      z: this.trackCameraPos.z,
      duration: this.trackPanMs / 1000,
      ease: "power2.inOut",
      onUpdate: () => {
        if (!stale()) this.camera.lookAt(this.trackCameraLookAt);
      },
    });
    master.add(() => {
      if (stale()) return;
      this.finalCameraPosition.copy(this.camera.position);
      this.runReveal();
    });
  },

  runReveal() {
    this.stage = "reveal";
    this.revealPaused = false;
    this.hideRevealOverlay();
    this.hideLegendaryOverlay();
    this.pushEvent("gacha_animation_progress", { phase: "reveal", index: 0, total: this.results.length });
    if (this.results.length === 0) {
      this.complete();
      return;
    }
    this.currentIndex = 0;
    void this.showMarble(this.results[0], 0);
  },

  async showMarble(entry, _resultIndex) {
    if (!this.webglReady) return;
    this.revealPaused = false;
    this.hideRevealOverlay();
    this.hideLegendaryOverlay();
    this.currentRevealEntry = entry;
    const seq = this.sequenceId;
    const introOk = await this.playLegendaryIntroGsap(entry, seq);
    if (!introOk || seq !== this.sequenceId || this.stage === "done") return;
    this.disposeObject3D(this.marbleRoot, { keepTextures: true });
    this.marbleRoot = null;
    if (this.marbleRollProxy) gsap.killTweensOf(this.marbleRollProxy);
    this.marbleRollProxy = null;

    const radius = GACHA_MARBLE_RADIUS;
    const url = canonicalTextureUrl(textureUrlFromResult(entry));
    const cached = url && this.textureCache.get(url);
    let material;
    if (cached) {
      material = buildMarbleMaterial(cached, url, this.mappedTextureCache);
    } else {
      material = new MeshStandardMaterial({
        color: rarityColor(entry.rarity || 1),
        metalness: 0.5,
        roughness: 0.35,
        emissive: rarityColor(entry.rarity || 1),
        emissiveIntensity: 0.14,
      });
    }
    const mesh = new Mesh(new SphereGeometry(radius, 40, 40), material);
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
          prev?.dispose?.();
        },
        undefined,
        () => {},
      );
    }
    mesh.rotation.order = "YXZ";
    mesh.rotation.x = 0;
    mesh.rotation.z = 0;
    this.scene.add(mesh);
    this.marbleRoot = mesh;
    this.startMarbleMotionGsap(mesh, entry, seq);
  },

  playLegendaryIntroGsap(entry, seq) {
    const rarity = Number(entry?.rarity) || 1;
    if (rarity < 3) return Promise.resolve(true);
    const stale = () => seq !== this.sequenceId || this.stage === "done";
    return (async () => {
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
          logo.src = canonicalTextureUrl(teamLogo) || teamLogo;
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
      if (!(await this.waitRevealMs(290, stale))) return false;
      flicker.style.animation = "none";
      flicker.style.opacity = "1";
      if (!(await this.waitRevealMs(280, stale))) return false;
      stars.style.animation = "gacha-legendary-stars 620ms cubic-bezier(0.22, 1, 0.36, 1) both";
      if (!(await this.waitRevealMs(1110, stale))) return false;
      overlay.classList.add("opacity-0");
      flicker.style.opacity = "0";
      if (!(await this.waitRevealMs(120, stale))) return false;
      return !stale();
    })();
  },

  waitRevealMs(ms, stale) {
    return new Promise((resolve) => {
      if (stale()) {
        resolve(false);
        return;
      }
      window.setTimeout(() => {
        resolve(!stale());
      }, ms);
    });
  },

  startMarbleMotionGsap(mesh, entry, seq) {
    const stale = () => seq !== this.sequenceId || this.stage === "done";
    const radius = GACHA_MARBLE_RADIUS;
    const rollY = Number.isFinite(this.trackRollY) ? this.trackRollY : this.introLookAt.y + radius * 0.9;
    const spawn =
      this.marbleSpawnPoint?.clone() ||
      new Vector3(this.introLookAt.x + 3, rollY + 0.04, this.introLookAt.z - 9);
    const startLine = this.startLinePoint?.clone();
    const rollCross = startLine
      ? startLine.clone().setY(rollY + 0.04)
      : new Vector3(this.introLookAt.x, rollY + 0.04, this.introLookAt.z);
    mesh.position.copy(spawn);
    mesh.rotation.order = "YXZ";
    mesh.rotation.x = 0;
    mesh.rotation.z = 0;
    mesh.rotation.y = 0;

    const totalDist = Math.max(1e-4, spawn.distanceTo(rollCross));
    const rarity = Number(entry?.rarity) || 1;
    const durationSec = Math.max(0.26, 0.34 - rarity * 0.012);
    const spinScale = (1.05 * totalDist) / radius;
    const proxy = { t: 0 };
    this.marbleRollProxy = proxy;

    gsap.to(proxy, {
      t: 1,
      duration: durationSec,
      ease: "none",
      onUpdate: () => {
        if (stale()) return;
        const baseT = proxy.t;
        const u = distanceRatioAccel(baseT);
        const pos = new Vector3().lerpVectors(spawn, rollCross, u);
        pos.y += 0.022 * Math.sin(baseT * Math.PI * 3.2);
        mesh.position.copy(pos);
        mesh.rotation.x = 0;
        mesh.rotation.z = 0;
        mesh.rotation.y = u * spinScale;
      },
      onComplete: () => {
        if (stale()) return;
        mesh.position.copy(rollCross);
        mesh.rotation.x = 0;
        mesh.rotation.z = 0;
        mesh.rotation.y = spinScale;
        this.marbleRollProxy = null;
        this.showRevealOverlay(this.currentRevealEntry);
        this.revealPaused = true;
      },
    });
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
              if (!child.isMesh) return;
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
            this.lightsCameraLookAt.set(0, 0.5, 0);
            this.lightsCameraPos.set(0, 10, 14);
            this.introFrom.set(0, 28, 14);
            this.introTo.copy(this.lightsCameraPos);
            this.trackCameraLookAt.set(0, 0, 2);
            this.trackCameraPos.set(0, 2.2, 8);
            this.driftTo.copy(this.trackCameraPos);
            this.finalCameraPosition.copy(this.trackCameraPos);
          }
          resolve();
        },
      );
    });
  },

  ensureTextureCached(url, gen) {
    const key = canonicalTextureUrl(url);
    if (!key || this.textureCache.has(key)) return Promise.resolve();
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
    const box = new Box3().setFromObject(root);
    const size = box.getSize(new Vector3());
    const maxXZ = Math.max(size.x, size.z, 0.001);
    const s = 22 / maxXZ;
    root.scale.setScalar(s);
    root.updateMatrixWorld(true);
    const b2 = new Box3().setFromObject(root);
    const c = b2.getCenter(new Vector3());
    root.position.x -= c.x;
    root.position.z -= c.z;
    root.updateMatrixWorld(true);
    const b3 = new Box3().setFromObject(root);
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
      obj.material = Array.isArray(obj.material) ? [clonedMat] : clonedMat;
      const row = Number(match[1]);
      const col = Number(match[2]);
      const mat = Array.isArray(obj.material) ? obj.material[0] : obj.material;
      out.push({
        mesh: obj,
        row,
        col,
        center: worldCenter,
        baseColor: mat?.color?.clone?.() || new Color(0x666666),
        baseEmissive: mat?.emissive?.clone?.() || new Color(0x000000),
      });
    });
    out.sort((a, b) => a.col - b.col || a.row - b.row);
    this.raceLights = out;
    this.setAllRaceLightsOff();
  },

  meshWorldCenter(mesh) {
    if (!mesh?.geometry) return mesh?.getWorldPosition(new Vector3()) || new Vector3();
    if (!mesh.geometry.boundingBox) mesh.geometry.computeBoundingBox();
    const localCenter = new Vector3();
    mesh.geometry.boundingBox.getCenter(localCenter);
    return mesh.localToWorld(localCenter);
  },

  configureStageAnchors() {
    if (!this.trackRoot) return;
    this.trackRoot.updateMatrixWorld(true);
    const box = new Box3().setFromObject(this.trackRoot);
    const stageCenter = box.getCenter(new Vector3());
    if (this.raceLights.length === 0) {
      this.introLookAt.set(stageCenter.x, stageCenter.y, stageCenter.z);
      this.marbleLookAt.copy(this.introLookAt);
      this.lightsCameraLookAt.copy(this.introLookAt);
      this.lightsCameraPos.set(stageCenter.x + 2.5, stageCenter.y + 7.5, stageCenter.z + 12);
      this.introFrom.copy(this.lightsCameraPos).add(new Vector3(0, 18, 0));
      this.introTo.copy(this.lightsCameraPos);
      this.trackCameraLookAt.copy(this.marbleLookAt);
      this.trackCameraPos.set(stageCenter.x + 1.2, stageCenter.y + 1.8, stageCenter.z + 6.5);
      this.driftFrom.copy(this.lightsCameraPos);
      this.driftTo.copy(this.trackCameraPos);
      this.finalCameraPosition.copy(this.trackCameraPos);
      return;
    }
    const avgLight = new Vector3();
    this.raceLights.forEach((l) => avgLight.add(l.center));
    avgLight.multiplyScalar(1 / this.raceLights.length);
    const minRow = this.raceLights.reduce((acc, l) => Math.min(acc, l.row), Infinity);
    const startRowLights = this.raceLights.filter((l) => l.row === minRow);
    const startLine = new Vector3();
    startRowLights.forEach((l) => startLine.add(l.center));
    startLine.multiplyScalar(1 / Math.max(1, startRowLights.length));
    this.startLinePoint = startLine.clone();
    const farZ =
      Math.abs(box.min.z - startLine.z) > Math.abs(box.max.z - startLine.z) ? box.min.z : box.max.z;
    const tunnelDir = new Vector3(0, 0, Math.sign(farZ - startLine.z) || -1);
    const cameraDir = tunnelDir.clone().multiplyScalar(-1);
    this.introLookAt.copy(startLine).add(new Vector3(0, 0.25, 0));
    this.lightsCameraLookAt.copy(avgLight).add(new Vector3(0, 0.18, 0));
    this.lightsCameraPos
      .copy(startLine)
      .addScaledVector(cameraDir, 6.35)
      .add(new Vector3(0, 3.45, 0));
    this.introFrom.copy(this.lightsCameraPos).add(new Vector3(0, 20.5, 0));
    this.introTo.copy(this.lightsCameraPos);
    this.marbleLookAt.copy(startLine).addScaledVector(tunnelDir, 1.1);
    this.trackCameraLookAt.copy(this.marbleLookAt);
    this.trackCameraPos
      .copy(startLine)
      .addScaledVector(cameraDir, 2.6 + 0.72)
      .setY(startLine.y + 1.22 - 2.0);
    this.driftFrom.copy(this.lightsCameraPos);
    this.driftTo.copy(this.trackCameraPos);
    this.finalCameraPosition.copy(this.trackCameraPos);
    const tunnelDepth = Math.max(1.0, Math.abs(farZ - startLine.z));
    const spawnDistance = Math.max(1.95, tunnelDepth * 0.82);
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
    this.raceLights.forEach((light) => this.setRaceLightState(light, LIGHT_OFF_COLOR, 0.05));
  },

  disposeObject3D(obj, opts = {}) {
    if (!obj) return;
    const keepTextures = opts.keepTextures === true;
    if (this.scene) this.scene.remove(obj);
    obj.traverse((child) => {
      if (!child.isMesh) return;
      child.geometry?.dispose?.();
      const mat = child.material;
      if (Array.isArray(mat)) {
        mat.forEach((m) => {
          if (keepTextures) clearMaterialTextureRefs(m);
          else m.map?.dispose?.();
          m?.dispose?.();
        });
      } else {
        if (keepTextures) clearMaterialTextureRefs(mat);
        else mat.map?.dispose?.();
        mat?.dispose?.();
      }
    });
  },

  finishEarly() {
    if (!this.currentPayload) return;
    this.preloadGen += 1;
    this.sequenceId += 1;
    this.killSequenceTimeline();
    this.disposeCinematicResources();
    this.setupScene();
    this.initRenderer();
    this.complete();
  },

  complete() {
    this.killSequenceTimeline();
    this.stage = "done";
    this.revealPaused = false;
    this.setAllRaceLightsOff();
    this.hideRevealOverlay(true);
    this.hideLegendaryOverlay(true);
    this.pushEvent("gacha_animation_done", {});
  },

  resizeRendererWith(renderer) {
    if (!renderer || !this.camera) return;
    const width = Math.max(this.el.clientWidth, 1);
    const height = Math.max(this.el.clientHeight, 1);
    renderer.setSize(width, height);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  },

  resizeRenderer() {
    if (!this.renderer || !this.camera) return;
    this.resizeRendererWith(this.renderer);
  },
};

export { GachaCinematic };
