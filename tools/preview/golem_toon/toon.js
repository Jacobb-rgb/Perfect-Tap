// Terra Forge shop stickers drawn FROM THE GAME'S OWN MODELS (owner 2026-11-12: "make it in the
// drawn version but more cool, and it has to look like it is in the game, so people don't say
// it's cap"). Every golem and egg the shop shows (IconAssets.ShopGolems) is the model its 3D
// picture builds (PictureModels.build, exported by tools/lune/export_golem_stickers.luau), seen
// from that picture's camera direction, drawn like the shop's icons (docs/art/shop_v3_concept/
// icons.js):
//   - every part keeps its exact game colour: flat cel tones by face direction (tops lit and a
//     touch warm, fronts the colour itself, sides in a darker shade turned toward purple), balls
//     and cylinders in hard bands; no textures, studs or noise
//   - a bold navy outline round the silhouette, thinner navy lines where parts of different
//     colours meet or one stands in front of another (drawn on the far part, like a drawn
//     shape's own outline), none inside a flat face
//   - white shines: a light band on the big blocks' top-front edges, a shine mark on the head,
//     the body and the egg shells, hard stripes on gold and silver, glints on glass
//   - neon flat and bright with a small glow; a thin light rim on the shaded side; small
//     sparkles on gems and crowns; the outline colour as a drop under it all
// Nothing is added to the model (no props, no background, no rarity glow). Rendered at 4x and
// box-filtered down. window.TOON.render(name, { cell, mode, debug }) returns a PNG data URL of
// one cell; mode "lit" draws the shop's own 3D picture instead (StoreView's camera and the
// ViewportFrame light of Pop.model) for side-by-side checks; debug keeps the 4x picture
// (TOON.big) and the parts in false colour with the inner lines (TOON.lines).
// Page: /golem_toon/toon.html, driven by tools/preview/shop_golem_sheet.mjs:
//   node tools/preview/shop_golem_sheet.mjs            the upload sheet + build/preview/icons/sticker_*.png
//   node tools/preview/shop_golem_sheet.mjs --lit      the shop's 3D pictures (build/preview/golem_3d)
//   STICKERS=<names> TOON_DEBUG=1 node ...             some stickers, with build/preview/golem_debug
import * as THREE from "three";

const OUTLINE_RGB = [0x22, 0x1a, 0x3d]; // icons.js's outline colour
const SS = 4; // supersampling: drawn at 4x, box-filtered down
// sizes in px at a 256 px cell (they scale with the cell)
const SIZE = {
  outline: 7.5, // round the silhouette
  drop: 5, // the outline colour again, this far down, under it all
  line: 2.75, // the inner lines
  fill: 238, // the sticker's longer side (outline and drop included)
  rim: 2.4, // the light rim on the shaded side
  bevel: 1.7, // the light band on the big blocks' top-front edges
  glow: 2.6, // how far the neon glows
};
const FOV = 18; // a narrow lens: close to a flat drawing, the proportions the same
// a depth step this big (studs) is an edge even between parts of one colour
const STEP = 0.1;
// nearer than this (studs) two touching parts are side by side: a seam, not one in front
const EPS = 0.012;

// ------------------------------------------------------------------ colour (sRGB <-> OKLab)
const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const gam = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
function oklab(rgb) {
  const r = lin(rgb[0]), g = lin(rgb[1]), b = lin(rgb[2]);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}
function linFromOklab(L, a, b) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}
// OKLCH (hue in radians) to sRGB 0..1; out of gamut: less chroma, same light and hue
function fromLch(L, C, h) {
  L = Math.min(1, Math.max(0, L));
  for (let i = 0; i < 24; i++) {
    const c = linFromOklab(L, C * Math.cos(h), C * Math.sin(h));
    if (c.every((v) => v >= -1e-4 && v <= 1 + 1e-4)) return c.map((v) => gam(Math.min(1, Math.max(0, v))));
    C *= 0.86;
  }
  const c = linFromOklab(L, 0, 0);
  return c.map((v) => gam(Math.min(1, Math.max(0, v))));
}
const lch = (rgb) => {
  const [L, a, b] = oklab(rgb);
  return [L, Math.hypot(a, b), Math.atan2(b, a)];
};
const hexRgb = (hex) => [parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255];
const DEG = Math.PI / 180;
// turns hue h toward `to` the short way round by at most `by` (radians)
function hueToward(h, to, by) {
  let d = to - h;
  while (d > Math.PI) d -= 2 * Math.PI;
  while (d < -Math.PI) d += 2 * Math.PI;
  return h + Math.sign(d) * Math.min(Math.abs(d), by);
}
const WARM = 95 * DEG; // the lit tops lean toward warm yellow
const COOL = 292 * DEG; // the shade leans toward purple (icons.js: navy, purple shades)

// The cel tones of one game colour: [lit top, the colour itself, side shade, deep shade].
function tones(rgb, kind) {
  let [L, C, h] = lch(rgb);
  if (kind === "glass") {
    // a lighter tint (see-through glass over light)
    L = L + (1 - L) * 0.3;
    C *= 0.9;
    rgb = fromLch(L, C, h);
  }
  const grey = C < 0.035;
  const dark = L < 0.4;
  // lit: lighter, a touch warm
  const litL = L > 0.93 ? Math.min(1, L + 0.04) : L + (dark ? 0.14 : 0.075 + 0.06 * (1 - L));
  const lit = fromLch(litL, C * (grey ? 1 : 1.04), grey ? h : hueToward(h, WARM, 7 * DEG));
  // shade: darker, hue turned toward cool purple, chroma kept (greys get a little cool tint)
  const sh = (k, turn) => {
    const sL = dark ? L * (1 - 0.5 * (1 - k)) : L * k;
    const sC = grey ? Math.max(C, 0.03 + 0.02 * (1 - k)) : C * 1.08 + 0.008;
    return fromLch(sL, sC, grey ? COOL : hueToward(h, COOL, turn));
  };
  return [lit, rgb, sh(0.8, 13 * DEG), sh(0.64, 20 * DEG)];
}

// The material class of a part: "neon", "glass", "metal" (stripes, highlights) or "matte".
function kindOf(material) {
  if (material === "Neon") return "neon";
  if (material === "Glass") return "glass";
  if (material === "Metal" || material === "Foil" || material === "DiamondPlate") return "metal";
  return "matte";
}
// How strong a metal's white stripes are: gold, silver and light metal full, coloured armour less.
function metalStrength(material, rgb) {
  if (material === "Foil") return 1;
  const [L, C, h] = lch(rgb);
  const gold = C > 0.08 && h > 50 * DEG && h < 115 * DEG;
  if (gold || (L > 0.7 && C < 0.07)) return 1;
  return 0.45;
}

// ------------------------------------------------------------------ geometry
const SHAPE_BLOCK = 0, SHAPE_BALL = 1, SHAPE_CYLINDER = 2, SHAPE_WEDGE = 3;
function wedgeGeometry() {
  const B0 = [-0.5, -0.5, -0.5], B1 = [0.5, -0.5, -0.5], B2 = [0.5, -0.5, 0.5], B3 = [-0.5, -0.5, 0.5];
  const T2 = [0.5, 0.5, 0.5], T3 = [-0.5, 0.5, 0.5];
  const tris = [[B0, B1, B2], [B0, B2, B3], [B3, B2, T2], [B3, T2, T3], [B0, T3, T2], [B0, T2, B1], [B0, B3, T3], [B1, T2, B2]];
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(tris.flat(2), 3));
  g.computeVertexNormals();
  return g;
}
const GEOMETRY = {
  [SHAPE_BLOCK]: new THREE.BoxGeometry(1, 1, 1),
  [SHAPE_BALL]: new THREE.SphereGeometry(0.5, 96, 64),
  // (Roblox cylinders run along X)
  [SHAPE_CYLINDER]: new THREE.CylinderGeometry(0.5, 0.5, 1, 96, 1).rotateZ(-Math.PI / 2),
  [SHAPE_WEDGE]: wedgeGeometry(),
};

// ------------------------------------------------------------------ the toon shader
const VERTEX = /* glsl */ `
uniform mat3 uNormalWorld;
uniform vec3 uSize;
varying vec3 vNormalW;
varying vec3 vNormalO;
varying vec3 vLocal;
varying vec3 vWorld;
varying float vDepth;
void main() {
  vNormalO = normal;
  vNormalW = normalize(uNormalWorld * normal);
  vLocal = position * uSize;
  vec4 w = modelMatrix * vec4(position, 1.0);
  vWorld = w.xyz;
  vec4 mv = viewMatrix * w;
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}`;

const FRAGMENT = /* glsl */ `
uniform int uPass;          // 0 colour, 1 id, 2 depth + tone class
uniform vec3 uId;
uniform vec3 uLit;
uniform vec3 uBase;
uniform vec3 uShade;
uniform vec3 uDeep;
uniform int uKind;          // 0 matte, 1 metal, 2 neon, 3 glass
uniform int uShape;         // 0 block, 1 ball, 2 cylinder, 3 wedge
uniform float uMetal;       // the white stripes' strength
uniform vec3 uSize;
uniform mat3 uAxes;         // the part's local axes in the world (unit)
uniform vec3 uLight;        // the tone light (world)
uniform vec3 uSpecLight;    // the highlight light (world)
uniform vec3 uCamPos;
uniform vec3 uCamRight;
uniform vec3 uCamUp;
uniform float uPx;          // studs per pixel at the model
uniform vec2 uDepthRange;
varying vec3 vNormalW;
varying vec3 vNormalO;
varying vec3 vLocal;
varying vec3 vWorld;
varying float vDepth;

float pick(vec3 v, int i) { return i == 0 ? v.x : (i == 1 ? v.y : v.z); }
vec3 axisOf(int i) { return i == 0 ? uAxes[0] : (i == 1 ? uAxes[1] : uAxes[2]); }

void main() {
  vec3 n = normalize(vNormalW);
  float t = dot(n, uLight);
  // the tone class: 1 lit top, 2 the colour itself (fronts), 3 shade (sides), 4 deep; 5 neon (flat)
  int cls = t > 0.70 ? 1 : (t > 0.30 ? 2 : (t > -0.45 ? 3 : 4));
  if (uKind == 2) cls = 5;
  if (uPass == 1) {
    gl_FragColor = vec4(uId, 1.0);
    return;
  }
  if (uPass == 2) {
    float d = clamp((vDepth - uDepthRange.x) / (uDepthRange.y - uDepthRange.x), 0.0, 1.0) * 65535.0;
    float hi = floor(d / 256.0);
    float lo = floor(d - hi * 256.0);
    gl_FragColor = vec4(hi / 255.0, lo / 255.0, 0.0, float(cls) / 255.0);
    return;
  }
  vec3 col = cls == 1 ? uLit : (cls == 2 ? uBase : (cls == 3 ? uShade : uDeep));
  if (uKind == 2) col = uBase;
  // flat faces (blocks, cylinder caps): white stripes on metal and glass fronts
  bool isFlat = uShape == 0 || (uShape == 2 && abs(vNormalO.x) > 0.5);
  if (isFlat && cls == 2 && (uKind == 1 || uKind == 3)) {
    vec3 an = abs(vNormalO);
    int axis = an.x > an.y ? (an.x > an.z ? 0 : 2) : (an.y > an.z ? 1 : 2);
    int ta = axis == 0 ? 1 : 0;
    int tb = axis == 2 ? 1 : 2;
    vec3 wa = axisOf(ta), wb = axisOf(tb);
    vec2 pa = vec2(dot(wa, uCamRight), dot(wa, uCamUp));
    vec2 pb = vec2(dot(wb, uCamRight), dot(wb, uCamUp));
    // u: the axis that runs more across the picture, v: the other
    bool aIsU = abs(pa.x) >= abs(pb.x);
    int tu = aIsU ? ta : tb;
    int tv = aIsU ? tb : ta;
    vec2 pu = aIsU ? pa : pb;
    vec2 pv = aIsU ? pb : pa;
    float hu = pick(uSize, tu) * 0.5, hv = pick(uSize, tv) * 0.5;
    if (uShape == 2) { hu = min(uSize.y, uSize.z) * 0.5; hv = hu; }
    float u01 = 0.5 + 0.5 * sign(pu.x) * pick(vLocal, tu) / hu;
    float v01 = 0.5 + 0.5 * sign(pv.y == 0.0 ? 1.0 : pv.y) * pick(vLocal, tv) / hv;
    float lu = 2.0 * hu * length(pu) / uPx;
    float lv = 2.0 * hv * length(pv) / uPx;
    if (lu > 22.0 && lv > 22.0) {
      // two diagonal stripes from the top left, one wide, one thin
      float a = u01 * lu + (1.0 - v01) * lv;
      float sum = lu + lv;
      float w1 = clamp(0.1 * sum, 5.0, 26.0);
      float c1 = 0.24 * sum + w1 * 0.5;
      float w2 = clamp(0.035 * sum, 3.0, 9.0);
      float c2 = c1 + w1 * 0.5 + clamp(0.05 * sum, 4.0, 14.0) + w2 * 0.5;
      bool stripe = abs(a - c1) < w1 * 0.5 || abs(a - c2) < w2 * 0.5;
      float amount = uKind == 3 ? 0.7 : 0.82 * uMetal;
      if (stripe) col = mix(col, vec3(1.0), amount);
    }
  }
  // curved metal and glass: a hard white highlight
  bool curved = uShape == 1 || (uShape == 2 && abs(vNormalO.x) < 0.5);
  if (curved && (uKind == 1 || uKind == 3)) {
    vec3 v = normalize(uCamPos - vWorld);
    vec3 r = reflect(-v, n);
    float s = dot(r, uSpecLight);
    float cut = uKind == 3 ? 0.94 : 0.9;
    if (s > cut) col = mix(col, vec3(1.0), uKind == 3 ? 0.8 : 0.9 * max(uMetal, 0.75));
  }
  gl_FragColor = vec4(col, 1.0);
}`;

// ------------------------------------------------------------------ the data
let DATA = null;
async function load() {
  if (!DATA) DATA = await fetch("/scenes/golem_stickers.json").then((r) => r.json());
  return DATA;
}

const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setClearColor(0x000000, 0);

// The parts of model `name` as meshes (toon materials), with what the 2D passes need to know.
function buildParts(model) {
  const group = new THREE.Group();
  const infos = [];
  const m4 = new THREE.Matrix4();
  model.parts.forEach((p, i) => {
    const [shape, sx, sy, sz, cf, color, material, transparency] = p;
    if (transparency > 0.95 || Math.min(sx, sy, sz) < 1e-4) return;
    const name = model.names[i] || "";
    const kind = kindOf(material);
    let rgb = hexRgb(color);
    if (kind === "neon") {
      // neon glows: a little brighter than its colour, flat
      const [L, C, h] = lch(rgb);
      rgb = fromLch(L + (1 - L) * 0.05, C * 1.02, h);
    }
    const [lit, base, shade, deep] = tones(rgb, kind);
    const size = shape === SHAPE_CYLINDER ? [sx, Math.min(sy, sz), Math.min(sy, sz)] : [sx, sy, sz];
    const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
    m4.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
    const world = m4.clone().multiply(new THREE.Matrix4().makeScale(...size));
    const id = infos.length + 1;
    const uniforms = {
      uPass: { value: 0 },
      uId: { value: new THREE.Vector3((id % 256) / 255, Math.floor(id / 256) / 255, 0) },
      uLit: { value: new THREE.Vector3(...lit) },
      uBase: { value: new THREE.Vector3(...base) },
      uShade: { value: new THREE.Vector3(...shade) },
      uDeep: { value: new THREE.Vector3(...deep) },
      uKind: { value: { matte: 0, metal: 1, neon: 2, glass: 3 }[kind] },
      uShape: { value: shape },
      uMetal: { value: kind === "metal" ? metalStrength(material, rgb) : kind === "glass" ? 1 : 0 },
      uSize: { value: new THREE.Vector3(...size) },
      uAxes: { value: new THREE.Matrix3().set(r00, r01, r02, r10, r11, r12, r20, r21, r22) },
      uNormalWorld: { value: new THREE.Matrix3().getNormalMatrix(world) },
      uLight: { value: new THREE.Vector3() },
      uSpecLight: { value: new THREE.Vector3() },
      uCamPos: { value: new THREE.Vector3() },
      uCamRight: { value: new THREE.Vector3() },
      uCamUp: { value: new THREE.Vector3() },
      uPx: { value: 0.01 },
      uDepthRange: { value: new THREE.Vector2(0, 1) },
    };
    const mesh = new THREE.Mesh(GEOMETRY[shape] || GEOMETRY[SHAPE_BLOCK], new THREE.ShaderMaterial({ uniforms, vertexShader: VERTEX, fragmentShader: FRAGMENT }));
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(world);
    mesh.matrixWorld.copy(world);
    group.add(mesh);
    infos.push({ id, name, shape, kind, color, base, lit, mesh });
  });
  return { group, infos };
}

// Every vertex of every part in the world (the camera frames them exactly).
function worldPoints(infos) {
  const pts = [];
  const v = new THREE.Vector3();
  for (const info of infos) {
    const pos = info.mesh.geometry.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      v.fromBufferAttribute(pos, i).applyMatrix4(info.mesh.matrix);
      pts.push(v.clone());
    }
  }
  return pts;
}

// A camera looking along -from at the model, its picture moved and zoomed so the projected
// model fills the box `box` (NDC: x0, x1, y0, y1; y up) of the frame exactly.
function framedCamera(from, pts, fovDeg, place) {
  const dir = new THREE.Vector3(...from).normalize();
  const bounds = new THREE.Box3().setFromPoints(pts);
  const center = bounds.getCenter(new THREE.Vector3());
  const radius = bounds.getSize(new THREE.Vector3()).length() / 2;
  const dist = (radius / Math.sin((fovDeg / 2) * DEG)) * 1.1;
  const camera = new THREE.PerspectiveCamera(fovDeg, 1, Math.max(0.05, dist - radius * 2), dist + radius * 2);
  camera.position.copy(center).addScaledVector(dir, dist);
  camera.up.set(0, 1, 0);
  camera.lookAt(center);
  camera.updateMatrixWorld(true);
  camera.updateProjectionMatrix();
  // the projected bounds
  const vp = new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  const q = new THREE.Vector3();
  for (const p of pts) {
    q.copy(p).applyMatrix4(vp);
    x0 = Math.min(x0, q.x);
    x1 = Math.max(x1, q.x);
    y0 = Math.min(y0, q.y);
    y1 = Math.max(y1, q.y);
  }
  const [a, bx, by] = place(x1 - x0, y1 - y0, x0, y1);
  const fit = new THREE.Matrix4().set(a, 0, 0, bx, 0, a, 0, by, 0, 0, 1, 0, 0, 0, 0, 1);
  camera.projectionMatrix.premultiply(fit);
  camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
  // studs per pixel at the model's centre (for a frame `px` px tall: divide by it)
  const depth = center.clone().applyMatrix4(camera.matrixWorldInverse).z * -1;
  const span = (2 * depth * Math.tan((fovDeg / 2) * DEG)) / a;
  return { camera, center, radius, depth, span, dir };
}

// ------------------------------------------------------------------ 2D helpers
// 1D squared distance transform (Felzenszwalb) with the nearest site's index
function dt1(f, n, d, idx, v, z) {
  let k = 0;
  v[0] = 0;
  z[0] = -Infinity;
  z[1] = Infinity;
  for (let q = 1; q < n; q++) {
    let s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    while (s <= z[k]) {
      k--;
      s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    }
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = Infinity;
  }
  k = 0;
  for (let q = 0; q < n; q++) {
    while (z[k + 1] < q) k++;
    d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
    idx[q] = v[k];
  }
}
// Squared distance from every pixel to the nearest pixel where site() holds, and that pixel's index.
function edt(w, h, site) {
  const INF = 1e20;
  const n = Math.max(w, h);
  const f = new Float64Array(n), d = new Float64Array(n), idx = new Int32Array(n), v = new Int32Array(n), z = new Float64Array(n + 1);
  const colD = new Float64Array(w * h), colI = new Int32Array(w * h);
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) f[y] = site(y * w + x) ? 0 : INF;
    dt1(f, h, d, idx, v, z);
    for (let y = 0; y < h; y++) {
      colD[y * w + x] = d[y];
      colI[y * w + x] = idx[y];
    }
  }
  const dist = new Float32Array(w * h), near = new Int32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) f[x] = colD[y * w + x];
    dt1(f, w, d, idx, v, z);
    for (let x = 0; x < w; x++) {
      dist[y * w + x] = d[x];
      const sx = idx[x];
      near[y * w + x] = colI[y * w + sx] * w + sx;
    }
  }
  return { dist, near };
}
// a separable box blur of a Float32 channel, `passes` times (a soft Gaussian)
function blur(src, w, h, r, passes) {
  const a = new Float32Array(src), b = new Float32Array(w * h);
  for (let p = 0; p < passes; p++) {
    for (let y = 0; y < h; y++) {
      let acc = 0;
      const row = y * w;
      for (let x = -r; x <= r; x++) acc += a[row + Math.min(w - 1, Math.max(0, x))];
      for (let x = 0; x < w; x++) {
        b[row + x] = acc / (2 * r + 1);
        acc += a[row + Math.min(w - 1, x + r + 1)] - a[row + Math.max(0, x - r)];
      }
    }
    for (let x = 0; x < w; x++) {
      let acc = 0;
      for (let y = -r; y <= r; y++) acc += b[Math.min(h - 1, Math.max(0, y)) * w + x];
      for (let y = 0; y < h; y++) {
        a[y * w + x] = acc / (2 * r + 1);
        acc += b[Math.min(h - 1, y + r + 1) * w + x] - b[Math.max(0, y - r) * w + x];
      }
    }
  }
  return a;
}

function readTarget(rt, S) {
  const raw = new Uint8Array(S * S * 4);
  renderer.readRenderTargetPixels(rt, 0, 0, S, S, raw);
  // (rows come bottom up)
  const out = new Uint8Array(S * S * 4);
  for (let y = 0; y < S; y++) out.set(raw.subarray((S - 1 - y) * S * 4, (S - y) * S * 4), y * S * 4);
  return out;
}

// colour distance of two parts' own colours (OKLab)
function colourGap(a, b) {
  const p = oklab(a.base), q = oklab(b.base);
  return Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]);
}

// ------------------------------------------------------------------ the toon sticker
const HEAD = /^(Head|HeadFill|HeadEdge\d|Helm|HelmFill|HelmEdge\d)$/;
const SHELL = /^Shell$/;
const SPARKLE = /(Gem\d?$|Emblem$|Moonstone$|^Orb$|Jewel|CrownCore$|^Star\d$|^Rune$|Buckle$|CrownPoint1$|CrownPiece3$|^Rose2$|ClaspGem)/;

async function renderToon(name, cell, debug) {
  const data = await load();
  const model = data.models[name];
  if (!model) throw new Error("no model " + name);
  const k = cell / 256; // px scale of the sizes
  const S = cell * SS;
  const { group, infos } = buildParts(model);
  const scene = new THREE.Scene();
  scene.add(group);
  const pts = worldPoints(infos);
  const out = SIZE.outline * k, drop = SIZE.drop * k, fill = SIZE.fill * k;
  // fit: the silhouette plus its outline and drop is `fill` px on its longer side, centred
  const view = framedCamera(model.from, pts, FOV, (bw, bh, x0, y1) => {
    const pxW = (bw / 2) * cell, pxH = (bh / 2) * cell;
    const a = Math.min((fill - 2 * out) / pxW, (fill - 2 * out - drop) / pxH);
    const W = a * pxW + 2 * out, H = a * pxH + 2 * out + drop;
    const left = (cell - W) / 2 + out, top = (cell - H) / 2 + out;
    const tx0 = (left / cell) * 2 - 1, ty1 = 1 - (top / cell) * 2;
    return [a, tx0 - a * x0, ty1 - a * y1];
  });
  const { camera } = view;
  const px = view.span / S; // studs per render pixel
  // the lights: the tones' from above and the front (the world's, so a model's front is its own
  // colour), the highlights' from the picture's top left
  const right = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 0);
  const up = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 1);
  const toCam = view.dir.clone();
  const light = new THREE.Vector3(0.3, 1.0, -0.8).normalize();
  const spec = new THREE.Vector3().addScaledVector(up, 1.0).addScaledVector(right, -0.75).addScaledVector(toCam, 0.9).normalize();
  const near = view.depth - view.radius * 1.3, far = view.depth + view.radius * 1.3;
  for (const info of infos) {
    const u = info.mesh.material.uniforms;
    u.uLight.value.copy(light);
    u.uSpecLight.value.copy(spec);
    u.uCamPos.value.copy(camera.position);
    u.uCamRight.value.copy(right);
    u.uCamUp.value.copy(up);
    u.uPx.value = px;
    u.uDepthRange.value.set(near, far);
  }
  renderer.setSize(S, S, false);
  const rt = new THREE.WebGLRenderTarget(S, S, { depthBuffer: true, samples: 0 });
  const pass = (n) => {
    for (const info of infos) info.mesh.material.uniforms.uPass.value = n;
    renderer.setRenderTarget(rt);
    renderer.setClearColor(0x000000, 0);
    renderer.clear();
    renderer.render(scene, camera);
    renderer.setRenderTarget(null);
    return readTarget(rt, S);
  };
  const colour = pass(0);
  const idRaw = pass(1);
  const depthRaw = pass(2);
  rt.dispose();
  for (const info of infos) info.mesh.material.dispose();

  const N = S * S;
  const id = new Int32Array(N), depth = new Float32Array(N), cls = new Uint8Array(N);
  for (let p = 0; p < N; p++) {
    if (idRaw[p * 4 + 3] < 128) continue;
    id[p] = idRaw[p * 4] + idRaw[p * 4 + 1] * 256;
    depth[p] = near + ((depthRaw[p * 4] * 256 + depthRaw[p * 4 + 1]) / 65535) * (far - near);
    cls[p] = depthRaw[p * 4 + 3];
  }
  const part = (p) => infos[id[p] - 1];
  // the colour, as floats 0..1
  const R = new Float32Array(N), G = new Float32Array(N), B = new Float32Array(N);
  for (let p = 0; p < N; p++) {
    R[p] = colour[p * 4] / 255;
    G[p] = colour[p * 4 + 1] / 255;
    B[p] = colour[p * 4 + 2] / 255;
  }
  const mix = (p, c, t) => {
    R[p] += (c[0] - R[p]) * t;
    G[p] += (c[1] - G[p]) * t;
    B[p] += (c[2] - B[p]) * t;
  };
  const WHITE = [1, 1, 1];

  // the part bounds on screen (big blocks get a bevel)
  const box = infos.map(() => [S, S, -1, -1]);
  for (let y = 0; y < S; y++)
    for (let x = 0; x < S; x++) {
      const i = id[y * S + x];
      if (!i) continue;
      const b = box[i - 1];
      if (x < b[0]) b[0] = x;
      if (y < b[1]) b[1] = y;
      if (x > b[2]) b[2] = x;
      if (y > b[3]) b[3] = y;
    }
  const big = infos.map((info, i) => {
    const b = box[i];
    return info.kind !== "neon" && b[2] - b[0] >= 40 * k * SS && b[3] - b[1] >= 32 * k * SS;
  });

  // 1. the bevel: a light band down from every top-front crease of a big block (a lit top over
  // its own front, the same colour)
  const bevel = SIZE.bevel * k * SS;
  for (let x = 0; x < S; x++) {
    for (let y = 1; y < S; y++) {
      const p = y * S + x;
      if (cls[p] !== 2) continue;
      const q = p - S;
      if (cls[q] !== 1 || !id[q]) continue;
      const a = part(p), b = part(q);
      if (a.color !== b.color || !big[a.id - 1]) continue;
      if (a.shape === SHAPE_BALL || b.shape === SHAPE_BALL) continue;
      // the crease: one px of the top lights too, then the band down the front
      mix(q, WHITE, 0.35);
      for (let j = 0; j < bevel + 1; j++) {
        const r = p + j * S;
        if (y + j >= S || id[r] !== id[p] || cls[r] !== 2) break;
        const t = Math.min(1, bevel + 0.5 - j);
        mix(r, a.lit, 0.85 * t);
        mix(r, WHITE, 0.3 * t);
      }
    }
  }

  // 2. the shine marks: the head's front, the body's front, an egg's shell (a white tilted
  // ellipse and a dot, placed at the most upper-left spot with room in the region)
  const bodyName = infos.some((i) => i.name === "Breastplate") ? /^Breastplate$/ : infos.some((i) => i.name === "BodyFill") ? /^(Body|BodyFill)$/ : /^Body$/;
  const shineRegions = [
    { test: (p) => HEAD.test(part(p).name) && cls[p] === 2, size: 0.085 },
    { test: (p) => bodyName.test(part(p).name) && cls[p] === 2, size: 0.06 },
    { test: (p) => SHELL.test(part(p).name) && cls[p] !== 0 && part(p).kind !== "neon", size: 0.1 },
  ];
  for (const region of shineRegions) {
    const inRegion = new Uint8Array(N);
    let any = 0, x0 = S, x1 = 0, y0 = S, y1 = 0;
    for (let p = 0; p < N; p++)
      if (id[p] && region.test(p)) {
        inRegion[p] = 1;
        any++;
        const x = p % S, y = (p / S) | 0;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    if (any < 400) continue;
    const { dist } = edt(S, S, (p) => !inRegion[p]);
    const bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    // the most upper-left spot with room for the mark (smaller marks if the big one has none there)
    let best = -1, rx = 0;
    for (const f of [1, 0.8, 0.62, 0.5]) {
      const r = Math.max(6 * k * SS, region.size * bw * f);
      const need = (r * 0.62 + SIZE.line * k * SS * 1.2) ** 2;
      let pick = -1, pickScore = Infinity;
      for (let p = 0; p < N; p++) {
        if (!inRegion[p] || dist[p] < need) continue;
        const score = ((p % S) - x0) / bw + (((p / S) | 0) - y0) / bh;
        if (score < pickScore) {
          pickScore = score;
          pick = p;
        }
      }
      if (pick >= 0 && (pickScore < 0.75 || f === 0.5)) {
        best = pick;
        rx = r;
        break;
      }
    }
    if (best < 0) continue;
    const ry = rx * 0.45;
    const cx = best % S, cy = (best / S) | 0;
    const ang = -32 * DEG, ca = Math.cos(ang), sa = Math.sin(ang);
    const dotR = ry * 0.55, dx = cx + rx * 1.35 * ca, dy = cy + rx * 1.35 * sa + ry * 0.9;
    const R0 = Math.ceil(rx * 2 + dotR * 2);
    for (let y = Math.max(0, cy - R0); y < Math.min(S, cy + R0); y++)
      for (let x = Math.max(0, cx - R0); x < Math.min(S, cx + R0); x++) {
        const p = y * S + x;
        if (!inRegion[p]) continue;
        const u = ((x - cx) * ca + (y - cy) * sa) / rx, v = (-(x - cx) * sa + (y - cy) * ca) / ry;
        const e = u * u + v * v;
        const dd = Math.hypot(x - dx, y - dy) / dotR;
        const a = Math.max(Math.min(1, (1 - e) * rx * 0.5), Math.min(1, (1 - dd) * dotR * 0.5));
        if (a > 0) mix(p, WHITE, 0.88 * a);
      }
  }

  // 3. the neon glow (a soft light from every neon part onto its neighbours)
  {
    const gr = new Float32Array(N), gg = new Float32Array(N), gb = new Float32Array(N);
    let anyNeon = false;
    for (let p = 0; p < N; p++)
      if (id[p] && part(p).kind === "neon") {
        gr[p] = R[p];
        gg[p] = G[p];
        gb[p] = B[p];
        anyNeon = true;
      }
    if (anyNeon) {
      const r = Math.max(1, Math.round((SIZE.glow * k * SS) / 1.6));
      const br = blur(gr, S, S, r, 3), bg = blur(gg, S, S, r, 3), bb = blur(gb, S, S, r, 3);
      const t = 0.9; // (screen blend)
      for (let p = 0; p < N; p++) {
        if (!id[p] || part(p).kind === "neon") continue;
        R[p] = 1 - (1 - R[p]) * (1 - Math.min(1, br[p] * t));
        G[p] = 1 - (1 - G[p]) * (1 - Math.min(1, bg[p] * t));
        B[p] = 1 - (1 - B[p]) * (1 - Math.min(1, bb[p] * t));
      }
    }
  }

  // 4. the light rim on the shaded side (right, a little down) of the silhouette; the edge's way
  // out is the slope of the soft-blurred silhouette (a pixel staircase must not flicker it)
  const outside = edt(S, S, (p) => !id[p]);
  {
    const rim = SIZE.rim * k * SS;
    const dirX = 0.94, dirY = 0.34;
    const mask = new Float32Array(N);
    for (let p = 0; p < N; p++) mask[p] = id[p] ? 1 : 0;
    const soft = blur(mask, S, S, Math.max(1, Math.round(rim * 0.6)), 2);
    for (let p = 0; p < N; p++) {
      if (!id[p]) continue;
      const d = Math.sqrt(outside.dist[p]);
      if (d > rim + 1) continue;
      const x = p % S, y = (p / S) | 0;
      if (x < 1 || y < 1 || x >= S - 1 || y >= S - 1) continue;
      const gx = soft[p - 1] - soft[p + 1], gy = soft[p - S] - soft[p + S];
      const len = Math.hypot(gx, gy);
      if (len < 1e-4) continue;
      const facing = (gx * dirX + gy * dirY) / len;
      if (facing < 0.35) continue;
      const t = Math.min(1, (facing - 0.35) / 0.3) * Math.min(1, rim + 0.5 - d);
      if (t <= 0) continue;
      const info = part(p);
      const [L, C, h] = lch(info.base);
      const rimColour = fromLch(Math.min(0.97, L + 0.3 + (1 - L) * 0.2), C * 0.7, hueToward(h, 250 * DEG, 30 * DEG));
      mix(p, rimColour, 0.85 * t);
    }
  }

  // 5. the inner lines: where a part stands in front of a part of another colour (or one
  // clearly further back), a navy line on the far part along the near part's edge
  const lineCov = new Float32Array(N);
  {
    const w = SIZE.line * k * SS;
    const reach = Math.ceil(w + 1);
    const disc = [];
    for (let dy = -reach; dy <= reach; dy++)
      for (let dx = -reach; dx <= reach; dx++) {
        const d = Math.hypot(dx, dy);
        if (d <= w + 0.5) disc.push([dx, dy, d]);
      }
    const gapCache = new Map();
    const gap = (a, b) => {
      const key = a < b ? a * 4096 + b : b * 4096 + a;
      let g = gapCache.get(key);
      if (g === undefined) {
        g = colourGap(infos[a - 1], infos[b - 1]);
        gapCache.set(key, g);
      }
      return g;
    };
    // a line of `radius` round pixel `src` onto the parts behind it (`back`: the part it stands in
    // front of there, always; any other part only where it is clearly further away)
    const stampFront = (src, radius, front, back) => {
      const x = src % S, y = (src / S) | 0, dz = depth[src];
      for (const [dx, dy, d] of disc) {
        if (d > radius + 0.5) continue;
        const xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= S || yy >= S) continue;
        const q = yy * S + xx;
        const other = id[q];
        if (!other || other === front) continue;
        if (other !== back && (depth[q] <= dz + EPS || (gap(front, other) < 0.06 && depth[q] - dz < STEP))) continue;
        const cov = Math.min(1, radius + 0.5 - d);
        if (cov > lineCov[q]) lineCov[q] = cov;
      }
    };
    // half a line round `src` onto the other parts (a seam between two parts side by side)
    const stampSide = (src, radius) => {
      const x = src % S, y = (src / S) | 0, me = id[src];
      for (const [dx, dy, d] of disc) {
        if (d > radius + 0.5) continue;
        const xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= S || yy >= S) continue;
        const q = yy * S + xx;
        if (!id[q] || id[q] === me) continue;
        const cov = Math.min(1, radius + 0.5 - d);
        if (cov > lineCov[q]) lineCov[q] = cov;
      }
    };
    // every pair of touching pixels of two parts, with which one is in front there (by depth)
    const recP = [], recQ = [], recDz = [];
    for (let y = 0; y < S; y++)
      for (let x = 0; x < S; x++) {
        const p = y * S + x;
        const a = id[p];
        if (!a) continue;
        if (x + 1 < S && id[p + 1] && id[p + 1] !== a) {
          recP.push(p);
          recQ.push(p + 1);
          recDz.push(depth[p + 1] - depth[p]);
        }
        if (y + 1 < S && id[p + S] && id[p + S] !== a) {
          recP.push(p);
          recQ.push(p + S);
          recDz.push(depth[p + S] - depth[p]);
        }
      }
    // which one is in front is a vote of all the touching pixels of the same two parts (a part's
    // 1 px top face peeking over its edge must not flip the line from side to side)
    const votes = new Map(); // key: smaller id * 65536 + bigger id -> [small in front, big in front, all, steps]
    const keyOf = (a, b) => (a < b ? a * 65536 + b : b * 65536 + a);
    for (let i = 0; i < recP.length; i++) {
      const a = id[recP[i]], b = id[recQ[i]];
      const key = keyOf(a, b);
      let v = votes.get(key);
      if (!v) votes.set(key, (v = [0, 0, 0, 0]));
      // dz > 0: b is further, a in front
      const dz = a < b ? recDz[i] : -recDz[i];
      if (dz > EPS) v[0]++;
      else if (dz < -EPS) v[1]++;
      v[2]++;
      if (Math.abs(dz) > STEP) v[3]++;
    }
    for (let i = 0; i < recP.length; i++) {
      const p = recP[i], q = recQ[i], a = id[p], b = id[q];
      const v = votes.get(keyOf(a, b));
      const lo = Math.min(a, b), hi = Math.max(a, b);
      const front = v[0] >= 0.25 * v[2] && v[0] >= v[1] ? lo : v[1] >= 0.25 * v[2] ? hi : 0;
      const differ = gap(a, b) >= 0.06;
      if (front && (differ || v[3] >= 0.3 * v[2])) {
        if (front === a) stampFront(p, w, a, b);
        else stampFront(q, w, b, a);
      } else if (!front && differ) {
        stampSide(p, w / 2);
        stampSide(q, w / 2);
      }
    }
    for (let p = 0; p < N; p++) if (lineCov[p] > 0) mix(p, OUTLINE_RGB.map((c) => c / 255), lineCov[p]);
    if (debug) {
      // DEBUG: the ids (false colour) with the line coverage over them
      const dbg = new Float32Array(N * 4);
      for (let p = 0; p < N; p++) {
        const i = id[p];
        const h = ((i * 2654435761) >>> 0) / 4294967296;
        dbg[p * 4] = i ? 0.3 + 0.7 * h : 0;
        dbg[p * 4 + 1] = i ? 0.3 + 0.7 * ((h * 7) % 1) : 0;
        dbg[p * 4 + 2] = i ? 0.3 + 0.7 * ((h * 13) % 1) : 0;
        dbg[p * 4 + 3] = 1;
        if (lineCov[p] > 0) {
          dbg[p * 4] *= 1 - lineCov[p];
          dbg[p * 4 + 1] *= 1 - lineCov[p];
          dbg[p * 4 + 2] *= 1 - lineCov[p];
        }
      }
      window.TOON.lines = downscale(dbg, S, S);
    }
  }

  // 6. the outline round the silhouette and the drop under it
  const outer = edt(S, S, (p) => id[p] > 0);
  const outW = out * SS, dropPx = Math.round(drop * SS);
  const ring = new Float32Array(N); // the outline's coverage (1 inside the silhouette)
  for (let p = 0; p < N; p++) {
    if (id[p]) ring[p] = 1;
    else ring[p] = Math.max(0, Math.min(1, outW + 0.5 - Math.sqrt(outer.dist[p])));
  }
  // compose: drop (ring moved down) under the ring under the picture
  const img = new Float32Array(N * 4); // premultiplied linear RGB + alpha
  const O = OUTLINE_RGB.map((c) => lin(c / 255));
  for (let p = 0; p < N; p++) {
    const y = (p / S) | 0;
    const dropA = y >= dropPx ? ring[p - dropPx * S] : 0;
    let a = Math.max(ring[p], dropA);
    let r = O[0] * a, g = O[1] * a, b = O[2] * a;
    if (id[p]) {
      r = lin(Math.min(1, Math.max(0, R[p])));
      g = lin(Math.min(1, Math.max(0, G[p])));
      b = lin(Math.min(1, Math.max(0, B[p])));
      a = 1;
    }
    img[p * 4] = r;
    img[p * 4 + 1] = g;
    img[p * 4 + 2] = b;
    img[p * 4 + 3] = a;
  }

  // 7. sparkles on gems and crowns (the two biggest; a golem's chest core only if it has no
  // other gem), at the gem's top right
  {
    const count = new Map();
    for (let p = 0; p < N; p++) if (id[p]) count.set(id[p], (count.get(id[p]) || 0) + 1);
    const min = 60 * k * k * SS * SS;
    const gems = [], cores = [];
    for (const [i, n] of count) {
      const info = infos[i - 1];
      if (n < min) continue;
      if (SPARKLE.test(info.name) && (info.kind === "neon" || info.kind === "glass" || /Crown/.test(info.name))) gems.push([i, n]);
      else if (info.name === "Core" && info.kind === "neon") cores.push([i, n]);
    }
    const picks = (gems.length ? gems : cores).sort((a, b) => b[1] - a[1]).slice(0, 2);
    picks.forEach(([i], n) => {
      const b = box[i - 1];
      const cx = b[2] - (b[2] - b[0]) * 0.2, cy = b[1] + (b[3] - b[1]) * 0.2;
      star(img, S, cx, cy, (n === 0 ? 7.5 : 5.5) * k * SS);
    });
  }

  if (debug) window.TOON.big = downscale(img, S, S);
  return downscale(img, S, cell);
}

// A four-point sparkle (a white astroid with a soft light round it) at (cx, cy), radius r.
function star(img, S, cx, cy, r) {
  const x0 = Math.max(0, Math.floor(cx - r * 1.6)), x1 = Math.min(S - 1, Math.ceil(cx + r * 1.6));
  const y0 = Math.max(0, Math.floor(cy - r * 1.6)), y1 = Math.min(S - 1, Math.ceil(cy + r * 1.6));
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++) {
      const u = Math.abs(x - cx) / r, v = Math.abs(y - cy) / r;
      const f = Math.sqrt(u) + Math.sqrt(v); // <= 1: inside the astroid
      const inside = Math.max(0, Math.min(1, (1 - f) * r * 0.35));
      const halo = Math.max(0, 1 - Math.hypot(u, v) / 0.55) * 0.5;
      const t = Math.max(inside, halo * (img[(y * S + x) * 4 + 3] > 0 ? 1 : 0));
      if (t <= 0) continue;
      const p = (y * S + x) * 4;
      const a = img[p + 3];
      // over: white (premultiplied, linear)
      img[p] = img[p] * (1 - t) + t;
      img[p + 1] = img[p + 1] * (1 - t) + t;
      img[p + 2] = img[p + 2] * (1 - t) + t;
      img[p + 3] = a * (1 - t) + t;
    }
}

// The 4x picture box-filtered down to `cell` px (premultiplied, linear light), as a PNG data URL.
function downscale(img, S, cell) {
  const f = S / cell;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = cell;
  const ctx = canvas.getContext("2d");
  const outImg = ctx.createImageData(cell, cell);
  const o = outImg.data;
  for (let y = 0; y < cell; y++)
    for (let x = 0; x < cell; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let j = 0; j < f; j++)
        for (let i = 0; i < f; i++) {
          const p = ((y * f + j) * S + x * f + i) * 4;
          r += img[p];
          g += img[p + 1];
          b += img[p + 2];
          a += img[p + 3];
        }
      const q = (y * cell + x) * 4;
      if (a <= 0) continue;
      // (the sums are premultiplied: divide by the alpha sum for the colour)
      o[q] = Math.round(gam(Math.min(1, r / a)) * 255);
      o[q + 1] = Math.round(gam(Math.min(1, g / a)) * 255);
      o[q + 2] = Math.round(gam(Math.min(1, b / a)) * 255);
      o[q + 3] = Math.round((a / (f * f)) * 255);
    }
  ctx.putImageData(outImg, 0, 0);
  return canvas.toDataURL("image/png");
}

// ------------------------------------------------------------------ the shop's own 3D picture
// (Pop.model's ViewportFrame light, StoreView.frame's camera: FOV 30, filling ModelFill 0.94)
let litRenderer = null;
async function renderLit(name, cell) {
  const data = await load();
  const model = data.models[name];
  const S = cell * SS;
  const scene = new THREE.Scene();
  const vpColor = (hex) => new THREE.Color().setRGB(...hexRgb(hex), THREE.SRGBColorSpace);
  scene.add(new THREE.AmbientLight(vpColor("aaaab4"), Math.PI));
  const sun = new THREE.DirectionalLight(vpColor("fffaf0"), Math.PI);
  sun.position.set(0.6, 1, 0.8);
  scene.add(sun);
  const m4 = new THREE.Matrix4();
  const corners = [];
  for (const [shape, sx, sy, sz, cf, color, material, transparency] of model.parts) {
    if (transparency > 0.95) continue;
    const mat = material === "Neon" ? new THREE.MeshBasicMaterial({ color: vpColor(color) }) : new THREE.MeshLambertMaterial({ color: vpColor(color) });
    if (transparency > 0.01) {
      mat.transparent = true;
      mat.opacity = Math.max(0.05, 1 - transparency);
    }
    const size = shape === SHAPE_CYLINDER ? [sx, Math.min(sy, sz), Math.min(sy, sz)] : [sx, sy, sz];
    const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
    m4.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
    const mesh = new THREE.Mesh(GEOMETRY[shape] || GEOMETRY[SHAPE_BLOCK], mat);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(m4).multiply(new THREE.Matrix4().makeScale(...size));
    mesh.matrixWorld.copy(mesh.matrix);
    scene.add(mesh);
    for (const sxn of [-0.5, 0.5]) for (const syn of [-0.5, 0.5]) for (const szn of [-0.5, 0.5]) corners.push(new THREE.Vector3(sxn, syn, szn).applyMatrix4(mesh.matrix));
  }
  // StoreView.frame: back off until every part's corners fit 0.94 of the 30 degree picture
  const dir = new THREE.Vector3(...model.from).normalize();
  const cross = new THREE.Vector3(0, 1, 0).cross(dir);
  const rightV = cross.length() > 1e-3 ? cross.normalize() : new THREE.Vector3(1, 0, 0);
  const upV = dir.clone().cross(rightV).normalize();
  const bounds = new THREE.Box3().setFromPoints(corners);
  const center = bounds.getCenter(new THREE.Vector3());
  const tall = Math.tan(15 * DEG) * 0.94;
  let distance = 0.1;
  for (const c of corners) {
    const at = c.clone().sub(center);
    distance = Math.max(distance, at.dot(dir) + Math.max(Math.abs(at.dot(upV)) / tall, Math.abs(at.dot(rightV)) / tall));
  }
  const camera = new THREE.PerspectiveCamera(30, 1, 0.05, 2000);
  camera.position.copy(center).addScaledVector(dir, distance);
  camera.lookAt(center);
  if (!litRenderer) {
    litRenderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    litRenderer.setPixelRatio(1);
    litRenderer.setClearColor(0x000000, 0);
  }
  litRenderer.setSize(S, S, false);
  litRenderer.render(scene, camera);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = cell;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(litRenderer.domElement, 0, 0, cell, cell);
  scene.traverse((o) => o.material && o.material.dispose());
  return canvas.toDataURL("image/png");
}

window.TOON = {
  async names() {
    return (await load()).order;
  },
  async render(name, opts = {}) {
    const cell = opts.cell || (await load()).cell || 256;
    return opts.mode === "lit" ? renderLit(name, cell) : renderToon(name, cell, opts.debug);
  },
};
window.__ready = true;
