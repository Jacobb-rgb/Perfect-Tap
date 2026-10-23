// Renders the 3D UI icons (tools/preview/icons/icons.js) to transparent PNGs.
//   node tools/preview/render_icons.mjs            -> every icon
//   node tools/preview/render_icons.mjs coin golem -> only these
//   ICON_STYLE=bubble node tools/preview/render_icons.mjs -> the older glossy style (default: pixel)
// Output: build/preview/icons/<name>.png (512 px). Part icons (blaster, ores)
// first need: lune run tools/lune/export_icon_parts.luau
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
const outDir = path.join(repo, "build/preview/icons");
fs.mkdirSync(outDir, { recursive: true });

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".png": "image/png" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url.startsWith("/scenes/") ? path.join(scenesDir, url.slice(8)) : path.join(here, url);
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
const page = await browser.newPage({ viewport: { width: 1100, height: 1100 } });
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));

const base = `http://127.0.0.1:${port}/icons/icons.html`;
const style = process.env.ICON_STYLE ? `&style=${encodeURIComponent(process.env.ICON_STYLE)}` : "";
await page.goto(`${base}?icon=coin`);
await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 120000 });
const all = await page.evaluate(() => window.ICON_NAMES);
const names = process.argv.slice(2).length ? process.argv.slice(2) : all;

for (const name of names) {
  await page.goto(`${base}?icon=${name}&size=512${style}`);
  await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 120000 });
  const err = await page.evaluate(() => window.__error);
  if (err) {
    console.error(`icon ${name} failed:`, err);
    continue;
  }
  const url = await page.evaluate(() => window.__png);
  fs.writeFileSync(path.join(outDir, `${name}.png`), Buffer.from(url.split(",")[1], "base64"));
  console.log(`icon ${name} -> build/preview/icons/${name}.png`);
}

await browser.close();
server.close();
