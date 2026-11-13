# Blender: a top-down orthographic picture of a processed floor .glb (Roblox axes: +X right, +Z down
# in the picture = the floor's front), with a 1-unit grid, for laying out the floor's gameplay spots.
# usage: Blender -b --factory-startup --python topdown.py -- floor.glb out.png px
import bpy, sys, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
path, out, px = argv[0], argv[1], int(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = px; sc.render.resolution_y = px
sc.view_settings.view_transform = 'Standard'
bpy.ops.import_scene.gltf(filepath=path)
obs = [o for o in sc.objects if o.type == 'MESH']
lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
for o in obs:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))); hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
span = max(hi.x - lo.x, hi.y - lo.y) * 1.02
cam_data = bpy.data.cameras.new("C"); cam_data.type = 'ORTHO'; cam_data.ortho_scale = span
cam = bpy.data.objects.new("C", cam_data); sc.collection.objects.link(cam)
cam.location = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z + 10)
cam.rotation_euler = (0, 0, 0)   # looking down -Z, image up = Blender +Y = Roblox -Z (the back)
cam_data.clip_end = 100
sc.camera = cam
w = bpy.data.worlds.new("W"); sc.world = w; w.color = (0.1, 0.1, 0.12)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("TOPDOWN", out, "x", round(lo.x, 3), round(hi.x, 3), "z(back..front)", round(-hi.y, 3), round(-lo.y, 3), "span", round(span, 3))
