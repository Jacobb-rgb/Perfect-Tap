// Turns an equirectangular sky panorama (Kenney Skyboxes Space, CC0) into
// the six square images a Roblox Sky needs, ready to upload:
//   node tools/kenney/skybox.mjs <panorama.png> <out dir> [size=1024] [yaw=0] [tilt=0]
// yaw (degrees) turns the panorama about the vertical: the panorama longitude
// that ends up in the north (Roblox -Z, SkyboxFt); tilt (degrees) then raises
// the northern sky toward the zenith (a turn about the east-west axis), so a
// band low on the horizon can arch over the north.
// writes <out>/SkyboxBk.png ... SkyboxUp.png, plus build/preview/skybox/<name>.png
// (a 2048 x 1024 copy the preview renderer draws as the sky).
//
// Faces are cut like jaxry's panorama-to-cubemap (px nx py ny pz nz), then
// named and turned the way Roblox's "Custom Skyboxes 101" guide says:
// pz -> Bk, nz -> Ft, nx -> Lf, px -> Rt, py -> Up turned 90 degrees
// clockwise, ny -> Dn turned 90 degrees counter-clockwise.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readPng, writePng } from "./png.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const [input, outDir, sizeArg, yawArg, tiltArg] = process.argv.slice(2);
if (!input || !outDir) {
  console.error("usage: node tools/kenney/skybox.mjs <panorama.png> <out dir> [size] [yaw]");
  process.exit(1);
}
const size = +(sizeArg || 1024);
const yaw = ((+(yawArg || 0)) * Math.PI) / 180;
const tilt = ((+(tiltArg || 0)) * Math.PI) / 180;
const ct = Math.cos(tilt), st = Math.sin(tilt);
const pano = readPng(input);
const W = pano.width, H = pano.height;
const rgb = new Float32Array(W * H * 3);
for (let y = 0; y < H; y++)
  for (let x = 0; x < W; x++) {
    const c = pano.get(x, y);
    rgb.set([c[0], c[1], c[2]], (y * W + x) * 3);
  }

// bilinear read, wrapping around horizontally
function sample(fx, fy, out) {
  fy = Math.min(Math.max(fy, 0), H - 1);
  const x0 = Math.floor(fx), y0 = Math.floor(fy);
  const tx = fx - x0, ty = fy - y0;
  const xa = ((x0 % W) + W) % W, xb = (xa + 1) % W, ya = y0, yb = Math.min(y0 + 1, H - 1);
  for (let k = 0; k < 3; k++) {
    const a = rgb[(ya * W + xa) * 3 + k], b = rgb[(ya * W + xb) * 3 + k];
    const c = rgb[(yb * W + xa) * 3 + k], d = rgb[(yb * W + xb) * 3 + k];
    out[k] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
  }
}

// jaxry's face orientations: face-plane (x, y) in -1..1, y down the image
const faces = {
  pz: (x, y) => [-1, -x, -y],
  nz: (x, y) => [1, x, -y],
  px: (x, y) => [x, -1, -y],
  nx: (x, y) => [-x, 1, -y],
  py: (x, y) => [-y, -x, 1],
  ny: (x, y) => [y, -x, -1],
};
function renderFace(fn) {
  const img = new Uint8Array(size * size * 3);
  const c = [0, 0, 0];
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const [dx, cy, dz] = fn((2 * (x + 0.5)) / size - 1, (2 * (y + 0.5)) / size - 1);
      // undo the tilt (jaxry's frame: +x = north, +z = up)
      const cx = dx * ct + dz * st, cz = -dx * st + dz * ct;
      const r = Math.hypot(cx, cy, cz);
      const lon = (((Math.atan2(cy, cx) + yaw) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
      const lat = Math.acos(cz / r);
      sample((W * lon) / Math.PI / 2 - 0.5, (H * lat) / Math.PI - 0.5, c);
      img.set([Math.round(c[0]), Math.round(c[1]), Math.round(c[2])], (y * size + x) * 3);
    }
  return img;
}
function rotate(img, clockwise) {
  const out = new Uint8Array(img.length);
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const [sx, sy] = clockwise ? [y, size - 1 - x] : [size - 1 - y, x];
      out.set(img.subarray((sy * size + sx) * 3, (sy * size + sx) * 3 + 3), (y * size + x) * 3);
    }
  return out;
}

fs.mkdirSync(outDir, { recursive: true });
const plan = [
  ["SkyboxBk", "pz", 0],
  ["SkyboxFt", "nz", 0],
  ["SkyboxLf", "nx", 0],
  ["SkyboxRt", "px", 0],
  ["SkyboxUp", "py", 1],
  ["SkyboxDn", "ny", -1],
];
for (const [name, face, turn] of plan) {
  let img = renderFace(faces[face]);
  if (turn) img = rotate(img, turn > 0);
  writePng(path.join(outDir, `${name}.png`), size, size, img);
  console.log(`${name}.png <- ${face}${turn ? (turn > 0 ? " (turned clockwise)" : " (turned counter-clockwise)") : ""}`);
}

// the preview renderer's copy: 2048 x 1024, yaw applied the same way
const pw = 2048, ph = 1024;
const prev = new Uint8Array(pw * ph * 3);
const c = [0, 0, 0];
for (let y = 0; y < ph; y++)
  for (let x = 0; x < pw; x++) {
    sample(((x + 0.5) / pw) * W - 0.5, ((y + 0.5) / ph) * H - 0.5, c);
    prev.set([Math.round(c[0]), Math.round(c[1]), Math.round(c[2])], (y * pw + x) * 3);
  }
const prevDir = path.join(repo, "build/preview/skybox");
fs.mkdirSync(prevDir, { recursive: true });
const prevFile = path.join(prevDir, `${path.basename(input, ".png")}.png`);
writePng(prevFile, pw, ph, prev);
console.log(`preview copy -> ${path.relative(repo, prevFile)}`);
