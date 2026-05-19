import * as THREE from "three";
import * as CANNON from "cannon-es";

// ─── Board constants ──────────────────────────────────────────────────────────
const NUM_ROWS = 6;
const NUM_SLOTS = 7;
const SLOT_SPACING = 1.0;
const ROW_SPACING = 0.85;
const PEG_RADIUS = 0.07;
const MARBLE_RADIUS = 0.19;
const ROW_TOP_Y = 2.5;
const SLOT_Y = ROW_TOP_Y - NUM_ROWS * ROW_SPACING - 0.65;
const MARBLE_START_Y = ROW_TOP_Y + 1.4;
// Physics pegs extend along z — tall enough to always catch the marble
const PEG_HEIGHT_PHYS = 3.0;
// Gentle horizontal force (N) biasing ball toward target slot each physics step
const GUIDE_FORCE = 0.9;

function slotX(slotId) {
  return (slotId - (NUM_SLOTS - 1) / 2) * SLOT_SPACING;
}

function pegPositionsForRow(row) {
  const count = row + 3;
  const start = -((count - 1) / 2.0);
  return Array.from({ length: count }, (_, i) => ({
    x: start + i * SLOT_SPACING,
    y: ROW_TOP_Y - row * ROW_SPACING,
  }));
}

// ─── Seeded RNG (mulberry32) ──────────────────────────────────────────────────
function mulberry32(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ─── Physics simulation ───────────────────────────────────────────────────────
function runSimulation(seed, targetSlot) {
  const rng = mulberry32(seed);
  const targetX = slotX(targetSlot);

  const world = new CANNON.World({ gravity: new CANNON.Vec3(0, -9.82, 0) });

  const marbleMaterial = new CANNON.Material("marble");
  const staticMaterial = new CANNON.Material("static");
  world.addContactMaterial(
    new CANNON.ContactMaterial(marbleMaterial, staticMaterial, {
      restitution: 0.55,
      friction: 0.15,
    }),
  );

  // Pegs — cylinder oriented along z axis (same as Three.js peg.rotation.x = PI/2)
  const pegShape = new CANNON.Cylinder(PEG_RADIUS, PEG_RADIUS, PEG_HEIGHT_PHYS, 8);
  const pegQuat = new CANNON.Quaternion();
  pegQuat.setFromAxisAngle(new CANNON.Vec3(1, 0, 0), Math.PI / 2);

  for (let r = 0; r < NUM_ROWS; r++) {
    for (const { x, y } of pegPositionsForRow(r)) {
      const body = new CANNON.Body({ mass: 0, material: staticMaterial });
      body.addShape(pegShape, new CANNON.Vec3(), pegQuat);
      body.position.set(x, y, 0);
      world.addBody(body);
    }
  }

  // Slot dividers
  const divShape = new CANNON.Box(new CANNON.Vec3(0.025, 0.5, 1.5));
  for (let i = 0; i <= NUM_SLOTS; i++) {
    const x = (i - NUM_SLOTS / 2) * SLOT_SPACING;
    const body = new CANNON.Body({ mass: 0, material: staticMaterial });
    body.addShape(divShape);
    body.position.set(x, SLOT_Y + 0.45, 0);
    world.addBody(body);
  }

  // Floor
  const floorBody = new CANNON.Body({ mass: 0, material: staticMaterial });
  floorBody.addShape(new CANNON.Plane());
  floorBody.quaternion.setFromAxisAngle(new CANNON.Vec3(1, 0, 0), -Math.PI / 2);
  floorBody.position.set(0, SLOT_Y - 0.55, 0);
  world.addBody(floorBody);

  // Marble — drop close to targetX with small seeded jitter
  const initX = targetX + (rng() - 0.5) * 0.3;
  const marbleBody = new CANNON.Body({
    mass: 1,
    material: marbleMaterial,
    linearDamping: 0.01,
    angularDamping: 0.6,
  });
  marbleBody.addShape(new CANNON.Sphere(MARBLE_RADIUS));
  marbleBody.position.set(initX, MARBLE_START_Y, 0);

  world.addBody(marbleBody);

  const DT = 1 / 120;
  const MAX_STEPS = 600; // 5 simulated seconds
  const VISUAL_EVERY = 2; // record at ~60 fps visual
  const frames = [];

  for (let i = 0; i < MAX_STEPS; i++) {
    // Apply gentle horizontal guidance toward target while marble is above slot area
    if (marbleBody.position.y > SLOT_Y + MARBLE_RADIUS * 2) {
      const dx = targetX - marbleBody.position.x;
      marbleBody.applyForce(new CANNON.Vec3(dx * GUIDE_FORCE, 0, 0));
    }

    // Manual 2D constraint: keep marble in xy plane
    marbleBody.velocity.z = 0;
    marbleBody.position.z = 0;
    marbleBody.angularVelocity.x = 0;
    marbleBody.angularVelocity.y = 0;

    world.step(DT);

    if (i % VISUAL_EVERY === 0) {
      frames.push({ x: marbleBody.position.x, y: marbleBody.position.y });
    }

    // Early exit: marble settled
    const speed = Math.sqrt(
      marbleBody.velocity.x ** 2 + marbleBody.velocity.y ** 2,
    );
    if (marbleBody.position.y < SLOT_Y + 0.1 && speed < 0.08 && i > 120) {
      break;
    }
  }

  return frames;
}

// ─── Texture helper ───────────────────────────────────────────────────────────
const loader = new THREE.TextureLoader();
function loadMarbleTexture(url, onLoad) {
  if (!url) { onLoad(null); return; }
  try {
    const canonical = /^https?:\/\//i.test(url)
      ? new URL(url).href
      : new URL(url, window.location.origin).href;
    loader.load(canonical, (tex) => {
      tex.colorSpace = THREE.SRGBColorSpace;
      onLoad(tex);
    }, undefined, () => onLoad(null));
  } catch {
    onLoad(null);
  }
}

// ─── Three.js scene ───────────────────────────────────────────────────────────
function buildScene() {
  const scene = new THREE.Scene();

  scene.add(new THREE.AmbientLight(0xffffff, 0.6));
  const key = new THREE.DirectionalLight(0xffffff, 1.2);
  key.position.set(3, 5, 4);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0x8899ff, 0.4);
  fill.position.set(-4, 2, 3);
  scene.add(fill);
  const rim = new THREE.PointLight(0xff6644, 0.5, 12);
  rim.position.set(0, SLOT_Y + 1, 3);
  scene.add(rim);

  const bgGeo = new THREE.PlaneGeometry(8.5, 10);
  const bgMat = new THREE.MeshStandardMaterial({ color: 0x0d0d1a, roughness: 0.9, metalness: 0.1 });
  const bg = new THREE.Mesh(bgGeo, bgMat);
  bg.position.z = -0.4;
  scene.add(bg);

  const pegGeo = new THREE.CylinderGeometry(PEG_RADIUS, PEG_RADIUS, 0.22, 12);
  const pegMat = new THREE.MeshStandardMaterial({ color: 0xaabbdd, metalness: 0.7, roughness: 0.3 });

  for (let r = 0; r < NUM_ROWS; r++) {
    for (const { x, y } of pegPositionsForRow(r)) {
      const peg = new THREE.Mesh(pegGeo, pegMat);
      peg.position.set(x, y, 0);
      peg.rotation.x = Math.PI / 2;
      scene.add(peg);
    }
  }

  const slotColors = [0x4455aa, 0x5566cc, 0x8844ee, 0xcc3399, 0x8844ee, 0x5566cc, 0x4455aa];
  const dividerGeo = new THREE.BoxGeometry(0.04, 0.9, 0.1);
  const dividerY = SLOT_Y + 0.45;

  for (let i = 0; i <= NUM_SLOTS; i++) {
    const x = (i - NUM_SLOTS / 2) * SLOT_SPACING;
    const mat = new THREE.MeshStandardMaterial({ color: 0x334466, roughness: 0.5 });
    const div = new THREE.Mesh(dividerGeo, mat);
    div.position.set(x, dividerY, 0);
    scene.add(div);
  }

  const floorGeo = new THREE.BoxGeometry(SLOT_SPACING - 0.06, 0.06, 0.15);
  const slotMeshes = [];

  for (let s = 0; s < NUM_SLOTS; s++) {
    const mat = new THREE.MeshStandardMaterial({
      color: slotColors[s],
      emissive: new THREE.Color(slotColors[s]),
      emissiveIntensity: 0.3,
      roughness: 0.4,
    });
    const floor = new THREE.Mesh(floorGeo, mat);
    floor.position.set(slotX(s), SLOT_Y - 0.4, 0);
    scene.add(floor);
    slotMeshes.push({ mesh: floor, mat });
  }

  return { scene, slotMeshes };
}

// ─── Hook ─────────────────────────────────────────────────────────────────────
export const PlinkoScene = {
  mounted() {
    const w = this.el.clientWidth || 400;
    const h = this.el.clientHeight || 600;

    this._renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    this._renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this._renderer.setSize(w, h, false);
    this._renderer.setClearColor(0x0d0d1a, 1);
    this.el.appendChild(this._renderer.domElement);

    this._camera = new THREE.PerspectiveCamera(46, w / h, 0.1, 50);
    this._camera.position.set(0, 0.5, 9.5);
    this._camera.lookAt(0, 0.5, 0);

    const { scene, slotMeshes } = buildScene();
    this._scene = scene;
    this._slotMeshes = slotMeshes;

    // Marble mesh
    const marbleGeo = new THREE.SphereGeometry(MARBLE_RADIUS, 40, 40);
    this._marbleMat = new THREE.MeshStandardMaterial({ color: 0x6b7280, roughness: 0.3, metalness: 0.1 });
    this._marble = new THREE.Mesh(marbleGeo, this._marbleMat);
    this._marble.position.set(0, MARBLE_START_Y, 0.25);
    this._scene.add(this._marble);

    this._mode = "idle"; // idle | replay | done
    this._replayFrames = null;
    this._replayStartTime = null;
    this._targetSlotId = null;
    this._lastTime = null;
    this._marbleRz = 0;
    this._prevFrameX = 0;

    this._onResize = () => this._resize();
    window.addEventListener("resize", this._onResize);

    this.handleEvent("plinko:drop", ({ slot, seed, texture_url }) => {
      this._startDrop(slot, seed, texture_url);
    });

    this._resize();
    this._loop();
  },

  destroyed() {
    if (this._raf) cancelAnimationFrame(this._raf);
    window.removeEventListener("resize", this._onResize);
    this._renderer?.dispose();
  },

  _resize() {
    const w = this.el.clientWidth || 400;
    const h = this.el.clientHeight || 600;
    this._renderer.setSize(w, h, false);
    this._camera.aspect = w / Math.max(h, 1);
    this._camera.updateProjectionMatrix();
  },

  _startDrop(targetSlot, seed, textureUrl) {
    this._mode = "simulating";
    this._targetSlotId = targetSlot;

    // Reset marble
    this._marble.position.set(0, MARBLE_START_Y, 0.25);
    this._marble.visible = true;
    this._marbleRz = 0;
    this._prevFrameX = 0;

    // Load texture while simulation runs (fast sync loop)
    loadMarbleTexture(textureUrl, (tex) => {
      if (tex) {
        this._marbleMat.map = tex;
        this._marbleMat.color.setHex(0xffffff);
      } else {
        this._marbleMat.map = null;
        this._marbleMat.color.setHex(0x9966ff);
      }
      this._marbleMat.needsUpdate = true;
    });

    // Run fast-forward physics simulation synchronously
    const frames = runSimulation(seed, targetSlot);
    this._replayFrames = frames;
    this._replayStartTime = null;
    this._mode = "replay";
  },

  _highlightSlot(slotId) {
    for (const { mat } of this._slotMeshes) {
      mat.emissiveIntensity = 0.3;
    }
    if (slotId >= 0 && slotId < this._slotMeshes.length) {
      this._slotMeshes[slotId].mat.emissiveIntensity = 1.2;
    }
  },

  _loop() {
    this._raf = requestAnimationFrame((ts) => {
      const dt = this._lastTime != null ? Math.min((ts - this._lastTime) / 1000, 0.1) : 0;
      this._lastTime = ts;

      if (this._mode === "idle") {
        this._marble.rotation.y += dt * 0.6;
      } else if (this._mode === "replay") {
        if (this._replayStartTime === null) this._replayStartTime = ts;

        const elapsed = ts - this._replayStartTime;
        // ~60fps recorded frames → each frame is ~16.67ms
        const frameIdx = Math.min(
          Math.floor(elapsed / (1000 / 60)),
          this._replayFrames.length - 1,
        );
        const frame = this._replayFrames[frameIdx];

        // Rolling rotation based on horizontal movement
        const dz = frame.x - this._prevFrameX;
        this._marbleRz -= dz * 3.0;
        this._prevFrameX = frame.x;

        this._marble.position.set(frame.x, frame.y, 0.25);
        this._marble.rotation.z = this._marbleRz;

        if (frameIdx >= this._replayFrames.length - 1) {
          this._mode = "done";
          this._highlightSlot(this._targetSlotId);
          this.pushEvent("plinko:done", {});
        }
      }

      this._renderer.render(this._scene, this._camera);
      this._loop();
    });
  },
};
