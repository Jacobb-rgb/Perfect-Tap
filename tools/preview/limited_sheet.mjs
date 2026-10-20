// The LIMITED EDITION golem proposals as pictures for the owner (Config/LimitedGolems):
//   docs/screenshots/limited_golems/navrhy.jpg          the 4 concepts in a 2x2 grid, the names big
//   docs/screenshots/limited_golems/navrh_<theme>.jpg   each concept, 1600 x 900
//   docs/screenshots/limited_golems/ikony.jpg           the 24 golems' shop icons (golem_<Id>), a row per theme
// Run tools/preview/limited_golems.sh (it renders everything first, then calls this).
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

// the order the owner sees them in, the picture names and a line in Czech (the owner's language)
const THEMES = [
  { id: "Dragonforge", shot: "limited_dragonforge", file: "dragonforge", cz: "Golemové z dračího ohně: černý obsidián a žhnoucí láva, sopka a drak před obřím měsícem." },
  { id: "Galaxy", shot: "limited_galaxy", file: "galaxy", cz: "Vesmírní golemové: planety, hvězdy, kometa a astronaut ve skafandru." },
  { id: "MechaNeon", shot: "limited_mecha", file: "mecha_neon", cz: "Chromovaní roboti s neonovými světly v nočním neonovém městě." },
  { id: "FrostTitans", shot: "limited_frost", file: "frost_titans", cz: "Ledoví golemové pod polární září, ledovce a sníh." },
];

const b64 = (file) => fs.readFileSync(file).toString("base64");
const font = (name, file) =>
  `@font-face { font-family: "${name}"; src: url(data:font/woff2;base64,${b64(path.join(here, "node_modules/@fontsource", file))}) format("woff2"); }`;
const FONTS = [
  font("Luckiest Guy", "luckiest-guy/files/luckiest-guy-latin-400-normal.woff2"),
  font("Luckiest Guy", "luckiest-guy/files/luckiest-guy-latin-ext-400-normal.woff2"),
  font("Fredoka One", "fredoka-one/files/fredoka-one-latin-400-normal.woff2"),
].join("\n");
const STYLE = `<style>${FONTS}
  body { margin: 0; background: #15131f; color: #fff; font-family: Arial, Helvetica, sans-serif; }
  .big { font-family: "Luckiest Guy", "Arial Black", sans-serif; letter-spacing: 1px; -webkit-text-stroke: 2px #0e0e12; paint-order: stroke fill; }
  .badge { display: inline-flex; align-items: center; justify-content: center; border-radius: 50%; background: linear-gradient(#fff46e, #fab014);
    border: 4px solid #0e0e12; color: #fff; font-family: "Luckiest Guy"; -webkit-text-stroke: 2px #0e0e12; paint-order: stroke fill; }
</style>`;

const info = {};
for (const t of THEMES) info[t.id] = JSON.parse(fs.readFileSync(path.join(preview, `limited_${t.id}_info.json`), "utf8"));
const shot = (t) => `data:image/jpeg;base64,${b64(path.join(preview, "shots", `${t.shot}.jpg`))}`;
const mythic = (t) => info[t.id].Golems.find((g) => g.Rarity === "Mythic");

const browser = await chromium.launch();
async function snap(html, width, height, file) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.setContent(html, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: file, type: "jpeg", quality: 85, fullPage: true });
  await page.close();
  console.log("->", path.relative(repo, file));
}

// each concept on its own (re-encoded at 85 %)
for (const t of THEMES) {
  await snap(`<html><body style="margin:0"><img src="${shot(t)}" style="display:block;width:1600px;height:900px"/></body></html>`, 1600, 900, path.join(out, `navrh_${t.file}.jpg`));
}

// the 2 x 2 overview
{
  const W = 1920, gap = 30, cellW = (W - 3 * gap) / 2, cellH = Math.round((cellW * 9) / 16);
  const cells = THEMES.map((t) => {
    const i = info[t.id], m = mythic(t);
    return `<div>
      <img src="${shot(t)}" style="display:block;width:${cellW}px;height:${cellH}px;border-radius:16px;border:4px solid #0e0e12;box-sizing:border-box"/>
      <div style="display:flex;align-items:center;gap:18px;margin-top:12px">
        <div class="badge" style="width:74px;height:74px;font-size:52px;flex:none">${i.Letter}</div>
        <div>
          <div class="big" style="font-size:50px;line-height:1">${i.Title}</div>
          <div style="font-size:22px;color:#d8d4ee;margin-top:6px">${t.cz} Hlavní: <b style="color:#ff7aa6">${m.Name} (1 %)</b></div>
        </div>
      </div>
    </div>`;
  });
  const html = `<html><head>${STYLE}</head><body>
    <div style="padding:26px ${gap}px 6px">
      <div class="big" style="font-size:64px;line-height:1">LIMITOVANÁ EDICE GOLEMŮ – 4 NÁVRHY</div>
      <div style="font-size:28px;color:#ffd84a;margin-top:10px;font-weight:bold">Vyber jeden: A, B, C nebo D. Každý má 6 golemů (Rare, Rare, Epic, Epic, Legendary, Mythic) a své pozadí do obchodu.</div>
    </div>
    <div style="display:grid;grid-template-columns:repeat(2,${cellW}px);gap:${gap}px;padding:${gap}px">${cells.join("")}</div>
  </body></html>`;
  await snap(html, W, 400, path.join(out, "navrhy.jpg"));
}

// the 24 shop icons, a row per theme
{
  const cell = 230;
  const rows = THEMES.map((t) => {
    const i = info[t.id];
    const icons = i.Golems.map((g) => {
      const file = path.join(preview, "icons", `golem_${g.Id}.png`);
      const img = fs.existsSync(file) ? `<img src="data:image/png;base64,${b64(file)}" style="width:${cell - 40}px;height:${cell - 40}px"/>` : "";
      return `<div style="width:${cell}px;text-align:center">${img}
        <div style="font-family:'Fredoka One';font-size:21px">${g.Name}</div>
        <div style="font-family:'Fredoka One';font-size:19px;color:${g.Color}">${g.Rarity.toUpperCase()} ${Math.round(g.Odds * 100)} %</div></div>`;
    });
    return `<div style="display:flex;align-items:center;padding:14px 20px;border-bottom:2px solid #2a2740">
      <div style="width:250px;flex:none;display:flex;align-items:center;gap:14px">
        <div class="badge" style="width:62px;height:62px;font-size:44px;flex:none">${i.Letter}</div>
        <div class="big" style="font-size:30px;line-height:1.05">${i.Title}</div>
      </div>${icons.join("")}</div>`;
  });
  const html = `<html><head>${STYLE}</head><body>
    <div class="big" style="font-size:44px;padding:22px 24px 8px">IKONY GOLEMŮ DO OBCHODU (24)</div>
    ${rows.join("")}</body></html>`;
  await snap(html, 250 + 6 * cell + 60, 400, path.join(out, "ikony.jpg"));
}

await browser.close();
