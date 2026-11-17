// The owner's mesh templates without the collision hulls nobody needs (integrator review 2026-11-17:
// Shared/Assets/MeshAssets.rbxm sat in ReplicatedStorage with ~4.7 MB of hulls, PhysicalConfigData,
// that every client loaded at join, and only the rocks and the mossy cliff ever collide).
//
//   node tools/meshy/strip_hulls.mjs strip <file.rbxm> [names...]   every MeshPart but the named ones
//        CollisionFidelity Box and without its hull (tools/lune/import_meshes.luau names the templates
//        whose clones collide); the shared strings nothing points at any more go
//   node tools/meshy/strip_hulls.mjs boxes <place.rbxl>   every MeshPart without a hull Box (a finished
//        place: tools/build.sh, make_test_place.luau)
//
// Lune 0.8.9 and Rojo 7.4 (rbx-dom of 2024) can't do it themselves: they can't clear a SharedString
// and they write no CollisionFidelity at all, so every place they write is put right here afterwards
// (a MeshPart without the property loads as Default, which wants a hull). Chunks this changes are
// written uncompressed (Roblox and rbx_binary read those), the others stay as they were.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const DEFAULT = 0; // Enum.CollisionFidelity.Default
const BOX = 2; // Enum.CollisionFidelity.Box
const STRING = 0x01;
const ENUM = 0x12;
const SHARED_STRING = 0x1c;

// an LZ4 block (no frame, no size prefix: the chunk header holds the size)
function lz4Block(input, size) {
  const out = Buffer.alloc(size);
  let i = 0;
  let o = 0;
  while (i < input.length) {
    const token = input[i++];
    let literals = token >> 4;
    if (literals === 15) {
      let b;
      do {
        b = input[i++];
        literals += b;
      } while (b === 255);
    }
    input.copy(out, o, i, i + literals);
    i += literals;
    o += literals;
    if (i >= input.length) break;
    const offset = input[i] | (input[i + 1] << 8);
    i += 2;
    let length = token & 15;
    if (length === 15) {
      let b;
      do {
        b = input[i++];
        length += b;
      } while (b === 255);
    }
    length += 4;
    for (let k = 0; k < length; k++, o++) out[o] = out[o - offset];
  }
  if (o !== size) throw new Error(`lz4: ${o} bytes unpacked, the header says ${size}`);
  return out;
}

// an array of u32 as rbx_binary stores it: bytes interleaved, most significant first
function readU32s(buf, at, n) {
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = ((buf[at + i] << 24) | (buf[at + n + i] << 16) | (buf[at + 2 * n + i] << 8) | buf[at + 3 * n + i]) >>> 0;
  }
  return out;
}
function writeU32s(values) {
  const n = values.length;
  const b = Buffer.alloc(4 * n);
  for (let i = 0; i < n; i++) {
    const v = values[i] >>> 0;
    b[i] = (v >>> 24) & 255;
    b[n + i] = (v >>> 16) & 255;
    b[2 * n + i] = (v >>> 8) & 255;
    b[3 * n + i] = v & 255;
  }
  return b;
}
function u32(n) {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n);
  return b;
}

// every chunk: its name, its bytes as stored (header included) and its unpacked data
function readFile(file, where) {
  if (file.toString("latin1", 0, 8) !== "<roblox!") throw new Error(`${where}: not a binary Roblox file`);
  const chunks = [];
  let off = 32;
  while (off < file.length) {
    const name = file.toString("latin1", off, off + 4);
    const packed = file.readUInt32LE(off + 4);
    const size = file.readUInt32LE(off + 8);
    const body = file.subarray(off + 16, off + 16 + (packed || size));
    const raw = file.subarray(off, off + 16 + (packed || size));
    off += 16 + (packed || size);
    let data = body;
    if (packed) data = body.readUInt32LE(0) === 0xfd2fb528 ? zlib.zstdDecompressSync(body) : lz4Block(body, size);
    if (data.length !== size) throw new Error(`chunk ${name}: ${data.length} bytes unpacked, the header says ${size}`);
    chunks.push({ name, raw, data, changed: false });
    if (name === "END\0") break;
  }
  const classes = new Map(); // class id -> { cls, count }
  const props = []; // { chunk, id, prop, type, at (where the values start) }
  let sstr = null;
  for (const c of chunks) {
    const d = c.data;
    if (c.name === "INST") {
      const nl = d.readUInt32LE(4);
      classes.set(d.readUInt32LE(0), { cls: d.toString("utf8", 8, 8 + nl), count: d.readUInt32LE(9 + nl) });
    } else if (c.name === "PROP") {
      const nl = d.readUInt32LE(4);
      props.push({ chunk: c, id: d.readUInt32LE(0), prop: d.toString("utf8", 8, 8 + nl), type: d[8 + nl], at: 9 + nl });
    } else if (c.name === "SSTR") {
      const count = d.readUInt32LE(4);
      const entries = [];
      let p = 8;
      for (let i = 0; i < count; i++) {
        const len = d.readUInt32LE(p + 16);
        entries.push({ hash: d.subarray(p, p + 16), value: d.subarray(p + 20, p + 20 + len) });
        p += 20 + len;
      }
      sstr = { chunk: c, version: d.readUInt32LE(0), entries };
    }
  }
  return { head: file.subarray(0, 32), chunks, classes, props, sstr };
}

function writeFile(f, dst) {
  const out = [f.head];
  for (const c of f.chunks) {
    if (!c.changed) {
      out.push(c.raw);
      continue;
    }
    const head = Buffer.alloc(16);
    head.write(c.name, 0, "latin1");
    head.writeUInt32LE(0, 4); // stored as it is
    head.writeUInt32LE(c.data.length, 8);
    out.push(head, c.data);
  }
  fs.writeFileSync(dst, Buffer.concat(out));
}

function setValues(p, values, write) {
  p.chunk.data = Buffer.concat([p.chunk.data.subarray(0, p.at), write(values)]);
  p.chunk.changed = true;
}

function names(p, count) {
  const out = [];
  let at = p.at;
  for (let i = 0; i < count; i++) {
    const len = p.chunk.data.readUInt32LE(at);
    out.push(p.chunk.data.toString("utf8", at + 4, at + 4 + len));
    at += 4 + len;
  }
  return out;
}

// The MeshPart classes of a file: their count, names, hull indices and fidelities.
function meshParts(f) {
  const out = [];
  for (const [id, { cls, count }] of f.classes) {
    if (cls !== "MeshPart") continue;
    const find = (prop, type) => f.props.find((p) => p.id === id && p.prop === prop && p.type === type);
    const nameProp = find("Name", STRING);
    const hull = find("PhysicalConfigData", SHARED_STRING);
    const fidelity = find("CollisionFidelity", ENUM);
    out.push({
      id,
      count,
      names: nameProp ? names(nameProp, count) : new Array(count).fill(""),
      hull,
      hulls: hull ? readU32s(hull.chunk.data, hull.at, count) : null,
      fidelity,
      modes: fidelity ? readU32s(fidelity.chunk.data, fidelity.at, count) : new Array(count).fill(DEFAULT),
    });
  }
  return out;
}

// the fidelities back into the file (a new property chunk, before the parent links, where none was)
function writeModes(f, m) {
  if (m.fidelity) {
    setValues(m.fidelity, m.modes, writeU32s);
    return;
  }
  const name = Buffer.from("CollisionFidelity", "utf8");
  const data = Buffer.concat([u32(m.id), u32(name.length), name, Buffer.from([ENUM]), writeU32s(m.modes)]);
  const at = f.chunks.findIndex((c) => c.name === "PRNT");
  f.chunks.splice(at < 0 ? f.chunks.length - 1 : at, 0, { name: "PROP", data, changed: true });
}

const hullBytes = (f, m, i) => (m.hulls && f.sstr ? f.sstr.entries[m.hulls[i]].value.length : 0);

function strip(src, keep) {
  const f = readFile(fs.readFileSync(src), src);
  const before = f.sstr ? f.sstr.entries.reduce((sum, e) => sum + e.value.length, 0) : 0;
  let boxes = 0;
  let dropped = 0;
  let empty = f.sstr ? f.sstr.entries.findIndex((e) => e.value.length === 0) : -1;
  for (const m of meshParts(f)) {
    for (let i = 0; i < m.count; i++) {
      if (keep.has(m.names[i])) continue;
      m.modes[i] = BOX;
      boxes++;
      if (hullBytes(f, m, i) > 0) {
        if (empty < 0) {
          empty = f.sstr.entries.length;
          f.sstr.entries.push({ hash: crypto.createHash("md5").update(Buffer.alloc(0)).digest(), value: Buffer.alloc(0) });
        }
        m.hulls[i] = empty;
        dropped++;
      }
    }
    writeModes(f, m);
    if (m.hull) setValues(m.hull, m.hulls, writeU32s);
  }
  let after = before;
  if (f.sstr) {
    // the shared strings still pointed at, renumbered in the order they're first used
    const lists = f.props
      .filter((p) => p.type === SHARED_STRING)
      .map((p) => ({ p, values: readU32s(p.chunk.data, p.at, f.classes.get(p.id).count) }));
    const renumber = new Map();
    const kept = [];
    for (const { values } of lists) {
      for (const v of values) {
        if (!renumber.has(v)) {
          renumber.set(v, kept.length);
          kept.push(f.sstr.entries[v]);
        }
      }
    }
    for (const { p, values } of lists) setValues(p, values.map((v) => renumber.get(v)), writeU32s);
    const body = [u32(f.sstr.version), u32(kept.length)];
    for (const e of kept) body.push(e.hash, u32(e.value.length), e.value);
    f.sstr.chunk.data = Buffer.concat(body);
    f.sstr.chunk.changed = true;
    after = kept.reduce((sum, e) => sum + e.value.length, 0);
  }
  writeFile(f, src);
  const mb = (n) => (n / 1e6).toFixed(2);
  console.log(`strip_hulls: ${boxes} MeshParts Box, ${dropped} hulls dropped (${keep.size} named keep theirs), shared strings ${mb(before)} -> ${mb(after)} MB`);
}

function boxes(src) {
  const f = readFile(fs.readFileSync(src), src);
  let set = 0;
  let total = 0;
  for (const m of meshParts(f)) {
    let changed = !m.fidelity;
    for (let i = 0; i < m.count; i++) {
      total++;
      if (hullBytes(f, m, i) === 0 && m.modes[i] !== BOX) {
        m.modes[i] = BOX;
        set++;
        changed = true;
      }
    }
    if (changed) writeModes(f, m);
  }
  writeFile(f, src);
  console.log(`${path.basename(src)}: ${set} of ${total} MeshParts without a collision hull made CollisionFidelity Box`);
}

const [cmd, file, ...rest] = process.argv.slice(2);
if (cmd === "strip" && file) strip(file, new Set(rest));
else if (cmd === "boxes" && file) boxes(file);
else {
  console.error("usage: node tools/meshy/strip_hulls.mjs strip <file.rbxm> [names that keep their hulls...] | boxes <place.rbxl>");
  process.exit(2);
}
