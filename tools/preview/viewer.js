// Terra Forge offline preview renderer.
// Renders the JSON exported by tools/lune/export_scene.luau with an
// approximation of Roblox Future lighting, Atmosphere, Bloom and
// ColorCorrection. It is only for screenshots outside Studio.
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { BokehPass } from "three/addons/postprocessing/BokehPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { ShaderPass } from "three/addons/postprocessing/ShaderPass.js";
import { renderUI } from "./ui.js";

const params = new URLSearchParams(location.search);
const sceneName = params.get("scene") || "world";
const shotName = params.get("shot") || "town_overview";
const WIDTH = Number(params.get("w") || 1600);
const HEIGHT = Number(params.get("h") || 900);

const SHAPE_BLOCK = 0;
const SHAPE_BALL = 1;
const SHAPE_CYLINDER = 2;
const SHAPE_WEDGE = 3;

function srgb(hex, mult = 1) {
  const c = new THREE.Color();
  c.setRGB(
    parseInt(hex.slice(0, 2), 16) / 255,
    parseInt(hex.slice(2, 4), 16) / 255,
    parseInt(hex.slice(4, 6), 16) / 255,
    THREE.SRGBColorSpace,
  );
  return c.multiplyScalar(mult);
}

function fromArray3(a, mult = 1) {
  const c = new THREE.Color();
  c.setRGB(a[0], a[1], a[2], THREE.SRGBColorSpace);
  return c.multiplyScalar(mult);
}

function wedgeGeometry() {
  const B0 = [-0.5, -0.5, -0.5], B1 = [0.5, -0.5, -0.5], B2 = [0.5, -0.5, 0.5], B3 = [-0.5, -0.5, 0.5];
  const T2 = [0.5, 0.5, 0.5], T3 = [-0.5, 0.5, 0.5];
  const tris = [
    [B0, B1, B2], [B0, B2, B3], // bottom
    [B3, B2, T2], [B3, T2, T3], // back (+Z, tall side)
    [B0, T3, T2], [B0, T2, B1], // slope (faces -Z/up)
    [B0, B3, T3], // left
    [B1, T2, B2], // right
  ];
  const pos = [];
  for (const t of tris) for (const v of t) pos.push(...v);
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

const geometries = {
  [SHAPE_BLOCK]: new THREE.BoxGeometry(1, 1, 1),
  [SHAPE_BALL]: new THREE.SphereGeometry(0.5, 24, 16),
  [SHAPE_CYLINDER]: new THREE.CylinderGeometry(0.5, 0.5, 1, 24).rotateZ(-Math.PI / 2),
  [SHAPE_WEDGE]: wedgeGeometry(),
};

function materialFor(kind, transparency) {
  const opts = { flatShading: false };
  let m;
  if (kind === "neon") {
    m = new THREE.MeshBasicMaterial({ toneMapped: true });
  } else if (kind === "metal") {
    m = new THREE.MeshStandardMaterial({ roughness: 0.38, metalness: 0.6, ...opts });
  } else if (kind === "glass") {
    m = new THREE.MeshStandardMaterial({ roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.45, ...opts });
  } else if (kind === "reflective") {
    m = new THREE.MeshStandardMaterial({ roughness: 0.25, metalness: 0.15, ...opts });
  } else {
    m = new THREE.MeshStandardMaterial({ roughness: 0.82, metalness: 0.0, ...opts });
  }
  if (transparency > 0.01) {
    m.transparent = true;
    m.opacity = Math.max(0.05, 1 - transparency);
    m.depthWrite = false;
  }
  return m;
}

function materialKind(name, reflectance) {
  if (name === "Neon") return "neon";
  if (name === "Metal" || name === "Foil" || name === "DiamondPlate" || name === "CorrodedMetal") return "metal";
  if (name === "Glass" || name === "ForceField") return "glass";
  if (reflectance > 0.05) return "reflective";
  return "standard";
}

function softSprite(color, hard = 0.0) {
  const size = 64;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext("2d");
  const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  g.addColorStop(0, `rgba(255,255,255,1)`);
  g.addColorStop(Math.min(0.9, 0.2 + hard), `rgba(255,255,255,0.6)`);
  g.addColorStop(1, `rgba(255,255,255,0)`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function fontFor(family) {
  if (!family) return "Fredoka One";
  if (family.includes("Luckiest")) return "Luckiest Guy";
  return "Fredoka One";
}

function textTexture(text, color, family, aspect) {
  const h = 256;
  const w = Math.max(64, Math.round(h * aspect));
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  const font = fontFor(family);
  const boxW = w * 0.92;
  const boxH = h * 0.84;
  let size = boxH;
  ctx.font = `${size}px "${font}"`;
  while (size > 8 && (ctx.measureText(text).width > boxW || size > boxH)) {
    size -= 2;
    ctx.font = `${size}px "${font}"`;
  }
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "#" + color;
  ctx.fillText(text, w / 2, h / 2 + size * 0.06);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

async function main() {
  await document.fonts.load('40px "Fredoka One"');
  await document.fonts.load('40px "Luckiest Guy"');
  const shots = await fetch(`/shots.json`).then((r) => r.json());
  const shot = shots[shotName];
  if (!shot) throw new Error("unknown shot " + shotName);
  const scene = await fetch(`/scenes/${shot.scene || sceneName}.json`).then((r) => r.json());
  // presets with empty groups (e.g. Workbench) inherit from Surface
  const base = scene.presets.Surface;
  const own = scene.presets[shot.preset || "Surface"] || base;
  const preset = {};
  for (const group of Object.keys(base)) preset[group] = { ...base[group], ...(own[group] || {}) };
  const isCaveShot = !['Surface', 'Quarry', 'Workbench'].includes(shot.preset || 'Surface');

  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(WIDTH, HEIGHT);
  renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = Math.pow(2, preset.Lighting.ExposureCompensation ?? 0) * (shot.exposure ?? 1.0);
  document.getElementById("stage").prepend(renderer.domElement);

  const world = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(shot.fov ?? 70, WIDTH / HEIGHT, 0.3, 4000);
  if (shot.useSceneCamera && scene.camera) {
    shot.position = scene.camera.camera;
    shot.target = scene.camera.target;
  }
  camera.position.set(...shot.position);
  camera.lookAt(new THREE.Vector3(...shot.target));

  // ---- parts, instanced by (shape, material kind, transparency) ----
  const groups = new Map();
  scene.parts.forEach((p, index) => {
    const [shape, sx, sy, sz, cf, color, mat, transparency, reflectance] = p;
    const kind = materialKind(mat, reflectance);
    const tKey = Math.round(transparency * 10) / 10;
    const key = `${shape}|${kind}|${tKey}`;
    if (!groups.has(key)) groups.set(key, { shape, kind, transparency: tKey, items: [] });
    groups.get(key).items.push({ sx, sy, sz, cf, color, index });
  });
  const partMatrices = [];
  const m4 = new THREE.Matrix4();
  const scaleM = new THREE.Matrix4();
  for (const g of groups.values()) {
    const material = materialFor(g.kind, g.transparency);
    const mesh = new THREE.InstancedMesh(geometries[g.shape], material, g.items.length);
    g.items.forEach((it, i) => {
      const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = it.cf;
      m4.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
      partMatrices[it.index] = m4.clone();
      scaleM.makeScale(it.sx, it.sy, it.sz);
      mesh.setMatrixAt(i, m4.clone().multiply(scaleM));
      const boost = g.kind === "neon" ? (isCaveShot ? 1.5 : 2.2) : 1;
      mesh.setColorAt(i, srgb(it.color, boost));
    });
    mesh.castShadow = g.kind !== "neon" && g.transparency < 0.3;
    mesh.receiveShadow = g.kind !== "neon";
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    world.add(mesh);
  }

  // ---- sign text (SurfaceGui on Front/Back faces) ----
  for (const [partIndex, face, text, color, family] of scene.texts) {
    const part = scene.parts[partIndex];
    const base = partMatrices[partIndex];
    if (!base) continue;
    const [, sx, sy, sz] = part;
    const tex = textTexture(text, color, family, sx / sy);
    const plane = new THREE.Mesh(
      new THREE.PlaneGeometry(sx, sy),
      new THREE.MeshStandardMaterial({ map: tex, transparent: true, roughness: 0.9 }),
    );
    const local = new THREE.Matrix4();
    if (face === 0) {
      local.makeRotationY(Math.PI).setPosition(0, 0, -sz / 2 - 0.02);
    } else {
      local.makeTranslation(0, 0, sz / 2 + 0.02);
    }
    plane.applyMatrix4(base.clone().multiply(local));
    world.add(plane);
  }

  // ---- lighting ----
  const L = preset.Lighting;
  const atm = preset.Atmosphere;
  const isCave = isCaveShot;
  const outdoor = fromArray3(L.OutdoorAmbient || [0.5, 0.45, 0.4]);
  const ambient = fromArray3(L.Ambient || [0.2, 0.2, 0.2]);
  world.add(new THREE.HemisphereLight(outdoor.clone().multiplyScalar(isCave ? 1.2 : 1.6), ambient.clone().multiplyScalar(isCave ? 0.8 : 1.2), isCave ? 1.0 : 1.3));
  world.add(new THREE.AmbientLight(ambient, isCave ? 5 : 0.8));

  const target = new THREE.Vector3(...shot.target);
  if (!isCave) {
    const sun = new THREE.DirectionalLight(new THREE.Color(1.0, 0.84, 0.66), (L.Brightness ?? 2) * 1.15);
    const sunDir = new THREE.Vector3(...(shot.sunDir || [-0.62, 0.48, 0.62])).normalize();
    sun.position.copy(target.clone().add(sunDir.multiplyScalar(400)));
    sun.target.position.copy(target);
    sun.castShadow = true;
    const ext = shot.shadowExtent ?? 220;
    sun.shadow.camera.left = -ext;
    sun.shadow.camera.right = ext;
    sun.shadow.camera.top = ext;
    sun.shadow.camera.bottom = -ext;
    sun.shadow.camera.near = 10;
    sun.shadow.camera.far = 1200;
    sun.shadow.mapSize.set(4096, 4096);
    sun.shadow.bias = -0.0005;
    sun.shadow.normalBias = 0.04;
    world.add(sun);
    world.add(sun.target);
  }

  // nearest point lights
  const lights = scene.lights
    .map((l) => ({ l, d: new THREE.Vector3(l[0], l[1], l[2]).distanceTo(target) }))
    .sort((a, b) => a.d - b.d)
    .slice(0, shot.maxLights ?? 16);
  for (const { l } of lights) {
    const [x, y, z, color, range, brightness] = l;
    const pl = new THREE.PointLight(srgb(color), brightness * (isCave ? 7 : 5), range * 1.4, 1);
    pl.position.set(x, y, z);
    world.add(pl);
  }

  // ---- sky / fog ----
  const fogColor = fromArray3(atm.Color || [0.8, 0.7, 0.6]);
  if (!isCave) {
    const skyGeo = new THREE.SphereGeometry(3000, 32, 16);
    const horizon = fogColor.clone().lerp(new THREE.Color(1.0, 0.72, 0.5), 0.35);
    const zenith = new THREE.Color().setRGB(0.32, 0.52, 0.86, THREE.SRGBColorSpace);
    const skyMat = new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      uniforms: { horizon: { value: horizon }, zenith: { value: zenith } },
      vertexShader: `varying vec3 vPos; void main(){ vPos = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);} `,
      fragmentShader: `uniform vec3 horizon; uniform vec3 zenith; varying vec3 vPos;
        void main(){ float h = clamp(normalize(vPos).y, -0.2, 1.0); float t = pow(max(h,0.0), 0.55);
          gl_FragColor = vec4(mix(horizon, zenith, t), 1.0); }`,
    });
    const sky = new THREE.Mesh(skyGeo, skyMat);
    sky.position.copy(camera.position);
    world.add(sky);
    world.fog = new THREE.FogExp2(fogColor, (atm.Density ?? 0.3) * 0.0028 * (atm.Haze ?? 1) * 0.6);
  } else {
    world.background = fogColor.clone().multiplyScalar(0.25);
    world.fog = new THREE.FogExp2(fogColor.clone().multiplyScalar(0.5), (atm.Density ?? 0.4) * 0.012);
  }

  // ---- particles ----
  const sprite = softSprite();
  for (const [x, y, z, kind, color, size] of scene.emitters) {
    if (new THREE.Vector3(x, y, z).distanceTo(camera.position) > 260) continue;
    const count = kind === "Smoke" ? 10 : kind === "Fire" ? 24 : kind === "Embers" ? 26 : 14;
    const pos = [];
    for (let i = 0; i < count; i++) {
      const t = Math.random();
      if (kind === "Smoke") {
        pos.push(x + (Math.random() - 0.5) * 3 + t * 6, y + 2 + t * 30, z + (Math.random() - 0.5) * 3);
      } else if (kind === "Fire") {
        pos.push(x + (Math.random() - 0.5) * size * 0.6 * (1 - t), y + t * 3, z + (Math.random() - 0.5) * size * 0.6 * (1 - t));
      } else if (kind === "Embers") {
        pos.push(x + (Math.random() - 0.5) * size * 1.4, y + Math.random() * 9, z + (Math.random() - 0.5) * size * 1.4);
      } else {
        pos.push(x + (Math.random() - 0.5) * 4, y + (Math.random() - 0.5) * 4, z + (Math.random() - 0.5) * 4);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    const additive = kind !== "Smoke";
    const pm = new THREE.PointsMaterial({
      map: sprite,
      color: kind === "Smoke" ? srgb(color) : srgb(color, 2.2),
      size: kind === "Smoke" ? 9 : kind === "Fire" ? 2.2 : kind === "Embers" ? 0.45 : 0.6,
      sizeAttenuation: true,
      transparent: true,
      opacity: kind === "Smoke" ? 0.35 : 0.95,
      depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    world.add(new THREE.Points(g, pm));
  }

  // ---- post processing ----
  const composer = new EffectComposer(renderer);
  composer.setSize(WIDTH, HEIGHT);
  composer.addPass(new RenderPass(world, camera));
  // DepthOfFieldEffect stand-in (the cleaning close-up blurs the background)
  if (shot.dof) {
    const focus = camera.position.distanceTo(new THREE.Vector3(...shot.target));
    composer.addPass(new BokehPass(world, camera, { focus, aperture: shot.dof.aperture ?? 0.004, maxblur: shot.dof.maxblur ?? 0.008 }));
  }
  const B = preset.Bloom || {};
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(WIDTH, HEIGHT), (B.Intensity ?? 0.8) * (isCaveShot ? 0.45 : 0.75), ((B.Size ?? 24) / 56) * 0.9, isCaveShot ? 0.9 : 0.82));
  composer.addPass(new OutputPass());
  const CC = preset.ColorCorrection || {};
  const tint = CC.TintColor || [1, 1, 1];
  composer.addPass(
    new ShaderPass({
      uniforms: {
        tDiffuse: { value: null },
        brightness: { value: CC.Brightness ?? 0 },
        contrast: { value: CC.Contrast ?? 0 },
        saturation: { value: CC.Saturation ?? 0 },
        tint: { value: new THREE.Vector3(tint[0], tint[1], tint[2]) },
      },
      vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);} `,
      fragmentShader: `uniform sampler2D tDiffuse; uniform float brightness; uniform float contrast; uniform float saturation; uniform vec3 tint; varying vec2 vUv;
        void main(){ vec4 c = texture2D(tDiffuse, vUv); vec3 col = c.rgb + brightness;
          col = (col - 0.5) * (1.0 + contrast) + 0.5;
          float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
          col = mix(vec3(l), col, 1.0 + saturation);
          col *= tint; gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a); }`,
    }),
  );

  composer.render();
  if (shot.ui) {
    const guis = await fetch(`/scenes/${shot.ui}.json`).then((r) => r.json());
    renderUI(document.getElementById("ui"), guis, WIDTH, HEIGHT);
    await document.fonts.ready;
  }
  window.__shot = shot;
  window.__done = true;
}

main().catch((e) => {
  console.error(e);
  window.__error = String(e && e.stack ? e.stack : e);
});
