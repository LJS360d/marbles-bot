import * as THREE from "three";

const TRACK_LENGTH_DEFAULT = 1100;
const COLOR_PALETTE = [
  0xef4444, 0xf59e0b, 0x10b981, 0x3b82f6, 0xa855f7, 0xec4899, 0x14b8a6, 0xeab308,
];

function colorFor(idx) {
  return COLOR_PALETTE[idx % COLOR_PALETTE.length];
}

class RaceScene {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x0a0a12);

    this.camera = new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 5000);
    this.camera.position.set(0, 14, -28);
    this.camera.lookAt(0, 0, 80);

    const ambient = new THREE.AmbientLight(0xffffff, 0.6);
    this.scene.add(ambient);
    const dir = new THREE.DirectionalLight(0xffffff, 0.8);
    dir.position.set(20, 40, 10);
    this.scene.add(dir);

    this.trackLength = TRACK_LENGTH_DEFAULT;
    this.trackGroup = new THREE.Group();
    this.scene.add(this.trackGroup);
    this.buildTrack(this.trackLength);

    this.marbles = new Map();
    this.lastFrame = null;
    this.targetFrame = null;
    this.lerpStart = 0;
    this.lerpDuration = 0.15;

    this.resize();
    this.boundResize = () => this.resize();
    window.addEventListener("resize", this.boundResize);

    this.running = true;
    this.tickHandle = null;
    this.animate = this.animate.bind(this);
    requestAnimationFrame(this.animate);
  }

  destroy() {
    this.running = false;
    if (this.tickHandle) cancelAnimationFrame(this.tickHandle);
    window.removeEventListener("resize", this.boundResize);
    this.renderer.dispose();
    for (const m of this.marbles.values()) {
      m.mesh.geometry.dispose();
      m.mesh.material.dispose();
    }
    this.marbles.clear();
  }

  buildTrack(length) {
    while (this.trackGroup.children.length) {
      const c = this.trackGroup.children.pop();
      if (c.geometry) c.geometry.dispose();
      if (c.material) c.material.dispose();
    }

    const groundGeo = new THREE.PlaneGeometry(20, length);
    const groundMat = new THREE.MeshStandardMaterial({ color: 0x1f2937, roughness: 0.85 });
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.z = length / 2;
    this.trackGroup.add(ground);

    const lineMat = new THREE.LineBasicMaterial({ color: 0x4b5563 });
    for (let z = 0; z <= length; z += 50) {
      const geom = new THREE.BufferGeometry().setFromPoints([
        new THREE.Vector3(-10, 0.05, z),
        new THREE.Vector3(10, 0.05, z),
      ]);
      const line = new THREE.Line(geom, lineMat);
      this.trackGroup.add(line);
    }
  }

  applySetup(setup) {
    if (!setup) return;
    if (setup.track && setup.track.length_meters) {
      this.trackLength = setup.track.length_meters;
      this.buildTrack(this.trackLength);
    }

    const racers = (setup.participants || []).flatMap((p) => p.racers || []);
    racers.forEach((r, idx) => {
      const id = r.user_marble_id || r.marble_id;
      if (!id || this.marbles.has(id)) return;
      const geom = new THREE.SphereGeometry(0.6, 32, 16);
      const mat = new THREE.MeshStandardMaterial({ color: colorFor(idx) });
      const mesh = new THREE.Mesh(geom, mat);
      mesh.position.set(0, 0.6, 0);
      this.scene.add(mesh);
      this.marbles.set(id, { mesh, target: { x: 0, y: 0.6, z: 0 } });
    });
  }

  applyFrames(frames) {
    if (!frames || !frames.length) return;
    this.lastFrame = this.targetFrame || this.lastFrame;
    this.targetFrame = frames[frames.length - 1];
    this.lerpStart = performance.now() / 1000;

    for (const m of this.targetFrame.marbles) {
      let entry = this.marbles.get(m.id);
      if (!entry) {
        const geom = new THREE.SphereGeometry(0.6, 32, 16);
        const mat = new THREE.MeshStandardMaterial({ color: colorFor(this.marbles.size) });
        const mesh = new THREE.Mesh(geom, mat);
        mesh.position.set(m.x || 0, 0.6, m.z || 0);
        this.scene.add(mesh);
        entry = { mesh, target: { x: m.x || 0, y: 0.6, z: m.z || 0 } };
        this.marbles.set(m.id, entry);
      }
      entry.target.x = m.x || 0;
      entry.target.z = m.z || 0;
    }
  }

  applyReplay(replay) {
    if (!replay) return;
    if (replay.track && replay.track.length_meters) {
      this.trackLength = replay.track.length_meters;
      this.buildTrack(this.trackLength);
    }
    const frames = replay.frames || [];
    if (frames.length) {
      this.applyFrames([frames[frames.length - 1]]);
    }
  }

  animate() {
    if (!this.running) return;
    this.tickHandle = requestAnimationFrame(this.animate);

    const now = performance.now() / 1000;
    const t = Math.min(1, (now - this.lerpStart) / this.lerpDuration);

    let leadZ = 0;
    for (const entry of this.marbles.values()) {
      const x = entry.mesh.position.x + (entry.target.x - entry.mesh.position.x) * t;
      const z = entry.mesh.position.z + (entry.target.z - entry.mesh.position.z) * t;
      entry.mesh.position.x = x;
      entry.mesh.position.z = z;
      entry.mesh.rotation.x = -z / 0.6;
      if (z > leadZ) leadZ = z;
    }

    const camZ = leadZ - 18;
    this.camera.position.z = camZ;
    this.camera.lookAt(0, 0.6, leadZ + 8);

    this.renderer.render(this.scene, this.camera);
  }

  resize() {
    const rect = this.canvas.parentElement.getBoundingClientRect();
    const w = Math.max(rect.width, 320);
    const h = Math.max(rect.height, 200);
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }
}

export const RaceRenderer = {
  mounted() {
    const canvas = this.el.querySelector("canvas");
    if (!canvas) return;
    this.scene = new RaceScene(canvas);

    const replayB64 = this.el.dataset.replayB64;
    if (replayB64) {
      try {
        const json = atob(replayB64);
        const replay = JSON.parse(json);
        this.scene.applyReplay(replay);
      } catch (_e) {
        // ignore
      }
    }

    this.handleEvent("race:setup", (setup) => this.scene && this.scene.applySetup(setup));
    this.handleEvent("race:frames", (payload) => this.scene && this.scene.applyFrames(payload.frames));
  },

  destroyed() {
    if (this.scene) this.scene.destroy();
    this.scene = null;
  },
};

export default RaceRenderer;
