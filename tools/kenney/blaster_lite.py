"""
The game's light version of the Kenney Blaster Kit shapes (the owner-approved
blasters of levels 1-10): the same side-profile tracing as blaster_shapes.py,
tuned for few parts so every player can hold one on a phone.

  - only the ten models the levels use (b, c, a, j, m, g, r, p, d, e) and the
    five star blasters' (h, l, f, o, q: Config/StarBlasterData)
  - a coarser raster, small specks merged, widths within WTOL merged (the bevel
    steps fold into their slab), outlines simplified to TOL meters
  - each region is COVERED (not cut) by a few big boxes and wedges, which may
    overlap (same color and width): candidates are the boxes between the
    outline's vertex coordinates that lie inside the region and the wedges
    on its slanted edges; the one that covers the most uncovered pixels is
    taken until all but STOP of the region is covered. A region the cover
    can't reach 95% of falls back to horizontal or vertical trapezoids

  python3 tools/kenney/blaster_lite.py [kit dir] [out file]
  defaults: ../kity/kenney_blaster-kit -> src/shared/Builders/KenneyShapes.luau

Needs numpy and Pillow (see blaster_shapes.py).
"""

import importlib.util
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
KIT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "..", "kity", "kenney_blaster-kit")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "src", "shared", "Builders", "KenneyShapes.luau")

# the full tracer, loaded as a module (its own argv defaults are not used)
_spec = importlib.util.spec_from_file_location("blaster_shapes", os.path.join(HERE, "blaster_shapes.py"))
bs = importlib.util.module_from_spec(_spec)
_argv = sys.argv
sys.argv = [_argv[0], KIT]
_spec.loader.exec_module(bs)
sys.argv = _argv

from PIL import Image  # noqa: E402

MODELS = ["blaster-b", "blaster-c", "blaster-a", "blaster-j", "blaster-m", "blaster-g", "blaster-r", "blaster-p", "blaster-d", "blaster-e"]
# the five STAR blasters (rebirth-only weapons): Comet, Nebula, Pulsar, Supernova, Singularity
MODELS += ["blaster-h", "blaster-l", "blaster-f", "blaster-o", "blaster-q"]
RES = 0.004  # meters per pixel
MIN_REGION = 300  # pixels: smaller specks merge into a neighbour
TOL = 0.012  # outline simplification (meters)
WTOL = 0.03  # widths closer than this become one slab (meters)
STOP = 0.02  # the cover stops when this share of a region is left
SIL_TOL = 0.016  # the silhouettes' outline simplification (meters)

bs.RES = RES
bs.MIN_REGION = MIN_REGION
_levels = bs.levels
bs.levels = lambda values, tol, min_count: _levels(values, max(tol, WTOL), min_count)


def cost(prims):
    return sum(1 if p[0] != "g" else 2 for p in prims)


def decompose(loops):
    """Horizontal or vertical trapezoids, whichever needs fewer parts."""
    h = []
    for t in bs.trapezoids(loops):
        h += bs.primitives(t)
    flipped = [[(p[1], p[0]) for p in loop] for loop in loops]
    v = []
    for t in bs.trapezoids(flipped):
        for p in bs.primitives(t):
            if p[0] == "b":
                v.append(("b", p[3], p[4], p[1], p[2]))
            elif p[0] == "t":
                # a right triangle: the corner, then the Z leg's end, then the Y leg's end (legs swap)
                v.append(("t", p[2], p[1], p[6], p[5], p[4], p[3]))
            else:
                v.append(("g", p[2], p[1], p[4], p[3], p[6], p[5]))
    return h if cost(h) <= cost(v) else v


def poly_mask(loops, H, W):
    """Even-odd fill of loops (pixel coordinates) on an H x W grid of pixel centers."""
    yy, xx = np.mgrid[0:H, 0:W]
    px, py = xx + 0.5, yy + 0.5
    inside = np.zeros((H, W), bool)
    for L in loops:
        n = len(L)
        for i in range(n):
            (x1, y1), (x2, y2) = L[i], L[(i + 1) % n]
            if y1 == y2:
                continue
            cond = (y1 > py) != (y2 > py)
            xint = (x2 - x1) * (py - y1) / (y2 - y1) + x1
            inside ^= cond & (px < xint)
    return inside


def cover(loops, H, W):
    """A few overlapping boxes and wedges covering the region (pixel coordinates). Returns prims, coverage."""
    target = poly_mask(loops, H, W)
    total = int(target.sum())
    if total == 0:
        return [], 0.0
    xs = sorted(set(int(round(p[0])) for L in loops for p in L))
    ys = sorted(set(int(round(p[1])) for L in loops for p in L))
    sat = np.pad(target.astype(np.int32), ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    cands = []
    for i in range(len(xs)):
        for j in range(i + 1, len(xs)):
            x0, x1 = max(0, xs[i]), min(W, xs[j])
            if x1 - x0 < 2:
                continue
            for k in range(len(ys)):
                for m in range(k + 1, len(ys)):
                    y0, y1 = max(0, ys[k]), min(H, ys[m])
                    if y1 - y0 < 2:
                        continue
                    area = (x1 - x0) * (y1 - y0)
                    inside = sat[y1, x1] - sat[y0, x1] - sat[y1, x0] + sat[y0, x0]
                    if inside >= area * 0.985:
                        mask = np.zeros((H, W), bool)
                        mask[y0:y1, x0:x1] = True
                        cands.append((("b", x0, x1, y0, y1), mask))
    for L in loops:
        n = len(L)
        for i in range(n):
            p, q = L[i], L[(i + 1) % n]
            if abs(p[0] - q[0]) < 1 or abs(p[1] - q[1]) < 1:
                continue
            for corner in ((p[0], q[1]), (q[0], p[1])):
                mask = poly_mask([[p, q, corner]], H, W)
                area = mask.sum()
                if area < 4 or (mask & target).sum() < area * 0.97:
                    continue
                zend = p if p[1] == corner[1] else q  # shares the corner's y: the end of the Z leg
                yend = q if zend is p else p
                cands.append((("t", corner, zend, yend), mask))
    covered = np.zeros((H, W), bool)
    chosen = []
    while True:
        need = target & ~covered
        if need.sum() <= total * STOP:
            break
        best, gain = None, 0
        for prim, mask in cands:
            g = int((mask & need).sum())
            if g > gain:
                best, gain = (prim, mask), g
        if best is None or gain < max(3, total * 0.004):
            break
        chosen.append(best[0])
        covered |= best[1]
    return chosen, 1 - (target & ~covered).sum() / total


def convert(name, palette):
    V, T, F = bs.load(name)
    r = bs.rasterize(V, T, F, palette)
    lab, regs = bs.label(r)
    zmin, ymin = r["zmin"], r["ymin"]

    def to_m(p):
        return ((p[0] - 1) * RES + zmin, (p[1] - 1) * RES + ymin)

    H, W = lab.shape

    def to_prims(found):
        """The cover's prims (pixel coordinates) in meters."""
        out = []
        for p in found:
            if p[0] == "b":
                z0, y0 = to_m((p[1], p[3]))
                z1, y1 = to_m((p[2], p[4]))
                out.append(("b", z0, z1, y0, y1))
            else:
                c, ze, ye = to_m(p[1]), to_m(p[2]), to_m(p[3])
                out.append(("t", c[0], c[1], ze[0], ze[1], ye[0], ye[1]))
        return out

    regions = []
    for rid, reg in regs.items():
        mask = lab == rid
        if not mask.any():
            continue
        pixel_loops = []
        for loop in bs.loops_of(mask):
            s = bs.simplify(loop, TOL / RES)
            if len(s) >= 3:
                pixel_loops.append([(float(p[0]), float(p[1])) for p in s])
        if not pixel_loops:
            continue
        loops = [[to_m(p) for p in L] for L in pixel_loops]
        found, coverage = cover(pixel_loops, H + 2, W + 2)
        prims = to_prims(found) if coverage >= 0.95 else decompose(loops)
        regions.append(dict(role=bs.ROLE_NAMES[reg["role"]], w=reg["w"], c=reg["c"], loops=loops, prims=prims, n=int(mask.sum())))
    # the silhouette: every colored pixel as one region (black rack silhouettes, the LV 11 "?")
    sil_mask = r["role"] > 0
    pixel_loops = []
    for loop in bs.loops_of(sil_mask):
        simple = bs.simplify(loop, SIL_TOL / RES)
        if len(simple) >= 3:
            pixel_loops.append([(float(p[0]), float(p[1])) for p in simple])
    found, coverage = cover(pixel_loops, H + 2, W + 2)
    # (a black silhouette on a board: 90% coverage reads fine)
    sil = dict(prims=to_prims(found) if coverage >= 0.9 else decompose([[to_m(p) for p in L] for L in pixel_loops]))
    used = V[sorted(set(t[0] - 1 for f in F for t in f))]
    bounds = (
        float(used[:, 2].min()),
        float(used[:, 2].max()),
        float(used[:, 1].min()),
        float(used[:, 1].max()),
        float(used[:, 0].min()),
        float(used[:, 0].max()),
    )
    return dict(regions=regions, bounds=bounds, silhouette=sil)


def main():
    palette = Image.open(os.path.join(KIT, "Models", "OBJ format", "Textures", "colormap.png")).convert("RGB")
    n = bs.lua_num
    lines = [
        "--[[",
        "\tGENERATED by tools/kenney/blaster_lite.py from the Kenney Blaster Kit (CC0,",
        "\twww.kenney.nl): the light shapes of the ten blaster levels and the five star blasters. Do not edit by",
        "\thand: rerun the script.",
        "",
        "\tPer model, in Kenney meters (barrel along -Z, +Y up): bounds",
        "\t{ zmin, zmax, ymin, ymax, xmin, xmax } and regions { role, w (width along X),",
        "\tc (center X), loops (outline polygons { z, y, z, y, ... }), prims }. A prim is",
        '\t{ "b", z0, z1, y0, y1 } (a box), { "t", ... } (a right triangle: the right',
        '\tangle corner, the end of its Z leg, the end of its Y leg) or { "g", ... } (any',
        "\ttriangle), always as z, y pairs. silhouette = the prims of the whole gun as one",
        "\tregion (the full width): black rack silhouettes.",
        "]]",
        "",
        "export type Region = { role: string, w: number, c: number, loops: { { number } }, prims: { { any } } }",
        "export type Shape = { bounds: { number }, regions: { Region }, silhouette: { { any } } }",
        "",
        "local shapes: { [string]: Shape } = {",
    ]
    total = 0
    for name in MODELS:
        d = convert(name, palette)
        lines.append('\t["%s"] = {' % name)
        lines.append("\t\tbounds = { %s }," % ", ".join(n(v) for v in d["bounds"]))
        lines.append("\t\tregions = {")
        count = 0
        for reg in sorted(d["regions"], key=lambda r: -r["n"]):
            loops = ", ".join("{ %s }" % ", ".join("%s, %s" % (n(p[0]), n(p[1])) for p in loop) for loop in reg["loops"])
            prims = ", ".join('{ "%s", %s }' % (p[0], ", ".join(n(v) for v in p[1:])) for p in reg["prims"])
            count += cost(reg["prims"])
            lines.append(
                '\t\t\t{ role = "%s", w = %s, c = %s, loops = { %s }, prims = { %s } },'
                % (reg["role"], n(reg["w"]), n(reg["c"]), loops, prims)
            )
        lines.append("\t\t},")
        sp = ", ".join('{ "%s", %s }' % (p[0], ", ".join(n(v) for v in p[1:])) for p in d["silhouette"]["prims"])
        lines.append("\t\tsilhouette = { %s }," % sp)
        lines.append("\t},")
        print("  silhouette ~%d parts" % cost(d["silhouette"]["prims"]))
        total += count
        print("%s: %d regions, ~%d parts" % (name, len(d["regions"]), count))
    lines.append("}")
    lines.append("")
    lines.append("return shapes")
    lines.append("")
    open(OUT, "w").write("\n".join(lines))
    print("wrote", OUT, "total parts ~", total)


if __name__ == "__main__":
    main()
