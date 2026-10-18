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

// Parts with Reflectance (water, the sea) mirror the sky in Roblox; they get
// the preview sky dome as an environment map once it exists.
const reflectiveMaterials = [];

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
    reflectiveMaterials.push(m);
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

// Roblox's Atmosphere hazes far objects toward the sky color in their
// direction: warm (Atmosphere.Color, with Glare) toward the sun and the Decay
// color away from it. three's FogExp2 has one color, so the fog shader chunks
// are patched to blend Color -> Decay by the horizontal angle to the sun (the
// same falloff as the sky dome's horizon). Density sets how fast things fade;
// Haze thickens it a little (calibrated so the old 0.34 / 1.8 settings keep
// their old look).
function fogDensity(atm) {
  return (atm.Density ?? 0.3) * 0.0019 * (1 + 0.35 * (atm.Haze ?? 1));
}

function linear3(c) {
  return `vec3(${c.r.toFixed(5)}, ${c.g.toFixed(5)}, ${c.b.toFixed(5)})`;
}

function directionalFog(atm, shot) {
  const sun = new THREE.Vector2(...[(shot.sunDir || [-0.62, 0.48, 0.62])[0], (shot.sunDir || [-0.62, 0.48, 0.62])[2]]).normalize();
  const away = fromArray3(atm.Decay || atm.Color || [0.6, 0.5, 0.8]);
  THREE.ShaderChunk.fog_pars_vertex = `
#ifdef USE_FOG
  varying float vFogDepth;
  varying vec3 vFogDir;
#endif`;
  THREE.ShaderChunk.fog_vertex = `
#ifdef USE_FOG
  vFogDepth = - mvPosition.z;
  vec4 fogWorld = vec4( transformed, 1.0 );
  #ifdef USE_INSTANCING
    fogWorld = instanceMatrix * fogWorld;
  #endif
  fogWorld = modelMatrix * fogWorld;
  vFogDir = fogWorld.xyz - cameraPosition;
#endif`;
  THREE.ShaderChunk.fog_pars_fragment = `
#ifdef USE_FOG
  uniform vec3 fogColor;
  varying float vFogDepth;
  varying vec3 vFogDir;
  #ifdef FOG_EXP2
    uniform float fogDensity;
  #else
    uniform float fogNear;
    uniform float fogFar;
  #endif
#endif`;
  THREE.ShaderChunk.fog_fragment = `
#ifdef USE_FOG
  #ifdef FOG_EXP2
    float fogFactor = 1.0 - exp( - fogDensity * fogDensity * vFogDepth * vFogDepth );
  #else
    float fogFactor = smoothstep( fogNear, fogFar, vFogDepth );
  #endif
  vec2 fogFlat = normalize( vFogDir.xz + vec2( 1e-5 ) );
  float fogWarm = pow( 0.5 + 0.5 * dot( fogFlat, vec2( ${sun.x.toFixed(5)}, ${sun.y.toFixed(5)} ) ), 1.6 );
  vec3 fogTint = mix( ${linear3(away)}, fogColor, fogWarm );
  gl_FragColor.rgb = mix( gl_FragColor.rgb, fogTint, fogFactor );
#endif`;
}

// Sunset sky dome (the Lighting preset's "Sky" group, ART_DIRECTION section 7):
// horizon SkyHorizon (pinker away from the sun, like Roblox's Atmosphere
// Decay) -> SkyPurple at MidAngle -> SkyTop at the zenith, an additive sun
// (2 degree disc, 10 degree halo, wide glow) around shot.sunDir and a soft
// layer of Terrain-Clouds-like streaks (Cover ~0.5) lit pink/orange toward
// the sun. Below the horizon it fades into the Atmosphere color so the far
// sea edge disappears.
//
// shot.skybox (an equirectangular panorama URL, e.g. "/scenes/skybox/x.png"
// from tools/kenney/skybox.mjs) puts a Roblox Sky skybox behind it: the
// panorama fills the sky, the sunset gradient stays as the Atmosphere haze
// low over the horizon (shot.skyboxHaze, default 0.35 = sine of the angle
// where the haze is gone) and the clouds and the sun stay in front.
// shot.skyboxYaw / skyboxTilt (degrees) turn it like tools/kenney/skybox.mjs.
function sunsetSky(preset, shot, camera, fogColor, fogAway, spaceTex) {
  const S = preset.Sky || {};
  const col = (a, fallback) => fromArray3(a || fallback);
  const sunDir = new THREE.Vector3(...(shot.sunDir || [-0.62, 0.48, 0.62])).normalize();
  const uniforms = {
    top: { value: col(S.Top, [64 / 255, 72 / 255, 150 / 255]) },
    mid: { value: col(S.Mid, [150 / 255, 98 / 255, 168 / 255]) },
    horizon: { value: col(S.Horizon, [1.0, 162 / 255, 86 / 255]) },
    horizonAway: { value: col(S.HorizonAway, [240 / 255, 150 / 255, 168 / 255]) },
    sunColor: { value: col(S.Sun, [1.0, 222 / 255, 150 / 255]) },
    fogColor: { value: fogColor.clone() },
    fogAway: { value: fogAway.clone() },
    sunDir: { value: sunDir },
    midSin: { value: Math.sin(((S.MidAngle ?? 25) * Math.PI) / 180) },
    cloudCover: { value: S.CloudCover ?? 0.5 },
    spaceTex: { value: spaceTex },
    spaceOn: { value: spaceTex ? 1.0 : 0.0 },
    spaceYaw: { value: ((shot.skyboxYaw ?? 0) * Math.PI) / 180 },
    spaceTilt: { value: ((shot.skyboxTilt ?? 0) * Math.PI) / 180 },
    spaceHaze: { value: shot.skyboxHaze ?? 0.35 },
    spaceGain: { value: shot.skyboxGain ?? 1.0 },
  };
  const skyMat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
    uniforms,
    vertexShader: `varying vec3 vPos; void main(){ vPos = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);} `,
    fragmentShader: `
      uniform vec3 top; uniform vec3 mid; uniform vec3 horizon; uniform vec3 horizonAway;
      uniform vec3 sunColor; uniform vec3 fogColor; uniform vec3 fogAway; uniform vec3 sunDir;
      uniform float midSin; uniform float cloudCover;
      uniform sampler2D spaceTex; uniform float spaceOn; uniform float spaceYaw; uniform float spaceTilt; uniform float spaceHaze; uniform float spaceGain;
      varying vec3 vPos;
      float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float noise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y); }
      float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++){ v += a * noise(p); p = p * 2.07 + vec2(3.1, 1.7); a *= 0.5; } return v; }
      void main(){
        vec3 d = normalize(vPos);
        float h = d.y;
        vec2 flatDir = normalize(d.xz + vec2(1e-5));
        vec2 flatSun = normalize(sunDir.xz + vec2(1e-5));
        float toward = 0.5 + 0.5 * dot(flatDir, flatSun);
        float warm = pow(toward, 1.6);
        vec3 hor = mix(horizonAway, horizon, warm);
        // horizon -> purple at midSin -> deep blue-purple at the zenith
        float t1 = smoothstep(0.0, midSin, h);
        float t2 = smoothstep(midSin * 0.6, 1.0, h);
        vec3 col = mix(hor, mid, pow(t1, 0.9));
        col = mix(col, top, pow(t2, 0.7));
        // warm band hugging the horizon toward the sun
        col += horizon * 0.18 * warm * exp(-max(h, 0.0) * 9.0);
        if (h < 0.0) col = mix(hor, mix(fogAway, fogColor, warm), clamp(-h * 10.0, 0.0, 1.0));
        // a Roblox Sky skybox: the panorama above, the sunset haze low down
        if (spaceOn > 0.5) {
          // tools/kenney/skybox.mjs's frame: x = north (-Z), y = west (-X), z = up
          vec3 q = vec3(-d.z, -d.x, d.y);
          q = vec3(q.x * cos(spaceTilt) + q.z * sin(spaceTilt), q.y, -q.x * sin(spaceTilt) + q.z * cos(spaceTilt));
          float lon = spaceYaw + atan(q.y, q.x);
          vec2 suv = vec2(fract(lon / 6.2831853), 1.0 - acos(clamp(q.z, -1.0, 1.0)) / 3.1415927);
          vec3 space = texture2D(spaceTex, suv).rgb * spaceGain;
          float haze = 1.0 - smoothstep(0.0, spaceHaze, h);
          col = mix(space, col, haze * 0.9);
        }
        // Terrain-Clouds-like streaks, lit pink/orange toward the sun
        if (h > 0.0) {
          vec2 uv = d.xz / (h + 0.12);
          float n = fbm(uv * vec2(1.1, 2.6) + vec2(7.0, 3.0));
          float m = smoothstep(1.0 - cloudCover - 0.02, 1.0 - cloudCover + 0.2, n) * smoothstep(0.02, 0.14, h) * (1.0 - smoothstep(0.55, 0.95, h));
          vec3 lit = mix(vec3(0.86, 0.36, 0.42), vec3(1.0, 0.55, 0.32), warm);
          vec3 shade = mix(mid * 0.85, lit, 0.35 + 0.4 * warm);
          vec3 cloud = mix(lit, shade, smoothstep(0.1, 0.6, h));
          col = mix(col, cloud, m * 0.75);
        }
        // the sun: disc, halo, broad glow
        float ang = acos(clamp(dot(d, sunDir), -1.0, 1.0));
        float disc = 1.0 - smoothstep(0.0165, 0.0195, ang);
        float halo = exp(-pow(ang / 0.1745, 2.0));
        float glow = exp(-ang / 0.6);
        col = min(col, vec3(1.15));
        col += sunColor * (disc * 3.5 + halo * 0.5 + glow * 0.1);
        gl_FragColor = vec4(col, 1.0);
      }`,
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(3000, 64, 32), skyMat);
  sky.position.copy(camera.position);
  return sky;
}

// Roblox's touch controls on phone renders (small-screen sizes from Roblox's
// TouchThumbstick / TouchJump: a 90 pt stick bottom-left, a 70 pt jump button
// bottom-right), drawn at `px` pixels per point.
function mobileControls(layer, px) {
  const add = (css) => {
    const d = document.createElement("div");
    d.style.cssText = "position:absolute;border-radius:50%;" + css;
    layer.appendChild(d);
  };
  add(`left:${35 * px}px;bottom:${20 * px}px;width:${90 * px}px;height:${90 * px}px;background:rgba(0,0,0,0.25);border:${2 * px}px solid rgba(255,255,255,0.45);`);
  add(`left:${60 * px}px;bottom:${45 * px}px;width:${40 * px}px;height:${40 * px}px;background:rgba(255,255,255,0.55);`);
  add(`right:${25 * px}px;bottom:${20 * px}px;width:${70 * px}px;height:${70 * px}px;background:rgba(0,0,0,0.25);border:${2 * px}px solid rgba(255,255,255,0.45);`);
}

async function main() {
  await document.fonts.load('40px "Fredoka One"');
  await document.fonts.load('40px "Luckiest Guy"');
  const shots = await fetch(`/shots.json`).then((r) => r.json());
  const shot = shots[shotName];
  if (!shot) throw new Error("unknown shot " + shotName);
  const scene = await fetch(`/scenes/${shot.scene || sceneName}.json`).then((r) => r.json());
  // empty Lua tables are exported as {} instead of []
  for (const key of ["parts", "lights", "emitters", "texts"]) if (!Array.isArray(scene[key])) scene[key] = [];
  // presets with empty groups (e.g. Workbench) inherit from Surface
  const base = scene.presets.Surface;
  const own = scene.presets[shot.preset || "Surface"] || base;
  const preset = {};
  for (const group of Object.keys(base)) preset[group] = { ...base[group], ...(own[group] || {}) };
  const isCaveShot = !['Surface', 'Quarry', 'Workbench'].includes(shot.preset || 'Surface');
  if (!isCaveShot) directionalFog(preset.Atmosphere || {}, shot);

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
    if (scene.camera.fov) camera.fov = scene.camera.fov;
    if (scene.camera.uiInset !== undefined) shot.uiInset = scene.camera.uiInset;
    camera.updateProjectionMatrix();
  }
  camera.position.set(...shot.position);
  camera.lookAt(new THREE.Vector3(...shot.target));

  // ---- parts, instanced by (shape, material kind, transparency, CastShadow) ----
  const groups = new Map();
  scene.parts.forEach((p, index) => {
    const [shape, sx, sy, sz, cf, color, mat, transparency, reflectance, castShadow] = p;
    if (Math.min(sx, sy, sz) < 1e-4) return; // flat parts give NaN normals (one NaN pixel blacks out the bloom)
    const kind = materialKind(mat, reflectance);
    const tKey = Math.round(transparency * 10) / 10;
    // a part with CastShadow off casts none here either (older scene files: every part casts)
    const shadow = castShadow !== 0;
    const key = `${shape}|${kind}|${tKey}|${shadow ? 1 : 0}`;
    if (!groups.has(key)) groups.set(key, { shape, kind, transparency: tKey, castShadow: shadow, items: [] });
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
    mesh.castShadow = g.castShadow && g.kind !== "neon" && g.transparency < 0.3;
    mesh.receiveShadow = g.kind !== "neon";
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    world.add(mesh);
  }

  // ---- sign text (SurfaceGui on Front/Back faces) ----
  for (const [partIndex, face, text, color, family, lightInfluence = 1] of scene.texts) {
    const part = scene.parts[partIndex];
    const base = partMatrices[partIndex];
    if (!base) continue;
    const [, sx, sy, sz] = part;
    const tex = textTexture(text, color, family, sx / sy);
    // SurfaceGui.LightInfluence like Roblox: 0 = the letters ignore the lighting (full
    // brightness), 1 = lit like the part, in between = that much lit, the rest self-lit.
    // Self-lit letters stay just under the bloom threshold (0.82): crisp, not a white blob.
    const li = Math.min(1, Math.max(0, lightInfluence));
    const selfLit = (1 - li) * 0.78;
    const textMaterial =
      li <= 0.01
        ? new THREE.MeshBasicMaterial({ map: tex, transparent: true, color: new THREE.Color(selfLit, selfLit, selfLit) })
        : new THREE.MeshStandardMaterial({
            map: tex,
            transparent: true,
            roughness: 0.9,
            color: new THREE.Color(li, li, li),
            emissive: new THREE.Color(selfLit, selfLit, selfLit),
            emissiveMap: tex,
          });
    const plane = new THREE.Mesh(new THREE.PlaneGeometry(sx, sy), textMaterial);
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
  // outdoors the hemisphere also stands in for EnvironmentDiffuseScale (Roblox
  // lights shaded faces with the sky too): 1.3 + 0.6 * scale (1.6 at 0.5)
  const hemi = isCave ? 1.0 : 1.3 + 0.6 * (L.EnvironmentDiffuseScale ?? 0);
  world.add(new THREE.HemisphereLight(outdoor.clone().multiplyScalar(isCave ? 1.2 : 1.6), ambient.clone().multiplyScalar(isCave ? 0.8 : 1.2), hemi));
  world.add(new THREE.AmbientLight(ambient, isCave ? 5 : 0.8));

  const target = new THREE.Vector3(...shot.target);
  if (!isCave) {
    const sun = new THREE.DirectionalLight(new THREE.Color(...(shot.sunColor || [1.0, 0.84, 0.66])), (L.Brightness ?? 2) * 1.15);
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
    const fogAway = fromArray3(atm.Decay || atm.Color || [0.6, 0.5, 0.8]);
    let spaceTex = null;
    if (shot.skybox) {
      spaceTex = await new THREE.TextureLoader().loadAsync(shot.skybox);
      spaceTex.colorSpace = THREE.SRGBColorSpace;
      spaceTex.wrapS = THREE.RepeatWrapping;
    }
    const sky = sunsetSky(preset, shot, camera, fogColor, fogAway, spaceTex);
    world.add(sky);
    const envScene = new THREE.Scene();
    envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 48, 24), sky.material));
    const env = new THREE.PMREMGenerator(renderer).fromScene(envScene, 0.02, 0.1, 200).texture;
    for (const m of reflectiveMaterials) {
      m.envMap = env;
      m.envMapIntensity = 1.0;
      m.needsUpdate = true;
    }
    world.fog = new THREE.FogExp2(fogColor, fogDensity(atm));
  } else {
    world.background = fogColor.clone().multiplyScalar(0.25);
    world.fog = new THREE.FogExp2(fogColor.clone().multiplyScalar(0.5), (atm.Density ?? 0.4) * 0.012);
  }

  // ---- particles ----
  const sprite = softSprite();
  for (const [x, y, z, kind, color, size, ext] of scene.emitters) {
    if (new THREE.Vector3(x, y, z).distanceTo(camera.position) > 260) continue;
    // small effects on a blaster (GunFlame / GunSpark): spread over the emitter part's box
    if (kind.startsWith("Gun")) {
      const [ex, ey, ez] = ext || [0.5, 0.5, 0.5];
      const flame = kind === "GunFlame";
      for (const [count, px] of flame ? [[18, 0.42], [26, 0.2]] : [[12, 0.26], [30, 0.11]]) {
        const pos = [];
        for (let i = 0; i < count; i++) {
          const rise = flame ? Math.random() * 0.6 : 0;
          pos.push(x + (Math.random() * 2 - 1) * ex * 1.15, y + (Math.random() * 2 - 1) * ey * 1.2 + rise, z + (Math.random() * 2 - 1) * ez * 1.15);
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
        const pm = new THREE.PointsMaterial({
          map: sprite, color: srgb(color, 2.0), size: px, sizeAttenuation: true, transparent: true,
          opacity: 0.95, depthWrite: false, blending: THREE.AdditiveBlending,
        });
        world.add(new THREE.Points(g, pm));
      }
      continue;
    }
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
  if (!isCaveShot) {
    // sun glow: cap the low sun's mirror highlight on the sea before bloom, so it
    // blooms like Roblox's small sun glint instead of a screen-filling white blob
    composer.addPass(
      new ShaderPass({
        uniforms: { tDiffuse: { value: null }, cap: { value: 2.6 } },
        vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);} `,
        fragmentShader: `uniform sampler2D tDiffuse; uniform float cap; varying vec2 vUv;
          void main(){ vec4 c = texture2D(tDiffuse, vUv); float m = max(c.r, max(c.g, c.b));
            gl_FragColor = vec4(m > cap ? c.rgb * (cap / m) : c.rgb, c.a); }`,
      }),
    );
  }
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(WIDTH, HEIGHT), (B.Intensity ?? 0.8) * (isCaveShot ? 0.45 : 0.75), ((B.Size ?? 24) / 56) * 0.9, isCaveShot ? 0.9 : 0.82));
  composer.addPass(new OutputPass());
  const CC = { ...(preset.ColorCorrection || {}), ...(shot.cc || {}) }; // shot.cc: per-shot overrides (studio shots)
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
    const uiLayer = document.getElementById("ui");
    uiLayer.style.width = `${WIDTH}px`;
    uiLayer.style.height = `${HEIGHT}px`;
    renderUI(uiLayer, guis, WIDTH, HEIGHT, shot.uiInset);
    if (shot.mobileControls) mobileControls(uiLayer, shot.mobileControls);
    // wait for the 3D icon pictures before the screenshot
    await Promise.all([...uiLayer.querySelectorAll("img")].map((img) => img.decode().catch(() => {})));
    await document.fonts.ready;
  }
  window.__shot = shot;
  window.__done = true;
}

main().catch((e) => {
  console.error(e);
  window.__error = String(e && e.stack ? e.stack : e);
});
