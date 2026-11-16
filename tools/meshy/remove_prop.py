# Blender: take a thing out of a processed floor's uploaded tiles (tools/meshy/process_glb.py
# "tiles") where it is fused with what stands round it, and rebuild that from the floor's mirror
# side. Only the tiles named in the config change; everything outside the edit stays as it was
# (tools/meshy/compare_tiles.py checks it). Owner 2026-11-15: the brown booth on its yellow bench
# in the Heartstone Core's hub (tools/meshy/remove_chest_2026-11-15.json).
#
# usage: Blender -b --factory-startup --python tools/meshy/remove_prop.py -- config.json
#
# config:
#   src, out (or null), report, layout {scale, ground_n, center_n}, ground (floor-local y)
#   tiles: the tiles the thing touches and the mirror side's tiles (joined while edited, split
#          again by material: a pressed face or a rebuilt one lands in the tile whose texture it uses)
#   mirror_c: the floor's mirror line x = c (floor-local studs; fit it on the floor's railing)
#   zones: [{poly: [[x, z], ...], ymin}] a vertex in a polygon above ymin is pressed to the ground
#          (heights kept at 1 %, so the top stays on top)
#   keep: [[x0, y0, z0, x1, y1, z1], ...] vertices never pressed (the posts the rebuild ends in)
#   keep_tubes: [[x0, y0, z0, x1, y1, z1, r, rc, pipe], ...] the same within r of a segment (x1..
#        at the post): a kept pipe that runs into a rebuilt post, with the post's own wall round it.
#        The mirror side's pipe there is not copied over it (faces whose normal runs across the
#        segment; pipe 0: copied all the same), nor its wall within rc (default r; rc < r: the
#        kept wall and the copied one overlap a little, no gap between them)
#   add: {poly: [[x, z], ...]} the area rebuilt: every face above the floor whose mirror image lies
#        in it (and not in a keep box) is copied from the mirror side, mirrored. polys: several
#        such areas; any_vertex: a face is copied when any corner's image lies in one (the copy
#        then reaches one face past the edge and overlaps the cut there instead of leaving a gap);
#        a number instead of true: only faces facing up at least that much (normal y)
#   mirror_shifts, donors: where a pressed face takes the floor's texture from: its mirror point
#        (shifted), else the same spot moved by a donor offset; the face's UVs continue that floor
#        face's own mapping, else its colour
#   underlay: [[x0, z0, x1, z1, y], ...] flat floor patches under joints (shown only through gaps)
#   unlayer (true): pressed faces covered by other pressed faces go (fewer triangles per tile)
#   fill (true): holes the tearing left next to kept vertices are closed in the kept piece's colour
#   shots: {prefix, target, views: [[dx, dy, dz, name], ...]} pictures after the edit
# The floor's own flat faces round the patch keep their texture and normals; faces torn between a
# pressed vertex and a standing one go; every other face keeps its corner normals.
import bpy, bmesh, sys, json, math
from mathutils import Vector, kdtree
from mathutils.bvhtree import BVHTree

cfg = json.load(open(sys.argv[sys.argv.index("--") + 1]))
L = cfg["layout"]
S, G = L["scale"], L["ground_n"]
CX, CZ = L["center_n"]
GROUND = cfg["ground"]
MC = cfg["mirror_c"]
stud = 1.0 / S


def local(w):
    return (w.x - CX) * S, (w.z - G) * S, (-w.y - CZ) * S


def by(y):
    return y / S + G


def to_b(x, z):
    return x / S + CX, -(z / S + CZ)


def mirror_bx(bx):
    # Blender x of the mirror image of Blender x about local x = MC
    x = (bx - CX) * S
    return (2 * MC - x) / S + CX


def inside(poly, x, z):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            hit = not hit
        j = i
    return hit


def in_box(x, y, z):
    return any(b[0] <= x <= b[3] and b[1] <= y <= b[4] and b[2] <= z <= b[5] for b in cfg.get("keep", []))


def tube_at(x, y, z, pick=6):
    # (the segment's unit direction, the tube) of the keep tube round the point (pick 6: within its
    # keep radius; 7: within its copy radius rc, which is r unless given)
    for t in cfg.get("keep_tubes", []):
        a, b = Vector(t[0:3]), Vector(t[3:6])
        ab = b - a
        k = max(0.0, min(1.0, (Vector((x, y, z)) - a).dot(ab) / ab.dot(ab)))
        r = t[6] if pick == 6 or len(t) <= 7 else t[7]
        if (Vector((x, y, z)) - (a + ab * k)).length <= r:
            return ab.normalized(), t
    return None


def in_keep(x, y, z):
    return in_box(x, y, z) or tube_at(x, y, z) is not None


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=cfg["src"])
objs = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
report = {"tiles": {}}

tiles = [objs[n] for n in cfg["tiles"]]
for o in tiles:
    assert o.matrix_world == o.matrix_world.Identity(4), o.name + " has a transform"
    assert len(o.data.materials) == 1, o.name
bpy.ops.object.select_all(action="DESELECT")
for o in tiles:
    o.select_set(True)
bpy.context.view_layer.objects.active = tiles[0]
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
me = ob.data
old_normals = [Vector(n.vector) for n in me.corner_normals]
old_face_loops = [list(p.loop_indices) for p in me.polygons]
old_loop_pos = [me.vertices[l.vertex_index].co.copy() for l in me.loops]

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
uv = bm.loops.layers.uv.active
orig = bm.faces.layers.int.new("sq_orig")
flag = bm.faces.layers.int.new("sq_flag")
was_floor = bm.faces.layers.int.new("sq_floor")
# (a layer added later would cost the element references taken by then; see step 2)
tube = bm.verts.layers.int.new("sq_tube")  # 1: kept for a keep_tubes pipe, whose torn end the rebuilt post closes
for f in bm.faces:
    f[orig] = f.index
    f[flag] = 0
bm.normal_update()
# each tile's colour texture (a floor face tinted by the thing's colour bleeds is taken over too)
tex = []
for m in me.materials:
    img = None
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.name.endswith("_color"):
            img = n.image
    tex.append((img.size[0], img.size[1], img.pixels[:]) if img else None)


def tint(f):
    t = tex[f.material_index]
    if t is None:
        return None
    w, h, px = t
    u = sum(l[uv].uv.x for l in f.loops) / len(f.loops)
    v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
    i = min(w - 1, max(0, int(u * w)))
    j = min(h - 1, max(0, int(v * h)))
    k = (j * w + i) * 4
    return px[k], px[k + 1], px[k + 2]


# the floor's own faces (2 = under the thing, hidden till now, or tinted by its colour: theirs goes)
orig_tree = BVHTree.FromBMesh(bm)
for f in bm.faces:
    ys = [local(v.co)[1] for v in f.verts]
    f[was_floor] = 1 if (f.normal.z > 0.9 and max(ys) < 0.25 and min(ys) > -0.35) else 0
    if f[was_floor] == 1:
        c = f.calc_center_median()
        x, _, z = local(c)
        if any(inside(zone["poly"], x, z) for zone in cfg["zones"]):
            loc, nrm, idx, d = orig_tree.ray_cast(c + Vector((0, 0, 0.05 * stud)), Vector((0, 0, 1)), 14 * stud)
            col = tint(f)
            if loc is not None or (col is not None and col[0] > col[2] * 1.05):
                f[was_floor] = 2


def is_floor(f):
    if f.normal.z < 0.95:
        return False
    _, y, _ = local(f.calc_center_median())
    return abs(y - GROUND) < 0.3


# 1. the rebuild: faces above the floor on the mirror side whose image lies in the add area
add_polys = cfg["add"].get("polys") or [cfg["add"]["poly"]]
any_vertex = cfg["add"].get("any_vertex", False)


def rebuilt_at(x, y, z):
    mx = 2 * MC - x
    return any(inside(p, mx, z) for p in add_polys) and not in_box(mx, y, z)


def mirror_pipe(f, x, y, z):
    # what of the mirror side is not copied round a kept pipe running into a rebuilt post: its own
    # pipe there (faces going round it, normal across it) and the post's wall within the copy
    # radius (the kept wall reaches out to the keep radius: the two overlap, no gap between them)
    t = tube_at(2 * MC - x, y, z)
    if t is not None and (len(t[1]) <= 8 or t[1][8]):
        n = Vector((-f.normal.x, f.normal.z, -f.normal.y))  # Blender -> local, mirrored
        if abs(n.dot(t[0])) < 0.7:
            return True
    return all(tube_at(2 * MC - lx, ly, lz, 7) is not None for lx, ly, lz in (local(v.co) for v in f.verts))


src_faces = []
for f in bm.faces:
    x, y, z = local(f.calc_center_median())
    if y < -0.08 or is_floor(f):
        continue
    reach = any_vertex is True or (any_vertex is not False and f.normal.z >= any_vertex)
    # (never a long face: a pipe's top running far out of the area would lie over the kept one)
    reach = reach and max(e.calc_length() for e in f.edges) <= 0.6 * stud
    if (rebuilt_at(x, y, z) or (reach and any(rebuilt_at(*local(v.co)) for v in f.verts))) and not mirror_pipe(f, x, y, z):
        src_faces.append(f)
dup = bmesh.ops.duplicate(bm, geom=src_faces)
new_faces = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)]
new_verts = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
for v in new_verts:
    v.co.x = mirror_bx(v.co.x)
bmesh.ops.reverse_faces(bm, faces=new_faces)
for f in new_faces:
    f[flag] = 3
rebuilt = set(new_verts)

# 2. press the thing down
moved = {}
protected = set()
for v in bm.verts:
    if v in rebuilt:
        continue
    x, y, z = local(v.co)
    if in_keep(x, y, z):
        protected.add(v)
        if not in_box(x, y, z):
            v[tube] = 1
        continue
    for zi, zone in enumerate(cfg["zones"]):
        if y > zone["ymin"] and inside(zone["poly"], x, z):
            y0 = by(GROUND)
            v.co.z = y0 + (v.co.z - y0) * 0.01
            moved[v] = zi
            break

kill = []
for f in bm.faces:
    if f[flag] == 3:
        continue
    ins = [v in moved for v in f.verts]
    if any(ins) and not all(ins):
        zs = [v.co.z for v in f.verts]
        near_kept = any(v in protected for v in f.verts)
        limit = (0.35 if near_kept else 1.5) * stud
        if max(zs) - min(zs) > limit:
            kill.append(f)
bmesh.ops.delete(bm, geom=kill, context="FACES")
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
bm.normal_update()

bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
bm.normal_update()


def low_in_zone(f):
    # a piece of the thing's foot that never rose above ymin (its rim on the ground), or the floor
    # that lay hidden under it: in a zone, flat on the ground, not the floor that showed before
    if f[was_floor] == 1:
        return False
    for v in f.verts:
        if v in protected or abs(local(v.co)[1] - GROUND) > 0.3:
            return False
    x, _, z = local(f.calc_center_median())
    return any(inside(zone["poly"], x, z) for zone in cfg["zones"])


def pressed_face(f):
    if f[flag] == 3:
        return False
    if not any(v in moved for v in f.verts):
        return low_in_zone(f)
    if f[was_floor] == 1 and not all(v in moved for v in f.verts):
        # the floor's own faces round the patch keep their texture and normals
        return False
    for v in f.verts:
        if v in moved:
            continue
        if v in protected:
            return False
        _, y, _ = local(v.co)
        if abs(y - GROUND) > 0.3:
            return False
    return True


squashed = [f for f in bm.faces if pressed_face(f)]
down = [f for f in squashed if f.normal.z < 0]
if down:
    bmesh.ops.reverse_faces(bm, faces=down)
bm.normal_update()

# 3. the pressed faces take the floor's look from their mirror point (any joined tile)
floor = [f for f in bm.faces if f[flag] not in (3, 4) and not any(v in moved for v in f.verts) and is_floor(f)]


under_faces = []
for r in cfg.get("underlay", []):
    x0, z0, x1, z1, yl = r
    n_x = max(1, int(math.ceil((x1 - x0) / 0.5)))
    n_z = max(1, int(math.ceil((z1 - z0) / 0.5)))
    grid = {}
    for i in range(n_x + 1):
        for j in range(n_z + 1):
            bx, bz = to_b(x0 + (x1 - x0) * i / n_x, z0 + (z1 - z0) * j / n_z)
            grid[(i, j)] = bm.verts.new((bx, bz, by(yl)))
    for i in range(n_x):
        for j in range(n_z):
            # (Blender y = -local z: this winding faces up)
            f = bm.faces.new((grid[(i, j)], grid[(i, j + 1)], grid[(i + 1, j + 1)], grid[(i + 1, j)]))
            under_faces.append(f)
bm.faces.ensure_lookup_table()
bm.normal_update()
for f in under_faces:
    if f.normal.z < 0:
        f.normal_flip()
    f[flag] = 4
    for l in f.loops:
        l[uv].uv = Vector((0.0, 0.0))
bm.normal_update()
squashed = squashed + under_faces

def uv_area(uvs):
    a = uvs[0]
    out = 0.0
    for k in range(1, len(uvs) - 1):
        e1, e2 = uvs[k] - a, uvs[k + 1] - a
        out += abs(e1.x * e2.y - e1.y * e2.x) / 2
    return out


dens = sorted(uv_area([l[uv].uv for l in f.loops]) / (f.calc_area() / (stud * stud)) for f in floor if f.calc_area() > 1e-12)
dens = dens[len(dens) // 2]
fverts, fpolys, index_of = [], [], {}
for f in floor:
    poly = []
    for v in f.verts:
        if v not in index_of:
            index_of[v] = len(fverts)
            fverts.append(Vector((v.co.x, v.co.y, 0.0)))
        poly.append(index_of[v])
    fpolys.append(poly)
tree = BVHTree.FromPolygons(fverts, fpolys)
kd = kdtree.KDTree(len(floor))
for i, f in enumerate(floor):
    c = f.calc_center_median()
    kd.insert((c.x, c.y, 0.0), i)
kd.balance()


def floor_at(bx, by_):
    loc, nrm, idx, d = tree.ray_cast(Vector((bx, by_, 1.0)), Vector((0, 0, -1)), 2.0)
    if loc is None:
        return None
    f = floor[idx]
    pts = [Vector((v.co.x, v.co.y)) for v in f.verts]
    uvs = [l[uv].uv.copy() for l in f.loops]
    p = Vector((bx, by_))
    for k in range(1, len(pts) - 1):
        a, b, c = pts[0], pts[k], pts[k + 1]
        v0, v1, v2 = b - a, c - a, p - a
        den = v0.x * v1.y - v1.x * v0.y
        if abs(den) < 1e-14:
            continue
        s = (v2.x * v1.y - v1.x * v2.y) / den
        t = (v0.x * v2.y - v2.x * v0.y) / den
        if s >= -1e-3 and t >= -1e-3 and s + t <= 1 + 1e-3:
            return uvs[0] + (uvs[k] - uvs[0]) * s + (uvs[k + 1] - uvs[0]) * t, f.material_index
    return None


def affine_at(bx, by_):
    loc, nrm, idx, d = tree.ray_cast(Vector((bx, by_, 1.0)), Vector((0, 0, -1)), 2.0)
    if loc is None:
        return None
    f = floor[idx]
    vs = [Vector((v.co.x, v.co.y)) for v in f.verts]
    us = [l[uv].uv.copy() for l in f.loops]
    a, b, c = vs[0], vs[1], vs[2]
    e1, e2 = b - a, c - a
    den = e1.x * e2.y - e2.x * e1.y
    if abs(den) < 1e-14:
        return None
    u1, u2 = us[1] - us[0], us[2] - us[0]

    def mp(qx, qy):
        d = Vector((qx, qy)) - a
        s_ = (d.x * e2.y - e2.x * d.y) / den
        t_ = (e1.x * d.y - d.x * e1.y) / den
        return us[0] + u1 * s_ + u2 * t_

    return mp, f.material_index


def spot(f, src):
    target = sum((l[uv].uv for l in src.loops), Vector((0.0, 0.0))) / len(src.loops)
    mid = sum((l[uv].uv for l in f.loops), Vector((0.0, 0.0))) / len(f.loops)
    ext = max(max(abs(l[uv].uv.x - mid.x), abs(l[uv].uv.y - mid.y)) for l in f.loops)
    k = min(1.0, 0.0005 / ext) if ext > 0 else 1.0
    for l in f.loops:
        l[uv].uv = target + (l[uv].uv - mid) * k
    f.material_index = src.material_index


donor_offsets = cfg.get("donors", [])
mirror_shifts = cfg.get("mirror_shifts", [[0, 0]])


def cand_points(x, z):
    return [(2 * MC - x + m[0], z + m[1]) for m in mirror_shifts] + [(x + d[0], z + d[1]) for d in donor_offsets]


def donor(x, z, only=None):
    # (uv, material, candidate) of the floor under the first donor point that hits (or candidate `only`)
    for ci, (px, pz) in enumerate(cand_points(x, z)):
        if only is not None and ci != only:
            continue
        bx, bz = to_b(px, pz)
        got = floor_at(bx, bz)
        if got is not None:
            return got[0], got[1], ci
    return None


def texel(mi, uv_):
    t = tex[mi]
    if t is None:
        return None
    w, h, px = t
    i = min(w - 1, max(0, int(uv_.x * w)))
    j = min(h - 1, max(0, int(uv_.y * h)))
    k = (j * w + i) * 4
    return px[k], px[k + 1], px[k + 2]


# the floor's usual colour (per channel median): a one-colour face takes the donor point nearest it,
# not a dark joint between the slabs that happens to lie under its centre
_cols = [c_ for c_ in (tint(f) for f in floor[:: max(1, len(floor) // 3000)]) if c_ is not None]
usual = tuple(sorted(c_[i] for c_ in _cols)[len(_cols) // 2] for i in range(3)) if _cols else None


def calm_donor(x, z):
    best = None
    for ci in range(len(cand_points(x, z))):
        got_ = donor(x, z, ci)
        if got_ is None:
            continue
        col = texel(got_[1], got_[0])
        if col is None or usual is None:
            continue
        d = sum((col[i] - usual[i]) ** 2 for i in range(3))
        if best is None or d < best[0]:
            best = (d, got_)
    return best[1] if best else None


TOL = 0.004  # UV: about 4 texels of a 1024 texture


def agrees(f, uvs, ci, mi):
    # the UVs over the face must be the floor's own between its corners: at its centre and edge
    # midpoints the interpolated UV equals the floor's (corners on different UV islands fail)
    vs = [local(v.co) for v in f.verts]
    n = len(vs)
    pts = [(sum(v[0] for v in vs) / n, sum(v[2] for v in vs) / n, sum(uvs, Vector((0.0, 0.0))) / n)]
    for k in range(n):
        a, b = vs[k], vs[k - 1]
        pts.append(((a[0] + b[0]) / 2, (a[2] + b[2]) / 2, (uvs[k] + uvs[k - 1]) / 2))
    for x, z, want in pts:
        got = donor(x, z, ci)
        if got is not None and (got[1] != mi or (got[0] - want).length > TOL):
            return False
    return True


cache = {}
cloned = spotted = 0
for f in squashed:
    per = []
    for v in f.verts:
        if v not in cache:
            x, _, z = local(v.co)
            cache[v] = donor(x, z)
        per.append(cache[v])
    ok = all(p is not None for p in per) and len({(p[1], p[2]) for p in per}) == 1
    if ok:
        uvs = [p[0] for p in per]
        ok = agrees(f, uvs, per[0][2], per[0][1])
    if ok:
        for l, u in zip(f.loops, uvs):
            l[uv].uv = u
        f.material_index = per[0][1]
        cloned += 1
    else:
        c = f.calc_center_median()
        x, _, z = local(c)
        got = donor(x, z)
        done = False
        if got is not None:
            # continue the floor face under the centre over the whole face, if that agrees
            bx, bz = to_b(*cand_points(x, z)[got[2]])
            aff = affine_at(bx, bz)
            if aff is not None:
                mp, mi = aff
                uvs = []
                for l in f.loops:
                    lx, _, lz = local(l.vert.co)
                    uvs.append(mp(*to_b(*cand_points(lx, lz)[got[2]])))
                if agrees(f, uvs, got[2], mi) and all(
                    (lambda d: d is None or (d[1] == mi and (d[0] - u).length <= TOL))(donor(local(l.vert.co)[0], local(l.vert.co)[2], got[2]))
                    for l, u in zip(f.loops, uvs)
                ):
                    for l, u in zip(f.loops, uvs):
                        l[uv].uv = u
                    f.material_index = mi
                    done = True
            if not done:
                # one colour: the floor's own at a donor point near the face's centre, the one
                # nearest the floor's usual colour
                g2 = calm_donor(x, z) or got
                mid = sum((l[uv].uv for l in f.loops), Vector((0.0, 0.0))) / len(f.loops)
                ext = max(max(abs(l[uv].uv.x - mid.x), abs(l[uv].uv.y - mid.y)) for l in f.loops)
                k = min(1.0, 0.0005 / ext) if ext > 0 else 1.0
                for l in f.loops:
                    l[uv].uv = g2[0] + (l[uv].uv - mid) * k
                f.material_index = g2[1]
                done = True
        if not done:
            _, i, _ = kd.find((c.x, c.y, 0.0))
            spot(f, floor[i])
        spotted += 1
    f[flag] = 1

# pressed faces under other pressed faces never show: they go (fewer triangles per tile)
unlayered = 0
if cfg.get("unlayer", True):
    sq = [f for f in bm.faces if f[flag] == 1]
    sverts, spolys, sidx = [], [], {}
    for f in sq:
        poly = []
        for v in f.verts:
            if v not in sidx:
                sidx[v] = len(sverts)
                sverts.append(v.co.copy())
            poly.append(sidx[v])
        spolys.append(poly)
    stree = BVHTree.FromPolygons(sverts, spolys)
    hidden = []
    for i, f in enumerate(sq):
        c = f.calc_center_median()
        vs = [v.co for v in f.verts]
        pts = [c] + [c + (q - c) * 0.97 for q in vs] + [c + ((vs[k] + vs[k - 1]) / 2 - c) * 0.97 for k in range(len(vs))]
        covered = True
        for p in pts:
            loc, nrm, idx, d = stree.ray_cast(Vector((p.x, p.y, p.z + 1.0)), Vector((0, 0, -1)), 2.0)
            if loc is None or idx == i or loc.z <= p.z + 1e-7:
                covered = False
                break
        if covered:
            hidden.append(f)
    bmesh.ops.delete(bm, geom=hidden, context="FACES")
    bm.faces.ensure_lookup_table()
    unlayered = len(hidden)

# 4. close small holes the torn faces left in the kept posts
bm.edges.ensure_lookup_table()
live = [v for v in protected if v.is_valid and not v[tube]]
prot_pts = kdtree.KDTree(max(len(live), 1))
for i, v in enumerate(live):
    prot_pts.insert(v.co, i)
prot_pts.balance()
open_edges = [e for e in bm.edges if e.is_boundary and live and prot_pts.find((e.verts[0].co + e.verts[1].co) / 2)[2] < 1.0 * stud]
filled = 0
if open_edges and cfg.get("fill", True):
    res = bmesh.ops.holes_fill(bm, edges=open_edges, sides=cfg.get("fill_sides", 80))
    newf = set(res["faces"])
    for f in res["faces"]:
        nb = None
        for e in f.edges:
            for g in e.link_faces:
                if g not in newf:
                    nb = g
                    break
            if nb:
                break
        if nb is not None:
            spot(f, nb)
        f[flag] = 2
        filled += 1
bm.normal_update()

bm.to_mesh(me)
bm.free()
me.update()
o_attr = me.attributes["sq_orig"].data
f_attr = me.attributes["sq_flag"].data
normals = [None] * len(me.loops)
for p in me.polygons:
    fl = f_attr[p.index].value
    if fl == 1:
        for li in p.loop_indices:
            normals[li] = Vector((0, 0, 1))
    elif fl == 2:
        for li in p.loop_indices:
            normals[li] = p.normal.copy()
    elif fl == 3:
        src = old_face_loops[o_attr[p.index].value]
        for li in p.loop_indices:
            pos = me.vertices[me.loops[li].vertex_index].co
            back = Vector((mirror_bx(pos.x), pos.y, pos.z))
            best = min(src, key=lambda oi: (old_loop_pos[oi] - back).length)
            n = old_normals[best]
            normals[li] = Vector((-n.x, n.y, n.z))
    else:
        src = old_face_loops[o_attr[p.index].value]
        for li, oi in zip(p.loop_indices, src):
            normals[li] = old_normals[oi]
me.normals_split_custom_set(normals)
if cfg.get("debug_glb"):
    # (a check copy: copied faces red, pressed blue, kept-pipe faces green, filled yellow, others grey)
    dbg = ob.copy()
    dbg.data = me.copy()
    bpy.context.scene.collection.objects.link(dbg)
    dm = dbg.data
    dm.materials.clear()
    for name, col in (("rest", (0.5, 0.5, 0.5, 1)), ("mirror", (0.9, 0.1, 0.1, 1)), ("pressed", (0.1, 0.2, 0.9, 1)),
                      ("pipe", (0.1, 0.8, 0.1, 1)), ("fill", (0.9, 0.9, 0.1, 1))):
        m = bpy.data.materials.new("dbg_" + name)
        m.diffuse_color = col
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = col
        dm.materials.append(m)
    fl = dm.attributes["sq_flag"].data
    tb = dm.attributes["sq_tube"].data
    for p_ in dm.polygons:
        f_ = fl[p_.index].value
        if f_ == 3:
            p_.material_index = 1
        elif f_ in (1, 4):
            p_.material_index = 2
        elif f_ == 2:
            p_.material_index = 4
        elif all(tb[i].value for i in p_.vertices):
            p_.material_index = 3
        else:
            p_.material_index = 0
    bpy.ops.object.select_all(action="DESELECT")
    dbg.select_set(True)
    bpy.context.view_layer.objects.active = dbg
    bpy.ops.export_scene.gltf(filepath=cfg["debug_glb"], export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_animations=False)
    bpy.data.objects.remove(dbg, do_unlink=True)
me.attributes.remove(me.attributes["sq_orig"])
me.attributes.remove(me.attributes["sq_flag"])
me.attributes.remove(me.attributes["sq_floor"])
me.attributes.remove(me.attributes["sq_tube"])
me.update()
report.update({"mirror_src": len(src_faces), "moved": len(moved), "protected": len(protected), "torn": len(kill),
               "squashed": len(squashed), "cloned": cloned, "spotted": spotted, "filled": filled, "unlayered": unlayered,
               "open_edges": len(open_edges)})

bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="MATERIAL")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
out_objs = []
for o in parts:
    used = {p.material_index for p in o.data.polygons}
    if not used:
        bpy.data.objects.remove(o, do_unlink=True)
        continue
    assert len(used) == 1, used
    mname = o.data.materials[list(used)[0]].name
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.material_slot_remove_unused()
    o.name = mname
    o.data.name = mname
    out_objs.append(o)


def info(o):
    used = {i for p in o.data.polygons for i in p.vertices}
    xs = [o.data.vertices[i].co for i in used]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    c = (lo + hi) / 2
    return {"tris": sum(len(p.vertices) - 2 for p in o.data.polygons), "center": [round(c.x, 5), round(c.z, 5), round(-c.y, 5)],
            "size": [round(hi.x - lo.x, 5), round(hi.z - lo.z, 5), round(hi.y - lo.y, 5)]}


for o in out_objs:
    report["tiles"][o.name] = info(o)
if cfg.get("out"):
    bpy.ops.object.select_all(action="DESELECT")
    for o in out_objs:
        for m in o.data.materials:
            if m:
                m.use_backface_culling = True
        o.select_set(True)
    bpy.context.view_layer.objects.active = out_objs[0]
    bpy.ops.export_scene.gltf(filepath=cfg["out"], export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT", export_image_format="AUTO", export_animations=False)
json.dump(report, open(cfg["report"], "w"), indent=1)
print("REPORT", json.dumps(report))

shots = cfg.get("shots")
if shots:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    sc.render.resolution_x = 1200
    sc.render.resolution_y = 900
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.color = (0.0, 0.45, 0.0) if shots.get("green") else (0.08, 0.08, 0.1)
    sc.render.image_settings.file_format = "JPEG"
    tx, ty, tz = shots["target"]

    def bl(x, y, z):
        return Vector((x / S + CX, -(z / S + CZ), y / S + G))

    tgt = bpy.data.objects.new("T", None)
    sc.collection.objects.link(tgt)
    tgt.location = bl(tx, ty, tz)
    cd = bpy.data.cameras.new("C")
    cd.lens = shots.get("lens", 35)
    cd.clip_start = 0.005
    cd.clip_end = 100
    cam = bpy.data.objects.new("C", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    con = cam.constraints.new("TRACK_TO")
    con.target = tgt
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    for dx, dy, dz, nm in shots["views"]:
        cam.location = bl(tx + dx, ty + dy, tz + dz)
        sc.render.filepath = shots["prefix"] + nm + ".jpg"
        bpy.ops.render.render(write_still=True)
        print("SHOT", sc.render.filepath)
