#!/bin/sh
# build.sh NAME DIR HEIGHT OUT.glb   (on the Mac; DIR is a painted candidate: textured.obj, .mtl, .jpg)
# The picture's face onto the paint (front.py, facefit.py, face.py), then the rig (rig.py).
#   PY: Python 3.11 with bpy 4.4, numpy<2, pillow, scipy;  PIC: the picture;  BOX: its cut-out's box
#   (json [x0, y0, x1, y1]);  UAL: AnimationLibrary_Godot_Standard.glb
set -e
NAME=$1; D=$2; H=$3; OUT=$4
HERE=$(cd "$(dirname "$0")" && pwd)
KP=$HERE/$NAME-keypoints.json
CW=$($PY -c "from PIL import Image; print(Image.open('$PIC').size[0])")
CH=$($PY -c "from PIL import Image; print(Image.open('$PIC').size[1])")
$PY $HERE/front.py "$D" "$BOX" $CW $CH > "$D/front.log" 2>&1
$PY $HERE/facefit.py "$PIC" "$D/front.png" "$KP" "$D/fit.json"
$PY $HERE/face.py "$D" "$PIC" "$BOX" "$D/fit.json" "$KP" > "$D/face.log" 2>&1
grep -E "face texels|FACE_OK" "$D/face.log"
$PY $HERE/rig.py $NAME "$D/textured.obj" "$BOX" "$UAL" "$KP" "$OUT" ${TRIS:-11000} $H > "$D/rig.log" 2>&1
grep -E "^mesh|^INFO \{" "$D/rig.log"
