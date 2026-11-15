# Blender: compare an edited tiles .glb (tools/meshy/remove_prop.py) with the original floor .glb:
# every face whose centre lies outside the edit box [x0, x1] x [z0, z1] (floor-local studs) must be
# there with the same positions and UVs (normals within rounding).
# usage: Blender -b --factory-startup --python tools/meshy/compare_tiles.py -- floor.glb tiles.glb x0 x1 z0 z1
import bpy, sys, json
argv = sys.argv[sys.argv.index("--") + 1:]
orig_path, new_path = argv[0], argv[1]
x0, x1, z0, z1 = map(float, argv[2:6])
S = 18.2756; CZ = -0.0007
def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return {o.name.split('.')[0]: o for o in bpy.data.objects if o not in before and o.type == 'MESH'}
bpy.ops.wm.read_factory_settings(use_empty=True)
new = load(new_path); orig = load(orig_path)
def table(o):
    me = o.data; uvl = me.uv_layers.active.data; nrm = me.corner_normals
    t = {}
    for p in me.polygons:
        c = p.center
        if x0 <= c.x * S <= x1 and z0 <= (-c.y - CZ) * S <= z1:
            continue
        corners = sorted(((tuple(round(v, 5) for v in me.vertices[me.loops[li].vertex_index].co), li) for li in p.loop_indices))
        key = tuple(k for k, _ in corners)
        t[key] = [(uvl[li].uv.copy(), nrm[li].vector.copy()) for _, li in corners]
    return t
out = {}
for name in sorted(new):
    a = table(orig[name]); b = table(new[name])
    missing = [k for k in a if k not in b]
    extra = [k for k in b if k not in a]
    du = dn = 0.0
    for k in a:
        if k in b:
            for (ua, na), (ub, nb) in zip(a[k], b[k]):
                du = max(du, (ua - ub).length); dn = max(dn, (na - nb).length)
    out[name] = {"outside": len(a), "missing": len(missing), "extra": len(extra), "max_uv_diff": du, "max_normal_diff": dn}
print("V2", json.dumps(out, indent=1))
