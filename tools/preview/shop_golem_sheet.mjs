// The shop's drawn stickers (owner 2026-11-12: "make it in the drawn version but more cool, and
// it has to look like it is in the game, so people don't say it's cap"; then "the hoverboard
// etc. doesn't have the drawn style yet"): every name in every image of IconAssets.StickerSheets
// (IconAssets.ShopGolems: golem_<Kind>, capsule_<Id> -> obchod_golemove.png; IconAssets.ShopItems:
// podium, train, board_<Id> -> obchod_predmety.png) drawn FROM THE GAME'S OWN MODEL, the one the
// shop's 3D picture shows (PictureModels.build: the golem in its egg costume or limited gear, the
// egg, the shard, the podium, the locomotive, the hoverboard) from that picture's camera
// direction, by the toon renderer tools/preview/golem_toon/toon.js (flat cel tones in each part's
// game colour, a bold navy outline, navy lines between parts, white shines, a drop; see its
// header). Writes the pictures the owner uploads, one per image: Columns x rows of Cell px,
// transparent, in the order of its Icons (at most 1024 px a side), and every sticker alone as
// build/preview/icons/sticker_<name>.png for the previews. An image already uploaded (its Id > 0)
// is not written again (the file stays the one the game shows) unless SHEETS names it.
//   node tools/preview/shop_golem_sheet.mjs [sheetOutDir]
//     first runs `lune run tools/lune/export_golem_stickers.luau` (the models and the images ->
//     build/preview/golem_stickers.json); sheetOutDir defaults to ../NAHRAJ_DO_ROBLOXU/ikony_obchod
//     next to the project
//   SHEETS=ShopGolems node tools/preview/shop_golem_sheet.mjs <dir>
//     writes these images (IconAssets names) whether uploaded or not (a check against the upload)
//   STICKERS=golem_RoseKnight,capsule_Royal node tools/preview/shop_golem_sheet.mjs
//     only these previews (no sheet); TOON_DEBUG=1 also writes build/preview/golem_debug/
//     <name>_4x.png (before the filter down) and <name>_lines.png (parts in false colour, the lines)
//   node tools/preview/shop_golem_sheet.mjs --lit [outDir]
//     the shop's own lit 3D pictures of the same models instead (StoreView's camera, Pop.model's
//     light), for side-by-side checks: <outDir>/<name>.png (default build/preview/golem_3d); no sheet
// The shop previews then show them (UI_QUICK=1: the shop over an empty sky, no map):
//   UI_QUICK=1 lune run tools/lune/export_scene.luau store
//   SHOTS_EXTRA=tools/preview/store_shots.json node tools/preview/render.mjs store store_pc_golems store_pc
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
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
const args = process.argv.slice(2);
const lit = args[0] === "--lit";
const outArg = lit ? args[1] : args[0];
const only = (process.env.STICKERS || "").split(",").filter(Boolean);
const debug = process.env.TOON_DEBUG === "1";
const sheetDir = path.resolve(outArg || path.join(kitRoot(), "NAHRAJ_DO_ROBLOXU/ikony_obchod"));
const previewDir = lit ? path.resolve(outArg || path.join(repo, "build/preview/golem_3d")) : path.join(repo, "build/preview/icons");
fs.mkdirSync(previewDir, { recursive: true });

const wantSheets = (process.env.SHEETS || "").split(",").filter(Boolean);

// the models, exactly as the game builds them, and the images' order and cells
// (IconAssets.StickerSheets: the game cuts its cells by them)
const exported = spawnSync("lune", ["run", "tools/lune/export_golem_stickers.luau"], { cwd: repo, encoding: "utf8" });
if (exported.status !== 0) {
  throw new Error("lune run tools/lune/export_golem_stickers.luau failed:\n" + (exported.stderr || exported.stdout || exported.error));
}
const data = JSON.parse(fs.readFileSync(path.join(repo, "build/preview/golem_stickers.json"), "utf8"));
for (const sheet of data.sheets) {
  sheet.W = sheet.columns * sheet.cell;
  sheet.H = Math.ceil(sheet.order.length / sheet.columns) * sheet.cell;
  if (sheet.W > 1024 || sheet.H > 1024) throw new Error(`${sheet.file} would be ${sheet.W} x ${sheet.H} px: Roblox shrinks pictures over 1024`);
}
const unknown = wantSheets.filter((n) => !data.sheets.some((s) => s.name === n));
if (unknown.length) throw new Error("SHEETS: no image " + unknown.join(", ") + " (IconAssets.StickerSheets: " + data.sheets.map((s) => s.name).join(", ") + ")");
const order = data.sheets.flatMap((s) => s.order);
const missing = order.filter((name) => !data.models[name]);
if (missing.length) throw new Error("no model for " + missing.join(", "));

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json" };
const roots = { "/scenes/": path.join(repo, "build/preview"), "/node_modules/": path.join(here, "node_modules"), "/golem_toon/": path.join(here, "golem_toon") };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const prefix = Object.keys(roots).find((p) => url.startsWith(p));
  if (!prefix) return res.writeHead(404).end();
  const file = path.join(roots[prefix], url.slice(prefix.length));
  if (!file.startsWith(roots[prefix])) return res.writeHead(403).end();
  fs.readFile(file, (err, body) => {
    if (err) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(body);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: 600, height: 600 } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));
page.on("pageerror", (e) => console.error("[page]", e.message));
await page.goto(`http://127.0.0.1:${port}/golem_toon/toon.html`);
await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });

const cellOf = Object.fromEntries(data.sheets.flatMap((s) => s.order.map((n) => [n, s.cell])));
const names = only.length ? order.filter((n) => only.includes(n)) : order;
const pictures = {};
for (const name of names) {
  const t0 = Date.now();
  const url = await page.evaluate(([name, cell, mode, debug]) => window.TOON.render(name, { cell, mode, debug }), [name, cellOf[name], lit ? "lit" : "toon", debug]);
  pictures[name] = url;
  if (debug && !lit) {
    // TOON_DEBUG=1: the 4x picture before it is filtered down
    const big = await page.evaluate(() => window.TOON.big);
    fs.mkdirSync(path.join(repo, "build/preview/golem_debug"), { recursive: true });
    fs.writeFileSync(path.join(repo, "build/preview/golem_debug", `${name}_4x.png`), Buffer.from(big.split(",")[1], "base64"));
    const lines = await page.evaluate(() => window.TOON.lines);
    if (lines) fs.writeFileSync(path.join(repo, "build/preview/golem_debug", `${name}_lines.png`), Buffer.from(lines.split(",")[1], "base64"));
  }
  const file = path.join(previewDir, lit ? `${name}.png` : `sticker_${name}.png`);
  fs.writeFileSync(file, Buffer.from(url.split(",")[1], "base64"));
  console.log(`${lit ? "3D" : "sticker"} ${name} (${Date.now() - t0} ms) -> ${path.relative(process.cwd(), file)}`);
}

if (!lit && !only.length) {
  for (const sheet of data.sheets) {
    const write = wantSheets.length ? wantSheets.includes(sheet.name) : sheet.id === 0;
    if (!write) {
      console.log(`sheet ${sheet.file}: uploaded (id ${sheet.id}), kept as it is (SHEETS=${sheet.name} writes it again)`);
      continue;
    }
    // the image: every sticker in its cell, transparent round them
    const png = await page.evaluate(
      async ([order, pictures, CELL, COLUMNS, W, H]) => {
        const canvas = document.createElement("canvas");
        canvas.width = W;
        canvas.height = H;
        const ctx = canvas.getContext("2d");
        for (let i = 0; i < order.length; i++) {
          const img = new Image();
          img.src = pictures[order[i]];
          await img.decode();
          ctx.drawImage(img, (i % COLUMNS) * CELL, Math.floor(i / COLUMNS) * CELL);
        }
        return canvas.toDataURL("image/png");
      },
      [sheet.order, pictures, sheet.cell, sheet.columns, sheet.W, sheet.H],
    );
    fs.mkdirSync(sheetDir, { recursive: true });
    const sheetFile = path.join(sheetDir, sheet.file);
    fs.writeFileSync(sheetFile, Buffer.from(png.split(",")[1], "base64"));
    console.log("sheet", path.relative(process.cwd(), sheetFile), `${sheet.W} x ${sheet.H}`, `${sheet.order.length} stickers`);
  }
}
await browser.close();
server.close();
