class_name Houses
extends RefCounted
## The village's houses, built in code like the rest of the world: a stone plinth, timber-framed walls with a
## real doorway and windows, a pitched roof of tile or thatch rows, a chimney, and a room inside with a floor,
## a hearth, beds, a table and the things of whoever lives there. You can walk in; Mo, Bo and the islanders go
## in to eat and sleep (Pal.go_in), and are seen in there, at the table or in bed.
##
## Seen from outside, a house is whole. Once you're inside, the roof and the walls between you and the camera
## are drawn only for their eyes (CUT_LAYER, which the main camera leaves out), so you look down into the room;
## what Mo and Bo see never changes.

## The floor stands this high above the ground the house is built on
const FLOOR := .32
## Wall thickness
const T := .16
const DOOR_W := 1.05
const DOOR_H := 2.05
## Render layer the main camera skips (game.gd), for the walls and roof cut away while you're inside
const CUT_LAYER := 1 << 11
const ROOF_PITCH := .62

## Each home: size (w across the front, d deep, h of the walls), colours, the roof's kind, where the door and
## windows are (x along the front and back, z along the sides), how many beds, and what's theirs inside
const SPECS := {
	house = {w = 5.8, d = 4.6, h = 2.45, walls = "#F2E4CB", roof = "#D46A4C", timber = "#6B4630", trim = "#4F86B8",
		roof_kind = "tiles", base = "stone", door_x = -1.0, front = [1.35], back = [-1.2, 1.3], side = [.2], beds = 2,
		rug = "#B8584A", blanket = ["#E57A5A", "#5AA9FF"], kind = "home", porch = true},
	nell = {w = 4.6, d = 3.9, h = 2.4, walls = "#DCE3E2", roof = "#4F7282", timber = "#5D5246", trim = "#C8553D",
		roof_kind = "tiles", base = "stone", door_x = -.7, front = [1.1], back = [.6], side = [], beds = 1,
		rug = "#4F7282", blanket = ["#8FB3C4"], kind = "fisher"},
	tam = {w = 4.8, d = 4.0, h = 2.4, walls = "#F5E6B6", roof = "#C99A4A", timber = "#7A5634", trim = "#6E8B3D",
		roof_kind = "thatch", base = "stone", door_x = .6, front = [-1.2], back = [0.0], side = [-.2], beds = 1,
		rug = "#D9A441", blanket = ["#E8C547"], kind = "bees"},
	odo = {w = 4.6, d = 3.9, h = 2.4, walls = "#DCC4A6", roof = "#6E527C", timber = "#4E3A2E", trim = "#B5704C",
		roof_kind = "tiles", base = "tall_stone", door_x = -.6, front = [1.1], back = [-.4], side = [.3], beds = 1,
		rug = "#8A5A86", blanket = ["#4FB3A5"], kind = "potter"},
}


## One house, as built.
class House:
	extends RefCounted
	var id := ""
	var spec := {}
	var node: Node3D
	var w := 0.0
	var d := 0.0
	var h := 0.0
	## The walls by side (front +z, back -z, left -x, right +x) and the roof: cut away when you're inside
	var walls := {}
	var roof: Node3D
	var window_m: ShaderMaterial
	var light: OmniLight3D
	var hearth: Dictionary
	var room: Node3D
	## What tick() last set, so materials and lights change only when they need to
	var _glow := -1.0
	var _lit := -1.0
	var _fire := -1.0
	var hearth_light: OmniLight3D
	var smoke: CPUParticles3D
	var crackle: AudioStreamPlayer3D
	var door_leaf: Node3D
	var door_k := 0.0
	var door_until := 0.0
	## Wall pieces as segments on the floor (local x, z), with the doorway left open, for you to bump into
	var segs := []
	## Furniture you walk round (local x, z, r)
	var solid := []
	## Where people are when they're inside: beds and a place at the table (local), by kind
	var spots := {bed = [], seat = []}
	var cut := false
	var inside_count := 0

	func floor_y() -> float:
		return node.global_position.y + FLOOR

	func local(p: Vector3) -> Vector2:
		var q := node.to_local(Vector3(p.x, node.global_position.y, p.z))
		return Vector2(q.x, q.z)

	## Inside the walls (pad: how far in from them)
	func contains(p: Vector3, pad := 0.0) -> bool:
		var q := local(p)
		return absf(q.x) < w / 2 - pad and absf(q.y) < d / 2 - pad

	## On the house's floor or its doorstep (where the ground is the floor)
	func on_floor(p: Vector3) -> bool:
		var q := local(p)
		if absf(q.x) < w / 2 and absf(q.y) < d / 2:
			return true
		return absf(q.x - float(spec.door_x)) < .75 and q.y >= d / 2 and q.y < d / 2 + .55

	## Where the door is from outside (out metres in front of it), on the ground
	func door_at(out := .7) -> Vector3:
		return node.to_global(Vector3(float(spec.door_x), 0, d / 2 + out))

	## Keep a point out of the walls and furniture. You (is_wisp) go in by the door; everyone else walks round
	## the house as one rounded block (they go in through Pal.go_in).
	func push(p: Vector3, r: float, is_wisp: bool) -> Vector3:
		var q := local(p)
		if absf(q.x) > w / 2 + 1.5 or absf(q.y) > d / 2 + 1.5:
			return p
		if not is_wisp:
			# The house as one rounded block. Out, and a little round (always the same way), so someone walking
			# into it slides round to the other side instead of standing pushing at the wall
			var hx := w / 2 + .05
			var hz := d / 2 + .05
			var rr := r + .1
			var c := Vector2(clampf(q.x, -hx, hx), clampf(q.y, -hz, hz))
			var off := q - c
			if off.length() < 1e-4:
				var dx := hx - absf(q.x)
				var dz := hz - absf(q.y)
				var nrm := Vector2(1.0 if q.x >= 0 else -1.0, 0) if dx < dz else Vector2(0, 1.0 if q.y >= 0 else -1.0)
				var dep := minf(dx, dz) + rr
				q += nrm * dep + nrm.orthogonal() * dep * .7
			elif off.length() < rr:
				var nrm := off.normalized()
				var dep := rr - off.length()
				q = c + nrm * rr + nrm.orthogonal() * dep * .7
		else:
			for s in segs:
				var c := Geometry2D.get_closest_point_to_segment(q, s[0], s[1])
				var o := q - c
				var m := T / 2 + r
				if o.length() < m:
					q = c + (o.normalized() if o.length() > 1e-4 else Vector2(0, 1)) * m
			for f in solid:
				var o := q - Vector2(f[0], f[1])
				var m: float = f[2] + r
				if o.length() < m and o.length() > 1e-4:
					q = Vector2(f[0], f[1]) + o.normalized() * m
		var g := node.to_global(Vector3(q.x, 0, q.y))
		return Vector3(g.x, p.y, g.z)

	## Cut the roof and the walls facing the camera away (only for the main camera), or put them back.
	func cutaway(on: bool, cam: Vector3) -> void:
		var to := local(cam)
		var face := {front = to.y > d / 2 - .5, back = to.y < -d / 2 + .5, left = to.x < -w / 2 + .5, right = to.x > w / 2 - .5}
		if not on:
			face = {front = false, back = false, left = false, right = false}
		_layers(roof, on)
		for k in walls:
			_layers(walls[k], face[k])
		cut = on

	static func _layers(n: Node, hide: bool) -> void:
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = Houses.CUT_LAYER if hide else 1
		for c in n.get_children():
			_layers(c, hide)


static func _box(parent: Node3D, m: Material, x: float, y: float, z: float, sx: float, sy: float, sz: float) -> MeshInstance3D:
	return Build.mesh(Build.box(sx, sy, sz), m, x, y, z, parent)


## A triangle standing on its base (span along z, rise up), t thick along x: a gable end.
static func _gable(span: float, rise: float, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(0, 0, -span / 2)
	var b := Vector3(0, 0, span / 2)
	var c := Vector3(0, rise, 0)
	for s in [-1.0, 1.0]:
		var o := Vector3(s * t / 2, 0, 0)
		# Both windings: seen from either side
		for tri in [[a, b, c], [a, c, b]]:
			for v in tri:
				st.add_vertex(v + o)
	st.generate_normals()
	return st.commit()


## A wall along x from -len/2 to len/2 (at z = 0, t thick), from 0 up to h, with openings [x0, x1, y0, y1].
static func _wall(parent: Node3D, m: Material, length: float, h: float, holes: Array) -> void:
	holes.sort_custom(func(a, b): return a[0] < b[0])
	var x := -length / 2
	for o in holes:
		if o[0] > x:
			_box(parent, m, (x + o[0]) / 2, h / 2, 0, o[0] - x, h, T)
		if o[2] > 0:
			_box(parent, m, (o[0] + o[1]) / 2, o[2] / 2, 0, o[1] - o[0], o[2], T)
		if o[3] < h:
			_box(parent, m, (o[0] + o[1]) / 2, (o[3] + h) / 2, 0, o[1] - o[0], h - o[3], T)
		x = o[1]
	if x < length / 2:
		_box(parent, m, (x + length / 2) / 2, h / 2, 0, length / 2 - x, h, T)


## A window in a wall's frame (x along it, sill to top): frame, glass that glows at night, shutters, a sill.
static func _window(parent: Node3D, x: float, y0: float, y1: float, wide: float, glass: Material, trim: Material, frame: Material) -> void:
	var hgt := y1 - y0
	var yc := (y0 + y1) / 2
	_box(parent, glass, x, yc, 0, wide, hgt, .04)
	# Frame and a cross bar
	for s in [-1.0, 1.0]:
		_box(parent, frame, x + s * (wide / 2 - .03), yc, 0, .07, hgt, T + .04)
		_box(parent, frame, x, yc + s * (hgt / 2 - .03), 0, wide, .07, T + .04)
	_box(parent, frame, x, yc, 0, .05, hgt, .1)
	_box(parent, frame, x, yc, 0, wide, .05, .1)
	# Sill, and shutters folded open outside
	_box(parent, frame, x, y0 - .04, T / 2 + .06, wide + .2, .07, .16)
	for s in [-1.0, 1.0]:
		var sh := _box(parent, trim, x + s * (wide / 2 + .2), yc, T / 2 + .03, .36, hgt + .04, .04)
		Build.mesh(Build.box(.3, .04, .02), frame, 0, hgt * .25, .025, sh)
		Build.mesh(Build.box(.3, .04, .02), frame, 0, -hgt * .25, .025, sh)


## Build a home at (x, z) on the ground at y, its door facing yaw. It isn't merged or solid yet: the level does that
## (Level.solidify, then finish()).
static func build(id: String, at: Vector3, yaw: float, tag: String) -> House:
	var S: Dictionary = SPECS[id]
	var H := House.new()
	H.id = id
	H.spec = S
	H.w = S.w
	H.d = S.d
	H.h = S.h
	var w: float = S.w
	var d: float = S.d
	var h: float = S.h
	var root := Build.group(null, tag)
	root.position = at
	root.rotation.y = yaw
	H.node = root
	var ao := {ao = .38, ao_h = 1.1}
	var wall_m := Build.mat(S.walls, ao.merged({ao_from = FLOOR}))
	var timber := Build.mat(S.timber, {ao = .25, ao_from = FLOOR})
	var trim := Build.mat(S.trim)
	var stone := Build.mat("#A39C92", {ao = .3, ao_h = .5})
	var stone_dark := Build.mat("#8C857C")
	H.window_m = Build.mat("#FFE6A3", {emissive = "#FFC86B", ei = .1, roughness = .4, unique = true})
	var inner := {sky = .45, ao = .45, ao_from = FLOOR, ao_h = 1.0}

	# The plinth, down into the slope, and a step up to the door
	_box(root, stone, 0, FLOOR - .55, 0, w + .3, 1.1, d + .3)
	for i in 14:
		var a := i / 14.0 * TAU
		var sx := clampf(cos(a) * 1.6, -1, 1) * (w / 2 + .16)
		var sz := clampf(sin(a) * 1.6, -1, 1) * (d / 2 + .16)
		Build.rot(Build.mesh(Build.dodeca(.16 + Build.rnd() * .1), stone_dark if i % 3 == 0 else stone, sx, .08, sz, root), Build.rnd() * 3, Build.rnd() * 3, 0)
	var dx: float = S.door_x
	_box(root, stone, dx, FLOOR - .2, d / 2 + .35, 1.5, .26, .6)
	_box(root, stone_dark, dx, FLOOR - .37, d / 2 + .7, 1.7, .2, .5)

	# The walls: each side its own group, so it can be cut away on its own
	var y0 := FLOOR
	var sides := {front = [Vector3(0, y0, d / 2 - T / 2), 0.0, w], back = [Vector3(0, y0, -d / 2 + T / 2), PI, w],
		left = [Vector3(-w / 2 + T / 2, y0, 0), -PI / 2, d - 2 * T], right = [Vector3(w / 2 - T / 2, y0, 0), PI / 2, d - 2 * T]}
	for k in sides:
		var g := Build.group(root)
		g.set_meta("keep", true)
		g.position = sides[k][0]
		g.rotation.y = sides[k][1]
		H.walls[k] = g
		var length: float = sides[k][2]
		var holes := []
		var wins: Array = S.front if k == "front" else (S.back if k == "back" else S.side)
		var wx := []
		for x in wins:
			# Back windows are seen from behind (the wall's turned round)
			var xx: float = -x if k == "back" else x
			if k == "left" and S.get("chimney", "left") == "left":
				xx = absf(x) + .6
			holes.append([xx - .42, xx + .42, 1.0, 1.75])
			wx.append(xx)
		if k == "front":
			holes.append([dx - DOOR_W / 2, dx + DOOR_W / 2, 0.0, DOOR_H])
		var stone_base: bool = S.base == "tall_stone"
		_wall(g, wall_m, length, h, holes)
		if stone_base:
			# A stone lower course, thicker than the wall
			var parts := [[-length / 2, length / 2]]
			if k == "front":
				parts = [[-length / 2, dx - DOOR_W / 2], [dx + DOOR_W / 2, length / 2]]
			for pr in parts:
				if pr[1] - pr[0] > .05:
					_box(g, stone, (pr[0] + pr[1]) / 2, .45, 0, pr[1] - pr[0], .9, T + .1)
		for xx in wx:
			_window(g, xx, 1.0, 1.75, .84, H.window_m, trim, timber)
		# Timber: a beam along the top and the bottom, and posts between
		_box(g, timber, 0, h - .08, .02, length + .04, .16, T + .06)
		_box(g, timber, 0, .06, .02, length + .04, .12, T + .06)
		var posts := [-length / 2 + .08, length / 2 - .08]
		var n := int(length / 1.5)
		for i in range(1, n):
			var px := -length / 2 + i * length / n
			if holes.all(func(o): return px < o[0] - .12 or px > o[1] + .12):
				posts.append(px)
		for px in posts:
			_box(g, timber, px, h / 2, .03, .14, h, T + .04)
		# A brace or two on the plain stretches
		if not stone_base:
			for i in posts.size() - 1:
				var a: float = posts[i]
				var b: float = posts[i + 1]
				var span := b - a
				if span > 1.0 and holes.all(func(o): return o[1] < a or o[0] > b):
					var br := _box(g, timber, (a + b) / 2, h / 2, .04, sqrt(span * span + h * h * .5) - .1, .11, T + .02)
					br.rotation.z = atan2(h * .7, span) * (1.0 if i % 2 == 0 else -1.0)
		if k == "front":
			# Door frame, and the door (open inward when someone's by it)
			for s in [-1.0, 1.0]:
				_box(g, timber, dx + s * (DOOR_W / 2 + .05), DOOR_H / 2, .02, .12, DOOR_H, T + .08)
			_box(g, timber, dx, DOOR_H + .06, .02, DOOR_W + .22, .14, T + .08)
			var hinge := Build.group(g)
			hinge.set_meta("keep", true)
			hinge.position = Vector3(dx - DOOR_W / 2 + .03, 0, -.02)
			var door_m := Build.mat(S.trim if id == "house" else "#8A5A3C", {ao = .2})
			_box(hinge, door_m, DOOR_W / 2 - .03, DOOR_H / 2, 0, DOOR_W - .08, DOOR_H - .04, .06)
			for yy in [.45, 1.55]:
				_box(hinge, Build.mat("#3B3B42"), DOOR_W / 2 - .03, yy, .04, DOOR_W - .2, .06, .02)
			Build.mesh(Build.sphere(.04, 8, 6), Build.mat("#C9A65A", {roughness = .4}), DOOR_W - .2, 1.0, .06, hinge)
			H.door_leaf = hinge
			H.segs.append([Vector2(-w / 2, d / 2 - T / 2), Vector2(dx - DOOR_W / 2, d / 2 - T / 2)])
			H.segs.append([Vector2(dx + DOOR_W / 2, d / 2 - T / 2), Vector2(w / 2, d / 2 - T / 2)])
	H.segs.append([Vector2(-w / 2, -d / 2 + T / 2), Vector2(w / 2, -d / 2 + T / 2)])
	H.segs.append([Vector2(-w / 2 + T / 2, -d / 2), Vector2(-w / 2 + T / 2, d / 2)])
	H.segs.append([Vector2(w / 2 - T / 2, -d / 2), Vector2(w / 2 - T / 2, d / 2)])

	# The roof: rows of tiles (or thatch) down each side from the ridge, gables at the ends, a chimney
	var roof := Build.group(root)
	roof.set_meta("keep", true)
	H.roof = roof
	var top := y0 + h
	var over := .5
	var run := d / 2 + over
	var rise := (d / 2) * tan(ROOF_PITCH)
	var ridge := top + rise + .06
	var slope := run / cos(ROOF_PITCH)
	var thatch: bool = S.roof_kind == "thatch"
	var rows := 5 if thatch else 7
	var rc := Color(S.roof)
	var row_m := [Build.mat(S.roof, {ao = .0}), Build.mat(rc.darkened(.1).to_html(false)), Build.mat(rc.lightened(.06).to_html(false))]
	var thick := .2 if thatch else .08
	for s in [-1.0, 1.0]:
		for i in rows:
			var u := slope * (1.0 - (i + .5) / rows)
			var depth := slope / rows * (1.35 if thatch else 1.25)
			var tile := _box(roof, row_m[(i + (1 if s > 0 else 0)) % 3], 0, 0, 0, w + over * 1.4 + (.1 if thatch else 0.0), thick, depth)
			tile.position = Vector3(0, ridge - u * sin(ROOF_PITCH) + i * .012, s * u * cos(ROOF_PITCH))
			tile.rotation.x = s * ROOF_PITCH
			if not thatch and i % 2 == 1:
				# Tiles: every other row a touch shifted, so the courses read
				tile.position.x += .06
			if thatch:
				# Each course of straw ends in a rolled lip, lying on the course below
				var up := Vector3(0, cos(ROOF_PITCH), s * sin(ROOF_PITCH))
				var down := Vector3(0, -sin(ROOF_PITCH), s * cos(ROOF_PITCH))
				var lip := Build.mesh(Build.cyl(thick * .75, thick * .75, w + over * 1.4 + .16, 8), row_m[(i + 1) % 3], 0, 0, 0, roof)
				lip.position = tile.position + down * depth * .5 + up * thick * .35
				lip.rotation = Vector3(0, 0, PI / 2)
	if thatch:
		var rr := Build.mesh(Build.cyl(.2, .2, w + over * 1.4 + .1, 10), Build.mat(rc.darkened(.15).to_html(false)), 0, ridge + .06, 0, roof)
		rr.rotation.z = PI / 2
	else:
		_box(roof, Build.mat(rc.darkened(.25).to_html(false)), 0, ridge + .05, 0, w + over * 1.4, .14, .26)
	# Gables, and the boards along their edges
	for s in [-1.0, 1.0]:
		var gb := Build.mesh(_gable(d, rise + .02, T), wall_m, s * (w / 2 - T / 2), top, 0, roof)
		gb.set_meta("gable", true)
		for zs in [-1.0, 1.0]:
			var bb := _box(roof, timber, s * (w / 2 + over * .7), 0, 0, .08, .16, slope + .1)
			bb.position = Vector3(s * (w / 2 + over * .7), ridge - slope / 2 * sin(ROOF_PITCH) - .02, zs * slope / 2 * cos(ROOF_PITCH))
			bb.rotation.x = zs * ROOF_PITCH
	var chim_z := -d / 4
	var chimney := Build.group(roof)
	_box(chimney, stone, 0, (ridge + .6 - FLOOR) / 2, 0, .62, ridge + .6 - FLOOR, .62)
	_box(chimney, stone_dark, 0, ridge + .62 - FLOOR, 0, .74, .12, .74)
	chimney.position = Vector3(-w / 2 + .1, FLOOR, chim_z)
	H.smoke = _smoke()
	H.smoke.position = Vector3(-w / 2 + .1, ridge + .9, chim_z)
	root.add_child(H.smoke)
	if S.get("porch", false):
		# A little roof over the door on two posts, and a bench by it
		var pr := Build.group(roof)
		for s in [-1.0, 1.0]:
			_box(pr, timber, dx + s * .85, (DOOR_H + .3) / 2 + FLOOR - .2, d / 2 + 1.05, .12, DOOR_H + .3, .12)
		var lid := _box(pr, row_m[1], dx, FLOOR + DOOR_H + .32, d / 2 + .6, 2.1, .08, 1.3)
		lid.rotation.x = .28
		H.solid.append([dx - .85, d / 2 + 1.05, .12])
		H.solid.append([dx + .85, d / 2 + 1.05, .12])

	# Inside (its own mesh, casting no shadow: the walls and roof already shade it)
	var room := Build.group(root)
	room.set_meta("keep", true)
	H.room = room
	var plank_a := Build.mat("#B98B5E", inner)
	var plank_b := Build.mat("#A97C52", inner)
	var n_planks := int((w - 2 * T) / .3)
	for i in n_planks:
		_box(room, plank_a if i % 2 == 0 else plank_b, -w / 2 + T + (i + .5) * (w - 2 * T) / n_planks, FLOOR - .02, 0, (w - 2 * T) / n_planks - .015, .06, d - 2 * T)
	_box(room, Build.mat(S.rug, inner), .1, FLOOR + .015, .35, 1.9, .02, 1.3)
	# Beams across under the roof (cut away with it)
	for i in 3:
		_box(roof, timber, -w / 2 + w * (i + 1) / 4.0, top - .1, 0, .16, .18, d - .1)
	_hearth(H, room, inner, stone, stone_dark)
	_beds(H, room, inner, timber)
	_table(H, room, inner, timber)
	_belongings(H, room, inner, timber, trim)
	# A warm light in the room (lit at night, or when you're in)
	H.light = Build.omni("#FFC48A", 0, maxf(w, d) * 1.1, 1.3)
	H.light.position = Vector3(.3, top - .45, .2)
	root.add_child(H.light)
	return H


static func _hearth(H: House, room: Node3D, inner: Dictionary, stone: Material, stone_dark: Material) -> void:
	var g := Build.group(room)
	var x := -H.w / 2 + T + .3
	var z := -H.d / 4
	_box(g, stone, x, FLOOR + .55, z, .6, 1.1, 1.2)
	_box(g, Build.mat("#2A2420"), x + .2, FLOOR + .35, z, .25, .55, .7)
	_box(g, Build.mat("#7A5236", inner), x + .3, FLOOR + 1.12, z, .22, .08, 1.4)
	_box(g, stone_dark, x + .35, FLOOR + .03, z, .5, .06, 1.3)
	# Pots on the mantel
	for i in 3:
		Build.mesh(Build.cyl(.06, .07, .16, 8), Build.mat(["#C46A4A", "#5E8FB8", "#E8D6A8"][i]), x + .32, FLOOR + 1.24, z - .45 + i * .4, room)
	H.hearth = Build.flames(g, [["#FF7A2F", .14, .38], ["#FFB547", .1, .28], ["#FFE491", .05, .18]])
	H.hearth.g.position = Vector3(x + .32, FLOOR + .08, z)
	Build.nohit(H.hearth.g)
	H.hearth_light = Build.omni("#FF8A3C", 0, 3.5, 1.6)
	H.hearth_light.position = Vector3(x + .7, FLOOR + .6, z)
	room.add_child(H.hearth_light)
	H.solid.append([x + .1, z, .62])


static func _beds(H: House, room: Node3D, inner: Dictionary, timber: Material) -> void:
	var S := H.spec
	var n: int = S.beds
	var long := 2.05 if H.id != "house" else 1.75
	for i in n:
		var x := H.w / 2 - T - .62 - i * 1.15
		var z := -H.d / 2 + T + long / 2 + .02
		var g := Build.group(room)
		var frame := Build.mat("#8A5E3C", inner)
		_box(g, frame, x, FLOOR + .2, z, .98, .28, long)
		_box(g, frame, x, FLOOR + .45, z - long / 2 + .04, .98, .75, .08)
		_box(g, frame, x, FLOOR + .3, z + long / 2 - .04, .98, .4, .08)
		_box(g, Build.mat("#F4EFE6", inner), x, FLOOR + .4, z, .88, .14, long - .12)
		_box(g, Build.mat(S.blanket[i % S.blanket.size()], inner), x, FLOOR + .47, z + long * .12, .92, .07, long * .66)
		_box(g, Build.mat("#FFFFFF", inner), x, FLOOR + .5, z - long / 2 + .28, .6, .1, .3)
		H.solid.append([x, z - .35, .5])
		H.solid.append([x, z + .35, .5])
		# Lying in it: feet at the foot of the bed, head on the pillow, facing up
		H.spots.bed.append({at = Vector3(x, 0, z + long / 2 - .25), yaw = 0.0, lift = .33})


static func _table(H: House, room: Node3D, inner: Dictionary, timber: Material) -> void:
	var x := -.35 if H.id == "house" else -.2
	var z := .45
	var g := Build.group(room)
	var wood := Build.mat("#9A6B44", inner)
	Build.mesh(Build.cyl(.55, .55, .07, 14), wood, x, FLOOR + .74, z, g)
	Build.mesh(Build.cyl(.08, .12, .7, 8), wood, x, FLOOR + .37, z, g)
	for s in [-1.0, 1.0]:
		Build.mesh(Build.cyl(.2, .18, .06, 10), wood, x + s * .85, FLOOR + .45, z, g)
		Build.mesh(Build.cyl(.05, .06, .42, 6), wood, x + s * .85, FLOOR + .21, z, g)
		H.spots.seat.append({at = Vector3(x + s * .85, 0, z), yaw = -s * PI / 2, lift = 0.0})
	# Bread and a jug on it
	Build.mesh(Build.sphere(.11, 10, 6, PI / 2), Build.mat("#D9A35E", inner), x + .15, FLOOR + .78, z - .1, g).scale.y = .7
	Build.mesh(Build.cyl(.06, .08, .22, 10), Build.mat("#E8E1D4", inner), x - .18, FLOOR + .88, z + .12, g)
	H.solid.append([x, z, .58])


## Whose house it is shows: the larder, Mo's shells and Bo's drawings; nets and floats; honey and herbs; pots.
static func _belongings(H: House, room: Node3D, inner: Dictionary, timber: Material, trim: Material) -> void:
	var w := H.w
	var d := H.d
	var shelf_m := Build.mat("#8A5E3C", inner)
	# A shelf on the back wall, at the left
	var sx := -w / 2 + 1.5
	var sz := -d / 2 + T + .14
	for yy in [1.0, 1.45]:
		_box(room, shelf_m, sx, FLOOR + yy, sz, 1.1, .05, .26)
	var things: Array = []
	match H.spec.kind:
		"home":
			# The larder by the door, and Mo's shells and Bo's pictures
			var lx := w / 2 - T - .35
			var lz := d / 2 - T - .55
			_box(room, Build.mat("#7A5236", inner), lx, FLOOR + .85, lz, .6, 1.7, .9)
			_box(room, Build.mat(H.spec.trim, inner), lx - .31, FLOOR + .85, lz, .02, 1.5, .8)
			H.solid.append([lx, lz, .5])
			for i in 5:
				Build.mesh(Build.cone(.05, .08, 7), Build.mat(["#F7D9C4", "#F2B8A8", "#FFF1DE", "#E9C9F0", "#F7D9C4"][i]), sx - .4 + i * .2, FLOOR + 1.07, sz, room).rotation.z = PI / 2
			for i in 2:
				var pic := _box(room, Build.mat("#FFF8EE", inner), -1.0 + i * .9, FLOOR + 1.65, -d / 2 + T + .02, .5, .4, .02)
				Build.mesh(Build.box(.3, .12, .01), Build.mat(["#5AA9FF", "#E57A5A"][i]), 0, -.05, .015, pic)
			things = [["#E8D6A8", .1], ["#C46A4A", .08], ["#9BC27A", .09]]
		"fisher":
			# A net on the wall, floats and oars
			var net := Build.group(room)
			var cord := Build.mat("#C9B48A", inner)
			for i in 6:
				_box(net, cord, -.6 + i * .24, 0, 0, .02, 1.1, .02)
				_box(net, cord, 0, -.5 + i * .2, 0, 1.25, .02, .02)
			net.position = Vector3(.3, FLOOR + 1.25, -d / 2 + T + .03)
			for i in 3:
				Build.mesh(Build.sphere(.09, 10, 8), Build.smooth(["#5FB38A", "#4F86B8", "#C8553D"][i], {opacity = .85, roughness = .2}), -.1 + i * .3, FLOOR + .75, -d / 2 + T + .1, room)
			for s in [-1.0, 1.0]:
				var oar := _box(room, Build.mat("#B98A5A", inner), w / 2 - T - .1, FLOOR + 1.0, .5 + s * .15, .05, 2.0, .06)
				oar.rotation.x = s * .25
			things = [["#9DB0B5", .09], ["#C9B48A", .1]]
		"bees":
			# Honey jars that catch the light, and herbs drying from a beam
			for i in 6:
				Build.mesh(Build.cyl(.07, .07, .16, 10), Build.smooth("#F2A93B", {opacity = .9, roughness = .25, emissive = "#C97A1A", ei = .15}), sx - .45 + i * .18, FLOOR + 1.11, sz, room)
			for i in 5:
				var hb := Build.mesh(Build.cone(.09, .35, 6), Build.mat(["#7FA65A", "#9BC27A", "#C9A0D8"][i % 3]), -.8 + i * .45, FLOOR + H.h - .4, -.1, room)
				hb.rotation.z = PI
			things = [["#F2A93B", .09], ["#E8C547", .08]]
		"potter":
			# Pots on every shelf, and a big one on the floor
			for yy in [1.07, 1.52]:
				for i in 4:
					Build.mesh(Build.cyl(.06 + i % 2 * .03, .08, .18 + (i % 3) * .05, 10), Build.mat(["#B5704C", "#C98A5E", "#8E5A3C", "#D9A06E"][i]), sx - .42 + i * .28, FLOOR + yy + .1, sz, room)
			Build.mesh(Build.sphere(.32, 12, 9), Build.mat("#B5704C", inner), w / 2 - T - .45, FLOOR + .3, d / 2 - T - .45, room).scale.y = 1.2
			H.solid.append([w / 2 - T - .45, d / 2 - T - .45, .35])
			things = [["#C98A5E", .1], ["#8E5A3C", .08]]
	for i in things.size():
		Build.mesh(Build.cyl(things[i][1], things[i][1] * 1.1, .2, 9), Build.mat(things[i][0]), sx - .3 + i * .32, FLOOR + 1.56, sz, room)
	# A chest at the foot of the room
	var cx := -w / 2 + T + .4
	var cz := d / 2 - T - .4
	if H.spec.door_x < -.3:
		cx = -w / 2 + T + .35
		cz = -.2 + d / 4
	_box(room, Build.mat("#7A5236", inner), cx, FLOOR + .22, cz, .5, .44, .8)
	_box(room, Build.mat("#3B3B42"), cx, FLOOR + .38, cz, .52, .04, .82)
	H.solid.append([cx, cz, .4])


static func _smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 7
	p.lifetime = 4.5
	p.preprocess = 4.5
	p.local_coords = false
	p.direction = Vector3(.2, 1, 0)
	p.spread = 12
	p.gravity = Vector3(.12, .08, 0)
	p.initial_velocity_min = .35
	p.initial_velocity_max = .55
	p.scale_amount_min = .7
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, .35))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(.15, Color(1, 1, 1, .5))
	ramp.add_point(.6, Color(1, 1, 1, .25))
	p.color_ramp = ramp
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(.5, .5)
	soft.fill_to = Vector2(1, .5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color("#D8D4CE")
	m.albedo_texture = soft
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(.7, .7)
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	Build.nohit(p)
	return p


## After the level's solidified: each part (each wall, the roof, the rest) becomes one mesh with its colours
## in the vertices, so a house is a handful of draws; the glowing glass and the flames stay as they are.
static func finish(H: House) -> void:
	if H.door_leaf:
		bake(H.door_leaf, Build.mat("#FFFFFF", {vcol = true}))
	for k in H.walls:
		bake(H.walls[k], Build.mat("#FFFFFF", {vcol = true, ao = .35, ao_h = 1.0}))
		Build.merge_static(H.walls[k])
	bake(H.roof, Build.mat("#FFFFFF", {vcol = true}))
	bake(H.room, Build.mat("#FFFFFF", {vcol = true, ao = .4, ao_from = FLOOR - .1, ao_h = 1.0}))
	for c in H.room.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Build.merge_static(H.room)
	bake(H.node, Build.mat("#FFFFFF", {vcol = true, ao = .4, ao_from = FLOOR - .1, ao_h = 1.0}))
	Build.merge_static(H.node)


## Bake root's plain meshes (one colour each) into one, its colours in the vertices.
static func bake(root: Node3D, m: ShaderMaterial) -> void:
	var inv := root.global_transform.affine_inverse()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var done := []
	var stack: Array = root.get_children()
	while stack.size():
		var c: Node = stack.pop_back()
		if c.has_meta("keep") or c.has_meta("tag") or c.has_meta("body") or (c is Node3D and not c.visible):
			continue
		if c is MeshInstance3D and c.mesh and c.get_child_count() == 0:
			var sm = c.material_override
			if not (sm is ShaderMaterial) or sm.shader != Build.LIT or float(sm.get_shader_parameter("emissive_energy")) > 0 or sm.get_shader_parameter("use_tex"):
				continue
			var col: Color = sm.get_shader_parameter("albedo")
			col.a = sm.get_shader_parameter("sky_seen") if sm.get_shader_parameter("sky_seen") != null else 1.0
			var xf: Transform3D = inv * c.global_transform
			var nb := xf.basis.inverse().transposed()
			var arr: Array = c.mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns = arr[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for i in vs.size():
				verts.append(xf * vs[i])
				norms.append((nb * ns[i]).normalized() if ns != null and ns.size() == vs.size() else Vector3.UP)
				cols.append(col)
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix != null and ix.size() > 0:
				for i in ix:
					idx.append(base + i)
			else:
				for i in vs.size():
					idx.append(base + i)
			done.append(c)
		else:
			stack.append_array(c.get_children())
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = m
	mi.set_meta("merged", true)
	root.add_child(mi)
	for n in done:
		n.get_parent().remove_child(n)
		n.free()


## Every frame: the door swings, the windows glow, the hearth and its smoke, the room's light.
## eve: how evening it is; fire: is the hearth lit; near: how far you are; in: you're inside.
static func tick(H: House, dt: float, t: float, eve: float, fire: bool, near: float, in_: bool, someone_in: bool) -> void:
	var want := 1.0 if t < H.door_until else 0.0
	H.door_k = move_toward(H.door_k, want, dt * 2.2)
	if H.door_leaf:
		H.door_leaf.rotation.y = -1.7 * Game.ease_io(H.door_k)
	# The room's own lights only near you (a light costs every pixel it reaches); from further off the windows glow
	var home := someone_in or eve > .3
	var glow := snappedf(lerpf(.1, 1.5, eve) if home else lerpf(.1, .3, eve), .02)
	if glow != H._glow:
		H._glow = glow
		Build.set_glow(H.window_m, glow)
	if H.hearth.g.visible != fire:
		H.hearth.g.visible = fire
	# The room's own lights only when you're in or at the door (a light costs every pixel it reaches); from
	# further off the windows glow
	var close := in_ or near < maxf(H.w, H.d) * .5 + 2.5
	if fire and close:
		Build.flicker(H.hearth, t, dt)
		Build.set_light(H.hearth_light, 6.0 + sin(t * 13.0) * .8)
	elif H._fire != 0.0:
		Build.set_light(H.hearth_light, 0.0)
	H._fire = 1.0 if fire and close else 0.0
	var room := ((2.6 if eve > .3 else 1.8) if close and (home or in_) else 0.0)
	if room != H._lit:
		H._lit = room
		Build.set_light(H.light, room)
	H.smoke.emitting = fire and near < 45.0
