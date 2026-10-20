// The LIMITED EDITION pictures for the owner (Config/LimitedGolems):
//   docs/screenshots/limited_golems/navrh_<set>.jpg    the banner concept, 1600 x 900
//   docs/screenshots/limited_golems/ikony_<set>.jpg    the set's 6 golem icons (golem_<Id>) and its capsule (capsule_<Id>)
// Run tools/preview/limited_golems.sh (it renders everything first, then calls this).
// (navrhy.jpg and the other navrh_*.jpg are the four proposals the owner chose from, 2026-10-20.)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const preview = path.join(repo, "build/preview");
const out = path.join(repo, "docs/screenshots/limited_golems");
fs.mkdirSync(out, { recursive: true });

// the sets, their banner shot and picture name
const SETS = [{ id: "Dragonforge", shot: "limited_dragonforge", file: "dragonforge" }];

const b64 = (file) => fs.readFileSync(file).toString("base64");
const font = (name, file) =>
  `@font-face { font-family: "${name}"; src: url(data:font/woff2;base64,${b64(path.join(here, "node_modules/@fontsource", file))}) format("woff2"); }`;
const FONTS = [
  font("Luckiest Guy", "luckiest-guy/files/luckiest-guy-latin-400-normal.woff2"),
  font("Luckiest Guy", "luckiest-guy/files/luckiest-guy-latin-ext-400-normal.woff2"),
  font("Fredoka One", "fredoka-one/files/fredoka-one-latin-400-normal.woff2"),
].join("\n");
const STYLE = `<style>${FONTS}
  body { margin: 0; background: #1a1018; color: #fff; font-family: Arial, Helvetica, sans-serif; }
  .big { font-family: "Luckiest Guy", "Arial Black", sans-serif; letter-spacing: 1px; -webkit-text-stroke: 2px #0e0e12; paint-order: stroke fill; }
</style>`;

const browser = await chromium.launch();
async function snap(html, width, height, file) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.setContent(html, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: file, type: "jpeg", quality: 85, fullPage: true });
  await page.close();
  console.log("->", path.relative(repo, file));
}

for (const s of SETS) {
  const info = JSON.parse(fs.readFileSync(path.join(preview, `limited_${s.id}_info.json`), "utf8"));
  // the banner concept (re-encoded at 85 %)
  const shot = `data:image/jpeg;base64,${b64(path.join(preview, "shots", `${s.shot}.jpg`))}`;
  await snap(`<html><body style="margin:0"><img src="${shot}" style="display:block;width:1600px;height:900px"/></body></html>`, 1600, 900, path.join(out, `navrh_${s.file}.jpg`));

  // the icons: the 6 golems and the capsule
  const cell = 250;
  const icon = (name) => {
    const file = path.join(preview, "icons", `${name}.png`);
    return fs.existsSync(file) ? `<img src="data:image/png;base64,${b64(file)}" style="width:${cell - 30}px;height:${cell - 30}px"/>` : "";
  };
  const cards = info.Golems.map(
    (g) => `<div style="width:${cell}px;text-align:center">${icon(`golem_${g.Id}`)}
      <div style="font-family:'Fredoka One';font-size:23px">${g.Name}</div>
      <div style="font-family:'Fredoka One';font-size:20px;color:${g.Color}">${g.Rarity.toUpperCase()} ${Math.round(g.Odds * 100)} %</div>
      <div style="font-family:'Fredoka One';font-size:18px;color:#8cf06a">${g.Bonus}</div></div>`,
  );
  cards.push(`<div style="width:${cell}px;text-align:center">${icon(`capsule_${info.CapsuleId}`)}
      <div style="font-family:'Fredoka One';font-size:23px">${info.Title} Capsule</div>
      <div style="font-family:'Fredoka One';font-size:20px;color:#ffb030">1 / 3 / 10 / 50</div></div>`);
  const html = `<html><head>${STYLE}</head><body>
    <div class="big" style="font-size:46px;padding:22px 28px 6px">${info.Title}: GOLEMOVÉ A KAPSLE</div>
    <div style="display:flex;flex-wrap:wrap;padding:10px 14px 24px">${cards.join("")}</div></body></html>`;
  await snap(html, 4 * cell + 60, 400, path.join(out, `ikony_${s.file}.jpg`));
}

await browser.close();
