// Terra Forge 3D UI icons (light "Bubble" UI style, like popular simulators).
// Each icon is a small glossy three.js model rendered on a transparent
// background, cropped, and given a thick dark outline. The PNGs are uploaded
// to Roblox as images (they are pictures, not in-game models).
//   page: /icons/icons.html?icon=<name>&size=512
// Icons named "parts:<file>" load a part model exported by
// tools/lune/export_icon_parts.luau (blaster, ore chunks), so they match the game.
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { FontLoader } from "three/addons/loaders/FontLoader.js";
import { TextGeometry } from "three/addons/geometries/TextGeometry.js";

let FONT = null; // helvetiker bold, loaded in main() for the enchant runes and TEXT_ICONS
const TEXT_ICONS = ["luck_server"]; // ICONS that draw text

// enchant_<EnchantConfig id>: a gem in the enchant's colour with its mark
const RUNES = {
  enchant_Power: ["P", "e2453c"],
  enchant_Swift: ["S", "3fa2ff"],
  enchant_Reach: ["R", "1fbfa0"],
  enchant_Magnetism: ["M", "8e5cf0"],
  enchant_Lucky: ["L", "2fc95a"],
  enchant_Midas: ["G", "f5a300"],
  enchant_TwinDrop: ["T", "b45cff"],
  enchant_Overcharge: ["O", "ff7a1c"],
  enchant_Prospector: ["D", "b0784a"],
  enchant_GolemBond: ["B", "5b7cff"],
  enchant_Heartfire: ["H", "ff3b5c"],
  enchant_Starbreaker: ["Star", "ff3b9a"],
};

const params = new URLSearchParams(location.search);
const iconName = params.get("icon") || "coin";
const SIZE = Number(params.get("size") || 512);
const RENDER = 1024;
const OUTLINE = "#1b1d33";

// ---------------------------------------------------------------- helpers
const D = THREE.MathUtils.degToRad;

function mat(color, o = {}) {
  return new THREE.MeshPhysicalMaterial({
    color: new THREE.Color(color),
    roughness: o.rough ?? 0.4,
    metalness: o.metal ?? 0,
    clearcoat: o.coat ?? 0.55,
    clearcoatRoughness: 0.22,
    emissive: new THREE.Color(o.glow ?? 0x000000),
    emissiveIntensity: o.glowI ?? 1,
    transparent: (o.opacity ?? 1) < 1,
    opacity: o.opacity ?? 1,
  });
}

function place(mesh, pos = [0, 0, 0], rot = [0, 0, 0]) {
  mesh.position.set(...pos);
  mesh.rotation.set(D(rot[0]), D(rot[1]), D(rot[2]));
  return mesh;
}

const box = (w, h, d, r, color, o, pos, rot) =>
  place(new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 6, Math.min(r, w / 2, h / 2, d / 2) - 1e-4), mat(color, o)), pos, rot);
const ball = (r, color, o, pos, rot, sx = 1, sy = 1, sz = 1) => {
  const m = place(new THREE.Mesh(new THREE.SphereGeometry(r, 40, 24), mat(color, o)), pos, rot);
  m.scale.set(sx, sy, sz);
  return m;
};
const cyl = (rt, rb, h, color, o, pos, rot, seg = 48) =>
  place(new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), mat(color, o)), pos, rot);
const torus = (R, r, arc, color, o, pos, rot) =>
  place(new THREE.Mesh(new THREE.TorusGeometry(R, r, 16, 48, arc), mat(color, o)), pos, rot);

// rounded profile revolved around Y (points: [radius, y] from bottom to top)
function lathe(points, color, o, pos, rot) {
  const pts = points.map(([x, y]) => new THREE.Vector2(x, y));
  return place(new THREE.Mesh(new THREE.LatheGeometry(pts, 72), mat(color, o)), pos, rot);
}

function extrude(shape, depth, bevel, color, o, pos, rot) {
  const g = new THREE.ExtrudeGeometry(shape, {
    depth,
    bevelEnabled: bevel > 0,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: 5,
    curveSegments: 32,
  });
  g.center();
  return place(new THREE.Mesh(g, mat(color, o)), pos, rot);
}

function starShape(outer, inner, points = 5) {
  const s = new THREE.Shape();
  for (let i = 0; i <= points * 2; i++) {
    const r = i % 2 === 0 ? outer : inner;
    const a = Math.PI / 2 + (i * Math.PI) / points;
    const x = Math.cos(a) * r;
    const y = Math.sin(a) * r;
    if (i === 0) s.moveTo(x, y);
    else s.lineTo(x, y);
  }
  return s;
}

// hexagonal crystal: prism + pointed top
function crystal(r, h, color, o, pos, rot) {
  const g = new THREE.Group();
  g.add(cyl(r, r * 0.92, h, color, o, [0, h / 2, 0], [0, 0, 0], 6));
  g.add(place(new THREE.Mesh(new THREE.ConeGeometry(r, r * 1.5, 6), mat(color, o)), [0, h + r * 0.75, 0]));
  return place(g, pos, rot);
}

function group(children, pos, rot) {
  const g = new THREE.Group();
  for (const c of children) g.add(c);
  return place(g, pos, rot);
}

// a gold star coin lying flat (the coins() look), radius 1.02 * s
function goldCoin(s, pos, rot) {
  const rim = lathe(
    [[0, -0.1], [0.8, -0.1], [0.9, -0.17], [1.0, -0.12], [1.02, 0], [1.0, 0.12], [0.9, 0.17], [0.8, 0.1], [0, 0.1]],
    GOLD, shiny,
  );
  const star = extrude(starShape(0.48, 0.22), 0.05, 0.03, "#ffd75e", shiny, [0, 0.13, 0], [-90, 0, 0]);
  const g = group([rim, star], pos, rot);
  g.scale.setScalar(s);
  return g;
}

// 4-point sparkle
const sparkle = (r, pos) => extrude(starShape(r, r * 0.4, 4), 0.06, 0.02, "#fff1a8", glow("#ffd040", 0.5), pos);

// repeatable pseudo-random numbers in [0, 1) (piles look the same every render)
function seeded(seed) {
  return () => (seed = (seed * 16807) % 2147483647) / 2147483647;
}

// ---------------------------------------------------------------- palette
const GOLD = "#ffcb2e";
const GOLD_DARK = "#f09a1a";
const STEEL = "#c9d3de";
const STEEL_DARK = "#7d8a9b";
const STONE = "#a3afc4";
const STONE_DARK = "#7b879e";
const GLOW_CYAN = "#46e6ff";
const shiny = { metal: 0.12, rough: 0.3, coat: 0.85 };
const steel = { metal: 0.55, rough: 0.3, coat: 0.5 };
const glow = (c, i = 1.4) => ({ glow: c, glowI: i, coat: 0.8, rough: 0.2 });

// ---------------------------------------------------------------- icons
// Each returns { model, yaw, pitch } (the model is turned toward the camera by yaw/pitch).
const ICONS = {
  coin() {
    const rim = lathe(
      [
        [0, -0.1], [0.76, -0.1], [0.8, -0.15], [0.86, -0.18], [0.95, -0.17], [1.0, -0.12],
        [1.02, 0], [1.0, 0.12], [0.95, 0.17], [0.86, 0.18], [0.8, 0.15], [0.76, 0.1], [0, 0.1],
      ],
      GOLD, shiny,
    );
    const star = extrude(starShape(0.5, 0.23), 0.05, 0.03, "#ffd75e", shiny, [0, 0.13, 0], [-90, 0, 0]);
    const coin = group([rim, star], [0, 0, 0], [90, 0, 0]);
    return { model: coin, yaw: -28, pitch: 8 };
  },

  coins() {
    const one = (pos, rot) => {
      const rim = lathe(
        [[0, -0.1], [0.8, -0.1], [0.9, -0.17], [1.0, -0.12], [1.02, 0], [1.0, 0.12], [0.9, 0.17], [0.8, 0.1], [0, 0.1]],
        GOLD, shiny,
      );
      const star = extrude(starShape(0.48, 0.22), 0.05, 0.03, "#ffd75e", shiny, [0, 0.13, 0], [-90, 0, 0]);
      return group([rim, star], pos, rot);
    };
    const stack = group([
      one([0, -0.75, 0], [0, 10, 0]), one([0.05, -0.47, 0.02], [0, 40, 0]), one([-0.04, -0.19, 0], [0, 75, 0]),
    ]);
    const front = one([0.55, 0.2, 0.75], [75, 0, -18]);
    return { model: group([stack, front]), yaw: -20, pitch: 18 };
  },

  backpack() {
    const BODY = "#f39b3b";
    const DARK = "#df7f25";
    const STRAP = "#8a4f22";
    const parts = [
      box(1.5, 1.8, 0.95, 0.4, BODY, {}, [0, 0, 0]),
      box(1.48, 0.78, 1.04, 0.32, DARK, {}, [0, 0.58, 0.03]),
      box(1.05, 0.78, 0.4, 0.2, DARK, {}, [0, -0.36, 0.48]),
      box(0.62, 0.08, 0.06, 0.03, STRAP, {}, [0, -0.08, 0.68]),
      box(0.22, 0.6, 0.08, 0.04, STRAP, {}, [0, 0.33, 0.55]),
      box(0.34, 0.26, 0.12, 0.06, GOLD, shiny, [0, 0.12, 0.6]),
      box(0.3, 0.75, 0.62, 0.14, DARK, {}, [0.8, -0.32, 0]),
      box(0.3, 0.75, 0.62, 0.14, DARK, {}, [-0.8, -0.32, 0]),
      torus(0.28, 0.075, Math.PI, STRAP, {}, [0, 0.95, 0]),
    ];
    return { model: group(parts), yaw: -24, pitch: 10 };
  },

  golem() {
    const parts = [
      box(1.7, 1.0, 1.15, 0.38, "#8e9bb3", {}, [0, -0.78, -0.05]),
      box(0.62, 0.62, 0.7, 0.24, STONE_DARK, {}, [1.02, -0.55, 0]),
      box(0.62, 0.62, 0.7, 0.24, STONE_DARK, {}, [-1.02, -0.55, 0]),
      box(1.55, 1.3, 1.3, 0.46, STONE, {}, [0, 0.35, 0]),
      box(1.32, 0.22, 0.34, 0.1, STONE_DARK, {}, [0, 0.62, 0.55]),
      ball(0.16, GLOW_CYAN, glow(GLOW_CYAN, 1.6), [0.34, 0.3, 0.6], [0, 0, 0], 1, 1.1, 0.55),
      ball(0.16, GLOW_CYAN, glow(GLOW_CYAN, 1.6), [-0.34, 0.3, 0.6], [0, 0, 0], 1, 1.1, 0.55),
      box(0.3, 0.06, 0.06, 0.03, "#5a6378", {}, [0, -0.04, 0.65]),
      box(0.42, 0.34, 0.2, 0.12, "#95a2b9", {}, [0.52, -0.12, 0.6], [0, 0, 18]),
      box(0.3, 0.26, 0.2, 0.1, "#95a2b9", {}, [-0.58, 0.72, 0.58], [0, 0, -12]),
      box(0.42, 0.3, 0.2, 0.12, "#7f8ba3", {}, [-0.5, -1.02, 0.52], [0, 0, 10]),
      place(new THREE.Mesh(new THREE.OctahedronGeometry(0.22), mat(GLOW_CYAN, glow(GLOW_CYAN, 1.1))), [0, -0.72, 0.56], [0, 45, 0]),
      ball(0.36, "#6ccb5f", {}, [-0.42, 0.98, 0.05], [0, 0, 0], 1, 0.38, 1),
      crystal(0.17, 0.42, "#7cf0ff", glow("#2bb8e0", 0.55), [0.18, 0.92, -0.05], [8, 0, -14]),
      crystal(0.12, 0.3, "#b48cff", glow("#7a4ce0", 0.5), [0.5, 0.88, 0.1], [0, 0, -34]),
      crystal(0.1, 0.22, "#7cf0ff", glow("#2bb8e0", 0.55), [-0.1, 0.94, 0.25], [20, 0, 18]),
    ];
    return { model: group(parts), yaw: -20, pitch: 8 };
  },

  build() {
    const hammer = group(
      [
        cyl(0.12, 0.12, 1.9, "#c98a4b", {}, [0, -0.15, 0]),
        cyl(0.15, 0.15, 0.62, "#e2453c", {}, [0, -0.82, 0]),
        box(1.25, 0.5, 0.52, 0.15, STEEL, steel, [0.1, 0.85, 0]),
        box(0.18, 0.56, 0.56, 0.08, "#e7edf4", steel, [0.7, 0.85, 0]),
      ],
      [0.18, 0, 0.12],
      [0, 0, 38],
    );
    const s = new THREE.Shape();
    const R = 0.44;
    const a = Math.acos(0.15 / R);
    s.absarc(0, 0, R, Math.PI - a, Math.PI * 2 + a, false);
    s.lineTo(0.15, 0.02);
    s.lineTo(-0.15, 0.02);
    s.closePath();
    const wrench = group(
      [
        extrude(s, 0.16, 0.035, "#8fb2db", steel, [0, 0.9, 0]),
        box(0.3, 1.55, 0.18, 0.08, "#8fb2db", steel, [0, -0.05, 0]),
        cyl(0.2, 0.2, 0.18, "#8fb2db", steel, [0, -0.85, 0], [90, 0, 0]),
      ],
      [-0.1, 0, -0.12],
      [0, 0, -40],
    );
    return { model: group([wrench, hammer]), yaw: -14, pitch: 6 };
  },

  shop() {
    const BAG = "#ff4f8b";
    const parts = [
      box(1.45, 1.5, 0.8, 0.14, BAG, {}, [0, -0.1, 0]),
      box(1.48, 0.24, 0.83, 0.08, "#ff8ab3", {}, [0, 0.58, 0]),
      torus(0.34, 0.065, Math.PI, "#b8285e", {}, [0, 0.7, 0.24]),
      torus(0.34, 0.065, Math.PI, "#b8285e", {}, [0, 0.7, -0.24]),
      extrude(starShape(0.44, 0.2), 0.08, 0.04, GOLD, shiny, [0, -0.15, 0.45]),
    ];
    return { model: group(parts), yaw: -24, pitch: 10 };
  },

  more() {
    const parts = [
      box(0.86, 0.86, 0.32, 0.22, "#ff5a5a", {}, [-0.5, 0.5, 0]),
      box(0.86, 0.86, 0.32, 0.22, "#ffc93c", {}, [0.5, 0.5, 0]),
      box(0.86, 0.86, 0.32, 0.22, "#3ddc84", {}, [-0.5, -0.5, 0]),
      box(0.86, 0.86, 0.32, 0.22, "#4da3ff", {}, [0.5, -0.5, 0]),
    ];
    return { model: group(parts), yaw: -20, pitch: 14 };
  },

  base() {
    const roof = new THREE.Shape();
    roof.moveTo(-1.0, 0);
    roof.lineTo(1.0, 0);
    roof.lineTo(0, 0.78);
    roof.closePath();
    const parts = [
      cyl(1.25, 1.3, 0.2, "#69d46a", {}, [0, -0.98, 0]),
      box(1.5, 1.05, 1.3, 0.14, "#fff1d6", {}, [0, -0.38, 0]),
      extrude(roof, 1.45, 0.07, "#ff6b3d", {}, [0, 0.42, 0]),
      box(0.24, 0.42, 0.24, 0.05, "#c0563a", {}, [0.45, 0.62, -0.25]),
      box(0.38, 0.6, 0.1, 0.08, "#8a5530", {}, [0, -0.6, 0.66]),
      ball(0.04, GOLD, shiny, [0.1, -0.6, 0.73]),
      box(0.34, 0.34, 0.1, 0.06, "#8fe3ff", glow("#3fbfe8", 0.35), [-0.48, -0.28, 0.66]),
      box(0.34, 0.34, 0.1, 0.06, "#8fe3ff", glow("#3fbfe8", 0.35), [0.48, -0.28, 0.66]),
    ];
    return { model: group(parts), yaw: -30, pitch: 14 };
  },

  lobby() {
    const STONE_L = "#dfe4ee";
    const WATER = "#4fc3ff";
    const parts = [
      lathe([[0, -0.4], [1.1, -0.4], [1.18, -0.3], [1.18, 0.0], [1.08, 0.08], [1.0, 0.0], [0.98, -0.12], [0, -0.12]], STONE_L, {}),
      cyl(1.0, 1.0, 0.04, WATER, glow("#1e88d0", 0.35), [0, -0.06, 0]),
      cyl(0.17, 0.22, 0.75, STONE_L, {}, [0, 0.3, 0]),
      lathe([[0, 0.62], [0.5, 0.62], [0.56, 0.7], [0.56, 0.82], [0.48, 0.84], [0, 0.76]], STONE_L, {}),
      cyl(0.44, 0.44, 0.03, WATER, glow("#1e88d0", 0.35), [0, 0.81, 0]),
      ball(0.17, "#8ee0ff", glow("#3fbfe8", 0.5), [0, 1.0, 0], [0, 0, 0], 1, 1.3, 1),
      ball(0.1, "#8ee0ff", glow("#3fbfe8", 0.5), [0, 1.26, 0]),
      ...[0, 72, 144, 216, 288].map((a) =>
        ball(0.08, "#8ee0ff", glow("#3fbfe8", 0.5), [Math.cos(D(a)) * 0.68, 0.55, Math.sin(D(a)) * 0.68]),
      ),
      ...[36, 108, 180, 252, 324].map((a) =>
        ball(0.065, "#8ee0ff", glow("#3fbfe8", 0.5), [Math.cos(D(a)) * 0.8, 0.25, Math.sin(D(a)) * 0.8]),
      ),
    ];
    return { model: group(parts), yaw: 0, pitch: 24 };
  },

  shard() {
    const parts = [
      crystal(0.32, 1.1, "#7cf0ff", glow("#25b6e6", 0.45), [0, -0.7, 0], [0, 0, 0]),
      crystal(0.24, 0.75, "#b48cff", glow("#7a4ce0", 0.45), [-0.45, -0.75, 0.1], [0, 30, 22]),
      crystal(0.22, 0.65, "#ff8ad8", glow("#e04ca8", 0.4), [0.45, -0.75, 0.05], [0, -20, -24]),
      crystal(0.16, 0.45, "#7cf0ff", glow("#25b6e6", 0.45), [0.12, -0.75, 0.42], [28, 0, -8]),
      ball(0.6, "#8a7f9a", { rough: 0.8 }, [0, -0.85, 0], [0, 0, 0], 1.2, 0.35, 1),
    ];
    return { model: group(parts), yaw: -18, pitch: 12 };
  },

  artifact() {
    const ring = lathe([[0.62, -0.3], [0.7, -0.3], [0.74, -0.22], [0.74, 0.12], [0.66, 0.16], [0.6, 0.12], [0.6, -0.22]], GOLD, shiny);
    const points = [];
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * Math.PI * 2;
      points.push(place(new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.5, 4), mat(GOLD, shiny)), [Math.cos(a) * 0.66, 0.38, Math.sin(a) * 0.66], [0, -D(a * 57.3), 0]));
      points.push(ball(0.07, GOLD, shiny, [Math.cos(a) * 0.66, 0.66, Math.sin(a) * 0.66]));
    }
    const gems = [
      ball(0.13, "#ff4f6d", glow("#c01838", 0.35), [0, -0.06, 0.72], [0, 0, 0], 1, 1, 0.6),
      ball(0.1, "#46b8ff", glow("#1a6fd0", 0.35), [0.5, -0.06, 0.52], [0, 45, 0], 1, 1, 0.6),
      ball(0.1, "#3ddc84", glow("#18a050", 0.35), [-0.5, -0.06, 0.52], [0, -45, 0], 1, 1, 0.6),
    ];
    const velvet = ball(0.58, "#c0304a", {}, [0, 0.0, 0], [0, 0, 0], 1, 0.75, 1);
    return { model: group([velvet, ring, ...points, ...gems]), yaw: 0, pitch: 18 };
  },

  medal() {
    const ribbonL = box(0.34, 0.9, 0.06, 0.04, "#ff4f6d", {}, [-0.22, 0.75, -0.1], [0, 0, 16]);
    const ribbonR = box(0.34, 0.9, 0.06, 0.04, "#4da3ff", {}, [0.22, 0.75, -0.1], [0, 0, -16]);
    const disc = lathe([[0, -0.12], [0.8, -0.12], [0.88, -0.06], [0.9, 0], [0.88, 0.06], [0.8, 0.12], [0, 0.12]], GOLD, shiny, [0, 0, 0], [90, 0, 0]);
    const inner = cyl(0.62, 0.62, 0.05, "#ffe07a", shiny, [0, 0, 0.12], [90, 0, 0]);
    const star = extrude(starShape(0.48, 0.21), 0.08, 0.04, "#ff9f1c", shiny, [0, 0, 0.18]);
    return { model: group([ribbonL, ribbonR, disc, inner, star]), yaw: -16, pitch: 6 };
  },

  podium() {
    const parts = [
      cyl(1.1, 1.15, 0.3, "#6b7b99", steel, [0, -0.9, 0]),
      cyl(0.8, 0.85, 0.5, "#fff1d6", {}, [0, -0.5, 0]),
      cyl(0.84, 0.84, 0.08, GOLD, shiny, [0, -0.22, 0]),
      crystal(0.26, 0.55, "#ff4f6d", glow("#c01838", 0.35), [0, -0.2, 0], [0, 0, 0]),
      crystal(0.16, 0.32, "#ff8ab3", glow("#c01838", 0.3), [0.32, -0.2, 0.1], [0, 0, -26]),
      crystal(0.15, 0.3, "#ff8ab3", glow("#c01838", 0.3), [-0.3, -0.2, 0.06], [0, 0, 24]),
    ];
    return { model: group(parts), yaw: -20, pitch: 18 };
  },

  moon() {
    const moon = new THREE.Shape();
    moon.absarc(0, 0, 1, D(-110), D(110), true);
    moon.absarc(0.45, 0, 0.82, D(118), D(-118), false);
    const parts = [
      extrude(moon, 0.4, 0.08, "#ffd75e", { coat: 0.8, rough: 0.3 }, [-0.2, 0, 0]),
      extrude(starShape(0.3, 0.13), 0.12, 0.04, "#fff1a8", glow("#ffd040", 0.4), [0.75, 0.55, 0.1]),
      extrude(starShape(0.18, 0.08), 0.1, 0.03, "#fff1a8", glow("#ffd040", 0.4), [0.95, -0.35, 0.1]),
      ball(0.07, "#fff1a8", glow("#ffd040", 0.5), [0.45, 0.95, 0.1]),
    ];
    return { model: group(parts), yaw: -14, pitch: 4 };
  },

  clover() {
    const leaves = [];
    for (let i = 0; i < 4; i++) {
      const a = D(45 + i * 90);
      leaves.push(ball(0.42, "#3ddc84", {}, [Math.cos(a) * 0.42, Math.sin(a) * 0.42, 0], [0, 0, i * 90 + 45], 1.0, 0.75, 0.35));
    }
    const stem = cyl(0.07, 0.09, 0.8, "#25a85a", {}, [0.25, -0.75, -0.05], [0, 0, 24]);
    const center = ball(0.14, "#9df2b8", {}, [0, 0, 0.1]);
    const spark = extrude(starShape(0.2, 0.08, 4), 0.06, 0.02, "#fff1a8", glow("#ffd040", 0.5), [0.75, 0.7, 0.15]);
    return { model: group([...leaves, stem, center, spark]), yaw: -16, pitch: 10 };
  },

  rainbow() {
    // Hexa Lucky (mining luck): a faceted rainbow gem with sparkles
    const colors = ["#ff5a5a", "#ffa63c", "#ffd23c", "#3ddc84", "#4da3ff", "#b48cff"];
    const parts = [];
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      const wedge = new THREE.Mesh(new THREE.CylinderGeometry(0.0, 0.85, 1.0, 1, 1, false, a, Math.PI / 3), mat(colors[i], glow(colors[i], 0.25)));
      wedge.position.set(0, -0.3, 0);
      wedge.rotation.x = Math.PI;
      parts.push(wedge);
      const top = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.85, 0.4, 1, 1, false, a, Math.PI / 3), mat(colors[i], glow(colors[i], 0.25)));
      top.position.set(0, 0.4, 0);
      parts.push(top);
    }
    parts.push(cyl(0.55, 0.55, 0.02, "#ffffff", { coat: 1 }, [0, 0.61, 0], [0, 0, 0], 6));
    parts.push(extrude(starShape(0.22, 0.08, 4), 0.06, 0.02, "#fff1a8", glow("#ffd040", 0.5), [0.9, 0.85, 0.2]));
    parts.push(extrude(starShape(0.15, 0.06, 4), 0.06, 0.02, "#fff1a8", glow("#ffd040", 0.5), [-0.95, 0.35, 0.2]));
    return { model: group(parts), yaw: 0, pitch: 22 };
  },

  enchant() {
    const parts = [
      ball(0.62, "#ff6a3d", glow("#ff3d1a", 0.6), [0, 0.05, 0]),
      ball(0.4, "#ffd27a", glow("#ffb03c", 0.9), [0, 0.05, 0.3]),
      torus(0.85, 0.06, Math.PI * 2, GOLD, shiny, [0, 0.05, 0], [70, 0, 20]),
      torus(0.85, 0.06, Math.PI * 2, GOLD, shiny, [0, 0.05, 0], [70, 0, -40]),
      cyl(0.5, 0.65, 0.3, "#5b6677", steel, [0, -0.8, 0]),
      cyl(0.66, 0.66, 0.08, GOLD, shiny, [0, -0.62, 0]),
    ];
    return { model: group(parts), yaw: -10, pitch: 10 };
  },

  check() {
    const s = new THREE.Shape();
    s.moveTo(-0.95, 0.1);
    s.lineTo(-0.55, 0.5);
    s.lineTo(-0.25, 0.2);
    s.lineTo(0.6, 1.0);
    s.lineTo(1.0, 0.6);
    s.lineTo(-0.25, -0.62);
    s.closePath();
    return { model: group([extrude(s, 0.3, 0.1, "#3ddc84", {})]), yaw: -10, pitch: 6 };
  },

  wheel() {
    const colors = ["#ff5a5a", "#ffc93c", "#3ddc84", "#4da3ff", "#b48cff", "#ff8ad8", "#ffa63c", "#22c7a9"];
    const parts = [];
    for (let i = 0; i < 8; i++) {
      const seg = new THREE.Mesh(new THREE.CylinderGeometry(0.95, 0.95, 0.18, 12, 1, false, (i * Math.PI) / 4, Math.PI / 4), mat(colors[i], {}));
      seg.rotation.x = Math.PI / 2;
      parts.push(seg);
    }
    parts.push(torus(0.98, 0.1, Math.PI * 2, GOLD, shiny, [0, 0, 0]));
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2 + Math.PI / 8;
      parts.push(ball(0.06, "#fff6c8", glow("#ffd040", 0.6), [Math.cos(a) * 0.98, Math.sin(a) * 0.98, 0.1]));
    }
    parts.push(cyl(0.2, 0.2, 0.3, GOLD, shiny, [0, 0, 0.1], [90, 0, 0]));
    parts.push(place(new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.42, 4), mat("#ff4f6d", {})), [0, 1.12, 0.12], [0, 45, 180]));
    parts.push(box(0.2, 0.9, 0.2, 0.06, "#7d8a9b", steel, [0, -1.2, -0.1]));
    parts.push(box(0.9, 0.16, 0.5, 0.06, "#7d8a9b", steel, [0, -1.62, -0.1]));
    return { model: group(parts), yaw: -16, pitch: 4 };
  },

  book() {
    const parts = [
      box(1.5, 1.9, 0.5, 0.08, "#2f95f5", {}, [0, 0, 0]),
      box(1.38, 1.8, 0.38, 0.04, "#fff4dc", { coat: 0.2 }, [0.08, 0, 0]),
      box(1.5, 1.9, 0.08, 0.04, "#2f95f5", {}, [0, 0, 0.26]),
      box(0.16, 1.9, 0.58, 0.06, "#1c64b8", {}, [-0.72, 0, 0]),
      box(0.3, 0.3, 0.1, 0.04, GOLD, shiny, [0.62, 0.82, 0.31]),
      box(0.3, 0.3, 0.1, 0.04, GOLD, shiny, [0.62, -0.82, 0.31]),
      place(new THREE.Mesh(new THREE.OctahedronGeometry(0.34), mat("#7cf0ff", glow("#25b6e6", 0.5))), [0.05, 0.1, 0.36], [0, 0, 0]),
      box(0.16, 0.7, 0.04, 0.02, "#ff4f6d", {}, [0.35, -1.1, 0.12]),
    ];
    return { model: group(parts), yaw: -26, pitch: 8 };
  },

  trophy() {
    const cup = lathe([[0, -0.1], [0.3, -0.1], [0.55, 0.15], [0.72, 0.6], [0.78, 1.0], [0.7, 1.02], [0.64, 0.62], [0.0, 0.5]], GOLD, shiny);
    const parts = [
      cup,
      torus(0.3, 0.07, Math.PI, GOLD, shiny, [0.72, 0.55, 0], [0, 0, -90]),
      torus(0.3, 0.07, Math.PI, GOLD, shiny, [-0.72, 0.55, 0], [0, 0, 90]),
      cyl(0.12, 0.16, 0.45, GOLD_DARK, shiny, [0, -0.32, 0]),
      box(0.95, 0.3, 0.7, 0.08, "#8a5530", {}, [0, -0.7, 0]),
      box(0.5, 0.12, 0.05, 0.03, GOLD, shiny, [0, -0.7, 0.36]),
      extrude(starShape(0.24, 0.1), 0.06, 0.02, "#fff1a8", shiny, [0, 0.55, 0.62]),
    ];
    return { model: group(parts), yaw: -12, pitch: 10 };
  },

  helmet() {
    const dome = new THREE.Mesh(new THREE.SphereGeometry(0.85, 40, 20, 0, Math.PI * 2, 0, Math.PI / 2), mat("#ffc21a", {}));
    const parts = [
      dome,
      cyl(1.08, 1.08, 0.1, "#ffb000", {}, [0, 0.02, 0.1]),
      box(0.16, 0.5, 1.5, 0.06, "#ffd860", {}, [0, 0.6, 0]),
      cyl(0.26, 0.3, 0.3, "#5b6677", steel, [0, 0.5, 0.78], [80, 0, 0]),
      cyl(0.2, 0.2, 0.05, "#fff8c8", glow("#ffe060", 1.4), [0, 0.53, 0.94], [80, 0, 0]),
    ];
    return { model: group(parts), yaw: -26, pitch: 18 };
  },

  cog() {
    const s = new THREE.Shape();
    const teeth = 8;
    for (let i = 0; i < teeth * 4; i++) {
      const a = (i / (teeth * 4)) * Math.PI * 2;
      const r = i % 4 === 1 || i % 4 === 2 ? 1.0 : 0.76;
      if (i === 0) s.moveTo(Math.cos(a) * r, Math.sin(a) * r);
      else s.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    s.closePath();
    const hole = new THREE.Path();
    hole.absarc(0, 0, 0.32, 0, Math.PI * 2, true);
    s.holes.push(hole);
    return { model: group([extrude(s, 0.32, 0.06, "#aab6c8", steel)]), yaw: -18, pitch: 12 };
  },

  lock() {
    const parts = [
      box(1.3, 1.05, 0.55, 0.22, GOLD, shiny, [0, -0.35, 0]),
      torus(0.42, 0.13, Math.PI, "#b8c4d0", steel, [0, 0.18, 0]),
      cyl(0.13, 0.13, 0.28, "#b8c4d0", steel, [-0.42, 0.06, 0]),
      cyl(0.13, 0.13, 0.28, "#b8c4d0", steel, [0.42, 0.06, 0]),
      cyl(0.13, 0.13, 0.1, "#5b4a1a", {}, [0, -0.25, 0.28], [90, 0, 0]),
      box(0.1, 0.26, 0.08, 0.03, "#5b4a1a", {}, [0, -0.45, 0.29]),
    ];
    return { model: group(parts), yaw: -16, pitch: 8 };
  },

  boots() {
    const parts = [
      box(0.62, 1.1, 0.7, 0.2, "#e2453c", {}, [-0.1, 0.25, 0]),
      box(1.15, 0.5, 0.75, 0.22, "#e2453c", {}, [0.18, -0.3, 0.02]),
      box(1.2, 0.16, 0.8, 0.07, "#5b3a22", {}, [0.18, -0.6, 0.02]),
      box(0.68, 0.2, 0.76, 0.08, "#fff1d6", {}, [-0.1, 0.78, 0]),
      box(0.12, 0.12, 0.05, 0.03, GOLD, shiny, [-0.1, 0.35, 0.37]),
      box(0.12, 0.12, 0.05, 0.03, GOLD, shiny, [-0.1, 0.1, 0.37]),
      box(0.4, 0.3, 0.06, 0.05, "#c0303a", {}, [0.45, -0.25, 0.4]),
    ];
    return { model: group(parts), yaw: -30, pitch: 10 };
  },

  gloves() {
    const C = "#ff9f43";
    const parts = [
      box(0.95, 0.95, 0.42, 0.24, C, {}, [0, -0.1, 0]),
      box(1.05, 0.4, 0.5, 0.15, "#c96a1c", {}, [0, -0.72, 0]),
      ...[-0.33, -0.11, 0.11, 0.33].map((x, i) => box(0.2, 0.55 + (i === 1 || i === 2 ? 0.1 : 0), 0.36, 0.1, C, {}, [x, 0.55 + (i === 1 || i === 2 ? 0.05 : 0), 0])),
      box(0.22, 0.5, 0.34, 0.1, C, {}, [-0.6, 0.0, 0.05], [0, 0, 35]),
    ];
    return { model: group(parts), yaw: -14, pitch: 6 };
  },

  magnet() {
    const parts = [
      torus(0.55, 0.24, Math.PI, "#e2453c", {}, [0, 0.15, 0]),
      cyl(0.24, 0.24, 0.55, "#e2453c", {}, [-0.55, -0.12, 0]),
      cyl(0.24, 0.24, 0.55, "#4da3ff", {}, [0.55, -0.12, 0]),
      cyl(0.245, 0.245, 0.3, "#dfe6ee", steel, [-0.55, -0.55, 0]),
      cyl(0.245, 0.245, 0.3, "#dfe6ee", steel, [0.55, -0.55, 0]),
      extrude(starShape(0.16, 0.06, 4), 0.05, 0.02, "#fff1a8", glow("#ffd040", 0.5), [0.0, -0.75, 0.2]),
    ];
    return { model: group(parts), yaw: -10, pitch: 8, roll: 0 };
  },

  speaker() {
    const cone = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.7, 0.6, 32), mat("#5b6677", steel));
    cone.rotation.z = -Math.PI / 2;
    cone.position.set(-0.15, 0, 0);
    const parts = [
      box(0.5, 0.6, 0.6, 0.12, "#4a5568", steel, [-0.55, 0, 0]),
      cone,
      torus(0.45, 0.07, Math.PI / 1.6, "#4da3ff", {}, [0.25, 0, 0], [0, 0, -56]),
      torus(0.75, 0.07, Math.PI / 1.6, "#4da3ff", {}, [0.25, 0, 0], [0, 0, -56]),
    ];
    return { model: group(parts), yaw: -10, pitch: 6 };
  },

  music() {
    const parts = [
      ball(0.32, "#b48cff", {}, [-0.45, -0.6, 0], [0, 0, 20], 1.3, 1, 0.9),
      ball(0.32, "#b48cff", {}, [0.55, -0.4, 0], [0, 0, 20], 1.3, 1, 0.9),
      box(0.12, 1.3, 0.12, 0.05, "#8e5cf0", {}, [-0.1, 0.05, 0]),
      box(0.12, 1.3, 0.12, 0.05, "#8e5cf0", {}, [0.9, 0.25, 0]),
      box(1.1, 0.24, 0.14, 0.06, "#8e5cf0", {}, [0.4, 0.75, 0], [0, 0, 11]),
    ];
    return { model: group(parts), yaw: -12, pitch: 4 };
  },

  camera() {
    const parts = [
      box(1.6, 1.0, 0.7, 0.22, "#4a5568", {}, [0, 0, 0]),
      box(0.5, 0.22, 0.5, 0.08, "#4a5568", {}, [-0.45, 0.58, 0]),
      cyl(0.36, 0.4, 0.4, "#2d3748", steel, [0.05, -0.02, 0.45], [90, 0, 0]),
      cyl(0.26, 0.26, 0.05, "#7cc4ff", glow("#3a8fd0", 0.4), [0.05, -0.02, 0.66], [90, 0, 0]),
      box(0.22, 0.16, 0.06, 0.04, "#fff8c8", glow("#ffe060", 0.8), [0.55, 0.3, 0.36]),
    ];
    return { model: group(parts), yaw: -20, pitch: 10 };
  },

  gamepad() {
    const parts = [
      box(1.8, 0.75, 0.45, 0.3, "#4a5568", {}, [0, 0.1, 0]),
      ball(0.42, "#4a5568", {}, [-0.68, -0.25, 0], [0, 0, 0], 1, 1.1, 0.75),
      ball(0.42, "#4a5568", {}, [0.68, -0.25, 0], [0, 0, 0], 1, 1.1, 0.75),
      box(0.36, 0.11, 0.08, 0.03, "#dfe6ee", {}, [-0.55, 0.12, 0.24]),
      box(0.11, 0.36, 0.08, 0.03, "#dfe6ee", {}, [-0.55, 0.12, 0.24]),
      ball(0.08, "#3ddc84", {}, [0.55, 0.28, 0.22]),
      ball(0.08, "#ff5a5a", {}, [0.7, 0.13, 0.22]),
      ball(0.08, "#4da3ff", {}, [0.4, 0.13, 0.22]),
      ball(0.08, "#ffc93c", {}, [0.55, -0.02, 0.22]),
    ];
    return { model: group(parts), yaw: -14, pitch: 18 };
  },

  lift() {
    const tri = (up) => {
      const t = new THREE.Shape();
      t.moveTo(-0.22, 0);
      t.lineTo(0.22, 0);
      t.lineTo(0, up ? 0.26 : -0.26);
      t.closePath();
      return t;
    };
    const parts = [
      box(1.5, 1.9, 0.5, 0.18, "#5b6677", steel, [0, 0, -0.05]),
      box(1.2, 1.55, 0.2, 0.08, "#c9d3de", steel, [0, -0.1, 0.22]),
      box(0.04, 1.5, 0.05, 0.02, "#7d8a9b", steel, [0, -0.1, 0.33]),
      box(0.62, 0.4, 0.12, 0.08, "#2d3748", {}, [0, 0.93, 0.25]),
      extrude(tri(true), 0.05, 0.02, "#3ddc84", glow("#18a050", 0.6), [-0.14, 0.98, 0.32]),
      extrude(tri(false), 0.05, 0.02, "#ffc93c", glow("#d09000", 0.6), [0.14, 0.88, 0.32]),
      box(1.7, 0.16, 0.6, 0.06, "#ffc93c", {}, [0, -1.0, 0.0]),
    ];
    return { model: group(parts), yaw: -18, pitch: 8 };
  },

  // PREVIEW ONLY: a stand-in for Roblox's built-in Robux icon (never uploaded;
  // the game shows rbxasset://textures/ui/common/robux.png, see IconAssets).
  robux() {
    const hex = (r) => {
      const s = new THREE.Shape();
      for (let i = 0; i < 6; i++) {
        const a = Math.PI / 6 + (i * Math.PI) / 3;
        if (i === 0) s.moveTo(Math.cos(a) * r, Math.sin(a) * r);
        else s.lineTo(Math.cos(a) * r, Math.sin(a) * r);
      }
      s.closePath();
      return s;
    };
    const ring = hex(1);
    ring.holes.push(hex(0.62));
    const parts = [
      extrude(ring, 0.25, 0.05, "#e9eef2", { rough: 0.35 }),
      extrude(hex(0.3), 0.25, 0.05, "#e9eef2", { rough: 0.35 }),
    ];
    return { model: group(parts), yaw: 0, pitch: 0 };
  },

  vault() {
    const bolts = [];
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2 + Math.PI / 8;
      bolts.push(ball(0.07, GOLD, shiny, [Math.cos(a) * 0.8, Math.sin(a) * 0.8, 0.2]));
    }
    const spokes = [];
    for (let i = 0; i < 3; i++) {
      spokes.push(box(0.09, 1.06, 0.09, 0.04, GOLD, shiny, [0, 0, 0.36], [0, 0, i * 60]));
      for (const s of [-1, 1]) {
        const a = D(i * 60 + 90);
        spokes.push(ball(0.1, GOLD, shiny, [Math.cos(a) * 0.53 * s, Math.sin(a) * 0.53 * s, 0.36]));
      }
    }
    const parts = [
      box(2.3, 2.3, 0.34, 0.26, "#5b6677", steel, [0, 0, -0.1]),
      cyl(1.0, 1.0, 0.34, STEEL, steel, [0, 0, 0.08], [90, 0, 0]),
      torus(1.0, 0.11, Math.PI * 2, STEEL_DARK, steel, [0, 0, 0.22]),
      cyl(0.24, 0.24, 0.26, GOLD_DARK, shiny, [0, 0, 0.3], [90, 0, 0]),
      ...bolts,
      ...spokes,
    ];
    return { model: group(parts), yaw: -24, pitch: 8 };
  },

  // rebirth (proposal mock): a gold star inside two chasing arrows
  rebirth() {
    const parts = [extrude(starShape(0.6, 0.26), 0.26, 0.07, GOLD, glow("#ffb000", 0.25), [0, 0, 0.1])];
    for (const [start, color] of [[25, "#ff8a1f"], [205, "#6c74f5"]]) {
      parts.push(torus(1.02, 0.14, D(140), color, shiny, [0, 0, 0], [0, 0, start]));
      const end = start + 140;
      const a = D(end);
      parts.push(place(new THREE.Mesh(new THREE.ConeGeometry(0.3, 0.46, 24), mat(color, shiny)), [Math.cos(a) * 1.02, Math.sin(a) * 1.02, 0], [0, 0, end]));
    }
    parts.push(ball(0.08, "#fff6c8", glow("#ffd040", 0.8), [0.78, 0.92, 0.2]));
    parts.push(ball(0.06, "#fff6c8", glow("#ffd040", 0.8), [-0.95, -0.82, 0.2]));
    return { model: group(parts), yaw: -14, pitch: 6 };
  },

  // Forge Star (proposal mock): the rebirth token, an indigo coin with a gold star
  star_token() {
    const disc = lathe([[0, -0.14], [0.82, -0.14], [0.92, -0.07], [0.95, 0], [0.92, 0.07], [0.82, 0.14], [0, 0.14]], "#6c74f5", shiny, [0, 0, 0], [90, 0, 0]);
    const inner = cyl(0.7, 0.7, 0.05, "#8e95ff", shiny, [0, 0, 0.14], [90, 0, 0]);
    const star = extrude(starShape(0.56, 0.24), 0.12, 0.05, GOLD, glow("#ffb000", 0.3), [0, 0, 0.22]);
    const sparkles = [
      ball(0.08, "#fff6c8", glow("#ffd040", 0.9), [0.86, 0.8, 0.25]),
      ball(0.06, "#fff6c8", glow("#ffd040", 0.9), [-0.9, 0.62, 0.25]),
    ];
    return { model: group([disc, inner, star, ...sparkles]), yaw: -18, pitch: 8 };
  },

  // ---- Robux store cards

  // coin tier: short coin stacks of different heights, loose coins in front
  coin_pile() {
    const rnd = seeded(11);
    const stack = (n, x, z) =>
      Array.from({ length: n }, (_, i) =>
        goldCoin(0.5, [x + (rnd() - 0.5) * 0.07, i * 0.15, z + (rnd() - 0.5) * 0.07], [0, rnd() * 360, 0]),
      );
    const parts = [
      ...stack(6, -0.62, -0.3),
      ...stack(9, 0.1, -0.45),
      ...stack(4, 0.78, -0.08),
      ...stack(3, -0.2, 0.42),
      goldCoin(0.5, [0.7, 0.0, 1.0], [8, 0, 6]),
      goldCoin(0.5, [-0.92, 0.28, 0.5], [64, 0, -12]),
    ];
    return { model: group(parts), yaw: -18, pitch: 20 };
  },

  // coin tier: a plump cloth money sack tied with rope, star coin emblem
  coin_sack() {
    const SACK = "#f2672e";
    const ROPE = "#d99a52";
    const cloth = { rough: 0.55, coat: 0.35 };
    const body = lathe(
      [
        [0, -1.0], [0.45, -0.98], [0.82, -0.86], [1.0, -0.56], [1.04, -0.2], [0.96, 0.16], [0.74, 0.44],
        [0.44, 0.62], [0.3, 0.7], [0.33, 0.8], [0.5, 0.94], [0.64, 1.06], [0.56, 1.12], [0.3, 1.04], [0, 1.02],
      ],
      SACK, cloth, [0, 0, 0], [0, 180, 0],
    );
    // gathered pleats toward the neck and a wavy cloth top
    const p = body.geometry.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const k = 1 + 0.1 * Math.min(1, Math.max(0, (y - 0.1) / 0.6)) * Math.sin(Math.atan2(x, z) * 8);
      p.setXYZ(i, x * k, y, z * k);
    }
    body.geometry.computeVertexNormals();
    const parts = [
      body,
      torus(0.35, 0.085, Math.PI * 2, ROPE, {}, [0, 0.72, 0], [90, 0, 0]),
      ball(0.13, ROPE, {}, [0.1, 0.7, 0.36]),
      cyl(0.06, 0.06, 0.36, ROPE, {}, [0.2, 0.52, 0.4], [0, 0, 28]),
      cyl(0.06, 0.06, 0.3, ROPE, {}, [0.0, 0.53, 0.42], [0, 0, -18]),
      group([goldCoin(0.38, [0, -0.18, 1.03], [78, 0, 0])], [0, 0, 0], [0, 18, 0]),
      goldCoin(0.36, [0.85, -0.94, 0.7], [0, 20, 0]),
      goldCoin(0.36, [0.42, -0.9, 1.05], [10, 0, -8]),
      goldCoin(0.36, [-0.88, -0.66, 0.66], [66, 0, -18]),
    ];
    return { model: group(parts), yaw: -18, pitch: 12 };
  },

  // top coin tier: an open treasure chest overflowing with glowing gold coins
  coin_chest() {
    const WOOD = "#a0582a";
    const WOOD_IN = "#6b3418";
    const wood = { rough: 0.55, coat: 0.35 };
    const W = 2.0, H = 0.95, DP = 1.3, TOP = H / 2;
    const half = new THREE.Shape();
    half.absarc(0, 0, DP / 2, 0, Math.PI, false);
    half.closePath();
    // lid built closed around the hinge (back top edge), then swung open
    const lid = group(
      [
        extrude(half, W - 0.08, 0.04, WOOD, wood, [0, DP / 4, DP / 2], [0, 90, 0]),
        box(W - 0.16, 0.04, DP - 0.16, 0.02, WOOD_IN, wood, [0, -0.02, DP / 2]),
        box(W + 0.05, 0.12, 0.14, 0.05, GOLD, shiny, [0, 0.02, DP - 0.05]),
        ...[-0.62, 0.62].map((x) => torus(DP / 2 + 0.01, 0.06, Math.PI, GOLD, shiny, [x, 0, DP / 2], [0, 90, 0])),
        ...[-0.98, 0.98].map((x) => torus(DP / 2 + 0.01, 0.06, Math.PI, GOLD, shiny, [x, 0, DP / 2], [0, 90, 0])),
      ],
      [0, TOP, -DP / 2],
      [-112, 0, 0],
    );
    // heaped coins: a glowing gold dome covered in coins that follow its slope
    const rnd = seeded(5);
    const pile = [];
    for (let i = 0; i < 20; i++) {
      const x = (rnd() - 0.5) * 1.7, z = (rnd() - 0.5) * 1.0;
      const h = Math.max(0.3, Math.sqrt(Math.max(0, 1 - (x / 0.9) ** 2 - (z / 0.55) ** 2)));
      pile.push(goldCoin(0.32, [x, TOP + 0.6 * h, z], [(z / 0.55) * 35 + (rnd() - 0.5) * 30, rnd() * 360, -(x / 0.9) * 35 + (rnd() - 0.5) * 30]));
    }
    pile.push(goldCoin(0.34, [-0.3, TOP + 0.66, 0.2], [62, 0, 12]), goldCoin(0.34, [0.38, TOP + 0.6, 0.22], [68, 0, -10]));
    const parts = [
      box(W, H, DP, 0.08, WOOD, wood, [0, 0, 0]),
      box(W + 0.05, 0.14, DP + 0.05, 0.05, GOLD, shiny, [0, TOP - 0.07, 0]),
      box(W + 0.05, 0.12, DP + 0.05, 0.05, GOLD, shiny, [0, -TOP + 0.06, 0]),
      ...[-0.62, 0.62].map((x) => box(0.18, H + 0.04, DP + 0.05, 0.05, GOLD, shiny, [x, 0, 0])),
      box(0.38, 0.44, 0.1, 0.06, GOLD, shiny, [0, 0.08, DP / 2 + 0.03]),
      cyl(0.07, 0.07, 0.04, "#5b3a1a", {}, [0, 0.13, DP / 2 + 0.08], [90, 0, 0]),
      box(0.06, 0.14, 0.04, 0.02, "#5b3a1a", {}, [0, 0.03, DP / 2 + 0.08]),
      lid,
      box(W - 0.14, 0.36, DP - 0.14, 0.16, GOLD, glow("#ffb000", 0.35), [0, TOP, 0]),
      ball(1, GOLD, glow("#ffb000", 0.35), [0, TOP, 0], [0, 0, 0], 0.9, 0.58, 0.55),
      ...pile,
      goldCoin(0.3, [0.98, TOP + 0.02, DP / 2 + 0.08], [60, 0, 14]),
      goldCoin(0.3, [1.25, -TOP + 0.05, 0.75], [0, 30, 0]),
      goldCoin(0.3, [-1.22, -TOP + 0.28, 0.58], [70, 0, -16]),
      sparkle(0.2, [-0.7, TOP + 0.75, 0.3]),
      sparkle(0.14, [0.8, TOP + 0.62, 0.4]),
    ];
    return { model: group(parts), yaw: -22, pitch: 16 };
  },

  // Shop button: a shopping cart (wire basket, black wheels, red grip), side-front view
  cart() {
    const WIRE = "#f2f5f9";
    const PANEL = "#b8c6d8";
    const wire = { metal: 0.3, rough: 0.3, coat: 0.7 };
    const v = (x, y, z) => new THREE.Vector3(x, y, z);
    const rod = (a, b, r, color = WIRE, o = wire) => {
      const d = new THREE.Vector3().subVectors(b, a);
      const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, d.length(), 16), mat(color, o));
      m.position.copy(a).addScaledVector(d, 0.5);
      m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
      return m;
    };
    const lerp = (a, b, t) => a.clone().lerp(b, t);
    // a wire panel a-b (top edge) / d-c (bottom edge) with an nu x nv grid
    const panel = (a, b, c, d, nu, nv) => {
      const g = new THREE.BufferGeometry().setFromPoints([a, b, c, a, c, d]);
      g.computeVertexNormals();
      const m = mat(PANEL, { rough: 0.5 });
      m.side = THREE.DoubleSide;
      const parts = [new THREE.Mesh(g, m)];
      for (let i = 1; i < nu; i++) parts.push(rod(lerp(a, b, i / nu), lerp(d, c, i / nu), 0.024));
      for (let j = 1; j < nv; j++) parts.push(rod(lerp(a, d, j / nv), lerp(b, c, j / nv), 0.024));
      return parts;
    };
    const TBL = v(-0.95, 0.55, -0.6), TBR = v(-0.95, 0.55, 0.6), TFL = v(1.05, 0.55, -0.6), TFR = v(1.05, 0.55, 0.6);
    const BBL = v(-0.75, -0.3, -0.48), BBR = v(-0.75, -0.3, 0.48), BFL = v(0.75, -0.3, -0.48), BFR = v(0.75, -0.3, 0.48);
    const HL = v(-1.32, 0.86, -0.6), HR = v(-1.32, 0.86, 0.6);
    const parts = [
      ...panel(TBR, TFR, BFR, BBR, 7, 4),
      ...panel(TBL, TFL, BFL, BBL, 7, 4),
      ...panel(TFR, TFL, BFL, BFR, 5, 4),
      ...panel(TBL, TBR, BBR, BBL, 5, 4),
      ...panel(BBR, BFR, BFL, BBL, 6, 4),
      ...[[TBL, TFL], [TFL, TFR], [TFR, TBR], [TBR, TBL]].map(([a, b]) => rod(a, b, 0.055)),
      ...[[BBL, BFL], [BFL, BFR], [BFR, BBR], [BBR, BBL]].map(([a, b]) => rod(a, b, 0.04)),
      ...[[TBL, BBL], [TBR, BBR], [TFL, BFL], [TFR, BFR]].map(([a, b]) => rod(a, b, 0.04)),
      rod(TBL, HL, 0.05),
      rod(TBR, HR, 0.05),
      rod(v(-1.32, 0.86, -0.68), v(-1.32, 0.86, 0.68), 0.085, "#ff4f5a", shiny),
    ];
    for (const z of [-0.45, 0.45]) {
      parts.push(rod(v(-0.95, 0.5, z), v(-0.92, -0.62, z), 0.045));
      parts.push(rod(v(0.75, -0.3, z), v(0.8, -0.62, z), 0.04));
      parts.push(rod(v(-1.0, -0.62, z), v(0.86, -0.62, z), 0.045));
      for (const x of [-0.86, 0.76]) {
        parts.push(cyl(0.17, 0.17, 0.13, "#2d3142", { rough: 0.6 }, [x, -0.84, z], [90, 0, 0]));
        parts.push(cyl(0.07, 0.07, 0.15, STEEL, steel, [x, -0.84, z], [90, 0, 0]));
        parts.push(rod(v(x, -0.62, z), v(x, -0.84, z), 0.035));
      }
    }
    return { model: group(parts), yaw: -28, pitch: 14 };
  },

  // hoverboard (mine floors pass): a rounded deck with cyan underglow and thrusters
  hoverboard() {
    const stadium = (len, w) => {
      const s = new THREE.Shape();
      const h = len / 2 - w / 2;
      s.absarc(h, 0, w / 2, -Math.PI / 2, Math.PI / 2, false);
      s.absarc(-h, 0, w / 2, Math.PI / 2, Math.PI * 1.5, false);
      s.closePath();
      return s;
    };
    const flat = [90, 0, 0];
    const NEON = "#bff8ff";
    const neon = glow(GLOW_CYAN, 2);
    const parts = [
      extrude(stadium(2.5, 0.84), 0.06, 0.05, "#2d3748", {}, [0, -0.1, 0], flat),
      extrude(stadium(2.6, 0.94), 0.05, 0.02, NEON, neon, [0, -0.02, 0], flat),
      extrude(stadium(2.5, 0.84), 0.06, 0.06, "#7b61ff", shiny, [0, 0.07, 0], flat),
      extrude(stadium(1.9, 0.56), 0.02, 0.02, "#4b3bb0", { rough: 0.7, coat: 0.2 }, [0, 0.165, 0], flat),
      extrude(stadium(1.6, 0.1), 0.02, 0.015, NEON, neon, [0, 0.19, 0], flat),
    ];
    // thrusters with a hover ring under each
    for (const x of [-0.7, 0.7]) {
      parts.push(cyl(0.22, 0.17, 0.14, "#5b6677", steel, [x, -0.2, 0]));
      parts.push(cyl(0.15, 0.15, 0.04, NEON, neon, [x, -0.28, 0]));
      parts.push(torus(0.26, 0.045, Math.PI * 2, NEON, neon, [x, -0.52, 0], [90, 0, 0]));
    }
    return { model: group(parts, [0, 0, 0], [14, 0, 20]), yaw: -18, pitch: 16 };
  },

  // Forgemaster's Pass (VIP bundle): a big gold crown with red and blue gems
  pass_crown() {
    const R = 0.95;
    const RED = "#ff3b5c";
    const BLUE = "#3f8cff";
    const spike = new THREE.Shape();
    spike.moveTo(-0.36, 0);
    spike.quadraticCurveTo(-0.08, 0.22, 0, 0.72);
    spike.quadraticCurveTo(0.08, 0.22, 0.36, 0);
    spike.closePath();
    const parts = [
      lathe([[R - 0.08, -0.42], [R + 0.06, -0.42], [R + 0.06, 0.2], [R - 0.08, 0.2]], GOLD, shiny),
      torus(R + 0.05, 0.09, Math.PI * 2, GOLD, shiny, [0, -0.42, 0], [90, 0, 0]),
      torus(R + 0.03, 0.07, Math.PI * 2, GOLD, shiny, [0, 0.2, 0], [90, 0, 0]),
      ball(R - 0.06, "#c8243f", { rough: 0.6, coat: 0.3 }, [0, 0.1, 0], [0, 0, 0], 1, 0.62, 1),
    ];
    for (let i = 0; i < 8; i++) {
      const a = i * 45;
      const gem = i === 0 ? 0.17 : i % 2 ? 0.1 : 0.13;
      parts.push(
        group([
          extrude(spike, 0.08, 0.06, GOLD, shiny, [0, 0.55, R], [10, 0, 0]),
          ball(0.11, GOLD, shiny, [0, 0.98, R + 0.08]),
          ball(gem, i % 2 ? BLUE : RED, glow(i % 2 ? "#1a5fd0" : "#c01838", 0.35), [0, -0.12, R + 0.08], [0, 0, 0], 1, 1.15, 0.55),
          torus(gem, 0.035, Math.PI * 2, GOLD_DARK, shiny, [0, -0.12, R + 0.06], [0, 0, 0]),
        ], [0, 0, 0], [0, a, 0]),
      );
    }
    parts.push(sparkle(0.22, [1.05, 1.0, 0.5]));
    parts.push(sparkle(0.14, [-1.15, 0.65, 0.5]));
    return { model: group(parts), yaw: 0, pitch: 16 };
  },

  // Luck server (Robux): a four-leaf clover with a gold "2x" badge and sparkles
  luck_server() {
    // half a heart leaf (tip at the origin, midrib on +Y), folded back along the midrib
    const halfLeaf = (side) => {
      const s = new THREE.Shape();
      s.moveTo(0, 0);
      s.bezierCurveTo(0.2 * side, 0.2, 0.58 * side, 0.38, 0.52 * side, 0.7);
      s.bezierCurveTo(0.46 * side, 1.0, 0.08 * side, 1.02, 0, 0.76);
      s.closePath();
      const g = new THREE.ExtrudeGeometry(s, { depth: 0.08, bevelEnabled: true, bevelThickness: 0.08, bevelSize: 0.06, bevelSegments: 5, curveSegments: 32 });
      g.translate(0, 0, -0.04);
      return place(new THREE.Mesh(g, mat("#3ddc84")), [0, 0, 0], [0, side * 12, 0]);
    };
    const parts = [];
    for (const a of [30, 120, 210, 300]) {
      const leaf = group([halfLeaf(1), halfLeaf(-1)], [Math.cos(D(a)) * 0.24, Math.sin(D(a)) * 0.24, 0], [0, 0, a - 90]);
      leaf.scale.set(0.9, 1, 1);
      parts.push(leaf);
    }
    parts.push(torus(1.2, 0.085, D(55), "#25a85a", {}, [0.96, -0.9, -0.1], [0, 0, 143]));
    parts.push(ball(0.2, "#9df2b8", {}, [0, 0, 0.08]));
    const g = new TextGeometry("2x", { font: FONT, size: 0.36, depth: 0.08, curveSegments: 8, bevelEnabled: true, bevelThickness: 0.02, bevelSize: 0.015, bevelSegments: 3 });
    g.center();
    parts.push(
      group([
        lathe([[0, -0.1], [0.4, -0.1], [0.46, -0.05], [0.48, 0], [0.46, 0.05], [0.4, 0.1], [0, 0.1]], GOLD, shiny, [0, 0, 0], [90, 0, 0]),
        cyl(0.36, 0.36, 0.04, "#f59a1c", shiny, [0, 0, 0.1], [90, 0, 0]),
        place(new THREE.Mesh(g, mat("#ffffff", { coat: 0.9 })), [0, 0, 0.16]),
      ], [0.72, -0.72, 0.3]),
    );
    parts.push(sparkle(0.22, [-0.95, 0.85, 0.2]));
    parts.push(sparkle(0.15, [0.95, 0.75, 0.2]));
    return { model: group(parts), yaw: -14, pitch: 8 };
  },
};

// ---------------------------------------------------------------- part models (exported from the game)
const SHAPE_BLOCK = 0, SHAPE_BALL = 1, SHAPE_CYLINDER = 2, SHAPE_WEDGE = 3;
function wedgeGeometry() {
  const B0 = [-0.5, -0.5, -0.5], B1 = [0.5, -0.5, -0.5], B2 = [0.5, -0.5, 0.5], B3 = [-0.5, -0.5, 0.5];
  const T2 = [0.5, 0.5, 0.5], T3 = [-0.5, 0.5, 0.5];
  const tris = [[B0, B1, B2], [B0, B2, B3], [B3, B2, T2], [B3, T2, T3], [B0, T3, T2], [B0, T2, B1], [B0, B3, T3], [B1, T2, B2]];
  const pos = [];
  for (const t of tris) for (const v of t) pos.push(...v);
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}
const partGeo = {
  [SHAPE_BLOCK]: new THREE.BoxGeometry(1, 1, 1),
  [SHAPE_BALL]: new THREE.SphereGeometry(0.5, 32, 20),
  [SHAPE_CYLINDER]: new THREE.CylinderGeometry(0.5, 0.5, 1, 32).rotateZ(-Math.PI / 2),
  [SHAPE_WEDGE]: wedgeGeometry(),
};

async function partsModel(file, view) {
  const data = await fetch(`/scenes/icon_parts/${file}.json`).then((r) => r.json());
  const g = new THREE.Group();
  const m4 = new THREE.Matrix4();
  for (const p of data.parts || []) {
    const [shape, sx, sy, sz, cf, color, material, transparency] = p;
    if (transparency > 0.95 || Math.min(sx, sy, sz) < 1e-4) continue;
    const neon = material === "Neon";
    const metal = material === "Metal" || material === "DiamondPlate" || material === "Foil";
    const c = "#" + color;
    const m = neon
      ? new THREE.MeshBasicMaterial({ color: new THREE.Color(c), toneMapped: false })
      : mat(c, metal ? steel : { rough: 0.5, coat: 0.35 });
    if (transparency > 0.01) {
      m.transparent = true;
      m.opacity = 1 - transparency;
    }
    const mesh = new THREE.Mesh(partGeo[shape], m);
    const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
    m4.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
    mesh.applyMatrix4(m4.clone().multiply(new THREE.Matrix4().makeScale(sx, sy, sz)));
    g.add(mesh);
  }
  const center = new THREE.Box3().setFromObject(g).getCenter(new THREE.Vector3());
  g.position.sub(center);
  const outer = new THREE.Group();
  outer.add(g);
  return { model: outer, yaw: view.yaw ?? 0, pitch: view.pitch ?? 0, roll: view.roll ?? 0 };
}

const PART_ICONS = {
  blaster: { file: "blaster", yaw: 90, pitch: 12, roll: 0 },
  blaster_copper: { file: "blaster_copper", yaw: 90, pitch: 12, roll: 0 },
  ore_raw: { file: "ore_raw", yaw: -20, pitch: 22 },
  ore_copper: { file: "ore_copper", yaw: -20, pitch: 22 },
  ore_silver: { file: "ore_silver", yaw: -20, pitch: 22 },
  ingot_gold: { file: "ingot_gold", yaw: -30, pitch: 28 },
  train: { file: "train", yaw: 125, pitch: 14 },
};

window.ICON_NAMES = [...Object.keys(ICONS), ...Object.keys(PART_ICONS), ...Object.keys(RUNES)];

// ---------------------------------------------------------------- render
function outlined(src, size) {
  // crop to the drawn pixels
  const w = src.width, h = src.height;
  const ctx = src.getContext("2d");
  const data = ctx.getImageData(0, 0, w, h).data;
  let x0 = w, y0 = h, x1 = 0, y1 = 0;
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++)
      if (data[(y * w + x) * 4 + 3] > 8) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
  const bw = x1 - x0 + 1, bh = y1 - y0 + 1;
  const stroke = Math.round(size * 0.034);
  const room = size - 2 * (stroke + Math.round(size * 0.02));
  const k = room / Math.max(bw, bh);
  const dw = bw * k, dh = bh * k;
  const dx = (size - dw) / 2, dy = (size - dh) / 2;

  const icon = document.createElement("canvas");
  icon.width = icon.height = size;
  const ic = icon.getContext("2d");
  ic.imageSmoothingQuality = "high";
  ic.drawImage(src, x0, y0, bw, bh, dx, dy, dw, dh);

  const sil = document.createElement("canvas");
  sil.width = sil.height = size;
  const sc = sil.getContext("2d");
  sc.drawImage(icon, 0, 0);
  sc.globalCompositeOperation = "source-in";
  sc.fillStyle = OUTLINE;
  sc.fillRect(0, 0, size, size);

  const out = document.createElement("canvas");
  out.width = out.height = size;
  const oc = out.getContext("2d");
  for (const r of [stroke, stroke * 0.7, stroke * 0.4]) {
    for (let i = 0; i < 48; i++) {
      const a = (i / 48) * Math.PI * 2;
      oc.drawImage(sil, Math.cos(a) * r, Math.sin(a) * r);
    }
  }
  oc.drawImage(icon, 0, 0);
  return out;
}

async function main() {
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setPixelRatio(1);
  renderer.setSize(RENDER, RENDER);
  renderer.setClearColor(0x000000, 0);
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = 1.05;
  document.body.appendChild(renderer.domElement);

  if (RUNES[iconName] || TEXT_ICONS.includes(iconName)) FONT = await new FontLoader().loadAsync("/node_modules/three/examples/fonts/helvetiker_bold.typeface.json");
  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.55;
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8a96b8, 0.9));
  const key = new THREE.DirectionalLight(0xffffff, 2.3);
  key.position.set(-2, 3, 3);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xd6e4ff, 0.7);
  fill.position.set(3, 0.5, 2);
  scene.add(fill);
  const rim = new THREE.DirectionalLight(0xffffff, 1.6);
  rim.position.set(1, 2, -3);
  scene.add(rim);

  // golem_<Kind> / capsule_<Id>: the step 7 GolemBuilder models (front = -Z, turned to the camera)
  if (RUNES[iconName]) {
    const [mark, hex] = RUNES[iconName];
    ICONS[iconName] = () => {
      const c = "#" + hex;
      const gem = new THREE.Shape();
      for (let i = 0; i < 6; i++) {
        const a = Math.PI / 6 + (i * Math.PI) / 3;
        if (i === 0) gem.moveTo(Math.cos(a), Math.sin(a));
        else gem.lineTo(Math.cos(a), Math.sin(a));
      }
      gem.closePath();
      const parts = [extrude(gem, 0.35, 0.12, c, { coat: 0.9, rough: 0.25 })];
      if (mark === "Star") {
        parts.push(extrude(starShape(0.55, 0.24), 0.14, 0.04, "#fff6d8", { coat: 0.9 }, [0, 0, 0.3]));
      } else {
        const g = new TextGeometry(mark, { font: FONT, size: 0.95, depth: 0.14, curveSegments: 8, bevelEnabled: true, bevelThickness: 0.03, bevelSize: 0.02, bevelSegments: 3 });
        g.center();
        parts.push(place(new THREE.Mesh(g, mat("#fff6d8", { coat: 0.9 })), [0, 0, 0.32]));
      }
      return { model: group(parts), yaw: -14, pitch: 8 };
    };
  }
  const partSpec =
    PART_ICONS[iconName] ||
    (/^(golem|capsule)_/.test(iconName) ? { file: iconName, yaw: 158, pitch: 10 } : null) ||
    (/^item_/.test(iconName) ? { file: iconName, yaw: -24, pitch: 24 } : null) ||
    (/^machine_/.test(iconName) ? { file: iconName, yaw: 145, pitch: 20 } : null) ||
    (/^hopper_/.test(iconName) ? { file: iconName, yaw: -28, pitch: 14 } : null) ||
    (/^star_/.test(iconName) ? { file: iconName, yaw: 90, pitch: 12, roll: 0 } : null) ||
    (/^artifact_/.test(iconName) ? { file: iconName, yaw: 160, pitch: 16 } : null);
  if (!ICONS[iconName] && !partSpec) throw new Error("unknown icon " + iconName);
  const spec = ICONS[iconName] ? ICONS[iconName]() : await partsModel(partSpec.file, partSpec);
  const holder = new THREE.Group();
  holder.add(spec.model);
  holder.rotation.set(D(spec.pitch ?? 0), D(spec.yaw ?? 0), D(spec.roll ?? 0), "XYZ");
  scene.add(holder);

  const bounds = new THREE.Box3().setFromObject(holder);
  const center = bounds.getCenter(new THREE.Vector3());
  const radius = bounds.getSize(new THREE.Vector3()).length() / 2;
  const fov = 24;
  const camera = new THREE.PerspectiveCamera(fov, 1, 0.1, 100);
  const dist = radius / Math.sin(D(fov / 2)) * 1.05;
  camera.position.set(center.x, center.y, center.z + dist);
  camera.lookAt(center);

  renderer.render(scene, camera);
  const src = document.createElement("canvas");
  src.width = src.height = RENDER;
  src.getContext("2d").drawImage(renderer.domElement, 0, 0);
  const out = outlined(src, SIZE);
  window.__png = out.toDataURL("image/png");
  out.style.background = "#7a8db0";
  document.body.appendChild(out);
  window.__done = true;
}

main().catch((e) => {
  console.error(e);
  window.__error = String(e && e.stack ? e.stack : e);
});
