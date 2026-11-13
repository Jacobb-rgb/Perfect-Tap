# Blender: render a textured 3/4 preview of each GLB (originals, for identification).
import bpy, sys, os, math, json
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = argv[0]
files = argv[1:]

def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'TEXTURE'
    sh.show_cavity = False
    sh.show_backface_culling = True
    sc.render.resolution_x = 640
    sc.render.resolution_y = 640
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new("W") if not sc.world else sc.world
    sc.world = w
    w.color = (0.82, 0.84, 0.88)
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.image_settings.quality = 88
    return sc

for path in files:
    name = os.path.basename(path).replace('Meshy_AI_', '').replace('_texture.glb', '').replace('.glb', '')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = setup_scene()
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as e:
        print("IMPORT FAIL", name, e); continue
    meshes = [o for o in sc.objects if o.type == 'MESH']
    lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3))); hi = Vector((max(hi[i], w[i]) for i in range(3)))
    ctr = (lo + hi) / 2; r = (hi - lo).length / 2
    flat = (hi.z - lo.z) < 0.35 * max(hi.x - lo.x, hi.y - lo.y)
    elev = math.radians(48 if flat else 22); az = math.radians(-35)
    d = Vector((math.cos(elev) * math.sin(az), -math.cos(elev) * math.cos(az), math.sin(elev)))
    cam_data = bpy.data.cameras.new("C"); cam_data.type = 'ORTHO'; cam_data.ortho_scale = 2 * r * 1.02
    cam = bpy.data.objects.new("C", cam_data); sc.collection.objects.link(cam)
    cam.location = ctr + d * (r * 4)
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    cam_data.clip_end = r * 10
    sc.camera = cam
    sc.render.filepath = os.path.join(out_dir, name + ".jpg")
    bpy.ops.render.render(write_still=True)
    print("DONE", name, [round(v, 3) for v in (hi - lo)])
