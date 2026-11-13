# Blender batch: Meshy GLB -> Roblox-ready GLB (<= 20k tris per mesh, textures <= 1024).
# usage: Blender -b --factory-startup --python process_glb.py -- jobs.json
import bpy, bmesh, sys, os, math, json, time
from mathutils import Vector

def log(*a):
    print("[proc]", *a, flush=True)

def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception as e:
        log("GPU setup failed", e)
    sc.cycles.samples = 1
    sc.cycles.use_denoising = False
    return sc

def select_only(objs, active):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active

def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    select_only(meshes, meshes[0])
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o != ob and o.name in bpy.data.objects and o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    return ob

def bbox(ob):
    xs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return lo, hi

def normalize(ob, anchor, size):
    # anchor 'bottom' = bbox bottom-center at origin, 'center' = bbox center; scale so max dim = size
    lo, hi = bbox(ob)
    c = (lo + hi) / 2
    if anchor == 'bottom':
        c.z = lo.z
    k = size / max(hi - lo)
    for v in ob.data.vertices:
        v.co = (v.co - c) * k
    ob.data.update()
    return k

def weld(ob, frac):
    lo, hi = bbox(ob)
    select_only([ob], ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=max(hi - lo) * frac)
    bpy.ops.object.mode_set(mode='OBJECT')

def decimate_to(ob, target):
    n = tri_count(ob)
    if n <= target:
        return
    select_only([ob], ob)
    m = ob.modifiers.new("dec", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = target / n
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=m.name)

def fresh_uv(ob, margin):
    while ob.data.uv_layers:
        ob.data.uv_layers.remove(ob.data.uv_layers[0])
    ob.data.uv_layers.new(name="UVMap")
    select_only([ob], ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    try:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin, shape_method='CONCAVE')
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT')

def make_emit(ob):
    for mat in ob.data.materials:
        if not mat or not mat.use_nodes:
            continue
        nt = mat.node_tree
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not out or not bsdf:
            continue
        src = bsdf.inputs['Base Color'].links[0].from_socket if bsdf.inputs['Base Color'].links else None
        em = nt.nodes.new('ShaderNodeEmission')
        if src:
            nt.links.new(src, em.inputs['Color'])
        else:
            em.inputs['Color'].default_value = bsdf.inputs['Base Color'].default_value
        nt.links.new(em.outputs['Emission'], out.inputs['Surface'])

def new_image(name, size, data):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    if data:
        img.colorspace_settings.name = 'Non-Color'
    return img

def bake_material(name, size, want_normal):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Roughness'].default_value = 0.85
    tc = nt.nodes.new('ShaderNodeTexImage'); tc.image = new_image(name + "_color", size, False)
    nt.links.new(tc.outputs['Color'], bsdf.inputs['Base Color'])
    tn = None
    if want_normal:
        tn = nt.nodes.new('ShaderNodeTexImage'); tn.image = new_image(name + "_normal", size, True)
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(tn.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    return mat, tc, tn

def bake(high, low, mats, extrusion, want_normal):
    sc = bpy.context.scene
    select_only([high, low], low)
    b = sc.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = extrusion
    b.max_ray_distance = extrusion * 3
    b.margin = 8
    b.use_clear = True
    for (mat, tc, tn) in mats:
        mat.node_tree.nodes.active = tc
    t = time.time()
    bpy.ops.object.bake(type='EMIT')
    log("  bake color", round(time.time() - t, 1), "s")
    if want_normal:
        for (mat, tc, tn) in mats:
            mat.node_tree.nodes.active = tn
        t = time.time()
        bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
        log("  bake normal", round(time.time() - t, 1), "s")
    for (mat, tc, tn) in mats:
        for im in (tc.image, tn.image if tn else None):
            if im:
                im.pack()

def resize_textures(ob, size):
    for mat in ob.data.materials:
        if not mat or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and max(n.image.size) > size:
                n.image.scale(size, size)
                n.image.pack()

def export(objs, path):
    for o in objs:
        for m in o.data.materials:
            if m:
                m.use_backface_culling = True
    select_only(objs, objs[0])
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_texcoords=True, export_normals=True,
                              export_materials='EXPORT', export_image_format='AUTO', export_animations=False)

def smooth(ob, deg):
    select_only([ob], ob)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(deg))
    except Exception:
        bpy.ops.object.shade_smooth()

def info(ob):
    lo, hi = bbox(ob)
    # Roblox / glTF axes: X, Y(up) = Blender Z, Z = -Blender Y
    c = (lo + hi) / 2
    return {"tris": tri_count(ob), "center": [round(c.x, 5), round(c.z, 5), round(-c.y, 5)],
            "size": [round(hi.x - lo.x, 5), round(hi.z - lo.z, 5), round(hi.y - lo.y, 5)]}

def double_side(ob):
    # back-to-back copies of every face, so meshes with flipped faces show no holes single-sided
    bm = bmesh.new(); bm.from_mesh(ob.data)
    orig = list(bm.faces)
    ret = bmesh.ops.duplicate(bm, geom=orig)
    newf = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
    bmesh.ops.reverse_faces(bm, faces=newf)
    bm.to_mesh(ob.data); bm.free()
    ob.data.update()

def clear_custom_normals(ob):
    select_only([ob], ob)
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception as e:
        log("  no custom normals clear", e)

# ---------------------------------------------------------------- modes
def unlayer(ob, gap):
    # up-facing faces with another up-facing face just above them (within `gap` units) are hidden
    # layers (a flattened copy of the top under it): they flicker when the mesh is squashed flat
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(bm)
    kill = []
    for f in bm.faces:
        if f.normal.z < 0.9:
            continue
        c = f.calc_center_median()
        loc, nrm, idx, dist = bvh.ray_cast(c + Vector((0, 0, 1e-5)), Vector((0, 0, 1)), gap)
        if loc is not None and idx != f.index and nrm.z > 0.9:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(ob.data); bm.free()
    log("  unlayer", len(kill), "faces")

def job_plain(j):
    ob = import_glb(j["src"])
    normalize(ob, j.get("anchor", "bottom"), j.get("unit", 4.0))
    if j.get("unlayer"):
        unlayer(ob, j["unlayer"])
    if tri_count(ob) > j["tris"]:
        decimate_to(ob, j["tris"])
    resize_textures(ob, j.get("tex", 1024))
    if j.get("double"):
        clear_custom_normals(ob)
        smooth(ob, j.get("smooth", 35))
        double_side(ob)
    ob.name = j["name"]; ob.data.name = j["name"]
    export([ob], j["out"])
    return {"parts": [dict(name=j["name"], **info(ob))]}

def job_bake(j):
    high = import_glb(j["src"])
    normalize(high, j.get("anchor", "bottom"), j.get("unit", 4.0))
    make_emit(high)
    low = high.copy(); low.data = high.data.copy(); bpy.context.collection.objects.link(low)
    weld(low, 1e-5)
    decimate_to(low, j["tris"])
    smooth(low, j.get("smooth", 40))
    fresh_uv(low, 0.006)
    mat = bake_material(j["name"], j.get("tex", 1024), j.get("normal", True))
    low.data.materials.clear(); low.data.materials.append(mat[0])
    lo, hi = bbox(low)
    bake(high, low, [mat], max(hi - lo) * j.get("extr", 0.02), j.get("normal", True))
    if j.get("double"):
        double_side(low)
    low.name = j["name"]; low.data.name = j["name"]
    export([low], j["out"])
    return {"parts": [dict(name=j["name"], **info(low))]}

def cut_boxes(ob, boxes):
    # delete the faces whose centre lies in any box (Blender axes, normalized units): openings
    # carved into a diorama (passages the game needs); the floor surface under them stays
    if not boxes:
        return
    bm = bmesh.new(); bm.from_mesh(ob.data)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        for b in boxes:
            if b[0] <= c.x <= b[3] and b[1] <= c.y <= b[4] and b[2] <= c.z <= b[5]:
                kill.append(f)
                break
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(ob.data); bm.free()
    log("  cut", len(kill), "faces")

def local_boxes_to_blender(j):
    # j["cuts"]: [[x0, y0, z0, x1, y1, z1], ...] in floor-local studs (Roblox axes) with
    # j["layout"] = {"scale", "ground_n", "center_n": [cx, cz]} of that floor
    out = []
    lay = j.get("layout")
    for c in j.get("cuts", []):
        s, g = lay["scale"], lay["ground_n"]; cx, cz = lay["center_n"]
        rx0, rx1 = c[0] / s + cx, c[3] / s + cx
        ry0, ry1 = c[1] / s + g, c[4] / s + g
        rz0, rz1 = c[2] / s + cz, c[5] / s + cz
        # Roblox (x, y, z) -> Blender (x, -z, y)
        out.append((rx0, -rz1, ry0, rx1, -rz0, ry1))
    return out

def job_tiles(j):
    # big diorama: decimate whole, split into a grid of tiles (<= cap tris each), bake one texture per tile
    high = import_glb(j["src"])
    normalize(high, "bottom", j.get("unit", 4.0))
    cut_boxes(high, local_boxes_to_blender(j))
    make_emit(high)
    low = high.copy(); low.data = high.data.copy(); bpy.context.collection.objects.link(low)
    weld(low, 1e-5)
    decimate_to(low, j["tris"])
    smooth(low, j.get("smooth", 35))
    lo, hi = bbox(low)
    cap = j.get("cap", 19000)
    # assign faces to cells, split cells over the cap
    bm = bmesh.new(); bm.from_mesh(low.data)
    bm.faces.ensure_lookup_table()
    cent = [f.calc_center_median() for f in bm.faces]
    cells = []
    def split(idx, x0, x1, y0, y1, depth):
        if len(idx) <= cap or depth > 4:
            if idx:
                cells.append(idx)
            return
        xm = (x0 + x1) / 2; ym = (y0 + y1) / 2
        q = [[], [], [], []]
        for i in idx:
            c = cent[i]
            q[(1 if c.x >= xm else 0) + (2 if c.y >= ym else 0)].append(i)
        split(q[0], x0, xm, y0, ym, depth + 1); split(q[1], xm, x1, y0, ym, depth + 1)
        split(q[2], x0, xm, ym, y1, depth + 1); split(q[3], xm, x1, ym, y1, depth + 1)
    g = j.get("grid", 4)
    for gx in range(g):
        for gy in range(g):
            x0 = lo.x + (hi.x - lo.x) * gx / g; x1 = lo.x + (hi.x - lo.x) * (gx + 1) / g
            y0 = lo.y + (hi.y - lo.y) * gy / g; y1 = lo.y + (hi.y - lo.y) * (gy + 1) / g
            idx = [i for i, c in enumerate(cent) if (x0 <= c.x < x1 or (gx == g - 1 and c.x >= x1)) and (y0 <= c.y < y1 or (gy == g - 1 and c.y >= y1))]
            split(idx, x0, x1, y0, y1, 0)
    face_cell = [0] * len(bm.faces)
    for ci, idx in enumerate(cells):
        for i in idx:
            face_cell[i] = ci
    bm.free()
    low.data.materials.clear()
    mats = []
    for ci in range(len(cells)):
        m = bake_material("%s_%02d" % (j["name"], ci + 1), j.get("tex", 1024), j.get("normal", False))
        low.data.materials.append(m[0]); mats.append(m)
    low.data.polygons.foreach_set("material_index", face_cell)
    low.data.update()
    log("  tiles", len(cells), [len(c) for c in cells])
    # UVs per tile: each tile fills its own 0..1 square
    while low.data.uv_layers:
        low.data.uv_layers.remove(low.data.uv_layers[0])
    low.data.uv_layers.new(name="UVMap")
    select_only([low], low)
    bpy.ops.object.mode_set(mode='EDIT')
    for ci in range(len(cells)):
        bpy.ops.mesh.select_all(action='DESELECT')
        low.active_material_index = ci
        bpy.ops.object.material_slot_select()
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
        try:
            bpy.ops.uv.pack_islands(rotate=True, margin=0.004, shape_method='CONCAVE')
        except TypeError:
            bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
    bpy.ops.object.mode_set(mode='OBJECT')
    bake(high, low, mats, max(hi - lo) * j.get("extr", 0.012), j.get("normal", False))
    # separate tiles
    select_only([low], low)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    tiles = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o != high]
    parts = []
    for o in tiles:
        mname = o.data.materials[0].name if o.data.materials else o.name
        o.name = mname; o.data.name = mname
        # keep only the material the faces use
        parts.append(dict(name=mname, **info(o)))
    bpy.data.objects.remove(high, do_unlink=True)
    export(tiles, j["out"])
    return {"parts": sorted(parts, key=lambda p: p["name"])}

MODES = {"plain": job_plain, "bake": job_bake, "tiles": job_tiles}

jobs = json.load(open(sys.argv[sys.argv.index("--") + 1]))
manifest_path = jobs["manifest"]
manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
for j in jobs["jobs"]:
    if j.get("skip_if_done") and os.path.exists(j["out"]) and j["name"] in manifest:
        continue
    t = time.time()
    reset()
    try:
        res = MODES[j["mode"]](j)
        res["file"] = os.path.basename(j["out"]); res["src"] = os.path.basename(j["src"]); res["mode"] = j["mode"]
        manifest[j["name"]] = res
        json.dump(manifest, open(manifest_path, "w"), indent=1)
        log("OK", j["name"], round(time.time() - t, 1), "s", [(p["name"], p["tris"]) for p in res["parts"]][:3], len(res["parts"]))
    except Exception as e:
        import traceback; traceback.print_exc()
        log("FAIL", j["name"], e)
log("ALL DONE")
