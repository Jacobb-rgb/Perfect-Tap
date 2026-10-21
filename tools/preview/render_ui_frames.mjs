// Renders exported UI frames (build/preview/<dir>/manifest.json + frame JSONs, e.g. from
// tools/lune/export_ui_motion.luau) over a still backdrop, encodes them into an MP4 and
// lays chosen frames out as a captioned strip JPG.
//   node tools/preview/render_ui_frames.mjs <dir> <backdrop> <out.mp4> <strip.jpg> [bitrate=6000000]
//     dir       a folder under build/preview with manifest.json:
//               { fps, width, height, frames: [{ file, caption? }], strip: [{ index, caption }], columns }
//     backdrop  an image under build/preview (e.g. shots/motion_backdrop.jpg)
// Frames go to build/preview/<dir>_jpg/; the MP4 is encoded with AVFoundation
// (tools/preview/encode_mp4.swift, macOS only).
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
const [dir, backdrop, outMp4, outStrip, bitrate = "6000000"] = process.argv.slice(2);
if (!dir || !backdrop || !outMp4 || !outStrip) {
  console.error("usage: render_ui_frames.mjs <dir> <backdrop> <out.mp4> <strip.jpg> [bitrate]");
  process.exit(1);
}
const manifest = JSON.parse(fs.readFileSync(path.join(scenesDir, dir, "manifest.json"), "utf8"));
const W = manifest.width || 1600;
const H = manifest.height || 900;
const fps = manifest.fps || 30;
const jpgDir = path.join(scenesDir, `${dir}_jpg`);

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".ttf": "font/ttf", ".png": "image/png", ".jpg": "image/jpeg" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url);
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
const page = await browser.newPage({ viewport: { width: W, height: H } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
await page.goto(`http://127.0.0.1:${port}/ui_frames.html?w=${W}&h=${H}&bg=${encodeURIComponent(backdrop)}`);
await page.waitForFunction(() => window.__ready, null, { timeout: 120000 });

// ONLY=12,40,93: just those frames (a quick look), no strip, no video
if (process.env.ONLY) {
  fs.mkdirSync(jpgDir, { recursive: true });
  for (const i of process.env.ONLY.split(",").map(Number)) {
    const frame = manifest.frames[i];
    await page.evaluate(([file, text]) => window.renderFrame(file, text), [`${dir}/${frame.file}`, frame.caption || ""]);
    const file = path.join(jpgDir, `frame_${String(i).padStart(4, "0")}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 90 });
    console.log("frame", i, "->", path.relative(repo, file));
  }
  await browser.close();
  server.close();
  process.exit(0);
}

fs.rmSync(jpgDir, { recursive: true, force: true });
fs.mkdirSync(jpgDir, { recursive: true });
const t0 = Date.now();
for (let i = 0; i < manifest.frames.length; i++) {
  const frame = manifest.frames[i];
  await page.evaluate(([file, text]) => window.renderFrame(file, text), [`${dir}/${frame.file}`, frame.caption || ""]);
  await page.screenshot({ path: path.join(jpgDir, `frame_${String(i).padStart(4, "0")}.jpg`), type: "jpeg", quality: 90 });
  if (i % 30 === 0) console.log(`frame ${i}/${manifest.frames.length} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
}

// the strip: chosen frames side by side with a caption under each
const strip = manifest.strip || [];
if (strip.length) {
  const columns = manifest.columns || 3;
  const tileW = Math.floor(W / 2.5);
  const tileH = Math.round((tileW * H) / W);
  const rows = Math.ceil(strip.length / columns);
  const capH = 40;
  const pad = 12;
  const sheetW = columns * tileW + (columns + 1) * pad;
  const sheetH = rows * (tileH + capH) + (rows + 1) * pad;
  const tiles = strip
    .map((s) => {
      const src = `http://127.0.0.1:${port}/scenes/${dir}_jpg/frame_${String(s.index).padStart(4, "0")}.jpg`;
      return `<div class="t"><img src="${src}"/><div class="c">${s.caption}</div></div>`;
    })
    .join("");
  await page.setViewportSize({ width: sheetW, height: sheetH });
  await page.setContent(`<!doctype html><html><head><style>
    @font-face { font-family: "Fredoka One"; src: url("http://127.0.0.1:${port}/node_modules/@fontsource/fredoka-one/files/fredoka-one-latin-400-normal.woff2"); }
    body { margin: 0; background: #16161c; }
    .g { display: grid; grid-template-columns: repeat(${columns}, ${tileW}px); gap: ${pad}px; padding: ${pad}px; }
    .t img { width: ${tileW}px; height: ${tileH}px; display: block; border-radius: 8px; }
    .c { height: ${capH}px; line-height: ${capH}px; color: #fff; font: 22px "Arial Rounded MT Bold", "Helvetica Neue", sans-serif; text-align: center; }
  </style></head><body><div class="g">${tiles}</div></body></html>`);
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map((img) => img.decode().catch(() => {})));
  });
  await page.screenshot({ path: outStrip, type: "jpeg", quality: 86, fullPage: true });
  console.log("strip ->", path.relative(repo, outStrip));
}
await browser.close();
server.close();

execFileSync("swift", [path.join(here, "encode_mp4.swift"), jpgDir, outMp4, String(fps), String(bitrate)], { stdio: "inherit" });
console.log("video ->", path.relative(repo, outMp4));
