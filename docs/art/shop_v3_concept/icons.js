// Terra Forge UI icons, drawn in code (SVG) in the chunky sticker style the owner showed
// (2026-11-11, the Gvesster icon pack look): a thick dark outline, a lit side and a
// shaded side (hard "cel" step), white shine marks and a darker drop under the outline.
// Every icon lives in a 100 x 100 box. icon(name) returns an <svg> string.
// Nothing here is copied from a pack: the shapes are our own.

(function () {
  const O = "#221a3d"; // the outline colour
  // [lit, shade] pairs: the cel gradients (radial, a hard step: the shade is a crescent
  // on the bottom-right of every shape)
  const PAL = {
    green: ["#6ee854", "#2fae3a"],
    leaf: ["#7cf05a", "#34b83c"],
    lime: ["#b8f55e", "#62c43a"],
    cash: ["#8ff07a", "#3fae4a"],
    gold: ["#ffe05a", "#f2a21c"],
    orange: ["#ffb03e", "#e2651e"],
    red: ["#ff6262", "#cf2a3a"],
    pink: ["#ff86c2", "#e2408e"],
    magenta: ["#ff6ad8", "#c42aa8"],
    purple: ["#b98cff", "#7a44e0"],
    violet: ["#9a6cff", "#5a2ec8"],
    blue: ["#5cc0ff", "#2a74e0"],
    cyan: ["#7ff4ff", "#22b6e2"],
    teal: ["#5ff0c8", "#1aa88e"],
    brown: ["#d4945a", "#8e5428"],
    tan: ["#f4d08a", "#c98f44"],
    grey: ["#eef1f8", "#aab4c9"],
    steel: ["#c9d3e6", "#7f8aa6"],
    white: ["#ffffff", "#d9def0"],
    paper: ["#fffbe8", "#e8d9a8"],
    dark: ["#5a5486", "#34305a"],
    navy: ["#4a5ad8", "#2a2e9a"],
    flame: ["#ffd84a", "#ff7a1e"],
    ember: ["#ff7a2a", "#d92a1e"],
  };

  // the shared <defs>: put once in the page (ICONS.defs())
  function defs() {
    let s = "";
    for (const [k, [a, b]] of Object.entries(PAL)) {
      s += `<radialGradient id="cel-${k}" cx="0.36" cy="0.3" r="0.82"><stop offset="0.7" stop-color="${a}"/><stop offset="0.7" stop-color="${b}"/></radialGradient>`;
      s += `<linearGradient id="lin-${k}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;
    }
    // the sticker outline for the game's 3D pictures (CSS: filter:url(#stk))
    s += `<filter id="stk" x="-20%" y="-20%" width="140%" height="150%">
      <feMorphology in="SourceAlpha" operator="dilate" radius="3.2" result="d"/>
      <feFlood flood-color="${O}"/><feComposite in2="d" operator="in" result="o"/>
      <feOffset in="o" dy="4" result="o2"/>
      <feMerge><feMergeNode in="o2"/><feMergeNode in="o"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`;
    s += `<filter id="stkw" x="-20%" y="-20%" width="140%" height="150%">
      <feMorphology in="SourceAlpha" operator="dilate" radius="2.4" result="d0"/>
      <feFlood flood-color="#ffffff"/><feComposite in2="d0" operator="in" result="w"/>
      <feMorphology in="SourceAlpha" operator="dilate" radius="5.5" result="d"/>
      <feFlood flood-color="${O}"/><feComposite in2="d" operator="in" result="o"/>
      <feOffset in="o" dy="4" result="o2"/>
      <feMerge><feMergeNode in="o2"/><feMergeNode in="o"/><feMergeNode in="w"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`;
    return `<svg width="0" height="0" style="position:absolute"><defs>${s}</defs></svg>`;
  }

  // rotate absolute path data (M L C Q Z only) by deg around (cx, cy)
  function rot(d, deg, cx = 50, cy = 50) {
    const a = (deg * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
    const nums = d.match(/-?\d*\.?\d+/g).map(Number);
    let i = 0;
    return d.replace(/-?\d*\.?\d+\s*,?\s*-?\d*\.?\d+/g, () => {
      const x = nums[i++] - cx, y = nums[i++] - cy;
      return `${(cx + x * c - y * s).toFixed(1)} ${(cy + x * s + y * c).toFixed(1)}`;
    });
  }

  const P = (d, fill, extra = "") => `<path d="${d}" fill="${fill}" stroke="${O}" stroke-width="7" stroke-linejoin="round" stroke-linecap="round" paint-order="stroke" ${extra}/>`;
  const C = (k) => `url(#cel-${k})`;
  const L = (k) => `url(#lin-${k})`;
  const shine = (x, y, w = 10, h = 6, r = -30) => `<ellipse cx="${x}" cy="${y}" rx="${w}" ry="${h}" fill="#fff" opacity="0.9" transform="rotate(${r} ${x} ${y})"/>`;
  const dot = (x, y, r = 3) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff" opacity="0.9"/>`;
  const line = (d, w, col) => `<path d="${d}" fill="none" stroke="${O}" stroke-width="${w + 7}" stroke-linecap="round" stroke-linejoin="round"/><path d="${d}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
  const txt = (x, y, t, size, fill, sw = 5) => `<text x="${x}" y="${y}" text-anchor="middle" font-family="Fredoka, sans-serif" font-size="${size}" fill="${fill}" stroke="${O}" stroke-width="${sw}" paint-order="stroke" stroke-linejoin="round">${t}</text>`;

  const circ = (cx, cy, r) => `M${cx - r} ${cy} A ${r} ${r} 0 1 1 ${cx + r} ${cy} A ${r} ${r} 0 1 1 ${cx - r} ${cy} Z`;
  const leaf = "M50 50 C 43 45 24 40 25 23 C 26 10 43 8 50 21 C 57 8 74 10 75 23 C 76 40 57 45 50 50 Z";
  function clover(cols) {
    const c = cols || ["leaf", "leaf", "leaf", "leaf"];
    let s = line("M52 56 C 55 72 60 82 70 93", 7, "#3cb43a");
    [-45, 45, 135, 225].forEach((deg, i) => { s += P(rot(leaf, deg), C(c[i])); });
    // veins: a light line down every leaf
    [-45, 45, 135, 225].forEach((deg) => {
      s += `<path d="${rot("M50 46 L 50 26", deg)}" stroke="#fff" stroke-opacity="0.45" stroke-width="3" stroke-linecap="round"/>`;
    });
    s += `<circle cx="50" cy="50" r="5" fill="${PAL.leaf[1]}"/>`;
    s += shine(30, 26, 7, 4, -45) + dot(40, 18, 2.6) + shine(70, 27, 5, 3, 45);
    return s;
  }

  const bill = (x, y, w, h, deg) => {
    const g = `transform="rotate(${deg} ${x + w / 2} ${y + h / 2})"`;
    return `<g ${g}>${P(`M${x + 5} ${y} L ${x + w - 5} ${y} Q ${x + w} ${y} ${x + w} ${y + 5} L ${x + w} ${y + h - 5} Q ${x + w} ${y + h} ${x + w - 5} ${y + h} L ${x + 5} ${y + h} Q ${x} ${y + h} ${x} ${y + h - 5} L ${x} ${y + 5} Q ${x} ${y} ${x + 5} ${y} Z`, C("cash"))}
      <rect x="${x + 6}" y="${y + 6}" width="${w - 12}" height="${h - 12}" rx="4" fill="none" stroke="#2a8a3a" stroke-width="2.5" opacity="0.7"/>
      <circle cx="${x + w / 2}" cy="${y + h / 2}" r="${h * 0.26}" fill="#c9ffb0" stroke="#2a8a3a" stroke-width="2.5"/>
      <text x="${x + w / 2}" y="${y + h / 2 + h * 0.15}" text-anchor="middle" font-family="Fredoka" font-size="${h * 0.42}" fill="#2a8a3a">$</text></g>`;
  };

  const I = {
    clover: () => clover(),
    clover_rainbow: () => clover(["pink", "gold", "cyan", "purple"]),
    clover_gold: () => clover(["gold", "gold", "gold", "gold"]),

    cash: () => bill(8, 44, 84, 46, 8) + bill(8, 34, 84, 46, -4) +
      `<g>${bill(10, 22, 80, 46, -10)}</g>` +
      P("M44 18 L 58 16 L 64 66 L 50 68 Z", C("gold"), 'transform="rotate(-10 52 42)"') + shine(24, 28, 8, 3, -10),

    coin: () => P("M50 8 A 42 42 0 1 1 49.9 8 Z", C("gold")) +
      `<circle cx="50" cy="50" r="30" fill="none" stroke="#c97a10" stroke-width="4" opacity="0.8"/>` +
      txt(50, 66, "$", 44, "#fff3a0", 6) + shine(30, 26, 9, 5, -40) + dot(22, 40, 3),

    coins: () => P(circ(64, 38, 27), C("gold")) + `<circle cx="64" cy="38" r="18" fill="none" stroke="#c97a10" stroke-width="3" opacity="0.8"/>` + txt(64, 50, "$", 30, "#fff3a0", 5) +
      P(circ(36, 64, 30), C("gold")) + `<circle cx="36" cy="64" r="20" fill="none" stroke="#c97a10" stroke-width="3" opacity="0.8"/>` + txt(36, 77, "$", 34, "#fff3a0", 5) +
      shine(24, 48, 6, 3, -40) + shine(54, 20, 5, 3, -40),

    bag: () => P("M36 30 C 14 46 10 92 50 92 C 90 92 86 46 64 30 Z", C("tan")) +
      P("M34 12 L 44 26 L 56 26 L 66 12 C 58 16 42 16 34 12 Z", C("tan")) +
      P("M34 26 Q 50 34 66 26 L 66 33 Q 50 41 34 33 Z", C("red")) +
      txt(50, 80, "$", 40, "#5fe04a", 6) + shine(30, 52, 7, 12, 20),

    chest: () => P("M10 48 L 90 48 L 90 88 Q 90 92 86 92 L 14 92 Q 10 92 10 88 Z", C("brown")) +
      P("M10 48 C 10 18 90 18 90 48 Z", C("orange")) +
      P("M20 48 L 20 92 L 30 92 L 30 48 Z", C("gold")) + P("M70 48 L 70 92 L 80 92 L 80 48 Z", C("gold")) +
      P("M8 44 L 92 44 L 92 54 L 8 54 Z", C("gold")) +
      P("M41 46 L 59 46 L 59 66 Q 50 72 41 66 Z", C("grey")) + `<circle cx="50" cy="56" r="3.5" fill="${O}"/>` +
      shine(30, 32, 10, 4, -10) + `<g opacity="0.9">${dot(64, 30, 2.4)}</g>`,

    gift: () => P("M14 46 L 86 46 L 86 90 Q 86 94 82 94 L 18 94 Q 14 94 14 90 Z", C("purple")) +
      P("M8 32 L 92 32 L 92 50 L 8 50 Z", C("violet")) +
      P("M42 32 L 58 32 L 58 94 L 42 94 Z", C("gold")) +
      P("M50 30 C 30 4 10 20 30 30 Z", C("gold")) + P("M50 30 C 70 4 90 20 70 30 Z", C("gold")) +
      P("M44 24 L 56 24 L 56 34 L 44 34 Z", C("orange")) + shine(24, 60, 5, 10, 0) + dot(22, 40, 2.6),

    basket: () => line("M26 46 C 26 6 74 6 74 46", 7, "#ff9ab0") +
      P("M8 40 L 92 40 L 84 90 Q 83 94 78 94 L 22 94 Q 17 94 16 90 Z", C("red")) +
      P("M4 34 L 96 34 L 96 46 L 4 46 Z", C("pink")) +
      `<path d="M30 52 L 33 86 M50 52 L 50 86 M70 52 L 67 86" stroke="#8e1424" stroke-width="5" stroke-linecap="round" opacity="0.55"/>` +
      shine(18, 38, 8, 2.5, 0) + shine(24, 60, 3, 9, -8),

    ticket: () => `<g transform="rotate(-14 50 50)">` +
      P("M8 26 L 92 26 L 92 40 Q 82 50 92 60 L 92 74 L 8 74 L 8 60 Q 18 50 8 40 Z", C("gold")) +
      `<path d="M66 30 L 66 70" stroke="#c97a10" stroke-width="3" stroke-dasharray="5 5"/>` +
      P("M38 36 L 41 45 L 51 45 L 43 51 L 46 61 L 38 55 L 30 61 L 33 51 L 25 45 L 35 45 Z", C("orange"), 'stroke-width="5"') +
      shine(20, 32, 8, 3, 0) + `</g>`,

    crown: () => P("M10 34 L 30 56 L 50 22 L 70 56 L 90 34 L 82 82 L 18 82 Z", C("gold")) +
      P("M16 74 L 84 74 L 82 90 L 18 90 Z", C("orange")) +
      P("M45 52 L 50 44 L 55 52 L 50 60 Z", C("red"), 'stroke-width="4"') +
      `<circle cx="10" cy="30" r="7" fill="${C("gold")}" stroke="${O}" stroke-width="6" paint-order="stroke"/>` +
      `<circle cx="50" cy="16" r="7" fill="${C("gold")}" stroke="${O}" stroke-width="6" paint-order="stroke"/>` +
      `<circle cx="90" cy="30" r="7" fill="${C("gold")}" stroke="${O}" stroke-width="6" paint-order="stroke"/>` +
      `<circle cx="30" cy="70" r="4.5" fill="${C("blue")}" stroke="${O}" stroke-width="4" paint-order="stroke"/><circle cx="70" cy="70" r="4.5" fill="${C("blue")}" stroke="${O}" stroke-width="4" paint-order="stroke"/>` +
      shine(26, 50, 3, 7, -30) + dot(8, 28, 2),

    bolt: () => P("M60 4 L 20 56 L 46 56 L 36 96 L 80 38 L 54 38 L 68 4 Z", C("gold")) + shine(46, 22, 3, 9, 35) + dot(40, 34, 2.5),
    bolt_cyan: () => P("M60 4 L 20 56 L 46 56 L 36 96 L 80 38 L 54 38 L 68 4 Z", C("cyan")) + shine(46, 22, 3, 9, 35) + dot(40, 34, 2.5),

    star: () => P("M50 6 L 62 36 L 94 38 L 69 58 L 78 90 L 50 72 L 22 90 L 31 58 L 6 38 L 38 36 Z", C("gold"), 'stroke-width="8"') + shine(40, 34, 4, 9, 30) + dot(50, 22, 2.6),

    egg: () => P("M50 6 C 76 6 90 46 90 62 C 90 84 72 96 50 96 C 28 96 10 84 10 62 C 10 46 24 6 50 6 Z", C("white")) +
      `<circle cx="34" cy="62" r="8" fill="${PAL.purple[0]}"/><circle cx="64" cy="44" r="6" fill="${PAL.purple[0]}"/><circle cx="62" cy="76" r="9" fill="${PAL.pink[0]}"/><circle cx="44" cy="30" r="4.5" fill="${PAL.pink[0]}"/>` +
      shine(30, 32, 5, 11, 25),

    wheel: () => {
      const cols = ["#ff5a6a", "#ffd84a", "#5fe04a", "#4ab4ff", "#b07aff", "#ff8a3a", "#5ff0ff", "#ff6ad8"];
      let s = P("M50 8 A 42 42 0 1 1 49.9 8 Z", "#fff");
      cols.forEach((c, i) => {
        const a0 = (i * 45 - 90) * Math.PI / 180, a1 = ((i + 1) * 45 - 90) * Math.PI / 180;
        s += `<path d="M50 52 L ${50 + 36 * Math.cos(a0)} ${52 + 36 * Math.sin(a0)} A 36 36 0 0 1 ${50 + 36 * Math.cos(a1)} ${52 + 36 * Math.sin(a1)} Z" fill="${c}" stroke="${O}" stroke-width="2.5"/>`;
      });
      s += `<circle cx="50" cy="52" r="9" fill="${C("gold")}" stroke="${O}" stroke-width="5"/>`;
      s += P("M42 2 L 58 2 L 50 18 Z", C("red"), 'stroke-width="5"');
      return s.replace('M50 8 A 42 42 0 1 1 49.9 8 Z', 'M50 10 A 42 42 0 1 1 49.9 10 Z') + shine(30, 28, 6, 3, -40);
    },

    potion: () => P("M40 10 L 60 10 L 60 34 C 82 42 88 62 82 76 C 76 92 24 92 18 76 C 12 62 18 42 40 34 Z", C("white")) +
      `<path d="M21 60 C 30 54 70 66 80 58 C 84 70 80 84 70 88 C 58 92 42 92 30 88 C 20 84 18 72 21 60 Z" fill="${C("magenta")}"/>` +
      P("M36 4 L 64 4 L 64 14 L 36 14 Z", C("brown")) +
      `<circle cx="42" cy="72" r="4" fill="#fff" opacity="0.7"/><circle cx="56" cy="78" r="2.6" fill="#fff" opacity="0.7"/><circle cx="62" cy="68" r="3" fill="#fff" opacity="0.6"/>` +
      shine(30, 52, 4, 10, 20),

    clock: () => P("M44 4 L 56 4 L 56 14 L 44 14 Z", C("red")) + P("M50 14 A 40 40 0 1 1 49.9 14 Z", C("white")) +
      `<circle cx="50" cy="54" r="31" fill="none" stroke="#c9d0e8" stroke-width="3"/>` +
      `<path d="M50 54 L 50 32 M50 54 L 66 62" stroke="${O}" stroke-width="6" stroke-linecap="round"/><circle cx="50" cy="54" r="5" fill="${PAL.red[0]}" stroke="${O}" stroke-width="3"/>` +
      shine(30, 34, 7, 4, -40),

    rebirth: () => line("M24 60 A 28 28 0 0 1 70 28", 11, PAL.magenta[0]) + P("M62 14 L 84 30 L 60 42 Z", C("magenta"), 'stroke-width="6"') +
      line("M76 42 A 28 28 0 0 1 30 74", 11, PAL.purple[0]) + P("M38 88 L 16 72 L 40 60 Z", C("purple"), 'stroke-width="6"') +
      `<circle cx="50" cy="51" r="9" fill="${C("gold")}" stroke="${O}" stroke-width="6" paint-order="stroke"/>`,

    book: () => P("M18 12 L 80 12 L 80 80 L 18 80 Z", C("blue")) + P("M18 80 L 80 80 L 86 92 L 24 92 Z", C("paper")) +
      P("M80 12 L 86 22 L 86 92 L 80 80 Z", C("paper")) + P("M18 12 L 28 12 L 28 80 L 18 80 Z", C("navy")) +
      P("M40 30 L 70 30 L 70 46 L 40 46 Z", C("gold"), 'stroke-width="5"') + shine(36, 60, 3, 10, 0),

    backpack: () => line("M36 24 C 36 6 64 6 64 24", 6, PAL.brown[1]) + P("M18 30 Q 18 20 30 20 L 70 20 Q 82 20 82 30 L 84 86 Q 84 94 76 94 L 24 94 Q 16 94 16 86 Z", C("orange")) +
      P("M28 58 L 72 58 L 72 84 Q 72 88 68 88 L 32 88 Q 28 88 28 84 Z", C("brown")) + P("M28 56 L 72 56 L 72 66 L 28 66 Z", C("orange")) +
      `<circle cx="50" cy="61" r="3.5" fill="${PAL.gold[0]}" stroke="${O}" stroke-width="3"/>` + shine(28, 34, 4, 8, 15),

    hammer: () => P("M44 40 L 56 40 L 60 94 L 40 94 Z", C("brown")) + P("M14 18 L 82 18 Q 92 18 92 28 L 92 40 L 14 40 Q 8 40 8 34 L 8 24 Q 8 18 14 18 Z", C("steel")) +
      P("M40 14 L 60 14 L 60 44 L 40 44 Z", C("dark")) + shine(22, 25, 8, 3, 0),

    moon: () => P("M64 8 C 30 10 16 52 34 76 C 50 96 82 92 94 70 C 64 80 40 52 64 8 Z", C("gold")) +
      P("M76 22 L 79 30 L 87 32 L 79 34 L 76 42 L 73 34 L 65 32 L 73 30 Z", "#fff", 'stroke-width="4"') + shine(36, 40, 4, 10, 20),

    gem: () => P("M24 12 L 76 12 L 94 38 L 50 94 L 6 38 Z", C("cyan")) +
      `<path d="M6 38 L 94 38 M24 12 L 36 38 L 50 94 L 64 38 L 76 12 M36 38 L 50 12 L 64 38" fill="none" stroke="#1a7fb0" stroke-width="3" stroke-linejoin="round" opacity="0.7"/>` +
      `<path d="M24 12 L 50 12 L 36 38 L 6 38 Z" fill="#fff" opacity="0.45"/>` + dot(26, 24, 3),

    fire: () => P("M50 4 C 64 24 88 36 84 64 C 80 88 64 96 50 96 C 32 96 16 84 16 62 C 16 46 28 38 32 26 C 40 36 40 44 46 48 C 46 32 44 18 50 4 Z", C("ember")) +
      `<path d="M50 40 C 60 54 72 62 68 78 C 64 90 36 92 32 78 C 30 66 42 62 44 52 C 48 58 50 50 50 40 Z" fill="${C("flame")}"/>` + shine(30, 56, 3, 8, 15),

    lock: () => line("M30 44 L 30 30 C 30 6 70 6 70 30 L 70 44", 8, PAL.steel[0]) + P("M14 42 L 86 42 Q 92 42 92 48 L 92 88 Q 92 94 86 94 L 14 94 Q 8 94 8 88 L 8 48 Q 8 42 14 42 Z", C("gold")) +
      P("M44 58 A 7 7 0 1 1 56 58 L 54 64 L 54 76 L 46 76 L 46 64 Z", O, 'stroke-width="0"') + shine(22, 52, 7, 3, 0),

    trophy: () => line("M24 26 C 4 26 6 54 30 54", 6, PAL.gold[1]) + line("M76 26 C 96 26 94 54 70 54", 6, PAL.gold[1]) +
      P("M20 10 L 80 10 L 76 44 C 72 62 58 66 50 66 C 42 66 28 62 24 44 Z", C("gold")) + P("M42 66 L 58 66 L 60 80 L 40 80 Z", C("orange")) +
      P("M26 80 L 74 80 L 76 94 L 24 94 Z", C("brown")) + P("M50 22 L 54 32 L 64 32 L 56 38 L 59 48 L 50 42 L 41 48 L 44 38 L 36 32 L 46 32 Z", "#fff", 'stroke-width="4"') + shine(30, 24, 3, 8, 10),

    sparkle: () => `<path d="M50 4 C 54 38 62 46 96 50 C 62 54 54 62 50 96 C 46 62 38 54 4 50 C 38 46 46 38 50 4 Z" fill="#fff"/>`,

    x2: () => P("M10 20 L 90 20 Q 96 20 96 26 L 96 74 Q 96 80 90 80 L 10 80 Q 4 80 4 74 L 4 26 Q 4 20 10 20 Z", C("red")) + txt(50, 66, "x2", 46, "#fff", 7),

    // a chunky toy blaster (the "Next Blaster" card): orange body, glowing cyan cell and muzzle
    blaster: () => P("M30 58 L 46 58 L 40 92 Q 39 96 34 96 L 22 96 Q 17 96 18 91 Z", C("dark")) +
      P("M8 34 Q 8 24 18 24 L 70 24 Q 78 24 80 30 L 82 36 L 92 36 Q 96 36 96 40 L 96 50 Q 96 54 92 54 L 82 54 L 80 60 Q 78 66 70 66 L 18 66 Q 8 66 8 56 Z", C("orange")) +
      P("M14 30 L 40 30 L 40 46 L 14 46 Z", C("red"), 'stroke-width="5"') +
      P("M48 30 L 72 30 Q 76 30 76 34 L 76 56 Q 76 60 72 60 L 48 60 Q 44 60 44 56 L 44 34 Q 44 30 48 30 Z", C("cyan"), 'stroke-width="5"') +
      `<path d="M52 38 L 68 38 M52 45 L 68 45 M52 52 L 68 52" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity="0.8"/>` +
      P("M90 32 L 98 32 L 98 58 L 90 58 Z", C("cyan"), 'stroke-width="5"') +
      P("M22 10 L 34 10 L 38 24 L 18 24 Z", C("dark"), 'stroke-width="5"') +
      shine(20, 28, 7, 2.5, 0) + dot(56, 34, 2.2),

    // Heartfire: a heart in flames
    heart_fire: () => P("M50 4 C 60 16 74 18 72 36 C 82 30 86 22 86 14 C 98 30 98 52 86 66 L 50 96 L 14 66 C 2 52 2 30 14 14 C 14 22 18 30 28 36 C 26 18 40 16 50 4 Z", C("ember")) +
      P("M50 40 C 58 26 82 28 82 48 C 82 64 64 74 50 86 C 36 74 18 64 18 48 C 18 28 42 26 50 40 Z", C("red")) +
      shine(32, 46, 6, 9, 30) + dot(40, 38, 2.4),

    // Starbreaker: a big star with a crack and shards flying off
    star_break: () => P("M50 6 L 62 36 L 94 38 L 69 58 L 78 90 L 50 72 L 22 90 L 31 58 L 6 38 L 38 36 Z", C("purple"), 'stroke-width="8"') +
      `<path d="M50 20 L 46 40 L 56 50 L 46 62 L 50 72" fill="none" stroke="${O}" stroke-width="4.5" stroke-linejoin="round" stroke-linecap="round"/>` +
      P("M84 8 L 92 14 L 86 20 Z", C("cyan"), 'stroke-width="4"') + P("M10 12 L 18 10 L 16 18 Z", C("pink"), 'stroke-width="4"') + P("M90 70 L 96 76 L 88 80 Z", C("gold"), 'stroke-width="4"') +
      shine(36, 40, 4, 8, 30) + dot(52, 26, 2.4),

    globe: () => P("M50 8 A 42 42 0 1 1 49.9 8 Z", C("blue")) +
      `<path d="M30 22 C 40 30 26 40 34 48 C 42 56 56 46 58 58 C 60 70 48 76 52 88 M70 18 C 64 28 74 34 84 36 M66 64 C 74 60 84 66 90 58" fill="none" stroke="${PAL.green[0]}" stroke-width="9" stroke-linecap="round"/>` +
      shine(30, 28, 8, 4, -40),

    users: () => P("M50 10 A 16 16 0 1 1 49.9 10 Z", C("gold")) + P("M18 92 C 18 56 82 56 82 92 Z", C("blue")) +
      P("M20 24 A 11 11 0 1 1 19.9 24 Z", C("gold"), 'transform="translate(-4 14)"') + P("M80 24 A 11 11 0 1 1 79.9 24 Z", C("gold"), 'transform="translate(4 14)"'),
  };

  window.ICONS = {
    defs,
    names: Object.keys(I),
    icon(name, size = 100, extra = "") {
      const inner = I[name] ? I[name]() : "";
      // the drop: the same picture in the outline colour, a little lower (the sticker's thick bottom edge)
      const drop = `<g transform="translate(0 5)" class="drop">${inner}</g>`;
      return `<svg class="ico" viewBox="-8 -8 116 120" width="${size}" height="${size * 120 / 116}" ${extra}>${drop}${inner}</svg>`;
    },
    css: `.ico .drop * { fill: ${O} !important; stroke: ${O} !important; opacity: 1 !important; }
          .ico .drop text { fill: ${O} !important; }`,
  };
})();
