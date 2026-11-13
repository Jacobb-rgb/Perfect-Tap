# Blender: where players can stand on a processed floor diorama (.glb), cell by cell, top down.
# usage: Blender -b --factory-startup --python floor_heights.py -- floor.glb out.json cells_per_unit
#
# Every cell shoots a ray straight down and walks through the surfaces it meets: an up-facing face
# is ground (air above, solid below), a down-facing face is the underside of something (solid
# above, air below: a bridge deck, an arch). The cell's walk height is the LOWEST ground that has at
# least CLEAR units of air above it (a path under an arch counts, lava 3 studs under a bridge deck
# does not); with none, the highest ground (a wall top). No ground at all = void (floating islands).
# Output in Roblox axes (x, y up, z front), normalized diorama units, plus the colour under each
# cell (for water/lava/path checks).
import bpy, sys, json
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
path, out, per_unit = argv[0], argv[1], float(argv[2])
CLEAR = float(argv[3]) if len(argv) > 3 else 0.5  # units of headroom that make a ground walkable

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
verts, polys, poly_obj = [], [], []
images = []
uv_of = []
for o in bpy.context.scene.objects:
    if o.type != 'MESH':
        continue
    me = o.data
    mw = o.matrix_world
    base = len(verts)
    verts += [mw @ v.co for v in me.vertices]
    img = None
    if me.materials and me.materials[0] and me.materials[0].use_nodes:
        for n in me.materials[0].node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                img = n.image
    if img is not None:
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    else:
        px = None
    images.append(px)
    uvl = me.uv_layers.active.data if me.uv_layers.active else None
    for p in me.polygons:
        polys.append([base + i for i in p.vertices])
        if uvl is not None:
            u = sum(uvl[li].uv.x for li in p.loop_indices) / len(p.loop_indices)
            v = sum(uvl[li].uv.y for li in p.loop_indices) / len(p.loop_indices)
        else:
            u = v = 0.0
        uv_of.append((len(images) - 1, u, v))
bvh = BVHTree.FromPolygons(verts, polys)
xs = np.array([v.x for v in verts]); ys = np.array([v.y for v in verts]); zs = np.array([v.z for v in verts])
lo = Vector((xs.min(), ys.min(), zs.min())); hi = Vector((xs.max(), ys.max(), zs.max()))

nx = int(round((hi.x - lo.x) * per_unit)); nz = int(round((hi.y - lo.y) * per_unit))
H = []   # walk height per cell (Roblox y, units) or None
C = []   # colour under the walk point
for iz in range(nz):           # Roblox z from back (-) to front (+): Blender y from hi to lo
    by = hi.y - (iz + 0.5) / per_unit
    rowH, rowC = [], []
    for ix in range(nx):
        bx = lo.x + (ix + 0.5) / per_unit
        origin = Vector((bx, by, hi.z + 1))
        grounds = []      # (height, air above)
        ceiling = None    # underside above the current air pocket
        z = origin.z
        for _ in range(12):
            loc, nrm, idx, dist = bvh.ray_cast(Vector((bx, by, z)), Vector((0, 0, -1)))
            if loc is None:
                break
            if nrm.z > 0.05:
                air = (ceiling - loc.z) if ceiling is not None else 1e9
                grounds.append((loc.z, air, idx))
                ceiling = None
            elif nrm.z < -0.05:
                ceiling = loc.z
            z = loc.z - 1e-4
        pick = None
        for g in sorted(grounds, key=lambda g: g[0]):
            if g[1] >= CLEAR:
                pick = g
                break
        if pick is None and grounds:
            pick = max(grounds, key=lambda g: g[0])
        if pick is None:
            rowH.append(None); rowC.append(None)
            continue
        rowH.append(round(pick[0], 4))
        img_i, u, v = uv_of[pick[2]]
        px = images[img_i]
        if px is not None:
            x = min(max(int(u * (px.shape[1] - 1)), 0), px.shape[1] - 1)
            y = min(max(int(v * (px.shape[0] - 1)), 0), px.shape[0] - 1)
            c = px[y, x, :3]
            rowC.append([round(float(c[0]), 3), round(float(c[1]), 3), round(float(c[2]), 3)])
        else:
            rowC.append(None)
    H.append(rowH); C.append(rowC)
json.dump({"lo": [lo.x, lo.z, -hi.y], "hi": [hi.x, hi.z, -lo.y], "per_unit": per_unit, "nx": nx, "nz": nz, "H": H, "C": C}, open(out, "w"))
vals = sorted(v for r in H for v in r if v is not None)
print("HEIGHTS", path.split('/')[-1], nx, "x", nz, "min", round(vals[0], 3), "median", round(vals[len(vals) // 2], 3), "max", round(vals[-1], 3), "void", sum(1 for r in H for v in r if v is None))
