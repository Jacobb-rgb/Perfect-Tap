"""
Converts chosen pieces of other Kenney kits (Space Station Kit, Mini Dungeon,
City Kit Commercial; all CC0) into part data for the Luau builders, the same
way tools/kenney/blaster_shapes.py does for the blasters: a 2.5D rebuild from
one projection. Here every piece picks its projection axis (x = side view,
z = front view for walls, y = top view for floors) and every region keeps
its real palette color.

  python3 tools/kenney/kit_shapes.py <kits dir> [out file]
  <kits dir> holds the unzipped kits as kenney_space-station-kit/, kenney_mini-dungeon/,
  kenney_city-kit-commercial/ (each with Models/OBJ format/...).
  default out: tools/lune/lib/kenney_kit_shapes.luau
"""

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blaster_shapes as bs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
KITS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "..", "kity")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "tools", "lune", "lib", "kenney_kit_shapes.luau")

SPACE, DUNGEON, CITY = "kenney_space-station-kit", "kenney_mini-dungeon", "kenney_city-kit-commercial"

# (kit, model, projection axis, pixel size in meters)
PIECES = [
    (SPACE, "wall", "z", 0.008),
    (SPACE, "wall-window", "z", 0.008),
    (SPACE, "wall-door-wide", "z", 0.008),
    (SPACE, "wall-banner", "z", 0.008),
    (SPACE, "wall-pillar", "z", 0.008),
    (SPACE, "wall-detail", "z", 0.006),
    (SPACE, "wall-corner", "z", 0.008),
    (SPACE, "display-wall-wide", "z", 0.004),
    (SPACE, "display-wall", "z", 0.004),
    (SPACE, "computer-wide", "x", 0.005),
    (SPACE, "computer-screen", "x", 0.004),
    (SPACE, "table-large", "z", 0.006),
    (SPACE, "container", "z", 0.005),
    (SPACE, "container-tall", "z", 0.005),
    (SPACE, "structure", "z", 0.008),
    (SPACE, "structure-barrier", "z", 0.006),
    (SPACE, "rail", "z", 0.005),
    (SPACE, "stairs", "x", 0.006),
    (SPACE, "floor-panel", "y", 0.008),
    (SPACE, "pipe", "x", 0.005),
    (DUNGEON, "character-human", "z", 0.004),
    (DUNGEON, "banner", "z", 0.005),
    (DUNGEON, "column", "z", 0.006),
    (DUNGEON, "wall", "z", 0.008),
    (DUNGEON, "wall-opening", "z", 0.008),
    (DUNGEON, "wood-structure", "z", 0.008),
    (DUNGEON, "wood-support", "z", 0.006),
    (DUNGEON, "barrel", "x", 0.005),
    (DUNGEON, "chest", "x", 0.005),
    (DUNGEON, "stairs", "x", 0.006),
    (DUNGEON, "shield-round", "z", 0.004),
    (CITY, "detail-awning-wide", "x", 0.004),
    (CITY, "detail-overhang-wide", "x", 0.004),
]

# How a projection axis turns the model so that it becomes the X (depth) axis of the rasterizer:
# a rotation, so the builder can turn the result back exactly.
ROTATE = {
    "x": lambda V: V,
    "z": lambda V: np.stack([V[:, 2], V[:, 1], -V[:, 0]], axis=1),  # about Y by +90 degrees
    "y": lambda V: np.stack([V[:, 1], -V[:, 0], V[:, 2]], axis=1),  # about Z by -90 degrees
}


def load(kit, name):
    V, T, F = [], [], []
    for line in open(os.path.join(KITS, kit, "Models", "OBJ format", name + ".obj")):
        p = line.split()
        if not p:
            continue
        if p[0] == "v":
            V.append(tuple(map(float, p[1:4])))
        elif p[0] == "vt":
            T.append(tuple(map(float, p[1:3])))
        elif p[0] == "f":
            F.append([tuple(int(x) for x in q.split("/")[:2]) for q in p[1:]])
    return np.array(V), T, F


def convert(kit, name, axis, res):
    palette = Image.open(os.path.join(KITS, kit, "Models", "OBJ format", "Textures", "colormap.png")).convert("RGB")
    V, T, F = load(kit, name)
    V = ROTATE[axis](V)
    bs.RES = res
    r = bs.rasterize(V, T, F, palette)
    # the visible palette color of every pixel (seen from +X), next to the role
    color = np.zeros((r["H"], r["W"], 3))
    zmin, ymin = r["zmin"], r["ymin"]
    best = np.full((r["H"], r["W"]), -1e9)
    for f in F:
        for k in range(1, len(f) - 1):
            tri = [f[0], f[k], f[k + 1]]
            P = V[[t[0] - 1 for t in tri]]
            uv = [T[t[1] - 1] for t in tri]
            u = sum(a[0] for a in uv) / 3
            v = sum(a[1] for a in uv) / 3
            c = palette.getpixel((min(511, int(u * 512)), min(511, int((1 - v) * 512))))
            pz = (P[:, 2] - zmin) / res + 1
            py = (P[:, 1] - ymin) / res + 1
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
            upd = xv > best[ys, zs]
            best[ys[upd], zs[upd]] = xv[upd]
            color[ys[upd], zs[upd]] = c
    lab, regs = bs.label(r)

    def to_m(p):
        return ((p[0] - 1) * res + zmin, (p[1] - 1) * res + ymin)

    out = []
    for rid, reg in regs.items():
        mask = lab == rid
        if not mask.any():
            continue
        loops = []
        for loop in bs.loops_of(mask):
            s = bs.simplify(loop, 0.9)
            if len(s) >= 3:
                loops.append([to_m(p) for p in s])
        if not loops:
            continue
        prims = []
        for t in bs.trapezoids(loops):
            prims += bs.primitives(t)
        rgb = np.median(color[mask], axis=0)
        out.append(dict(role=bs.ROLE_NAMES[reg["role"]], w=reg["w"], c=reg["c"], rgb=rgb, loops=loops, prims=prims, n=int(mask.sum())))
    used = V[sorted(set(t[0] - 1 for f in F for t in f))]
    bounds = tuple(float(v) for v in (used[:, 2].min(), used[:, 2].max(), used[:, 1].min(), used[:, 1].max(), used[:, 0].min(), used[:, 0].max()))
    return out, bounds


def main():
    num = bs.lua_num
    lines = [
        "--[[",
        "\tGENERATED by tools/kenney/kit_shapes.py from Kenney's Space Station Kit, Mini",
        "\tDungeon and City Kit Commercial (CC0, www.kenney.nl). Do not edit by hand.",
        "",
        '\tPer piece ("kit/model"): axis (the projection: "x", "z" or "y"; the builder turns',
        "\tthe parts back), bounds { zmin, zmax, ymin, ymax, xmin, xmax } in the turned frame",
        "\t(Kenney meters), regions { role, rgb, w, c, loops, prims } like kenney_blaster_shapes.",
        "]]",
        "",
        "return {",
    ]
    total = 0
    for kit, name, axis, res in PIECES:
        regions, b = convert(kit, name, axis, res)
        key = {SPACE: "space", DUNGEON: "dungeon", CITY: "city"}[kit] + "/" + name
        lines.append('\t["%s"] = {' % key)
        lines.append('\t\taxis = "%s",' % axis)
        lines.append("\t\tbounds = { %s }," % ", ".join(num(v) for v in b))
        lines.append("\t\tregions = {")
        count = 0
        for reg in sorted(regions, key=lambda r: -r["n"]):
            loops = ", ".join("{ %s }" % ", ".join("%s, %s" % (num(p[0]), num(p[1])) for p in loop) for loop in reg["loops"])
            prims = ", ".join('{ "%s", %s }' % (p[0], ", ".join(num(v) for v in p[1:])) for p in reg["prims"])
            count += sum(1 if p[0] != "g" else 2 for p in reg["prims"])
            rgb = "{ %d, %d, %d }" % tuple(int(round(c)) for c in reg["rgb"])
            lines.append(
                '\t\t\t{ role = "%s", rgb = %s, w = %s, c = %s, loops = { %s }, prims = { %s } },'
                % (reg["role"], rgb, num(reg["w"]), num(reg["c"]), loops, prims)
            )
        lines.append("\t\t},")
        lines.append("\t},")
        total += count
        print("%s: %d regions, ~%d parts" % (key, len(regions), count))
    lines.append("}")
    lines.append("")
    open(OUT, "w").write("\n".join(lines))
    print("wrote", OUT, "total parts ~", total)


if __name__ == "__main__":
    main()
