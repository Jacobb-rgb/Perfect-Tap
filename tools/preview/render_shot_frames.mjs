// Renders a video whose frames are shots on one world (the camera fixed): each frame only
// swaps its "extra" parts and its UI overlay (viewer.js window.__frame), then encodes an MP4.
//   node tools/preview/render_shot_frames.mjs <shots.json> <out name> [fps=20] [stills=name,name]
// e.g. node tools/preview/render_shot_frames.mjs build/preview/egg_video_shots.json vejce_e 20
// (tools/lune/export_egg_panel.luau writes that file). The world loads once from the first
// shot. Frames: build/preview/<out>_frames/, video: build/preview/<out>.mp4 (macOS
// AVFoundation, tools/preview/encode_mp4.swift). With stills: only those frames, copied to
// build/preview/shots/<name>.jpg.
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
const [shotsFile, outName, fpsArg, stillsArg] = process.argv.slice(2);
if (!shotsFile || !outName) {
  console.error("usage: render_shot_frames.mjs <shots.json> <out name> [fps] [stills]");
  process.exit(1);
}
const fps = Number(fpsArg || 20);
const stills = stillsArg ? stillsArg.split(",") : null;
const framesDir = path.join(scenesDir, `${outName}_frames`);
const shots = JSON.parse(fs.readFileSync(path.resolve(repo, shotsFile), "utf8"));
const names = Object.keys(shots).sort();
// the page loads a copy of the first shot without its extra parts and UI
const first = { ...shots[names[0]] };
delete first.extra;
delete first.ui;
const all = { ...shots, __frames_world: first };

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png", ".ttf": "font/ttf" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  if (url === "/shots.json") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify(all));
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

const W = first.width || 1600;
const H = first.height || 900;
const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: W, height: H } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
await page.goto(`http://127.0.0.1:${port}/index.html?scene=${first.scene}&shot=__frames_world&w=${W}&h=${H}`);
await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 300000 });
const err = await page.evaluate(() => window.__error);
if (err) {
  console.error(err);
  process.exit(1);
}

const list = stills || names;
fs.rmSync(framesDir, { recursive: true, force: true });
fs.mkdirSync(framesDir, { recursive: true });
fs.mkdirSync(path.join(scenesDir, "shots"), { recursive: true });
const t0 = Date.now();
for (const [i, name] of list.entries()) {
  await page.evaluate(([fx, ui]) => window.__frame(fx, ui), [shots[name].extra, shots[name].ui]);
  const file = path.join(framesDir, `frame_${String(i).padStart(4, "0")}.jpg`);
  await page.screenshot({ path: file, type: "jpeg", quality: 92 });
  if (stills) fs.copyFileSync(file, path.join(scenesDir, "shots", `${name}.jpg`));
  if (i % 20 === 0) console.log(`frame ${i}/${list.length} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
}
if (!stills) {
  const out = path.join(scenesDir, `${outName}.mp4`);
  execFileSync("swift", [path.join(here, "encode_mp4.swift"), framesDir, out, String(fps)], { stdio: "inherit" });
  console.log("video ->", path.relative(repo, out));
}
await browser.close();
server.close();
