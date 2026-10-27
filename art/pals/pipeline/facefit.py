# python facefit.py concept.png DIR/front.png keypoints.json OUT.json
# Where the concept's face is on the painted mesh, seen from the front at the concept's size: the shift
# and scale of the concept's eyes, nose and mouth that best fit the painted ones (the correlation of
# their light and dark: the paint copied the concept's features, if not cleanly).
import sys, json
import numpy as np
from PIL import Image
import json as _j
KP = _j.load(open(sys.argv[3]))
con = np.asarray(Image.open(sys.argv[1]).convert('L'), float)
ren = Image.open(sys.argv[2]).convert('RGBA'); a = np.asarray(ren, float)
ren = a[:, :, :3].mean(2) * (a[:, :, 3] / 255) + 200 * (1 - a[:, :, 3] / 255)
def edges(g):
    gx = np.zeros_like(g); gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]; gy[1:-1] = g[2:] - g[:-2]
    return np.hypot(gx, gy)
x, y, rx, ry = KP['face']['patch']  # the eyes, nose and mouth, without the hair round them
patch = con[y - ry:y + ry, x - rx:x + rx]
patch = (patch - patch.mean()) / (patch.std() + 1e-6)
E = ren
best = (-1, 0, 0, 1)
for s in np.arange(0.92, 1.081, 0.01):  # (the mesh is made from the picture: about its size)
    img = Image.fromarray(E.astype(np.float32))
    # The render scaled about the face's middle by 1/s, so the concept's patch is compared at scale s.
    W, H = E.shape[1], E.shape[0]
    sc = img.resize((int(W / s), int(H / s)), Image.BILINEAR)
    Es = np.asarray(sc, float)
    cx, cy = x / s, y / s
    for dy in range(-70, 71, 2):
        for dx in range(-50, 51, 2):
            X, Y = int(round(cx + dx / s)), int(round(cy + dy / s))
            win = Es[Y - ry:Y + ry, X - rx:X + rx]
            if win.shape != patch.shape: continue
            w = (win - win.mean()) / (win.std() + 1e-6)
            c = (w * patch).mean()
            if c > best[0]: best = (c, dx, dy, s)
c, dx, dy, s = best
print('FIT corr', round(c, 3), 'shift', dx, dy, 'scale', round(s, 3))
json.dump({'dx': dx, 'dy': dy, 's': s, 'corr': c}, open(sys.argv[4], 'w'))
