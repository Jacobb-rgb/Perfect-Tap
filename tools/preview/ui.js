// Renders exported Roblox ScreenGuis as HTML (approximation of Roblox layout):
// UDim2 position/size, AnchorPoint, UIListLayout, UIGridLayout, UIPadding,
// UIScale, UICorner, UIStroke, UIGradient, TextScaled. For preview images only.

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
  return "Fredoka One";
}

const isGui = (n) => ["Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "CanvasGroup"].includes(n.c);
const child = (n, cls) => (n.ch || []).find((c) => c.c === cls);

function resolveSize(node, parentW, parentH) {
  const [xs, xo, ys, yo] = node.size;
  return { w: parentW * xs + xo, h: parentH * ys + yo };
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
      const stops = grad.keys.map(([t, c]) => `${rgba(mulHex(node.bg, c), 1 - node.bgt)} ${t * 100}%`).join(", ");
      el.style.backgroundImage = `linear-gradient(${grad.rot + 90}deg, ${stops})`;
    } else {
      el.style.backgroundColor = rgba(node.bg, 1 - node.bgt);
    }
  }
  for (const s of (node.ch || []).filter((c) => c.c === "UIStroke")) {
    const contextualText = isText && s.mode === "Contextual";
    if (!contextualText && s.t < 0.999) {
      el.style.boxShadow = `0 0 0 ${s.th}px ${rgba(s.col, 1 - s.t)}`;
    }
  }
  if (node.icon) {
    // 3D UI icon (tools/preview/render_icons.mjs output), ScaleType Fit
    const img = document.createElement("img");
    img.src = `/scenes/icons/${node.icon}.png`;
    img.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:contain;";
    img.style.opacity = String(1 - (node.it || 0));
    el.appendChild(img);
  }
  if (node.rot) el.style.transform = `rotate(${node.rot}deg)`;
  if (node.clip) el.style.overflow = "hidden";
  el.style.zIndex = String(node.z || 1);

  if (isText && node.text !== "") {
    const span = document.createElement("div");
    const font = fontFamily(node.font);
    span.style.position = "absolute";
    span.style.inset = "0";
    span.style.display = "flex";
    span.style.alignItems = node.ty === "Top" ? "flex-start" : node.ty === "Bottom" ? "flex-end" : "center";
    span.style.justifyContent = node.tx === "Left" ? "flex-start" : node.tx === "Right" ? "flex-end" : "center";
    span.style.textAlign = node.tx === "Left" ? "left" : node.tx === "Right" ? "right" : "center";
    span.style.fontFamily = `"${font}"`;
    const size = node.scaled ? fitText(node.text, font, w, h, node.wrap) : node.ts;
    span.style.fontSize = `${size}px`;
    span.style.lineHeight = "1.05";
    span.style.color = rgba(node.tc, 1 - node.tt);
    span.style.whiteSpace = node.wrap ? "normal" : "nowrap";
    const stroke = (node.ch || []).find((c) => c.c === "UIStroke" && c.mode === "Contextual");
    if (stroke && node.tt < 0.99 && stroke.t < 0.99) {
      span.style.webkitTextStroke = `${stroke.th * 2}px ${rgba(stroke.col, (1 - stroke.t) * (1 - node.tt))}`;
      span.style.paintOrder = "stroke fill";
    }
    span.textContent = node.text;
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
