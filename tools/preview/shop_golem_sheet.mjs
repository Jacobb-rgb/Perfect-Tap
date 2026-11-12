// Rasterises the shop's golem and egg stickers (docs/art/shop_v3_concept/golems.js, owner
// 2026-11-11: his pick B, the game's own skins drawn like the shop's icons) into the ONE picture
// the owner uploads (IconAssets.ShopGolems): Columns x rows of Cell px, transparent, in the order
// of IconAssets.ShopGolems.Icons (at most 1024 px a side). Also writes every sticker alone (256
// px) as build/preview/icons/sticker_<name>.png for the previews.
//   node tools/preview/shop_golem_sheet.mjs [sheetOutDir]
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

// the sheet's order and cells: IconAssets.ShopGolems (the game cuts its cells by them)
const luau = fs.readFileSync(path.join(repo, "src/shared/Config/IconAssets.luau"), "utf8");
const block = luau.match(/IconAssets\.ShopGolems = \{([\s\S]*?)\n\}/);
if (!block) throw new Error("IconAssets.ShopGolems not found");
const icons = block[1].match(/Icons = \{([\s\S]*?)\}/);
const order = [...icons[1].matchAll(/"([A-Za-z0-9_]+)"/g)].map((m) => m[1]);
const CELL = Number((block[1].match(/Cell = (\d+)/) || [0, 256])[1]);
const COLUMNS = Number((block[1].match(/Columns = (\d+)/) || [0, 4])[1]);
const ROWS = Math.ceil(order.length / COLUMNS);
const W = COLUMNS * CELL, H = ROWS * CELL;
if (W > 1024 || H > 1024) throw new Error(`the sheet would be ${W} x ${H} px: Roblox shrinks pictures over 1024`);

const golemsJs = path.join(repo, "docs/art/shop_v3_concept/golems.js");
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html, body { margin: 0; padding: 0; background: transparent; }
#sheet { position: relative; width: ${W}px; height: ${H}px; }
.cell { position: absolute; width: ${CELL}px; height: ${CELL}px; display: flex; align-items: center; justify-content: center; }
#one { position: absolute; left: 0; top: ${H + 20}px; width: 256px; height: 256px; display: flex; align-items: center; justify-content: center; }
</style></head><body><div id="sheet"></div><div id="one"></div>
<script src="file://${golemsJs}"></script></body></html>`;
const pagePath = path.join(repo, "build/preview/shop_golem_sheet.html");
fs.writeFileSync(pagePath, html);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: Math.max(W, 256), height: H + 300 } });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
await page.goto("file://" + pagePath);
const missing = await page.evaluate(
  ({ order, CELL, COLUMNS }) => {
    const G = window.GOLEMS;
    document.head.insertAdjacentHTML("beforeend", "<style>" + G.css + "</style>");
    document.body.insertAdjacentHTML("afterbegin", G.defs());
    const sheet = document.getElementById("sheet");
    const out = [];
    order.forEach((name, i) => {
      if (!G.names.includes(name)) out.push(name);
      const cell = document.createElement("div");
      cell.className = "cell";
      cell.style.left = `${(i % COLUMNS) * CELL}px`;
      cell.style.top = `${Math.floor(i / COLUMNS) * CELL}px`;
      // (a sticker's square box holds its wings, outline and drop: it fills the cell)
      cell.innerHTML = G.icon(name, CELL);
      sheet.appendChild(cell);
    });
    return out;
  },
  { order, CELL, COLUMNS },
);
if (missing.length) throw new Error("golems.js has no " + missing.join(", "));
await page.waitForTimeout(200);
const sheetFile = path.join(sheetDir, "obchod_golemove.png");
await page.locator("#sheet").screenshot({ path: sheetFile, omitBackground: true });
console.log("sheet", path.relative(process.cwd(), sheetFile), `${W} x ${H}`, `${order.length} stickers`);

for (const name of order) {
  await page.evaluate((name) => {
    document.getElementById("one").innerHTML = window.GOLEMS.icon(name, 256);
  }, name);
  await page.locator("#one").screenshot({ path: path.join(previewDir, `sticker_${name}.png`), omitBackground: true });
}
console.log("previews", order.length, "->", path.relative(process.cwd(), previewDir));
await browser.close();
fs.rmSync(pagePath, { force: true });
