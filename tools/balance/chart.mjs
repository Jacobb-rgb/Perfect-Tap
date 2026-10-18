// Balance chart: money earned and income per second over 10 hours (log scale),
// today's prices vs the calibrated proposal, for the Typical player.
// Input: build/balance/sim.json (+ build/balance/proposal.json if present),
// written by `lune run tools/lune/balance_sim.luau [calibrate]`.
// Output: docs/screenshots/balance_chart.png
// Run: node tools/balance/chart.mjs
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = process.cwd();
const require = createRequire(path.join(root, "tools/preview/package.json"));
const { chromium } = require("playwright");

const read = (file) => (fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null);
const sim = read(path.join(root, "build/balance/sim.json"));
const proposal = read(path.join(root, "build/balance/proposal.json"));
if (!sim) throw new Error("run lune run tools/lune/balance_sim.luau first");

const pick = (data, name) => data && data.Scenarios.find((s) => s.Name === name);
const lines = [
  { label: "Today: income/s", data: pick(sim, "Typical"), key: "Income", color: "#ff9a3c", dash: "" },
  { label: "Today: money earned", data: pick(sim, "Typical"), key: "Earned", color: "#ff9a3c", dash: "6 5" },
  { label: "Proposal: income/s", data: pick(proposal, "Proposal Typical"), key: "Income", color: "#5ac8ff", dash: "" },
  { label: "Proposal: money earned", data: pick(proposal, "Proposal Typical"), key: "Earned", color: "#5ac8ff", dash: "6 5" },
].filter((l) => l.data);

const W = 1400, H = 800, L = 110, R = 40, T = 70, B = 90;
const hours = 10;
const minLog = 0, maxLog = 13; // 1 .. 10^13
const x = (t) => L + (t / (hours * 3600)) * (W - L - R);
const y = (v) => {
  const lv = Math.log10(Math.max(1, v));
  return T + (1 - (lv - minLog) / (maxLog - minLog)) * (H - T - B);
};
const fmt = (e) => (e >= 12 ? `${10 ** (e - 12)}T` : e >= 9 ? `${10 ** (e - 9)}B` : e >= 6 ? `${10 ** (e - 6)}M` : e >= 3 ? `${10 ** (e - 3)}K` : `${10 ** e}`);

let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" font-family="Arial, sans-serif">`;
svg += `<rect width="100%" height="100%" fill="#16141f"/>`;
svg += `<text x="${L}" y="40" fill="#fff" font-size="26" font-weight="bold">TERRA FORGE balance sim: typical player, first 10 hours (log scale)</text>`;
for (let e = minLog; e <= maxLog; e++) {
  svg += `<line x1="${L}" x2="${W - R}" y1="${y(10 ** e)}" y2="${y(10 ** e)}" stroke="#2c2a3a"/>`;
  svg += `<text x="${L - 12}" y="${y(10 ** e) + 5}" fill="#aaa" font-size="15" text-anchor="end">$${fmt(e)}</text>`;
}
for (let h = 0; h <= hours; h++) {
  svg += `<line y1="${T}" y2="${H - B}" x1="${x(h * 3600)}" x2="${x(h * 3600)}" stroke="#2c2a3a"/>`;
  svg += `<text x="${x(h * 3600)}" y="${H - B + 26}" fill="#aaa" font-size="15" text-anchor="middle">${h}h</text>`;
}
for (const line of lines) {
  const pts = line.data.Series.map((p) => `${x(p.T).toFixed(1)},${y(p[line.key]).toFixed(1)}`).join(" ");
  svg += `<polyline points="${pts}" fill="none" stroke="${line.color}" stroke-width="3.5" stroke-dasharray="${line.dash}"/>`;
}
// blaster milestones of both runs as dots on the income line
const markers = (data, color, row) => {
  if (!data) return;
  for (const m of data.Milestones) {
    const level = /^Blaster (\d+)$/.exec(m.Key);
    if (!level || m.Median == null) continue;
    const px = x(m.Median);
    svg += `<circle cx="${px}" cy="${H - B - 14 - row * 22}" r="9" fill="${color}"/>`;
    svg += `<text x="${px}" y="${H - B - 9 - row * 22}" fill="#111" font-size="12" font-weight="bold" text-anchor="middle">${level[1]}</text>`;
  }
};
markers(pick(sim, "Typical"), "#ff9a3c", 1);
markers(pick(proposal, "Proposal Typical"), "#5ac8ff", 0);
let ly = T + 20;
for (const line of lines) {
  svg += `<line x1="${L + 30}" x2="${L + 70}" y1="${ly}" y2="${ly}" stroke="${line.color}" stroke-width="4" stroke-dasharray="${line.dash}"/>`;
  svg += `<text x="${L + 80}" y="${ly + 5}" fill="#eee" font-size="16">${line.label}</text>`;
  ly += 26;
}
svg += `<text x="${L + 30}" y="${ly + 10}" fill="#bbb" font-size="14">numbered dots = new blaster level</text>`;
svg += `</svg>`;

const out = path.join(root, "docs/screenshots/balance_chart.png");
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
await page.screenshot({ path: out });
await browser.close();
console.log("chart ->", path.relative(root, out));
