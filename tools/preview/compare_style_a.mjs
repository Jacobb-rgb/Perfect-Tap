// Comparison sheets for the plot style A proposal (preview only): today on the
// left, style A on the right, a small caption on each.
// Input:  build/preview/shots/psa_<angle>_today.jpg and psa_<angle>_a.jpg
//         (SHOTS_EXTRA=tools/preview/plot_style_a_shots.json node tools/preview/render.mjs yard_today|yard_style_a ...)
// Output: docs/screenshots/plot_style_a/compare_<angle>.jpg
// Run:    node tools/preview/compare_style_a.mjs [angle ...]   (default: overview pen podiums train)
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = process.cwd();
const require = createRequire(path.join(root, "tools/preview/package.json"));
const { chromium } = require("playwright");

const requested = process.argv.slice(2);
const angles = requested.length ? requested : ["overview", "pen", "podiums", "train"];
const shots = path.join(root, "build/preview/shots");
const outDir = path.join(root, "docs/screenshots/plot_style_a");
fs.mkdirSync(outDir, { recursive: true });

const W = 1920;
const PAD = 12;
const GAP = 12;
const IMG_W = (W - 2 * PAD - GAP) / 2;
const IMG_H = Math.round((IMG_W * 9) / 16);
const H = IMG_H + 2 * PAD;

const dataUri = (file) => `data:image/jpeg;base64,${fs.readFileSync(file).toString("base64")}`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
for (const angle of angles) {
  const today = path.join(shots, `psa_${angle}_today.jpg`);
  const styleA = path.join(shots, `psa_${angle}_a.jpg`);
  if (!fs.existsSync(today) || !fs.existsSync(styleA)) {
    console.error(`missing renders for ${angle}`);
    continue;
  }
  const panel = (src, caption, color) => `
    <div class="panel">
      <img src="${dataUri(src)}">
      <div class="cap" style="background:${color}">${caption}</div>
    </div>`;
  await page.setContent(`<html><head><style>
    body { margin: 0; background: #1b1a26; }
    .sheet { display: flex; gap: ${GAP}px; padding: ${PAD}px; }
    .panel { position: relative; width: ${IMG_W}px; height: ${IMG_H}px; border-radius: 10px; overflow: hidden; }
    .panel img { width: 100%; height: 100%; display: block; }
    .cap { position: absolute; left: 14px; top: 12px; padding: 5px 14px 4px; border-radius: 8px;
           font: 800 22px/1.1 "Arial Black", Arial, sans-serif; letter-spacing: 1px; color: #fff;
           box-shadow: 0 2px 6px rgba(0,0,0,0.35); }
  </style></head><body><div class="sheet">
    ${panel(today, "TODAY", "rgba(40,42,58,0.88)")}
    ${panel(styleA, "STYLE A", "rgba(240,128,30,0.95)")}
  </div></body></html>`);
  const out = path.join(outDir, `compare_${angle}.jpg`);
  await page.screenshot({ path: out, type: "jpeg", quality: 90 });
  console.log("sheet ->", path.relative(root, out));
}
await browser.close();
