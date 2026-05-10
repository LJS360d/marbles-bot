import * as THREE from "three";

const STORAGE_KEY = "marbles:race_dock_pos";
const COLOR_PALETTE = [
  0xef4444, 0xf59e0b, 0x10b981, 0x3b82f6, 0xa855f7, 0xec4899, 0x14b8a6, 0xeab308,
];

function loadPos() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (_e) {
    return null;
  }
}

function savePos(pos) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(pos));
  } catch (_e) {}
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function colorFor(idx) {
  return COLOR_PALETTE[idx % COLOR_PALETTE.length];
}

class MiniRaceScene {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x0a0a12);

    this.camera = new THREE.PerspectiveCamera(65, 16 / 9, 0.1, 5000);
    this.camera.position.set(0, 9, -20);
    this.camera.lookAt(0, 0, 60);

    this.scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(15, 30, 5);
    this.scene.add(dir);

    this.trackLength = 1100;
    this.trackGroup = new THREE.Group();
    this.scene.add(this.trackGroup);
    this.buildTrack(this.trackLength);

    this.marbles = new Map();
    this.targets = new Map();
    this.lastUpdate = performance.now() / 1000;

    this.running = true;
    this.handle = null;
    this.animate = this.animate.bind(this);
    requestAnimationFrame(this.animate);
  }

  buildTrack(length) {
    while (this.trackGroup.children.length) {
      const c = this.trackGroup.children.pop();
      if (c.geometry) c.geometry.dispose();
      if (c.material) c.material.dispose();
    }
    const groundGeo = new THREE.PlaneGeometry(20, length);
    const groundMat = new THREE.MeshStandardMaterial({ color: 0x1f2937, roughness: 0.9 });
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.z = length / 2;
    this.trackGroup.add(ground);
  }

  applyFrames(frames) {
    if (!frames || !frames.length) return;
    const last = frames[frames.length - 1];
    this.lastUpdate = performance.now() / 1000;
    for (const m of last.marbles) {
      let mesh = this.marbles.get(m.id);
      if (!mesh) {
        const geom = new THREE.SphereGeometry(0.6, 24, 12);
        const mat = new THREE.MeshStandardMaterial({ color: colorFor(this.marbles.size) });
        mesh = new THREE.Mesh(geom, mat);
        mesh.position.set(m.x || 0, 0.6, m.z || 0);
        this.scene.add(mesh);
        this.marbles.set(m.id, mesh);
      }
      this.targets.set(m.id, { x: m.x || 0, z: m.z || 0 });
    }
  }

  animate() {
    if (!this.running) return;
    this.handle = requestAnimationFrame(this.animate);
    const t = clamp((performance.now() / 1000 - this.lastUpdate) / 0.2, 0, 1);
    let leadZ = 0;
    for (const [id, mesh] of this.marbles.entries()) {
      const target = this.targets.get(id);
      if (!target) continue;
      mesh.position.x += (target.x - mesh.position.x) * t;
      mesh.position.z += (target.z - mesh.position.z) * t;
      mesh.rotation.x = -mesh.position.z / 0.6;
      if (mesh.position.z > leadZ) leadZ = mesh.position.z;
    }
    this.camera.position.z = leadZ - 16;
    this.camera.lookAt(0, 0.6, leadZ + 6);
    this.renderer.render(this.scene, this.camera);
  }

  resize() {
    const rect = this.canvas.parentElement.getBoundingClientRect();
    const w = Math.max(rect.width, 160);
    const h = Math.max(rect.height, 90);
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  destroy() {
    this.running = false;
    if (this.handle) cancelAnimationFrame(this.handle);
    for (const mesh of this.marbles.values()) {
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.marbles.clear();
    this.renderer.dispose();
  }
}

export const RaceDock = {
  mounted() {
    this.applyPos();
    this.attachDrag();

    this.boundFrames = (payload) => this.scene && this.scene.applyFrames(payload.frames);
    this.handleEvent("race:frames", this.boundFrames);

    this.boundResize = () => this.scene && this.scene.resize();
    window.addEventListener("resize", this.boundResize);

    this.boundOpen = () => {
      this.pushEvent("show", {});
      const dock = this.el.querySelector("#race-dock") || this.el;
      dock.classList.add("ring", "ring-primary");
      setTimeout(() => dock.classList.remove("ring", "ring-primary"), 1200);
    };
    window.addEventListener("phx:race-dock:open", this.boundOpen);

    this.maybeMountCanvas();
  },

  updated() {
    this.applyPos();
    this.attachDrag();
    this.maybeMountCanvas();
  },

  destroyed() {
    window.removeEventListener("resize", this.boundResize);
    window.removeEventListener("phx:race-dock:open", this.boundOpen);
    if (this.scene) {
      this.scene.destroy();
      this.scene = null;
    }
    this.detachDrag();
  },

  dockEl() {
    return this.el.querySelector("#race-dock");
  },

  applyPos() {
    const dock = this.dockEl();
    if (!dock) return;
    const pos = loadPos();
    if (!pos) return;
    if (typeof pos.left === "number") {
      dock.style.left = `${pos.left}px`;
      dock.style.right = "auto";
    }
    if (typeof pos.top === "number") {
      dock.style.top = `${pos.top}px`;
      dock.style.bottom = "auto";
    }
  },

  savePos() {
    const dock = this.dockEl();
    if (!dock) return;
    const r = dock.getBoundingClientRect();
    savePos({ left: r.left, top: r.top });
  },

  attachDrag() {
    this.detachDrag();
    const dock = this.dockEl();
    if (!dock) return;
    const handle = dock.querySelector('[data-role="drag-handle"]');
    if (!handle) return;

    let drag = null;
    const onDown = (e) => {
      if (e.target.closest("button")) return;
      const rect = dock.getBoundingClientRect();
      drag = { dx: e.clientX - rect.left, dy: e.clientY - rect.top };
      window.addEventListener("mousemove", onMove);
      window.addEventListener("mouseup", onUp);
      e.preventDefault();
    };
    const onMove = (e) => {
      if (!drag) return;
      const left = clamp(e.clientX - drag.dx, 0, window.innerWidth - 60);
      const top = clamp(e.clientY - drag.dy, 0, window.innerHeight - 60);
      dock.style.left = `${left}px`;
      dock.style.top = `${top}px`;
      dock.style.right = "auto";
      dock.style.bottom = "auto";
    };
    const onUp = () => {
      drag = null;
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      this.savePos();
      if (this.scene) this.scene.resize();
    };

    handle.addEventListener("mousedown", onDown);
    this._dragHandle = handle;
    this._dragOnDown = onDown;
  },

  detachDrag() {
    if (this._dragHandle && this._dragOnDown) {
      this._dragHandle.removeEventListener("mousedown", this._dragOnDown);
    }
    this._dragHandle = null;
    this._dragOnDown = null;
  },

  maybeMountCanvas() {
    const canvas = this.el.querySelector('[data-role="mini-canvas"]');
    if (canvas && !this.scene) {
      this.scene = new MiniRaceScene(canvas);
      requestAnimationFrame(() => this.scene && this.scene.resize());
    } else if (!canvas && this.scene) {
      this.scene.destroy();
      this.scene = null;
    }
  },
};

export default RaceDock;
