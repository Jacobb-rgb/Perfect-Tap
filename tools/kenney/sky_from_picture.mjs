// Wraps one flat 16:9 sky picture round the whole sky as an equirectangular
// panorama, for tools/kenney/skybox.mjs to cut into Roblox's six faces:
//   node tools/kenney/sky_from_picture.mjs <picture.png> <panorama.png> [top=76] [bottom=-7]
// Two copies of the picture side by side make the 360 degrees, their cloudy
// left and right edges faded over each other so they meet without a seam.
// <top> and <bottom> are the elevations (degrees) of the picture's top and
// bottom edges. A flat picture would pinch into streaks at the zenith, so the
// top fades into a starry cap in the picture's own night blue; under the
// horizon it fades into the picture's low haze. Whites are capped a little
// under full so Bloom keeps the clouds crisp (Bloom Threshold 1 at Exposure
// 0.27 starts at 0.83 in linear light, and 0.9 in sRGB is 0.79 in linear).
// The sky in the game (LightingConfig.Skybox):
//   node tools/kenney/sky_from_picture.mjs docs/art/sky_vortex_source.png /tmp/sky_vir.png
//   node tools/kenney/skybox.mjs /tmp/sky_vir.png <out dir> 1024 117 0
import { readPng, writePng } from "./png.mjs";

const [input, output, topArg, bottomArg] = process.argv.slice(2);
if (!input || !output) {
  console.error("usage: node tools/kenney/sky_from_picture.mjs <picture.png> <panorama.png> [top] [bottom]");
  process.exit(1);
}
const TOP = +(topArg ?? 76);
const BOTTOM = +(bottomArg ?? -7);
const CAP_FROM = TOP - 16; // the starry cap starts to show here...
const CAP_FULL = 80; // ...and is all there is from here up
const OVERLAP = 0.2; // of the picture's width
const LOW_FROM = BOTTOM + 2;
const LOW_FULL = BOTTOM - 12;
const WHITE = 0.9;
const W = 4096, H = 2048;

const pic = readPng(input);
const PW = pic.width, PH = pic.height;
const rgb = new Float32Array(PW * PH * 3);
for (let y = 0; y < PH; y++)
  for (let x = 0; x < PW; x++) {
    const c = pic.get(x, y);
    rgb.set([c[0], c[1], c[2]], (y * PW + x) * 3);
  }

function sample(u, v, out) {
  const fx = Math.min(Math.max(u * PW - 0.5, 0), PW - 1.001);
  const fy = Math.min(Math.max(v * PH - 0.5, 0), PH - 1.001);
  const x0 = Math.floor(fx), y0 = Math.floor(fy), tx = fx - x0, ty = fy - y0;
  for (let k = 0; k < 3; k++) {
    const a = rgb[(y0 * PW + x0) * 3 + k], b = rgb[(y0 * PW + x0 + 1) * 3 + k];
    const c = rgb[((y0 + 1) * PW + x0) * 3 + k], d = rgb[((y0 + 1) * PW + x0 + 1) * 3 + k];
    out[k] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
  }
}

// the average colour of a box of the picture (u, v from 0 to 1)
function average(u0, v0, u1, v1) {
  const sum = [0, 0, 0];
  const c = [0, 0, 0];
  let n = 0;
  for (let v = v0; v < v1; v += 0.01)
    for (let u = u0; u < u1; u += 0.01) {
      sample(u, v, c);
      sum[0] += c[0]; sum[1] += c[1]; sum[2] += c[2];
      n++;
    }
  return sum.map((s) => s / n);
}
const CAP = average(0.3, 0.0, 0.42, 0.1); // the dark blue of the picture's starry top
const LOW = average(0.3, 0.92, 0.7, 1.0); // its low haze

const smooth = (a, b, t) => {
  const x = Math.min(Math.max((t - a) / (b - a), 0), 1);
  return x * x * (3 - 2 * x);
};
const fract = (x) => x - Math.floor(x);

// procedural stars for the cap, hashed in 3D so they stay round at the zenith
const hash = (x, y, z, k) => fract(Math.sin(x * 12.9898 + y * 78.233 + z * 37.719 + k * 19.19) * 43758.5453);
const STAR_CELL = 0.05; // about 3 degrees
function stars(dx, dy, dz) {
  const fx = dx / STAR_CELL, fy = dy / STAR_CELL, fz = dz / STAR_CELL;
  const cx = Math.floor(fx), cy = Math.floor(fy), cz = Math.floor(fz);
  let glow = 0;
  for (let k = -1; k <= 1; k++)
    for (let j = -1; j <= 1; j++)
      for (let i = -1; i <= 1; i++) {
        const x = cx + i, y = cy + j, z = cz + k;
        const pick = hash(x, y, z, 0);
        if (pick > 0.6) continue;
        const px = x + hash(x, y, z, 1), py = y + hash(x, y, z, 2), pz = z + hash(x, y, z, 3);
        const size = 0.06 + 0.14 * Math.pow(pick / 0.6, 5);
        const ex = fx - px, ey = fy - py, ez = fz - pz;
        glow = Math.max(glow, Math.exp(-(ex * ex + ey * ey + ez * ez) / (size * size)) * (0.5 + 0.5 * hash(x, y, z, 4)));
      }
  return glow;
}

// One copy of the picture, tiled: the last OVERLAP of its width fades over the
// first OVERLAP of the next copy, so its left and right clouds melt together
// without a mirror's butterfly shape.
function picture(lon, v, out) {
  const t = fract(2 * lon) * (1 - OVERLAP);
  sample(t, v, out);
  if (t < OVERLAP) {
    const r = out[0], g = out[1], b = out[2];
    sample(t + 1 - OVERLAP, v, out);
    const w = smooth(0, OVERLAP, t);
    out[0] += (r - out[0]) * w;
    out[1] += (g - out[1]) * w;
    out[2] += (b - out[2]) * w;
  }
}

// a soft shoulder instead of a hard clip
const cap = WHITE * 255;
const soft = (value) => (value <= cap * 0.75 ? value : cap * 0.75 + cap * 0.25 * (1 - Math.exp(-(value - cap * 0.75) / (cap * 0.25))));

const out = new Uint8Array(W * H * 3);
const c = [0, 0, 0];
for (let y = 0; y < H; y++) {
  const elevation = 90 - (180 * (y + 0.5)) / H;
  // the picture's rows, mirrored past both edges
  let v = (TOP - elevation) / (TOP - BOTTOM);
  if (v < 0) v = -v;
  if (v > 1) v = 2 - v;
  const capMix = smooth(CAP_FROM, CAP_FULL, elevation);
  const lowMix = 1 - smooth(LOW_FULL, LOW_FROM, elevation);
  const e = (elevation * Math.PI) / 180;
  for (let x = 0; x < W; x++) {
    const lon = (x + 0.5) / W; // 0..1 round the sky
    picture(lon, v, c);
    let r = c[0], g = c[1], b = c[2];
    if (capMix > 0) {
      const a = lon * 2 * Math.PI;
      const s = stars(Math.cos(e) * Math.cos(a), Math.cos(e) * Math.sin(a), Math.sin(e));
      const cr = CAP[0] + s * 215, cg = CAP[1] + s * 225, cb = CAP[2] + s * 235;
      r += (cr - r) * capMix; g += (cg - g) * capMix; b += (cb - b) * capMix;
    }
    if (lowMix > 0) {
      r += (LOW[0] - r) * lowMix; g += (LOW[1] - g) * lowMix; b += (LOW[2] - b) * lowMix;
    }
    out.set([Math.round(soft(r)), Math.round(soft(g)), Math.round(soft(b))], (y * W + x) * 3);
  }
}
writePng(output, W, H, out);
console.log(`${output}: ${W} x ${H} from ${PW} x ${PH}; picture from ${BOTTOM} to ${TOP} degrees; cap ${CAP.map(Math.round)}; low ${LOW.map(Math.round)}`);
