// Renders the world animations showreel (world_anim.html) frame by frame, encodes an MP4 and a contact sheet.
//   node tools/preview/render_world_anim.mjs [width=1280] [height=720] [bitrate=6000000] [stills=t1,t2,...|-] [data=world_motion] [out=svet_animace]
// Needs build/preview/<data>.json (lune run tools/lune/export_world_motion.luau [fps] [golem_run]).
// Frames go to build/preview/world_frames/, the video to build/preview/<out>.mp4 (AVFoundation through
// tools/preview/encode_mp4.swift, macOS only), the contact sheet to build/preview/<out>.jpg (its moments and
// title come from the data: picks / sheetTitle).
// With stills: only those frames -> build/preview/shots/world_<t>.jpg (for checking).
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
const framesDir = path.join(scenesDir, "world_frames");
const args = process.argv.slice(2);
const width = Number(args[0] || 1280);
const height = Number(args[1] || 720);
const bitrate = Number(args[2] || 6000000);
const stills = args[3] && args[3] !== "-" ? args[3] : "";
const dataName = args[4] || "world_motion";
const outName = args[5] || "svet_animace";

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".jpg": "image/jpeg" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url === "/" ? "world_anim.html" : url);
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
await page.goto(`http://127.0.0.1:${port}/world_anim.html?w=${width}&h=${height}&data=${dataName}`);
await page.waitForFunction(() => window.__ready || window.__error, null, { timeout: 240000 });
const err = await page.evaluate(() => window.__error);
if (err) {
  console.error(err);
  process.exit(1);
}
const total = await page.evaluate(() => window.__frames);
const fps = await page.evaluate(() => window.__fps);

if (stills) {
  fs.mkdirSync(path.join(scenesDir, "shots"), { recursive: true });
  for (const t of String(stills).split(",").map(Number)) {
    await page.evaluate((t) => window.renderFrame(t), t);
    const file = path.join(scenesDir, "shots", `${dataName}_${t.toFixed(2)}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 90 });
    console.log("still", t, "->", path.relative(repo, file));
  }
} else {
  fs.rmSync(framesDir, { recursive: true, force: true });
  fs.mkdirSync(framesDir, { recursive: true });
  const t0 = Date.now();
  for (let i = 0; i < total; i++) {
    await page.evaluate((t) => window.renderFrame(t), i / fps);
    await page.screenshot({ path: path.join(framesDir, `frame_${String(i).padStart(4, "0")}.jpg`), type: "jpeg", quality: 92 });
    if (i % 30 === 0) console.log(`frame ${i}/${total} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
  }
  const out = path.join(scenesDir, `${outName}.mp4`);
  execFileSync("swift", [path.join(here, "encode_mp4.swift"), framesDir, out, String(fps), String(bitrate)], { stdio: "inherit" });
  console.log("video ->", path.relative(repo, out));

  // the contact sheet: 12 moments over the reel, 4 x 3, each with its time
  const meta = await page.evaluate(() => window.__meta || {});
  const moments = meta.picks || [0.6, 1.5, 3.35, 4.7, 6.78, 7.4, 10.3, 10.55, 12.6, 13.6, 15.0, 16.3];
  const picks = moments.map((t) => Math.min(total - 1, Math.round(t * fps)));
  const sheetTitle = meta.sheetTitle || "animace ve světě";
  const cell = 480, cellH = Math.round((cell * height) / width);
  const html = `<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:#141820;font-family:'Avenir Next',sans-serif">
    <div style="color:#fff;font-weight:800;font-size:30px;padding:18px 22px 6px">TERRA FORGE · ${sheetTitle} <span style="font-weight:600;font-size:18px;color:#b9c6da">(náhled z herního kódu, ${picks.length} okamžiků ze ${outName}.mp4)</span></div>
    <div style="display:grid;grid-template-columns:repeat(4,${cell}px);gap:10px;padding:12px 22px 22px">
    ${picks
      .map(
        (i) => `<div style="position:relative"><img src="/scenes/world_frames/frame_${String(i).padStart(4, "0")}.jpg" style="width:${cell}px;height:${cellH}px;display:block;border-radius:8px">
        <div style="position:absolute;left:8px;top:8px;background:rgba(0,0,0,0.6);color:#fff;font-size:15px;font-weight:700;padding:2px 8px;border-radius:6px">${(i / fps).toFixed(1)} s</div></div>`,
      )
      .join("")}
    </div></body></html>`;
  const rows = Math.ceil(picks.length / 4);
  const sheet = await browser.newPage({ viewport: { width: cell * 4 + 30 + 44, height: cellH * rows + 10 * (rows - 1) + 100 } });
  fs.writeFileSync(path.join(scenesDir, "world_sheet.html"), html);
  await sheet.goto(`http://127.0.0.1:${port}/scenes/world_sheet.html`, { waitUntil: "load" });
  await sheet.evaluate(async () => {
    await Promise.all([...document.images].map((img) => (img.complete ? null : new Promise((r) => (img.onload = img.onerror = r)))));
  });
  const sheetFile = path.join(scenesDir, `${outName}.jpg`);
  await sheet.screenshot({ path: sheetFile, type: "jpeg", quality: 88, fullPage: true });
  console.log("sheet ->", path.relative(repo, sheetFile));
}
await browser.close();
server.close();
