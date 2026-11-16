// Renders a 2 s looping animation of one shop tab (frame(t) in shop_wow.html) as PNG frames.
// node render_anim.cjs <outdir> <page> [fps]   then make_anim.py turns the frames into an animated WebP
const path = require("path");
const fs = require("fs");
const HERE = __dirname;
const W = path.resolve(HERE, "../../..");                       // the repo root (main checkout or worktree)
// Paths from the repo root: this checkout's own file, else the main checkout's (a worktree three
// levels below it shares its node_modules and preview shots).
const MAIN = path.resolve(W, "../../..");
function find(rel) {
  for (const base of [W, MAIN]) {
    if (fs.existsSync(base + "/" + rel)) return base + "/" + rel;
  }
  return W + "/" + rel;
}
const { chromium } = require(find("tools/preview/node_modules/playwright"));
(async () => {
  const [out, page = "featured", fps = "20"] = process.argv.slice(2);
  const html = fs.readFileSync(HERE + "/shop_wow.html", "utf8")
    .replaceAll("FONTDIR", "file://" + W + "/tools/preview/fonts")
    .replaceAll("ICONS/", "file://" + W + "/build/preview/icons/")
    .replaceAll("TILES/", "file://" + W + "/tools/preview/tile_art/")
    .replaceAll('url("BG")', 'url("file://' + find("build/preview/shots/lobby_spawn.jpg") + '")')
    .replace('<script src="icons.js">', '<script src="file://' + HERE + '/icons.js">');
  const built = path.join(out, "shop_anim_built.html");
  fs.writeFileSync(built, html);
  const dir = path.join(out, "frames_" + page);
  fs.mkdirSync(dir, { recursive: true });
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  p.on("pageerror", (e) => console.log("pageerror:", e.message));
  await p.goto("file://" + built + "?page=" + page);
  await p.waitForTimeout(500);
  const n = 2 * +fps;
  for (let i = 0; i < n; i++) {
    await p.evaluate((t) => window.frame(t), i / +fps);
    await p.screenshot({ path: path.join(dir, String(i).padStart(3, "0") + ".png") });
  }
  await b.close();
  console.log("frames", n, dir);
})();
