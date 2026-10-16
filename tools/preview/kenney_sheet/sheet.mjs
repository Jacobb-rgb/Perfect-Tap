// Renders a contact sheet of Kenney Factory Kit models (GLB) for art reference.
//   KENNEY_KIT="/path/to/kenney_factory-kit_3.0/Models/GLB format" \
//   node tools/preview/kenney_sheet/sheet.mjs out.jpg machine,hopper-round,pipe-large-valve
// Needs `npm install` in tools/preview (three + playwright) and a Chromium for Playwright.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  ({ chromium } = require("/opt/node22/lib/node_modules/playwright"));
}
const here = path.dirname(fileURLToPath(import.meta.url));
const kit = process.env.KENNEY_KIT;
if (!kit || !fs.existsSync(kit)) {
  console.error('Set KENNEY_KIT to the kit\'s "Models/GLB format" folder.');
  process.exit(1);
}
const three = path.resolve(here, "../node_modules/three");
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url.startsWith("/kit/") ? path.join(kit, url.slice(5)) : url.startsWith("/three/") ? path.join(three, url.slice(7)) : path.join(here, url.slice(1));
  fs.readFile(file, (e, d) => {
    if (e) {
      res.writeHead(404).end();
      return;
    }
    const ext = path.extname(file);
    res.writeHead(200, { "Content-Type": ext === ".js" ? "text/javascript" : ext === ".html" ? "text/html" : "application/octet-stream" });
    res.end(d);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const [outName, list] = process.argv.slice(2);
const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("console", (m) => {
  if (m.type() === "error") console.error("[page]", m.text());
});
await page.goto(`http://127.0.0.1:${server.address().port}/sheet.html?names=${list}`);
await page.waitForFunction(() => window.__done, null, { timeout: 240000 });
const data = await page.evaluate(() => window.__png);
fs.writeFileSync(outName, Buffer.from(data.split(",")[1], "base64"));
await browser.close();
server.close();
console.log("wrote", outName);
