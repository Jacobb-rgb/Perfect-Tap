// Contact sheet of a move showreel: 3 key frames per move in a grid with captions.
//   node tools/preview/moves_sheet.mjs [out=build/preview/pohyby_hrace.jpg] [scene=anim_moves]
// Needs build/preview/<scene>.json (lune run tools/lune/export_moves.luau, or export_emotes.luau
// for scene anim_emotes: its segments carry their own picks); renders moves.html?clean=1.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const scenesDir = path.join(repo, "build/preview");
const out = path.resolve(repo, process.argv[2] || "build/preview/pohyby_hrace.jpg");
const sceneName = (process.argv[3] || "anim_moves").replace(/[^a-z_]/gi, "");

// [segment-relative seconds, caption] per move (the segment starts come from the JSON)
const PICKS = {
  Carry: [[1.0, "nese rudu"], [1.4, "krok"], [1.8, "krok"]],
  Throw: [[0.73, "nápřah"], [0.82, "hod"], [0.92, "dokončení"]],
  Recoil: [[0.43, "výstřel"], [0.55, "návrat"], [0.65, "další rána"]],
  Spray: [[0.8, "stříká"], [0.93, "stříká"], [1.05, "stříká"]],
  Hammer: [[1.1, "nápřah"], [1.36, "úder"], [1.46, "odraz"]],
  Celebrate: [[0.44, "podřep"], [0.64, "skok"], [0.98, "jo!"]],
  BigCelebrate: [[0.46, "podřep"], [0.8, "otočka ve skoku"], [1.38, "ta-da"]],
  CashToss: [[0.46, "nabrat"], [0.62, "vyhodit"], [0.9, "déšť peněz"]],
  Wave: [[0.48, "mává"], [0.68, "mává"], [0.88, "mává"]],
  Shrug: [[0.3, "klid"], [0.5, "pokrčí"], [0.9, "pokrčí"]],
};
const TITLES = { BigCelebrate: "BIG CELEBRATE", CashToss: "CASH TOSS" };

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url === "/" ? "moves.html" : url);
  if (!file.startsWith(here) && !file.startsWith(scenesDir)) return res.writeHead(403).end();
  fs.readFile(file, (err, data) => {
    if (err) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const data = JSON.parse(fs.readFileSync(path.join(scenesDir, `${sceneName}.json`), "utf8"));
const emotes = sceneName === "anim_emotes";
const CW = 560, CH = 340;
const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: CW, height: CH } });
await page.goto(`http://127.0.0.1:${port}/moves.html?w=${CW}&h=${CH}&clean=1&scene=${sceneName}`);
await page.waitForFunction(() => window.__ready || window.__error, null, { timeout: 240000 });
const err = await page.evaluate(() => window.__error);
if (err) {
  console.error(err);
  process.exit(1);
}
const rows = [];
for (const seg of data.segments) {
  const picks = seg.picks || PICKS[seg.move] || [];
  const cells = [];
  for (const [t, caption] of picks) {
    await page.evaluate((time) => window.renderFrame(time), seg.start + t);
    const shot = await page.screenshot({ type: "jpeg", quality: 88 });
    cells.push({ src: `data:image/jpeg;base64,${shot.toString("base64")}`, caption });
  }
  rows.push({ title: seg.title || TITLES[seg.move] || seg.move.toUpperCase(), subtitle: seg.subtitle, cells });
}
await page.close();

// two moves side by side per row: 6 frames
const W = 30 + 6 * (CW / 2 + 12) + 30 + 24;
const cellW = CW / 2, cellH = CH / 2;
const pairs = [];
for (let i = 0; i < rows.length; i += 2) pairs.push(rows.slice(i, i + 2));
const html = `<html><head><meta charset="utf-8"><style>
@font-face { font-family: "Luckiest Guy"; src: url("data:font/woff2;base64,${fs
  .readFileSync(path.join(here, "node_modules/@fontsource/luckiest-guy/files/luckiest-guy-latin-400-normal.woff2"))
  .toString("base64")}") format("woff2"); }
body { margin: 0; background: #2a1d16; font-family: "Arial Rounded MT Bold", Arial, sans-serif; color: #fff; }
h1 { font-family: "Luckiest Guy"; color: #ffd36b; font-size: 46px; margin: 26px 30px 2px; letter-spacing: 1px; }
h2 { margin: 0 30px 18px; font-size: 18px; font-weight: normal; opacity: 0.8; }
.row { display: flex; gap: 24px; padding: 0 30px 22px; }
.move { background: #3a2a20; border-radius: 16px; padding: 12px; }
.title { font-family: "Luckiest Guy"; color: #ffd36b; font-size: 24px; letter-spacing: 1px; }
.sub { font-size: 14px; opacity: 0.85; margin: 2px 0 8px; }
.cells { display: flex; gap: 8px; }
.cell img { width: ${cellW}px; height: ${cellH}px; border-radius: 10px; display: block; }
.cell div { font-size: 14px; margin-top: 4px; text-align: center; }
</style></head><body>
${
  data.sheetTitle
    ? `<h1>${data.sheetTitle}</h1><h2>${data.sheetSubtitle || ""}</h2>`
    : emotes
    ? `<h1>TERRA FORGE: EMOTY (NAVRH)</h1><h2>${data.segments.length} emotů k výběru · náhled z herního kódu (MoveMath na R15 postavičce) · video: emoty.mp4</h2>`
    : `<h1>TERRA FORGE: POHYBY HRACE</h1><h2>${data.segments.length} pohybů hráče · náhled z herního kódu (MoveMath na R15 postavičce) · video: pohyby_hrace.mp4</h2>`
}
${pairs
  .map(
    (pair) => `<div class="row">${pair
      .map(
        (m) => `<div class="move"><div class="title">${m.title}</div><div class="sub">${m.subtitle}</div><div class="cells">${m.cells
          .map((c) => `<div class="cell"><img src="${c.src}"/><div>${c.caption}</div></div>`)
          .join("")}</div></div>`,
      )
      .join("")}</div>`,
  )
  .join("")}
</body></html>`;
const sheet = await browser.newPage({ viewport: { width: Math.ceil(W), height: 400 } });
await sheet.setContent(html);
await sheet.waitForTimeout(200);
fs.mkdirSync(path.dirname(out), { recursive: true });
await sheet.screenshot({ path: out, type: "jpeg", quality: 86, fullPage: true });
await browser.close();
server.close();
console.log("sheet ->", path.relative(repo, out));
