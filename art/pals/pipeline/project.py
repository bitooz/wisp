# python project.py SHAPE.obj PICTURE-rgba.png OUT.obj
# A stand-in for the paint: the picture projected onto the shape from the front (its box on the
# shape's front silhouette). Good enough to tell the parts apart on the front, wrong on the back.
import bpy, sys, os
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
shape, pic, out = argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=shape)
o = bpy.context.scene.objects[0]
bpy.context.view_layer.objects.active = o
o.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = o.data
xs = [v.co.x for v in me.vertices]
zs = [v.co.z for v in me.vertices]
x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
import numpy as np
from PIL import Image
a = np.array(Image.open(pic))[:, :, 3] > 128
H, W = a.shape
ys, xs_ = np.nonzero(a)
bx0, bx1, by0, by1 = xs_.min(), xs_.max() + 1, ys.min(), ys.max() + 1
uv = me.uv_layers.new(name='uv')
for l in me.loops:
    v = me.vertices[l.vertex_index].co
    fx, fy = (v.x - x0) / (x1 - x0), (z1 - v.z) / (z1 - z0)
    uv.data[l.index].uv = ((bx0 + fx * (bx1 - bx0)) / W, 1 - (by0 + fy * (by1 - by0)) / H)
img = bpy.data.images.load(os.path.abspath(pic))
m = bpy.data.materials.new('pic')
m.use_nodes = True
t = m.node_tree.nodes.new('ShaderNodeTexImage')
t.image = img
m.node_tree.links.new(t.outputs['Color'], m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
me.materials.append(m)
bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, export_materials=True, path_mode='ABSOLUTE')
