// Crate opening animation for a new blaster (preview video only).
// Loads build/preview/anim_crate.json (tools/lune/export_anim.luau): the Kenney
// weapon case (base + lid) and the blaster, rebuilt from the same parts the game
// would use. Every frame is a pure function of time t (window.renderFrame(t)),
// so tools/preview/render_anim.mjs can step it frame by frame. All effects have
// Roblox counterparts (ParticleEmitters, Beams, neon parts, lights, tweens,
// camera shake, a ScreenGui flash, Bloom / ColorCorrection).
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { ShaderPass } from "three/addons/postprocessing/ShaderPass.js";

const params = new URLSearchParams(location.search);
const W = Number(params.get("w") || 1920);
const H = Number(params.get("h") || 1080);
export const DURATION = 10;

// ---------------------------------------------------------------- small helpers
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const prog = (t, a, b) => clamp((t - a) / (b - a));
const easeOutCubic = (x) => 1 - Math.pow(1 - x, 3);
const easeInCubic = (x) => x * x * x;
const easeInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const easeOutBack = (x) => {
  const c1 = 1.9, c3 = c1 + 1;
  return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
};
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hexColor(hex, mult = 1) {
  const c = new THREE.Color();
  c.setRGB(parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, THREE.SRGBColorSpace);
  return c.multiplyScalar(mult);
}
function radialTexture(stops) {
  const s = 128;
  const cv = document.createElement("canvas");
  cv.width = cv.height = s;
  const g = cv.getContext("2d").createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  for (const [o, c] of stops) g.addColorStop(o, c);
  const ctx = cv.getContext("2d");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, s, s);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}
const softTex = radialTexture([[0, "rgba(255,255,255,1)"], [0.25, "rgba(255,255,255,0.8)"], [1, "rgba(255,255,255,0)"]]);
const ringTex = radialTexture([[0, "rgba(255,255,255,0)"], [0.72, "rgba(255,255,255,0)"], [0.9, "rgba(255,255,255,1)"], [1, "rgba(255,255,255,0)"]]);
// a four-point star for sparkles
const starTex = (() => {
  const s = 128;
  const cv = document.createElement("canvas");
  cv.width = cv.height = s;
  const ctx = cv.getContext("2d");
  const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  g.addColorStop(0, "rgba(255,255,255,1)");
  g.addColorStop(0.15, "rgba(255,255,255,0.6)");
  g.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, s, s);
  ctx.globalCompositeOperation = "lighter";
  for (const [w, h] of [[s, 6], [6, s]]) {
    const lg = ctx.createLinearGradient(w === s ? 0 : s / 2, w === s ? s / 2 : 0, w === s ? s : s / 2, w === s ? s / 2 : s);
    ctx.fillStyle = "rgba(255,255,255,0.9)";
    ctx.beginPath();
    ctx.ellipse(s / 2, s / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
})();

// ---------------------------------------------------------------- parts (same encoding as viewer.js)
const SHAPE_BLOCK = 0, SHAPE_BALL = 1, SHAPE_CYLINDER = 2, SHAPE_WEDGE = 3;
function wedgeGeometry() {
  const B0 = [-0.5, -0.5, -0.5], B1 = [0.5, -0.5, -0.5], B2 = [0.5, -0.5, 0.5], B3 = [-0.5, -0.5, 0.5];
  const T2 = [0.5, 0.5, 0.5], T3 = [-0.5, 0.5, 0.5];
  const tris = [[B0, B1, B2], [B0, B2, B3], [B3, B2, T2], [B3, T2, T3], [B0, T3, T2], [B0, T2, B1], [B0, B3, T3], [B1, T2, B2]];
  const pos = [];
  for (const t of tris) for (const v of t) pos.push(...v);
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}
const geometries = {
  [SHAPE_BLOCK]: new THREE.BoxGeometry(1, 1, 1),
  [SHAPE_BALL]: new THREE.SphereGeometry(0.5, 20, 14),
  [SHAPE_CYLINDER]: new THREE.CylinderGeometry(0.5, 0.5, 1, 24).rotateZ(-Math.PI / 2),
  [SHAPE_WEDGE]: wedgeGeometry(),
};
function kindOf(mat) {
  if (mat === "Neon") return "neon";
  if (mat === "Metal" || mat === "Foil" || mat === "DiamondPlate") return "metal";
  if (mat === "Glass") return "glass";
  return "standard";
}
// Builds a group of instanced meshes; returns { group, neonMaterials }.
function buildParts(parts, offset = new THREE.Vector3()) {
  const group = new THREE.Group();
  const buckets = new Map();
  for (const p of parts) {
    const [shape, sx, sy, sz, cf, color, mat, transparency] = p;
    if (transparency > 0.98 || Math.min(sx, sy, sz) < 1e-4) continue; // flat parts give NaN normals
    const kind = kindOf(mat);
    const tKey = Math.round(transparency * 10) / 10;
    const key = `${shape}|${kind}|${tKey}`;
    if (!buckets.has(key)) buckets.set(key, { shape, kind, t: tKey, items: [] });
    buckets.get(key).items.push({ sx, sy, sz, cf, color });
  }
  const neonMaterials = [];
  const m4 = new THREE.Matrix4();
  const sc = new THREE.Matrix4();
  for (const b of buckets.values()) {
    let material;
    if (b.kind === "neon") {
      material = new THREE.MeshBasicMaterial({ color: 0xffffff });
      neonMaterials.push(material);
    } else if (b.kind === "metal") material = new THREE.MeshStandardMaterial({ roughness: 0.35, metalness: 0.6 });
    else if (b.kind === "glass") material = new THREE.MeshStandardMaterial({ roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.4 });
    else material = new THREE.MeshStandardMaterial({ roughness: 0.78, metalness: 0.05 });
    if (b.t > 0.01) {
      material.transparent = true;
      material.opacity = Math.max(0.05, 1 - b.t);
      material.depthWrite = false;
    }
    const mesh = new THREE.InstancedMesh(geometries[b.shape], material, b.items.length);
    b.items.forEach((it, i) => {
      const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = it.cf;
      m4.set(r00, r01, r02, x + offset.x, r10, r11, r12, y + offset.y, r20, r21, r22, z + offset.z, 0, 0, 0, 1);
      sc.makeScale(it.sx, it.sy, it.sz);
      mesh.setMatrixAt(i, m4.clone().multiply(sc));
      mesh.setColorAt(i, hexColor(it.color, b.kind === "neon" ? 2.2 : 1));
    });
    mesh.castShadow = b.kind !== "neon";
    mesh.receiveShadow = b.kind !== "neon";
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    group.add(mesh);
  }
  return { group, neonMaterials };
}

// ---------------------------------------------------------------- additive particle layers
// A point layer: per particle position, size (world units) and rgba; rebuilt every frame.
class PointLayer {
  constructor(max, tex, camera) {
    this.max = max;
    this.geo = new THREE.BufferGeometry();
    this.pos = new Float32Array(max * 3);
    this.size = new Float32Array(max);
    this.rgba = new Float32Array(max * 4);
    this.geo.setAttribute("position", new THREE.BufferAttribute(this.pos, 3));
    this.geo.setAttribute("size", new THREE.BufferAttribute(this.size, 1));
    this.geo.setAttribute("rgba", new THREE.BufferAttribute(this.rgba, 4));
    this.mat = new THREE.ShaderMaterial({
      uniforms: { tex: { value: tex }, scale: { value: 1 } },
      vertexShader: `attribute float size; attribute vec4 rgba; varying vec4 vC; uniform float scale;
        void main(){ vC = rgba; vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_PointSize = size * scale / -mv.z; gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform sampler2D tex; varying vec4 vC;
        void main(){ vec4 t = texture2D(tex, gl_PointCoord); gl_FragColor = vec4(vC.rgb * vC.a * t.a, 1.0); }`,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      transparent: true,
    });
    this.points = new THREE.Points(this.geo, this.mat);
    this.points.frustumCulled = false;
    this.camera = camera;
    this.n = 0;
  }
  begin() {
    this.n = 0;
    this.mat.uniforms.scale.value = H / (2 * Math.tan(THREE.MathUtils.degToRad(this.camera.fov) / 2));
  }
  add(x, y, z, size, color, alpha) {
    if (this.n >= this.max || alpha <= 0.001) return;
    const i = this.n++;
    this.pos[i * 3] = x;
    this.pos[i * 3 + 1] = y;
    this.pos[i * 3 + 2] = z;
    this.size[i] = size;
    this.rgba[i * 4] = color.r;
    this.rgba[i * 4 + 1] = color.g;
    this.rgba[i * 4 + 2] = color.b;
    this.rgba[i * 4 + 3] = alpha;
  }
  end() {
    this.geo.setDrawRange(0, this.n);
    for (const k of ["position", "size", "rgba"]) this.geo.attributes[k].needsUpdate = true;
  }
}

// Streaks: camera-facing quads from a head to a tail point, bright head, fading tail.
class StreakLayer {
  constructor(max, camera) {
    this.max = max;
    this.camera = camera;
    this.geo = new THREE.BufferGeometry();
    this.pos = new Float32Array(max * 4 * 3);
    this.col = new Float32Array(max * 4 * 4);
    const idx = [];
    for (let i = 0; i < max; i++) idx.push(i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3);
    this.geo.setIndex(idx);
    this.geo.setAttribute("position", new THREE.BufferAttribute(this.pos, 3));
    this.geo.setAttribute("rgba", new THREE.BufferAttribute(this.col, 4));
    this.mat = new THREE.ShaderMaterial({
      vertexShader: `attribute vec4 rgba; varying vec4 vC; void main(){ vC = rgba; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `varying vec4 vC; void main(){ gl_FragColor = vec4(vC.rgb * vC.a, 1.0); }`,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      transparent: true,
      side: THREE.DoubleSide,
    });
    this.mesh = new THREE.Mesh(this.geo, this.mat);
    this.mesh.frustumCulled = false;
    this.n = 0;
    this.tmp = [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()];
  }
  begin() {
    this.n = 0;
  }
  add(head, tail, width, color, alpha) {
    if (this.n >= this.max || alpha <= 0.001) return;
    const [d, v, s] = this.tmp;
    d.subVectors(head, tail);
    v.subVectors(this.camera.position, head);
    s.crossVectors(d, v);
    if (s.lengthSq() < 1e-10) return;
    s.normalize();
    const i = this.n++;
    const pts = [
      [head.x + s.x * width, head.y + s.y * width, head.z + s.z * width, 1],
      [head.x - s.x * width, head.y - s.y * width, head.z - s.z * width, 1],
      [tail.x - s.x * width * 0.25, tail.y - s.y * width * 0.25, tail.z - s.z * width * 0.25, 0],
      [tail.x + s.x * width * 0.25, tail.y + s.y * width * 0.25, tail.z + s.z * width * 0.25, 0],
    ];
    pts.forEach((p, k) => {
      this.pos.set(p.slice(0, 3), (i * 4 + k) * 3);
      this.col.set([color.r, color.g, color.b, alpha * p[3]], (i * 4 + k) * 4);
    });
  }
  end() {
    this.geo.setDrawRange(0, this.n * 6);
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.rgba.needsUpdate = true;
  }
}

// ---------------------------------------------------------------- scene
async function main() {
  await document.fonts.load('40px "Fredoka One"');
  await document.fonts.load('40px "Luckiest Guy"');
  await document.fonts.load('40px "Press Start 2P"');
  const data = await fetch("/scenes/anim_crate.json").then((r) => r.json());
  const meta = data.meta;
  const glow = hexColor(meta.glow);
  const body = hexColor(meta.body);
  const glowHot = glow.clone().lerp(new THREE.Color(1, 1, 1), 0.45);
  const white = new THREE.Color(1, 1, 1);
  const css = document.documentElement.style;
  css.setProperty("--glow", "#" + meta.glow);
  css.setProperty("--light", "#" + meta.glow);
  css.setProperty("--deep", "#" + meta.body);
  document.getElementById("rarity").textContent = meta.rarity;
  document.getElementById("name").textContent = meta.name;
  document.getElementById("level").textContent = "LV " + meta.level;

  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(W, H);
  renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  const stage = document.getElementById("stage");
  stage.style.width = W + "px";
  stage.style.height = H + "px";
  stage.prepend(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(42, W / H, 0.1, 500);

  // backdrop: a dark sphere, the rarity color low on the horizon
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(200, 32, 16),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      uniforms: { glow: { value: body.clone().multiplyScalar(0.3) }, pulse: { value: 0 } },
      vertexShader: `varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `uniform vec3 glow; uniform float pulse; varying vec3 vP;
        void main(){ float h = vP.y; vec3 top = vec3(0.012, 0.01, 0.03); vec3 mid = glow * (0.16 + 0.45 * pulse);
          vec3 c = mix(mid, top, smoothstep(-0.05, 0.55, h)); c = mix(c, vec3(0.0), smoothstep(-0.05, -0.4, h));
          gl_FragColor = vec4(c, 1.0); }`,
    }),
  );
  scene.add(sky);
  // far stars
  {
    const r = rng(7);
    const g = new THREE.BufferGeometry();
    const p = [];
    for (let i = 0; i < 500; i++) {
      const th = r() * Math.PI * 2, ph = Math.acos(r() * 0.9);
      p.push(Math.sin(ph) * Math.cos(th) * 150, Math.cos(ph) * 150 - 10, Math.sin(ph) * Math.sin(th) * 150);
    }
    g.setAttribute("position", new THREE.Float32BufferAttribute(p, 3));
    scene.add(new THREE.Points(g, new THREE.PointsMaterial({ color: 0x8890b0, size: 0.6, sizeAttenuation: true, transparent: true, opacity: 0.7 })));
  }

  // floor and a hexagonal stage with a glowing ring
  const floor = new THREE.Mesh(new THREE.CircleGeometry(60, 64).rotateX(-Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0x07070b, roughness: 0.42, metalness: 0.35 }));
  floor.position.y = -0.6;
  floor.receiveShadow = true;
  scene.add(floor);
  const platform = new THREE.Mesh(new THREE.CylinderGeometry(7.2, 7.6, 0.6, 6), new THREE.MeshStandardMaterial({ color: 0x1a1a24, roughness: 0.55, metalness: 0.35 }));
  platform.position.y = -0.3;
  platform.rotation.y = Math.PI / 6;
  platform.receiveShadow = true;
  scene.add(platform);
  const ringMat = new THREE.MeshBasicMaterial({ color: glow.clone().multiplyScalar(1.6) });
  const ring = new THREE.Mesh(new THREE.TorusGeometry(7.3, 0.07, 8, 6).rotateX(Math.PI / 2), ringMat);
  ring.rotation.y = Math.PI / 6;
  ring.position.y = 0.0;
  scene.add(ring);
  const innerRing = new THREE.Mesh(new THREE.TorusGeometry(5.2, 0.04, 8, 64).rotateX(Math.PI / 2), ringMat);
  innerRing.position.y = 0.01;
  scene.add(innerRing);

  // lights
  scene.add(new THREE.AmbientLight(0x707080, 0.5));
  scene.add(new THREE.HemisphereLight(0x9a9ab0, 0x101014, 0.55));
  const key = new THREE.DirectionalLight(0xfff2ea, 1.8);
  key.position.set(14, 22, 12);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  for (const k of ["left", "bottom"]) key.shadow.camera[k] = -14;
  for (const k of ["right", "top"]) key.shadow.camera[k] = 14;
  key.shadow.bias = -0.0005;
  scene.add(key);
  const rim = new THREE.DirectionalLight(glow, 1.3);
  rim.position.set(-14, 9, -10);
  scene.add(rim);
  const coreLight = new THREE.PointLight(glow, 0, 30, 1.6);
  coreLight.position.set(0, 2.2, 0);
  scene.add(coreLight);
  const gunLight = new THREE.PointLight(glow, 0, 22, 1.5);
  scene.add(gunLight);

  // the crate: base and lid (the lid on a hinge along its back edge)
  const lift = new THREE.Vector3(0, 0.14, 0); // Kenney's case reaches 0.02 m below its origin
  const crate = new THREE.Group();
  scene.add(crate);
  const base = buildParts(data.base.parts, lift);
  crate.add(base.group);
  const hinge = new THREE.Group();
  hinge.position.set(meta.crate.hingeX, meta.crate.hingeY + lift.y, 0);
  crate.add(hinge);
  const lid = buildParts(data.lid.parts, new THREE.Vector3(-meta.crate.hingeX, lift.y - meta.crate.hingeY - lift.y, 0));
  hinge.add(lid.group);
  // a glowing seam between base and lid, and the light inside
  const seamMat = new THREE.MeshBasicMaterial({ color: glowHot.clone(), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  const seam = new THREE.Mesh(new THREE.BoxGeometry(meta.crate.width + 0.08, 0.1, meta.crate.length + 0.08), seamMat);
  seam.position.y = meta.crate.hingeY + lift.y + 0.02;
  crate.add(seam);
  const insideMat = new THREE.MeshBasicMaterial({ color: glowHot.clone().multiplyScalar(2.5), transparent: true, opacity: 0, depthWrite: false });
  const inside = new THREE.Mesh(new THREE.BoxGeometry(meta.crate.width * 0.82, 0.05, meta.crate.length * 0.86), insideMat);
  inside.position.y = meta.crate.hingeY + lift.y - 0.05;
  crate.add(inside);

  // the blaster, centered on its bounding box
  const gunPivot = new THREE.Group();
  scene.add(gunPivot);
  const gun = buildParts(data.gun.parts);
  gunPivot.add(gun.group);

  // aura behind the gun and the god rays
  const aura = new THREE.Sprite(new THREE.SpriteMaterial({ map: softTex, color: glow, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: 0 }));
  scene.add(aura);
  const rays = (() => {
    const n = 18, pos = [], col = [], r = rng(3);
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + r() * 0.15, w = 0.035 + r() * 0.05, len = 0.7 + r() * 0.5;
      pos.push(0, 0, 0, Math.cos(a - w) * len, Math.sin(a - w) * len, 0, Math.cos(a + w) * len, Math.sin(a + w) * len, 0);
      col.push(1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    // per vertex alpha in the 4th component of a vec4 color
    const c4 = [];
    for (let i = 0; i < n; i++) c4.push(1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0);
    g.setAttribute("rgba", new THREE.Float32BufferAttribute(c4, 4));
    const m = new THREE.ShaderMaterial({
      uniforms: { color: { value: glow.clone() }, alpha: { value: 0 } },
      vertexShader: `attribute vec4 rgba; varying float vA; void main(){ vA = rgba.a; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `uniform vec3 color; uniform float alpha; varying float vA; void main(){ gl_FragColor = vec4(color * vA * vA * alpha, 1.0); }`,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      transparent: true,
      side: THREE.DoubleSide,
    });
    const mesh = new THREE.Mesh(g, m);
    mesh.frustumCulled = false;
    return mesh;
  })();
  scene.add(rays);

  // light pillar (two layers)
  function pillarLayer(radius, strength) {
    const m = new THREE.ShaderMaterial({
      uniforms: { color: { value: glowHot.clone() }, alpha: { value: 0 }, strength: { value: strength } },
      vertexShader: `varying vec2 vUv; varying vec3 vN; varying vec3 vV;
        void main(){ vUv = uv; vec4 mv = modelViewMatrix * vec4(position,1.0); vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform vec3 color; uniform float alpha; uniform float strength; varying vec2 vUv; varying vec3 vN; varying vec3 vV;
        void main(){ float f = pow(abs(dot(vN, vV)), 1.6); float fade = pow(1.0 - vUv.y, 1.4);
          gl_FragColor = vec4(color * f * fade * alpha * strength, 1.0); }`,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      transparent: true,
      side: THREE.DoubleSide,
    });
    const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius * 1.15, 1, 48, 1, true).translate(0, 0.5, 0), m);
    mesh.frustumCulled = false;
    scene.add(mesh);
    return mesh;
  }
  const pillarCore = pillarLayer(0.8, 2.2);
  const pillarWide = pillarLayer(2.2, 0.9);

  // floor shockwaves
  function shockwave() {
    const m = new THREE.MeshBasicMaterial({ map: ringTex, color: glowHot.clone(), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2).rotateX(-Math.PI / 2), m);
    mesh.position.y = 0.05;
    scene.add(mesh);
    return mesh;
  }
  const waveA = shockwave(), waveB = shockwave(), waveC = shockwave();
  // a vertical ring around the burst (a camera facing ring)
  const burstRing = new THREE.Sprite(new THREE.SpriteMaterial({ map: ringTex, color: glowHot.clone(), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: 0 }));
  scene.add(burstRing);

  // flying crystal shards
  const shardGeo = new THREE.OctahedronGeometry(1, 0).scale(0.55, 1.4, 0.55);
  const shardMat = new THREE.MeshBasicMaterial({ color: glow.clone().multiplyScalar(1.8) });
  const shards = [];
  {
    const r = rng(11);
    for (let i = 0; i < 34; i++) {
      const m = new THREE.Mesh(shardGeo, shardMat);
      scene.add(m);
      const a = r() * Math.PI * 2, up = 0.5 + r() * 0.9;
      shards.push({ mesh: m, dir: new THREE.Vector3(Math.cos(a), up, Math.sin(a)).normalize(), speed: 9 + r() * 10, spin: new THREE.Vector3(r() * 12, r() * 12, r() * 12), size: 0.12 + r() * 0.18, delay: r() * 0.08 });
    }
  }

  const points = new PointLayer(6000, softTex, camera);
  const stars = new PointLayer(1200, starTex, camera);
  const streaks = new StreakLayer(900, camera);
  scene.add(points.points, stars.points, streaks.mesh);

  // ---------------------------------------------------------------- post processing
  const composer = new EffectComposer(renderer);
  composer.setSize(W, H);
  composer.addPass(new RenderPass(scene, camera));
  // guard: a single NaN / infinite pixel would spread through the bloom blur and black out the frame
  composer.addPass(
    new ShaderPass({
      uniforms: { tDiffuse: { value: null } },
      vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `uniform sampler2D tDiffuse; varying vec2 vUv;
        void main(){ vec4 c = texture2D(tDiffuse, vUv);
          if (any(isnan(c)) || any(isinf(c))) c = vec4(0.0, 0.0, 0.0, 1.0);
          gl_FragColor = vec4(min(c.rgb, vec3(40.0)), c.a); }`,
    }),
  );
  const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), 0.85, 0.55, 0.74);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());
  const chroma = new ShaderPass({
    uniforms: { tDiffuse: { value: null }, amount: { value: 0 }, punch: { value: 0 } },
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `uniform sampler2D tDiffuse; uniform float amount; uniform float punch; varying vec2 vUv;
      void main(){ vec2 d = vUv - 0.5; float r = length(d);
        vec2 o = d * amount * (0.4 + r * 1.6);
        vec3 c = vec3(texture2D(tDiffuse, vUv + o).r, texture2D(tDiffuse, vUv).g, texture2D(tDiffuse, vUv - o).b);
        c = (c - 0.5) * (1.0 + 0.12 + punch * 0.25) + 0.5; c *= 1.0 + punch * 0.15;
        float l = dot(c, vec3(0.2126, 0.7152, 0.0722)); c = mix(vec3(l), c, 1.18);
        gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0); }`,
  });
  composer.addPass(chroma);

  // ---------------------------------------------------------------- the timeline
  const T_LAND = 0.55, T_BURST = 2.85, T_RISE_END = 4.7;
  const crateTop = meta.crate.top + lift.y;
  const gunRest = new THREE.Vector3(0, crateTop + 3.6, 0);
  const tmpA = new THREE.Vector3(), tmpB = new THREE.Vector3();

  function shakeAt(t) {
    let a = 0;
    for (const [t0, amp, k] of [[T_LAND, 0.35, 9], [T_BURST, 0.6, 6], [T_BURST - 0.25, 0.12, 12]]) if (t >= t0) a += amp * Math.exp(-(t - t0) * k);
    a += 0.05 * prog(t, 1.0, T_BURST) * (t < T_BURST ? 1 : 0); // the rumble before the burst
    return new THREE.Vector3(Math.sin(t * 71.3) + Math.sin(t * 43.1), Math.sin(t * 57.9) + Math.cos(t * 31.7), Math.cos(t * 63.2)).multiplyScalar(a * 0.5);
  }

  function cameraAt(t) {
    const keys = [
      [0.0, [17, 8.5, 12], [0, 2.0, 0], 44],
      [T_LAND, [15.5, 7.2, 10.5], [0, 1.6, 0], 42],
      [T_BURST - 0.05, [11.2, 5.2, 7.4], [0, 1.9, 0], 40],
      [T_BURST + 0.6, [13.6, 6.8, 9.2], [0, 3.6, 0], 44],
      [T_RISE_END, [11.2, 7.3, 6.8], [0, gunRest.y - 1.3, 0], 42],
      [DURATION, [9.0, 7.1, 5.2], [0, gunRest.y - 0.95, 0], 40],
    ];
    let i = 0;
    while (i < keys.length - 2 && t > keys[i + 1][0]) i++;
    const [t0, p0, l0, f0] = keys[i];
    const [t1, p1, l1, f1] = keys[i + 1];
    const u = easeInOut(prog(t, t0, t1));
    const pos = new THREE.Vector3(...p0).lerp(new THREE.Vector3(...p1), u);
    const look = new THREE.Vector3(...l0).lerp(new THREE.Vector3(...l1), u);
    return { pos, look, fov: lerp(f0, f1, u) };
  }

  function renderFrame(t) {
    // camera
    const cam = cameraAt(t);
    const shake = shakeAt(t);
    camera.position.copy(cam.pos).add(shake);
    camera.fov = cam.fov;
    camera.updateProjectionMatrix();
    camera.lookAt(cam.look.clone().add(shake.clone().multiplyScalar(0.4)));

    // crate drop, squash, rumble, hop
    const drop = prog(t, 0, T_LAND);
    let y = lerp(16, 0, easeInCubic(drop));
    let squash = 1;
    if (t > T_LAND) {
      const u = t - T_LAND;
      y = Math.max(0, Math.sin(Math.min(u / 0.32, 1) * Math.PI) * 0.55 * (u < 0.32 ? 1 : 0));
      squash = 1 - 0.14 * Math.exp(-u * 10) * Math.cos(u * 30);
    }
    const hop = prog(t, T_BURST - 0.3, T_BURST);
    if (hop > 0 && hop < 1) y += Math.sin(hop * Math.PI) * 0.7;
    const rumble = t > 1.0 && t < T_BURST ? Math.pow(prog(t, 1.0, T_BURST), 2) : 0;
    crate.position.set(0, y, 0);
    crate.scale.set(2 - squash, squash, 2 - squash);
    crate.rotation.set(Math.sin(t * 47) * 0.05 * rumble, 0, Math.sin(t * 53 + 1) * 0.06 * rumble);
    if (t < T_LAND) crate.rotation.z = (1 - drop) * 0.25;

    // lid: snaps open at the burst with an overshoot, settles
    const open = prog(t, T_BURST, T_BURST + 0.32);
    let lidAngle = open > 0 ? easeOutBack(open) * 1.95 : 0;
    lidAngle -= prog(t, T_BURST + 0.32, T_BURST + 1.2) * 0.12;
    if (t < T_BURST) lidAngle = Math.max(0, Math.sin(t * 38) * 0.04 * rumble); // rattling
    hinge.rotation.z = lidAngle;

    // seam and inside glow
    const charge = prog(t, 1.0, T_BURST);
    seamMat.opacity = t < T_BURST ? 0.15 + 0.85 * charge * (0.75 + 0.25 * Math.sin(t * 40)) : 0;
    insideMat.opacity = t >= T_BURST ? 0.75 - prog(t, T_BURST + 1.5, T_BURST + 3) * 0.4 : 0;
    coreLight.intensity = t < T_BURST ? charge * 26 : 60 * Math.exp(-(t - T_BURST) * 3) + 10;
    sky.material.uniforms.pulse.value = (t < T_BURST ? charge * 0.3 : 0.6 * Math.exp(-(t - T_BURST) * 1.5) + 0.12) * (1 + 0.1 * Math.sin(t * 3));
    ringMat.color.copy(glow).multiplyScalar(1.2 + 2.5 * Math.exp(-Math.abs(t - T_LAND) * 8) + 3 * (t > T_BURST ? Math.exp(-(t - T_BURST) * 3) : 0) + charge * 0.8);

    // gun: hidden inside, rises in the light, spins, then floats at the hero angle
    const rise = prog(t, T_BURST + 0.05, T_RISE_END);
    gunPivot.visible = t > T_BURST + 0.02;
    const bob = Math.sin((t - T_RISE_END) * 2.1) * 0.16 * prog(t, T_RISE_END - 0.5, T_RISE_END + 0.5);
    gunPivot.position.set(0, lerp(crateTop - 1.2, gunRest.y, easeOutCubic(rise)) + bob, 0);
    const spin = (1 - easeOutCubic(rise)) * Math.PI * 2 * 2.5;
    // the hero angle: side on to the camera, the barrel to the right, turned a little toward us
    gunPivot.rotation.set(0.06 * Math.sin(t * 1.3), -0.32 + spin + 0.1 * Math.sin(t * 0.9), 0.05 * Math.sin(t * 1.7));
    const s = lerp(0.35, 1, easeOutCubic(prog(t, T_BURST, T_BURST + 1.0)));
    gunPivot.scale.setScalar(s);
    const gunGlow = 1 + 0.7 * Math.exp(-Math.max(0, t - T_BURST - 0.3) * 2.2);
    for (const m of gun.neonMaterials) m.color.setScalar(gunGlow);
    gunLight.position.copy(gunPivot.position).add(new THREE.Vector3(2.5, 1.2, 1.5));
    gunLight.intensity = t > T_BURST ? 14 + 4 * Math.sin(t * 4) : 0;

    // aura and god rays behind the gun
    const behind = tmpA.subVectors(gunPivot.position, camera.position).normalize();
    aura.position.copy(gunPivot.position).addScaledVector(behind, 2.5);
    const auraIn = prog(t, T_BURST, T_BURST + 0.4);
    aura.material.opacity = auraIn * (0.28 + 0.06 * Math.sin(t * 5));
    aura.scale.setScalar(15 + 2 * Math.sin(t * 3));
    rays.position.copy(gunPivot.position).addScaledVector(behind, 4);
    rays.quaternion.copy(camera.quaternion);
    rays.rotateZ(t * 0.35);
    const raysIn = easeOutCubic(prog(t, T_BURST, T_BURST + 0.35));
    rays.scale.setScalar(lerp(2, 19, raysIn));
    rays.material.uniforms.alpha.value = raysIn * (0.32 - 0.2 * prog(t, T_BURST + 0.5, T_BURST + 2)) * (0.9 + 0.1 * Math.sin(t * 7));

    // light pillar
    const pIn = easeOutCubic(prog(t, T_BURST, T_BURST + 0.18));
    const pOut = 1 - prog(t, T_BURST + 0.35, T_BURST + 1.5);
    for (const [m, w] of [[pillarCore, 1], [pillarWide, 1]]) {
      m.visible = t >= T_BURST && pIn * pOut > 0.001; // a zero-height pillar has NaN normals
      if (!m.visible) continue;
      m.position.set(0, crateTop - 0.6, 0);
      m.scale.set(w * (1 + 0.6 * Math.exp(-(t - T_BURST) * 5)), 34 * pIn, w * (1 + 0.6 * Math.exp(-(t - T_BURST) * 5)));
      m.material.uniforms.alpha.value = t >= T_BURST ? pIn * pOut * 0.6 * (0.85 + 0.15 * Math.sin(t * 30)) : 0;
    }

    // shockwaves: landing, burst, echo
    for (const [w, t0, size, dur] of [[waveA, T_LAND, 14, 0.7], [waveB, T_BURST, 26, 0.9], [waveC, T_BURST + 0.12, 18, 1.1]]) {
      const u = prog(t, t0, t0 + dur);
      w.visible = t >= t0 && u < 1;
      w.scale.setScalar(lerp(1.5, size, easeOutCubic(u)));
      w.material.opacity = (1 - u) * 1.4;
    }
    {
      const u = prog(t, T_BURST, T_BURST + 0.55);
      burstRing.visible = t >= T_BURST && u < 1;
      burstRing.position.set(0, crateTop + 0.5, 0);
      burstRing.scale.setScalar(lerp(1, 22, easeOutCubic(u)));
      burstRing.material.opacity = (1 - u) * 1.2;
    }

    // shards fly out of the case
    for (const sh of shards) {
      const a = t - T_BURST - sh.delay;
      sh.mesh.visible = a > 0 && a < 1.6;
      if (!sh.mesh.visible) continue;
      const p = sh.mesh.position;
      p.set(0, crateTop, 0).addScaledVector(sh.dir, sh.speed * a);
      p.y -= 9 * a * a;
      sh.mesh.rotation.set(sh.spin.x * a, sh.spin.y * a, sh.spin.z * a);
      sh.mesh.scale.setScalar(sh.size * (1 - prog(a, 1.0, 1.6)) * 2.2);
    }

    // particles
    points.begin();
    stars.begin();
    streaks.begin();
    // landing dust
    {
      const r = rng(21);
      for (let i = 0; i < 70; i++) {
        const a = r() * Math.PI * 2, sp = 2 + r() * 5, life = 0.7 + r() * 0.6;
        const u = (t - T_LAND) / life;
        if (u < 0 || u > 1) continue;
        const d = sp * easeOutCubic(u) * life;
        const x = Math.cos(a) * (3 + d), z = Math.sin(a) * (2 + d);
        points.add(x, 0.3 + u * 1.2 * r(), z, 1.6 + u * 2.5, new THREE.Color(0.55, 0.5, 0.65), (1 - u) * 0.12);
      }
    }
    // energy pulled into the case while it charges
    {
      const r = rng(33);
      for (let i = 0; i < 260; i++) {
        const ts = 0.9 + r() * (T_BURST - 1.05), dur = 0.55 + r() * 0.4;
        const u = (t - ts) / dur;
        const th0 = r() * Math.PI * 2, ph = Math.acos(r() * 1.6 - 0.6), R = 7 + r() * 5;
        if (u < 0 || u > 1 || t > T_BURST) continue;
        const k = Math.pow(1 - u, 1.7);
        const th = th0 + u * 2.4;
        const head = tmpA.set(Math.sin(ph) * Math.cos(th) * R * k, 1.8 + Math.cos(ph) * R * k * 0.8, Math.sin(ph) * Math.sin(th) * R * k);
        const k2 = Math.pow(1 - Math.max(0, u - 0.06), 1.7);
        const th2 = th0 + (u - 0.06) * 2.4;
        const tail = tmpB.set(Math.sin(ph) * Math.cos(th2) * R * k2, 1.8 + Math.cos(ph) * R * k2 * 0.8, Math.sin(ph) * Math.sin(th2) * R * k2);
        streaks.add(head, tail, 0.05, i % 3 ? glowHot : white, Math.sin(u * Math.PI) * 1.4);
      }
    }
    // the burst: sparks with gravity and trails
    {
      const r = rng(44);
      for (let i = 0; i < 420; i++) {
        const delay = r() * 0.12, life = 0.6 + r() * 1.1;
        const a = t - T_BURST - delay;
        const u = a / life;
        const ang = r() * Math.PI * 2, up = r() * 1.3 + 0.15, sp = 7 + r() * 16;
        if (u < 0 || u > 1) continue;
        const dir = new THREE.Vector3(Math.cos(ang), up, Math.sin(ang)).normalize();
        const drag = (x) => (1 - Math.exp(-x * 2.2)) / 2.2;
        const p = (x) => new THREE.Vector3(dir.x * sp * drag(x), crateTop + dir.y * sp * drag(x) - 4.5 * x * x, dir.z * sp * drag(x));
        const head = p(a), tail = p(Math.max(0, a - 0.045));
        streaks.add(head, tail, 0.045 + r() * 0.04, i % 4 === 0 ? white : glowHot, (1 - u) * 2.0);
      }
    }
    // a soft blast cloud
    {
      const r = rng(55);
      for (let i = 0; i < 60; i++) {
        const a = t - T_BURST, life = 0.5 + r() * 0.5;
        const u = a / life;
        if (u < 0 || u > 1) continue;
        const ang = r() * Math.PI * 2, el = r() * 1.2;
        const d = (2 + r() * 4) * easeOutCubic(u);
        points.add(Math.cos(ang) * d, crateTop + el * d, Math.sin(ang) * d, 3 + 5 * u, glow, (1 - u) * 0.3);
      }
    }
    // sparkles orbiting the gun and twinkling around it
    if (t > T_BURST) {
      const r = rng(66);
      const gp = gunPivot.position;
      const fadeIn = prog(t, T_BURST + 0.2, T_BURST + 0.8);
      for (let i = 0; i < 44; i++) {
        const ring = r() < 0.5 ? 1 : -1;
        const R = 4.6 + r() * 1.6, sp = (0.6 + r() * 0.8) * ring, ph = r() * Math.PI * 2, tilt = (r() - 0.5) * 0.9;
        const a = ph + t * sp;
        const x = Math.cos(a) * R, z = Math.sin(a) * R * 0.75, y = Math.sin(a * 1.3 + ph) * 0.7 + tilt * Math.cos(a) * R * 0.3;
        const tw = 0.5 + 0.5 * Math.sin(t * (6 + r() * 6) + ph * 3);
        // sparkles close to the camera would turn into big blurry stars: shrink and dim them
        const near = clamp(camera.position.distanceTo(tmpB.set(gp.x + x, gp.y + y, gp.z + z)) / 10, 0.25, 1);
        stars.add(gp.x + x, gp.y + y, gp.z + z, (0.3 + r() * 0.45) * near, i % 3 ? glowHot : white, fadeIn * (0.25 + 0.5 * tw) * near);
      }
      // glitter rising from the gun body
      for (let i = 0; i < 45; i++) {
        const life = 0.9 + r() * 0.9, t0 = T_BURST + 0.4 + r() * 8;
        const u = (t - t0) / life;
        const ox = (r() - 0.5) * 1.2, oz = (r() - 0.5) * 6, oy = (r() - 0.5) * 1.6;
        if (u < 0 || u > 1) continue;
        stars.add(gp.x + ox, gp.y + oy + 0.6 + u * 1.6, gp.z + oz, 0.18 + r() * 0.22, glowHot, Math.sin(u * Math.PI) * 0.6);
      }
    }
    // dust motes in the air
    {
      const r = rng(77);
      for (let i = 0; i < 90; i++) {
        const x = (r() - 0.5) * 40, z = (r() - 0.5) * 30 - 6, y0 = r() * 14;
        const y = ((y0 + t * (0.2 + r() * 0.4)) % 14) - 0.5;
        points.add(x, y, z, 0.12 + r() * 0.12, glow, 0.35 * (0.5 + 0.5 * Math.sin(t * 2 + i)));
      }
    }
    points.end();
    stars.end();
    streaks.end();

    // post: chromatic punch at the burst
    const kick = t >= T_BURST ? Math.exp(-(t - T_BURST) * 5) : 0;
    chroma.uniforms.amount.value = 0.006 + 0.03 * kick + 0.01 * Math.exp(-Math.abs(t - T_LAND) * 10);
    chroma.uniforms.punch.value = kick;
    bloom.strength = 0.8 + 0.6 * kick + 0.25 * charge * (t < T_BURST ? 1 : 0);

    // overlays: flash, title, fade
    const flash = t >= T_BURST ? Math.max(0, 1 - (t - T_BURST) / 0.2) : 0;
    document.getElementById("flash").style.opacity = String(Math.pow(flash, 2) * 0.7 + Math.exp(-Math.abs(t - T_LAND) * 18) * 0.08);
    const title = [["newTag", 4.95], ["rarity", 5.15], ["name", 5.55], ["level", 5.85]];
    for (const [id, t0] of title) {
      const u = prog(t, t0, t0 + 0.45);
      const el = document.getElementById(id);
      el.style.opacity = String(easeOutCubic(u));
      const sc = id === "rarity" ? lerp(2.4, 1, easeOutBack(u)) : lerp(0.6, 1, easeOutBack(u));
      el.style.transform = `translateY(${(1 - easeOutCubic(u)) * 30}px) scale(${sc * (id === "rarity" ? 1 + 0.03 * Math.sin(t * 4) : 1)})`;
    }
    document.getElementById("fade").style.opacity = String(prog(t, DURATION - 0.35, DURATION) * 0.9);

    composer.render();
    return true;
  }

  window.renderFrame = renderFrame;
  window.__duration = DURATION;
  renderFrame(Number(params.get("t") || 0));
  window.__ready = true;
}

main().catch((e) => {
  console.error(e);
  window.__error = String(e && e.stack ? e.stack : e);
});
