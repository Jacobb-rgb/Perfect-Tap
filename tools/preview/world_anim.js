// The world animations showreel (preview video only): golems hopping and
// jumping on equip, the blaster hit flash, the ore popping out of a rock, the
// sell cash burst. Loads build/preview/world_motion.json (or ?data=<name>: build/preview/<name>.json, e.g. golem_run)
// (tools/lune/export_world_motion.luau): static scenes, rigid groups and, per
// frame, the camera, the group matrices and every moving part, all computed
// by the game's own code in Lune. Every frame is a pure function of its index
// (window.renderFrame(t)), so tools/preview/render_world_anim.mjs can step it.
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { ShaderPass } from "three/addons/postprocessing/ShaderPass.js";

const params = new URLSearchParams(location.search);
const W = Number(params.get("w") || 1280);
const H = Number(params.get("h") || 720);

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
// Lune writes an empty table as {}: treat anything but an array as empty
const arr = (x) => (Array.isArray(x) ? x : []);

function srgb(hex, mult = 1) {
  const c = new THREE.Color();
  c.setRGB(parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, THREE.SRGBColorSpace);
  return c.multiplyScalar(mult);
}

// ---------------------------------------------------------------- parts (Export's encoding)
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
  if (mat === "Glass" || mat === "ForceField") return "glass";
  return "standard";
}
const NEON_BOOST = 1.45; // Neon a little over 1 so the bloom picks it up but keeps its hue
function matrixOf(cf, sx, sy, sz, out = new THREE.Matrix4()) {
  const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
  out.set(r00 * sx, r01 * sy, r02 * sz, x, r10 * sx, r11 * sy, r12 * sz, y, r20 * sx, r21 * sy, r22 * sz, z, 0, 0, 0, 1);
  return out;
}
// Instanced buckets for a static part list (by shape, look and transparency).
function buildParts(parts) {
  const group = new THREE.Group();
  const buckets = new Map();
  for (const p of parts) {
    const [shape, sx, sy, sz, cf, color, mat, transparency, , shadow] = p;
    if (transparency > 0.98 || Math.min(sx, sy, sz) < 1e-4) continue;
    const kind = kindOf(mat);
    const tKey = Math.round(transparency * 10) / 10;
    const key = `${shape}|${kind}|${tKey}|${shadow ? 1 : 0}`;
    if (!buckets.has(key)) buckets.set(key, { shape, kind, t: tKey, shadow, items: [] });
    buckets.get(key).items.push({ sx, sy, sz, cf, color });
  }
  const m4 = new THREE.Matrix4();
  for (const b of buckets.values()) {
    let material;
    if (b.kind === "neon") material = new THREE.MeshBasicMaterial({ color: 0xffffff });
    else if (b.kind === "metal") material = new THREE.MeshStandardMaterial({ roughness: 0.38, metalness: 0.55 });
    else if (b.kind === "glass") material = new THREE.MeshStandardMaterial({ roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.4, depthWrite: false });
    else material = new THREE.MeshStandardMaterial({ roughness: 0.8, metalness: 0.04 });
    if (b.t > 0.01) {
      material.transparent = true;
      material.opacity = Math.max(0.05, 1 - b.t);
      material.depthWrite = false;
    }
    const mesh = new THREE.InstancedMesh(geometries[b.shape], material, b.items.length);
    b.items.forEach((it, i) => {
      mesh.setMatrixAt(i, matrixOf(it.cf, it.sx, it.sy, it.sz, m4));
      mesh.setColorAt(i, srgb(it.color, b.kind === "neon" ? NEON_BOOST : 1));
    });
    mesh.castShadow = b.kind !== "neon" && b.shadow !== 0;
    mesh.receiveShadow = b.kind !== "neon";
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.frustumCulled = false;
    group.add(mesh);
  }
  return group;
}

// ---------------------------------------------------------------- the sky
function skyDome(top, horizon, ground) {
  return new THREE.Mesh(
    new THREE.SphereGeometry(900, 32, 16),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      uniforms: { top: { value: top }, horizon: { value: horizon }, ground: { value: ground } },
      vertexShader: `varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `uniform vec3 top; uniform vec3 horizon; uniform vec3 ground; varying vec3 vP;
        void main(){ float h = vP.y; vec3 c = mix(horizon, top, smoothstep(0.0, 0.55, h)); c = mix(c, ground, smoothstep(0.0, -0.25, h));
          gl_FragColor = vec4(c, 1.0); }`,
    }),
  );
}

// ---------------------------------------------------------------- main
async function main() {
  await document.fonts.load('40px "Fredoka One"');
  const dataName = (params.get("data") || "world_motion").replace(/[^a-z0-9_]/gi, "");
  const data = await fetch(`/scenes/${dataName}.json`).then((r) => r.json());
  const fps = data.fps;
  const frames = data.frames;

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
  const camera = new THREE.PerspectiveCamera(42, W / H, 0.1, 2000);

  // one root per static scene, each with its own light rig
  const looks = {
    day: {
      sky: skyDome(srgb("5f9be6"), srgb("ffd9b0"), srgb("8a7a66")),
      fog: new THREE.Fog(srgb("f2d9bf"), 90, 420),
      hemi: new THREE.HemisphereLight(srgb("cfe2ff"), srgb("8f7c62"), 1.25),
      ambient: new THREE.AmbientLight(srgb("ffffff"), 0.25),
      sun: new THREE.DirectionalLight(srgb("fff0dc"), 2.6),
      sunDir: new THREE.Vector3(-0.55, 0.62, 0.56).normalize(),
      pointScale: 3,
      exposure: 1.0,
    },
    mine: {
      sky: skyDome(srgb("05070d"), srgb("0b1420"), srgb("05070d")),
      fog: new THREE.Fog(srgb("0b1726"), 30, 110),
      hemi: new THREE.HemisphereLight(srgb("7fa6d8"), srgb("1a2430"), 0.9),
      ambient: new THREE.AmbientLight(srgb("9fb8ff"), 0.35),
      sun: new THREE.DirectionalLight(srgb("cfe0ff"), 1.0),
      sunDir: new THREE.Vector3(0.35, 0.85, 0.4).normalize(),
      pointScale: 9,
      exposure: 1.15,
    },
  };
  for (const look of Object.values(looks)) {
    look.sun.castShadow = true;
    look.sun.shadow.mapSize.set(2048, 2048);
    for (const k of ["left", "bottom"]) look.sun.shadow.camera[k] = -40;
    for (const k of ["right", "top"]) look.sun.shadow.camera[k] = 40;
    look.sun.shadow.camera.near = 1;
    look.sun.shadow.camera.far = 400;
    look.sun.shadow.bias = -0.0006;
    look.sun.shadow.normalBias = 0.03;
  }
  const roots = arr(data.scenes).map((s) => {
    const root = new THREE.Group();
    root.add(buildParts(arr(s.parts)));
    const look = looks[s.look] || looks.day;
    root.userData.look = look;
    for (const [x, y, z, color, range, brightness] of arr(s.lights)) {
      const pl = new THREE.PointLight(srgb(color), brightness * look.pointScale, range * 1.4, 1);
      pl.position.set(x, y, z);
      root.add(pl);
    }
    root.visible = false;
    scene.add(root);
    return root;
  });
  const lookRoots = {};
  for (const [name, look] of Object.entries(looks)) {
    const g = new THREE.Group();
    g.add(look.sky, look.hemi, look.ambient, look.sun, look.sun.target);
    g.visible = false;
    scene.add(g);
    lookRoots[name] = g;
  }

  // rigid groups (golems, rocks): local parts, a matrix per frame
  const groups = arr(data.groups).map((g) => {
    const holder = new THREE.Group();
    holder.matrixAutoUpdate = false;
    holder.add(buildParts(arr(g.parts)));
    holder.visible = false;
    scene.add(holder);
    return holder;
  });

  // moving parts: a pool of meshes, one material each
  const pool = [];
  function poolMesh(i) {
    while (pool.length <= i) {
      const standard = new THREE.MeshStandardMaterial({ roughness: 0.75, metalness: 0.05 });
      const neon = new THREE.MeshBasicMaterial({ color: 0xffffff });
      const mesh = new THREE.Mesh(geometries[SHAPE_BLOCK], standard);
      mesh.matrixAutoUpdate = false;
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      mesh.frustumCulled = false;
      mesh.userData = { standard, neon };
      mesh.visible = false;
      scene.add(mesh);
      pool.push(mesh);
    }
    return pool[i];
  }

  // ---------------------------------------------------------------- post
  const composer = new EffectComposer(renderer);
  composer.setSize(W, H);
  composer.addPass(new RenderPass(scene, camera));
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
  const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), 0.55, 0.42, 0.9);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());

  // ---------------------------------------------------------------- overlays
  const titleBox = document.querySelector("#title .box");
  const titleMain = document.querySelector("#title .main");
  const titleSub = document.querySelector("#title .sub");
  const slow = document.getElementById("slow");
  const fade = document.getElementById("fade");
  const popupLayer = document.getElementById("popups");
  // where each segment starts (frame index)
  const segStart = {};
  frames.forEach((f, i) => {
    if (segStart[f.seg] === undefined) segStart[f.seg] = i;
  });
  const segEnd = {};
  frames.forEach((f, i) => {
    segEnd[f.seg] = i;
  });

  const m4 = new THREE.Matrix4();
  const tmp = new THREE.Vector3();
  function renderFrame(t) {
    const index = clamp(Math.round(t * fps), 0, frames.length - 1);
    const f = frames[index];
    // scene + look
    roots.forEach((r, i) => (r.visible = i === f.s));
    const look = roots[f.s].userData.look;
    for (const [name, g] of Object.entries(lookRoots)) g.visible = looks[name] === look;
    scene.fog = look.fog;
    renderer.toneMappingExposure = look.exposure;
    // camera
    const [px, py, pz, tx, ty, tz, fov] = f.cam;
    camera.position.set(px, py, pz);
    camera.fov = fov;
    camera.updateProjectionMatrix();
    camera.lookAt(tx, ty, tz);
    camera.updateMatrixWorld();
    look.sun.target.position.set(tx, ty, tz);
    look.sun.position.copy(look.sun.target.position).addScaledVector(look.sunDir, 150);
    look.sun.target.updateMatrixWorld();
    // groups
    groups.forEach((g) => (g.visible = false));
    for (const entry of arr(f.g)) {
      const g = groups[entry[0]];
      g.matrix.copy(matrixOf(entry.slice(1), 1, 1, 1, m4));
      g.matrixWorldNeedsUpdate = true;
      g.visible = true;
    }
    // moving parts
    let n = 0;
    for (const p of arr(f.p)) {
      const [shape, sx, sy, sz, cf, color, mat, transparency] = p;
      if (transparency > 0.98 || Math.min(sx, sy, sz) < 1e-4) continue;
      const mesh = poolMesh(n++);
      const neon = mat === "Neon";
      const material = neon ? mesh.userData.neon : mesh.userData.standard;
      mesh.material = material;
      mesh.geometry = geometries[shape];
      material.color.copy(srgb(color, neon ? NEON_BOOST : 1));
      const opaque = transparency < 0.01;
      material.transparent = !opaque;
      material.opacity = 1 - transparency;
      material.depthWrite = opaque;
      mesh.castShadow = !neon && opaque;
      mesh.matrix.copy(matrixOf(cf, sx, sy, sz, m4));
      mesh.matrixWorldNeedsUpdate = true;
      mesh.visible = true;
    }
    for (let i = n; i < pool.length; i++) pool[i].visible = false;
    // titles: fade in at each segment's start, out at its end
    const seg = data.segments[f.seg];
    const since = (index - segStart[f.seg]) / fps;
    const until = (segEnd[f.seg] - index) / fps;
    titleMain.textContent = seg.title;
    titleSub.textContent = seg.sub;
    const show = clamp(since / 0.35) * clamp(until / 0.25);
    titleBox.style.opacity = String(show);
    titleBox.style.transform = `translateY(${(1 - clamp(since / 0.35)) * 1.2}vw)`;
    slow.style.opacity = f.label === "slow" ? String(clamp(since / 0.2)) : "0";
    // a short dip to black between scenes (not inside one continuous shot: segments with cut = false)
    const cut = Math.min(since, until);
    fade.style.opacity = seg.cut === false ? "0" : String(clamp(1 - cut / 0.12) * 0.85);
    // +$ popups (SellController's look)
    popupLayer.innerHTML = "";
    for (const [text, line, x, y, z, alpha, scale] of arr(f.o)) {
      tmp.set(x, y, z).project(camera);
      if (tmp.z > 1) continue;
      const div = document.createElement("div");
      div.className = "pop";
      div.style.left = ((tmp.x + 1) / 2) * W + "px";
      div.style.top = ((1 - tmp.y) / 2) * H + "px";
      div.style.opacity = String(alpha);
      div.style.transform = `translate(-50%, -100%) scale(${scale})`;
      div.innerHTML = `<div class="amount">${text}</div>` + (line ? `<div class="line">${line}</div>` : "");
      popupLayer.appendChild(div);
    }
    composer.render();
  }

  window.renderFrame = renderFrame;
  window.__duration = frames.length / fps;
  window.__frames = frames.length;
  window.__fps = fps;
  window.__meta = { picks: data.picks, sheetTitle: data.sheetTitle };
  renderFrame(0);
  window.__ready = true;
}

main().catch((e) => {
  console.error(e);
  window.__error = String(e && e.stack ? e.stack : e);
});
