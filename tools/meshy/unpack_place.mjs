// Makes a place saved by a current Roblox Studio readable for Lune 0.8.9 (rbx-dom of 2024), for
// tools/lune/import_meshes.luau (it calls this itself when Lune can't read the file):
//   - every zstd chunk is stored raw (old rbx_binary can't decode the new zstd frames),
//   - the new Content properties (type 0x22: MeshContent, TextureContent, ColorMapContent, ...) get
//     the classic string property next to them (MeshId, TextureID, ColorMap, ...) with the same ids,
//   - the Tags properties go (old rbx-dom expects another type for them; the templates need no tags).
// usage: node tools/meshy/unpack_place.mjs <in.rbxl> <out.rbxl>
import fs from "node:fs";
import zlib from "node:zlib";

const CONTENT_TO_STRING = {
  MeshContent: "MeshId",
  TextureContent: "TextureID",
  ColorMapContent: "ColorMap",
  NormalMapContent: "NormalMap",
  MetalnessMapContent: "MetalnessMap",
  RoughnessMapContent: "RoughnessMap",
};
const DROP = new Set(["Tags"]);

const [src, dst] = process.argv.slice(2);
if (!src || !dst) {
  console.error("usage: node tools/meshy/unpack_place.mjs <in.rbxl> <out.rbxl>");
  process.exit(2);
}
const file = fs.readFileSync(src);
if (file.toString("latin1", 0, 8) !== "<roblox!") throw new Error(`${src}: not a binary Roblox file`);

// an array of i32 as rbx_binary stores it: bytes interleaved (most significant first), zigzag-encoded
function readI32s(buf, at, n) {
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const x = ((buf[at + i] << 24) | (buf[at + n + i] << 16) | (buf[at + 2 * n + i] << 8) | buf[at + 3 * n + i]) >>> 0;
    out[i] = (x >>> 1) ^ -(x & 1);
  }
  return out;
}
function chunk(name, data) {
  const head = Buffer.alloc(16);
  head.write(name, 0, "latin1");
  head.writeUInt32LE(0, 4); // stored raw
  head.writeUInt32LE(data.length, 8);
  return [head, data];
}
function u32(n) {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n);
  return b;
}

const out = [file.subarray(0, 32)];
const classes = new Map();
const report = { unpacked: 0, converted: [], dropped: 0 };
let off = 32;
while (off < file.length) {
  const name = file.toString("latin1", off, off + 4);
  const clen = file.readUInt32LE(off + 4);
  const ulen = file.readUInt32LE(off + 8);
  let data = file.subarray(off + 16, off + 16 + (clen || ulen));
  off += 16 + (clen || ulen);
  if (clen) {
    if (data.readUInt32LE(0) !== 0xfd2fb528) throw new Error(`chunk ${name}: compressed, but not zstd`);
    data = zlib.zstdDecompressSync(data);
    if (data.length !== ulen) throw new Error(`chunk ${name}: ${data.length} bytes unpacked, header says ${ulen}`);
    report.unpacked++;
  }
  if (name === "INST") {
    const nl = data.readUInt32LE(4);
    classes.set(data.readUInt32LE(0), { cls: data.toString("utf8", 8, 8 + nl), count: data.readUInt32LE(9 + nl) });
  }
  if (name === "PROP") {
    const id = data.readUInt32LE(0);
    const nl = data.readUInt32LE(4);
    const prop = data.toString("utf8", 8, 8 + nl);
    const type = data[8 + nl];
    if (DROP.has(prop)) {
      report.dropped++;
      continue;
    }
    out.push(...chunk(name, data));
    const target = CONTENT_TO_STRING[prop];
    if (type === 0x22 && target) {
      // Content: the kind of each value (1 = an uri), then the uris in order (objects follow: unused)
      const { cls, count } = classes.get(id);
      let p = 9 + nl;
      const kinds = readI32s(data, p, count);
      p += 4 * count;
      const uriCount = data.readUInt32LE(p);
      p += 4;
      const uris = [];
      for (let i = 0; i < uriCount; i++) {
        const l = data.readUInt32LE(p);
        uris.push(data.subarray(p + 4, p + 4 + l));
        p += 4 + l;
      }
      let next = 0;
      const values = kinds.map((k) => (k === 1 ? uris[next++] : Buffer.alloc(0)));
      if (next !== uriCount) throw new Error(`${cls}.${prop}: ${next} uri values but ${uriCount} uris`);
      const body = [u32(id), u32(Buffer.byteLength(target)), Buffer.from(target, "utf8"), Buffer.from([0x01])];
      for (const v of values) body.push(u32(v.length), v);
      out.push(...chunk("PROP", Buffer.concat(body)));
      report.converted.push(`${cls}.${prop}->${target} (${uriCount})`);
    }
    continue;
  }
  out.push(...chunk(name, data));
  if (name === "END\0") break;
}
fs.writeFileSync(dst, Buffer.concat(out));
console.log(`unpacked ${report.unpacked} chunks, dropped ${report.dropped} Tags chunks, ${report.converted.join(", ") || "no Content properties"}`);
