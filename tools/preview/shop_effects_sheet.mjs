// Draws the shop v3 effects (owner 2026-11-11: "cool and smooth, not laggy") into ONE picture the
// owner uploads (IconAssets.ShopFx): a sunburst, a soft glow, a sparkle, a field of dots, a flame,
// a patch of classic studs and three lightning bolts, white on transparent (the game tints them
// with ImageColor3), in the cells IconAssets.ShopFx.Cells lists (1024 px square). Also writes every
// sprite alone as build/preview/icons/shopfx_<name>.png for the previews.
//   node tools/preview/shop_effects_sheet.mjs [sheetOutDir]
//   (default ../NAHRAJ_DO_ROBLOXU/ikony_obchod next to the project)
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
function kitRoot() {
  let dir = repo;
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(dir, "NAHRAJ_DO_ROBLOXU"))) return dir;
    dir = path.dirname(dir);
  }
  return path.dirname(repo);
}
const sheetDir = path.resolve(process.argv[2] || path.join(kitRoot(), "NAHRAJ_DO_ROBLOXU/ikony_obchod"));
const previewDir = path.join(repo, "build/preview/icons");
fs.mkdirSync(sheetDir, { recursive: true });
fs.mkdirSync(previewDir, { recursive: true });

// the cells: IconAssets.ShopFx.Cells (the game cuts its sprites by them)
const luau = fs.readFileSync(path.join(repo, "src/shared/Config/IconAssets.luau"), "utf8");
const block = luau.match(/IconAssets\.ShopFx = \{[\s\S]*?Cells = \{([\s\S]*?)\n\t\}/);
if (!block) throw new Error("IconAssets.ShopFx.Cells not found");
const cells = {};
for (const m of block[1].matchAll(/(\w+) = \{ (\d+), (\d+), (\d+), (\d+) \}/g)) {
  cells[m[1]] = [Number(m[2]), Number(m[3]), Number(m[4]), Number(m[5])];
}
const SIZE = 1024;
for (const [name, [x, y, w, h]] of Object.entries(cells)) {
  if (x + w > SIZE || y + h > SIZE) throw new Error(`${name} leaves the ${SIZE} px sheet`);
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE } });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent"><canvas id="c" width="${SIZE}" height="${SIZE}"></canvas></body></html>`);
const pngs = await page.evaluate((cells) => {
  const SIZE = 1024;
  // a seeded random (the same sheet every time)
  let seed = 20261111;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
  const out = {};
  const sheet = document.getElementById("c");
  const sctx = sheet.getContext("2d");

  function cell(w, h) {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    return [c, c.getContext("2d")];
  }

  const draw = {
    // a sunburst: 18 soft wedges, bright in the middle, gone at the rim
    rays(ctx, w, h) {
      const cx = w / 2, cy = h / 2, R = w / 2;
      ctx.filter = "blur(2px)";
      const n = 18;
      for (let i = 0; i < n; i++) {
        const a0 = (i / n) * Math.PI * 2;
        const a1 = a0 + (Math.PI * 2) / n * 0.45;
        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, R);
        g.addColorStop(0, "rgba(255,255,255,0.0)");
        g.addColorStop(0.08, "rgba(255,255,255,0.85)");
        g.addColorStop(0.45, "rgba(255,255,255,0.45)");
        g.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.arc(cx, cy, R, a0, a1);
        ctx.closePath();
        ctx.fill();
      }
      ctx.filter = "none";
    },
    // a soft round glow
    glow(ctx, w, h) {
      const g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
      g.addColorStop(0, "rgba(255,255,255,1)");
      g.addColorStop(0.25, "rgba(255,255,255,0.6)");
      g.addColorStop(0.6, "rgba(255,255,255,0.18)");
      g.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, w, h);
    },
    // a four-point sparkle with a halo
    sparkle(ctx, w, h) {
      const cx = w / 2, cy = h / 2, r = w * 0.46;
      const halo = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 0.55);
      halo.addColorStop(0, "rgba(255,255,255,0.7)");
      halo.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = halo;
      ctx.fillRect(0, 0, w, h);
      ctx.shadowColor = "rgba(255,255,255,0.9)";
      ctx.shadowBlur = 18;
      ctx.fillStyle = "#fff";
      ctx.beginPath();
      const k = 0.12;
      ctx.moveTo(cx, cy - r);
      ctx.bezierCurveTo(cx + r * k, cy - r * k, cx + r * k, cy - r * k, cx + r, cy);
      ctx.bezierCurveTo(cx + r * k, cy + r * k, cx + r * k, cy + r * k, cx, cy + r);
      ctx.bezierCurveTo(cx - r * k, cy + r * k, cx - r * k, cy + r * k, cx - r, cy);
      ctx.bezierCurveTo(cx - r * k, cy - r * k, cx - r * k, cy - r * k, cx, cy - r);
      ctx.fill();
      ctx.shadowBlur = 0;
    },
    // small soft dots (the bodies' particles)
    dots(ctx, w, h) {
      for (let i = 0; i < 46; i++) {
        const x = 6 + rnd() * (w - 12), y = 6 + rnd() * (h - 12), r = 1 + rnd() * 2.6;
        const g = ctx.createRadialGradient(x, y, 0, x, y, r * 1.8);
        g.addColorStop(0, `rgba(255,255,255,${(0.45 + rnd() * 0.5).toFixed(2)})`);
        g.addColorStop(0.55, "rgba(255,255,255,0.35)");
        g.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, r * 1.8, 0, Math.PI * 2);
        ctx.fill();
      }
    },
    // a flame tongue, bright inside
    flame(ctx, w, h) {
      ctx.filter = "blur(1.5px)";
      const path = (s) => {
        ctx.beginPath();
        ctx.moveTo(w * 0.5, h * (0.04 + (1 - s) * 0.5));
        ctx.bezierCurveTo(w * (0.5 + 0.48 * s), h * 0.42, w * (0.5 + 0.5 * s), h * 0.78, w * 0.5, h * 0.99);
        ctx.bezierCurveTo(w * (0.5 - 0.5 * s), h * 0.78, w * (0.5 - 0.48 * s), h * 0.42, w * 0.5, h * (0.04 + (1 - s) * 0.5));
        ctx.closePath();
      };
      ctx.fillStyle = "rgba(255,255,255,0.55)";
      path(1);
      ctx.fill();
      ctx.fillStyle = "rgba(255,255,255,0.95)";
      path(0.55);
      ctx.fill();
      ctx.filter = "none";
    },
    // classic Roblox top studs: a lit top-left, a faint body, a shaded bottom-right ring (overlay)
    studs(ctx, w, h) {
      const step = 32, r = 10.5;
      for (let y = step / 2; y < h; y += step) {
        for (let x = step / 2; x < w; x += step) {
          ctx.fillStyle = "rgba(0,0,0,0.26)";
          ctx.beginPath();
          ctx.arc(x + 1.6, y + 2, r, 0, Math.PI * 2);
          ctx.fill();
          ctx.fillStyle = "rgba(255,255,255,0.16)";
          ctx.beginPath();
          ctx.arc(x, y, r, 0, Math.PI * 2);
          ctx.fill();
          const g = ctx.createRadialGradient(x - r * 0.35, y - r * 0.4, 0, x - r * 0.35, y - r * 0.4, r * 0.75);
          g.addColorStop(0, "rgba(255,255,255,0.75)");
          g.addColorStop(1, "rgba(255,255,255,0)");
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.arc(x, y, r, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    },
  };
  // lightning: a jagged line top to bottom with forks: a wide haze, a body, a hot core
  function boltPoints(x1, y1, x2, y2, disp, depth) {
    if (depth === 0) return [[x1, y1], [x2, y2]];
    const mx = (x1 + x2) / 2 + (rnd() - 0.5) * disp, my = (y1 + y2) / 2 + (rnd() - 0.5) * disp * 0.35;
    const a = boltPoints(x1, y1, mx, my, disp / 2, depth - 1), b = boltPoints(mx, my, x2, y2, disp / 2, depth - 1);
    return a.concat(b.slice(1));
  }
  function bolt(ctx, w, h) {
    const main = boltPoints(w * (0.4 + rnd() * 0.2), 6, w * (0.4 + rnd() * 0.2), h - 6, w * 0.7, 6);
    const paths = [main];
    for (let i = 0; i < 3; i++) {
      const k = Math.floor(main.length * (0.2 + rnd() * 0.55));
      const [bx, by] = main[k];
      const side = rnd() < 0.5 ? -1 : 1;
      const len = h * (0.16 + rnd() * 0.18);
      paths.push(boltPoints(bx, by, bx + side * len * 0.55, by + len, len * 0.5, 4));
    }
    const stroke = (p, width, color, blur) => {
      ctx.filter = blur ? `blur(${blur}px)` : "none";
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.beginPath();
      p.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
      ctx.stroke();
    };
    paths.forEach((p, i) => stroke(p, i ? 12 : 22, "rgba(255,255,255,0.32)", 7));
    paths.forEach((p, i) => stroke(p, i ? 4 : 8, "rgba(255,255,255,0.85)", 1));
    paths.forEach((p, i) => stroke(p, i ? 1.6 : 3, "rgba(255,255,255,1)", 0));
    ctx.filter = "none";
  }
  draw.bolt1 = bolt;
  draw.bolt2 = bolt;
  draw.bolt3 = bolt;

  for (const [name, [x, y, w, h]] of Object.entries(cells)) {
    const fn = draw[name];
    if (!fn) throw new Error("no drawing for " + name);
    const [c, ctx] = cell(w, h);
    fn(ctx, w, h);
    sctx.drawImage(c, x, y);
    out[name] = c.toDataURL("image/png");
  }
  out.__sheet = sheet.toDataURL("image/png");
  return out;
}, cells);
await browser.close();

const write = (file, url) => fs.writeFileSync(file, Buffer.from(url.split(",")[1], "base64"));
const sheetFile = path.join(sheetDir, "obchod_efekty.png");
write(sheetFile, pngs.__sheet);
console.log("sheet", path.relative(process.cwd(), sheetFile), `${SIZE} x ${SIZE}`, `${Object.keys(cells).length} sprites`);
for (const name of Object.keys(cells)) write(path.join(previewDir, `shopfx_${name}.png`), pngs[name]);
console.log("previews", Object.keys(cells).length, "->", path.relative(process.cwd(), previewDir));
