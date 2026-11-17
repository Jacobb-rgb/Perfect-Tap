// Rasterises the shop v3 sticker icons (docs/art/shop_v3_concept/icons.js, owner 2026-11-11)
// into the ONE picture the owner uploads (IconAssets.Shop): 6 x 6 cells of 170 px, 1020 px
// square (under Roblox's 1024), transparent, in the order of IconAssets.Shop.Icons. Also
// writes every icon alone (256 px) as build/preview/icons/shop_<name>.png for the previews.
//   node tools/preview/shop_icon_sheet.mjs [sheetOutDir]
//   (default ../NAHRAJ_DO_ROBLOXU/ikony_obchod next to the project)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  ({ chromium } = require("/opt/node22/lib/node_modules/playwright"));
}

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
// the project folder's parent holds NAHRAJ_DO_ROBLOXU (a worktree sits 3 deeper: .claude/worktrees/<name>)
function kitRoot() {
  let dir = repo;
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(dir, "NAHRAJ_DO_ROBLOXU"))) return dir;
    dir = path.dirname(dir);
  }
  return path.dirname(repo);
}
const sheetDir = path.resolve(process.argv[2] || path.join(kitRoot(), "NAHRAJ_DO_ROBLOXU/ikony_obchod"));
const previewDir = path.join(repo, "build/preview/icons");
fs.mkdirSync(sheetDir, { recursive: true });
fs.mkdirSync(previewDir, { recursive: true });

// the sheet's order: IconAssets.Shop.Icons (the game cuts its cells by this order)
const luau = fs.readFileSync(path.join(repo, "src/shared/Config/IconAssets.luau"), "utf8");
const block = luau.match(/IconAssets\.Shop = \{[\s\S]*?Icons = \{([\s\S]*?)\}/);
if (!block) throw new Error("IconAssets.Shop.Icons not found");
const order = [...block[1].matchAll(/"([a-z0-9_]+)"/g)].map((m) => m[1]);
const cellMatch = luau.match(/IconAssets\.Shop = \{[\s\S]*?Cell = (\d+)/);
const columnsMatch = luau.match(/IconAssets\.Shop = \{[\s\S]*?Columns = (\d+)/);
const CELL = Number(cellMatch ? cellMatch[1] : 170);
const COLUMNS = Number(columnsMatch ? columnsMatch[1] : 6);
const ROWS = Math.ceil(order.length / COLUMNS);
const SIZE = Math.max(COLUMNS, ROWS) * CELL;
if (SIZE > 1024) throw new Error(`the sheet would be ${SIZE} px: Roblox shrinks pictures over 1024`);

const iconsJs = path.join(repo, "docs/art/shop_v3_concept/icons.js");
const font = path.join(repo, "tools/preview/fonts/FredokaOne-Regular.ttf");
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face { font-family: "Fredoka"; src: url("file://${font}"); }
html, body { margin: 0; padding: 0; background: transparent; }
#sheet { position: relative; width: ${SIZE}px; height: ${SIZE}px; }
.cell { position: absolute; width: ${CELL}px; height: ${CELL}px; display: flex; align-items: center; justify-content: center; }
#one { position: absolute; left: 0; top: ${SIZE + 20}px; width: 256px; height: 256px; display: flex; align-items: center; justify-content: center; }
</style></head><body><div id="sheet"></div><div id="one"></div>
<script src="file://${iconsJs}"></script></body></html>`;
const pagePath = path.join(repo, "build/preview/shop_icon_sheet.html");
fs.writeFileSync(pagePath, html);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE + 300 } });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
await page.goto("file://" + pagePath);
await page.evaluate(() => document.fonts.load('40px "Fredoka"'));
const missing = await page.evaluate(
  ({ order, CELL, COLUMNS }) => {
    const ICONS = window.ICONS;
    document.head.insertAdjacentHTML("beforeend", "<style>" + ICONS.css + "</style>");
    document.body.insertAdjacentHTML("afterbegin", ICONS.defs());
    const sheet = document.getElementById("sheet");
    const out = [];
    order.forEach((name, i) => {
      if (!ICONS.names.includes(name)) out.push(name);
      const cell = document.createElement("div");
      cell.className = "cell";
      cell.style.left = `${(i % COLUMNS) * CELL}px`;
      cell.style.top = `${Math.floor(i / COLUMNS) * CELL}px`;
      // (the icon's box is 116 x 120 units: 0.9 of the cell keeps its outline and drop inside)
      cell.innerHTML = ICONS.icon(name, Math.floor(CELL * 0.86));
      sheet.appendChild(cell);
    });
    return out;
  },
  { order, CELL, COLUMNS },
);
if (missing.length) throw new Error("icons.js has no " + missing.join(", "));
await page.waitForTimeout(200);
const sheetFile = path.join(sheetDir, "obchod_ikony.png");
await page.locator("#sheet").screenshot({ path: sheetFile, omitBackground: true });
console.log("sheet", path.relative(process.cwd(), sheetFile), `${SIZE} x ${SIZE}`, `${order.length} icons`);

for (const name of order) {
  await page.evaluate((name) => {
    document.getElementById("one").innerHTML = window.ICONS.icon(name, 220);
  }, name);
  await page.locator("#one").screenshot({ path: path.join(previewDir, `shop_${name}.png`), omitBackground: true });
}
console.log("previews", order.length, "->", path.relative(process.cwd(), previewDir));
await browser.close();
fs.rmSync(pagePath, { force: true });
