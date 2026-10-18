// A 2x2 (or 1xN) picture sheet with captions: node tools/preview/sheet.mjs out.jpg img1 "caption 1" img2 "caption 2" ...
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = process.cwd();
const require = createRequire(path.join(root, "tools/preview/package.json"));
const { chromium } = require("playwright");

const [out, ...rest] = process.argv.slice(2);
const cells = [];
for (let i = 0; i + 1 < rest.length; i += 2) {
  const data = fs.readFileSync(path.resolve(root, rest[i])).toString("base64");
  cells.push({ src: `data:image/jpeg;base64,${data}`, caption: rest[i + 1] });
}
const cols = cells.length === 4 ? 2 : cells.length;
const W = 1920, cellW = (W - 30 * (cols + 1)) / cols, cellH = cellW * 9 / 16;
const rows = Math.ceil(cells.length / cols);
const H = rows * (cellH + 120) + 30;
const html = `<html><body style="margin:0;background:#16141f;font-family:Arial,sans-serif">
<div style="display:grid;grid-template-columns:repeat(${cols},${cellW}px);gap:30px;padding:30px">
${cells.map((c) => `<div><img src="${c.src}" style="width:${cellW}px;height:${cellH}px;border-radius:14px;display:block"/>
<div style="color:#fff;font-size:28px;font-weight:bold;margin-top:12px">${c.caption}</div></div>`).join("")}
</div></body></html>`;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: Math.ceil(H) } });
await page.setContent(html);
await page.screenshot({ path: out, type: "jpeg", quality: 90 });
await browser.close();
console.log("sheet ->", out);
