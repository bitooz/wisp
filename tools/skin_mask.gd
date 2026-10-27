extends SceneTree
## Where the skin is on Mo's and Bo's textures (their faces, necks and hands), as a small mask beside each
## model (art/pals/<id>_skin.png), so the island's other people can wear their bodies in other colours without
## their skin changing too (shaders/pal.gdshader). From the meshes themselves: every triangle mostly bound to the
## forearms or hands, or that lies in the face and neck (in front, below the brows, down to the collar), painted into the mask where its UVs
## fall. Run once after changing the models:
##   godot --headless --path . -s res://tools/skin_mask.gd

const SIZE := 512
const BONES := ["DEF-head", "DEF-neck", "DEF-hand.L", "DEF-hand.R", "DEF-forearm.L", "DEF-forearm.R"]


func _init() -> void:
	for id in ["mo", "bo"]:
		var root: Node3D = load("res://art/pals/%s.glb" % id).instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var skin: Skin = mi.skin
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := bones.size() / v.size()
		var want := {}
		for i in skin.get_bind_count():
			if String(skin.get_bind_name(i)) in BONES:
				want[i] = String(skin.get_bind_name(i))
		var F: Dictionary = Pal.FACE[id]
		var is_skin := PackedByteArray()
		is_skin.resize(v.size())
		for i in v.size():
			var best := -1
			var bw := 0.0
			for k in per:
				if weights[i * per + k] > bw:
					bw = weights[i * per + k]
					best = bones[i * per + k]
			var name: String = want.get(best, "")
			var p := v[i]
			# Hands and forearms by what moves them; the face and neck by where they are: below the brows, the
			# front of the head down to the collar (hair and clothes there are told apart by colour, in the shader)
			var ok := name.begins_with("DEF-hand") or name.begins_with("DEF-forearm")
			if p.y < F.brow.y - .015 and p.y > F.mouth.y - .2 and absf(p.x) < .12:
				ok = p.z > -.03 or p.y < F.mouth.y - .05
			is_skin[i] = 1 if ok else 0
		var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_L8)
		var n := 0
		for t in range(0, idx.size(), 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			if is_skin[a] + is_skin[b] + is_skin[c] < 2:
				continue
			_fill(img, uv[a] * SIZE, uv[b] * SIZE, uv[c] * SIZE)
			n += 1
		# A little wider, so the seams don't show
		var grown := img.duplicate()
		for y in SIZE:
			for x in SIZE:
				if img.get_pixel(x, y).r > .5:
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							grown.set_pixel(clampi(x + dx, 0, SIZE - 1), clampi(y + dy, 0, SIZE - 1), Color.WHITE)
		grown.save_png("res://art/pals/%s_skin.png" % id)
		print("%s: %d skin triangles of %d" % [id, n, idx.size() / 3])
	quit()


func _fill(img: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	var lo := Vector2i(floori(minf(a.x, minf(b.x, c.x))), floori(minf(a.y, minf(b.y, c.y))))
	var hi := Vector2i(ceili(maxf(a.x, maxf(b.x, c.x))), ceili(maxf(a.y, maxf(b.y, c.y))))
	var area := (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	for y in range(maxi(0, lo.y), mini(SIZE, hi.y + 1)):
		for x in range(maxi(0, lo.x), mini(SIZE, hi.x + 1)):
			var p := Vector2(x + .5, y + .5)
			var w0 := (c - b).cross(p - b) / area
			var w1 := (a - c).cross(p - c) / area
			var w2 := 1.0 - w0 - w1
			if w0 >= -.02 and w1 >= -.02 and w2 >= -.02:
				img.set_pixel(x, y, Color.WHITE)
