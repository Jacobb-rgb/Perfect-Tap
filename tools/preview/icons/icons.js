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

window.ICON_NAMES = [...Object.keys(ICONS), ...Object.keys(PART_ICONS)];

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
  const partSpec =
    PART_ICONS[iconName] ||
    (/^(golem|capsule)_/.test(iconName) ? { file: iconName, yaw: 158, pitch: 10 } : null) ||
    (/^item_/.test(iconName) ? { file: iconName, yaw: -24, pitch: 24 } : null);
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
