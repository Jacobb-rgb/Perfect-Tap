// Turns Kenney 3D kit models (OBJ + colormap texture, CC0) into colored box
// lists that Luau rebuilds from Roblox parts (we never import meshes: see
// .claude/skills/kenney-style-builder). For each model in the manifest:
//   1. sample every triangle densely and mark the voxels it touches, with
//      the texture colour under each sample (surface voxels),
//   2. flood the outside from the grid border; whatever the flood can't
//      reach is enclosed interior (never visible),
//   3. merge surface voxels of one colour into boxes greedily; interior
//      voxels are wildcards a box may run through, so boxes stay big,
//   4. write src/server/World/Lobby/Backdrop/Horizon/Kenney/<Name>.luau.
//
//   KENNEY_KITS=/path/to/kity node tools/kenney/voxelize.mjs [tools/kenney/horizon_models.json] [Name ...]
// Manifest entry: { kit, model, n (grid steps along the longest side), merge
// (colour distance merged into one, default 24), clipBelow (model units),
// smooth (despeckle passes, default 1) }
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const outDir = process.env.VOXEL_OUT || path.join(repo, "src/server/World/Lobby/Backdrop/Horizon/Kenney");

function findKits() {
  const tries = [process.env.KENNEY_KITS, path.resolve(repo, "../kity"), path.resolve(repo, "../../../../kity")];
  for (const t of tries) if (t && fs.existsSync(t)) return t;
  throw new Error("Set KENNEY_KITS to the folder with the unzipped kenney_* kits");
}

// ---------------------------------------------------------------- PNG (8-bit RGB/RGBA/palette)
function readPng(file) {
  const buf = fs.readFileSync(file);
  let pos = 8;
  let width = 0, height = 0, colorType = 0, depth = 0, palette = null, trns = null;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      depth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error("interlaced PNG");
    } else if (type === "PLTE") palette = data;
    else if (type === "tRNS") trns = data;
    else if (type === "IDAT") idat.push(data);
    pos += 12 + len;
  }
  if (depth !== 8) throw new Error(`PNG bit depth ${depth}`);
  const channels = { 2: 3, 6: 4, 3: 1, 0: 1, 4: 2 }[colorType];
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const px = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? px[y * stride + x - channels] : 0;
      const b = y > 0 ? px[(y - 1) * stride + x] : 0;
      const c = x >= channels && y > 0 ? px[(y - 1) * stride + x - channels] : 0;
      let v = src[x];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      px[y * stride + x] = v & 255;
    }
  }
  return {
    width,
    height,
    get(x, y) {
      const i = y * stride + x * channels;
      if (colorType === 3) {
        const k = px[i];
        return [palette[k * 3], palette[k * 3 + 1], palette[k * 3 + 2], trns && k < trns.length ? trns[k] : 255];
      }
      if (colorType === 2) return [px[i], px[i + 1], px[i + 2], 255];
      if (colorType === 6) return [px[i], px[i + 1], px[i + 2], px[i + 3]];
      return [px[i], px[i], px[i], 255];
    },
  };
}

// ---------------------------------------------------------------- OBJ
function readObj(file) {
  const text = fs.readFileSync(file, "utf8");
  const v = [], vt = [], tris = [];
  let texture = null;
  for (const line of text.split("\n")) {
    const p = line.trim().split(/\s+/);
    if (p[0] === "v") v.push([+p[1], +p[2], +p[3]]);
    else if (p[0] === "vt") vt.push([+p[1], +p[2]]);
    else if (p[0] === "mtllib") {
      const mtl = fs.readFileSync(path.join(path.dirname(file), p.slice(1).join(" ")), "utf8");
      const m = mtl.match(/map_Kd\s+(.+)/);
      if (m) texture = path.join(path.dirname(file), m[1].trim());
    } else if (p[0] === "f") {
      const idx = p.slice(1).map((s) => s.split("/").map((n) => (n ? +n : 0)));
      for (let i = 1; i + 1 < idx.length; i++) tris.push([idx[0], idx[i], idx[i + 1]]);
    }
  }
  return { v, vt, tris, texture };
}

// ---------------------------------------------------------------- voxelize + merge
function voxelize(objFile, spec) {
  const { v, vt, tris, texture } = readObj(objFile);
  const tex = texture ? readPng(texture) : null;
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const p of v) for (let k = 0; k < 3; k++) (lo[k] = Math.min(lo[k], p[k])), (hi[k] = Math.max(hi[k], p[k]));
  const ext = hi.map((h, k) => h - lo[k]);
  const h = Math.max(...ext) / spec.n;
  // one empty voxel of padding on every side; a tiny offset keeps faces off voxel borders
  const origin = lo.map((l) => l - h + h * 0.013);
  const dim = ext.map((e) => Math.ceil(e / h) + 3);
  const [nx, ny, nz] = dim;
  const N = nx * ny * nz;
  const id = (x, y, z) => x + nx * (y + ny * z);
  const votes = new Map(); // voxel -> Map(colorKey -> weight)
  const colorOf = (uv) => {
    if (!tex || !uv) return [200, 200, 200];
    const u = ((uv[0] % 1) + 1) % 1, w = ((uv[1] % 1) + 1) % 1;
    const c = tex.get(Math.min(tex.width - 1, Math.floor(u * tex.width)), Math.min(tex.height - 1, Math.floor((1 - w) * tex.height)));
    return [c[0], c[1], c[2]];
  };
  for (const t of tris) {
    const P = t.map((q) => v[q[0] - 1]);
    const T = t.map((q) => (q[1] ? vt[q[1] - 1] : null));
    const edge = Math.max(...[0, 1, 2].map((i) => Math.hypot(...[0, 1, 2].map((k) => P[i][k] - P[(i + 1) % 3][k]))));
    const steps = Math.max(1, Math.ceil(edge / (h * 0.35)));
    // the triangle's colour: its texture at the centroid (Kenney colormaps are flat swatches)
    const uvc = T[0] && T[1] && T[2] ? [0, 1].map((k) => (T[0][k] + T[1][k] + T[2][k]) / 3) : null;
    const col = colorOf(uvc);
    const key = (col[0] << 16) | (col[1] << 8) | col[2];
    for (let i = 0; i <= steps; i++) {
      for (let j = 0; j <= steps - i; j++) {
        const a = i / steps, b = j / steps, c = 1 - a - b;
        const py = P[0][1] * c + P[1][1] * a + P[2][1] * b;
        // clipBelow drops what sits under a height (a hex building's own tile, a hull under the waterline)
        if (spec.clipBelow !== undefined && py < spec.clipBelow + 1e-3) continue;
        const x = Math.floor((P[0][0] * c + P[1][0] * a + P[2][0] * b - origin[0]) / h);
        const y = Math.floor((py - origin[1]) / h);
        const z = Math.floor((P[0][2] * c + P[1][2] * a + P[2][2] * b - origin[2]) / h);
        const k = id(x, y, z);
        let m = votes.get(k);
        if (!m) votes.set(k, (m = new Map()));
        m.set(key, (m.get(key) || 0) + 1);
      }
    }
  }
  // 0 empty-outside, 1 surface, 2 interior
  const kind = new Uint8Array(N);
  const color = new Int32Array(N).fill(-1);
  for (const [k, m] of votes) {
    kind[k] = 1;
    let best = -1, bw = -1;
    for (const [c, w] of m) if (w > bw) (bw = w), (best = c);
    color[k] = best;
  }
  // flood the outside
  const outside = new Uint8Array(N);
  const stack = [id(0, 0, 0)];
  outside[stack[0]] = 1;
  while (stack.length) {
    const k = stack.pop();
    const x = k % nx, y = Math.floor(k / nx) % ny, z = Math.floor(k / (nx * ny));
    for (const [dx, dy, dz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
      const X = x + dx, Y = y + dy, Z = z + dz;
      if (X < 0 || Y < 0 || Z < 0 || X >= nx || Y >= ny || Z >= nz) continue;
      const q = id(X, Y, Z);
      if (!outside[q] && kind[q] === 0) (outside[q] = 1), stack.push(q);
    }
  }
  for (let k = 0; k < N; k++) if (kind[k] === 0 && !outside[k]) kind[k] = 2;
  // despeckle: a surface voxel whose colour is rare around it takes the
  // colour most of its surface neighbours share (windows, rivets, seams)
  for (let pass = 0; pass < (spec.smooth ?? 1); pass++) {
    const next = color.slice();
    for (let z = 1; z < nz - 1; z++)
      for (let y = 1; y < ny - 1; y++)
        for (let x = 1; x < nx - 1; x++) {
          const k = id(x, y, z);
          if (kind[k] !== 1) continue;
          const counts = new Map();
          for (let dz = -1; dz <= 1; dz++)
            for (let dy = -1; dy <= 1; dy++)
              for (let dx = -1; dx <= 1; dx++) {
                const q = id(x + dx, y + dy, z + dz);
                if (kind[q] === 1) counts.set(color[q], (counts.get(color[q]) || 0) + 1);
              }
          let best = color[k], bc = 0;
          for (const [c, n] of counts) if (n > bc) (bc = n), (best = c);
          if ((counts.get(color[k]) || 0) <= 2 && bc >= 5) next[k] = best;
        }
    color.set(next);
  }
  // merge near-identical colours (texture seams)
  const palette = [];
  const remap = new Map();
  for (let k = 0; k < N; k++) {
    if (color[k] < 0) continue;
    if (!remap.has(color[k])) {
      const c = color[k], r = c >> 16, g = (c >> 8) & 255, b = c & 255;
      let found = palette.findIndex((p) => Math.abs(p[0] - r) + Math.abs(p[1] - g) + Math.abs(p[2] - b) < (spec.merge ?? 24));
      if (found < 0) (found = palette.length), palette.push([r, g, b]);
      remap.set(c, found);
    }
    color[k] = remap.get(color[k]);
  }
  // greedy boxes over the surface voxels, interior as wildcard; try three axis orders, keep the fewest
  const orders = [[0, 2, 1], [2, 0, 1], [0, 1, 2]];
  let bestBoxes = null;
  for (const order of orders) {
    const used = new Uint8Array(N);
    const boxes = [];
    const fits = (q, c) => kind[q] === 2 || (kind[q] === 1 && !used[q] && color[q] === c);
    for (let z = 0; z < nz; z++)
      for (let y = 0; y < ny; y++)
        for (let x = 0; x < nx; x++) {
          const k0 = id(x, y, z);
          if (kind[k0] !== 1 || used[k0]) continue;
          const c = color[k0];
          const start = [x, y, z];
          const size = [1, 1, 1];
          const ok = (s) => {
            for (let dz = 0; dz < s[2]; dz++)
              for (let dy = 0; dy < s[1]; dy++)
                for (let dx = 0; dx < s[0]; dx++) {
                  const X = start[0] + dx, Y = start[1] + dy, Z = start[2] + dz;
                  if (X >= nx || Y >= ny || Z >= nz || !fits(id(X, Y, Z), c)) return false;
                }
            return true;
          };
          for (const axis of order) {
            for (;;) {
              const s = size.slice();
              s[axis]++;
              if (!ok(s)) break;
              size[axis]++;
            }
          }
          let surface = 0;
          for (let dz = 0; dz < size[2]; dz++)
            for (let dy = 0; dy < size[1]; dy++)
              for (let dx = 0; dx < size[0]; dx++) {
                const q = id(x + dx, y + dy, z + dz);
                if (kind[q] === 1) (used[q] = 1), surface++;
              }
          boxes.push([x, y, z, x + size[0], y + size[1], z + size[2], c]);
        }
    if (!bestBoxes || boxes.length < bestBoxes.length) bestBoxes = boxes;
  }
  // drop colours no box uses, renumber
  const usedColors = [...new Set(bestBoxes.map((b) => b[6]))];
  const boxes = bestBoxes.map((b) => [...b.slice(0, 6), usedColors.indexOf(b[6]) + 1]);
  return { h, origin, dim, palette: usedColors.map((i) => palette[i]), boxes, lo, hi };
}

function writeLuau(name, spec, res) {
  const hex = (c) => c.map((n) => n.toString(16).padStart(2, "0")).join("");
  const r = (n) => +n.toFixed(4);
  const lines = [
    "--[[",
    `\t${name}: Kenney ${spec.kit} "${spec.model}" (CC0, kenney.nl) rebuilt as ${res.boxes.length} boxes.`,
    "\tGENERATED by tools/kenney/voxelize.mjs (tools/kenney/horizon_models.json): do not edit, re-run the tool.",
    "\tUnits are Kenney model units; Voxel = size of one grid step, Origin = model-space corner of voxel (0, 0, 0).",
    "\tBoxes is flat: x0, y0, z0, x1, y1, z1 (grid, max exclusive), colour index, ...",
    "]]",
    "",
    "return {",
    `\tVoxel = ${r(res.h)},`,
    `\tOrigin = { ${res.origin.map(r).join(", ")} },`,
    `\tMin = { ${res.lo.map(r).join(", ")} },`,
    `\tMax = { ${res.hi.map(r).join(", ")} },`,
    `\tColors = { ${res.palette.map((c) => `"${hex(c)}"`).join(", ")} },`,
    "\tBoxes = {",
  ];
  for (const b of res.boxes) lines.push(`\t\t${b.join(", ")},`);
  lines.push("\t},", "}", "");
  fs.writeFileSync(path.join(outDir, `${name}.luau`), lines.join("\n"));
}

const manifestFile = process.argv[2] && process.argv[2].endsWith(".json") ? process.argv[2] : path.join(here, "horizon_models.json");
const only = process.argv.slice(process.argv[2] && process.argv[2].endsWith(".json") ? 3 : 2);
const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
const kits = findKits();
fs.mkdirSync(outDir, { recursive: true });
for (const [name, spec] of Object.entries(manifest)) {
  if (only.length && !only.includes(name)) continue;
  const obj = path.join(kits, `kenney_${spec.kit}`, "Models", "OBJ format", `${spec.model}.obj`);
  const res = voxelize(obj, spec);
  writeLuau(name, spec, res);
  console.log(`${name.padEnd(18)} ${spec.kit}/${spec.model}  grid ${res.dim.join("x")}  boxes ${res.boxes.length}  colours ${res.palette.length}`);
}
