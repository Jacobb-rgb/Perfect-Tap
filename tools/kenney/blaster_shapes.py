"""
Converts Kenney Blaster Kit models (CC0, OBJ format) into side-profile shape
data that the Luau builders rebuild from Roblox parts (we never import the
meshes: they would need uploads under the owner's account).

How: the model is rasterized from the side (along X). Every pixel keeps the
solid's extent along X (front and back surface) and the palette color seen
from the side. Pixels are grouped into regions of the same color role
(body / light / mid / dark) and the same width; each region's outline is
traced and simplified, then cut into horizontal trapezoids, which become one
box plus up to two wedges each. Kenney's chamfers become small steps, which
reads like their soft bevels.

  python3 tools/kenney/blaster_shapes.py [kit dir] [out file]
  defaults: ../kity/kenney_blaster-kit -> tools/lune/lib/kenney_blaster_shapes.luau

Needs numpy and Pillow.
"""

import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
KIT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "..", "kity", "kenney_blaster-kit")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "tools", "lune", "lib", "kenney_blaster_shapes.luau")

MODELS = ["blaster-" + c for c in "abcdefghijklmnopqr"]
RES = 0.0025  # meters per pixel
MIN_REGION = 22  # pixels; smaller specks merge into a neighbour


def load(name, group=None):
    """Vertices, uvs and faces of a model; `group` keeps only the faces of one OBJ group
    ("lid"), "!lid" all but that group."""
    V, T, F = [], [], []
    current = None
    for line in open(os.path.join(KIT, "Models", "OBJ format", name + ".obj")):
        p = line.split()
        if not p:
            continue
        if p[0] == "g":
            current = p[1] if len(p) > 1 else None
        elif p[0] == "f" and group is not None:
            keep = current != group[1:] if group.startswith("!") else current == group
            if not keep:
                continue
        if p[0] == "v":
            V.append(tuple(map(float, p[1:4])))
        elif p[0] == "vt":
            T.append(tuple(map(float, p[1:3])))
        elif p[0] == "f":
            F.append([tuple(int(x) for x in q.split("/")[:2]) for q in p[1:]])
    return np.array(V), T, F


def role_of(c):
    r, g, b = c
    mx, mn = max(c), min(c)
    s = (mx - mn) / mx if mx else 0
    v = mx / 255
    if s > 0.35 and v > 0.3:
        return 1  # body: the blaster's color
    if v > 0.62:
        return 2  # light grey-blue steel
    if v > 0.3:
        return 3  # mid grey
    return 4  # dark


ROLE_NAMES = {1: "body", 2: "light", 3: "mid", 4: "dark"}


def rasterize(V, T, F, palette):
    zmin, zmax = V[:, 2].min(), V[:, 2].max()
    ymin, ymax = V[:, 1].min(), V[:, 1].max()
    W = int((zmax - zmin) / RES) + 3
    H = int((ymax - ymin) / RES) + 3
    xhi = np.full((H, W), -1e9)
    xlo = np.full((H, W), 1e9)
    role = np.zeros((H, W), np.int8)
    for f in F:
        for k in range(1, len(f) - 1):
            tri = [f[0], f[k], f[k + 1]]
            P = V[[t[0] - 1 for t in tri]]
            uv = [T[t[1] - 1] for t in tri]
            u = sum(a[0] for a in uv) / 3
            v = sum(a[1] for a in uv) / 3
            c = palette.getpixel((min(511, int(u * 512)), min(511, int((1 - v) * 512))))
            pz = (P[:, 2] - zmin) / RES + 1
            py = (P[:, 1] - ymin) / RES + 1
            x0, x1 = int(np.floor(pz.min())), int(np.ceil(pz.max()))
            y0, y1 = int(np.floor(py.min())), int(np.ceil(py.max()))
            gz, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            a, b = pz[1] - pz[0], pz[2] - pz[0]
            c2, d = py[1] - py[0], py[2] - py[0]
            det = a * d - b * c2
            if abs(det) < 1e-9:
                continue
            l1 = ((gz - pz[0]) * d - (gy - py[0]) * b) / det
            l2 = (a * (gy - py[0]) - c2 * (gz - pz[0])) / det
            l0 = 1 - l1 - l2
            m = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
            if not m.any():
                continue
            x = l0 * P[0, 0] + l1 * P[1, 0] + l2 * P[2, 0]
            ys = np.floor(gy[m]).astype(int)
            zs = np.floor(gz[m]).astype(int)
            xv = x[m]
            upd = xv > xhi[ys, zs]
            xhi[ys[upd], zs[upd]] = xv[upd]
            role[ys[upd], zs[upd]] = role_of(c)
            upd = xv < xlo[ys, zs]
            xlo[ys[upd], zs[upd]] = xv[upd]
    inside = xhi > -1e8
    return dict(zmin=zmin, ymin=ymin, W=W, H=H, xhi=xhi, xlo=xlo, role=np.where(inside, role, 0))


def levels(values, tol, min_count):
    """Peaks of a 1D sample: values snapped to peaks within the sample."""
    if len(values) == 0:
        return []
    q = np.round(values / 0.002) * 0.002
    uniq, counts = np.unique(q, return_counts=True)
    order = np.argsort(-counts)
    peaks = []
    for i in order:
        if counts[i] < min_count and peaks:
            break
        if all(abs(uniq[i] - p) > tol for p in peaks):
            peaks.append(uniq[i])
    return sorted(peaks)


def label(r):
    H, W = r["H"], r["W"]
    role = r["role"]
    width = np.where(role > 0, r["xhi"] - r["xlo"], 0)
    center = np.where(role > 0, (r["xhi"] + r["xlo"]) / 2, 0)
    key = np.zeros((H, W), np.int64)
    wl = np.zeros((H, W))
    cl = np.zeros((H, W))
    for ro in (1, 2, 3, 4):
        m = role == ro
        if not m.any():
            continue
        ws = levels(width[m], 0.005, max(30, int(m.sum() * 0.02)))
        cs = levels(center[m], 0.006, max(30, int(m.sum() * 0.04)))
        wi = np.abs(width[m][:, None] - np.array(ws)[None, :]).argmin(axis=1)
        ci = np.abs(center[m][:, None] - np.array(cs)[None, :]).argmin(axis=1)
        wl[m] = np.array(ws)[wi]
        cl[m] = np.array(cs)[ci]
        key[m] = ro * 1000000 + wi * 1000 + ci + 1
    # connected regions of equal key
    lab = np.zeros((H, W), np.int32)
    regions = []
    for y in range(H):
        for x in range(W):
            if key[y, x] and not lab[y, x]:
                rid = len(regions) + 1
                q = deque([(y, x)])
                lab[y, x] = rid
                pix = []
                while q:
                    a, b = q.popleft()
                    pix.append((a, b))
                    for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        na, nb = a + da, b + db
                        if 0 <= na < H and 0 <= nb < W and not lab[na, nb] and key[na, nb] == key[y, x]:
                            lab[na, nb] = rid
                            q.append((na, nb))
                regions.append(dict(id=rid, role=int(role[y, x]), w=float(wl[y, x]), c=float(cl[y, x]), n=len(pix)))
    # merge specks into the neighbour they share the longest border with
    changed = True
    while changed:
        changed = False
        sizes = np.bincount(lab.ravel(), minlength=len(regions) + 1)
        for reg in regions:
            rid = reg["id"]
            if sizes[rid] == 0 or sizes[rid] >= MIN_REGION:
                continue
            ys, xs = np.nonzero(lab == rid)
            border = {}
            for a, b in zip(ys, xs):
                for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    na, nb = a + da, b + db
                    if 0 <= na < H and 0 <= nb < W and lab[na, nb] and lab[na, nb] != rid:
                        border[lab[na, nb]] = border.get(lab[na, nb], 0) + 1
            if border:
                target = max(border, key=border.get)
                lab[lab == rid] = target
                changed = True
            elif sizes[rid] < 6:
                lab[lab == rid] = 0
                changed = True
    return lab, {reg["id"]: reg for reg in regions}


def loops_of(mask):
    """Boundary loops of a binary mask along pixel edges (inside on the left)."""
    H, W = mask.shape
    out = {}
    pad = np.zeros((H + 2, W + 2), bool)
    pad[1:-1, 1:-1] = mask

    def add(a, b):
        out.setdefault(a, []).append(b)

    for y in range(H):
        for x in range(W):
            if not mask[y, x]:
                continue
            Y, X = y + 1, x + 1
            if not pad[Y - 1, X]:
                add((x, y), (x + 1, y))
            if not pad[Y, X + 1]:
                add((x + 1, y), (x + 1, y + 1))
            if not pad[Y + 1, X]:
                add((x + 1, y + 1), (x, y + 1))
            if not pad[Y, X - 1]:
                add((x, y + 1), (x, y))
    loops = []
    while out:
        start = next(iter(out))
        loop = [start]
        prev_dir = None
        p = start
        while True:
            options = out.get(p)
            if not options:
                break
            if len(options) > 1 and prev_dir is not None:
                # at a pinch point keep turning the same way (left), so loops stay simple
                def turn(q):
                    d = (q[0] - p[0], q[1] - p[1])
                    return -(prev_dir[0] * d[1] - prev_dir[1] * d[0])
                options.sort(key=turn)
            q = options.pop(0)
            if not options:
                del out[p]
            prev_dir = (q[0] - p[0], q[1] - p[1])
            p = q
            if p == start:
                break
            loop.append(p)
        if len(loop) >= 4:
            loops.append(loop)
    return loops


def simplify(loop, tol):
    """Douglas-Peucker on a closed loop."""
    pts = [np.array(p, float) for p in loop]
    n = len(pts)
    # start at the point farthest from the first one, split into two chains
    far = max(range(n), key=lambda i: np.sum((pts[i] - pts[0]) ** 2))

    def dp(chain):
        if len(chain) < 3:
            return chain
        a, b = chain[0], chain[-1]
        ab = b - a
        L = np.hypot(*ab)
        best, bi = -1, 0
        for i in range(1, len(chain) - 1):
            ap = chain[i] - a
            d = abs(ab[0] * ap[1] - ab[1] * ap[0]) / L if L > 1e-9 else np.hypot(*ap)
            if d > best:
                best, bi = d, i
        if best <= tol:
            return [a, b]
        left = dp(chain[: bi + 1])
        right = dp(chain[bi:])
        return left[:-1] + right

    c1 = dp(pts[: far + 1])
    c2 = dp(pts[far:] + [pts[0]])
    out = c1[:-1] + c2[:-1]
    # drop collinear points
    res = []
    for i, p in enumerate(out):
        a, b = out[i - 1], out[(i + 1) % len(out)]
        cross = (p[0] - a[0]) * (b[1] - p[1]) - (p[1] - a[1]) * (b[0] - p[0])
        if abs(cross) > 1e-9:
            res.append(p)
    return res


def trapezoids(loops):
    """Horizontal trapezoids of a polygon with holes: (y0, y1, a0, b0, a1, b1)."""
    edges = []
    for loop in loops:
        for i in range(len(loop)):
            p, q = loop[i], loop[(i + 1) % len(loop)]
            if abs(p[1] - q[1]) > 1e-9:
                edges.append((p, q))
    ys = sorted(set(round(float(p[1]), 6) for loop in loops for p in loop))
    out = []
    prev = {}
    for y0, y1 in zip(ys, ys[1:]):
        if y1 - y0 < 1e-9:
            continue
        ym = (y0 + y1) / 2
        cross = []
        for ei, (p, q) in enumerate(edges):
            lo, hi = (p, q) if p[1] < q[1] else (q, p)
            if lo[1] <= ym <= hi[1]:
                t0 = (y0 - lo[1]) / (hi[1] - lo[1])
                t1 = (y1 - lo[1]) / (hi[1] - lo[1])
                z0 = lo[0] + (hi[0] - lo[0]) * t0
                z1 = lo[0] + (hi[0] - lo[0]) * t1
                cross.append(((z0 + z1) / 2, ei, z0, z1))
        cross.sort()
        cur = {}
        for k in range(0, len(cross) - 1, 2):
            l, r = cross[k], cross[k + 1]
            key = (l[1], r[1])
            if key in prev and abs(prev[key][1] - y0) < 1e-9:
                t = prev[key]
                t[1] = y1
                t[4], t[5] = l[3], r[3]
                cur[key] = t
            else:
                t = [y0, y1, l[2], r[2], l[3], r[3]]
                out.append(t)
                cur[key] = t
        prev = cur
    return out


def primitives(trap, eps=1e-6):
    """A trapezoid as a box and right-triangle wedges (or two general triangles)."""
    y0, y1, a0, b0, a1, b1 = trap
    L, R = max(a0, a1), min(b0, b1)
    prims = []
    if R > L + eps:
        prims.append(("b", L, R, y0, y1))
        if a0 < a1 - eps:
            prims.append(("t", a1, y0, a0, y0, a1, y1))  # right angle first, then the z leg, then the y leg
        elif a1 < a0 - eps:
            prims.append(("t", a0, y1, a1, y1, a0, y0))
        if b0 > b1 + eps:
            prims.append(("t", b1, y0, b0, y0, b1, y1))
        elif b1 > b0 + eps:
            prims.append(("t", b0, y1, b1, y1, b0, y0))
    else:
        prims.append(("g", a0, y0, b0, y0, b1, y1))
        prims.append(("g", a0, y0, b1, y1, a1, y1))
    return prims


def convert(name, palette, group=None):
    V, T, F = load(name, group)
    r = rasterize(V, T, F, palette)
    lab, regs = label(r)
    zmin, ymin = r["zmin"], r["ymin"]

    def to_m(p):
        return ((p[0] - 1) * RES + zmin, (p[1] - 1) * RES + ymin)

    out_regions = []
    for rid, reg in regs.items():
        mask = lab == rid
        if not mask.any():
            continue
        loops = []
        for loop in loops_of(mask):
            s = simplify(loop, 0.9)
            if len(s) >= 3:
                loops.append([to_m(p) for p in s])
        if not loops:
            continue
        prims = []
        for t in trapezoids(loops):
            prims += primitives(t)
        out_regions.append(dict(role=ROLE_NAMES[reg["role"]], w=reg["w"], c=reg["c"], loops=loops, prims=prims, n=int(mask.sum())))
    used = V[sorted(set(t[0] - 1 for f in F for t in f))]  # only the vertices of the kept faces
    return dict(
        regions=out_regions,
        bounds=(
            float(used[:, 2].min()),
            float(used[:, 2].max()),
            float(used[:, 1].min()),
            float(used[:, 1].max()),
            float(used[:, 0].min()),
            float(used[:, 0].max()),
        ),
    )


def lua_num(v):
    s = "%.4f" % v
    s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main():
    palette = Image.open(os.path.join(KIT, "Models", "OBJ format", "Textures", "colormap.png")).convert("RGB")
    lines = [
        "--[[",
        "\tGENERATED by tools/kenney/blaster_shapes.py from the Kenney Blaster Kit (CC0,",
        "\twww.kenney.nl). Do not edit by hand: rerun the script.",
        "",
        "\tPer model, in Kenney meters (barrel along -Z, +Y up): bounds",
        "\t{ zmin, zmax, ymin, ymax, xmin, xmax } and regions { role, w (width along X),",
        "\tc (center X), loops (outline polygons { z, y, z, y, ... }), prims }. A prim is",
        '\t{ "b", z0, z1, y0, y1 } (a box), { "t", ... } (a right triangle: the right',
        '\tangle corner, the end of its Z leg, the end of its Y leg) or { "g", ... } (any',
        "\ttriangle), always as z, y pairs.",
        "]]",
        "",
        "return {",
    ]
    total = 0
    jobs = [(name, name, None) for name in MODELS]
    # the weapon case: its base and its lid (an OBJ group of its own) separately, for the opening
    jobs += [("crate-medium:base", "crate-medium", "!lid"), ("crate-medium:lid", "crate-medium", "lid")]
    for key, name, group in jobs:
        d = convert(name, palette, group)
        b = d["bounds"]
        lines.append('\t["%s"] = {' % key)
        lines.append("\t\tbounds = { %s }," % ", ".join(lua_num(v) for v in b))
        lines.append("\t\tregions = {")
        count = 0
        for reg in sorted(d["regions"], key=lambda r: -r["n"]):
            loops = ", ".join("{ %s }" % ", ".join("%s, %s" % (lua_num(p[0]), lua_num(p[1])) for p in loop) for loop in reg["loops"])
            prims = ", ".join(
                '{ "%s", %s }' % (p[0], ", ".join(lua_num(v) for v in p[1:])) for p in reg["prims"]
            )
            count += sum(1 if p[0] != "g" else 2 for p in reg["prims"])
            lines.append(
                '\t\t\t{ role = "%s", w = %s, c = %s, loops = { %s }, prims = { %s } },'
                % (reg["role"], lua_num(reg["w"]), lua_num(reg["c"]), loops, prims)
            )
        lines.append("\t\t},")
        lines.append("\t},")
        total += count
        print("%s: %d regions, ~%d parts" % (key, len(d["regions"]), count))
    lines.append("}")
    lines.append("")
    open(OUT, "w").write("\n".join(lines))
    print("wrote", OUT, "total parts ~", total)


if __name__ == "__main__":
    main()
