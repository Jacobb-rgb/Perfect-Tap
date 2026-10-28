// A "theirs | ours" comparison sheet: rows of two pictures side by side, each fitted whole
// into its cell (no stretching: a cropped reference keeps its own shape), a caption under each.
//   node tools/preview/pair_sheet.mjs out.jpg "Title" left1 "caption" right1 "caption" [left2 ... right2 ...]
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = process.cwd();
const require = createRequire(path.join(root, "tools/preview/package.json"));
const { chromium } = require("playwright");

const [out, title, ...rest] = process.argv.slice(2);
const cells = [];
for (let i = 0; i + 1 < rest.length; i += 2) {
  const file = path.resolve(root, rest[i]);
  const mime = file.endsWith(".png") ? "image/png" : "image/jpeg";
  cells.push({ src: `data:${mime};base64,${fs.readFileSync(file).toString("base64")}`, caption: rest[i + 1] });
}
const W = 1920;
const cellW = (W - 30 * 3) / 2;
const cellH = Math.round((cellW * 9) / 16);
const rows = Math.ceil(cells.length / 2);
const H = 90 + rows * (cellH + 70) + 20;
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
const html = `<html><body style="margin:0;background:#16141f;font-family:Arial,sans-serif">
<div style="color:#fff;font-size:34px;font-weight:bold;padding:26px 30px 0">${esc(title)}</div>
<div style="display:grid;grid-template-columns:repeat(2,${cellW}px);gap:20px 30px;padding:20px 30px">
${cells
  .map(
    (c, i) => `<div><div style="width:${cellW}px;height:${cellH}px;border-radius:14px;background:#0c0b12;display:flex;align-items:center;justify-content:center;overflow:hidden">
<img src="${c.src}" style="max-width:100%;max-height:100%;object-fit:contain;display:block"/></div>
<div style="color:${i % 2 === 0 ? "#ffcf66" : "#8cff8c"};font-size:24px;font-weight:bold;margin-top:10px">${esc(c.caption)}</div></div>`,
  )
  .join("")}
</div></body></html>`;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: Math.ceil(H) } });
await page.setContent(html);
await page.screenshot({ path: out, type: "jpeg", quality: 90 });
await browser.close();
console.log("sheet ->", out);
