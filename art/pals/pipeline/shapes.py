# python shapes.py OUT.png RGBA.png A.obj [B.obj ...]   (bpy 4.4 as a module, or blender -b --python)
# The candidate shapes side by side, from the front and the side, untextured, after the cut-out
# picture; and how well each one's front silhouette covers the picture's (intersection over union).
import bpy, sys, math
import numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
out, ref, files = argv[0], argv[1], argv[2:]
N = 256


def mask_of(px):  # alpha box, fitted into N x N keeping the aspect, bottom-centred
    from PIL import Image
    a = (px[:, :, 3] > 128)
    ys, xs = np.nonzero(a)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = a.shape
    s = N / max(h, w)
    im = Image.fromarray((a * 255).astype(np.uint8)).resize((max(1, round(w * s)), max(1, round(h * s))))
    c = np.zeros((N, N), bool)
    b = np.array(im) > 128
    x0 = (N - b.shape[1]) // 2
    c[N - b.shape[0]:, x0:x0 + b.shape[1]] = b
    return c


from PIL import Image
ref_px = np.array(Image.open(ref).convert('RGBA'))
ref_mask = mask_of(ref_px)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.show_cavity = True
sc.render.film_transparent = True
objs = []
for f in files:
    before = set(sc.objects)
    bpy.ops.wm.obj_import(filepath=f)
    o = [o for o in sc.objects if o not in before][0]
    bpy.context.view_layer.update()
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    h = max(v.z for v in bb) - min(v.z for v in bb)
    o.scale = [2 / h] * 3  # all 2 tall, standing on z = 0
    o.location.z = -min(v.z for v in bb) * 2 / h
    o['h'], o['z0'] = 2.0, 0.0
    objs.append(o)
bpy.ops.object.camera_add(location=(0, -10, 0), rotation=(math.radians(90), 0, 0))
cam = sc.objects['Camera']
sc.camera = cam
cam.data.type = 'ORTHO'

# Each one alone from the front, as a mask
scores = []
sc.render.resolution_x = sc.render.resolution_y = 512
for o in objs:
    for p in objs:
        p.hide_render = p is not o
    cam.data.ortho_scale = o['h'] * 1.3
    cam.location = (o.location.x, -10, o['z0'] + o['h'] / 2)
    sc.render.filepath = '/tmp/_mask.png'
    bpy.ops.render.render(write_still=True)
    m = mask_of(np.array(Image.open('/tmp/_mask.png').convert('RGBA')))
    Image.fromarray(np.stack([ref_mask, m, m & ref_mask], -1).astype(np.uint8) * 255).save(out.replace('.png', f'-mask{objs.index(o)}.png'))
    iou = (m & ref_mask).sum() / (m | ref_mask).sum()
    scores.append(iou)
    print('IOU', files[objs.index(o)], round(float(iou), 3), flush=True)

# All of them: front and side
for p in objs:
    p.hide_render = False
for i, o in enumerate(objs):
    c = o.copy()
    sc.collection.objects.link(c)
    c.rotation_euler.z = math.radians(90)
    o.location.x = i * 5.0
    c.location.x = i * 5.0 + 2.5
    o.location.z -= 1
    c.location.z = o.location.z
sc.render.film_transparent = False
cam.location = ((len(files) - 1) * 2.5 + 1.25, -10, 0)
cam.data.ortho_scale = len(files) * 5.0
sc.render.resolution_x, sc.render.resolution_y = 400 * len(files), 440
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print('SCORES', ' '.join(f'{f.split("/")[-1]}={s:.3f}' for f, s in zip(files, scores)))
