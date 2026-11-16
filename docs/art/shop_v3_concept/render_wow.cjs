// Renders shop_wow.html (the 2026-11-11 "wow" concept) to JPGs, one per tab.
// node render_wow.cjs <outdir> [pages...]   (run from anywhere; paths are absolute)
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
  const [out = HERE, ...pages] = process.argv.slice(2);
  const list = pages.length ? pages : ["featured", "golems", "blasters", "passes", "boosts", "cash"];
  let html = fs.readFileSync(HERE + "/shop_wow.html", "utf8")
    .replaceAll("FONTDIR", "file://" + W + "/tools/preview/fonts")
    .replaceAll("ICONS/", "file://" + W + "/build/preview/icons/")
    .replaceAll("TILES/", "file://" + W + "/tools/preview/tile_art/")
    .replaceAll('url("BG")', 'url("file://' + find("build/preview/shots/lobby_spawn.jpg") + '")')
    .replace('<script src="icons.js">', '<script src="file://' + HERE + '/icons.js">');
  const built = path.join(out, "shop_wow_built.html");
  fs.writeFileSync(built, html);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  p.on("pageerror", (e) => console.log("pageerror:", e.message));
  p.on("console", (m) => { if (m.type() === "error") console.log("console:", m.text()); });
  for (const pg of list) {
    await p.goto("file://" + built + "?page=" + pg);
    await p.waitForTimeout(400);
    await p.screenshot({ path: path.join(out, "wow_" + pg + ".jpg"), type: "jpeg", quality: 92 });
    console.log("ok", pg);
  }
  await b.close();
})();
