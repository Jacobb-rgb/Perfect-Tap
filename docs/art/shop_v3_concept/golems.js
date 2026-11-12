// Terra Forge shop golems and eggs, drawn in code (SVG) as chunky stickers in the style of the
// shop's icons (icons.js; owner 2026-11-11 picked B: "make B, just do it with the skins that are
// in the game"). Every drawing is the game's own golem: its GolemConfig colours and the costume
// its builder puts on it (Builders/EggGear/Royal, Builders/LimitedGear/Dragonforge), the eggs
// from Builders/CapsuleEggs and the Dragonforge shard. A thick dark outline, flat colour with a
// hard light/shade step (radial "cel" gradients), white shine marks and a darker drop under
// everything. Every sticker is drawn in a 128 x 128 box (feet at y 123) and shown in a square
// viewBox round it (BOX, room for wings, outlines and the drop). icon(name, size) returns an
// <svg> string; names are the shop's picture names (golem_<Kind>, capsule_<Id>).
// Nothing here is copied from anywhere: the shapes are our own.

(function () {
  const O = "#221a3d"; // the outline colour (icons.js)
  // [lit, shade] pairs: the cel gradients (a hard step, the shade a crescent bottom-right)
  const PAL = {
    gold: ["#ffd95a", "#eb9a1e"],
    goldDeep: ["#f2b23a", "#c47a14"],
    paleGold: ["#fff0a8", "#f2c95a"],
    pearl: ["#fffaf0", "#ddd3c0"],
    white: ["#ffffff", "#dfe3f2"],
    blade: ["#f4f7ff", "#b3bfd8"],
    // the Silver Squire (Silver: 172 184 216, its helm lighter)
    silverHelm: ["#d3dcf2", "#99a6c8"],
    silver: ["#bdc8e6", "#8794b8"],
    silverSuit: ["#6d7488", "#4b5064"],
    plume: ["#ff5c62", "#c8283a"],
    // the Rose Knight (CrystalRose: 250 64 142)
    roseHelm: ["#ff5ea2", "#d02e78"],
    rose: ["#f24a92", "#c22a6c"],
    roseSuit: ["#8a1e48", "#5e1232"],
    roseGlow: ["#ffb3d8", "#ff7cbc"],
    // the Moonstone Oracle (Moonstone: 168 196 240)
    moonHelm: ["#c6d8f8", "#90a8d8"],
    moon: ["#b4caf0", "#839cd0"],
    moonSuit: ["#5e6c8c", "#414c68"],
    moonCap: ["#566484", "#3a4562"],
    moonGlow: ["#e4eeff", "#b6cbf4"],
    // the Storm Titan (StormGem: 42 112 255)
    stormHelm: ["#4f8bff", "#2458e0"],
    storm: ["#3f7cff", "#1f4fd0"],
    stormSuit: ["#1c3c9a", "#122a70"],
    stormCap: ["#24489e", "#173274"],
    stormGlow: ["#a8dcff", "#62b6ff"],
    bolt: ["#fff59a", "#ffd23c"],
    // the Celestial Sovereign (CelestialCore: 62 72 232)
    celestHelm: ["#5a64f2", "#363cc8"],
    celest: ["#4c56ea", "#2e34bc"],
    celestSuit: ["#232884", "#171a5e"],
    celestCap: ["#262c92", "#191d66"],
    celestGlow: ["#c4ceff", "#8e9cff"],
    star: ["#fff6c4", "#ffd96a"],
    // the Gilded Porter (deep gold plates, velvet)
    porter: ["#f0b43c", "#c48420"],
    porterSuit: ["#8a5a14", "#634010"],
    velvet: ["#c8304e", "#8e1a34"],
    lamp: ["#fff6c8", "#ffd96a"],
    // Dragonforge
    ivory: ["#fbf0d8", "#d2bb92"],
    basalt: ["#625a64", "#433b46"],
    basaltDark: ["#3e3540", "#2a222c"],
    whelpMuzzle: ["#7a727c", "#57505a"],
    whelpWing: ["#d0823a", "#a05a26"],
    whelpWingDark: ["#a8622a", "#7c4419"],
    tan: ["#d0a080", "#a8785a"],
    hatch: ["#d8482e", "#a82c1e"],
    hatchDark: ["#9c2a1c", "#701a12"],
    shell: ["#fff6e2", "#e6d2a8"],
    spot: ["#ff9a4a", "#e2621e"],
    scaleHelm: ["#c22a36", "#8c1624"],
    scaleDark: ["#8a1824", "#5e0e18"],
    scaleBody: ["#3c3444", "#28212e"],
    cape: ["#b81e36", "#7e0f22"],
    flame: ["#ffb03a", "#ff6a1a"],
    flameHot: ["#ffe98a", "#ffc23a"],
    ember: ["#ff5a3a", "#cf2a1e"],
    flameRed: ["#e84a40", "#b52c2a"],
    flameDark: ["#a83030", "#7a1c22"],
    belly: ["#ffe2b8", "#f0b880"],
    leather: ["#7a3a2a", "#52241a"],
    lens: ["#a8f0ff", "#4cc6f0"],
    obsidian: ["#3c2e38", "#231a22"],
    obsidianDark: ["#2a2028", "#170f16"],
    lava: ["#ffa23a", "#ff5a14"],
    wingDark: ["#6e2026", "#46121a"],
    kingBody: ["#3e2a3a", "#261824"],
    kingGold: ["#ffd24a", "#e0901c"],
    kingRed: ["#d82a40", "#9a1226"],
    kingRed2: ["#a8182e", "#760c20"],
    kingRed3: ["#7c1022", "#560818"],
    gemRed: ["#ff5a78", "#d81e44"],
    ermine: ["#ffffff", "#e2dcd2"],
    // the eggs
    eggPearl: ["#fffdf6", "#e8dcc4"],
    eggGold: ["#ffd24a", "#e89a1c"],
    cloud: ["#ffffff", "#d8e0f0"],
    iris: ["#ff5a7c", "#e01e4a"],
    dragonShell: ["#8a2230", "#5a1420"],
    dragonLow: ["#5a1c26", "#3a1018"],
    dragonScale: ["#b42a2c", "#801a20"],
    rock: ["#4e3c48", "#2e222c"],
  };

  // the shared <defs>: put once in the page (GOLEMS.defs()); ids start "gc-" (icons.js uses "cel-")
  function defs() {
    let s = "";
    for (const [k, [a, b]] of Object.entries(PAL)) {
      s += `<radialGradient id="gc-${k}" cx="0.36" cy="0.3" r="0.82"><stop offset="0.7" stop-color="${a}"/><stop offset="0.7" stop-color="${b}"/></radialGradient>`;
      s += `<linearGradient id="gl-${k}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;
    }
    return `<svg width="0" height="0" style="position:absolute"><defs>${s}</defs></svg>`;
  }

  const C = (k) => `url(#gc-${k})`; // a cel fill
  const L = (k) => `url(#gl-${k})`; // a light-to-shade fill, top to bottom
  const SW = 5; // the outline (paint-order stroke: half of it shows outside a shape)
  // The silhouette pass: icon() draws every sticker twice, first with HALO on (each outlined
  // shape in the outline colour, its outline HW wider; no marks or shines), under the picture
  // and again a little lower (the drop): a bold even edge round the whole golem like the shop's
  // icons, while the lines inside stay thin enough for the small details.
  let HALO = false;
  const HW = 5;
  const hs = (sw) => (HALO ? sw + HW : sw);
  const hf = (fill) => (HALO ? O : fill);

  // a path with the outline
  const P = (d, fill, sw = SW, extra = "") =>
    `<path d="${d}" fill="${hf(fill)}" stroke="${O}" stroke-width="${hs(sw)}" stroke-linejoin="round" stroke-linecap="round" paint-order="stroke" ${extra}/>`;
  // a rounded box
  const R = (x, y, w, h, r, fill, sw = SW, extra = "") =>
    `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${hf(fill)}" stroke="${O}" stroke-width="${hs(sw)}" paint-order="stroke" ${extra}/>`;
  // an ellipse
  const E = (cx, cy, rx, ry, fill, sw = SW, extra = "") =>
    `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${hf(fill)}" stroke="${O}" stroke-width="${hs(sw)}" paint-order="stroke" ${extra}/>`;
  // a flat mark with no outline (inside a shape: the silhouette pass skips it)
  const F = (d, fill, extra = "") => (HALO ? "" : `<path d="${d}" fill="${fill}" ${extra}/>`);
  const shine = (x, y, w = 6, h = 3, r = -30, o = 0.9) =>
    HALO ? "" : `<ellipse cx="${x}" cy="${y}" rx="${w}" ry="${h}" fill="#fff" opacity="${o}" transform="rotate(${r} ${x} ${y})"/>`;
  const dot = (x, y, r = 2, o = 0.9) => (HALO ? "" : `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff" opacity="${o}"/>`);
  // a stroke with an outline (a staff, a strap, a halo)
  const line = (d, w, col, ow = 5) =>
    `<path d="${d}" fill="none" stroke="${O}" stroke-width="${hs(w + ow)}" stroke-linecap="round" stroke-linejoin="round"/>` +
    (HALO ? "" : `<path d="${d}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`);
  // a diamond (a square turned 45 degrees) round (cx, cy)
  const dia = (cx, cy, w, h, fill, sw = 4) => P(`M${cx} ${cy - h / 2} L${cx + w / 2} ${cy} L${cx} ${cy + h / 2} L${cx - w / 2} ${cy} Z`, fill, sw);
  // a four-point star round (cx, cy)
  const star4 = (cx, cy, r, fill, sw = 3.5) =>
    P(`M${cx} ${cy - r} Q${cx + r * 0.18} ${cy - r * 0.18} ${cx + r} ${cy} Q${cx + r * 0.18} ${cy + r * 0.18} ${cx} ${cy + r} Q${cx - r * 0.18} ${cy + r * 0.18} ${cx - r} ${cy} Q${cx - r * 0.18} ${cy - r * 0.18} ${cx} ${cy - r} Z`, fill, sw);
  const g = (inner, t) => `<g transform="${t}">${inner}</g>`;

  // ------------------------------------------------------------ the Royal egg's armour set
  // (EggGear/Clean + Royal: plates in the ore's colour over a darker under-suit, gold gauntlets,
  // collar, rims and belt, a gold crest with the glowing gem, the eyes in a dark visor)
  // k: plate, suit (PAL names), gem (a colour), gold (PAL name, default gold)
  function knightBody(k) {
    const plate = C(k.plate), suit = C(k.suit), gold = C(k.gold || "gold");
    let s = "";
    // legs and boots
    s += R(45, 102, 15, 14, 3, suit) + R(68, 102, 15, 14, 3, suit);
    s += R(42, 111, 20, 12, 4, plate) + R(66, 111, 20, 12, 4, plate);
    // arms (under-suit)
    s += R(24, 84, 16, 16, 5, suit) + R(88, 84, 16, 16, 5, suit);
    // the torso, the breastplate
    s += R(37, 76, 54, 31, 6, suit);
    s += R(41, 78, 46, 25, 7, plate);
    if (k.chest) s += k.chest;
    // the gold crest with its gem
    s += P("M55 82 L73 82 L73 91 Q73 98 64 102 Q55 98 55 91 Z", gold, 4);
    s += dia(64, 90.5, 10, 11, k.gem, 3);
    // the belt and its glowing buckle
    s += R(37, 100, 54, 7, 3, gold, 4);
    s += R(59, 98.5, 10, 10, 2.5, k.buckle || k.gem, 3.5);
    // the collar
    s += R(39, 73, 50, 7, 3, gold, 4);
    // the shoulder plates (domes) on gold rims
    for (const [x, m] of [[35, 1], [93, -1]]) {
      s += R(x - 15, 84, 30, 5, 2.5, gold, 4);
      s += P(`M${x - 14} 86 Q${x - 14} 72 ${x} 72 Q${x + 14} 72 ${x + 14} 86 Z`, plate, 4.5);
      s += shine(x - 6 * m, 77, 4, 2, -20 * m, 0.75);
      if (k.shoulderGem) s += dia(x, 74, 8, 7, k.shoulderGem, 3);
    }
    // the gold gauntlets
    s += R(21, 95, 19, 15, 5, gold) + R(88, 95, 19, 15, 5, gold);
    // shines
    s += shine(47, 83, 2.2, 4.5, 15, 0.7) + shine(25, 99, 2, 3.5, 10, 0.75) + shine(92, 99, 2, 3.5, 10, 0.75);
    return s;
  }

  // a knight's head: the block, a dark cap over its top (or none), the gold band, gold guards on its
  // sides, the visor and its eyes. h: { fill, cap, band, top, eye }
  function knightHead(h) {
    const top = h.top ?? 20;
    let s = R(26, top, 76, 78 - top, 12, C(h.fill));
    if (h.cap) s += P(`M26 ${top + 14} L26 ${top + 10} Q26 ${top} 38 ${top} L90 ${top} Q102 ${top} 102 ${top + 10} L102 ${top + 14} Z`, C(h.cap), 4.5);
    s += R(21, top + 16, 9, 36, 3.5, C("gold"), 4) + R(98, top + 16, 9, 36, 3.5, C("gold"), 4);
    if (h.band !== false) s += R(24, top + 9, 80, 7, 3.5, C("gold"), 4);
    s += visor(35, top + 24, 58, 19, h.eye, 10);
    s += shine(37, top + 5, 6, 2, -8, 0.8) + dot(47, top + 4.5, 1.4);
    return s;
  }

  // the visor on a head: a dark slit, two glowing eyes
  function visor(x, y, w, h, eye, eh) {
    let s = R(x, y, w, h, 4, "#1d1726", 4);
    const ew = Math.round(w * 0.27), ey = y + (h - eh) / 2;
    if (!HALO) {
      s += `<rect x="${x + w * 0.12}" y="${ey}" width="${ew}" height="${eh}" rx="1.5" fill="${eye}"/>`;
      s += `<rect x="${x + w - w * 0.12 - ew}" y="${ey}" width="${ew}" height="${eh}" rx="1.5" fill="${eye}"/>`;
    }
    return s;
  }

  // a sword held up in the right fist (the viewer's left), the blade leaning out; fire: a glowing core
  function swordBlade(blade, fire) {
    let s = P("M25 90 L25 33 L29 24 L33 33 L33 90 Z", C(blade), 4.5);
    if (fire) s += F("M27.6 86 L27.6 37 L29 32 L30.4 37 L30.4 86 Z", fire);
    s += shine(26.9, 52, 0.9, 9, 0, 0.8);
    return g(s, "rotate(-14 29 98)");
  }
  function swordGuard(guard) {
    return g(R(20, 87, 18, 5, 2.5, C(guard), 3.5), "rotate(-14 29 98)");
  }
  // a gold staff in the right fist (the viewer's left) from y0 up to y1
  const staff = (x, y0, y1, w = 4.5) => line(`M${x} ${y0} L${x} ${y1}`, w, "#f2b02a", 4.5);
  // the aura disc a Legendary or Mythic golem hovers on
  const aura = (fill) => E(64, 121, 42, 7, fill, 4.5) + (HALO ? "" : `<ellipse cx="64" cy="121" rx="30" ry="4" fill="#fff" opacity="0.28"/>`);

  const D = {};

  // SilverSquire (Uncommon): a closed silver helm with a red plume and a gold nose guard, a round
  // pearl shield, a sword
  D.golem_SilverSquire = () => {
    let s = swordBlade("blade");
    s += knightBody({ plate: "silver", suit: "silverSuit", gem: "#eef6ff" });
    s += swordGuard("gold");
    s += knightHead({ fill: "silverHelm", eye: "#e2ecff" });
    s += R(61, 31, 6, 26, 2.5, C("gold"), 3.5); // the nose guard
    s += P("M64 21 C56 14 57 2 64 0 C71 2 72 14 64 21 Z", C("plume"), 4.5);
    s += shine(61, 7, 1.6, 4, 15, 0.85);
    // the round shield on the left arm (the viewer's right)
    s += E(107, 100, 16, 18, C("gold"));
    s += E(107, 100, 11.5, 13.5, C("pearl"), 3.5);
    s += E(107, 100, 4, 4, C("gold"), 3.5);
    s += shine(101.5, 93, 2.2, 4, 20, 0.85);
    return s;
  };

  // RoseKnight (Rare): a closed rose helm with a gold brow and crest, a rose on the crest, a big
  // pearl kite shield, a sword, roses on its shoulders
  D.golem_RoseKnight = () => {
    const glow = "#ff9ad0";
    let s = swordBlade("blade");
    s += knightBody({ plate: "rose", suit: "roseSuit", gem: glow, shoulderGem: glow });
    s += swordGuard("gold");
    // the crest (a gold fin front to back) and the rose at its front
    s += R(60.5, 6, 7, 18, 2.5, C("gold"), 4);
    s += knightHead({ fill: "roseHelm", eye: glow, band: false });
    s += R(27, 33, 74, 7, 3, C("gold"), 4); // the gold brow over the slit
    s += dia(64, 8, 14, 14, C("rose"), 4) + dia(64, 8, 6, 6, glow, 2.5);
    // the kite shield on the left arm: pearl on a gold rim, a glowing rose
    s += P("M90 82 L124 82 L124 98 Q124 112 107 123 Q90 112 90 98 Z", C("gold"));
    s += P("M94 86 L120 86 L120 98 Q120 109 107 117.5 Q94 109 94 98 Z", C("pearl"), 3.5);
    s += dia(107, 99, 11, 13, glow, 3);
    s += shine(98.5, 92, 1.8, 4, 0, 0.85);
    return s;
  };

  // MoonstoneOracle (Epic): a halo of moonlight, a gold crescent on its brow holding a moonstone,
  // a crescent staff with an orb, orbs floating round it
  D.golem_MoonstoneOracle = () => {
    const glow = "#dbe7ff";
    let s = staff(16, 116, 26);
    s += line("M8 9 L10 22 L22 22 L24 9", 3.5, "#f2b02a", 4.5);
    s += E(16, 13, 5.5, 5.5, C("moonGlow"), 3.5);
    s += knightBody({ plate: "moon", suit: "moonSuit", gem: glow, shoulderGem: glow });
    s += knightHead({ fill: "moonHelm", cap: "moonCap", eye: "#d6e2ff" });
    // the gold crescent rising from the brow, the moonstone in its cup
    s += line("M47 4 Q47 27 64 28 Q81 27 81 4", 4, "#f6bd3a", 4.5);
    s += dia(64, 17, 12, 14, C("moonGlow"), 3.5);
    // the halo
    s += `<ellipse cx="64" cy="5" rx="25" ry="5.5" fill="none" stroke="${O}" stroke-width="${hs(9)}"/>`;
    if (!HALO) s += `<ellipse cx="64" cy="5" rx="25" ry="5.5" fill="none" stroke="#d4e2ff" stroke-width="4"/>`;
    // orbs floating round it
    s += E(115, 70, 5.5, 5.5, C("moonGlow"), 3.5) + E(121, 54, 3.5, 3.5, C("moonGlow"), 3);
    return s;
  };

  // StormTitan (Legendary): a crown of lightning, lightning rising from its shoulders, storm
  // crystals on its back, gold spikes, sparks; it hovers on its aura
  D.golem_StormTitan = () => {
    const glow = "#8fd0ff";
    let s = aura(C("stormGlow"));
    // storm crystals on its back, peeking over the shoulders
    s += P("M33 74 L25 46 L33 40 L41 70 Z", C("stormGlow"), 4) + P("M95 74 L103 46 L95 40 L87 70 Z", C("stormGlow"), 4);
    // lightning rising from its shoulders
    s += P("M21 80 L8 62 L15 60 L4 40 L20 58 L13 60 L26 77 Z", C("bolt"), 3.5);
    s += P("M107 80 L120 62 L113 60 L124 40 L108 58 L115 60 L102 77 Z", C("bolt"), 3.5);
    s += knightBody({ plate: "storm", suit: "stormSuit", gem: glow, shoulderGem: glow });
    // gold spikes on the shoulder plates
    s += P("M25 76 L16 66 L30 71 Z", C("gold"), 3.5) + P("M103 76 L112 66 L98 71 Z", C("gold"), 3.5);
    // lightning in its gauntlets
    s += F("M27 98 L33 104 L30 104 L35 109 L28 103 L31 103 Z", "#fff59a") + F("M101 98 L95 104 L98 104 L93 109 L100 103 L97 103 Z", "#fff59a");
    s += knightHead({ fill: "stormHelm", cap: "stormCap", eye: glow, top: 24 });
    // the crown of lightning: gold band, five points with glowing tips, blue gems
    s += P("M36 27 L36 13 L42 20 L49 6 L56 17 L64 2 L72 17 L79 6 L86 20 L92 13 L92 27 Z", C("gold"), 4.5);
    s += F("M49 6 L52.5 11.5 L46.5 11.5 Z M64 2 L67.5 8 L60.5 8 Z M79 6 L82 11.5 L76 11.5 Z", "#fff6a8");
    s += dia(50, 21, 7, 8, glow, 2.5) + dia(64, 21, 8, 9, glow, 2.5) + dia(78, 21, 7, 8, glow, 2.5);
    // storm orbs floating round it
    s += E(121, 92, 4.5, 4.5, C("stormGlow"), 3) + E(7, 98, 4, 4, C("stormGlow"), 3);
    return s;
  };

  // CelestialSovereign (Mythic): a gold crown of stars under a gold halo, wings of light, a star
  // sceptre, stars floating round it; it hovers on its aura
  D.golem_CelestialSovereign = () => {
    const glow = "#b8c2ff";
    let s = aura(C("celestGlow"));
    // wings of light: a gold feather and two of light on each side
    for (const m of [1, -1]) {
      const x = m > 0 ? 100 : 28;
      s += g(E(0, 0, 20, 6, C("star"), 4), `translate(${x + m * 12} ${58}) rotate(${-m * 40})`);
      s += g(E(0, 0, 18, 5.5, C("star"), 4), `translate(${x + m * 15} ${70}) rotate(${-m * 16})`);
      s += g(E(0, 0, 20, 6.5, C("gold"), 4), `translate(${x + m * 11} ${80}) rotate(${-m * 2})`);
    }
    // the star sceptre in the right fist
    s += staff(15, 116, 30);
    s += R(10, 26, 10, 6, 2, C("gold"), 3.5);
    s += P("M15 4 L18 12 L26 9 L21 16 L28 21 L19 21 L18 29 L15 23 L12 29 L11 21 L2 21 L9 16 L4 9 L12 12 Z", C("star"), 3.5);
    s += knightBody({ plate: "celest", suit: "celestSuit", gem: glow, shoulderGem: "#fff2a8" });
    s += knightHead({ fill: "celestHelm", cap: "celestCap", eye: glow, top: 26 });
    // the crown of stars and the gold halo over it
    s += P("M37 29 L37 17 L44 22 L51 10 L58 20 L64 7 L70 20 L77 10 L84 22 L91 17 L91 29 Z", C("gold"), 4.5);
    s += dia(51, 23, 6, 7, "#fff2a8", 2.5) + dia(64, 23, 8, 9, glow, 2.5) + dia(77, 23, 6, 7, "#fff2a8", 2.5);
    s += `<ellipse cx="64" cy="4" rx="21" ry="4.5" fill="none" stroke="${O}" stroke-width="${hs(9)}"/>`;
    if (!HALO) s += `<ellipse cx="64" cy="4" rx="21" ry="4.5" fill="none" stroke="#ffd84a" stroke-width="4"/>`;
    // stars floating round it
    s += star4(118, 48, 6, C("star")) + star4(112, 30, 3.5, C("star"), 3);
    return s;
  };

  // GildedPorter (Rare, the Starter Pack's): gold plates, a velvet porter's cap on a gold brim with
  // a miner's lamp, velvet straps of the pack of gold on its back, a railway lantern
  D.golem_GildedPorter = () => {
    const glow = "#ffe46a";
    let s = knightBody({
      plate: "porter",
      suit: "porterSuit",
      gem: glow,
      chest: R(49.5, 79, 5, 22, 2, C("velvet"), 3) + R(73.5, 79, 5, 22, 2, C("velvet"), 3),
    });
    // the railway lantern in the left hand (the viewer's right)
    s += line("M103 100 Q110 92 117 100", 2.5, "#c47a14", 4);
    s += R(101, 100, 18, 20, 4, C("goldDeep"), 4.5) + R(105, 104, 10, 12, 2, C("lamp"), 3);
    s += knightHead({ fill: "porter", eye: glow, band: false, top: 26 });
    // the velvet cap on its gold brim, the lamp on its front
    s += P("M31 30 L31 22 Q31 4 64 4 Q97 4 97 22 L97 30 Z", C("velvet"));
    s += R(25, 26, 78, 8, 3.5, C("goldDeep"), 4);
    s += E(64, 18, 9, 9, C("goldDeep"), 4) + E(64, 18, 5.5, 5.5, C("lamp"), 3);
    s += shine(44, 12, 6, 2.5, -15, 0.8);
    return s;
  };


  // ------------------------------------------------------------ the Dragonforge set
  // (LimitedGear/Dragonforge: a dragon golem's body, its face, horns, wings, claws and tail)
  const pts = (list) => list.map(([x, y], i) => `${i ? "L" : "M"}${x} ${y}`).join(" ") + " Z";
  const mx = (list) => list.map(([x, y]) => [128 - x, y]);
  // both sides of a shape drawn on the viewer's left (the right one mirrored, its light still top-left)
  const pair = (fn) => fn((x) => x) + fn((x) => 128 - x);

  // a bat wing behind each shoulder: the membrane, its outer panel (and an inner one), the bones;
  // w: { m1, m2, m3?, bone, kx, ky (the wing's width and height: kx 1 reaches the box's edge), boneLow }
  function batWings(w) {
    const kx = w.kx ?? 1, ky = w.ky ?? kx;
    // the left wing's points (shoulder R, wrist W, finger tips T1 (high) and T2 (low), L low on the back)
    const Rp = [38, 74], Wp = [38 - 20 * kx, 74 - 34 * ky], T1 = [38 - 34 * kx, 74 - 50 * ky], T2 = [38 - 36 * kx, 74 - 4 * ky], Lp = [38 - 6 * kx, 74 + 16 * ky];
    const mid = (a, b, d) => [(a[0] + b[0]) / 2 + d[0], (a[1] + b[1]) / 2 + d[1]];
    const s1 = mid(T1, T2, [7 * kx, 0]), s2 = mid(T2, Lp, [5 * kx, -5 * ky]);
    let s = "";
    for (const side of [0, 1]) {
      const f = side ? mx : (l) => l;
      // the whole membrane, scalloped between the finger tips
      s += P(pts(f([Rp, Wp, T1, s1, T2, s2, Lp])), C(w.m1), 4.5);
      // the outer panel
      s += P(pts(f([Wp, T1, s1, T2])), C(w.m2), 3.5);
      if (w.m3) s += P(pts(f([Rp, T2, s2, Lp])), C(w.m3), 3.5);
      // the bones
      const b = f([Rp, Wp, T1]);
      s += line(`M${b[0][0]} ${b[0][1]} L${b[1][0]} ${b[1][1]} L${b[2][0]} ${b[2][1]}`, 3.2 * Math.max(kx, 0.8), w.bone, 3.5);
      if (w.boneLow) {
        const c = f([Wp, T2]);
        s += line(`M${c[0][0]} ${c[0][1]} L${c[1][0]} ${c[1][1]}`, 2.6, w.bone, 3.5);
      }
    }
    return s;
  }

  // the body: legs, arms with claws, the torso with the glowing core and the belly; d: { body, dark,
  // core, belly, claws, fists }
  function dragonBody(d) {
    let s = "";
    s += R(45, 102, 15, 20, 3.5, C(d.dark)) + R(68, 102, 15, 20, 3.5, C(d.dark));
    // claws under the fists
    const claw = d.claws || "ivory";
    for (const x of [24, 31, 38, 90, 97, 104]) s += P(`M${x - 3} 106 L${x + 3} 106 L${x} 113 Z`, C(claw), 3);
    s += R(23, 80, 17, 27, 5.5, C(d.fists || d.body)) + R(88, 80, 17, 27, 5.5, C(d.fists || d.body));
    s += R(37, 75, 54, 33, 7, C(d.body));
    if (d.belly) s += R(51, 95, 26, 5, 2.5, C(d.belly), 3) + R(53, 101.5, 22, 5, 2.5, C(d.belly), 3);
    s += dia(64, 85, 15, 15, C(d.core), 3.5) + shine(61.5, 82, 1.5, 2.5, 30, 0.85);
    s += shine(43, 81, 2, 4, 15, 0.6);
    return s;
  }

  // a dragon's eyes: glowing squares, slit pupils, a glint
  function dragonEyes(y, eye, w = 13, h = 11) {
    let s = "";
    for (const x of [40, 88 - w]) {
      s += R(x, y, w, h, 2, eye, 3.5);
      if (!HALO) s += `<rect x="${x + w * 0.42}" y="${y + 1.5}" width="${w * 0.2}" height="${h - 3}" rx="1" fill="#2a120e"/>` + `<rect x="${x + 2}" y="${y + 2}" width="3" height="3" fill="#fff"/>`;
    }
    return s;
  }

  // a pair of horns from the head's top corners, curving up and out
  function horns(top, fill, tip, k = 1) {
    return pair((X) => {
      const d = `M${X(34)} ${top + 6} C${X(30)} ${top - 4 * k} ${X(24 - 4 * k)} ${top - 10 * k} ${X(22 - 4 * k)} ${top - 22 * k} C${X(30)} ${top - 16 * k} ${X(40)} ${top - 10 * k} ${X(46)} ${top + 4} Z`;
      let s = P(d, C(fill), 4);
      if (tip) s += P(`M${X(22 - 4 * k)} ${top - 22 * k} C${X(25)} ${top - 18 * k} ${X(29)} ${top - 15 * k} ${X(31)} ${top - 13 * k} L${X(25 - 2 * k)} ${top - 11 * k} Z`, C(tip), 3);
      return s;
    });
  }

  // a tail curling out to the golem's right (the viewer's left), its tip at (x, y)
  function tail(fill, tipFn) {
    let s = line("M44 108 C36 116 22 118 14 112", 6, fill === "basalt" ? "#4a424c" : fill, 4.5);
    s += tipFn(12, 110);
    return s;
  }

  // flight goggles on the forehead: the strap, two round lenses in their rims
  function goggles(y, rim, lens) {
    let s = R(25, y - 3.5, 78, 7, 3, C("leather"), 3.5);
    for (const x of [51, 77]) s += E(x, y, 9, 9, C(rim), 3.5) + E(x, y, 5.5, 5.5, C(lens), 2.5) + shine(x - 2, y - 2.5, 1.6, 1, -30, 0.9);
    return s;
  }

  // a flame (a teardrop) standing at (x, y bottom), h tall
  const flameShape = (x, y, w, h, fill, sw = 3.5) =>
    P(`M${x} ${y - h} C${x + w * 0.2} ${y - h * 0.6} ${x + w / 2} ${y - h * 0.45} ${x + w / 2} ${y - h * 0.22} C${x + w / 2} ${y - 1} ${x + w * 0.2} ${y} ${x} ${y} C${x - w * 0.2} ${y} ${x - w / 2} ${y - 1} ${x - w / 2} ${y - h * 0.22} C${x - w / 2} ${y - h * 0.45} ${x - w * 0.2} ${y - h * 0.6} ${x} ${y - h} Z`, fill, sw);

  // CinderWhelp (Rare): a soot-black baby dragon: curled ivory horns, flight goggles, a muzzle with
  // glowing nostrils, little boned bat wings, ivory claws, a tail with a glowing spade
  D.golem_CinderWhelp = () => {
    const glow = "#ff8a2a";
    let s = batWings({ m1: "whelpWing", m2: "whelpWingDark", bone: "#3e3540", kx: 1, ky: 1.05, boneLow: true });
    s += tail("#3e3540", (x, y) => dia(x, y, 13, 13, C("flame"), 3.5));
    s += dragonBody({ body: "basalt", dark: "basaltDark", core: "flame", belly: "tan" });
    s += horns(22, "ivory", null, 1);
    s += R(26, 20, 76, 58, 13, C("basalt"));
    // the orange crest on top
    s += flameShape(64, 21, 10, 14, C("flame"));
    s += goggles(32, "gold", "flame");
    s += dragonEyes(44, C("flame"));
    // the muzzle with its glowing nostrils
    s += R(46, 57, 36, 17, 5, C("whelpMuzzle"), 4);
    s += R(53, 61, 6, 4, 1.5, glow, 2) + R(69, 61, 6, 4, 1.5, glow, 2);
    s += shine(37, 25, 6, 2, -8, 0.6);
    return s;
  };

  // EmberHatchling (Rare): still half in its egg: the top of the shell as a cap (a broken zigzag rim,
  // orange spots), the bottom round its hips, big sparkly eyes, a blush, a gold bell, stubby wings
  D.golem_EmberHatchling = () => {
    let s = batWings({ m1: "flame", m2: "flame", bone: "#9c2a1c", kx: 0.55, ky: 0.5 });
    s += tail("#9c2a1c", (x, y) => dia(x, y, 11, 11, C("flameHot"), 3));
    // the tiny gold cape behind
    s += P("M38 78 L90 78 L98 110 L30 110 Z", C("flameHot"), 4);
    s += dragonBody({ body: "hatch", dark: "hatchDark", core: "flameHot" });
    // the bottom of the egg round its hips, its broken points up
    s += P("M32 98 L40 92 L46 98 L54 88 L64 98 L74 88 L82 98 L88 92 L96 98 C98 114 84 122 64 122 C44 122 30 114 32 98 Z", C("shell"), 4.5);
    s += shine(40, 108, 2.2, 5, 20, 0.85);
    // the red collar and its gold bell
    s += R(38, 72, 52, 7, 3.5, C("ember"), 3.5);
    s += R(26, 30, 76, 48, 13, C("hatch"));
    // the top of the egg: a dome over the head, its zigzag rim over the brow
    s += P("M22 40 C22 6 40 0 64 0 C88 0 106 6 106 40 L98 34 L90 44 L82 34 L73 44 L64 34 L55 44 L46 34 L38 44 L30 34 Z", C("shell"), 4.5);
    s += E(46, 14, 5, 4, C("spot"), 3) + E(78, 9, 4, 3.5, C("spot"), 3) + E(88, 22, 4.5, 4, C("spot"), 3);
    s += shine(36, 18, 3, 6, 30, 0.9);
    // big sparkly eyes and the blush
    for (const x of [41, 71]) {
      s += R(x, 46, 16, 15, 3, C("flameHot"), 3.5);
      if (!HALO) s += `<rect x="${x + 9}" y="${48}" width="4.5" height="4.5" fill="#fff"/><rect x="${x + 3}" y="${55}" width="2.5" height="2.5" fill="#fff"/>`;
    }
    s += F("M33 64 h8 v4 h-8 Z M87 64 h8 v4 h-8 Z", "#ff9aa6");
    s += E(64, 79, 5, 5, C("gold"), 3) + shine(62.5, 77.5, 1.2, 1, 0, 0.9);
    return s;
  };

  // ScaleKnight (Epic, Dragonscale Knight): a closed helm shaped like a dragon's skull (brow,
  // jaw, fangs, swept gold horns, a glowing crest and a plume of flame), a cape, a tabard with the
  // dragon's eye, a kite shield, a flaming sword
  D.golem_ScaleKnight = () => {
    const glow = "#ff5a2a";
    // the cape behind
    let s = P("M30 76 L98 76 L106 118 L22 118 Z", C("cape"), 4.5);
    s += swordBlade("blade", "#ff7a2a");
    s += dragonBody({ body: "scaleBody", dark: "scaleDark", core: "ember" });
    // the tabard with the dragon's eye, the gold belt
    s += R(49, 78, 30, 26, 4, C("cape"), 3.5) + dia(64, 88, 12, 14, C("ember"), 3);
    s += R(37, 100, 54, 6, 3, C("gold"), 3.5);
    // gold bracers, scale pauldrons on the shoulders
    s += R(22, 86, 19, 9, 3, C("gold"), 3.5) + R(87, 86, 19, 9, 3, C("gold"), 3.5);
    s += g(R(18, 74, 26, 9, 3.5, C("scaleHelm"), 4), "rotate(-14 31 78)") + g(R(84, 74, 26, 9, 3.5, C("scaleHelm"), 4), "rotate(14 97 78)");
    s += swordGuard("gold");
    // swept-back horns, gold into ivory
    s += horns(22, "gold", "ivory", 1.05);
    // the crest of three glowing fins, the plume of flame
    s += flameShape(64, 18, 12, 20, C("flame")) + flameShape(64, 18, 6, 12, C("flameHot"), 2.5);
    s += R(26, 20, 76, 58, 12, C("scaleHelm"));
    // the brow ridge over the slit, the slit and its glowing eyes
    s += R(28, 32, 72, 8, 3.5, C("scaleDark"), 4);
    s += R(36, 41, 56, 13, 3, "#1d1215", 4);
    if (!HALO) s += `<rect x="42" y="44" width="15" height="7" rx="1.5" fill="${glow}"/><rect x="71" y="44" width="15" height="7" rx="1.5" fill="${glow}"/>`;
    // the snout (the jaw) under it, glowing nostrils, fangs
    s += R(42, 57, 44, 16, 4.5, C("scaleDark"), 4);
    s += R(53, 61, 6, 4, 1.5, glow, 2) + R(69, 61, 6, 4, 1.5, glow, 2);
    s += P("M47 72 L53 72 L50 79 Z", C("ivory"), 3) + P("M75 72 L81 72 L78 79 Z", C("ivory"), 3);
    s += shine(37, 25, 6, 2, -8, 0.7);
    // the kite shield on the left arm with the dragon's eye
    s += P("M92 82 L124 82 L124 98 Q124 111 108 122 Q92 111 92 98 Z", C("scaleHelm"));
    s += R(105, 92, 6, 16, 2, glow, 2.5) + shine(97.5, 89, 1.8, 4, 0, 0.7);
    return s;
  };

  // Flamewing (Epic): wings made of fire (ember red, flame, white hot), a flame mohawk, short ivory
  // horns, aviator goggles, a scarf, burning fists, a belt with a glowing buckle
  D.golem_Flamewing = () => {
    let s = batWings({ m1: "ember", m2: "flame", m3: "flameHot", bone: "#ffe066", kx: 1, ky: 1.25 });
    s += tail("#7a1c22", (x, y) => flameShape(x, y + 6, 13, 18, C("flame")));
    s += dragonBody({ body: "flameRed", dark: "flameDark", core: "flameHot", belly: "belly", fists: "flame" });
    // the brown belt and its glowing buckle, brown bracers
    s += R(37, 99, 54, 6, 3, C("leather"), 3.5) + dia(64, 102, 9, 9, C("flameHot"), 3);
    s += R(22, 84, 19, 7, 3, C("leather"), 3.5) + R(87, 84, 19, 7, 3, C("leather"), 3.5);
    // the scarf round the neck
    s += R(36, 72, 56, 7, 3.5, C("belly"), 3.5);
    s += horns(22, "ivory", null, 0.75);
    // the flame mohawk: hot in the middle
    s += flameShape(52, 22, 10, 14, C("flame")) + flameShape(76, 22, 10, 14, C("flame")) + flameShape(64, 22, 12, 22, C("flameHot"));
    s += R(26, 20, 76, 58, 12, C("flameRed"));
    s += goggles(32, "gold", "lens");
    s += dragonEyes(44, C("flameHot"));
    s += R(46, 57, 36, 17, 5, C("ember"), 4);
    s += R(53, 61, 6, 4, 1.5, "#ffb03a", 2) + R(69, 61, 6, 4, 1.5, "#ffb03a", 2);
    s += shine(37, 25, 6, 2, -8, 0.75);
    return s;
  };

  // MagmaWyvern (Legendary): obsidian with lava in its cracks, huge torn wings (a glowing inner
  // panel), long swept horns, a roaring maw, a high collar, ivory spikes, lava fists; it hovers
  D.golem_MagmaWyvern = () => {
    const lava = "#ff7a1a";
    let s = aura(C("lava"));
    s += batWings({ m1: "lava", m2: "wingDark", bone: "#2a2028", kx: 1, ky: 1.3, boneLow: true });
    // the high collar of the cape behind the head
    s += P("M30 80 L22 30 L40 46 L64 40 L88 46 L106 30 L98 80 Z", C("obsidianDark"), 4.5);
    s += dragonBody({ body: "obsidian", dark: "obsidianDark", core: "lava", fists: "lava" });
    // lava in its cracks (chest, arms, legs)
    s += F("M42 80 L46 86 L44 90 M84 92 L80 97 M30 86 L33 92 M97 90 L94 96 M49 106 L51 112 M77 108 L75 114", "none", `stroke="${lava}" stroke-width="2.4" stroke-linecap="round"`);
    // dark pauldrons with ivory spikes
    s += P("M19 82 L13 64 L27 76 Z", C("ivory"), 3.5) + P("M109 82 L115 64 L101 76 Z", C("ivory"), 3.5);
    s += g(R(18, 74, 26, 9, 3.5, C("obsidian"), 4), "rotate(-14 31 78)") + g(R(84, 74, 26, 9, 3.5, C("obsidian"), 4), "rotate(14 97 78)");
    // long horns swept back
    s += horns(22, "ivory", null, 1.12);
    s += R(26, 20, 76, 58, 12, C("obsidian"));
    s += F("M36 30 L42 38 L40 44 M90 28 L86 35", "none", `stroke="${lava}" stroke-width="2.4" stroke-linecap="round"`);
    s += R(30, 33, 68, 7, 3, C("obsidianDark"), 3.5);
    s += dragonEyes(42, C("lava"), 12, 9);
    // the roaring maw: the snout, the glowing mouth, the lower jaw, fangs
    s += R(44, 54, 40, 10, 4, C("obsidianDark"), 4);
    s += R(47, 63, 34, 8, 3, C("lava"), 3.5);
    s += R(45, 70, 38, 7, 3, C("obsidianDark"), 4);
    s += P("M50 62 L56 62 L53 69 Z", C("ivory"), 2.5) + P("M72 62 L78 62 L75 69 Z", C("ivory"), 2.5);
    s += shine(37, 25, 6, 2, -8, 0.45);
    return s;
  };

  // DragonKing (Mythic): huge gold-boned wings in three crimson panels, a gold crown with gems and a
  // living flame, gold horns, a royal cape with an ermine collar, gold armour, a gold dragon mask,
  // a sceptre with a fire orb, fire gems floating round it; it hovers on its aura
  D.golem_DragonKing = () => {
    const glow = "#ff9a1e";
    let s = aura(C("lava"));
    s += batWings({ m1: "kingRed2", m2: "kingRed", m3: "kingRed3", bone: "#ffcc44", kx: 1, ky: 1.3, boneLow: true });
    // the royal cape behind
    s += P("M30 76 L98 76 L108 118 L20 118 Z", C("cape"), 4.5);
    s += R(22, 112, 84, 7, 3, C("gold"), 3.5);
    // the sceptre in the right fist: a gold staff, its diamond head, the fire orb
    s += staff(16, 116, 30);
    s += dia(16, 27, 14, 14, C("kingGold"), 3.5) + E(16, 15, 7, 7, C("flameHot"), 3.5) + shine(14, 13, 2, 1.5, -30, 0.9);
    s += dragonBody({ body: "kingBody", dark: "kingGold", core: "flame", claws: "kingGold" });
    // gold armour: the breastplate over the core, the belt, bracers with red gems
    s += R(42, 77, 44, 24, 6, C("kingGold"), 4) + dia(64, 87, 13, 14, C("flame"), 3);
    s += R(37, 100, 54, 6, 3, C("goldDeep"), 3.5);
    s += R(22, 86, 19, 9, 3, C("kingGold"), 3.5) + R(87, 86, 19, 9, 3, C("kingGold"), 3.5);
    s += dia(31.5, 90.5, 6, 6, C("gemRed"), 2.5) + dia(96.5, 90.5, 6, 6, C("gemRed"), 2.5);
    // the ermine collar
    s += R(28, 73, 72, 10, 5, C("ermine"), 4);
    if (!HALO) s += `<rect x="33" y="77.5" width="3" height="3" fill="#2a1e2a"/><rect x="92" y="77.5" width="3" height="3" fill="#2a1e2a"/>`;
    // gold horns
    s += horns(24, "kingGold", "ivory", 1);
    s += R(26, 24, 76, 54, 12, C("kingBody"));
    // the gold dragon mask over the snout, the eyes
    s += dragonEyes(42, C("flame"), 12, 10);
    s += R(44, 55, 40, 18, 5, C("kingGold"), 4);
    s += R(53, 59, 6, 4, 1.5, glow, 2) + R(69, 59, 6, 4, 1.5, glow, 2);
    // the crown: a gold band, five points, three gems and a living flame
    s += P("M34 32 L34 16 L41 23 L48 10 L56 21 L64 6 L72 21 L80 10 L87 23 L94 16 L94 32 Z", C("kingGold"), 4.5);
    s += dia(48, 26, 7, 8, C("gemRed"), 2.5) + dia(64, 26, 9, 10, C("flame"), 2.5) + dia(80, 26, 7, 8, C("gemRed"), 2.5);
    s += dia(64, 4, 16, 16, C("flame"), 3.5) + dia(64, 5, 7, 7, "#fff6c8", 2.5);
    // fire gems floating round it
    s += dia(120, 58, 9, 11, C("gemRed"), 3) + dia(7, 66, 8, 10, C("flameHot"), 3);
    return s;
  };

  // ------------------------------------------------------------ the eggs
  // An egg's shell (CapsuleEggs: a ball under the waist, a taller shell over it): a half circle (r)
  // under its widest line (cy) and a half ellipse 1.5 r tall over it, so it is round at the bottom
  // and narrows to its tip (the game's own stands straighter; drawn so, it read like a vase).
  const EGG_TOP = 1.5;
  function eggPath(cx, cy, r) {
    const k = 0.5523, t = cy - EGG_TOP * r, b = cy + r, h = EGG_TOP * r;
    return `M${cx} ${t} C${cx + k * r} ${t} ${cx + r} ${cy - k * h} ${cx + r} ${cy} ` +
      `C${cx + r} ${cy + k * r} ${cx + k * r} ${b} ${cx} ${b} C${cx - k * r} ${b} ${cx - r} ${cy + k * r} ${cx - r} ${cy} ` +
      `C${cx - r} ${cy - k * h} ${cx - k * r} ${t} ${cx} ${t} Z`;
  }
  // the half width of the shell at height y
  function eggHalf(cy, r, y) {
    const v = y >= cy ? (y - cy) / r : (cy - y) / (EGG_TOP * r);
    return r * Math.sqrt(Math.max(0, 1 - v * v));
  }
  // the lower part of the shell under y0 (y0 >= cy)
  function eggLow(cx, cy, r, y0) {
    const w = eggHalf(cy, r, y0);
    return `M${cx - w} ${y0} L${cx + w} ${y0} A${r} ${r} 0 0 1 ${cx} ${cy + r} A${r} ${r} 0 0 1 ${cx - w} ${y0} Z`;
  }
  // a band round the shell from y0 to y0 + h, following its sides
  function eggBand(cx, cy, r, y0, h, fill) {
    const w0 = eggHalf(cy, r, y0), w1 = eggHalf(cy, r, y0 + h);
    return P(`M${cx - w0} ${y0} L${cx + w0} ${y0} L${cx + w1} ${y0 + h} L${cx - w1} ${y0 + h} Z`, fill, 3.5);
  }
  // a short talon gripping the shell's bottom from the side, its tip (another colour) curling in;
  // the bottom between the two stays bare (a ring of gold there read like a vase's foot)
  function talon(cx, cy, r, m, fill, tip) {
    const x = (f) => cx + m * f * r;
    let s = P(`M${x(0.6)} ${cy + 0.98 * r} C${x(0.92)} ${cy + 0.9 * r} ${x(1.1)} ${cy + 0.66 * r} ${x(1.1)} ${cy + 0.32 * r} L${x(0.94)} ${cy + 0.4 * r} C${x(0.92)} ${cy + 0.62 * r} ${x(0.8)} ${cy + 0.78 * r} ${x(0.56)} ${cy + 0.86 * r} Z`, fill, 4);
    s += P(`M${x(1.1)} ${cy + 0.32 * r} L${x(1.02)} ${cy + 0.06 * r} L${x(0.94)} ${cy + 0.4 * r} Z`, tip, 3);
    return s;
  }
  // a stream of light or lava running down the shell from its tip, ending in a drop
  function stream(cx, cy, r, m, color, fill, w = 3.1) {
    const t = cy - EGG_TOP * r;
    let s = line(`M${cx + m * 6} ${t + 5} C${cx + m * 12} ${t + 14} ${cx + m * 17} ${t + 24} ${cx + m * 18} ${t + 37}`, w, color, 3.5);
    return s + E(cx + m * 18, t + 40, 3.1, 3.1, fill, 3);
  }
  // the shell's gloss: a long curved light down its upper left, a glint
  function gloss(cx, cy, r, o = 0.95) {
    if (HALO) return "";
    const t = cy - EGG_TOP * r;
    return `<path d="M${cx - 0.74 * r} ${cy + 0.05 * r} C${cx - 0.84 * r} ${cy - 0.5 * r} ${cx - 0.62 * r} ${t + 0.42 * r} ${cx - 0.24 * r} ${t + 0.1 * r}" fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round" opacity="${o}"/>` +
      dot(cx - 0.76 * r, cy + 0.26 * r, 1.8, o);
  }
  // the crown on an egg's tip: two points leaning out, a taller middle one, a white-hot core
  function eggCrown(cx, top, side, mid) {
    let s = g(dia(0, 0, 9, 15, side, 3.5), `translate(${cx - 7.5} ${top - 1}) rotate(-28)`);
    s += g(dia(0, 0, 9, 15, side, 3.5), `translate(${cx + 7.5} ${top - 1}) rotate(28)`);
    return s + dia(cx, top - 5, 12, 19, mid, 3.5) + dia(cx, top - 3, 5, 7, "#fff8d8", 2.2);
  }

  // capsule_Royal: THE ROYAL EGG (divine): a pearl shell on its gold foot with a row of gold
  // scales, the red gem in a gold frame, gold light running down from a crown on its tip, angel
  // wings, a gold halo, clouds at its foot (its gold claw is gold on gold: not drawn)
  D.capsule_Royal = () => {
    const cx = 64, cy = 80, r = 34, t = cy - EGG_TOP * r;
    let s = "";
    // the clouds at its foot, to the sides (the round bottom stays clear)
    s += E(cx - 34, cy + 29, 10, 7, C("cloud"), 4) + E(cx + 35, cy + 27, 9, 6.5, C("cloud"), 4);
    // angel wings on its sides: a gold feather over two pearl ones
    for (const m of [-1, 1]) {
      const x = cx + m * 28;
      s += g(E(0, 0, 13, 5.5, C("pearl"), 4), `translate(${x + m * 13} ${cy - 6}) rotate(${m * 12})`);
      s += g(E(0, 0, 16, 6, C("pearl"), 4), `translate(${x + m * 15} ${cy - 15}) rotate(${m * -10})`);
      s += g(E(0, 0, 17, 6.5, C("gold"), 4), `translate(${x + m * 13} ${cy - 25}) rotate(${m * -32})`);
    }
    // the shell, its gold foot, the glowing band and the scales
    s += P(eggPath(cx, cy, r), C("eggPearl"), 5);
    s += P(eggLow(cx, cy, r, cy + 8), C("eggGold"), 4.5);
    s += eggBand(cx, cy, r, cy + 3, 5.5, C("paleGold"));
    for (const x of [-16, -8, 0, 8, 16]) s += dia(cx + x, cy + 16, 7, 8, C("paleGold"), 2.5);
    // gold light running down from the crown, the emblem: a gold frame, the red gem, a sparkle
    s += stream(cx, cy, r, -1, "#ffd24a", C("gold")) + stream(cx, cy, r, 1, "#ffd24a", C("gold"));
    s += dia(cx, cy - 18, 24, 26, C("eggGold"), 4) + dia(cx, cy - 18, 15, 17, C("iris"), 3);
    s += star4(cx - 1, cy - 20, 3.8, "#ffffff", 1.8);
    s += gloss(cx, cy, r);
    // the crown on its tip and the gold halo over it
    s += eggCrown(cx, t - 1, C("gold"), C("paleGold"));
    s += `<ellipse cx="${cx}" cy="${t - 19}" rx="16" ry="3.8" fill="none" stroke="${O}" stroke-width="${hs(8.5)}"/>`;
    if (!HALO) s += `<ellipse cx="${cx}" cy="${t - 19}" rx="16" ry="3.8" fill="none" stroke="#ffd84a" stroke-width="3.8"/>`;
    s += E(cx + 3, cy + r + 3, 9, 5, C("cloud"), 3.5);
    return s;
  };

  // capsule_Dragonforge: THE DRAGONFORGE SHARD (a dragon egg): a dark volcanic shell, lava running
  // down from a crown of flame and round its waist, a row of scales, the dragon's eye in a gold
  // frame, ivory horns, obsidian spikes and fire crystals breaking out, held in a gold claw over
  // volcanic rocks on a pool of lava
  D.capsule_Dragonforge = () => {
    const cx = 64, cy = 79, r = 35, t = cy - EGG_TOP * r;
    const lava = "#ff7a1e";
    let s = "";
    // the lava pool and the rocks round its foot
    s += E(cx, cy + r + 2, 40, 6.5, C("lava"), 4);
    s += P(`M${cx - 41} ${cy + 35} L${cx - 38} ${cy + 25} L${cx - 28} ${cy + 24} L${cx - 23} ${cy + 34} Z`, C("rock"), 3.5);
    s += P(`M${cx + 24} ${cy + 34} L${cx + 29} ${cy + 24} L${cx + 38} ${cy + 25} L${cx + 42} ${cy + 35} Z`, C("rock"), 3.5);
    // obsidian spikes and fire crystals breaking out of its sides
    s += P(`M${cx - 27} ${cy - 18} L${cx - 55} ${cy - 31} L${cx - 52} ${cy - 23} L${cx - 24} ${cy - 6} Z`, C("obsidian"), 4);
    s += P(`M${cx - 55} ${cy - 31} L${cx - 46} ${cy - 28} L${cx - 52} ${cy - 23} Z`, C("rock"), 2.5);
    s += P(`M${cx + 27} ${cy - 10} L${cx + 56} ${cy - 21} L${cx + 52} ${cy - 13} L${cx + 24} ${cy + 2} Z`, C("obsidian"), 4);
    s += P(`M${cx + 56} ${cy - 21} L${cx + 47} ${cy - 18} L${cx + 52} ${cy - 13} Z`, C("rock"), 2.5);
    s += g(dia(0, 0, 12, 24, C("flame"), 3.5), `translate(${cx - 31} ${cy + 1}) rotate(-38)`);
    s += g(dia(0, 0, 10, 20, C("flameHot"), 3.5), `translate(${cx + 32} ${cy + 9}) rotate(42)`);
    // the ivory horns on top
    s += P(`M${cx - 13} ${t + 9} L${cx - 25} ${t - 13} L${cx - 6} ${t + 3} Z`, C("ivory"), 3.5);
    s += P(`M${cx + 13} ${t + 9} L${cx + 25} ${t - 13} L${cx + 6} ${t + 3} Z`, C("ivory"), 3.5);
    // the shell, its darker lower part, the lava band, the scales
    s += P(eggPath(cx, cy, r), C("dragonShell"), 5);
    s += P(eggLow(cx, cy, r, cy + 8), C("dragonLow"), 4.5);
    s += eggBand(cx, cy, r, cy + 3, 5.5, C("lava"));
    for (const x of [-16, -8, 0, 8, 16]) s += dia(cx + x, cy + 16, 7, 8, C("dragonScale"), 2.5);
    // the gold claw: two talons gripping its bottom, ivory tips
    s += talon(cx, cy, r, -1, C("gold"), C("ivory")) + talon(cx, cy, r, 1, C("gold"), C("ivory"));
    // three streams of lava running down from the crown, each with a drip
    s += stream(cx, cy, r, -1, lava, C("lava"), 3.3) + stream(cx, cy, r, 1, lava, C("lava"), 3.3);
    s += line(`M${cx + 1} ${t + 6} C${cx + 3} ${t + 12} ${cx + 4} ${t + 16} ${cx + 4} ${t + 20}`, 3.3, lava, 3.5) + E(cx + 4, t + 22, 2.8, 2.8, C("lava"), 3);
    // the dragon's eye: a gold frame, the glowing iris, the slit pupil
    s += dia(cx, cy - 16, 23, 25, C("gold"), 4) + dia(cx, cy - 16, 15, 17, C("flameHot"), 3);
    if (!HALO) s += `<rect x="${cx - 1.7}" y="${cy - 23.5}" width="3.4" height="15" rx="1.7" fill="#2a120e"/>`;
    s += gloss(cx, cy, r, 0.5);
    // the crown of flame on its tip
    s += eggCrown(cx, t - 1, C("flame"), C("flameHot"));
    return s;
  };

  const BOX = [-13, -11, 154, 154]; // the viewBox: x, y, width, height

  window.GOLEMS = {
    defs,
    box: BOX,
    names: Object.keys(D),
    icon(name, size = 128, extra = "") {
      if (!D[name]) return "";
      HALO = true;
      const halo = D[name]();
      HALO = false;
      const inner = D[name]();
      // the silhouette in the outline colour under the picture, and again a little lower (the drop);
      // one square box for all (the same scale for every golem): the widest wings and the highest
      // horns stay inside it with their outline and drop
      return `<svg class="gico" viewBox="${BOX.join(" ")}" width="${size}" height="${size}" ${extra}>` +
        `<g transform="translate(0 4.5)">${halo}</g>${halo}${inner}</svg>`;
    },
    css: `.gico { overflow: visible; }`,
  };
})();
