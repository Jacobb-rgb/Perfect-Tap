const path = require("path"), fs = require("fs");
const M = "/Users/kuban/Desktop/Terra Forge Roblox game KIT/projekt";
const W = M + "/.claude/worktrees/shop-v3";
const { chromium } = require(M + "/tools/preview/node_modules/playwright");
const here = __dirname;
const enc = (p) => "file://" + p.split("/").map(encodeURIComponent).join("/");
let html = fs.readFileSync(path.join(here, "shop.html"), "utf8")
  .replaceAll("FONTDIR", enc(W + "/tools/preview/fonts"))
  .replaceAll("ICONS", enc(W + "/build/preview/icons"))
  .replaceAll("TILES", enc(W + "/tools/preview/tile_art"))
  .replaceAll("BG", enc(M + "/build/preview/shots/lobby_spawn.jpg"));
fs.writeFileSync(path.join(here, "shop_built.html"), html);
(async () => {
  const browser = await chromium.launch({ args: ["--allow-file-access-from-files"] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const pages = process.argv.slice(2).length ? process.argv.slice(2) : ["featured", "golems", "blasters", "passes", "boosts", "cash"];
  for (const p of pages) {
    await page.goto(enc(path.join(here, "shop_built.html")) + "?page=" + p);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(here, "shop_" + p + ".jpg"), type: "jpeg", quality: 90 });
    console.log("rendered", p);
  }
  await browser.close();
})();
