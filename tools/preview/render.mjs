// Renders preview screenshots of exported scenes with headless Chromium.
//   node tools/preview/render.mjs world town_overview great_forge ...
//   (no shot names = every shot in shots.json that uses that scene)
import http from "node:http";
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
const scenesDir = path.join(repo, "build/preview");
const outDir = path.join(repo, "build/preview/shots");
fs.mkdirSync(outDir, { recursive: true });

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png", ".ttf": "font/ttf" };

// Extra shots from a private file (SHOTS_EXTRA=path), merged over shots.json, so parallel
// workers can add camera angles without editing the shared file.
function allShots() {
  const base = JSON.parse(fs.readFileSync(path.join(here, "shots.json"), "utf8"));
  const extra = process.env.SHOTS_EXTRA;
  if (extra && fs.existsSync(extra)) Object.assign(base, JSON.parse(fs.readFileSync(extra, "utf8")));
  return base;
}

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  if (url === "/shots.json") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(allShots()));
    return;
  }
  let file;
  if (url.startsWith("/scenes/")) file = path.join(scenesDir, url.slice("/scenes/".length));
  else file = path.join(here, url === "/" ? "index.html" : url);
  if (!file.startsWith(here) && !file.startsWith(scenesDir)) {
    res.writeHead(403).end();
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(data);
  });
});

await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const [sceneName = "world", ...requested] = process.argv.slice(2);
const shots = allShots();
const names = requested.length ? requested : Object.keys(shots).filter((n) => (shots[n].scene || "world") === sceneName);

const browser = await chromium.launch({
  executablePath: fs.existsSync("/opt/pw-browsers/chromium") ? undefined : undefined,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
// RENDER_W / RENDER_H (default 1600 x 900): e.g. 1920 x 1080 for the store thumbnails
const renderW = Number(process.env.RENDER_W || 1600);
const renderH = Number(process.env.RENDER_H || 900);
const page = await browser.newPage({ viewport: { width: renderW, height: renderH } });
page.on("console", (m) => {
  if (m.type() === "error") console.error("[page]", m.text());
});

for (const name of names) {
  const t0 = Date.now();
  // per-shot width / height (phone renders) win over RENDER_W / RENDER_H
  const w = shots[name].width || renderW;
  const h = shots[name].height || renderH;
  await page.setViewportSize({ width: w, height: h });
  await page.goto(`http://127.0.0.1:${port}/index.html?scene=${sceneName}&shot=${name}&w=${w}&h=${h}`);
  await page.waitForFunction(() => window.__done || window.__error, null, { timeout: 240000 });
  const err = await page.evaluate(() => window.__error);
  if (err) {
    console.error(`shot ${name} failed:`, err);
    continue;
  }
  const file = path.join(outDir, `${name}.jpg`);
  await page.screenshot({ path: file, type: "jpeg", quality: 88, timeout: 180000 });
  console.log(`rendered ${name} in ${((Date.now() - t0) / 1000).toFixed(1)}s -> ${path.relative(repo, file)}`);
}

await browser.close();
server.close();
