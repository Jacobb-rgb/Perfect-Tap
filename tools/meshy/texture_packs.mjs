// The owner's PBR models keep their texture packs (tools/meshy/texture_packs.json).
//
// When Studio's 3D Importer uploads a model with PBR maps it also uploads a "TexturePack": the
// maps packed for the engine at runtime (SurfaceAppearance.TexturePackContent, a Content property).
// The tools that write our places (Rojo 7.4, Lune 0.8.9: rbx-dom of 2024) can't carry Content
// properties, so every place they wrote had SurfaceAppearances without a pack. Studio then tries to
// make and upload a new pack for each one when the place runs: 137 at once hit Roblox's rate limit
// (HTTP 429, "PBR textures may not be visible in game", owner's Studio log 2026-11-15), and the
// models drew grey. A pack that failed to upload never shows in a published game.
//
// This tool puts the packs back into a finished place file, the way Studio itself saves them:
//   node tools/meshy/texture_packs.mjs inject <place.rbxl> [out.rbxl]   every SurfaceAppearance whose
//        maps are in the table gets its TexturePackContent (in place when no out is given)
//   node tools/meshy/texture_packs.mjs check <place.rbxl>    exit 1 if a SurfaceAppearance has no pack
//   node tools/meshy/texture_packs.mjs extract <studio.rbxl> adds a Studio-saved place's packs to the table
// Table key: the asset ids "ColorMap|NormalMap|RoughnessMap|MetalnessMap" (an empty map is "").
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const TABLE = path.join(path.dirname(fileURLToPath(import.meta.url)), "texture_packs.json");
const MAPS = ["ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap"];
const PACK = "TexturePackContent";
const CONTENT = 0x22;
const STRING = 0x01;

// ---------------------------------------------------------------- the binary format (rbx_binary)

function lz4(data, size) {
  const out = Buffer.alloc(size);
  let i = 0;
  let o = 0;
  while (i < data.length) {
    const token = data[i++];
    let literals = token >> 4;
    if (literals === 15) {
      let b;
      do {
        b = data[i++];
        literals += b;
      } while (b === 255);
    }
    data.copy(out, o, i, i + literals);
    i += literals;
    o += literals;
    if (i >= data.length) break;
    const back = data[i] | (data[i + 1] << 8);
    i += 2;
    let match = token & 15;
    if (match === 15) {
      let b;
      do {
        b = data[i++];
        match += b;
      } while (b === 255);
    }
    match += 4;
    for (let k = 0; k < match; k++) {
      out[o] = out[o - back];
      o++;
    }
  }
  if (o !== size) throw new Error(`lz4: ${o} bytes unpacked, header says ${size}`);
  return out;
}

// every chunk: its name, its raw bytes as stored (header included) and its unpacked data
function readChunks(file) {
  if (file.toString("latin1", 0, 8) !== "<roblox!") throw new Error("not a binary Roblox file");
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
    if (packed) data = body.readUInt32LE(0) === 0xfd2fb528 ? zlib.zstdDecompressSync(body) : lz4(body, size);
    if (data.length !== size) throw new Error(`chunk ${name}: ${data.length} bytes, header says ${size}`);
    chunks.push({ name, raw, data });
    if (name === "END\0") break;
  }
  return chunks;
}

function chunkBytes(name, data) {
  const head = Buffer.alloc(16);
  head.write(name, 0, "latin1");
  head.writeUInt32LE(0, 4); // stored as it is (Studio reads uncompressed chunks)
  head.writeUInt32LE(data.length, 8);
  return Buffer.concat([head, data]);
}

function str(buf, at) {
  const n = buf.readUInt32LE(at);
  return [buf.toString("utf8", at + 4, at + 4 + n), at + 4 + n];
}

function u32(n) {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n);
  return b;
}

// i32 arrays: zigzag, bytes interleaved most significant first
function readI32s(buf, at, n) {
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const x = ((buf[at + i] << 24) | (buf[at + n + i] << 16) | (buf[at + 2 * n + i] << 8) | buf[at + 3 * n + i]) >>> 0;
    out[i] = (x >>> 1) ^ -(x & 1);
  }
  return out;
}

function writeI32s(values) {
  const n = values.length;
  const out = Buffer.alloc(4 * n);
  for (let i = 0; i < n; i++) {
    const z = ((values[i] << 1) ^ (values[i] >> 31)) >>> 0;
    out[i] = (z >>> 24) & 255;
    out[n + i] = (z >>> 16) & 255;
    out[2 * n + i] = (z >>> 8) & 255;
    out[3 * n + i] = z & 255;
  }
  return out;
}

// A Content property's values (kind 0 = none, 1 = an uri; Studio writes two zero counts after the
// uris for the object kinds, which none of ours use).
function readContent(data, at, count) {
  const kinds = readI32s(data, at, count);
  let p = at + 4 * count;
  const uriCount = data.readUInt32LE(p);
  p += 4;
  const uris = [];
  for (let i = 0; i < uriCount; i++) {
    const [s, next] = str(data, p);
    uris.push(s);
    p = next;
  }
  let next = 0;
  return kinds.map((k) => {
    if (k === 1) return uris[next++];
    if (k === 0) return "";
    throw new Error(`a Content value of kind ${k} (only none and uri are known here)`);
  });
}

function contentChunk(classId, prop, values) {
  const kinds = values.map((v) => (v ? 1 : 0));
  const uris = values.filter((v) => v);
  const parts = [u32(classId), u32(Buffer.byteLength(prop)), Buffer.from(prop, "utf8"), Buffer.from([CONTENT]), writeI32s(kinds), u32(uris.length)];
  for (const uri of uris) parts.push(u32(Buffer.byteLength(uri)), Buffer.from(uri, "utf8"));
  parts.push(u32(0), u32(0));
  return chunkBytes("PROP", Buffer.concat(parts));
}

// ---------------------------------------------------------------- SurfaceAppearances in a place

const idOf = (s) => (String(s || "").match(/(\d+)\s*$/) || [, ""])[1];

function surfaces(chunks) {
  let classId = null;
  let count = 0;
  for (const c of chunks) {
    if (c.name !== "INST") continue;
    const [cls, at] = str(c.data, 4);
    if (cls === "SurfaceAppearance") {
      classId = c.data.readUInt32LE(0);
      count = c.data.readUInt32LE(at + 1);
    }
  }
  const props = {};
  let packIndex = -1;
  let lastProp = -1;
  chunks.forEach((c, i) => {
    if (c.name !== "PROP" || classId === null || c.data.readUInt32LE(0) !== classId) return;
    lastProp = i;
    const [prop, at] = str(c.data, 4);
    const type = c.data[at];
    let values = null;
    if (type === STRING) {
      values = [];
      let p = at + 1;
      for (let k = 0; k < count; k++) {
        const [s, next] = str(c.data, p);
        values.push(s);
        p = next;
      }
    } else if (type === CONTENT) {
      values = readContent(c.data, at + 1, count);
    }
    if (values) props[prop] = values;
    if (prop === PACK) packIndex = i;
  });
  const keys = [];
  for (let k = 0; k < count; k++) {
    keys.push(MAPS.map((m) => idOf((props[m + "Content"] || props[m] || [])[k])).join("|"));
  }
  return { classId, count, keys, packs: props[PACK] || new Array(count).fill(""), packIndex, lastProp };
}

function loadTable() {
  return fs.existsSync(TABLE) ? JSON.parse(fs.readFileSync(TABLE, "utf8")) : {};
}

// ---------------------------------------------------------------- commands

function inject(src, dst) {
  const file = fs.readFileSync(src);
  const chunks = readChunks(file);
  const s = surfaces(chunks);
  if (s.classId === null || s.count === 0) {
    if (dst !== src) fs.writeFileSync(dst, file);
    console.log(`${path.basename(dst)}: no SurfaceAppearances`);
    return;
  }
  const table = loadTable();
  const values = s.keys.map((key, k) => {
    const id = table[key] || idOf(s.packs[k]);
    return id ? `rbxassetid://${id}` : "";
  });
  const chunk = contentChunk(s.classId, PACK, values);
  const out = [file.subarray(0, 32)];
  chunks.forEach((c, i) => {
    if (i === s.packIndex) {
      out.push(chunk);
      return;
    }
    out.push(c.raw);
    if (s.packIndex < 0 && i === s.lastProp) out.push(chunk);
  });
  const result = Buffer.concat(out);
  // read it back: the same chunks, every SurfaceAppearance with the pack it should have
  const again = surfaces(readChunks(result));
  values.forEach((v, k) => {
    if ((again.packs[k] || "") !== v) throw new Error(`read back: SurfaceAppearance ${k} has "${again.packs[k]}", not "${v}"`);
  });
  fs.writeFileSync(dst, result);
  const missing = values.filter((v) => !v).length;
  console.log(`${path.basename(dst)}: ${s.count - missing} of ${s.count} SurfaceAppearances carry their texture pack`);
  if (missing) console.log(`  without one: ${[...new Set(s.keys.filter((_, k) => !values[k]))].slice(0, 8).join(", ")}${missing > 8 ? " ..." : ""}`);
}

function check(src) {
  const s = surfaces(readChunks(fs.readFileSync(src)));
  const table = loadTable();
  const without = s.keys.filter((key, k) => !idOf(s.packs[k]) && !table[key]);
  const stored = s.packs.filter((p) => idOf(p)).length;
  console.log(`${path.basename(src)}: ${s.count} SurfaceAppearances, ${stored} with a stored pack, ${without.length} with no pack known`);
  if (without.length) {
    console.log(`  no pack: ${[...new Set(without)].slice(0, 8).join(", ")}`);
    process.exitCode = 1;
  }
  if (stored < s.count) process.exitCode = 1;
}

function extract(src) {
  const s = surfaces(readChunks(fs.readFileSync(src)));
  const table = loadTable();
  let added = 0;
  s.keys.forEach((key, k) => {
    const id = idOf(s.packs[k]);
    if (id && table[key] !== id) {
      table[key] = id;
      added++;
    }
  });
  const sorted = Object.fromEntries(Object.entries(table).sort(([a], [b]) => (a < b ? -1 : 1)));
  fs.writeFileSync(TABLE, JSON.stringify(sorted, null, 1) + "\n");
  console.log(`${path.basename(src)}: ${s.count} SurfaceAppearances, ${added} packs added (table: ${Object.keys(sorted).length})`);
}

const [cmd, a, b] = process.argv.slice(2);
if (cmd === "inject" && a) inject(a, b || a);
else if (cmd === "check" && a) check(a);
else if (cmd === "extract" && a) extract(a);
else {
  console.error("usage: node tools/meshy/texture_packs.mjs inject <place.rbxl> [out.rbxl] | check <place.rbxl> | extract <studio.rbxl>");
  process.exit(2);
}
