import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

const RADIUS = 0.55;

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

const configureMarbleTexture = (tex) => {
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.flipY = true;
  tex.wrapS = THREE.ClampToEdgeWrapping;
  tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.generateMipmaps = true;
};

export const MarblePreview = {
  mounted() {
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.el.innerHTML = "";
    this.el.appendChild(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(42, 1, 0.1, 50);
    this.camera.position.set(0, 0.35, 2.1);

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.minDistance = 1.2;
    this.controls.maxDistance = 4;

    const amb = new THREE.AmbientLight(0xffffff, 0.55);
    const dir = new THREE.DirectionalLight(0xffffff, 1.1);
    dir.position.set(2, 3, 2);
    this.scene.add(amb, dir);

    const geo = new THREE.SphereGeometry(RADIUS, 48, 48);
    const mat = new THREE.MeshStandardMaterial({ color: 0x6b7280, roughness: 0.35, metalness: 0.05 });
    this.mesh = new THREE.Mesh(geo, mat);
    this.scene.add(this.mesh);

    this._loader = new THREE.TextureLoader();
    this._frame = null;
    this._onResize = () => this.resize();
    window.addEventListener("resize", this._onResize);

    this.handleEvent("marble:preview", ({ texture_url }) => {
      this.applyTexture(texture_url);
    });

    this.resize();
    this.applyTexture(this.el.dataset.textureUrl);
    this.loop();
  },

  updated() {
    this.applyTexture(this.el.dataset.textureUrl);
    this.resize();
  },

  destroyed() {
    if (this._frame) cancelAnimationFrame(this._frame);
    window.removeEventListener("resize", this._onResize);
    this.controls?.dispose();
    this.renderer?.dispose();
  },

  resize() {
    const w = this.el.clientWidth || 280;
    const h = this.el.clientHeight || 200;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / Math.max(h, 1);
    this.camera.updateProjectionMatrix();
  },

  applyTexture(rawUrl) {
    const url = canonicalTextureUrl(rawUrl);
    if (!url) {
      this.mesh.material.map?.dispose();
      this.mesh.material.map = null;
      this.mesh.material.color.setHex(0x6b7280);
      this.mesh.material.needsUpdate = true;
      return;
    }

    this._loader.load(
      url,
      (tex) => {
        configureMarbleTexture(tex);
        if (this.mesh.material.map) this.mesh.material.map.dispose();
        this.mesh.material.map = tex;
        this.mesh.material.color.setHex(0xffffff);
        this.mesh.material.needsUpdate = true;
      },
      undefined,
      () => {
        this.mesh.material.map?.dispose();
        this.mesh.material.map = null;
        this.mesh.material.color.setHex(0x6b7280);
        this.mesh.material.needsUpdate = true;
      },
    );
  },

  loop() {
    this._frame = requestAnimationFrame(() => this.loop());
    this.controls?.update();
    this.renderer.render(this.scene, this.camera);
  },
};
