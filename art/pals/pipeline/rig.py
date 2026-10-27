# python rig.py NAME MESH.obj BOX.json UAL.glb keypoints.json OUT.glb MAXTRIS HEIGHT
#   (bpy 4.4 as a module, Python 3.11; or blender -b --factory-startup --python rig.py -- ...)
# Mo or Bo, from Hunyuan3D-2.1's textured mesh (adapted from Hidden Hearths' traveller):
#   - cleaned, made lighter (the head keeps its detail), stood up facing glTF +Z, HEIGHT tall overall;
#   - given the Universal Animation Library's skeleton (Quaternius, CC0), fitted to the joints picked on
#     the picture (keypoints.json, matched to the mesh by the cut-out's box, BOX.json), set as deep in
#     the mesh as the middle of the limb or body there;
#   - skinned by Blender's bone heat, each limb kept to what is close round it (not the bag or the vest);
#   - given eyelids: a skin-coloured patch over each eye on its own bone (lid.L, lid.R), folded up out of
#     sight at rest; the blink clip unfolds them;
#   - for the player, the lantern (keypoints 'lantern') on its own bone, hanging from the left hand (the
#     game keeps it hanging), its glass marked to glow (the vertex colour's red);
#   - and given the library's clips, bone by bone (each bone turns in the world as the library's does,
#     counted from an A pose like theirs): idle, walk, run, jump, talk and pick_up; and two made here on
#     the same skeleton, as the libraries have none: wave and point (the right arm, over the idle).
import bpy, bmesh, sys, math, json
import numpy as np
from mathutils import Matrix, Vector, Quaternion
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
JUMP_FROM, JUMP_TO = 0.5, 0.55  # the jump: from the take-off to the landing's recovery
NAME, MESH, BOX, UAL, KP, OUT, MAXTRIS, H = argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], int(argv[6]), float(argv[7])
CLIPS = {  # the game's name: the library's clips (or a stretch of one, as fractions), one after another
    'idle': ['Idle_Loop'], 'walk': ['Walk_Loop'], 'run': ['Jog_Fwd_Loop'],
    'jump': [('Jump_Start', JUMP_FROM, 1.0), ('Jump_Land', 0.0, JUMP_TO)],
    'talk': ['Idle_Talking_Loop'], 'pick_up': ['PickUp_Table'], 'wave': ['Idle_Loop'], 'point': ['Idle_Loop'],
}
LOOPS = ('idle', 'walk', 'run', 'talk')
K = H / 1.8  # (distances below were first set for a figure 1.8 tall)
FPS = 30
kp = json.load(open(KP))
box = json.load(open(BOX))  # the cut-out's box in the concept: [x0, y0, x1, y1]

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS

def activate(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
def join(objs):
    activate(objs[0])
    for o in objs: o.select_set(True)
    if len(objs) > 1: bpy.ops.object.join()
    return bpy.context.view_layer.objects.active

# Hits along a ray, front to back (location y of each).
def hits(bvh, x, z, y0=-5.0, y1=5.0):
    out, o, d = [], Vector((x, y0, z)), Vector((0, 1, 0))
    while True:
        loc, n, i, dist = bvh.ray_cast(o, d, y1 - o.y)
        if loc is None: return out
        out.append(loc.y)
        o = loc + d * 1e-4
# The middle of the first solid at least `thick` deep along a ray from the front.
def middle(bvh, x, z, thick):
    h = hits(bvh, x, z)
    for a, b in zip(h[0::2], h[1::2]):
        if b - a >= thick: return (a + b) / 2
    return (h[0] + h[-1]) / 2 if h else None

# ---------------------------------------------------------------- the library
bpy.ops.import_scene.gltf(filepath=UAL)
S = [o for o in sc.objects if o.type == 'ARMATURE'][0]
S.name = 'ual'
manq = join([o for o in sc.objects if o.type == 'MESH'])
S.animation_data_create()
S.animation_data.action = None
for pb in S.pose.bones: pb.matrix_basis = Matrix()
bpy.context.view_layer.update()
SR = {b.name: S.matrix_world @ b.matrix_local for b in S.data.bones}  # rest, in the world
s_height = max((manq.matrix_world @ Vector(c)).z for c in manq.bound_box)
k = H / s_height
manq.hide_set(True); manq.hide_render = True

# ---------------------------------------------------------------- the mesh
before = set(sc.objects)
bpy.ops.wm.obj_import(filepath=MESH)
ob = join([o for o in sc.objects if o not in before and o.type == 'MESH'])
ob.name = ob.data.name = NAME
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
def co(): return np.array([v.co[:] for v in me.vertices])

# Upright (the longest axis up), arms along X, toes to -Y (glTF +Z).
P = co()
up = int(np.argmax(np.ptp(P, 0)))
if up == 1: me.transform(Matrix.Rotation(math.radians(90), 4, 'X'))
elif up == 0: me.transform(Matrix.Rotation(math.radians(-90), 4, 'Y'))
P = co(); Z0, Z1 = P[:, 2].min(), P[:, 2].max()
band = lambda a, b: P[(P[:, 2] > Z0 + a * (Z1 - Z0)) & (P[:, 2] < Z0 + b * (Z1 - Z0))]
# (Feet down: the lowest twentieth is the boots, narrower than the shoulders' band.)
if np.ptp(band(0.0, 0.05)[:, 0]) > np.ptp(band(0.75, 0.85)[:, 0]) * 1.6: me.transform(Matrix.Rotation(math.pi, 4, 'X'))
P = co(); Z0, Z1 = P[:, 2].min(), P[:, 2].max()
arms = band(0.45, 0.65)
if np.ptp(arms[:, 1]) > np.ptp(arms[:, 0]): me.transform(Matrix.Rotation(math.radians(90), 4, 'Z'))
P = co(); Z0, Z1 = P[:, 2].min(), P[:, 2].max()
toes = band(0.0, 0.03)[:, 1].mean() - band(0.12, 0.22)[:, 1].mean()
if toes > 0: me.transform(Matrix.Rotation(math.pi, 4, 'Z'))
me.update()

# The concept on the mesh: the cut-out's box is the mesh's box seen from the front.
P = co(); mn, mx = P.min(0), P.max(0)
sx = (mx[0] - mn[0]) / (box[2] - box[0]); sz = (mx[2] - mn[2]) / (box[3] - box[1])
print('picture to mesh scale x', round(sx, 5), 'z', round(sz, 5))
def at(px, py): return mn[0] + (px - box[0]) * sx, mx[2] - (py - box[1]) * sz
# Feet at 0, the middle under the hips, 1.8 to the top of the head.
xc, z_sole = at(kp['x'], kp['sole']); z_top = mx[2]
bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
_, zh = at(kp['x'], kp['torso']['DEF-hips'])
yc = middle(bvh, xc, zh, 0.08 * (z_top - z_sole))
s = H / (z_top - z_sole)
me.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-xc, -yc, -z_sole)))
me.update()
def at(px, py):  # noqa: the same, in the final placing
    return (mn[0] + (px - box[0]) * sx - xc) * s, (mx[2] - (py - box[1]) * sz - z_sole) * s
dg = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(ob, dg)

J_HEAD = at(kp['x'], kp['torso']['DEF-neck'])[1]
# Lighter, for the game, evenly; only the face (the front of the head) is spared a little: its shape is
# in the texture, and anime hair is a big share of the mesh, which would otherwise starve the body.
if len(me.polygons) > MAXTRIS:
    keep = ob.vertex_groups.new(name='keep')
    for v in me.vertices:
        w = min(1, max(0, (v.co.z - J_HEAD) / (0.04 * K))) * (1 if v.co.y < -0.02 * K and abs(v.co.x) < 0.09 * K else 0)
        if w > 0: keep.add([v.index], w, 'REPLACE')
    d = ob.modifiers.new('dec', 'DECIMATE'); d.ratio = MAXTRIS / len(me.polygons)
    d.vertex_group = 'keep'; d.invert_vertex_group = True; d.vertex_group_factor = 2
    activate(ob); bpy.ops.object.modifier_apply(modifier='dec')
    ob.vertex_groups.remove(ob.vertex_groups['keep'])
print('mesh', len(me.polygons), 'triangles')

# ---------------------------------------------------------------- the joints
J = {}
T_ = kp['torso']; L_ = kp['limbs']
for n, py in T_.items():
    x, z = at(kp['x'], py)
    J[n] = Vector((0, middle(bvh, 0, z, 0.1) or 0, z))
# The spine runs from the hips to the head (their middles are the surest), curved as the library's
# is about its own line from hips to head (the belt, the pouches and the scarf would otherwise pull
# single joints forward).
sh, shd = SR['DEF-hips'].translation, SR['DEF-head'].translation
for n in ('DEF-spine.001', 'DEF-spine.002', 'DEF-spine.003', 'DEF-neck'):
    sn = SR[n].translation
    t = (sn.z - sh.z) / (shd.z - sh.z)
    J[n].y = J['DEF-hips'].y + t * (J['DEF-head'].y - J['DEF-hips'].y) + (sn.y - (sh.y + t * (shd.y - sh.y))) * k
for n, (px, py) in L_.items():
    x, z = at(px, py)
    limb = 'arm' if any(t in n for t in ('arm', 'hand', 'tip', 'shoulder')) else 'leg'
    y = middle(bvh, x, z, 0.03 if limb == 'arm' else 0.05)
    if y is None and n.startswith('tip'): y = J['DEF-hand' + n[3:]].y
    J[n] = Vector((x, y if y is not None else 0, z))
# The hip and shoulder joints sit as deep in the body as the library's do.
for n, ref in (('DEF-thigh', 'DEF-hips'), ('DEF-shoulder', 'DEF-spine.003'), ('DEF-upper_arm', 'DEF-spine.003')):
    for t in ('L', 'R'):
        J[f'{n}.{t}'].y = J[ref].y + (SR[f'{n}.{t}'].translation.y - SR[ref].translation.y) * k
# The toe: the ball of the foot, as far behind the boot's tip as the library's is behind its own.
mbvh = BVHTree.FromObject(manq, dg)
for t in ('L', 'R'):
    a = J[f'DEF-foot.{t}']
    tip = hits(bvh, a.x, 0.03)
    stoe = SR[f'DEF-toe.{t}'].translation
    stip = hits(mbvh, stoe.x, 0.03 / k)
    ty = (tip[0] if tip else a.y - 0.2) + ((stoe.y - stip[0]) * k if stip else 0.06)
    J[f'DEF-toe.{t}'] = Vector((a.x, ty, SR[f'DEF-toe.{t}'].translation.z * k))
    J[f'toe_tip.{t}'] = Vector((a.x, tip[0] if tip else ty - 0.06, J[f'DEF-toe.{t}'].z))
print('JOINTS', {n: [round(c, 3) for c in v] for n, v in J.items()})

# ---------------------------------------------------------------- the skeleton
T = S.copy(); T.data = S.data.copy(); T.name = T.data.name = NAME + '_rig'
sc.collection.objects.link(T)
T.animation_data_clear()
activate(T)
bpy.ops.object.mode_set(mode='EDIT')
eb = T.data.edit_bones
for e in list(eb):
    if any(f in e.name for f in ('f_', 'thumb')): eb.remove(e)
srest = {b.name: (b.head_local.copy(), b.tail_local.copy(), (b.matrix_local.to_3x3() @ Vector((0, 0, 1)))) for b in S.data.bones}
for e in eb:
    if e.name == 'root': continue
    h0, t0, z0 = srest[e.name]
    head = J.get(e.name)
    if head is None: print('no joint for', e.name); continue
    # The tail: the next joint, if the library's bone reaches it; otherwise as long as the library's.
    child = next((c for c in e.children if (srest[c.name][0] - t0).length < 1e-3), None)
    if child and child.name in J: tail = J[child.name]
    elif e.name.startswith('DEF-hand'): tail = J['tip.' + e.name[-1]]
    elif e.name.startswith('DEF-toe'): tail = J['toe_tip.' + e.name[-1]]
    elif e.name == 'DEF-head': tail = Vector((head.x, head.y, H))
    else: tail = head + (t0 - h0) * k
    e.use_connect = False
    e.head, e.tail = head, tail
    # The bone's roll: the library's, turned as the bone is.
    r = (t0 - h0).normalized().rotation_difference((tail - head).normalized())
    e.align_roll(r @ z0)
bpy.ops.object.mode_set(mode='OBJECT')
T.data.bones['root'].use_deform = False
TR = {b.name: T.matrix_world @ b.matrix_local for b in T.data.bones}
names = [b.name for b in T.data.bones]  # parents before children

# ---------------------------------------------------------------- the skin
activate(ob); T.select_set(True); bpy.context.view_layer.objects.active = T
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
P = co()
vg = {g.index: g.name for g in ob.vertex_groups}
W = np.zeros((len(P), len(names)))
col = {n: i for i, n in enumerate(names)}
for v in me.vertices:
    for g in v.groups:
        n = vg[g.group]
        if n in col: W[v.index, col[n]] = g.weight
def segdist(p, a, b):
    a, b = np.array(a), np.array(b); ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)
seg = {n: (T.data.bones[n].head_local, T.data.bones[n].tail_local) for n in names}
D = np.stack([segdist(P, *seg[n]) for n in names], 1)
# Where bone heat found nothing: the nearest bones.
lost = W.sum(1) < 1e-4
if lost.any():
    near = np.exp(-(D[lost] - D[lost].min(1, keepdims=True)) / 0.02); near[:, col['root']] = 0
    W[lost] = near
print('vertices bone heat missed:', int(lost.sum()))
# A limb only moves what is close round it: not the cape behind an arm or hanging round the thighs, nor
# the bow. The boots and gloves are the limb's own, however bulky. What a limb lets go of goes to the
# body: the chest above the waist, the hips below.
reach = {n: r * K for n, r in {'DEF-upper_arm': 0.09, 'DEF-forearm': 0.085, 'DEF-hand': 0.12, 'DEF-thigh': 0.11, 'DEF-shin': 0.09}.items()}
hem = J['DEF-shin.L'].z + 0.04  # the cape ends about the knees
chest, hips = col['DEF-spine.003'], col['DEF-hips']
for n in names:
    base = n[:-2]
    if base not in reach: continue
    i = col[n]
    keep = np.clip(1 - (D[:, i] - reach[base]) / 0.05, 0, 1)
    if base in ('DEF-thigh', 'DEF-shin'):
        keep[P[:, 2] < hem - 0.05] = 1  # below the hem: the legs and boots
        keep = np.maximum(keep, 0.3 * (W[:, i] > 0))  # a hem still sways a little with the leg
    moved = W[:, i] * (1 - keep)
    W[:, i] -= moved
    up = P[:, 2] > J['DEF-spine.001'].z
    W[up, chest] += moved[up]; W[~up, hips] += moved[~up]
# Smoothed a little along the mesh's edges (no hard steps where the cape leaves a limb).
E = np.array([e.vertices[:] for e in me.edges])
deg = np.bincount(E.ravel(), minlength=len(P)).astype(float)[:, None]
for _ in range(2):
    acc = np.zeros_like(W)
    np.add.at(acc, E[:, 0], W[E[:, 1]]); np.add.at(acc, E[:, 1], W[E[:, 0]])
    W = 0.5 * W + 0.5 * acc / np.maximum(deg, 1)
# At most four bones a vertex, and they add up to one.
W[:, col['root']] = 0
order = np.argsort(-W, 1)
for r in range(len(W)): W[r, order[r, 4:]] = 0
W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
for g in list(ob.vertex_groups): ob.vertex_groups.remove(g)
for n in names:
    if n == 'root': continue
    g = ob.vertex_groups.new(name=n)
    for v in np.nonzero(W[:, col[n]] > 1e-3)[0]: g.add([int(v)], float(W[v, col[n]]), 'REPLACE')

# ---------------------------------------------------------------- the eyelids
# Over each eye (keypoints 'eyes': middle and half sizes on the picture), a patch that follows the face's
# own shape a hair in front of it, coloured from the face's own texture: skin, with a dark lash line at
# its lower edge. Each is on a bone at the top of the eye, just inside the head; the blink clip's first
# and last frames squeeze the lid flat into the head (scale (1, .02, .02)), its middle lets it down.
me.calc_loop_triangles()
fbvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
uvl = me.uv_layers.active.data
def uv_at(x, z):
    loc, n, i, d = fbvh.ray_cast(Vector((x, -5, z)), Vector((0, 1, 0)))
    poly = me.polygons[i]
    vs = [me.vertices[v].co for v in poly.vertices[:3]]
    uvs = [Vector(uvl[l].uv) for l in poly.loop_indices[:3]]
    v0, v1, v2 = vs[1] - vs[0], vs[2] - vs[0], loc - vs[0]
    d00, d01, d11, d20, d21 = v0.dot(v0), v0.dot(v1), v1.dot(v1), v2.dot(v0), v2.dot(v1)
    den = d00 * d11 - d01 * d01 or 1e-12
    b = (d11 * d20 - d01 * d21) / den; c = (d00 * d21 - d01 * d20) / den
    return uvs[0] * (1 - b - c) + uvs[1] * b + uvs[2] * c, loc, n
LIDS = {}
NU, NV = 10, 6
lid_bm = bmesh.new()
lid_uv = lid_bm.loops.layers.uv.new('UVMap')
for side, (ex, ey, hw, hh) in kp['eyes'].items():
    cx, cz = at(ex, ey)
    rx = abs(at(ex + hw, ey)[0] - cx) * 1.3
    rz = abs(at(ex, ey - hh)[1] - cz) * 1.35
    skin_uv = uv_at(cx, cz - rz * 2.6)[0]
    dark_uv = uv_at(cx, cz)[0]
    grid = []
    for j in range(NV + 1):
        row = []
        for i in range(NU + 1):
            a_ = -1 + 2 * i / NU; b_ = 1 - 2 * j / NV
            x = cx + a_ * rx
            z = cz + rz * (b_ * (1 - 0.3 * a_ * a_) + 0.08)
            hit = fbvh.ray_cast(Vector((x, -5, z)), Vector((0, 1, 0)))
            p = hit[0] + hit[1] * 0.0025 * K if hit[0] else Vector((x, J['DEF-head'].y - 0.05, z))
            row.append(lid_bm.verts.new(p))
        grid.append(row)
    rows = {v: j for j, r in enumerate(grid) for v in r}
    for j in range(NV):
        for i in range(NU):
            f = lid_bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]))
            for l in f.loops:
                l[lid_uv].uv = dark_uv if rows[l.vert] >= NV - 1 else skin_uv
    top = Vector((cx, 0, cz + rz * 1.05))
    hit = fbvh.ray_cast(Vector((cx, -5, top.z)), Vector((0, 1, 0)))[0]
    top.y = (hit.y if hit else J['DEF-head'].y) + 0.012 * K
    LIDS['lid.' + side] = (top, [v for r in grid for v in r])
# Facing the front (-Y)
lid_bm.normal_update()
for f in lid_bm.faces:
    if f.normal.y > 0: f.normal_flip()
activate(T)
bpy.ops.object.mode_set(mode='EDIT')
for n, (top, vs) in LIDS.items():
    e = T.data.edit_bones.new(n)
    e.head, e.tail = top, top + Vector((0, 0, -0.03 * K))
    e.parent = T.data.edit_bones['DEF-head']
    e.align_roll(Vector((0, -1, 0)))
bpy.ops.object.mode_set(mode='OBJECT')
lid_bm.verts.index_update()
groups = {n: [v.index for v in vs] for n, (top, vs) in LIDS.items()}
lid_me = bpy.data.meshes.new('lids')
lid_bm.to_mesh(lid_me); lid_bm.free()
lid_ob = bpy.data.objects.new('lids', lid_me)
sc.collection.objects.link(lid_ob)
lid_me.uv_layers[0].name = me.uv_layers.active.name
for n, ids in groups.items():
    lid_ob.vertex_groups.new(name=n).add(ids, 1.0, 'REPLACE')
lid_me.materials.append(me.materials[0])
activate(ob); lid_ob.select_set(True)
bpy.ops.object.join()
me = ob.data
print('lids', {n: [round(c, 3) for c in t] for n, (t, v) in LIDS.items()}, flush=True)

# ---------------------------------------------------------------- the lantern
# Everything in its box (on the picture, seen from the front) rides on its bone, which hangs from the
# handle where the left hand holds it, pointing down to the flame. The glass round the flame glows.
LANTERN = kp.get('lantern')
if LANTERN:
    (x0, y0, x1, y1), hx, fx = LANTERN['box'], LANTERN['handle'], LANTERN['flame']
    ax0, az0 = at(x0, y1); ax1, az1 = at(x1, y0)
    P = co()
    inside = (P[:, 0] > ax0) & (P[:, 0] < ax1) & (P[:, 2] > az0) & (P[:, 2] < az1)
    hp, fp = Vector(at(*hx)), Vector(at(*fx))
    mid_y = float(np.median(P[inside, 1])) if inside.any() else 0.0
    head, tail = Vector((hp[0], mid_y, hp[1])), Vector((fp[0], mid_y, fp[1]))
    activate(T)
    bpy.ops.object.mode_set(mode='EDIT')
    e = T.data.edit_bones.new('lantern')
    e.head, e.tail = head, tail
    e.parent = T.data.edit_bones[LANTERN.get('bone', 'DEF-hand.L')]
    e.align_roll(Vector((0, -1, 0)))
    f = T.data.edit_bones.new('flame')  # (moves nothing: where the game puts the light)
    f.head, f.tail, f.parent, f.use_deform = tail, tail + (tail - head) * 0.2, e, False
    bpy.ops.object.mode_set(mode='OBJECT')
    ids = [int(i) for i in np.nonzero(inside)[0]]
    for g in ob.vertex_groups: g.remove(ids)
    ob.vertex_groups.new(name='lantern').add(ids, 1.0, 'REPLACE')
    # The glass: within the flame's reach of it (a third of the box's width), as the colour's red
    r = 0.3 * (ax1 - ax0)
    glow = me.color_attributes.new('glow', 'BYTE_COLOR', 'POINT')
    for v in me.vertices:
        d = math.hypot(v.co.x - tail.x, v.co.z - tail.z)
        k_ = max(0.0, min(1.0, (r - d) / (0.35 * r))) if inside[v.index] else 0.0
        glow.data[v.index].color = (k_, 0, 0, 1)
    me.color_attributes.active_color = glow
    print('lantern', len(ids), 'vertices', 'glass', sum(1 for c in glow.data if c.color[0] > 0.5), flush=True)

# ---------------------------------------------------------------- the clips
# The library's skeleton turned, bone by bone from the root, to point as ours does at rest: its pose
# then and our rest are the same pose, and each frame's turn from it carries over.
SA = {}
for n in names:
    b = S.data.bones[n]
    if b.parent is None or n == 'root': SA[n] = SR[n].copy(); continue
    p = b.parent.name
    m = SA[p] @ SR[p].inverted() @ SR[n]  # where the parent's turn takes it
    d_now = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    d_want = (TR[n].to_3x3() @ Vector((0, 1, 0))).normalized()
    q = d_now.rotation_difference(d_want)
    rot = (q.to_matrix() @ m.to_3x3()).to_4x4(); rot.translation = m.translation
    SA[n] = rot
C = {n: SA[n].to_3x3().inverted() @ TR[n].to_3x3() for n in names}
# The body (the spine, the neck, the head, the collarbones) turns as the library's does from its rest,
# the character's own shape kept: they stand more upright than the library's mannequin, and matching
# its bones' directions would bow them.
for n in names:
    if n in ('DEF-hips', 'DEF-spine.001', 'DEF-spine.002', 'DEF-spine.003', 'DEF-neck', 'DEF-head') or n.startswith('DEF-shoulder'):
        C[n] = SR[n].to_3x3().inverted() @ TR[n].to_3x3()
hip_k = TR['DEF-thigh.L'].translation.z / SR['DEF-thigh.L'].translation.z

T.animation_data_create()
for pb in T.pose.bones: pb.rotation_mode = 'QUATERNION'
spb = {pb.name: pb for pb in S.pose.bones}
done = []


def find_action(src):
    return next((a for a in bpy.data.actions if a.name == src), None) or next((a for a in bpy.data.actions if a.name.split('_Armature')[0].split('.')[0] == src), None)


def world_at(act, f):
    """Each of our bones in the world at the library's frame f of act."""
    S.animation_data.action = act
    if hasattr(S.animation_data, 'action_slot') and len(getattr(act, 'slots', [])): S.animation_data.action_slot = act.slots[0]
    sc.frame_set(int(f))
    world = {}
    for n in names:
        b = T.data.bones[n]
        if n == 'root': world[n] = TR[n].copy(); continue
        sw = S.matrix_world @ spb[n].matrix
        rot = sw.to_3x3() @ C[n]
        if b.parent is None or b.parent.name == 'root':
            pos = TR[n].translation + (sw.translation - SR[n].translation) * hip_k
        else:
            p = b.parent.name
            pos = (world[p] @ (TR[p].inverted() @ TR[n])).translation
        m = rot.to_4x4(); m.translation = pos
        world[n] = m
    return world


# The right arm, posed here (the character's right is -X, the front -Y): where each bone should point
# over time, eased in from and back out to the idle's arm. wave: raised to the side, the forearm swinging
# over the head. point: straight out in front at shoulder height.
def smooth(x): x = min(1, max(0, x)); return x * x * (3 - 2 * x)
def arm_wave(t, sec):
    w = smooth(t / 0.3) * smooth((sec - t) / 0.35)
    sw = math.sin((t - 0.3) * math.tau * 1.6) if t > 0.3 else 0
    up = Vector((-0.75, -0.2, 0.35)).normalized()
    fore = Vector((-0.25 - 0.4 * sw, -0.25, 0.95)).normalized()
    return w, {'DEF-upper_arm.R': up, 'DEF-forearm.R': fore, 'DEF-hand.R': fore}
def arm_point(t, sec):
    w = smooth(t / 0.3) * smooth((sec - t) / 0.3)
    d = Vector((-0.28, -0.95, 0.1)).normalized()
    return w, {'DEF-upper_arm.R': d, 'DEF-forearm.R': d, 'DEF-hand.R': (d + Vector((0, 0, -0.05))).normalized()}
POSED = {'wave': (arm_wave, 2.0), 'point': (arm_point, 1.6)}
ARM = ['DEF-shoulder.R', 'DEF-upper_arm.R', 'DEF-forearm.R', 'DEF-hand.R']


def pose_arm(world, w, dirs):
    for n in ARM:
        b = T.data.bones[n]
        p = b.parent.name
        pos = (world[p] @ (TR[p].inverted() @ TR[n])).translation
        rot = world[n].to_quaternion()
        if n in dirs:
            # the bone turned from its rest to point that way, its twist kept from the rest
            q = (TR[n].to_3x3() @ Vector((0, 1, 0))).normalized().rotation_difference(dirs[n]) @ TR[n].to_quaternion()
            rot = rot.slerp(q, w)
        m = rot.to_matrix().to_4x4(); m.translation = pos
        world[n] = m


for clip, srcs in CLIPS.items():
    frames = []  # (action, frame) one after another
    for src in srcs:
        src, a_, b_ = src if isinstance(src, tuple) else (src, 0.0, 1.0)
        act = find_action(src)
        if not act: print('no clip', src); continue
        f0, f1 = act.frame_range
        f0, f1 = f0 + (f1 - f0) * a_, f0 + (f1 - f0) * b_
        frames += [(act, f) for f in range(int(round(f0)), int(round(f1)) + 1)]
    if clip in POSED:  # the idle, as long as the gesture takes
        fn, sec = POSED[clip]
        n_ = int(round(sec * FPS)) + 1
        frames = [frames[i % (len(frames) - 1)] for i in range(n_)]
    if not frames: continue
    new = bpy.data.actions.new(clip)
    T.animation_data.action = new
    last = {}
    for f, (act, sf) in enumerate(frames):
        world = world_at(act, sf)
        if clip in POSED:
            w, dirs = POSED[clip][0](f / FPS, POSED[clip][1])
            pose_arm(world, w, dirs)
        for n in names:
            if n == 'root': continue
            b = T.data.bones[n]; pb = T.pose.bones[n]
            p = b.parent.name if b.parent else None
            basis = (TR[p].inverted() @ TR[n]).inverted() @ (world[p].inverted() @ world[n]) if p else TR[n].inverted() @ world[n]
            q = basis.to_quaternion()
            if n in last and last[n].dot(q) < 0: q.negate()
            last[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert('rotation_quaternion', frame=f + 1)
            if p == 'root' or p is None:
                pb.location = basis.translation
                pb.keyframe_insert('location', frame=f + 1)
    T.animation_data.action = None
    done.append((clip, round((len(frames) - 1) / FPS, 2)))
    print('clip', clip, 'from', srcs, done[-1][1], 's', flush=True)
S.animation_data.action = None
# The blink: the lids down over the eyes and back up (only the lid bones move); its first and last
# frames are the eyes open.
blink = bpy.data.actions.new('blink')
T.animation_data.action = blink
NB = 6
for f in range(NB + 1):
    k_ = math.sin(math.pi * f / NB) ** 0.7
    for n in LIDS:
        pb = T.pose.bones[n]
        pb.scale = (1, 0.02 + 0.98 * k_, 0.02 + 0.98 * k_)
        pb.keyframe_insert('scale', frame=f + 1)
T.animation_data.action = None
for n in LIDS:
    T.pose.bones[n].scale = (1, 1, 1)
done.append(('blink', round(NB / FPS, 2)))
for pb in T.pose.bones: pb.rotation_quaternion = Quaternion(); pb.location = (0, 0, 0)

# ---------------------------------------------------------------- material and export
activate(ob)
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
for mat in me.materials:
    if not mat or not mat.use_nodes: continue
    for n in list(mat.node_tree.nodes):
        if n.type == 'BSDF_PRINCIPLED':
            for name, v in (('Metallic', 0.0), ('Roughness', 0.85)):
                if n.inputs[name].is_linked: mat.node_tree.links.remove(n.inputs[name].links[0])
                n.inputs[name].default_value = v
            if n.inputs['Normal'].is_linked: mat.node_tree.links.remove(n.inputs['Normal'].links[0])
    for n in list(mat.node_tree.nodes):
        if n.type == 'TEX_IMAGE' and not n.outputs['Color'].is_linked: mat.node_tree.nodes.remove(n)
        elif n.type == 'TEX_IMAGE' and n.image and max(n.image.size) > 2048: n.image.scale(2048, 2048)
for o in [manq, S]: bpy.data.objects.remove(o)
# Only our own clips go out, each action an animation by its name (the library's actions
# would fit the same bones).
for a in list(bpy.data.actions):
    if a.name not in CLIPS and a.name != 'blink': bpy.data.actions.remove(a)
for t in list(T.animation_data.nla_tracks): T.animation_data.nla_tracks.remove(t)
activate(ob); T.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                          export_image_format='JPEG', export_jpeg_quality=88, export_animation_mode='ACTIONS',
                          export_skins=True, export_def_bones=False, export_optimize_animation_size=False,
                          export_vertex_color='ACTIVE' if LANTERN else 'NONE')
P = co()
info = dict(tris=len(me.polygons), verts=len(me.vertices), size=[round(float(v), 3) for v in np.ptp(P, 0)], clips=done, bones=len(names))
json.dump(info, open(OUT.replace('.glb', '.json'), 'w')); print('INFO', info)
