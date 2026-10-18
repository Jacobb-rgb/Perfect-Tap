// Packs the rendered 3D icons (build/preview/icons/*.png) into the sprite
// sheets listed in build/preview/icon_sheets.json (from
// tools/lune/export_icon_sheets.luau): 6 x 6 cells, transparent background.
//   node tools/preview/icon_sheets.mjs [outDir]   (default build/preview/icon_sheets)
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const iconsDir = path.join(repo, "build/preview/icons");
const layout = JSON.parse(fs.readFileSync(path.join(repo, "build/preview/icon_sheets.json"), "utf8"));
const outDir = path.resolve(process.argv[2] || path.join(repo, "build/preview/icon_sheets"));
fs.mkdirSync(outDir, { recursive: true });

const server = http.createServer((req, res) => {
  const name = decodeURIComponent(req.url.split("?")[0]).replace(/^\//, "");
  if (name === "") return res.writeHead(200, { "Content-Type": "text/html" }).end("<!doctype html><html><body></body></html>");
  const file = path.join(iconsDir, name);
  if (!file.startsWith(iconsDir)) return res.writeHead(403).end();
  fs.readFile(file, (err, data) => {
    if (err) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": "image/png" }).end(data);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${port}/`);

let missing = 0;
for (const sheet of layout.Sheets) {
  for (const name of sheet.Icons) {
    if (!fs.existsSync(path.join(iconsDir, `${name}.png`))) {
      console.error(`missing icon ${name} (render it with render_icons.mjs)`);
      missing++;
    }
  }
  const url = await page.evaluate(
    async ({ icons, cell, columns }) => {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = cell * columns;
      const ctx = canvas.getContext("2d");
      ctx.imageSmoothingQuality = "high";
      for (let i = 0; i < icons.length; i++) {
        const img = new Image();
        img.src = `/${icons[i]}.png`;
        try {
          await img.decode();
        } catch {
          continue;
        }
        ctx.drawImage(img, (i % columns) * cell, Math.floor(i / columns) * cell, cell, cell);
      }
      return canvas.toDataURL("image/png");
    },
    { icons: sheet.Icons, cell: layout.Cell, columns: layout.Columns },
  );
  const file = path.join(outDir, sheet.File);
  fs.writeFileSync(file, Buffer.from(url.split(",")[1], "base64"));
  console.log(`sheet ${sheet.Name}: ${sheet.Icons.length} icons -> ${file}`);
}

await browser.close();
server.close();
process.exit(missing > 0 ? 1 : 0);
