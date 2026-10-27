# blender -b --factory-startup --python front.py -- DIR box.json CW CH
# The painted mesh from the front, unlit, drawn at the concept's own size and place (the cut-out's box
# on the mesh's box), for matching the concept's face to where the mesh has it: DIR/front.png.
import bpy, sys, json, math
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
D, box, CW, CH = argv[0], json.load(open(argv[1])), int(argv[2]), int(argv[3])
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.wm.obj_import(filepath=f'{D}/textured.obj')
ob = [o for o in sc.objects if o.type == 'MESH'][0]
bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
mn = Vector([min(v[i] for v in bb) for i in range(3)]); mx = Vector([max(v[i] for v in bb) for i in range(3)])
sx = (mx.x - mn.x) / (box[2] - box[0]); sz = (mx.z - mn.z) / (box[3] - box[1]); s = (sx + sz) / 2
# The concept's middle on the mesh.
cx = mn.x + (CW / 2 - box[0]) * sx; cz = mx.z - (CH / 2 - box[1]) * sz
bpy.ops.object.camera_add(location=(cx, mn.y - 5, cz), rotation=(math.radians(90), 0, 0))
cam = sc.objects['Camera']; sc.camera = cam; cam.data.type = 'ORTHO'
cam.data.ortho_scale = max(CW * sx, CH * sz)
cam.data.sensor_fit = 'AUTO'
sc.render.engine = 'BLENDER_WORKBENCH'; sc.display.shading.light = 'FLAT'; sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x, sc.render.resolution_y = CW, CH
sc.render.film_transparent = True
sc.render.filepath = f'{D}/front.png'
bpy.ops.render.render(write_still=True)
print('FRONT_OK', sx, sz)
