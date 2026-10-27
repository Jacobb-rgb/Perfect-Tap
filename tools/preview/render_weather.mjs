// Renders the weather reel (preview only): the lobby once through viewer.js, the weather drawn
// over it frame by frame by weather_overlay.js, the rainbow as 3D parts through viewer.js's
// window.__frame (re-rendered only when its strength steps). An approximation of Roblox.
//   lune run tools/lune/export_scene.luau world && lune run tools/lune/export_weather.luau
//   node tools/preview/render_weather.mjs [stills]      # stills: only the picked moments
// -> build/preview/pocasi.mp4 (macOS AVFoundation), build/preview/pocasi.jpg (contact sheet),
//    build/preview/shots/weather_<n>_<kind>.jpg (one still per weather kind)
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
const framesDir = path.join(scenesDir, "weather_frames");
const shotsDir = path.join(scenesDir, "shots");
const stillsOnly = process.argv[2] === "stills";
const data = JSON.parse(fs.readFileSync(path.join(scenesDir, "weather_reel.json"), "utf8"));
const W = data.width;
const H = data.height;
const shot = { ...data.shot, width: W, height: H };

// ---------------------------------------------------------------- the rainbow as parts
// Each band's polyline (the game's Bezier arcs, world space) becomes thin blocks facing the
// camera; LEVELS strengths, so the world is re-rendered only a few times.
const LEVELS = 6;
function rainbowParts(alpha) {
  const parts = [];
  if (alpha <= 0) return parts;
  const cam = data.shot.position;
  for (const band of data.rainbow) {
    for (let i = 0; i + 1 < band.points.length; i++) {
      const a = band.points[i];
      const b = band.points[i + 1];
      if (Math.min(a[1], b[1]) < data.seaY) continue;
      const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2];
      const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      const length = Math.hypot(...d);
      const Z = d.map((v) => v / length);
      const toCam = [cam[0] - mid[0], cam[1] - mid[1], cam[2] - mid[2]];
      let X = [Z[1] * toCam[2] - Z[2] * toCam[1], Z[2] * toCam[0] - Z[0] * toCam[2], Z[0] * toCam[1] - Z[1] * toCam[0]];
      const xl = Math.hypot(...X);
      X = X.map((v) => v / xl);
      const Y = [Z[1] * X[2] - Z[2] * X[1], Z[2] * X[0] - Z[0] * X[2], Z[0] * X[1] - Z[1] * X[0]];
      const t = 1 - (1 - (a[3] + b[3]) / 2) * alpha;
      const cf = [...mid, X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]];
      parts.push([0, band.width, 0.5, length * 1.02, cf, band.color, "SmoothPlastic", t, 0]);
    }
  }
  return parts;
}
for (let k = 0; k <= LEVELS; k++) {
  fs.writeFileSync(path.join(scenesDir, `weather_rainbow_${k}.json`), JSON.stringify({ parts: rainbowParts(k / LEVELS) }));
}

// ---------------------------------------------------------------- server + page
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png", ".ttf": "font/ttf", ".jpg": "image/jpeg" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  if (url === "/shots.json") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ weather_cam: shot }));
  }
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url === "/" ? "index.html" : url);
  if (!file.startsWith(here) && !file.startsWith(scenesDir)) return res.writeHead(403).end();
  fs.readFile(file, (err, body) => {
    if (err) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(body);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: W, height: H } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
await page.goto(`http://127.0.0.1:${port}/index.html?scene=world&shot=weather_cam&w=${W}&h=${H}`);
await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 300000 });
const err = await page.evaluate(() => window.__error);
if (err) {
  console.error(err);
  process.exit(1);
}
await page.addScriptTag({ url: "/weather_overlay.js" });
const info = await page.evaluate(() => window.weatherSetup("/scenes/weather_reel.json"));

let level = 0;
async function frame(i) {
  const r = await page.evaluate((i) => window.weatherFrame(i), i);
  const want = Math.round(r.rainbow * LEVELS);
  if (want !== level) {
    level = want;
    await page.evaluate((name) => window.__frame(name), `weather_rainbow_${level}`);
  }
  return r;
}

const names = ["jasno", "dest", "bourka", "krupobiti", "snih", "mlha", "vitr", "vedro", "duha"];
fs.mkdirSync(shotsDir, { recursive: true });
const stills = [];
if (stillsOnly) {
  for (const [n, i] of info.picks.entries()) {
    await frame(i);
    const file = path.join(shotsDir, `weather_${n}_${names[n] || n}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 88 });
    stills.push(file);
    console.log("still", i, "->", path.relative(repo, file));
  }
} else {
  fs.rmSync(framesDir, { recursive: true, force: true });
  fs.mkdirSync(framesDir, { recursive: true });
  const t0 = Date.now();
  for (let i = 0; i < info.frames; i++) {
    await frame(i);
    const file = path.join(framesDir, `frame_${String(i).padStart(4, "0")}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 90 });
    const n = info.picks.indexOf(i);
    if (n >= 0) {
      const still = path.join(shotsDir, `weather_${n}_${names[n] || n}.jpg`);
      fs.copyFileSync(file, still);
      stills.push(still);
    }
    if (i % 48 === 0) console.log(`frame ${i}/${info.frames} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
  }
  const out = path.join(scenesDir, "pocasi.mp4");
  execFileSync("swift", [path.join(here, "encode_mp4.swift"), framesDir, out, String(info.fps), "4000000"], { stdio: "inherit" });
  console.log("video ->", path.relative(repo, out));
}

// the contact sheet: one still per kind, 3 x 3
const cell = 520;
const cellH = Math.round((cell * H) / W);
const html = `<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:#1b1626;font-family:'Avenir Next',sans-serif">
  <div style="color:#fff;font-weight:800;font-size:30px;padding:18px 22px 6px">TERRA FORGE · počasí <span style="font-weight:600;font-size:18px;color:#c9bfe0">(náhled z herního kódu, three.js, ne Roblox)</span></div>
  <div style="display:grid;grid-template-columns:repeat(3,${cell}px);gap:10px;padding:12px 22px 22px">
  ${stills.map((f) => `<img src="/scenes/shots/${path.basename(f)}" style="width:${cell}px;height:${cellH}px;display:block;border-radius:8px">`).join("")}
  </div></body></html>`;
fs.writeFileSync(path.join(scenesDir, "weather_sheet.html"), html);
const rows = Math.ceil(stills.length / 3);
const sheet = await browser.newPage({ viewport: { width: cell * 3 + 20 + 44, height: cellH * rows + 10 * (rows - 1) + 100 } });
await sheet.goto(`http://127.0.0.1:${port}/scenes/weather_sheet.html`, { waitUntil: "load" });
await sheet.evaluate(async () => {
  await Promise.all([...document.images].map((img) => (img.complete ? null : new Promise((r) => (img.onload = img.onerror = r)))));
});
const sheetFile = path.join(scenesDir, "pocasi.jpg");
await sheet.screenshot({ path: sheetFile, type: "jpeg", quality: 86, fullPage: true });
console.log("sheet ->", path.relative(repo, sheetFile));
await browser.close();
server.close();
