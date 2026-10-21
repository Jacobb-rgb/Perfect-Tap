// Renders exported Roblox ScreenGuis as HTML (approximation of Roblox layout):
// UDim2 position/size, AnchorPoint, UIListLayout, UIGridLayout, UIPadding,
// UIScale, UICorner, UIStroke, UIGradient, TextScaled, AutomaticSize,
// UISizeConstraint. For preview images only.

const TOPBAR_INSET = 36;
const measureCanvas = document.createElement("canvas");
const measureCtx = measureCanvas.getContext("2d");

function rgba(hex, alpha = 1) {
  const r = parseInt(hex.slice(0, 2), 16);
  const g = parseInt(hex.slice(2, 4), 16);
  const b = parseInt(hex.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

function mulHex(a, b) {
  const out = [0, 2, 4].map((i) => Math.round((parseInt(a.slice(i, i + 2), 16) * parseInt(b.slice(i, i + 2), 16)) / 255));
  return out.map((v) => v.toString(16).padStart(2, "0")).join("");
}

function fontFamily(family) {
  if (!family) return "Fredoka One";
  if (family.includes("Luckiest")) return "Luckiest Guy";
  if (family.includes("ComicNeue")) return "Comic Neue Angular"; // Enum.Font.Cartoon
  return "Fredoka One";
}

const isGui = (n) => ["Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "CanvasGroup", "ViewportFrame"].includes(n.c);
const child = (n, cls) => (n.ch || []).find((c) => c.c === cls);

const LINE_HEIGHT = 1.05; // the text spans' line-height below

// Lines of `text` at the current measureCtx font, wrapped at maxW when `wrap` (Roblox breaks at "\n" too).
function textLines(text, maxW, wrap) {
  const out = [];
  for (const para of String(text).split("\n")) {
    if (!wrap) {
      out.push(para);
      continue;
    }
    let line = "";
    for (const word of para.split(/\s+/)) {
      const test = line ? line + " " + word : word;
      if (line && measureCtx.measureText(test).width > maxW) {
        out.push(line);
        line = word;
      } else line = test;
    }
    out.push(line);
  }
  return out;
}

// What an AutomaticSize node holds at size w x h: its text and its children (a
// list's run, else the furthest child edge), plus its padding.
function contentSize(node, w, h) {
  const pad = child(node, "UIPadding");
  const [pt, pr, pb, pl] = pad ? pad.p : [0, 0, 0, 0];
  const cw = Math.max(0, w - pl - pr);
  const chh = Math.max(0, h - pt - pb);
  let cx = 0;
  let cy = 0;
  if (node.text !== undefined && node.text !== "" && !node.scaled) {
    measureCtx.font = `${node.ts}px "${fontFamily(node.font)}"`;
    const lines = textLines(node.text, cw, node.wrap && !node.auto.includes("X"));
    cx = Math.max(...lines.map((l) => measureCtx.measureText(l).width));
    cy = lines.length * node.ts * LINE_HEIGHT;
  }
  const kids = (node.ch || []).filter((c) => isGui(c) && c.vis !== false);
  const list = child(node, "UIListLayout");
  if (list) {
    const vertical = list.dir === "Vertical";
    const gap = vertical ? list.pad[0] * chh + list.pad[1] : list.pad[0] * cw + list.pad[1];
    let main = gap * Math.max(0, kids.length - 1);
    let cross = 0;
    for (const k of kids) {
      const s = resolveSize(k, cw, chh);
      main += vertical ? s.h : s.w;
      cross = Math.max(cross, vertical ? s.w : s.h);
    }
    cx = Math.max(cx, vertical ? cross : main);
    cy = Math.max(cy, vertical ? main : cross);
  } else {
    for (const k of kids) {
      const s = resolveSize(k, cw, chh);
      cx = Math.max(cx, k.pos[0] * cw + k.pos[1] + (1 - k.anchor[0]) * s.w);
      cy = Math.max(cy, k.pos[2] * chh + k.pos[3] + (1 - k.anchor[1]) * s.h);
    }
  }
  return { w: cx + pl + pr, h: cy + pt + pb };
}

// A node's size in its parent: UDim2, grown by AutomaticSize (never below the
// set size, like Roblox), then held inside a UISizeConstraint.
function resolveSize(node, parentW, parentH) {
  const [xs, xo, ys, yo] = node.size;
  let w = parentW * xs + xo;
  let h = parentH * ys + yo;
  if (node.auto) {
    const content = contentSize(node, w, h);
    if (node.auto.includes("X")) w = Math.max(w, content.w);
    if (node.auto.includes("Y")) h = Math.max(h, content.h);
  }
  const limit = child(node, "UISizeConstraint");
  if (limit) {
    w = Math.min(Math.max(w, limit.min[0]), limit.max[0]);
    h = Math.min(Math.max(h, limit.min[1]), limit.max[1]);
  }
  return { w, h };
}

function fitText(text, font, maxW, maxH, wrap) {
  let lo = 4, hi = 100;
  const fits = (size) => {
    measureCtx.font = `${size}px "${font}"`;
    if (!wrap) return measureCtx.measureText(text).width <= maxW && size * 1.05 <= maxH;
    // naive wrap estimate
    const words = text.split(/\s+/);
    let lines = 1, line = "";
    for (const w of words) {
      const test = line ? line + " " + w : w;
      if (measureCtx.measureText(test).width > maxW && line) {
        lines++;
        line = w;
      } else line = test;
    }
    return lines * size * 1.1 <= maxH;
  };
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (fits(mid)) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

// A UIGradient's CSS stops: its colour keys times `base`, its transparency keys times `alpha`.
function gradientStops(grad, base, alpha) {
  const lerp = (keys, t, mix) => {
    if (t <= keys[0][0]) return keys[0][1];
    for (let i = 1; i < keys.length; i++) {
      if (t <= keys[i][0]) {
        const [t0, v0] = keys[i - 1];
        const [t1, v1] = keys[i];
        return mix(v0, v1, (t - t0) / Math.max(1e-6, t1 - t0));
      }
    }
    return keys[keys.length - 1][1];
  };
  const mixHex = (a, b, f) =>
    [0, 2, 4].map((i) => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - f) + parseInt(b.slice(i, i + 2), 16) * f).toString(16).padStart(2, "0")).join("");
  const fades = grad.tkeys && grad.tkeys.length >= 2 ? grad.tkeys : [[0, 0], [1, 0]];
  const times = [...new Set([...grad.keys.map((k) => k[0]), ...fades.map((k) => k[0])])].sort((a, b) => a - b);
  return times
    .map((t) => {
      const c = lerp(grad.keys, t, mixHex);
      const tr = lerp(fades, t, (a, b, f) => a + (b - a) * f);
      return `${rgba(mulHex(base, c), alpha * (1 - tr))} ${t * 100}%`;
    })
    .join(", ");
}

function styleElement(el, node, w, h) {
  const corner = child(node, "UICorner");
  if (corner) {
    const r = Math.min(corner.r[0] * Math.min(w, h) + corner.r[1], Math.min(w, h) / 2);
    el.style.borderRadius = `${r}px`;
  }
  const isText = node.text !== undefined;
  if (node.bgt < 0.999) {
    const grad = child(node, "UIGradient");
    if (grad && grad.keys && grad.keys.length >= 2) {
      el.style.backgroundImage = `linear-gradient(${grad.rot + 90}deg, ${gradientStops(grad, node.bg, 1 - node.bgt)})`;
    } else {
      el.style.backgroundColor = rgba(node.bg, 1 - node.bgt);
    }
  }
  for (const s of (node.ch || []).filter((c) => c.c === "UIStroke")) {
    const contextualText = isText && s.mode === "Contextual";
    if (!contextualText && s.t < 0.999) {
      const sg = child(s, "UIGradient");
      if (sg && sg.keys && sg.keys.length >= 2) {
        // a gradient stroke (UIStroke > UIGradient): a ring painted with the gradient
        const ring = document.createElement("div");
        const r = parseFloat(el.style.borderRadius || "0");
        ring.style.cssText = `position:absolute;inset:${-s.th}px;padding:${s.th}px;border-radius:${r + s.th}px;pointer-events:none;z-index:${(node.z || 1) + 1};`;
        ring.style.backgroundImage = `linear-gradient(${sg.rot + 90}deg, ${gradientStops(sg, s.col, 1 - s.t)})`;
        ring.style.webkitMask = "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)";
        ring.style.webkitMaskComposite = "xor";
        ring.style.maskComposite = "exclude";
        el.appendChild(ring);
      } else {
        el.style.boxShadow = `0 0 0 ${s.th}px ${rgba(s.col, 1 - s.t)}`;
      }
    }
  }
  if (node.icon && node.tile) {
    // a repeating texture (ScaleType Tile, TileSize in px)
    const t = document.createElement("div");
    t.style.cssText = `position:absolute;inset:0;background:url(/scenes/icons/${node.icon}.png) 0 0/${node.tile}px ${node.tile}px repeat;opacity:${1 - (node.it || 0)};border-radius:inherit;`;
    el.appendChild(t);
  } else if (node.icon) {
    // 3D UI icon (tools/preview/render_icons.mjs output), ScaleType Fit
    if (node.ic && node.ic !== "ffffff") {
      // ImageColor3 tints the picture (Roblox multiplies; a flat tint is close enough here)
      const tint = document.createElement("div");
      const url = `url(/scenes/icons/${node.icon}.png)`;
      tint.style.cssText = `position:absolute;inset:0;background:${rgba(node.ic, 1 - (node.it || 0))};-webkit-mask:${url} center/contain no-repeat;mask:${url} center/contain no-repeat;`;
      el.appendChild(tint);
    } else {
      const img = document.createElement("img");
      img.src = `/scenes/icons/${node.icon}.png`;
      img.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:contain;";
      img.style.opacity = String(1 - (node.it || 0));
      el.appendChild(img);
    }
  }
  if (node.rot) el.style.transform = `rotate(${node.rot}deg)`;
  if (node.clip) el.style.overflow = "hidden";
  el.style.zIndex = String(node.z ?? 1);

  if (isText && node.text !== "") {
    const span = document.createElement("div");
    const font = fontFamily(node.font);
    span.style.position = "absolute";
    // (Roblox insets a text by its UIPadding)
    const textPad = child(node, "UIPadding");
    span.style.inset = textPad ? textPad.p.map((v) => `${v}px`).join(" ") : "0";
    span.style.display = "flex";
    span.style.alignItems = node.ty === "Top" ? "flex-start" : node.ty === "Bottom" ? "flex-end" : "center";
    span.style.justifyContent = node.tx === "Left" ? "flex-start" : node.tx === "Right" ? "flex-end" : "center";
    span.style.textAlign = node.tx === "Left" ? "left" : node.tx === "Right" ? "right" : "center";
    span.style.fontFamily = `"${font}"`;
    let size = node.scaled ? fitText(node.text, font, w, h, node.wrap) : node.ts;
    // UITextSizeConstraint on a scaled label: Roblox keeps the fitted size within it
    if (node.scaled && node.maxts) size = Math.min(size, node.maxts);
    if (node.scaled && node.mints) size = Math.max(size, node.mints);
    span.style.fontSize = `${size}px`;
    span.style.lineHeight = String(LINE_HEIGHT);
    span.style.color = rgba(node.tc, 1 - node.tt);
    // Roblox always breaks lines at "\n" (wrapped or not)
    span.style.whiteSpace = node.wrap ? "pre-line" : "pre";
    const stroke = (node.ch || []).find((c) => c.c === "UIStroke" && c.mode === "Contextual");
    if (stroke && node.tt < 0.99 && stroke.t < 0.99) {
      span.style.webkitTextStroke = `${stroke.th * 2}px ${rgba(stroke.col, (1 - stroke.t) * (1 - node.tt))}`;
      span.style.paintOrder = "stroke fill";
    }
    span.textContent = node.text;
    const textGrad = child(node, "UIGradient");
    if (textGrad && textGrad.keys && textGrad.keys.length >= 2 && node.tt < 0.99) {
      // a gradient on text colours the glyphs; the stroke stays outside them (a copy underneath)
      if (span.style.webkitTextStroke) {
        const under = span.cloneNode(true);
        under.style.color = "transparent";
        el.appendChild(under);
        span.style.webkitTextStroke = "";
      }
      const inner = document.createElement("span");
      inner.textContent = node.text;
      inner.style.backgroundImage = `linear-gradient(${textGrad.rot + 90}deg, ${gradientStops(textGrad, node.tc, 1 - node.tt)})`;
      inner.style.webkitBackgroundClip = "text";
      inner.style.backgroundClip = "text";
      inner.style.color = "transparent";
      span.textContent = "";
      span.appendChild(inner);
    }
    el.appendChild(span);
  }
}

function layoutChildren(node, el, w, h) {
  const kids = (node.ch || []).filter((c) => isGui(c) && c.vis !== false);
  const pad = child(node, "UIPadding");
  const [pt, pr, pb, pl] = pad ? pad.p : [0, 0, 0, 0];
  const cw = w - pl - pr;
  const ch = h - pt - pb;
  const list = child(node, "UIListLayout");
  const grid = child(node, "UIGridLayout");
  const placed = [];
  if (list) {
    const vertical = list.dir === "Vertical";
    const gap = vertical ? list.pad[0] * ch + list.pad[1] : list.pad[0] * cw + list.pad[1];
    const sorted = kids.map((k, i) => ({ k, i })).sort((a, b) => (a.k.lo - b.k.lo) || (a.i - b.i)).map((x) => x.k);
    const sizes = sorted.map((k) => resolveSize(k, cw, ch));
    const total = sizes.reduce((s, sz) => s + (vertical ? sz.h : sz.w), 0) + gap * Math.max(0, sorted.length - 1);
    let cursor;
    const mainAlign = vertical ? list.va : list.ha;
    const mainLen = vertical ? ch : cw;
    if (mainAlign === "Center") cursor = (mainLen - total) / 2;
    else if (mainAlign === "Bottom" || mainAlign === "Right") cursor = mainLen - total;
    else cursor = 0;
    sorted.forEach((k, i) => {
      const sz = sizes[i];
      let x, y;
      if (vertical) {
        y = cursor;
        x = list.ha === "Center" ? (cw - sz.w) / 2 : list.ha === "Right" ? cw - sz.w : 0;
        cursor += sz.h + gap;
      } else {
        x = cursor;
        y = list.va === "Center" ? (ch - sz.h) / 2 : list.va === "Bottom" ? ch - sz.h : 0;
        cursor += sz.w + gap;
      }
      placed.push({ k, x: x + pl, y: y + pt, w: sz.w, h: sz.h });
    });
  } else if (grid) {
    const cellW = grid.cell[0] * cw + grid.cell[1];
    const cellH = grid.cell[2] * ch + grid.cell[3];
    const gapX = grid.cpad[0] * cw + grid.cpad[1];
    const gapY = grid.cpad[2] * ch + grid.cpad[3];
    const perRow = Math.max(1, Math.floor((cw + gapX) / (cellW + gapX)));
    const sorted = kids.map((k, i) => ({ k, i })).sort((a, b) => (a.k.lo - b.k.lo) || (a.i - b.i)).map((x) => x.k);
    const rowW = Math.min(sorted.length, perRow) * (cellW + gapX) - gapX;
    const offsetX = grid.ha === "Center" ? (cw - rowW) / 2 : 0;
    sorted.forEach((k, i) => {
      const col = i % perRow;
      const row = Math.floor(i / perRow);
      placed.push({ k, x: pl + offsetX + col * (cellW + gapX), y: pt + row * (cellH + gapY), w: cellW, h: cellH });
    });
  } else {
    for (const k of kids) {
      const sz = resolveSize(k, cw, ch);
      const x = pl + k.pos[0] * cw + k.pos[1] - k.anchor[0] * sz.w;
      const y = pt + k.pos[2] * ch + k.pos[3] - k.anchor[1] * sz.h;
      placed.push({ k, x, y, w: sz.w, h: sz.h });
    }
  }
  if (node.cp) {
    // a scrolled ScrollingFrame: its content moves by the canvas position
    for (const p of placed) {
      p.x -= node.cp[0];
      p.y -= node.cp[1];
    }
  }
  for (const p of placed) {
    const childEl = document.createElement("div");
    childEl.style.position = "absolute";
    childEl.style.left = `${p.x}px`;
    childEl.style.top = `${p.y}px`;
    childEl.style.width = `${Math.max(0, p.w)}px`;
    childEl.style.height = `${Math.max(0, p.h)}px`;
    childEl.dataset.name = p.k.n;
    const scale = child(p.k, "UIScale");
    if (scale && scale.s !== 1) {
      childEl.style.transform = `scale(${scale.s})`;
      childEl.style.transformOrigin = "center center";
    }
    styleElement(childEl, p.k, p.w, p.h);
    el.appendChild(childEl);
    layoutChildren(p.k, childEl, p.w, p.h);
  }
}

export function renderUI(container, guis, width, height, topbarInset) {
  const sorted = [...guis].sort((a, b) => (a.order || 0) - (b.order || 0));
  for (const gui of sorted) {
    if (gui.enabled === false) continue;
    const inset = gui.inset ? (topbarInset ?? TOPBAR_INSET) : 0;
    const scaleNode = child(gui, "UIScale");
    const s = scaleNode ? scaleNode.s : 1;
    const vw = width / s;
    const vh = (height - inset) / s;
    const layer = document.createElement("div");
    layer.style.position = "absolute";
    layer.style.left = "0px";
    layer.style.top = `${inset}px`;
    layer.style.width = `${vw}px`;
    layer.style.height = `${vh}px`;
    layer.style.transform = `scale(${s})`;
    layer.style.transformOrigin = "0 0";
    container.appendChild(layer);
    layoutChildren(gui, layer, vw, vh);
  }
  if (sorted.some((g) => g.inset)) {
    // Roblox top bar (menu/chat buttons) placeholder for realism
    const bar = document.createElement("div");
    bar.style.cssText = "position:absolute;left:12px;top:6px;display:flex;gap:8px;";
    for (let i = 0; i < 2; i++) {
      const b = document.createElement("div");
      b.style.cssText = "width:32px;height:32px;border-radius:9px;background:rgba(20,20,24,0.55);";
      bar.appendChild(b);
    }
    container.appendChild(bar);
  }
}
