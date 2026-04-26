import * as THREE from "three";
import * as CANNON from "cannon-es";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

const TRACK_GLB_URL = "/3d/tracks/savage_speedway_s1.glb";

const NEUTRAL_TINT = 0xffffff;
const NO_TEXTURE_COLOR = 0x6b7280;

/** Base sphere radius before sandbox scale (matches prior sandbox). */
const SANDBOX_BASE_SPHERE_RADIUS = 0.42;
/** Visual + physics sphere radius (8× smaller than previous sandbox). */
const SANDBOX_MARBLE_RADIUS = SANDBOX_BASE_SPHERE_RADIUS / 8;

const SANDBOX_MARBLE_LIMIT = 10;

const canonicalTextureUrl = (url) => {
  if (!url || typeof url !== "string") return null;
  try {
    if (/^https?:\/\//i.test(url)) {
      return new URL(url).href;
    }
    return new URL(url, window.location.origin).href;
  } catch {
    return url;
  }
};

/**
 * Client-side guard: first `limit` entries that resolve to a texture URL.
 * Server should already send only textured rows; keep in sync with
 * `MarblesWeb.Dev.SandboxLive.pick_textured_marbles_for_sandbox/2`.
 */
export function takeTexturedMarbleEntries(entries, limit) {
  if (!Array.isArray(entries) || !Number.isFinite(limit) || limit <= 0) {
    return [];
  }
  return entries
    .filter((e) => canonicalTextureUrl(e.texture_url))
    .slice(0, limit);
}

const decodeMarblesPayload = (b64) => {
  if (!b64 || typeof b64 !== "string") return [];
  try {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    const text = new TextDecoder("utf-8").decode(bytes);
    const data = JSON.parse(text);
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
};

const configureMarbleTexture = (tex) => {
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.flipY = true;
  tex.wrapS = THREE.ClampToEdgeWrapping;
  tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.generateMipmaps = true;
};

const fitTrackToScene = (root) => {
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
};

/**
 * Bird's-eye "top-left" of the track AABB in world XZ: minimum X, maximum Z.
 * Y is above the track roof so marbles drop onto the scene.
 */
const trackSpawnTopLeftWorld = (trackRoot, radius) => {
  trackRoot.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(trackRoot);
  const x = -12;
  const z = -2;
  const y = 50;
  return { x, y, z, box };
};

const fmt3 = (n) =>
  typeof n === "number" && Number.isFinite(n) ? n.toFixed(3) : "?";

const DevSandbox = {
  mounted() {
    this.animationFrame = null;
    this.lastStepTime = performance.now();
    this.trackRoot = null;
    this.world = null;
    this.textureCache = new Map();
    this.marbleRoots = [];
    this.marbleBodies = [];
    this.spawnAnchorWorld = null;
    this.cameraMode = "orbit";
    this.followMarbleIndex = 0;
    this._marblePos = new THREE.Vector3();
    this._velXZ = new THREE.Vector3();
    this._backXZ = new THREE.Vector3(0, 0, -1);
    this._desiredCam = new THREE.Vector3();
    this._followCamPos = new THREE.Vector3();
    this._followLook = new THREE.Vector3();
    this.resizeHandler = () => this.resize();
    this._onCycleCamera = () => this.cycleCameraMode();

    const rawEntries = decodeMarblesPayload(this.el.dataset.marblesB64);
    this.entries = takeTexturedMarbleEntries(rawEntries, SANDBOX_MARBLE_LIMIT);

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x080b12);

    const w = Math.max(this.el.clientWidth, 1);
    const h = Math.max(this.el.clientHeight, 1);
    this.camera = new THREE.PerspectiveCamera(55, w / h, 0.1, 250);
    this.camera.position.set(12, 10, 14);

    const ambient = new THREE.AmbientLight(0xffffff, 0.55);
    this.scene.add(ambient);
    const key = new THREE.DirectionalLight(0xffffff, 1.1);
    key.position.set(10, 20, 12);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x6b9cff, 0.35);
    rim.position.set(-12, 8, -10);
    this.scene.add(rim);

    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(80, 80),
      new THREE.MeshStandardMaterial({
        color: 0x0b1220,
        roughness: 0.96,
        metalness: 0.05,
      }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -1.2;
    this.scene.add(floor);

    const grid = new THREE.GridHelper(60, 60, 0x1e293b, 0x0f172a);
    grid.position.y = -1.19;
    this.scene.add(grid);

    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.resize();
    this.el.appendChild(this.renderer.domElement);

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.06;
    this.controls.target.set(0, 0.5, 0);

    this.gltfLoader = new GLTFLoader();
    this.textureLoader = new THREE.TextureLoader();
    this.gltfLoader.setCrossOrigin("anonymous");
    this.textureLoader.setCrossOrigin("anonymous");

    window.addEventListener("resize", this.resizeHandler);

    this.mountCameraHudUi();
    this.loadScene(this.entries);
  },

  mountCameraHudUi() {
    const wrap = document.createElement("div");
    wrap.style.cssText =
      "position:absolute;inset:0;pointer-events:none;z-index:10;font:12px/1.45 ui-monospace,monospace;";
    const hud = document.createElement("pre");
    hud.id = "dev-sandbox-camera-hud";
    hud.style.cssText =
      "position:absolute;top:8px;left:8px;margin:0;padding:8px 10px;background:rgba(0,0,0,0.58);color:#e2e8f0;border-radius:6px;pointer-events:none;white-space:pre;max-width:min(420px,92vw);";
    const btn = document.createElement("button");
    btn.type = "button";
    btn.id = "dev-sandbox-cycle-cam";
    btn.style.cssText =
      "position:absolute;bottom:10px;right:10px;pointer-events:auto;padding:8px 12px;border-radius:6px;background:#152238;color:#e2e8f0;border:1px solid #334155;cursor:pointer;font:inherit;";
    btn.addEventListener("click", this._onCycleCamera);
    wrap.appendChild(hud);
    wrap.appendChild(btn);
    this.el.appendChild(wrap);
    this.uiOverlay = wrap;
    this.cameraHudEl = hud;
    this.cycleCamBtn = btn;
    this.syncCycleCameraButtonLabel();
  },

  syncCycleCameraButtonLabel() {
    if (!this.cycleCamBtn) return;
    const n = this.marbleBodies.length;
    if (n === 0) {
      this.cycleCamBtn.textContent = "Cycle camera (no marbles)";
      this.cycleCamBtn.disabled = true;
      return;
    }
    this.cycleCamBtn.disabled = false;
    if (this.cameraMode === "orbit") {
      this.cycleCamBtn.textContent = "Cycle camera · Orbit → follow #1";
    } else {
      const next = this.followMarbleIndex + 1;
      if (next >= n) {
        this.cycleCamBtn.textContent = `Cycle camera · Marble ${this.followMarbleIndex + 1}/${n} → Orbit`;
      } else {
        this.cycleCamBtn.textContent = `Cycle camera · Marble ${this.followMarbleIndex + 1}/${n} → #${next + 1}`;
      }
    }
  },

  cycleCameraMode() {
    const n = this.marbleBodies.length;
    if (n === 0) return;
    if (this.cameraMode === "orbit") {
      this.cameraMode = "follow";
      this.followMarbleIndex = 0;
      this.controls.enabled = false;
      this.resetFollowSmoothing();
    } else {
      const next = this.followMarbleIndex + 1;
      if (next >= n) {
        this.cameraMode = "orbit";
        this.controls.enabled = true;
      } else {
        this.followMarbleIndex = next;
        this.resetFollowSmoothing();
      }
    }
    this.syncCycleCameraButtonLabel();
  },

  updateBackDirFromBody(body) {
    this._velXZ.set(body.velocity.x, 0, body.velocity.z);
    if (this._velXZ.lengthSq() > 0.0008) {
      this._velXZ.normalize();
      this._backXZ.copy(this._velXZ).multiplyScalar(-1);
    }
  },

  resetFollowSmoothing() {
    const body = this.marbleBodies[this.followMarbleIndex];
    if (!body) return;
    this.updateBackDirFromBody(body);
    this._marblePos.set(body.position.x, body.position.y, body.position.z);
    const height = Math.max(2.2, SANDBOX_MARBLE_RADIUS * 48);
    const behind = 1.15;
    this._desiredCam.copy(this._marblePos);
    this._desiredCam.y += height;
    this._desiredCam.addScaledVector(this._backXZ, behind);
    this._followCamPos.copy(this._desiredCam);
    this._followLook.copy(this._marblePos);
  },

  updateCameraHud() {
    if (!this.cameraHudEl || !this.camera) return;
    const p = this.camera.position;
    const t = this.controls.target;
    let modeLine = `mode    ${this.cameraMode}`;
    if (this.cameraMode === "follow" && this.marbleBodies.length > 0) {
      modeLine += ` · marble ${this.followMarbleIndex + 1}/${this.marbleBodies.length}`;
    }
    let spawnLine = "";
    if (this.spawnAnchorWorld) {
      const a = this.spawnAnchorWorld;
      spawnLine = `\nspawn   ${fmt3(a.x)} ${fmt3(a.y)} ${fmt3(a.z)}`;
    }
    this.cameraHudEl.textContent = `camera  ${fmt3(p.x)} ${fmt3(p.y)} ${fmt3(p.z)}
target  ${fmt3(t.x)} ${fmt3(t.y)} ${fmt3(t.z)}
${modeLine}${spawnLine}`;
  },

  destroyed() {
    window.removeEventListener("resize", this.resizeHandler);
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame);
    if (this.cycleCamBtn && this._onCycleCamera) {
      this.cycleCamBtn.removeEventListener("click", this._onCycleCamera);
    }
    if (this.uiOverlay?.parentNode === this.el) {
      this.el.removeChild(this.uiOverlay);
    }
    this.uiOverlay = null;
    this.cameraHudEl = null;
    this.cycleCamBtn = null;
    this.controls?.dispose();

    if (this.world) {
      while (this.world.bodies.length > 0) {
        this.world.removeBody(this.world.bodies[0]);
      }
      this.world = null;
    }

    for (const mesh of this.marbleRoots) {
      this.scene.remove(mesh);
      mesh.geometry?.dispose?.();
      const m = mesh.material;
      if (m) {
        if (m.map) m.map = null;
        m.dispose?.();
      }
    }
    this.marbleRoots = [];
    this.marbleBodies = [];

    if (this.trackRoot) {
      this.scene.remove(this.trackRoot);
      this.trackRoot.traverse((child) => {
        if (child.isMesh) {
          child.geometry?.dispose?.();
          const mat = child.material;
          if (Array.isArray(mat)) {
            mat.forEach((mm) => {
              mm.map?.dispose?.();
              mm?.dispose?.();
            });
          } else {
            mat.map?.dispose?.();
            mat?.dispose?.();
          }
        }
      });
      this.trackRoot = null;
    }

    for (const tex of this.textureCache.values()) {
      tex.dispose();
    }
    this.textureCache.clear();

    this.renderer?.dispose();
    if (this.renderer?.domElement?.parentNode === this.el) {
      this.el.removeChild(this.renderer.domElement);
    }
  },

  resize() {
    if (!this.renderer || !this.camera) return;
    const w = Math.max(this.el.clientWidth, 1);
    const h = Math.max(this.el.clientHeight, 1);
    this.renderer.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  },

  initPhysics() {
    const world = new CANNON.World();
    world.gravity.set(0, -14, 0);
    world.allowSleep = true;
    world.defaultContactMaterial.friction = 0.28;
    world.defaultContactMaterial.restitution = 0.12;

    const groundMat = new CANNON.Material("ground");
    const marbleMat = new CANNON.Material("marble");

    const groundBody = new CANNON.Body({ mass: 0, material: groundMat });
    groundBody.addShape(new CANNON.Plane());
    groundBody.quaternion.setFromEuler(-Math.PI / 2, 0, 0);
    groundBody.position.set(0, -1.2, 0);
    world.addBody(groundBody);

    world.addContactMaterial(
      new CANNON.ContactMaterial(marbleMat, groundMat, {
        friction: 0.45,
        restitution: 0.22,
      }),
    );
    world.addContactMaterial(
      new CANNON.ContactMaterial(marbleMat, marbleMat, {
        friction: 0.25,
        restitution: 0.42,
      }),
    );

    this.world = world;
    this.marblePhysMaterial = marbleMat;
  },

  async loadScene(entries) {
    await new Promise((resolve) => {
      this.gltfLoader.load(
        TRACK_GLB_URL,
        (gltf) => {
          const root = gltf.scene;
          fitTrackToScene(root);
          this.scene.add(root);
          this.trackRoot = root;
          resolve();
        },
        undefined,
        () => resolve(),
      );
    });

    const urls = [
      ...new Set(
        entries.map((e) => canonicalTextureUrl(e.texture_url)).filter(Boolean),
      ),
    ];

    await Promise.all(
      urls.map(
        (url) =>
          new Promise((resolve) => {
            if (this.textureCache.has(url)) {
              resolve();
              return;
            }
            this.textureLoader.load(
              url,
              (tex) => {
                configureMarbleTexture(tex);
                this.textureCache.set(url, tex);
                resolve();
              },
              undefined,
              () => resolve(),
            );
          }),
      ),
    );

    this.initPhysics();
    this.placePhysicsMarbles(entries);
    this.fitCameraToSpawn(entries.length);
    this.syncCycleCameraButtonLabel();
    this.loop();
  },

  fitCameraToSpawn(count) {
    const n = Math.max(1, count);
    const span = Math.max(8, n * SANDBOX_MARBLE_RADIUS * 14);
    this.camera.position.set(span * 0.85, span * 0.5, span * 0.75);
    this.controls.target.set(0, 0.15, 0);
    this.controls.update();
  },

  placePhysicsMarbles(entries) {
    const n = entries.length;
    if (n === 0 || !this.trackRoot || !this.world) return;

    const radius = SANDBOX_MARBLE_RADIUS;
    const anchor = trackSpawnTopLeftWorld(this.trackRoot, radius);
    this.spawnAnchorWorld = { x: anchor.x, y: anchor.y, z: anchor.z };
    const sep = radius * 2.8;

    entries.forEach((entry, i) => {
      const url = canonicalTextureUrl(entry.texture_url);
      const tex = url && this.textureCache.get(url);

      let mat;
      if (tex) {
        mat = new THREE.MeshBasicMaterial({
          map: tex,
          color: NEUTRAL_TINT,
        });
      } else {
        mat = new THREE.MeshStandardMaterial({
          color: NO_TEXTURE_COLOR,
          metalness: 0.15,
          roughness: 0.75,
        });
      }

      const mesh = new THREE.Mesh(
        new THREE.SphereGeometry(radius, 32, 32),
        mat,
      );

      const px = anchor.x + i * sep;
      const py = anchor.y;
      const pz = anchor.z;
      mesh.position.set(px, py, pz);

      const shape = new CANNON.Sphere(radius);
      const body = new CANNON.Body({
        mass: 0.35,
        shape,
        material: this.marblePhysMaterial,
        linearDamping: 0.08,
        angularDamping: 0.12,
      });
      body.position.set(px, py, pz);

      this.world.addBody(body);
      this.scene.add(mesh);
      this.marbleRoots.push(mesh);
      this.marbleBodies.push(body);
    });
  },

  loop() {
    this.animationFrame = requestAnimationFrame(() => this.loop());

    const now = performance.now();
    const dt = Math.min((now - this.lastStepTime) / 1000, 0.05);
    this.lastStepTime = now;
    if (this.world) {
      this.world.step(1 / 60, dt, 6);
    }

    for (let i = 0; i < this.marbleRoots.length; i++) {
      const mesh = this.marbleRoots[i];
      const body = this.marbleBodies[i];
      if (!mesh || !body) continue;
      mesh.position.copy(body.position);
      mesh.quaternion.copy(body.quaternion);
    }

    if (this.cameraMode === "follow" && this.controls) {
      const body = this.marbleBodies[this.followMarbleIndex];
      if (body) {
        this.updateBackDirFromBody(body);
        this._marblePos.set(body.position.x, body.position.y, body.position.z);
        const height = Math.max(2.2, SANDBOX_MARBLE_RADIUS * 48);
        const behind = 1.15;
        this._desiredCam.copy(this._marblePos);
        this._desiredCam.y += height;
        this._desiredCam.addScaledVector(this._backXZ, behind);
        const smooth = 1 - Math.exp(-5.2 * dt);
        this._followCamPos.lerp(this._desiredCam, smooth);
        this._followLook.lerp(this._marblePos, smooth);
        this.camera.position.copy(this._followCamPos);
        this.camera.lookAt(this._followLook);
        this.controls.target.copy(this._followLook);
      }
    } else {
      this.controls?.update();
    }

    this.updateCameraHud();
    this.renderer.render(this.scene, this.camera);
  },
};

export { DevSandbox };
