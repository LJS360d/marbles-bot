import * as THREE from "three";

const GACHA_SKIP_CONFIRM_KEY = "gachaSkipConfirm";

const rarityColor = (rarity) => {
  if (rarity >= 3) return 0xffc857;
  if (rarity === 2) return 0x8fd3ff;
  return 0xd1d5db;
};

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
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame);
    window.removeEventListener("resize", this.resizeHandler);

    if (this.renderer) {
      this.renderer.dispose();
      if (this.renderer.domElement.parentNode === this.el) {
        this.el.removeChild(this.renderer.domElement);
      }
    }

    if (this.marbleMesh) {
      this.scene.remove(this.marbleMesh);
      this.marbleMesh.geometry.dispose();
      this.marbleMesh.material.dispose();
    }
  },

  setupScene() {
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x080b12);

    this.camera = new THREE.PerspectiveCamera(
      60,
      this.el.clientWidth / Math.max(this.el.clientHeight, 1),
      0.1,
      100,
    );
    this.camera.position.set(0, 2.2, 6);

    const ambient = new THREE.AmbientLight(0xffffff, 0.8);
    this.scene.add(ambient);

    const keyLight = new THREE.DirectionalLight(0xffffff, 1.2);
    keyLight.position.set(5, 8, 6);
    this.scene.add(keyLight);

    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(18, 18),
      new THREE.MeshStandardMaterial({ color: 0x0f172a, roughness: 0.95 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -1.2;
    this.scene.add(floor);

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

    if (this.marbleMesh) {
      this.marbleMesh.rotation.y += 0.02;
      this.marbleMesh.rotation.x += 0.01;
    }

    if (this.renderer) {
      this.renderer.render(this.scene, this.camera);
    }
  },

  start(payload) {
    this.clearTimers();
    this.currentPayload = payload;
    this.results = payload.results || [];
    this.currentIndex = 0;
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

    if (this.marbleMesh) {
      this.scene.remove(this.marbleMesh);
      this.marbleMesh.geometry.dispose();
      this.marbleMesh.material.dispose();
    }

    const geometry = new THREE.SphereGeometry(0.9, 40, 40);
    const material = new THREE.MeshStandardMaterial({
      color: rarityColor(entry.rarity || 1),
      metalness: 0.75,
      roughness: 0.2,
      emissive: rarityColor(entry.rarity || 1),
      emissiveIntensity: 0.12,
    });

    this.marbleMesh = new THREE.Mesh(geometry, material);
    this.scene.add(this.marbleMesh);
  },

  finishEarly() {
    if (!this.currentPayload) return;
    this.clearTimers();
    this.complete();
  },

  complete() {
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
