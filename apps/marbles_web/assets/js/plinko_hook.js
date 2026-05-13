import * as THREE from "three";

// ─── Board constants ──────────────────────────────────────────────────────────
const NUM_ROWS = 6;
const NUM_SLOTS = 7;
const SLOT_SPACING = 1.0;
const ROW_SPACING = 0.85;
const PEG_RADIUS = 0.07;
const PEG_HEIGHT = 0.22;
const MARBLE_RADIUS = 0.19;
const ROW_TOP_Y = 2.5;
const SLOT_Y = ROW_TOP_Y - NUM_ROWS * ROW_SPACING - 0.65;
const MARBLE_START_Y = ROW_TOP_Y + 1.4;

// Row r has (r + 3) pegs, centered at x = 0, spacing 1.0
function pegPositionsForRow(row) {
  const count = row + 3;
  const start = -((count - 1) / 2.0);
  return Array.from({ length: count }, (_, i) => ({
    x: start + i * SLOT_SPACING,
    y: ROW_TOP_Y - row * ROW_SPACING,
  }));
}

// Slot x centers: slot 0 = x = -3, slot 6 = x = 3
function slotX(slotId) {
  return (slotId - (NUM_SLOTS - 1) / 2) * SLOT_SPACING;
}

// ─── Path generation ──────────────────────────────────────────────────────────
// Generates a list of ±1 step decisions (right = +1, left = -1) such that
// the marble starts at x=0 and ends at slotX(targetSlot).
// Uses weighted randomness so path looks natural but always arrives correctly.
function generatePath(targetSlot) {
  let rightsLeft = targetSlot;          // rights needed to reach target slot
  let leftsLeft = NUM_ROWS - targetSlot; // lefts needed
  const steps = [];

  for (let i = 0; i < NUM_ROWS; i++) {
    const canRight = rightsLeft > 0;
    const canLeft = leftsLeft > 0;
    let goRight;

    if (canRight && canLeft) {
      // Weighted toward the correct direction but not fully deterministic
      const rightWeight = rightsLeft / (rightsLeft + leftsLeft);
      goRight = Math.random() < rightWeight;
    } else {
      goRight = canRight;
    }

    steps.push(goRight ? 1 : -1);
    if (goRight) rightsLeft--; else leftsLeft--;
  }

  return steps;
}

// Convert step decisions into world-space marble positions along the path.
// Returns array of {x, y} checkpoints the marble passes through.
function buildCheckpoints(steps) {
  const checkpoints = [{ x: 0, y: MARBLE_START_Y }];
  let x = 0;

  for (let r = 0; r < NUM_ROWS; r++) {
    const rowY = ROW_TOP_Y - r * ROW_SPACING;
    // Arrive just above peg
    checkpoints.push({ x, y: rowY + MARBLE_RADIUS + PEG_RADIUS + 0.05 });
    // Bounce: shift half a slot in the chosen direction
    x += steps[r] * 0.5;
    // Exit peg going down
    checkpoints.push({ x, y: rowY - MARBLE_RADIUS - PEG_RADIUS - 0.1 });
  }

  // Final fall into slot
  checkpoints.push({ x, y: SLOT_Y + MARBLE_RADIUS + 0.05 });
  checkpoints.push({ x, y: SLOT_Y - 0.15 });

  return checkpoints;
}

// ─── Texture helper ───────────────────────────────────────────────────────────
const loader = new THREE.TextureLoader();
function loadMarbleTexture(url, onLoad) {
  if (!url) { onLoad(null); return; }
  try {
    const canonical = /^https?:\/\//i.test(url)
      ? new URL(url).href
      : new URL(url, window.location.origin).href;

    loader.load(
      canonical,
      (tex) => {
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.flipY = true;
        onLoad(tex);
      },
      undefined,
      () => onLoad(null),
    );
  } catch {
    onLoad(null);
  }
}

// ─── Scene builder ────────────────────────────────────────────────────────────
function buildScene() {
  const scene = new THREE.Scene();

  // Lights
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

  // Board background plane
  const bgGeo = new THREE.PlaneGeometry(8.5, 10);
  const bgMat = new THREE.MeshStandardMaterial({
    color: 0x0d0d1a,
    roughness: 0.9,
    metalness: 0.1,
  });
  const bg = new THREE.Mesh(bgGeo, bgMat);
  bg.position.z = -0.4;
  scene.add(bg);

  // Pegs
  const pegGeo = new THREE.CylinderGeometry(PEG_RADIUS, PEG_RADIUS, PEG_HEIGHT, 12);
  const pegMat = new THREE.MeshStandardMaterial({ color: 0xaabbdd, metalness: 0.7, roughness: 0.3 });

  for (let r = 0; r < NUM_ROWS; r++) {
    for (const { x, y } of pegPositionsForRow(r)) {
      const peg = new THREE.Mesh(pegGeo, pegMat);
      peg.position.set(x, y, 0);
      peg.rotation.x = Math.PI / 2; // cylinder along z-axis (toward camera)
      scene.add(peg);
    }
  }

  // Slot dividers (thin vertical bars at bottom)
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

  // Slot floor indicators (colored bands)
  const floorGeo = new THREE.BoxGeometry(SLOT_SPACING - 0.06, 0.06, 0.15);

  for (let s = 0; s < NUM_SLOTS; s++) {
    const mat = new THREE.MeshStandardMaterial({
      color: slotColors[s],
      emissive: new THREE.Color(slotColors[s]),
      emissiveIntensity: 0.3,
      roughness: 0.4,
    });
    const floor = new THREE.Mesh(floorGeo, mat);
    floor.position.set(slotX(s), SLOT_Y - 0.4, 0);
    floor.userData.slotId = s;
    scene.add(floor);
  }

  return scene;
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

    this._scene = buildScene();

    // Marble mesh (added to scene, starts above board)
    const marbleGeo = new THREE.SphereGeometry(MARBLE_RADIUS, 40, 40);
    this._marbleMat = new THREE.MeshStandardMaterial({
      color: 0x6b7280,
      roughness: 0.3,
      metalness: 0.1,
    });
    this._marble = new THREE.Mesh(marbleGeo, this._marbleMat);
    this._marble.position.set(0, MARBLE_START_Y, 0.25);
    this._scene.add(this._marble);

    this._animState = "idle"; // idle | dropping | done
    this._animCheckpoints = null;
    this._animProgress = 0;
    this._animCheckpointIdx = 0;
    this._targetSlotId = null;

    this._onResize = () => this._resize();
    window.addEventListener("resize", this._onResize);

    this.handleEvent("plinko:drop", ({ slot, texture_url }) => {
      this._startDrop(slot, texture_url);
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

  _startDrop(targetSlot, textureUrl) {
    this._animState = "dropping";
    this._targetSlotId = targetSlot;

    const steps = generatePath(targetSlot);
    this._animCheckpoints = buildCheckpoints(steps);
    this._animCheckpointIdx = 0;
    this._animProgress = 0;
    this._lastTime = null;

    // Reset marble to start position
    this._marble.position.set(0, MARBLE_START_Y, 0.25);
    this._marble.visible = true;

    // Load texture if provided
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
  },

  _updateAnimation(dt) {
    if (this._animState !== "dropping") return;
    const checkpoints = this._animCheckpoints;
    if (!checkpoints || this._animCheckpointIdx >= checkpoints.length - 1) return;

    const i = this._animCheckpointIdx;
    const from = checkpoints[i];
    const to = checkpoints[i + 1];

    // Ease in-out per segment, faster in middle rows
    const segmentDuration = i === 0 ? 0.38 : i >= checkpoints.length - 3 ? 0.32 : 0.18;
    this._animProgress += dt / segmentDuration;

    if (this._animProgress >= 1.0) {
      this._animProgress = 0;
      this._animCheckpointIdx++;

      if (this._animCheckpointIdx >= checkpoints.length - 1) {
        // Snap to final position
        const last = checkpoints[checkpoints.length - 1];
        this._marble.position.set(last.x, last.y, 0.25);
        this._animState = "done";
        this._highlightSlot(this._targetSlotId);
        this.pushEvent("plinko:done", {});
        return;
      }
    }

    const t = easeInOut(this._animProgress);
    const x = from.x + (to.x - from.x) * t;
    const y = from.y + (to.y - from.y) * t;
    this._marble.position.set(x, y, 0.25);
    this._marble.rotation.z -= dt * 4.5 * (to.x - from.x > 0 ? 1 : -1);
  },

  _highlightSlot(slotId) {
    this._scene.traverse((obj) => {
      if (obj.userData.slotId === slotId) {
        obj.material.emissiveIntensity = 1.0;
      }
    });
  },

  _loop() {
    this._raf = requestAnimationFrame((ts) => {
      const dt = this._lastTime != null ? Math.min((ts - this._lastTime) / 1000, 0.1) : 0;
      this._lastTime = ts;

      if (this._animState === "idle") {
        this._marble.rotation.y += dt * 0.6;
      }

      this._updateAnimation(dt);

      this._renderer.render(this._scene, this._camera);
      this._loop();
    });
  },
};

function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
}
