// The stud pictures for the custom stud look (src/shared/Config/StudStyleConfig.luau).
//   node tools/studs/make_stud_textures.mjs
// One picture holds 2 x 2 studs (StudsPerTile = 2: one stud per stud, like
// Roblox's own surfaces). Each stud is a raised rounded square, 0.62 studs wide
// with a 0.07-stud bevel, the shape of Roblox's SurfaceType.Studs.
//   studs_color.png      white, with soft shading on the bevels (the part's colour tints it)
//   studs_normal.png     tangent-space normals, OpenGL (green = up in the picture)
//   studs_roughness.png  plastic sheen, a touch smoother on the stud tops
// Written to docs/art/studs (the source, for uploading) and build/preview/studs
// (the preview renderer). With Roblox Studio installed it also copies Roblox's
// own stud tile into build/preview/studs/native_studs.png for the Classic look's
// previews (never committed: it is Roblox's picture).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { writePng } from "../kenney/png.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const outDirs = [path.join(repo, "docs/art/studs"), path.join(repo, "build/preview/studs")];
for (const dir of outDirs) fs.mkdirSync(dir, { recursive: true });

const SIZE = 512; // px per picture (2 x 2 studs: 256 px per stud)
const CELLS = 2;
const HALF = 0.31; // stud half width (studs)
const RADIUS = 0.12; // corner radius
const BEVEL = 0.07; // bevel width
const HEIGHT = 0.08; // stud height (studs): the normal map's slopes
const LIGHT = normalize([-0.55, 0.55, 0.63]); // baked light for the colour map: from the top left

function normalize(v) {
  const l = Math.hypot(...v);
  return v.map((x) => x / l);
}

const smooth = (t) => t * t * (3 - 2 * t);

// signed distance to the stud's rounded square in its cell (u, v in 0..1)
function dist(u, v) {
  const qx = Math.abs(u - 0.5) - (HALF - RADIUS);
  const qy = Math.abs(v - 0.5) - (HALF - RADIUS);
  const outside = Math.hypot(Math.max(qx, 0), Math.max(qy, 0));
  return outside + Math.min(Math.max(qx, qy), 0) - RADIUS;
}

// height in studs at (x, y) studs in the picture (y up)
function height(x, y) {
  const u = x - Math.floor(x);
  const v = y - Math.floor(y);
  const d = dist(u, v);
  return HEIGHT * smooth(Math.min(1, Math.max(0, -d / BEVEL)));
}

const color = new Uint8Array(SIZE * SIZE * 3);
const normal = new Uint8Array(SIZE * SIZE * 3);
const rough = new Uint8Array(SIZE * SIZE * 3);
const px = CELLS / SIZE; // studs per pixel
const eps = px * 0.5;
const SUB = 3; // supersamples per side

for (let row = 0; row < SIZE; row++) {
  for (let col = 0; col < SIZE; col++) {
    let nx = 0, ny = 0, nz = 0, shade = 0, top = 0;
    for (let sy = 0; sy < SUB; sy++) {
      for (let sx = 0; sx < SUB; sx++) {
        const x = (col + (sx + 0.5) / SUB) * px;
        const y = (SIZE - row - (sy + 0.5) / SUB) * px; // picture row 0 is the top
        const dx = (height(x + eps, y) - height(x - eps, y)) / (2 * eps);
        const dy = (height(x, y + eps) - height(x, y - eps)) / (2 * eps);
        const n = normalize([-dx, -dy, 1]);
        nx += n[0];
        ny += n[1];
        nz += n[2];
        // the bevels lit from the top left, a soft contact shadow round each stud's foot
        const lit = n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2];
        const d = dist(x - Math.floor(x), y - Math.floor(y));
        const foot = d > 0 ? 1 - 0.16 * Math.max(0, 1 - d / 0.06) : 1;
        shade += Math.min(1, (0.62 + 0.38 * lit / LIGHT[2]) * foot);
        top += height(x, y) >= HEIGHT * 0.999 ? 1 : 0;
      }
    }
    const k = SUB * SUB;
    const n = normalize([nx / k, ny / k, nz / k]);
    const i = (row * SIZE + col) * 3;
    const c = Math.round(255 * Math.min(1, shade / k));
    color[i] = color[i + 1] = color[i + 2] = c;
    normal[i] = Math.round((n[0] * 0.5 + 0.5) * 255);
    normal[i + 1] = Math.round((n[1] * 0.5 + 0.5) * 255);
    normal[i + 2] = Math.round((n[2] * 0.5 + 0.5) * 255);
    const r = Math.round(150 - 22 * (top / k)); // roughness ~0.59, stud tops ~0.5
    rough[i] = rough[i + 1] = rough[i + 2] = r;
  }
}

for (const dir of outDirs) {
  writePng(path.join(dir, "studs_color.png"), SIZE, SIZE, color);
  writePng(path.join(dir, "studs_normal.png"), SIZE, SIZE, normal);
  writePng(path.join(dir, "studs_roughness.png"), SIZE, SIZE, rough);
}
console.log(`stud pictures ${SIZE} px -> ${outDirs.map((d) => path.relative(repo, d)).join(", ")}`);

// ---- Roblox's own stud tile (preview only) ----
const STUDIO_STUDS = "/Applications/RobloxStudio.app/Contents/Resources/PlatformContent/pc/textures/studs.dds";

// DXT1 decoder (the studs atlas is 128 x 2048 DXT1; tile 0 = SurfaceType.Studs, 2 x 2 studs)
function decodeDxt1(buf, width, height) {
  const out = new Uint8Array(width * height * 3);
  let pos = 128; // "DDS " + 124-byte header
  const c565 = (c) => [((c >> 11) & 31) * 255 / 31, ((c >> 5) & 63) * 255 / 63, (c & 31) * 255 / 31];
  for (let by = 0; by < height / 4; by++) {
    for (let bx = 0; bx < width / 4; bx++) {
      const a = buf.readUInt16LE(pos), b = buf.readUInt16LE(pos + 2), bits = buf.readUInt32LE(pos + 4);
      pos += 8;
      const ca = c565(a), cb = c565(b);
      const pal = a > b
        ? [ca, cb, ca.map((x, j) => (2 * x + cb[j]) / 3), ca.map((x, j) => (x + 2 * cb[j]) / 3)]
        : [ca, cb, ca.map((x, j) => (x + cb[j]) / 2), [0, 0, 0]];
      for (let p = 0; p < 16; p++) {
        const v = pal[(bits >>> (2 * p)) & 3];
        const o = ((by * 4 + (p >> 2)) * width + bx * 4 + (p & 3)) * 3;
        out[o] = Math.round(v[0]);
        out[o + 1] = Math.round(v[1]);
        out[o + 2] = Math.round(v[2]);
      }
    }
  }
  return out;
}

if (fs.existsSync(STUDIO_STUDS)) {
  const buf = fs.readFileSync(STUDIO_STUDS);
  const width = buf.readUInt32LE(16), height = buf.readUInt32LE(12);
  const all = decodeDxt1(buf, width, height);
  const tile = all.subarray(0, width * width * 3); // tile 0: the top square
  writePng(path.join(repo, "build/preview/studs/native_studs.png"), width, width, tile);
  console.log("Roblox's own stud tile -> build/preview/studs/native_studs.png (preview only)");
} else {
  console.log("Roblox Studio not found: Classic previews use the custom colour map");
}
