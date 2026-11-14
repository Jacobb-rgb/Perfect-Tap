"""Gameplay layout of a mine floor diorama, from tools/meshy/floor_heights.py samples.

python3 -I tools/meshy/floor_layout.py <heights.json> <FloorId> <size_x> <size_z> <config.json> <out.json> [map.html]

Places the diorama evenly scaled into the floor's footprint (its depth fits Floor.Size.Z, or
config.scale), with the floor's usual ground level at local y = 0 and its centre at x = z = 0, then:
  boxes   invisible collision boxes from the walk heights (equal heights merged greedily; walls in
          2-stud steps), local studs {x0, z0, x1, z1, top}; void cells get none
  spawns  rock spawn points on flat open ground away from walls, props, water, lava and the
          config's keep-clear circles (farthest-point spread), the back part "deep"
  giant   the most open flat spot in the back half (or config.giant)
config: {"scale": s?, "keep": [[x, z, r], ...], "giant": [x, z]?, "spawns": n, "deep_z": z, "min_gap": d}
"""
import json, math, sys

hp, fid, size_x, size_z, cfg_path, out_path = sys.argv[1:7]
size_x, size_z = float(size_x), float(size_z)
d = json.load(open(hp))
cfg = json.load(open(cfg_path)).get(fid, {}) if cfg_path != "-" else {}
H, C = d["H"], d["C"]
nx, nz, per = d["nx"], d["nz"], d["per_unit"]
lo, hi = d["lo"], d["hi"]
width_n, depth_n = hi[0] - lo[0], hi[2] - lo[2]
scale = cfg.get("scale") or min(size_z / depth_n, size_x / width_n)
cell = scale / per  # studs per cell

# the usual ground: the most common height (0.02-unit bins)
hist = {}
for row in H:
    for v in row:
        if v is not None:
            k = round(v / 0.02)
            hist[k] = hist.get(k, 0) + 1
ground_n = max(hist.items(), key=lambda kv: kv[1])[0] * 0.02
cx_n, cz_n = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2

def local_x(ix): return (lo[0] + (ix + 0.5) / per - cx_n) * scale
def local_z(iz): return (lo[2] + (iz + 0.5) / per - cz_n) * scale
def local_y(v): return (v - ground_n) * scale

Y = [[None if v is None else local_y(v) for v in row] for row in H]

def hue_kind(c):
    if c is None:
        return None
    r, g, b = c
    mx, mn = max(c), min(c)
    sat = (mx - mn) / mx if mx > 1e-6 else 0
    if sat > 0.45 and r > 0.55 and r >= g >= b:
        return "lava"  # bright orange/red
    if sat > 0.35 and b > 0.45 and g > 0.45 and r < 0.45:
        return "water"  # cyan/teal
    return None

# ---- collision boxes: blocks of K x K cells (their highest point, so nobody sinks in), heights
# snapped (the usual ground to 0, low ground in half studs, walls in 4-stud steps), equal neighbours
# merged greedily into rectangles
K = cfg.get("block", 2)
def q(y):
    if y is None:
        return None
    if abs(y) <= cfg.get("snap", 0.7):
        return 0.0
    if y > 8:
        return math.ceil(y / 4) * 4
    return round(y / 0.5) * 0.5

bx_n, bz_n = (nx + K - 1) // K, (nz + K - 1) // K
QB = []
for jz in range(bz_n):
    row = []
    for jx in range(bx_n):
        vals = [Y[iz][ix] for iz in range(jz * K, min(nz, jz * K + K)) for ix in range(jx * K, min(nx, jx * K + K)) if Y[iz][ix] is not None]
        cells = (min(nz, jz * K + K) - jz * K) * (min(nx, jx * K + K) - jx * K)
        # a block is void only when most of it is void (islands' ragged rims stay walkable)
        row.append(q(max(vals)) if len(vals) * 2 >= cells else None)
    QB.append(row)
used = [[False] * bx_n for _ in range(bz_n)]
boxes = []
bcell = cell * K
for jz in range(bz_n):
    for jx in range(bx_n):
        if used[jz][jx] or QB[jz][jx] is None:
            continue
        h = QB[jz][jx]
        w = 1
        while jx + w < bx_n and not used[jz][jx + w] and QB[jz][jx + w] == h:
            w += 1
        dz = 1
        while jz + dz < bz_n and all(not used[jz + dz][jx + k] and QB[jz + dz][jx + k] == h for k in range(w)):
            dz += 1
        for a2 in range(jz, jz + dz):
            for b2 in range(jx, jx + w):
                used[a2][b2] = True
        x0 = local_x(jx * K) - cell / 2; x1 = x0 + w * bcell
        z0 = local_z(jz * K) - cell / 2; z1 = z0 + dz * bcell
        boxes.append([round(x0, 2), round(z0, 2), round(x1, 2), round(z1, 2), h])

# ---- spawns: flat open ground with a clear disc around it
FLAT = 0.75
R = cfg.get("clear", 4.5)
rc = int(math.ceil(R / cell))
LEVEL = cfg.get("level", 3.0)  # spawns stand on ground within this many studs of the usual ground
BUMP = cfg.get("bump", 1.0)    # ...that is flat to this much around them
flat = [[Y[iz][ix] is not None and abs(Y[iz][ix]) <= LEVEL and hue_kind(C[iz][ix]) is None for ix in range(nx)] for iz in range(nz)]
keep = cfg.get("keep", [])
cands = []
for iz in range(rc, nz - rc):
    for ix in range(rc, nx - rc):
        if not flat[iz][ix]:
            continue
        ok = True
        yc = Y[iz][ix]
        for a in range(-rc, rc + 1):
            for b in range(-rc, rc + 1):
                if a * a + b * b <= rc * rc and (not flat[iz + a][ix + b] or abs(Y[iz + a][ix + b] - yc) > BUMP):
                    ok = False
                    break
            if not ok:
                break
        if not ok:
            continue
        x, z = local_x(ix), local_z(iz)
        if abs(x) > size_x / 2 - 6 or abs(z) > size_z / 2 - 6:
            continue
        if any((x - k[0]) ** 2 + (z - k[1]) ** 2 < k[2] ** 2 for k in keep):
            continue
        cands.append((x, z, Y[iz][ix]))

def spread(points, n, gap, first=None):
    chosen = []
    if not points:
        return chosen
    start = first if first is not None else max(range(len(points)), key=lambda i: -points[i][1])
    chosen.append(points[start])
    dist = [math.hypot(p[0] - chosen[0][0], p[1] - chosen[0][1]) for p in points]
    while len(chosen) < n:
        i = max(range(len(points)), key=lambda k: dist[k])
        if dist[i] < gap:
            break
        chosen.append(points[i])
        dist = [min(dist[k], math.hypot(points[k][0] - points[i][0], points[k][1] - points[i][1])) for k in range(len(points))]
    return chosen

# anchors: the flattest square of `size` studs nearest to `near` (searched within `radius`)
def flat_square(x, z, size, bump):
    half = size / 2
    i0 = int(math.floor((x - half) / scale * per + (cx_n - lo[0]) * per)); i1 = int(math.ceil((x + half) / scale * per + (cx_n - lo[0]) * per))
    j0 = int(math.floor((z - half) / scale * per + (cz_n - lo[2]) * per)); j1 = int(math.ceil((z + half) / scale * per + (cz_n - lo[2]) * per))
    if i0 < 0 or j0 < 0 or i1 >= nx or j1 >= nz:
        return None
    vals = []
    for iz in range(j0, j1):
        for ix in range(i0, i1):
            v = Y[iz][ix]
            if v is None or hue_kind(C[iz][ix]) is not None:
                return None
            vals.append(v)
    if max(vals) - min(vals) > bump:
        return None
    return max(vals)

def height_at(x, z):
    ix = int(round((x / scale + cx_n - lo[0]) * per - 0.5)); iz = int(round((z / scale + cz_n - lo[2]) * per - 0.5))
    if 0 <= iz < nz and 0 <= ix < nx and Y[iz][ix] is not None:
        return Y[iz][ix]
    return None

anchors = {}
def by_order(item):
    # anchors placed beside another one come after it
    return 1 if "beside" in item[1] else 0
for name, a in sorted(cfg.get("anchors", {}).items(), key=by_order):
    if "beside" in a:
        # (owner 2026-11-14: the ore lift next to the elevator, not out in the field) the flattest
        # square of `size` on a ring round the other anchor: at its side first (the elevator's door
        # faces the floor's middle along x), toward the nearer floor edge, then round, then further out
        other = anchors.get(a["beside"])
        best = None
        if other:
            ox, oz = other[0], other[2]
            want = math.atan2(1.0 if oz >= 0 else -1.0, 0.0)
            r = a.get("ring", 14.0)
            while r <= a.get("ring", 14.0) + a.get("radius", 10) and best is None:
                for t in range(0, 181, 5):
                    for sgn in ((1,) if t in (0, 180) else (1, -1)):
                        ang = want + sgn * math.radians(t)
                        x, z = ox + r * math.cos(ang), oz + r * math.sin(ang)
                        y = flat_square(x, z, a.get("size", 6), a.get("bump", 1.0))
                        if y is not None and abs(y - other[1]) <= a.get("level", 2.0):
                            best = [round(x, 2), round(y, 2), round(z, 2), True]
                            break
                    if best:
                        break
                r += 1.0
        anchors[name] = best
        if best:
            keep.append([best[0], best[2], a.get("keep", a.get("size", 6) * 0.75 + 4)])
        continue
    if "at" in a:
        ax, az = a["at"]
        y = height_at(ax, az)
        anchors[name] = [ax, round(y if y is not None else 0, 2), az, flat_square(ax, az, a.get("size", 6), a.get("bump", 1.0)) is not None]
        continue
    nx0, nz0 = a["near"]
    best = None
    step = 1.0
    r = 0.0
    while r <= a.get("radius", 20) and best is None:
        k = max(1, int(2 * math.pi * r / step)) if r > 0 else 1
        for t in range(k):
            ang = 2 * math.pi * t / k
            x, z = nx0 + r * math.cos(ang), nz0 + r * math.sin(ang)
            y = flat_square(x, z, a.get("size", 6), a.get("bump", 1.0))
            if y is not None and abs(y) <= a.get("level", 3.5):
                best = [round(x, 2), round(y, 2), round(z, 2), True]
                break
        r += step
    anchors[name] = best
    if best:
        keep.append([best[0], best[2], a.get("keep", a.get("size", 6) * 0.75 + 4)])

# giant: the most open flat spot in the back half (or the config's)
if "giant" in cfg:
    gx, gz = cfg["giant"]
    giant = (gx, gz, height_at(gx, gz) or 0.0)
else:
    best, giant = -1, None
    for (x, z, y) in cands:
        if z > 0:
            continue
        # openness: distance to the nearest non-flat cell (coarse)
        ix = int(round((x / scale + cx_n - lo[0]) * per - 0.5)); iz = int(round((z / scale + cz_n - lo[2]) * per - 0.5))
        r = 0
        while r < 20:
            r += 1
            ring = [(iz + a, ix + b) for a in (-r, r) for b in range(-r, r + 1)] + [(iz + a, ix + b) for b in (-r, r) for a in range(-r, r + 1)]
            if any(not (0 <= p < nz and 0 <= q2 < nx) or not flat[p][q2] for p, q2 in ring):
                break
        if r > best:
            best, giant = r, (x, z, y)
gap_giant = cfg.get("giant_clear", 12)
cands = [p for p in cands if giant is None or math.hypot(p[0] - giant[0], p[1] - giant[1]) > gap_giant]
cands = [p for p in cands if not any((p[0] - k[0]) ** 2 + (p[1] - k[1]) ** 2 < k[2] ** 2 for k in keep)]
if "zone" in cfg:  # spawns only inside these rectangles [x0, z0, x1, z1]
    cands = [p for p in cands if any(r[0] <= p[0] <= r[2] and r[1] <= p[1] <= r[3] for r in cfg["zone"])]
spawns = spread(cands, cfg.get("spawns", 28), cfg.get("min_gap", 9.0))
deep_z = cfg.get("deep_z", -size_z * 0.15)
# lights: spread over the walkable ground (any height near the usual ground), farthest-point
ground_pts = [(local_x(ix), local_z(iz), Y[iz][ix]) for iz in range(0, nz, 3) for ix in range(0, nx, 3)
              if Y[iz][ix] is not None and abs(Y[iz][ix]) <= max(LEVEL, 3)]
lights = spread(ground_pts, cfg.get("lights", 10), cfg.get("light_gap", 26.0))
out = {
    "id": fid, "scale": round(scale, 4), "ground_n": round(ground_n, 4), "center_n": [round(cx_n, 4), round(cz_n, 4)],
    "cell": round(cell, 3), "boxes": boxes,
    "spawns": [[round(x, 2), round(y, 2), round(z, 2), z < deep_z] for (x, z, y) in spawns],
    "giant": [round(giant[0], 2), round(giant[2], 2), round(giant[1], 2)] if giant else None,
    "extent": [round(local_x(0) - cell / 2, 2), round(local_z(0) - cell / 2, 2), round(local_x(nx - 1) + cell / 2, 2), round(local_z(nz - 1) + cell / 2, 2)],
    "top": round(max(v for row in Y for v in row if v is not None), 2), "bottom": round(min(v for row in Y for v in row if v is not None), 2),
    "anchors": anchors,
    "lights": [[round(x, 2), round(y, 2), round(z, 2)] for (x, z, y) in lights],
}
json.dump(out, open(out_path, "w"))
deep = sum(1 for s in out["spawns"] if s[3])
print(f"{fid}: scale {scale:.2f} cell {cell:.2f} boxes {len(boxes)} spawns {len(spawns)} (deep {deep}) giant {out['giant']} extent {out['extent']} y {out['bottom']}..{out['top']}")
for k, v in anchors.items():
    print("   ", k, v)

if len(sys.argv) > 7:
    # a map: heights in grey, lava/water tinted, spawns white dots, giant red, keep circles
    px = 4
    rows = []
    for iz in range(nz):
        for ix in range(nx):
            y = Y[iz][ix]
            if y is None:
                col = "#101018"
            else:
                k = hue_kind(C[iz][ix])
                t = max(0, min(1, (y + 4) / 40))
                g = int(60 + 190 * t)
                col = "#c85020" if k == "lava" else "#30a0c0" if k == "water" else f"rgb({g},{g},{int(g*0.9)})"
                if abs(y) <= FLAT and k is None:
                    col = "#8a9a70"
            rows.append(f"c.fillStyle='{col}';c.fillRect({ix*px},{iz*px},{px},{px});")
    def to_px(x, z):
        ix = (x / scale + cx_n - lo[0]) * per; iz = (z / scale + cz_n - lo[2]) * per
        return ix * px, iz * px
    marks = []
    for s in out["spawns"]:
        a, b = to_px(s[0], s[2]); marks.append(f"c.fillStyle='{'#ff60ff' if s[3] else '#ffffff'}';c.beginPath();c.arc({a},{b},6,0,7);c.fill();")
    if giant:
        a, b = to_px(giant[0], giant[1]); marks.append(f"c.fillStyle='#ff2020';c.beginPath();c.arc({a},{b},10,0,7);c.fill();")
    for gx in range(-80, 81, 10):
        a, _ = to_px(gx, 0); marks.append(f"c.strokeStyle='rgba(255,255,255,{0.5 if gx == 0 else 0.18})';c.lineWidth=1;c.beginPath();c.moveTo({a},0);c.lineTo({a},{nz*px});c.stroke();c.fillStyle='#fff';c.font='11px sans-serif';c.fillText('{gx}',{a+2},12);")
    for gz in range(-80, 81, 10):
        _, b = to_px(0, gz); marks.append(f"c.strokeStyle='rgba(255,255,255,{0.5 if gz == 0 else 0.18})';c.lineWidth=1;c.beginPath();c.moveTo(0,{b});c.lineTo({nx*px},{b});c.stroke();c.fillStyle='#fff';c.font='11px sans-serif';c.fillText('{gz}',2,{b-2});")
    for k, v in anchors.items():
        if v:
            a, b = to_px(v[0], v[2]); marks.append(f"c.fillStyle='#ffd000';c.fillRect({a-7},{b-7},14,14);c.fillStyle='#000';c.font='bold 11px sans-serif';c.fillText('{k[:3]}',{a-9},{b+4});")
    for k in keep:
        a, b = to_px(k[0], k[1]); marks.append(f"c.strokeStyle='#ffd000';c.lineWidth=2;c.beginPath();c.arc({a},{b},{k[2]/scale*per*px},0,7);c.stroke();")
    html = f"<html><body style='margin:0;background:#000'><canvas id=k width={nx*px} height={nz*px}></canvas><script>const c=document.getElementById('k').getContext('2d');{''.join(rows)}{''.join(marks)}</script></body></html>"
    open(sys.argv[7], "w").write(html)
