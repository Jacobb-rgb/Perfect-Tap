// The shop's golem and egg stickers (owner 2026-11-12: "make it in the drawn version but more
// cool, and it has to look like it is in the game, so people don't say it's cap"): every name
// in IconAssets.ShopGolems.Icons (golem_<Kind>, capsule_<Id>) drawn FROM THE GAME'S OWN MODEL,
// the one the shop's 3D picture shows (PictureModels.build: the golem in its egg costume or
// limited gear, the egg, the shard) from that picture's camera direction, by the toon renderer
// tools/preview/golem_toon/toon.js (flat cel tones in each part's game colour, a bold navy
// outline, navy lines between parts, white shines, a drop; see its header). Writes the ONE
// picture the owner uploads (IconAssets.ShopGolems): Columns x rows of Cell px, transparent, in
// the order of IconAssets.ShopGolems.Icons (at most 1024 px a side), and every sticker alone as
// build/preview/icons/sticker_<name>.png for the previews.
//   node tools/preview/shop_golem_sheet.mjs [sheetOutDir]
//     first runs `lune run tools/lune/export_golem_stickers.luau` (the models ->
//     build/preview/golem_stickers.json); sheetOutDir defaults to ../NAHRAJ_DO_ROBLOXU/ikony_obchod
//     next to the project (obchod_golemove.png)
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

// the models, exactly as the game builds them
const exported = spawnSync("lune", ["run", "tools/lune/export_golem_stickers.luau"], { cwd: repo, encoding: "utf8" });
if (exported.status !== 0) {
  throw new Error("lune run tools/lune/export_golem_stickers.luau failed:\n" + (exported.stderr || exported.stdout || exported.error));
}
const data = JSON.parse(fs.readFileSync(path.join(repo, "build/preview/golem_stickers.json"), "utf8"));
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

const names = only.length ? order.filter((n) => only.includes(n)) : order;
const pictures = {};
for (const name of names) {
  const t0 = Date.now();
  const url = await page.evaluate(([name, cell, mode, debug]) => window.TOON.render(name, { cell, mode, debug }), [name, CELL, lit ? "lit" : "toon", debug]);
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
  // the sheet: every sticker in its cell, transparent round them
  const sheet = await page.evaluate(
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
    [order, pictures, CELL, COLUMNS, W, H],
  );
  fs.mkdirSync(sheetDir, { recursive: true });
  const sheetFile = path.join(sheetDir, "obchod_golemove.png");
  fs.writeFileSync(sheetFile, Buffer.from(sheet.split(",")[1], "base64"));
  console.log("sheet", path.relative(process.cwd(), sheetFile), `${W} x ${H}`, `${order.length} stickers`);
}
await browser.close();
server.close();
