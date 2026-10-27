// The weather reel's stand-ins (preview only, never game code). The lobby is rendered
// once by viewer.js (index.html); this script draws the weather on top of it, frame by
// frame, from build/preview/weather_reel.json (tools/lune/lib/weather_preview.luau: the
// game's WeatherConfig / WeatherLogic numbers):
//   - the particles as 2D sprites on a canvas over the render: the same sky field (its
//     strips round the clear-view hole, the inner ring smaller and fainter), boxes, pads
//     (never within Ground.Clear of the camera), rates, speeds, sizes, lifetimes, colours
//     and transparencies as the game's ParticleEmitters (simulated here: Roblox's particles
//     cannot be rendered outside Roblox). Rain streak length is a guess for Squash (check
//     in Studio). No occlusion.
//   - WeatherTint (the game's ColorCorrectionEffect) as CSS: contrast / saturate filters
//     on both canvases, a multiply layer for TintColor and a plus-lighter layer for a
//     positive Brightness (the lightning flash).
//   - the rainbow is added as real 3D parts through viewer.js's window.__frame (so the
//     island hides its feet), built from the game's Bezier arcs (render_weather.mjs).
// Every frame is a function of its index (the simulation is stepped in order from 0).
(() => {
  let data, W, H, cam, ctx, overlay, glCanvas, tintLayer, addLayer, titleBox, titleMain, titleSub;
  let rand;
  let simFrame = -1;
  let particles = [];
  const accum = {};
  let pads = [];
  let padClock = 0;
  let padIndex = 0;

  // ---------------------------------------------------------------- small helpers
  function mulberry32(a) {
    return function () {
      a |= 0;
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const rr = (a, b) => a + (b - a) * rand();
  const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const len = (a) => Math.sqrt(dot(a, a));
  const norm = (a) => mul(a, 1 / (len(a) || 1));
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const rgb = (hex) => [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16), parseInt(hex.slice(4, 6), 16)];

  function setupCamera(shot) {
    const pos = shot.position;
    const f = norm(sub(shot.target, pos));
    const r = norm(cross(f, [0, 1, 0]));
    const u = cross(r, f);
    cam = { pos, f, r, u, focal: H / 2 / Math.tan((shot.fov * Math.PI) / 360) };
  }
  function project(p) {
    const v = sub(p, cam.pos);
    const z = dot(v, cam.f);
    if (z < 0.5) return null;
    return [W / 2 + (dot(v, cam.r) / z) * cam.focal, H / 2 - (dot(v, cam.u) / z) * cam.focal, z];
  }

  // a direction inside a cone of `deg` degrees round `dir`
  function cone(dir, deg) {
    if (deg <= 0) return dir;
    const k = Math.tan((deg * Math.PI) / 180) * Math.sqrt(rand());
    const a = rand() * Math.PI * 2;
    const helper = Math.abs(dir[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
    const x = norm(cross(dir, helper));
    const y = cross(dir, x);
    return norm(add(dir, add(mul(x, Math.cos(a) * k), mul(y, Math.sin(a) * k))));
  }

  // ---------------------------------------------------------------- the game's boxes (WeatherFx.place)
  function boxes(frame) {
    const box = data.box;
    const flat = norm([cam.f[0], 0, cam.f[2]]);
    const at = add(cam.pos, mul(flat, box.ahead));
    const wind = [Math.cos(frame.wind), 0, Math.sin(frame.wind)];
    const up = [0, 1, 0];
    const Z = cross(wind, up);
    const s = frame.slant;
    const X = add(mul(wind, Math.cos(s)), mul(up, Math.sin(s)));
    const Y = add(mul(wind, -Math.sin(s)), mul(up, Math.cos(s)));
    // the sky field is centred on the camera's fall line (WeatherFx.place)
    const skyCenter = add(add(cam.pos, mul(wind, -box.height * Math.tan(s))), [0, box.height, 0]);
    const airCenter = sub([at[0], data.groundY + box.air[1] / 2 - 0.5, at[2]], mul(wind, box.upwind));
    const field = data.sky[frame.kind];
    return {
      sky: { center: skyCenter, X, Y, Z, strips: field ? field.strips : [], down: mul(Y, -1) },
      air: { center: airCenter, X: wind, Y: up, Z, size: box.air },
      wind,
    };
  }
  // a spot in one of the sky strips, picked by its share; returns [position, near]
  function inSky(sky) {
    let roll = rand();
    let pick = sky.strips[sky.strips.length - 1];
    for (const strip of sky.strips) {
      roll -= strip[5];
      if (roll < 0) {
        pick = strip;
        break;
      }
    }
    const [x, z, sx, sz, near] = pick;
    const u = x + rr(-0.5, 0.5) * sx;
    const w = z + rr(-0.5, 0.5) * sz;
    return [add(sky.center, add(add(mul(sky.X, u), mul(sky.Y, rr(-1, 1))), mul(sky.Z, w))), near];
  }
  function inBox(b) {
    return add(
      b.center,
      add(add(mul(b.X, rr(-0.5, 0.5) * b.size[0]), mul(b.Y, rr(-0.5, 0.5) * b.size[1])), mul(b.Z, rr(-0.5, 0.5) * b.size[2])),
    );
  }

  // ---------------------------------------------------------------- the simulation
  const SKY = ["Rain", "Hail", "Snow"];
  const AIR = ["Leaves", "Leaves2", "Heat"];
  const PAD = ["Ripple", "Drop", "Bounce", "Settle"];

  function spawn(key, p, dir, look, kind, near = false) {
    const speed = rr(look.speed[0], look.speed[1]);
    const v = mul(cone(dir, look.spread), speed);
    // the inner ring round the clear view: smaller, fainter (Box.NearSize / NearAlpha)
    const size = rr(look.size[0], look.size[1]) * (near ? data.box.nearSize : 1);
    particles.push({
      near,
      key,
      kind,
      p,
      v,
      age: 0,
      life: rr(look.lifetime[0], look.lifetime[1]),
      size,
      rot: rand() * 360,
      spin: rr(-look.rotSpeed, look.rotSpeed),
      color: key === "Leaves2" ? look.color2 : look.color,
      dying: false,
    });
  }

  function step(frame, dt, warming = false) {
    const B = boxes(frame);
    const P = data.particles;
    // pads: PerTick of them move every check (WeatherController.movePads)
    padClock += dt;
    const flat = norm([cam.f[0], 0, cam.f[2]]);
    const focus = add(cam.pos, mul(flat, data.ground.ahead));
    while (pads.length < data.ground.points) pads.push(null);
    while (padClock >= data.ground.every) {
      padClock -= data.ground.every;
      for (let k = 0; k < data.ground.perTick; k++) {
        padIndex = (padIndex + 1) % pads.length;
        // clear view: a spot too close to the camera is tried again, else the pad rests
        let spot = null;
        for (let t = 0; t < data.ground.tries && !spot; t++) {
          const r = Math.sqrt(rand()) * data.ground.radius;
          const a = rand() * Math.PI * 2;
          const c = [focus[0] + Math.cos(a) * r, data.groundY + 0.15, focus[2] + Math.sin(a) * r];
          if (len(sub(c, cam.pos)) >= data.ground.clear) spot = c;
        }
        pads[padIndex] = spot;
      }
    }
    for (const [keys, where] of [
      [SKY, "sky"],
      [AIR, "air"],
      [PAD, "pad"],
    ]) {
      for (const key of keys) {
        const look = P[key === "Leaves2" ? "Leaves" : key];
        const perPad = where === "pad";
        const rate = (frame.rates[key] || 0) * (perPad ? pads.filter(Boolean).length : 1);
        accum[key] = (accum[key] || 0) + rate * dt;
        while (accum[key] >= 1) {
          accum[key] -= 1;
          let p, dir;
          let near = false;
          if (where === "sky") {
            if (!B.sky.strips.length) continue;
            [p, near] = inSky(B.sky);
            dir = B.sky.down;
          } else if (where === "air") {
            p = inBox(B.air);
            dir = key === "Heat" ? [0, 1, 0] : B.wind;
          } else {
            const live = pads.filter(Boolean);
            if (!live.length) continue;
            const c = live[Math.floor(rand() * live.length)];
            const h = data.ground.pad / 2;
            p = [c[0] + rr(-h, h), c[1], c[2] + rr(-h, h)];
            dir = [0, 1, 0];
          }
          spawn(key, p, dir, look, frame.kind, near);
        }
      }
    }
    // move, age; a kind that is gone fades out fast (the reel's compression)
    const keep = [];
    for (const q of particles) {
      const look = P[q.key === "Leaves2" ? "Leaves" : q.key];
      q.age += dt * (!warming && q.kind !== frame.kind ? Math.max(1, q.life / 0.6) : 1);
      if (q.age >= q.life) continue;
      q.v = add(q.v, [0, -look.gravity * dt, 0]);
      if (look.drag) q.v = mul(q.v, Math.exp(-look.drag * dt));
      q.p = add(q.p, mul(q.v, dt));
      q.rot += q.spin * dt;
      keep.push(q);
    }
    particles = keep;
  }

  // The reel is compressed (a kind lasts ~2 s, not minutes): before a kind's segment its
  // particles are simulated on their own for as long as they live, at the segment's peak
  // rates, as if it had been raining / snowing for a while. They fade in with the segment.
  function prewarm(seg) {
    let peak = null;
    for (const f of data.frames) if (f.seg === seg && (!peak || f.i > peak.i)) peak = f;
    if (!peak || peak.i <= 0) return;
    let warm = 0;
    for (const [key, rate] of Object.entries(peak.rates)) {
      if (rate > 0) warm = Math.max(warm, data.particles[key === "Leaves2" ? "Leaves" : key].lifetime[1]);
    }
    const old = particles;
    particles = [];
    const dt = 1 / data.fps;
    for (let t = 0; t < Math.min(warm, 10); t += dt) step(peak, dt, true);
    particles = old.concat(particles);
  }

  // ---------------------------------------------------------------- drawing
  function alphaOf(q, look) {
    const t = q.age / q.life;
    let a;
    if (look.grow !== 1) a = 1 - t; // a ripple clears as it spreads
    else if (t < 0.1) a = t / 0.1;
    else if (t > 0.8) a = (1 - t) / 0.2;
    else a = 1;
    return clamp(a) * (1 - look.transparency) * (q.near ? data.box.nearAlpha : 1);
  }
  function soft(x, y, r, color, alpha, hard = 0.45) {
    const [cr, cg, cb] = rgb(color);
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(${cr},${cg},${cb},${alpha})`);
    g.addColorStop(hard, `rgba(${cr},${cg},${cb},${alpha * 0.85})`);
    g.addColorStop(1, `rgba(${cr},${cg},${cb},0)`);
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  function flat(q, look, radius, alpha, ring) {
    const pts = [];
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * Math.PI * 2;
      const s = project([q.p[0] + Math.cos(a) * radius, q.p[1], q.p[2] + Math.sin(a) * radius]);
      if (!s) return;
      pts.push(s);
    }
    const [cr, cg, cb] = rgb(q.color);
    ctx.beginPath();
    pts.forEach((s, i) => (i ? ctx.lineTo(s[0], s[1]) : ctx.moveTo(s[0], s[1])));
    ctx.closePath();
    if (ring) {
      ctx.strokeStyle = `rgba(${cr},${cg},${cb},${alpha})`;
      ctx.lineWidth = Math.max(0.8, ((radius * 0.22) * cam.focal) / pts[0][2]);
      ctx.stroke();
    } else {
      ctx.fillStyle = `rgba(${cr},${cg},${cb},${alpha})`;
      ctx.fill();
    }
  }

  function draw(frame) {
    ctx.clearRect(0, 0, W, H);
    const P = data.particles;
    // far first (the soft heat puffs overlap)
    const order = particles
      .map((q) => ({ q, s: project(q.p) }))
      .filter((e) => e.s && e.q.p[1] > data.groundY - 0.2)
      .sort((a, b) => b.s[2] - a.s[2]);
    for (const { q, s } of order) {
      const look = P[q.key === "Leaves2" ? "Leaves" : q.key];
      const alpha = alphaOf(q, look) * (q.kind === frame.kind ? Math.min(1, frame.i / 0.7) : 1);
      if (alpha <= 0.003) continue;
      const [x, y, z] = s;
      const t = q.age / q.life;
      const size = q.size * (1 + (look.grow - 1) * t);
      const px = (size * cam.focal) / z;
      if (q.key === "Rain") {
        // VelocityParallel + Squash: a thin streak along its velocity (length: a guess)
        const tail = project(sub(q.p, mul(norm(q.v), size * 6)));
        if (!tail) continue;
        const [cr, cg, cb] = rgb(q.color);
        ctx.strokeStyle = `rgba(${cr},${cg},${cb},${alpha})`;
        ctx.lineWidth = Math.max(0.7, px / 5);
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(tail[0], tail[1]);
        ctx.stroke();
      } else if (q.key === "Leaves" || q.key === "Leaves2") {
        const [cr, cg, cb] = rgb(q.color);
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate((q.rot * Math.PI) / 180);
        ctx.scale(1, 0.35 + 0.65 * Math.abs(Math.cos((q.rot * Math.PI) / 90)));
        ctx.fillStyle = `rgba(${cr},${cg},${cb},${alpha})`;
        ctx.fillRect(-px / 2, -px * 0.32, px, px * 0.64);
        ctx.restore();
      } else if (q.key === "Ripple") {
        flat(q, look, size / 2, alpha, true);
      } else if (q.key === "Settle") {
        // a soft flake lying flat (the smoke texture, VelocityPerpendicular)
        const ex = project(add(q.p, [size / 2, 0, 0]));
        const ez = project(add(q.p, [0, 0, size / 2]));
        if (!ex || !ez) continue;
        const rx = Math.max(0.8, Math.hypot(ex[0] - x, ex[1] - y, ez[0] - x, ez[1] - y) / 1.2);
        const ry = Math.max(0.5, Math.min(rx, Math.abs(ez[1] - y) + Math.abs(ex[1] - y)));
        ctx.save();
        ctx.translate(x, y);
        ctx.scale(1, ry / rx);
        soft(0, 0, rx, q.color, alpha, 0.35);
        ctx.restore();
      } else if (q.key === "Heat") {
        soft(x, y, Math.max(1, px / 2), q.color, alpha, 0.2);
      } else {
        soft(x, y, Math.max(0.8, px / 2), q.color, Math.min(1, alpha * 1.2), 0.55);
      }
    }
  }

  // WeatherTint as CSS (see the top)
  function tint(frame) {
    const [r, g, b, brightness, contrast, saturation] = frame.tint;
    const filter = `contrast(${(1 + contrast).toFixed(3)}) saturate(${(1 + saturation).toFixed(3)})`;
    glCanvas.style.filter = filter;
    overlay.style.filter = filter;
    const dark = Math.min(0, brightness);
    const m = (c) => Math.round(clamp(c * (1 + dark * 2.2)) * 255);
    tintLayer.style.background = `rgb(${m(r)},${m(g)},${m(b)})`;
    addLayer.style.background = `rgba(255,255,255,${clamp(Math.max(0, brightness)).toFixed(3)})`;
  }

  function titles(index) {
    const frame = data.frames[index];
    const seg = data.segments[frame.seg];
    const t = index / data.fps - seg.start;
    const show = clamp(t / 0.3) * clamp((seg.length - t) / 0.25);
    titleMain.textContent = seg.title;
    titleSub.textContent = seg.sub;
    titleBox.style.opacity = String(show);
  }

  window.weatherSetup = async (reelUrl) => {
    data = await fetch(reelUrl).then((r) => r.json());
    W = data.width;
    H = data.height;
    rand = mulberry32(20271027);
    setupCamera(data.shot);
    const stage = document.getElementById("stage");
    glCanvas = stage.querySelector("canvas");
    overlay = document.createElement("canvas");
    overlay.width = W;
    overlay.height = H;
    overlay.style.cssText = "position:absolute;left:0;top:0;pointer-events:none";
    stage.appendChild(overlay);
    ctx = overlay.getContext("2d");
    tintLayer = document.createElement("div");
    tintLayer.style.cssText = `position:absolute;left:0;top:0;width:${W}px;height:${H}px;mix-blend-mode:multiply;pointer-events:none`;
    addLayer = document.createElement("div");
    addLayer.style.cssText = `position:absolute;left:0;top:0;width:${W}px;height:${H}px;mix-blend-mode:plus-lighter;pointer-events:none`;
    stage.appendChild(tintLayer);
    stage.appendChild(addLayer);
    const box = document.createElement("div");
    box.style.cssText = `position:absolute;left:0;top:${Math.round(H * 0.035)}px;width:${W}px;text-align:center;pointer-events:none;font-family:"Fredoka One",sans-serif;color:#fff;text-shadow:0 3px 0 #3a2252,0 0 12px rgba(40,10,60,0.6)`;
    titleMain = document.createElement("div");
    titleMain.style.cssText = `font-size:${Math.round(H * 0.075)}px;letter-spacing:1px`;
    titleSub = document.createElement("div");
    titleSub.style.cssText = `font-size:${Math.round(H * 0.03)}px;margin-top:4px`;
    box.appendChild(titleMain);
    box.appendChild(titleSub);
    stage.appendChild(box);
    titleBox = box;
    const note = document.createElement("div");
    note.style.cssText = `position:absolute;right:12px;bottom:10px;font-family:"Fredoka One",sans-serif;font-size:${Math.round(H * 0.022)}px;color:rgba(255,255,255,0.85);text-shadow:0 2px 0 rgba(0,0,0,0.5);pointer-events:none`;
    note.textContent = "náhled z herního kódu (three.js, ne Roblox)";
    stage.appendChild(note);
    return { frames: data.frames.length, fps: data.fps, picks: data.picks, segments: data.segments };
  };

  // Draws frame `index` (steps the simulation from where it is; going back restarts it).
  window.weatherFrame = (index) => {
    if (index < simFrame) {
      rand = mulberry32(20271027);
      particles = [];
      pads = [];
      padClock = 0;
      padIndex = 0;
      for (const k of Object.keys(accum)) delete accum[k];
      simFrame = -1;
    }
    const dt = 1 / data.fps;
    while (simFrame < index) {
      simFrame += 1;
      const f = data.frames[simFrame];
      if (simFrame === 0 || data.frames[simFrame - 1].seg !== f.seg) prewarm(f.seg);
      step(f, dt);
    }
    const frame = data.frames[index];
    draw(frame);
    tint(frame);
    titles(index);
    return { rainbow: frame.rb, seg: frame.seg };
  };
})();
