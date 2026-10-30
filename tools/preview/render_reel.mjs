// Renders a frame-by-frame reel exported by a Lune tool (the shots of build/preview/<tag>_shots.json:
// one world scene + per-frame "extra" parts, a UI overlay and an optional camera "cam": { position, target, fov }),
// encodes an MP4 and draws its storyboard.
//   node tools/preview/render_reel.mjs <tag> [fps=20] [bitrate=4000000] [stills=i,j,...|-|board]
//   tags: levelup (lune run tools/lune/export_levelup.luau), minejuice (lune run tools/lune/export_mine_juice.luau)
// Frames: build/preview/<tag>_frames/, video: build/preview/<tag>.mp4 (macOS AVFoundation through encode_mp4.swift),
// storyboard: build/preview/<tag>_board.jpg from build/preview/<tag>_board.json ({ title, cells: [{ frame, caption }] }).
// With stills: only those frames -> build/preview/shots/<tag>_<i>.jpg (for checking), no video.
// With "board": only the storyboard again, from the frames already rendered.
// A three.js approximation of Roblox: the same game code poses everything, the renderer only draws it.
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
const args = process.argv.slice(2);
const tag = args[0] || "levelup";
const fps = Number(args[1] || 20);
const bitrate = Number(args[2] || 4000000);
const boardOnly = args[3] === "board";
const stills = args[3] && args[3] !== "-" && !boardOnly ? args[3].split(",").map(Number) : null;
const framesDir = path.join(scenesDir, `${tag}_frames`);
const shots = JSON.parse(fs.readFileSync(path.join(scenesDir, `${tag}_shots.json`), "utf8"));
const names = Object.keys(shots).sort();
// the page loads a copy of the first shot without its extra parts and UI
const first = { ...shots[names[0]] };
delete first.extra;
delete first.ui;
const worldShot = `${tag}_world`;
const all = { ...shots, [worldShot]: first };
const W = first.width || 1600;
const H = first.height || 900;

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png", ".ttf": "font/ttf", ".jpg": "image/jpeg" };
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

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: W, height: H } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
await page.goto(`http://127.0.0.1:${port}/index.html?scene=${first.scene}&shot=${worldShot}&w=${W}&h=${H}`);
await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 300000 });
const err = await page.evaluate(() => window.__error);
if (err) {
  console.error(err);
  process.exit(1);
}

const pad = (i) => String(i).padStart(4, "0");
if (stills) {
  fs.mkdirSync(path.join(scenesDir, "shots"), { recursive: true });
  for (const i of stills) {
    const name = names[Math.min(i, names.length - 1)];
    await page.evaluate(([fx, ui, cam]) => window.__frame(fx, ui, cam), [shots[name].extra, shots[name].ui, shots[name].cam]);
    const file = path.join(scenesDir, "shots", `${tag}_${pad(i)}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 90 });
    console.log("still", i, "->", path.relative(repo, file));
  }
} else {
  if (!boardOnly) {
    fs.rmSync(framesDir, { recursive: true, force: true });
    fs.mkdirSync(framesDir, { recursive: true });
    const t0 = Date.now();
    for (const [i, name] of names.entries()) {
      await page.evaluate(([fx, ui, cam]) => window.__frame(fx, ui, cam), [shots[name].extra, shots[name].ui, shots[name].cam]);
      await page.screenshot({ path: path.join(framesDir, `frame_${pad(i)}.jpg`), type: "jpeg", quality: 90 });
      if (i % 20 === 0) console.log(`frame ${i}/${names.length} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
    }
    const out = path.join(scenesDir, `${tag}.mp4`);
    execFileSync("swift", [path.join(here, "encode_mp4.swift"), framesDir, out, String(fps), String(bitrate)], { stdio: "inherit" });
    console.log("video ->", path.relative(repo, out));
  }

  // the storyboard: the picked frames with their captions, 4 a row
  const boardFile = path.join(scenesDir, `${tag}_board.json`);
  if (fs.existsSync(boardFile)) {
    const board = JSON.parse(fs.readFileSync(boardFile, "utf8"));
    const cells = board.cells || [];
    const cols = Math.min(4, cells.length);
    const cell = 520;
    const cellH = Math.round((cell * H) / W);
    const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
    const html = `<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:#151924;font-family:'Avenir Next','Helvetica Neue',sans-serif">
      <div style="color:#fff;font-weight:800;font-size:32px;padding:18px 24px 4px">TERRA FORGE · ${esc(board.title || tag)}</div>
      <div style="color:#b9c6da;font-weight:600;font-size:17px;padding:0 24px 8px">náhled z herního kódu (three.js, přibližně jako v Robloxu) · ${cells.length} okamžiků z videa ${tag}.mp4</div>
      <div style="display:grid;grid-template-columns:repeat(${cols},${cell}px);gap:14px;padding:12px 24px 24px">
      ${cells
        .map(
          (c, k) => `<div><div style="position:relative"><img src="/scenes/${tag}_frames/frame_${pad(Math.min(c.frame, names.length - 1))}.jpg" style="width:${cell}px;height:${cellH}px;display:block;border-radius:10px">
          <div style="position:absolute;left:8px;top:8px;background:rgba(0,0,0,0.62);color:#fff;font-size:15px;font-weight:700;padding:2px 9px;border-radius:7px">${k + 1} · ${(c.frame / (board.fps || fps)).toFixed(2)} s</div></div>
          <div style="color:#fff;font-size:19px;font-weight:700;padding:7px 4px 0;line-height:1.25">${esc(c.caption)}</div></div>`,
        )
        .join("")}
      </div></body></html>`;
    const rows = Math.ceil(cells.length / cols);
    const sheet = await browser.newPage({ viewport: { width: cell * cols + 14 * (cols - 1) + 48, height: (cellH + 60) * rows + 14 * (rows - 1) + 110 } });
    fs.writeFileSync(path.join(scenesDir, `${tag}_board.html`), html);
    await sheet.goto(`http://127.0.0.1:${port}/scenes/${tag}_board.html`, { waitUntil: "load" });
    await sheet.evaluate(async () => {
      await Promise.all([...document.images].map((img) => (img.complete ? null : new Promise((r) => (img.onload = img.onerror = r)))));
    });
    const sheetFile = path.join(scenesDir, `${tag}_board.jpg`);
    await sheet.screenshot({ path: sheetFile, type: "jpeg", quality: 84, fullPage: true });
    console.log("storyboard ->", path.relative(repo, sheetFile));
  }
}
await browser.close();
server.close();
