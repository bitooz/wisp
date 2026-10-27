# python glb2obj.py IN.glb DIR   (bpy 4.4 as a module)
# A TRELLIS.2 candidate as the rest of the pipeline takes Hunyuan3D's: DIR/textured.obj, .mtl and .jpg
# (its base colour; the rest of its PBR maps aren't used: the game's skin is matte), standing as
# Hunyuan's do (front to -Y once imported).
import bpy, sys, os, math
from mathutils import Matrix
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
src, D = argv[0], argv[1]
TURN = float(argv[2]) if len(argv) > 2 else 0.0  # degrees about the vertical, if its front isn't -Y
os.makedirs(D, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in obs: o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
if len(obs) > 1: bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if TURN: ob.data.transform(Matrix.Rotation(math.radians(TURN), 4, 'Z'))
# As many faces as Hunyuan3D's (its FaceReducer's 60k), the seams welded first (TRELLIS.2's export
# splits the mesh along its UV islands, which the rig's decimation can't collapse across)
import bmesh
bm = bmesh.new(); bm.from_mesh(ob.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(ob.data); bm.free()
if len(ob.data.polygons) > 60000:
    d = ob.modifiers.new('dec', 'DECIMATE'); d.ratio = 60000 / len(ob.data.polygons)
    bpy.ops.object.modifier_apply(modifier='dec')
img = next(n.image for m in ob.data.materials if m and m.use_nodes for n in m.node_tree.nodes
           if n.type == 'TEX_IMAGE' and n.image and any(l.to_socket.name == 'Base Color' for l in n.outputs['Color'].links))
img.filepath_raw = f'{D}/textured.jpg'; img.file_format = 'JPEG'
bpy.context.scene.render.image_settings.quality = 95
img.save()
bpy.ops.wm.obj_export(filepath=f'{D}/textured.obj', export_selected_objects=True, export_materials=True,
                      path_mode='STRIP', export_normals=True, export_uv=True)
mtl = open(f'{D}/textured.mtl').read().splitlines()
mtl = [l for l in mtl if not l.startswith(('map_', 'norm', 'disp', 'refl', 'Pr ', 'Pm ', 'Ke '))]
out = []
for l in mtl:
    out.append(l)
    if l.startswith('newmtl'): out.append('map_Kd textured.jpg')
open(f'{D}/textured.mtl', 'w').write('\n'.join(out) + '\n')
print('GLB2OBJ_OK', len(ob.data.polygons), 'faces', img.size[:])
