# Blender: surface spots + average colour of processed meshes (rocks: where glints and cracks go).
# usage: Blender -b --factory-startup --python surface_spots.py -- out.json count file.glb [file.glb ...]
# Spots are face centres on the upper/outer surface, spread out by farthest-point sampling, in Roblox
# axes as fractions of the mesh's box (-0.5..0.5 per axis, from the box centre) with the face normal.
import bpy, sys, json, os, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_path, count, files = argv[0], int(argv[1]), argv[2:]
result = json.load(open(out_path)) if os.path.exists(out_path) else {}

def to_rbx(v):
    return Vector((v.x, v.z, -v.y))

for path in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    ob = obs[0]
    me = ob.data
    mw = ob.matrix_world
    verts = [to_rbx(mw @ v.co) for v in me.vertices]
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    size = hi - lo
    ctr = (lo + hi) / 2
    nmat = mw.to_3x3()
    # colour: sample the base colour image at face centres (area weighted)
    img = None
    mat = me.materials[0] if me.materials else None
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and n.outputs['Color'].links and any(l.to_socket.name == 'Base Color' for l in n.outputs['Color'].links):
                img = n.image
    px = None
    if img is not None and img.size[0] > 0:
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    uv = me.uv_layers.active.data if me.uv_layers.active else None
    cands = []
    csum = np.zeros(3); wsum = 0.0
    for p in me.polygons:
        c = to_rbx(mw @ p.center)
        n = to_rbx(nmat @ p.normal).normalized()
        if px is not None and uv is not None:
            u = sum(uv[li].uv.x for li in p.loop_indices) / len(p.loop_indices)
            v = sum(uv[li].uv.y for li in p.loop_indices) / len(p.loop_indices)
            x = min(max(int(u * (px.shape[1] - 1)), 0), px.shape[1] - 1)
            y = min(max(int(v * (px.shape[0] - 1)), 0), px.shape[0] - 1)
            csum += px[y, x, :3] * p.area; wsum += p.area
        rel = (c - ctr)
        height = (c.y - lo.y) / max(size.y, 1e-6)
        outward = Vector((rel.x, 0, rel.z))
        out_dot = n.dot(outward.normalized()) if outward.length > 1e-6 else 0
        # upper and outer faces, not the foot
        if height > 0.25 and height < 0.92 and (n.y > 0.25 or out_dot > 0.55) and p.area > 0:
            cands.append((c, n))
    spots = []
    if cands:
        pts = np.array([[c.x, c.y, c.z] for c, _ in cands])
        # farthest-point sampling starting from the highest candidate
        chosen = [int(np.argmax(pts[:, 1]))]
        d = np.linalg.norm(pts - pts[chosen[0]], axis=1)
        while len(chosen) < min(count, len(cands)):
            i = int(np.argmax(d)); chosen.append(i)
            d = np.minimum(d, np.linalg.norm(pts - pts[i], axis=1))
        for i in chosen:
            c, n = cands[i]
            r = c - ctr
            spots.append([round(r.x / size.x, 4), round(r.y / size.y, 4), round(r.z / size.z, 4), round(n.x, 3), round(n.y, 3), round(n.z, 3)])
    # Image.pixels of an 8-bit image are its stored (sRGB) values: average them as they are
    avg = (csum / wsum) if wsum > 0 else np.array([0.5, 0.5, 0.5])
    srgb = [float(c) for c in avg]
    name = os.path.basename(path)[:-4]
    result[name] = {"spots": spots, "tint": [round(min(max(c, 0), 1), 4) for c in srgb]}
    print("SPOTS", name, len(spots), result[name]["tint"])
json.dump(result, open(out_path, "w"), indent=1)
