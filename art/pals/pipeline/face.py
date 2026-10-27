# python face.py DIR concept.png box.json fit.json keypoints.json
# The face, from the concept: Hunyuan3D-2.1 paints the whole figure from views too small for a face,
# which comes out smudged. The concept shows it clean, from the front, as the mesh was made from it:
# every texel of the face and the front of the hair that the front view sees is given the concept's
# colour there (matched in brightness to the paint round it), fading out towards the sides of the
# head and the edge of the face. Writes DIR/textured-face.png and points the material at it.
import bpy, bmesh, sys, json, math
import numpy as np
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
D, CONCEPT, BOX, FIT, KPF = argv[0], argv[1], argv[2], argv[3], argv[4]
# The face on the concept (pixels): its middle and half sizes, and where the fading starts (0..1).
FACE = json.load(open(KPF))['face']
box = json.load(open(BOX))
# Where the concept's face fits the mesh's (facefit.py): a point on the mesh seen at front-view pixel p
# is the concept's pixel FACE + (p - FACE - shift) / scale.
fit = json.load(open(FIT))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=f'{D}/textured.obj')
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
# (The importer stands the mesh up with the object's turn: into the vertices.)
bpy.context.view_layer.objects.active = ob; ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
me.calc_loop_triangles()
V = np.array([v.co[:] for v in me.vertices])
tris = np.array([t.vertices[:] for t in me.loop_triangles])
loops = np.array([t.loops[:] for t in me.loop_triangles])
uv = np.array([d.uv[:] for d in me.uv_layers.active.data])
img = next(i for i in bpy.data.images if i.size[0] > 0 and 'metal' not in i.name and 'rough' not in i.name)
W, H = img.size
tex = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
con = bpy.data.images.load(CONCEPT)
CW, CH = con.size
cpx = np.array(con.pixels[:], dtype=np.float32).reshape(CH, CW, 4)

# The figure faces -Y here (an OBJ facing +Z, imported Z up); the front view looks along +Y. The
# cut-out's box is the mesh's box seen from the front.
mn, mx = V.min(0), V.max(0)
sx = (mx[0] - mn[0]) / (box[2] - box[0]); sz = (mx[2] - mn[2]) / (box[3] - box[1])
# The front view as front.py draws it: the concept's middle at the middle, one scale both ways.
u = max(CW * sx, CH * sz) / max(CW, CH)
mcx = mn[0] + (CW / 2 - box[0]) * sx; mcz = mx[2] - (CH / 2 - box[1]) * sz
def to_px(x, z):
    px, py = CW / 2 + (x - mcx) / u, CH / 2 - (z - mcz) / u
    return FACE['x'] + (px - FACE['x'] - fit['dx']) / fit['s'], FACE['y'] + (py - FACE['y'] - fit['dy']) / fit['s']
bvh = BVHTree.FromPolygons([tuple(v) for v in V], [tuple(t) for t in tris])

def sample(px, py):
    # Bilinear, from the concept (its rows run bottom up in Blender).
    x = np.clip(px, 0, CW - 1.001); y = np.clip(CH - 1 - py, 0, CH - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int); fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    a, b, c, d = cpx[y0, x0], cpx[y0, x0 + 1], cpx[y0 + 1, x0], cpx[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

done = np.zeros((H, W), bool)
acc_t, acc_c, acc_w = [], [], []
writes = []
for ti, (t, l) in enumerate(zip(tris, loops)):
    P = V[t]
    n = np.cross(P[1] - P[0], P[2] - P[0]); ln = np.linalg.norm(n)
    if ln < 1e-12: continue
    n /= ln
    facing = -n[1]
    if facing < 0.2: continue
    cx, cz = P[:, 0].mean(), P[:, 2].mean()
    px, py = to_px(cx, cz)
    e = math.hypot((px - FACE['x']) / FACE['rx'], (py - FACE['y']) / FACE['ry'])
    if e > 1: continue
    # Seen from the front (not behind a lock of hair or the collar)?
    hit = bvh.ray_cast((cx, mn[1] - 1, cz), (0, 1, 0))
    if hit[2] is None or (hit[2] != ti and hit[0][1] < P[:, 1].mean() - 0.004 * (mx[2] - mn[2])): continue
    w_face = min(1, max(0, (facing - 0.2) / 0.4)) * (1 - max(0, (e - FACE['soft']) / (1 - FACE['soft'])))
    T = uv[l] * [W, H]
    lo = np.floor(T.min(0)).astype(int); hi = np.ceil(T.max(0)).astype(int)
    xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
    q = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
    # Barycentrics of each texel in the triangle's UVs.
    d = (T[1, 1] - T[2, 1]) * (T[0, 0] - T[2, 0]) + (T[2, 0] - T[1, 0]) * (T[0, 1] - T[2, 1])
    if abs(d) < 1e-12: continue
    b0 = ((T[1, 1] - T[2, 1]) * (q[:, 0] - T[2, 0]) + (T[2, 0] - T[1, 0]) * (q[:, 1] - T[2, 1])) / d
    b1 = ((T[2, 1] - T[0, 1]) * (q[:, 0] - T[2, 0]) + (T[0, 0] - T[2, 0]) * (q[:, 1] - T[2, 1])) / d
    b2 = 1 - b0 - b1
    inside = (b0 >= -0.12) & (b1 >= -0.12) & (b2 >= -0.12)
    if not inside.any(): continue
    q, b = q[inside], np.stack([b0, b1, b2], 1)[inside]
    p3 = b @ P
    cpx_, cpy_ = to_px(p3[:, 0], p3[:, 2])
    ix = np.clip(q[:, 0].astype(int), 0, W - 1); iy = np.clip(q[:, 1].astype(int), 0, H - 1)
    col = sample(cpx_, cpy_)[:, :3]
    writes.append((ix, iy, col, w_face))
    if w_face > 0.6: acc_t.append(tex[iy, ix, :3].mean(0)); acc_c.append(col.mean(0))

# Matched to the paint round it: the same average colour as the painted face had.
gain = np.array(acc_t).mean(0) / np.maximum(np.array(acc_c).mean(0), 1e-3) if acc_t else np.ones(3)
gain = np.clip(gain, 0.9, 1.1)  # (kept near the picture: the paint is often darker)
print('face texels', sum(len(w[0]) for w in writes), 'gain', gain.round(3))
for ix, iy, col, w in writes:
    tex[iy, ix, :3] = tex[iy, ix, :3] * (1 - w) + np.clip(col * gain, 0, 1) * w
img.pixels.foreach_set(tex.ravel())
img.filepath_raw = f'{D}/textured-face.png'; img.file_format = 'PNG'
img.save()
mtl = open(f'{D}/textured.mtl').read()
open(f'{D}/textured.mtl', 'w').write(mtl.replace('textured.jpg', 'textured-face.png'))
print('FACE_OK')
