// Renders an animation page frame by frame and encodes an MP4 (default: the crate opening, anim.html).
//   node tools/preview/render_anim.mjs [fps=30] [width=1920] [height=1080] [frames=all] [stills=t1,t2,...] [still prefix]
// Needs build/preview/anim_crate.json (lune run tools/lune/export_anim.luau).
// Frames go to build/preview/anim_frames/, the video to build/preview/crate_opening.mp4
// (encoded with AVFoundation through tools/preview/encode_mp4.swift, macOS only).
// Other pages (same window.renderFrame(t) / __duration contract), through the environment:
//   ANIM_PAGE=moves.html ANIM_OUT=pohyby_hrace.mp4 ANIM_BITRATE=3500000 node tools/preview/render_anim.mjs 30 1280 720
//   (the player-move showreel: lune run tools/lune/export_moves.luau first)
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
const framesDir = path.join(scenesDir, "anim_frames");
const [fps = 30, width = 1920, height = 1080, maxFrames = 0, stills = "", prefix = "anim"] = process.argv.slice(2).map((v, i) => (i < 4 ? Number(v) : v));
const pageName = process.env.ANIM_PAGE || "anim.html";
const outName = process.env.ANIM_OUT || "crate_opening.mp4";
const bitrate = process.env.ANIM_BITRATE || "";

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url === "/" ? pageName : url);
  if (!file.startsWith(here) && !file.startsWith(scenesDir)) return res.writeHead(403).end();
  fs.readFile(file, (err, data) => {
    if (err) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width, height } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
await page.goto(`http://127.0.0.1:${port}/${pageName}?w=${width}&h=${height}`);
await page.waitForFunction(() => window.__ready || window.__error, null, { timeout: 240000 });
const err = await page.evaluate(() => window.__error);
if (err) {
  console.error(err);
  process.exit(1);
}
const duration = await page.evaluate(() => window.__duration);

if (stills) {
  // single test frames: build/preview/shots/anim_<t>.jpg
  fs.mkdirSync(path.join(scenesDir, "shots"), { recursive: true });
  for (const t of String(stills).split(",").map(Number)) {
    await page.evaluate((t) => window.renderFrame(t), t);
    const file = path.join(scenesDir, "shots", `${prefix}_${t.toFixed(2)}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 90 });
    console.log("still", t, "->", path.relative(repo, file));
  }
} else {
  fs.rmSync(framesDir, { recursive: true, force: true });
  fs.mkdirSync(framesDir, { recursive: true });
  const total = maxFrames || Math.round(duration * fps);
  const t0 = Date.now();
  for (let i = 0; i < total; i++) {
    await page.evaluate((t) => window.renderFrame(t), i / fps);
    await page.screenshot({ path: path.join(framesDir, `frame_${String(i).padStart(4, "0")}.jpg`), type: "jpeg", quality: 93 });
    if (i % 30 === 0) console.log(`frame ${i}/${total} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
  }
  const out = path.join(scenesDir, outName);
  const encodeArgs = [path.join(here, "encode_mp4.swift"), framesDir, out, String(fps)];
  if (bitrate) encodeArgs.push(bitrate);
  execFileSync("swift", encodeArgs, { stdio: "inherit" });
  console.log("video ->", path.relative(repo, out));
}
await browser.close();
server.close();
