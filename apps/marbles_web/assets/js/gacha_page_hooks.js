import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

const GACHA_SKIP_CONFIRM_KEY = "gachaSkipConfirm";

const TRACK_GLB_URL = "/3d/tracks/savage_speedway_s1.glb";

const MARBLE_HD_GLB_URL = "/3d/marble-center-high.glb";

const rarityColor = (rarity) => {
  if (rarity >= 3) return 0xffc857;
  if (rarity === 2) return 0x8fd3ff;
  return 0xd1d5db;
};

const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

const easeInOutQuad = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);

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
    this.resizeHandler = () => this.resizeRenderer();
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
    this.marbleLoadGen = 0;
    this.marbleMotion = null;
    this.gltfLoader = new GLTFLoader();
    this.textureLoader = new THREE.TextureLoader();

    this.setupScene();
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
    this.introActive = false;
    this.introSegment = null;
    this.marbleMotion = null;
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame);

    window.removeEventListener("resize", this.resizeHandler);

    if (this.renderer) {
      this.renderer.dispose();
      if (this.renderer.domElement.parentNode === this.el) {
        this.el.removeChild(this.renderer.domElement);
      }
    }

    this.disposeObject3D(this.marbleRoot);
    this.disposeObject3D(this.trackRoot);
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
      new THREE.MeshStandardMaterial({ color: 0x0b1220, roughness: 0.96, metalness: 0.05 }),
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
      this.resizeRenderer();
      this.el.appendChild(this.renderer.domElement);
      this.webglReady = true;
      this.renderLoop();
    } catch {
      this.webglReady = false;
    }
  },

  renderLoop() {
    this.animationFrame = requestAnimationFrame(() => this.renderLoop());

    if (this.introActive) {
      this.updateIntroCamera();
    }

    if (this.marbleRoot && this.marbleMotion) {
      const t = Math.min(1, (performance.now() - this.marbleMotion.t0) / this.marbleMotion.duration);
      const e = 1 - (1 - t) * (1 - t);
      this.marbleRoot.position.lerpVectors(this.marbleMotion.spawn, this.marbleMotion.rest, e);
      this.marbleRoot.position.y += 0.22 * Math.sin(t * Math.PI);
      this.marbleRoot.rotation.z = 0.42 * Math.sin(t * Math.PI * 1.5);
      this.marbleRoot.rotation.y += 0.055;
      if (t >= 1) {
        this.marbleMotion = null;
      }
    } else if (this.marbleRoot && !this.introActive) {
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
    this.introActive = false;
    this.introSegment = null;
    this.marbleMotion = null;
    this.currentPayload = payload;
    this.results = payload.results || [];
    this.currentIndex = 0;
    this.stage = "intro";

    this.disposeObject3D(this.marbleRoot);
    this.marbleRoot = null;

    this.finalCameraPosition.copy(this.introTo).add(this.driftDelta);

    this.camera.position.copy(this.introFrom);
    this.camera.lookAt(this.introLookAt);

    this.loadTrackForPull();

    this.pushEvent("gacha_animation_progress", {
      phase: "intro",
      index: 0,
      total: this.results.length,
    });

    this.introSegment = "vertical";
    this.introStartedAt = performance.now();
    this.introActive = true;
  },

  loadTrackForPull() {
    this.disposeObject3D(this.trackRoot);
    this.trackRoot = null;

    this.gltfLoader.load(
      TRACK_GLB_URL,
      (gltf) => {
        const root = gltf.scene;
        this.fitTrackToScene(root);
        this.scene.add(root);
        this.trackRoot = root;
        const box = new THREE.Box3().setFromObject(root);
        const c = box.getCenter(new THREE.Vector3());
        this.introLookAt.set(c.x, Math.min(c.y + 0.4, 1.2), c.z);
      },
      undefined,
      () => {
        this.introLookAt.set(0, 0, 0);
      },
    );
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
    this.pushEvent("gacha_animation_progress", {
      phase: "reveal",
      index: 0,
      total: this.results.length,
    });

    const interval = window.setInterval(() => {
      if (this.currentIndex >= this.results.length) {
        this.clearTimers();
        this.complete();
        return;
      }

      const entry = this.results[this.currentIndex];
      this.showMarble(entry);
      this.currentIndex += 1;

      this.pushEvent("gacha_animation_progress", {
        phase: "reveal",
        index: this.currentIndex,
        total: this.results.length,
      });
    }, 700);

    this.activeTimers.push(interval);
  },

  showMarble(entry) {
    if (!this.webglReady) return;

    this.disposeObject3D(this.marbleRoot);
    this.marbleRoot = null;
    this.marbleMotion = null;

    const gen = ++this.marbleLoadGen;
    const textureUrl = entry.texture_url || null;

    this.gltfLoader.load(
      MARBLE_HD_GLB_URL,
      (gltf) => {
        if (gen !== this.marbleLoadGen || !this.currentPayload) return;
        const root = gltf.scene;
        this.fitMarbleToScene(root, 1.35);
        this.scene.add(root);
        this.marbleRoot = root;
        if (textureUrl) {
          this.applyMarbleTexture(root, textureUrl, gen);
        }
        this.startMarbleMotion(root);
      },
      undefined,
      () => {
        if (gen !== this.marbleLoadGen) return;
        this.showMarbleFallbackSphere(entry);
      },
    );
  },

  applyMarbleTexture(root, url, gen) {
    this.textureLoader.load(
      url,
      (tex) => {
        if (gen !== this.marbleLoadGen) {
          tex.dispose();
          return;
        }
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.flipY = false;
        tex.minFilter = THREE.LinearMipmapLinearFilter;
        tex.magFilter = THREE.LinearFilter;
        tex.generateMipmaps = true;
        root.traverse((c) => {
          if (!c.isMesh || !c.material) return;
          const mats = Array.isArray(c.material) ? c.material : [c.material];
          mats.forEach((m) => {
            if (m.name === "colormap") {
              if (m.map) m.map.dispose();
              m.map = tex;
              m.needsUpdate = true;
            }
          });
        });
      },
      undefined,
      () => {},
    );
  },

  startMarbleMotion(root) {
    const spawn = new THREE.Vector3(4.1, 1.55, -2.35);
    const rest = new THREE.Vector3(0, 0.28, 0);
    root.position.copy(spawn);
    this.marbleMotion = { spawn, rest, t0: performance.now(), duration: 520 };
  },

  fitMarbleToScene(root, targetMaxDim) {
    root.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(root);
    const size = box.getSize(new THREE.Vector3());
    const m = Math.max(size.x, size.y, size.z, 0.001);
    const s = targetMaxDim / m;
    root.scale.setScalar(s);
    root.updateMatrixWorld(true);
    const b2 = new THREE.Box3().setFromObject(root);
    const c = b2.getCenter(new THREE.Vector3());
    root.position.sub(c);
  },

  showMarbleFallbackSphere(entry) {
    const geometry = new THREE.SphereGeometry(0.9, 40, 40);
    const material = new THREE.MeshStandardMaterial({
      color: rarityColor(entry.rarity || 1),
      metalness: 0.75,
      roughness: 0.2,
      emissive: rarityColor(entry.rarity || 1),
      emissiveIntensity: 0.12,
    });
    const mesh = new THREE.Mesh(geometry, material);
    this.scene.add(mesh);
    this.marbleRoot = mesh;
    this.startMarbleMotion(mesh);
  },

  disposeObject3D(obj) {
    if (!obj) return;
    this.scene.remove(obj);
    obj.traverse((child) => {
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
  },

  finishEarly() {
    if (!this.currentPayload) return;
    this.introActive = false;
    this.introSegment = null;
    this.clearTimers();
    this.camera.position.copy(this.finalCameraPosition);
    this.camera.lookAt(this.introLookAt);
    this.complete();
  },

  complete() {
    this.introActive = false;
    this.introSegment = null;
    this.stage = "done";
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
