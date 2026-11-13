// A camera tour video through several exported scenes (one segment per place, each with its own
// lighting preset, lights and caption), for the owner: "a video of what the whole world looks like".
//   node tools/preview/render_tour.mjs <tour.json> [tag=tour]
// tour.json: { fps, width, height, bitrate, segments: [ { scene, preset, title, seconds, fov, shadowExtent,
//   maxLights, sunDir, keys: [ { position: [x, y, z], target: [x, y, z] }, ... ] } ] }
// The camera glides through the keys (smoothed), the lights and the sun's shadow box are set up around
// the segment's middle target. Scenes come from export_scene.luau (MESHY=1 for the owner's models: the
// processed .glb files are served like render.mjs does). Frames: build/preview/<tag>_frames/,
// video: build/preview/<tag>.mp4 (encode_mp4.swift), storyboard: build/preview/<tag>_board.jpg.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const scenesDir = path.join(repo, "build/preview");
const tourFile = process.argv[2];
const tag = process.argv[3] || "tour";
const tour = JSON.parse(fs.readFileSync(tourFile, "utf8"));
const fps = tour.fps || 20;
const W = tour.width || 1280;
const H = tour.height || 720;
const framesDir = path.join(scenesDir, `${tag}_frames`);

// the processed .glb files of the owner's models (as in render.mjs)
function meshSets() {
  const sets = [];
  if (process.env.MESH_DIR) sets.push(process.env.MESH_DIR);
  let dir = repo;
  for (let i = 0; i < 6; i++) {
    const up = path.join(dir, "NAHRAJ_DO_ROBLOXU");
    if (fs.existsSync(up)) {
      for (const name of fs.readdirSync(up).filter((n) => n.startsWith("3D_modely_")).sort().reverse()) sets.push(path.join(up, name));
      break;
    }
    dir = path.dirname(dir);
  }
  return sets;
}
const MESH_SETS = meshSets();
function meshFile(name) {
  if (name.includes("/") || name.includes("..")) return null;
  for (const set of MESH_SETS) {
    const file = path.join(set, name);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

let shots = {};
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png", ".ttf": "font/ttf", ".jpg": "image/jpeg" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  if (url === "/shots.json") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify(shots));
  }
  if (url === "/scenes/tour_empty.json") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end('{"parts":[]}');
  }
  if (url.startsWith("/scenes/meshes/")) {
    const glb = meshFile(url.slice("/scenes/meshes/".length));
    if (!glb) return res.writeHead(404).end();
    return fs.readFile(glb, (err, data) => {
      if (err) return res.writeHead(404).end();
      res.writeHead(200, { "Content-Type": "model/gltf-binary" });
      res.end(data);
    });
  }
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url === "/" ? "index.html" : url);
  if (!file.startsWith(here) && !file.startsWith(scenesDir)) return res.writeHead(403).end();
  fs.readFile(file, (err, data) => {
    if (err) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

// a smooth path through the keys: Catmull-Rom between the points, eased in and out over the segment
const ease = (t) => t * t * (3 - 2 * t);
function along(points, t) {
  const n = points.length;
  if (n === 1) return points[0];
  const u = ease(Math.min(Math.max(t, 0), 1)) * (n - 1);
  const i = Math.min(Math.floor(u), n - 2);
  const f = u - i;
  const p0 = points[Math.max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[Math.min(i + 2, n - 1)];
  return [0, 1, 2].map((k) => {
    const a = p0[k], b = p1[k], c = p2[k], d = p3[k];
    return 0.5 * (2 * b + (-a + c) * f + (2 * a - 5 * b + 4 * c - d) * f * f + (-a + 3 * b - 3 * c + d) * f * f * f);
  });
}

fs.rmSync(framesDir, { recursive: true, force: true });
fs.mkdirSync(framesDir, { recursive: true });
const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const pad = (i) => String(i).padStart(5, "0");
let frame = 0;
const board = { title: tour.title || "Celý svět", fps, cells: [] };
const t0 = Date.now();
for (const [si, seg] of tour.segments.entries()) {
  const keys = seg.keys;
  const mid = keys[Math.floor(keys.length / 2)];
  const shotName = `tour_${si}`;
  shots = {
    [shotName]: {
      scene: seg.scene,
      position: keys[0].position,
      target: mid.target,
      fov: seg.fov || 60,
      preset: seg.preset || "Surface",
      shadowExtent: seg.shadowExtent || 220,
      maxLights: seg.maxLights || 32,
      ...(seg.sunDir ? { sunDir: seg.sunDir } : {}),
      ...(seg.exposure ? { exposure: seg.exposure } : {}),
    },
  };
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
  await page.goto(`http://127.0.0.1:${port}/index.html?scene=${seg.scene}&shot=${shotName}&w=${W}&h=${H}`);
  await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 600000 });
  const err = await page.evaluate(() => window.__error);
  if (err) {
    console.error(seg.title, err);
    process.exit(1);
  }
  // the caption: the place's name in the top-left corner
  await page.evaluate((title) => {
    const tagEl = document.createElement("div");
    tagEl.textContent = title;
    tagEl.style.cssText =
      "position:fixed;left:28px;top:22px;z-index:99;padding:8px 18px;border-radius:12px;background:rgba(10,12,24,0.62);color:#fff;font:800 30px 'Avenir Next','Helvetica Neue',sans-serif;letter-spacing:0.5px;text-shadow:0 2px 6px rgba(0,0,0,0.6)";
    document.body.appendChild(tagEl);
  }, seg.title);
  const count = Math.max(2, Math.round((seg.seconds || 6) * fps));
  const positions = keys.map((k) => k.position);
  const targets = keys.map((k) => k.target);
  for (let f = 0; f < count; f++) {
    const t = f / (count - 1);
    await page.evaluate(([cam]) => window.__frame("tour_empty", null, cam), [{ position: along(positions, t), target: along(targets, t), fov: seg.fov || 60 }]);
    await page.screenshot({ path: path.join(framesDir, `frame_${pad(frame)}.jpg`), type: "jpeg", quality: 88 });
    if (f === Math.floor(count / 2)) board.cells.push({ frame, caption: seg.title });
    frame++;
  }
  console.log(`segment ${si + 1}/${tour.segments.length} "${seg.title}": ${count} frames (${((Date.now() - t0) / 1000).toFixed(0)} s)`);
  await page.close();
}
const out = path.join(scenesDir, `${tag}.mp4`);
execFileSync("swift", [path.join(here, "encode_mp4.swift"), framesDir, out, String(fps), String(tour.bitrate || 6000000)], { stdio: "inherit" });
console.log("video ->", path.relative(repo, out));

// the storyboard: the middle frame of each place, 3 a row
const cols = 3;
const cell = 520;
const cellH = Math.round((cell * H) / W);
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
const html = `<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:#151924;font-family:'Avenir Next','Helvetica Neue',sans-serif">
  <div style="color:#fff;font-weight:800;font-size:32px;padding:18px 24px 4px">TERRA FORGE · ${esc(board.title)}</div>
  <div style="color:#b9c6da;font-weight:600;font-size:17px;padding:0 24px 8px">náhled z herního kódu (three.js, přibližně jako v Robloxu) · ${board.cells.length} míst z videa</div>
  <div style="display:grid;grid-template-columns:repeat(${cols},${cell}px);gap:14px;padding:12px 24px 24px">
  ${board.cells.map((c) => `<div><img src="/scenes/${tag}_frames/frame_${pad(c.frame)}.jpg" style="width:${cell}px;height:${cellH}px;display:block;border-radius:10px"><div style="color:#fff;font-size:19px;font-weight:700;padding:7px 4px 0">${esc(c.caption)}</div></div>`).join("")}
  </div></body></html>`;
fs.writeFileSync(path.join(scenesDir, `${tag}_board.html`), html);
const rows = Math.ceil(board.cells.length / cols);
const sheet = await browser.newPage({ viewport: { width: cell * cols + 14 * (cols - 1) + 48, height: (cellH + 48) * rows + 14 * (rows - 1) + 110 } });
await sheet.goto(`http://127.0.0.1:${port}/scenes/${tag}_board.html`, { waitUntil: "load" });
await sheet.evaluate(async () => {
  await Promise.all([...document.images].map((img) => (img.complete ? null : new Promise((r) => (img.onload = img.onerror = r)))));
});
await sheet.screenshot({ path: path.join(scenesDir, `${tag}_board.jpg`), type: "jpeg", quality: 84, fullPage: true });
console.log("storyboard ->", path.relative(repo, path.join(scenesDir, `${tag}_board.jpg`)));
await browser.close();
server.close();
