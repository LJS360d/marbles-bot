import {
  Engine,
  Scene,
  ArcRotateCamera,
  HemisphericLight,
  DirectionalLight,
  MeshBuilder,
  StandardMaterial,
  Color3,
  Color4,
  Vector3,
} from "@babylonjs/core";

const TRACK_LENGTH_DEFAULT = 1100;
const MARBLE_RADIUS = 0.6;

const PALETTE = [
  new Color3(0.94, 0.27, 0.27),
  new Color3(0.96, 0.62, 0.04),
  new Color3(0.06, 0.72, 0.51),
  new Color3(0.23, 0.51, 0.96),
  new Color3(0.66, 0.33, 0.97),
  new Color3(0.93, 0.30, 0.60),
  new Color3(0.08, 0.72, 0.65),
  new Color3(0.92, 0.71, 0.04),
];

function colorFor(idx) {
  return PALETTE[idx % PALETTE.length];
}

class RaceScene {
  constructor(canvas) {
    this.canvas = canvas;
    this.engine = new Engine(canvas, true, { preserveDrawingBuffer: false, stencil: false });
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(0.04, 0.04, 0.07, 1);

    this.trackLength = TRACK_LENGTH_DEFAULT;
    this.marbles = new Map();
    this.playerMarbleId = null;

    // lerp state
    this.lerpStart = 0;
    this.lerpDuration = 0.12;
    this.targetPositions = new Map(); // id -> {x, z}

    this._buildCamera();
    this._buildLights();
    this._buildTrack(this.trackLength);

    this.boundResize = () => this.engine.resize();
    window.addEventListener("resize", this.boundResize);

    this.engine.runRenderLoop(() => {
      this._interpolate();
      this._followCamera();
      this.scene.render();
    });
  }

  _buildCamera() {
    // ArcRotateCamera orbiting around origin; we shift its target in _followCamera
    this.camera = new ArcRotateCamera("cam", -Math.PI / 2, Math.PI / 3.5, 28, Vector3.Zero(), this.scene);
    this.camera.lowerRadiusLimit = 10;
    this.camera.upperRadiusLimit = 60;
    this.camera.minZ = 0.1;
    this.camera.maxZ = 5000;
  }

  _buildLights() {
    const hemi = new HemisphericLight("hemi", new Vector3(0, 1, 0), this.scene);
    hemi.intensity = 0.6;
    hemi.diffuse = new Color3(1, 1, 1);
    hemi.groundColor = new Color3(0.2, 0.2, 0.3);

    const dir = new DirectionalLight("dir", new Vector3(0.5, -1, 0.3), this.scene);
    dir.intensity = 0.9;
    dir.diffuse = new Color3(1, 0.95, 0.85);
  }

  _buildTrack(length) {
    // Dispose previous track meshes (including materials)
    for (const m of this.scene.meshes.slice()) {
      if (m.metadata && m.metadata.isTrack) m.dispose(false, true);
    }

    const groundMat = new StandardMaterial("ground", this.scene);
    groundMat.diffuseColor = new Color3(0.12, 0.16, 0.22);
    groundMat.specularColor = Color3.Black();

    const ground = MeshBuilder.CreateGround("track_ground", { width: 24, height: length }, this.scene);
    ground.position.z = length / 2;
    ground.material = groundMat;
    ground.metadata = { isTrack: true };

    const laneMat = new StandardMaterial("lane", this.scene);
    laneMat.diffuseColor = new Color3(0.28, 0.33, 0.42);
    laneMat.specularColor = Color3.Black();

    const step = 60;
    for (let z = 0; z <= length; z += step) {
      const line = MeshBuilder.CreateBox(`lane_${z}`, { width: 24, height: 0.04, depth: 0.3 }, this.scene);
      line.position.set(0, 0.02, z);
      line.material = laneMat;
      line.metadata = { isTrack: true };
    }

    // Start + finish lines
    const startMat = new StandardMaterial("start", this.scene);
    startMat.diffuseColor = new Color3(0.2, 0.8, 0.3);
    startMat.specularColor = Color3.Black();
    const startLine = MeshBuilder.CreateBox("start_line", { width: 24, height: 0.06, depth: 0.6 }, this.scene);
    startLine.position.set(0, 0.03, 0);
    startLine.material = startMat;
    startLine.metadata = { isTrack: true };

    const finishMat = new StandardMaterial("finish", this.scene);
    finishMat.diffuseColor = new Color3(0.9, 0.2, 0.2);
    finishMat.specularColor = Color3.Black();
    const finishLine = MeshBuilder.CreateBox("finish_line", { width: 24, height: 0.06, depth: 0.6 }, this.scene);
    finishLine.position.set(0, 0.03, length);
    finishLine.material = finishMat;
    finishLine.metadata = { isTrack: true };
  }

  _getOrCreateMarble(id, idx) {
    if (this.marbles.has(id)) return this.marbles.get(id);

    const sphere = MeshBuilder.CreateSphere(`marble_${id}`, { diameter: MARBLE_RADIUS * 2, segments: 16 }, this.scene);
    sphere.position.set(0, MARBLE_RADIUS, 0);

    const mat = new StandardMaterial(`mat_${id}`, this.scene);
    mat.diffuseColor = colorFor(idx ?? this.marbles.size);
    mat.specularColor = new Color3(0.5, 0.5, 0.5);
    mat.specularPower = 32;
    sphere.material = mat;

    const entry = { mesh: sphere };
    this.marbles.set(id, entry);
    return entry;
  }

  applySetup(setup) {
    if (!setup) return;

    if (setup.track?.length_meters) {
      this.trackLength = setup.track.length_meters;
      this._buildTrack(this.trackLength);
    }

    if (setup.current_user_id) {
      // Find which marble id belongs to current user — will match on first frame
      this._pendingUserId = setup.current_user_id;
    }

    const racers = (setup.participants || []).flatMap((p) => p.racers || []);
    racers.forEach((r, idx) => {
      const id = r.user_marble_id || r.marble_id;
      if (!id) return;
      this._getOrCreateMarble(id, idx);
    });
  }

  applyFrames(frames) {
    if (!frames || !frames.length) return;
    const latest = frames[frames.length - 1];
    this.lerpStart = performance.now() / 1000;

    for (const m of latest.marbles) {
      // Match player marble id from user_id
      if (this._pendingUserId && m.user_id === this._pendingUserId) {
        this.playerMarbleId = m.id;
        this._pendingUserId = null;
      }
      const entry = this._getOrCreateMarble(m.id, null);
      if (!this.targetPositions.has(m.id)) {
        this.targetPositions.set(m.id, { x: m.x || 0, z: m.z || 0 });
      } else {
        const t = this.targetPositions.get(m.id);
        t.x = m.x || 0;
        t.z = m.z || 0;
      }
    }
  }

  applyReplay(replay) {
    if (!replay) return;
    if (replay.track?.length_meters) {
      this.trackLength = replay.track.length_meters;
      this._buildTrack(this.trackLength);
    }
    const frames = replay.frames || [];
    if (frames.length) this.applyFrames([frames[frames.length - 1]]);
  }

  _interpolate() {
    const now = performance.now() / 1000;
    const alpha = Math.min(1, (now - this.lerpStart) / this.lerpDuration);

    for (const [id, entry] of this.marbles) {
      const target = this.targetPositions.get(id);
      if (!target) continue;
      const prevZ = entry.mesh.position.z;
      entry.mesh.position.x += (target.x - entry.mesh.position.x) * alpha;
      entry.mesh.position.z += (target.z - entry.mesh.position.z) * alpha;
      // Rolling rotation proportional to distance traveled
      entry.mesh.rotation.x -= (entry.mesh.position.z - prevZ) / MARBLE_RADIUS;
    }
  }

  _followCamera() {
    // Follow player marble if known; else follow lead marble
    let targetId = this.playerMarbleId;
    if (!targetId && this.marbles.size > 0) {
      let maxZ = -Infinity;
      for (const [id, entry] of this.marbles) {
        if (entry.mesh.position.z > maxZ) { maxZ = entry.mesh.position.z; targetId = id; }
      }
    }
    if (!targetId) return;

    const entry = this.marbles.get(targetId);
    if (!entry) return;

    const pos = entry.mesh.position;
    this.camera.target = Vector3.Lerp(this.camera.target, new Vector3(pos.x, 0, pos.z), 0.08);
  }

  destroy() {
    window.removeEventListener("resize", this.boundResize);
    this.engine.stopRenderLoop();
    this.scene.dispose();
    this.engine.dispose();
  }
}

// --- Skill toast overlay ---

const TOAST_DURATION_MS = 1800;

function createToastContainer(el) {
  const div = document.createElement("div");
  div.style.cssText =
    "position:absolute;top:12px;right:12px;display:flex;flex-direction:column;gap:6px;pointer-events:none;z-index:10;";
  el.appendChild(div);
  return div;
}

function showToast(container, abilityKey) {
  const toast = document.createElement("div");
  toast.style.cssText = [
    "background:rgba(0,0,0,0.75)",
    "border:1px solid rgba(255,255,255,0.15)",
    "border-radius:8px",
    "padding:4px 10px",
    "font-size:0.7rem",
    "font-weight:600",
    "letter-spacing:0.08em",
    "color:#fff",
    "text-transform:uppercase",
    "opacity:1",
    "transition:opacity 0.4s ease",
  ].join(";");
  toast.textContent = abilityKey.replace(/_/g, " ");
  container.appendChild(toast);

  setTimeout(() => { toast.style.opacity = "0"; }, TOAST_DURATION_MS - 400);
  setTimeout(() => { toast.remove(); }, TOAST_DURATION_MS);
}

// --- LiveView hook ---

export const RaceRenderer = {
  mounted() {
    const canvas = this.el.querySelector("canvas");
    if (!canvas) return;

    this.raceScene = new RaceScene(canvas);
    this.toastContainer = createToastContainer(this.el);

    const replayB64 = this.el.dataset.replayB64;
    if (replayB64) {
      try {
        const replay = JSON.parse(atob(replayB64));
        this.raceScene.applyReplay(replay);
      } catch (_) {}
    }

    this.handleEvent("race:setup", (setup) => this.raceScene?.applySetup(setup));
    this.handleEvent("race:frames", ({ frames }) => this.raceScene?.applyFrames(frames));
    this.handleEvent("race:abilities", ({ triggers }) => {
      if (!triggers) return;
      for (const t of triggers) showToast(this.toastContainer, t.ability_key);
    });
  },

  destroyed() {
    this.raceScene?.destroy();
    this.raceScene = null;
  },
};

export default RaceRenderer;
