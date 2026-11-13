# Blender: top-down height samples of a processed floor GLB (Roblox axes, normalized units)
# usage: Blender -b --python heightfield.py -- floor.glb out.json cells
import bpy, sys, json, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
argv = sys.argv[sys.argv.index("--") + 1:]
path, out, cells = argv[0], argv[1], int(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
dg = bpy.context.evaluated_depsgraph_get()
verts, polys = [], []
for o in bpy.context.scene.objects:
    if o.type != 'MESH':
        continue
    me = o.data; mw = o.matrix_world; base = len(verts)
    verts += [mw @ v.co for v in me.vertices]
    polys += [[base + i for i in p.vertices] for p in me.polygons]
bvh = BVHTree.FromPolygons(verts, polys)
xs = [v.x for v in verts]; ys = [v.y for v in verts]; zs = [v.z for v in verts]
lo = Vector((min(xs), min(ys), min(zs))); hi = Vector((max(xs), max(ys), max(zs)))
# grid over Blender X (Roblox X) and Blender Y (Roblox -Z)
H = []
for iz in range(cells):          # Roblox Z from back (-) to front (+)
    row = []
    bz = hi.y - (iz + 0.5) * (hi.y - lo.y) / cells   # Blender y = -Roblox z
    for ix in range(cells):
        bx = lo.x + (ix + 0.5) * (hi.x - lo.x) / cells
        hit = bvh.ray_cast(Vector((bx, bz, hi.z + 1)), Vector((0, 0, -1)))
        row.append(round(hit[0].z, 4) if hit[0] is not None else None)
    H.append(row)
json.dump({"lo": [lo.x, lo.z, -hi.y], "hi": [hi.x, hi.z, -lo.y], "cells": cells, "H": H}, open(out, "w"))
vals = sorted(v for r in H for v in r if v is not None)
print("HF", path.split('/')[-1], "cells", cells, "min", vals[0], "max", vals[-1], "median", vals[len(vals)//2], "empty", sum(1 for r in H for v in r if v is None))
