class_name Pal
extends Node3D
## Mo or Bo: a kid who goes along with you, or off on their own (mind.gd), looks at things, talks, and
## remembers what they've seen. The body is a rigged, textured model (art/pals, made from
## the pictures with Hunyuan3D) on the Universal Animation Library's skeleton, with its
## clips: idle, walk, run, jump, talk, pick_up, wave and point, and blink for the eyelids.
## gait.gd blends them by speed and leans them into turns; the head turns to what they look at.
## How they feel shows (looks.gd, set by mind.gd): a pose layer over the clips (Bearing: slumped, hunched,
## shivering), the pace and spring of their walk, the eyelids, a little face (brows and a mouth) and where their
## eyes go (whoever they're with, what they're after, glancing about when scared, sliding off you after a fib).

signal arrived(gen: int)
## Walked into something or someone (mind.gd makes a feeling of it): "thing" (with how it felt) or "person"
signal bumped(kind: String, what)

const PAL_LAYER := 2
const MODELS := {mo = preload("res://art/pals/mo.glb"), bo = preload("res://art/pals/bo.glb")}
const SKIN := preload("res://shaders/pal.gdshader")
const INK := preload("res://shaders/ink.gdshader")
## The eyelids' bones: only the blink player moves them (players sharing a skeleton must not
## touch each other's bones)
const LIDS := ["lid.L", "lid.R"]
## Gestures that play once over standing still, and how fast
const ONCE := {jump = 1.0, pick_up = 2.2, wave = 1.0, point = 1.0}
## Easing into and out of going (m/s²)
const ACCEL := 4.5
const DECEL := 5.0

var id := ""
var pal_name := ""
var color := Color.WHITE
var game: Node

var inner: Node3D
var skin: ShaderMaterial
var skel: Skeleton3D
var gait: Gait
var eye_anim: AnimationPlayer
var looker: LookAt
var eye_y := 0.0
var shut := false
var gesture := ""
var gesture_new := false
var was_active := false
var was_look := 0.0
var was_crouch := 0.0
var body: StaticBody3D
var cy := 0.0
var speed := 2.1
## How fast they're going now (eased toward what they want)
var pace := 0.0
var phase := 0.0
var layer_bit := 2
## Which model they wear ("mo" or "bo"), and how much bigger than it they are
var model_id := ""
var size := Vector3.ONE
## Mo and Bo go along with you; the island's other people live their own lives (Folk)
var folk := false
## Talking quietly to someone, out of your hearing (gossip, minds.gd): seconds left; the mouth goes
var mutter := 0.0
## Far from you (the island's other people): fewer updates, their clips stepped by hand, no pose layers or face
var far := false
var lod_dt := 0.0

var yaw := PI
var t_yaw := PI
var path = null
var walk_gen := 0
var talk := false
var closed := false
var blink := 1.0
var jump := 0.0
var jv := 0.0
var sq := 0.0
var gaze = null
var crouch := 0.0
var mode := "follow"
var going := false
var plate = null
## Everything this one has seen, as "level:thing". Kept for the whole adventure.
var known := {}
var recoil := 0.0
var look = null
var look_t := 0.0
## Their voice (voice.gd): their lines, in their Fish Audio voice
var voice: Voice
## What they're carrying: a thing from a level ({t, node, light, …}), or null
var held = null
## Who they keep near in "follow": the light, or the other one
var follow_who: Node3D = null
## Where they are ("isle", "cave"): each can be somewhere else. Only those where you are are in view.
var place_id := "isle"
## Just come through a way: placed at the arrival when you next come there too
var arriving := true
## Where they came from, and since when they've been away from you
var came_from := ""
var away_since := 0.0
## Lying down (resting or asleep): they ease down onto the ground and back up
var lie := false
## Raised off the floor (lying in a bed, indoors)
var lift := 0.0
var lying := 0.0
## Indoors ("house"): out of sight and out of the way until they come out
var inside := ""
## Not to feel the same bump over and over while pressing on
var bump_t := 0.0
## Body language on (off only to measure what it costs)
static var expressive := true
## How they look (Looks.of, from mind.gd a few times a second), and what's shown now (eased toward it)
var feel := {}
var shown := {slump = 0.0, hunch = 0.0, shiver = 0.0, bounce = 0.0, walk = 1.0, lids = 0.0}
## Who they're with (to look at, or away from), and what they're thinking about (where they're going)
var with_node: Node3D = null
var think_at = null
## Seconds left of looking shifty (just said something that wasn't so)
var nervous := 0.0
var bearing: Bearing
var mug: Dictionary = {}
var glance_t := 0.0
var glance_n := 0
var glance_len := 1.0
var lids_at := -1.0
## Where their eyes are going now, as body language has it (null: where gaze says)
var eyes_on = null
var since := 0.0


func setup(o: Dictionary, g: Node) -> void:
	game = g
	id = o.id
	pal_name = o.name
	color = Color(o.color)
	layer_bit = o.layer
	model_id = o.get("model", id)
	size = o.get("scale", Vector3.ONE)
	folk = Folk.has(id)
	name = pal_name
	set_meta("tag", id)
	inner = Node3D.new()
	add_child(inner)
	var model: Node3D = MODELS[model_id].instantiate()
	model.scale = size
	inner.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var R := .26 * size.x
	cy = mesh.get_aabb().end.y / 2 * size.y
	skin = ShaderMaterial.new()
	skin.shader = SKIN
	skin.set_shader_parameter("emissive", color)
	skin.set_shader_parameter("hue", o.get("hue", 0.0))
	skin.set_shader_parameter("desat", o.get("desat", 0.0))
	skin.set_shader_parameter("tone", o.get("tone", 1.0))
	if folk:
		skin.set_shader_parameter("skin_mask", load("res://art/pals/%s_skin.png" % model_id))
		skin.set_shader_parameter("skin_sat", .68 if model_id == "mo" else .9)
	var src_mat = mesh.mesh.surface_get_material(0)
	if src_mat is BaseMaterial3D:
		skin.set_shader_parameter("albedo_tex", src_mat.albedo_texture)
	mesh.material_override = skin
	var src: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	gait = Gait.new(model, src, ONCE, func(b): return not LIDS.has(b))
	eye_anim = _player(model, src, ["blink"], func(b): return LIDS.has(b))
	src.queue_free()
	eye_y = skel.get_bone_global_rest(skel.find_bone(LIDS[0])).origin.y * size.y
	# Longer legs, longer strides
	gait.grow(size.y)
	looker = LookAt.new()
	looker.head = skel.find_bone("DEF-head")
	looker.neck = skel.find_bone("DEF-neck")
	bearing = Bearing.new()
	bearing.setup(skel)
	skel.add_child(bearing)
	skel.add_child(looker)
	_make_face(mesh)
	# Each on its own render layer, so the corner view can leave out the one looking
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (layer_bit - 1)
	# Something for the others' eyes to bump into
	body = StaticBody3D.new()
	body.collision_layer = PAL_LAYER
	body.collision_mask = 0
	body.set_meta("tag", id)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = R
	cap.height = cy * 2
	cs.shape = cap
	cs.position.y = cy
	body.add_child(cs)
	add_child(body)
	voice = Voice.new()
	voice.position.y = cy * 1.75
	add_child(voice)
	phase = Build.rnd() * 6
	gait.t_idle = phase
	reset()


func reset() -> void:
	if voice:
		voice.hush()
	held = null
	follow_who = null
	place_id = "isle"
	arriving = true
	came_from = ""
	yaw = PI
	t_yaw = PI
	stop()
	pace = 0
	talk = false
	closed = false
	blink = 1 + Build.rnd() * 3
	jump = 0
	jv = 0
	sq = 0
	gaze = game.wisp
	crouch = 0
	# The island's other people never trail after you
	mode = "free" if folk else "follow"
	going = false
	plate = null
	known.clear()
	recoil = 0
	look = null
	look_t = 0
	lie = false
	lying = 0
	go_out()
	shut = false
	gesture = ""
	_rest(eye_anim, "blink")
	lids_at = -1.0
	feel = {}
	nervous = 0.0
	with_node = null
	think_at = null
	for c in inner.get_children():
		if c.has_meta("carried"):
			c.queue_free()


## In view (where you are) or not: hidden, with nothing to bump into, while they're somewhere else.
func set_here(on: bool) -> void:
	visible = on
	body.collision_layer = PAL_LAYER if on and inside == "" else 0
	if not on and voice:
		voice.hush()


## Where they are indoors, if the level shows its rooms (island.gd inside_spot): in bed asleep, at the table
## otherwise. {at, yaw, lift}; empty when they're not in, or it can't be seen.
func spot_inside() -> Dictionary:
	if inside == "" or game.level == null or game.level.id != place_id or not game.level.has_method("inside_spot"):
		return {}
	return game.level.inside_spot(inside, self)


## Into a house (out of sight, or in its room), or back out of it at the door.
func go_in(where: String) -> void:
	inside = where
	inner.visible = false
	body.collision_layer = 0


func go_out(at = null) -> void:
	if inside == "" and inner.visible:
		return
	inside = ""
	lift = 0.0
	inner.visible = true
	body.collision_layer = PAL_LAYER if visible else 0
	if at is Vector3:
		position = at


func place(x: float, z: float) -> void:
	position = Vector3(x, 0, z)
	stop()
	mode = "free" if folk else "follow"
	face(game.wisp_g)
	yaw = t_yaw


## Walk through the points ([x, z] each); returns when there, or when stopped.
func walk(pts: Array) -> void:
	stop()
	walk_gen += 1
	var mine := walk_gen
	path = pts.map(func(q): return Vector3(q[0], 0, q[1]))
	while true:
		var done: int = await arrived
		if done >= mine:
			return


func stop() -> void:
	path = null
	arrived.emit.call_deferred(walk_gen)


func face(v: Vector3) -> void:
	t_yaw = atan2(v.x - position.x, v.z - position.z)


func bounce() -> void:
	if jump <= 0:
		jv = 3.4
		_gesture("jump")


func _gesture(g: String) -> void:
	gesture = g
	gesture_new = true


func knows(key: String) -> bool:
	return known.has(key)


## Pick a thing up: it goes in their hand, light and all, and stops being something to bump into.
func hold(T: Dictionary) -> void:
	held = T
	var n: Node3D = T.node
	if not T.has("ground_scale"):
		T.ground_scale = n.scale
	n.reparent(inner, false)
	n.position = Vector3(-.26, cy * 1.05 + T.get("hold_y", 0.0), .2)
	n.rotation = Vector3.ZERO
	n.scale = T.ground_scale * T.get("hold_scale", 1.0)
	n.set_meta("carried", true)
	_bodies(n, false)
	_gesture("pick_up")


## Let go of what they hold; the level puts it down, or someone else takes it.
func let_go() -> Dictionary:
	var T: Dictionary = held
	held = null
	if T == null:
		return {}
	T.node.remove_meta("carried")
	T.node.scale = T.get("ground_scale", T.node.scale)
	_bodies(T.node, true)
	return T


static func _bodies(n: Node, on: bool) -> void:
	for b in n.find_children("*", "StaticBody3D", true, false):
		if on:
			b.collision_layer = b.get_meta("layer", b.collision_layer)
		else:
			b.set_meta("layer", b.collision_layer)
			b.collision_layer = 0


func eye_world() -> Vector3:
	# Lying down, the eyes are near the ground
	return to_global(Vector3(0, lerpf(eye_y + inner.position.y, .3, lying), lerpf(.2, -.8, lying)))


## Hold a clip's first pose (the eyes open).
func _rest(p: AnimationPlayer, clip: String) -> void:
	p.play(clip)
	p.seek(0, true)
	p.pause()


## A player for some of the model's clips, keeping only the tracks of the bones keep() accepts.
func _player(model: Node3D, src: AnimationPlayer, clips: Array, keep: Callable) -> AnimationPlayer:
	var lib := AnimationLibrary.new()
	for c in clips:
		var a: Animation = src.get_animation(c).duplicate()
		for i in range(a.get_track_count() - 1, -1, -1):
			if not keep.call(str(a.track_get_path(i)).get_slice(":", 1)):
				a.remove_track(i)
		a.loop_mode = Animation.LOOP_NONE if ONCE.has(c) or c == "blink" else Animation.LOOP_LINEAR
		lib.add_animation(c, a)
	var p := AnimationPlayer.new()
	p.name = clips[0].capitalize() + "Player"
	model.add_child(p)
	p.root_node = p.get_path_to(model)
	p.add_animation_library("", lib)
	return p


## Turns the head (and a little of the neck) toward a point after the clips have posed the body.
class LookAt extends SkeletonModifier3D:
	var head := -1
	var neck := -1
	## Where to look, in the skeleton's space (null: straight ahead)
	var target = null
	var turn := Quaternion.IDENTITY

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or head < 0:
			return
		var hp := sk.get_bone_global_pose(head)
		var want := Quaternion.IDENTITY
		if target != null:
			var d: Vector3 = (target - hp.origin).normalized()
			var yaw_ := clampf(atan2(d.x, d.z), -1.1, 1.1)
			var pitch := clampf(asin(clampf(d.y, -1, 1)), -.45, .5)
			want = Quaternion(Vector3.UP, yaw_) * Quaternion(Vector3.RIGHT, -pitch)
		turn = turn.slerp(want, minf(1, delta * 6))
		var half := Quaternion.IDENTITY.slerp(turn, .35)
		if neck >= 0:
			var np_ := sk.get_bone_global_pose(neck)
			sk.set_bone_global_pose(neck, Transform3D(Basis(half) * np_.basis, np_.origin))
			hp = sk.get_bone_global_pose(head)
		sk.set_bone_global_pose(head, Transform3D(Basis(half.inverse() * turn) * hp.basis, hp.origin))


## How they hold themselves, over the clips (before the head turns to look): slumped (the back rounds, the head
## hangs, the shoulders drop), hunched (shoulders up, arms drawn in and hugged to the chest), shivering (a fast
## small tremble), or lifted (chest and chin up: happy). Turns in the skeleton's own space (it faces +z), so
## it works whatever the clip; the legs are left to the clips and the foot lock.
class Bearing extends SkeletonModifier3D:
	## Time spent posing, all of them together (µs, for the frame-cost numbers)
	static var us := 0
	var low := -1
	var spine := -1
	var neck := -1
	var head := -1
	var shoulder := [-1, -1]
	var arm := [-1, -1]
	var fore := [-1, -1]
	var slump := 0.0
	var hunch := 0.0
	var shiver := 0.0
	var lift := 0.0
	var t := 0.0

	func setup(sk: Skeleton3D) -> void:
		low = sk.find_bone("DEF-spine.001")
		spine = sk.find_bone("DEF-spine.002")
		neck = sk.find_bone("DEF-neck")
		head = sk.find_bone("DEF-head")
		for i in 2:
			var s: String = ["L", "R"][i]
			shoulder[i] = sk.find_bone("DEF-shoulder." + s)
			arm[i] = sk.find_bone("DEF-upper_arm." + s)
			fore[i] = sk.find_bone("DEF-forearm." + s)

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or (slump + hunch + shiver + lift) < .005:
			return
		var t0 := Time.get_ticks_usec()
		t += delta
		# About 15 and 11 times a second, so it never quite repeats
		var tr := (sin(t * 94.0) * .6 + sin(t * 69.0) * .4) * shiver
		_turn(sk, low, Vector3.RIGHT, .14 * slump + .06 * hunch - .05 * lift)
		_turn(sk, spine, Vector3.RIGHT, .3 * slump + .16 * hunch - .08 * lift)
		_turn(sk, spine, Vector3.BACK, .03 * tr)
		_turn(sk, neck, Vector3.RIGHT, .2 * slump + .1 * hunch - .06 * lift)
		_turn(sk, head, Vector3.RIGHT, .3 * slump - .12 * lift + .03 * tr)
		for i in 2:
			var side := 1.0 if i == 0 else -1.0
			# The shoulders go up (or droop); the arms keep hanging, drawn in and forward to hug themselves
			var up := side * (.42 * hunch - .12 * slump + .05 * tr)
			_turn(sk, shoulder[i], Vector3.BACK, up)
			_turn(sk, arm[i], Vector3.BACK, -up - side * .3 * hunch)
			_turn(sk, arm[i], Vector3.RIGHT, -.5 * hunch + .1 * slump)
			_turn(sk, fore[i], Vector3.RIGHT, -1.1 * hunch)
			_turn(sk, fore[i], Vector3.UP, -side * .5 * hunch)
		us += Time.get_ticks_usec() - t0

	static func _turn(sk: Skeleton3D, b: int, axis: Vector3, a: float) -> void:
		if b < 0 or absf(a) < 1e-4:
			return
		var g := sk.get_bone_global_pose(b)
		sk.set_bone_global_pose(b, Transform3D(Basis(Quaternion(axis, a)) * g.basis, g.origin))


## Where the face is on each model, as the mesh was made (x across, y up, z out of the face): the middle of the
## mouth and its half width, the brows (one side; the other mirrors it), how far out the face is in the middle
## (at the mouth, and at the brows) and how fast it curves back to the sides; the brows' colour, and how far
## their fringe hangs out in front of them (the brows show over it).
const FACE := {
	mo = {mouth = Vector2(0, 1.105), half = .0115, brow = Vector2(.038, 1.181), z0 = .099, z1 = .114, curve = 4.0,
		brow_out = .003, brow_color = Color(.36, .12, .06), pull = .05},
	bo = {mouth = Vector2(0, 1.215), half = .011, brow = Vector2(.036, 1.279), z0 = .087, z1 = .107, curve = 4.0,
		brow_out = .003, brow_color = Color(.09, .07, .07), pull = .04},
}
## Brows: how high (m), how tilted (inner end up, as a slope) and how arched; the mouth: how much the corners
## rise (m), how wide (a share), and how open
const BROWS := {neutral = [0.0, 0.0, .002], happy = [.004, -.05, .004], sad = [.002, .3, 0.0], worried = [.004, .4, .001],
	cross = [-.004, -.45, 0.0], scared = [.008, .2, .003]}
const MOUTHS := {smile = [.0045, 1.0, 0.0], grin = [.004, 1.15, .007], flat = [0.0, .8, 0.0], frown = [-.005, .9, 0.0], o = [0.0, .5, 0.0]}


## A little face over the painted one, riding on the head: two brows and a mouth, drawn as thin dark shapes
## that are made again when the look changes.
func _make_face(mesh: MeshInstance3D) -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = "DEF-head"
	skel.add_child(at)
	# From the mesh as made to the head bone: the skin's bind pose for it
	var bind := Transform3D()
	var skin_: Skin = mesh.skin
	var hb := skel.find_bone("DEF-head")
	if skin_:
		for i in skin_.get_bind_count():
			if skin_.get_bind_name(i) == &"DEF-head" or skin_.get_bind_bone(i) == hb:
				bind = skin_.get_bind_pose(i)
				break
	var F: Dictionary = FACE[model_id]
	var brow_ink := ShaderMaterial.new()
	brow_ink.shader = INK
	brow_ink.set_shader_parameter("color", Color(Folk.BODY[id].brow) if folk else F.brow_color)
	brow_ink.set_shader_parameter("pull", F.pull)
	var lip_ink := ShaderMaterial.new()
	lip_ink.shader = INK
	lip_ink.set_shader_parameter("color", Color(.32, .1, .08))
	lip_ink.set_shader_parameter("pull", .008)
	mug = {at = at, bind = bind, F = F, brows = []}
	for i in 2:
		mug.brows.append(_ink_mesh(at, brow_ink))
	mug.mouth = _ink_mesh(at, lip_ink)
	_show_face("neutral", "flat")


func _ink_mesh(at: Node3D, ink: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.material_override = ink
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	at.add_child(m)
	return m


## A point on the face (as the mesh was made), out from it by `out`, in the head bone's space.
func _on_face(x: float, y: float, out := .002) -> Vector3:
	var F: Dictionary = mug.F
	var k := clampf((y - F.mouth.y) / (F.brow.y - F.mouth.y), -.5, 1.5)
	var z: float = lerpf(F.z0, F.z1, k) - F.curve * x * x + out
	return mug.bind * Vector3(x, y, z)


## A filled shape between two curves across (top and bottom, from u = -1 to 1).
func _band(top: Callable, bottom: Callable, out := .002) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := 10
	for i in n:
		var u0 := -1.0 + 2.0 * i / n
		var u1 := -1.0 + 2.0 * (i + 1) / n
		var a: Vector2 = top.call(u0)
		var b: Vector2 = top.call(u1)
		var c: Vector2 = bottom.call(u0)
		var d: Vector2 = bottom.call(u1)
		var A := _on_face(a.x, a.y, out)
		var B := _on_face(b.x, b.y, out)
		var C := _on_face(c.x, c.y, out)
		var D := _on_face(d.x, d.y, out)
		v.append_array([A, B, C, B, D, C])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Brows and mouth for these shapes (Looks names).
func _show_face(brows: String, mouth: String) -> void:
	mug.shape = brows + "|" + mouth
	var F: Dictionary = mug.F
	if mug.get("brows_now", "") != brows:
		mug.brows_now = brows
		_draw_brows(brows)
	if mug.get("mouth_now", "") != mouth:
		mug.mouth_now = mouth
		_draw_mouth(mouth)


func _draw_brows(brows: String) -> void:
	var F: Dictionary = mug.F
	var bw: Array = BROWS[brows]
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var cx: float = side * F.brow.x
		var cy: float = F.brow.y + bw[0]
		var h := .013
		# u from -1 to 1 across; the inner end is the one nearer the middle
		var line := func(u: float, dy: float) -> Vector2:
			var inner := -u * side
			return Vector2(cx + u * h, cy + inner * h * bw[1] + bw[2] * (1.0 - u * u) + dy * (1.0 - .45 * maxf(0.0, -inner)))
		mug.brows[i].mesh = _band(func(u): return line.call(u, .0028), func(u): return line.call(u, -.0028), F.brow_out)


func _draw_mouth(mouth: String) -> void:
	var F: Dictionary = mug.F
	var mw: Array = MOUTHS[mouth]
	var half: float = F.half * mw[1]
	var my: float = F.mouth.y
	var top: Callable
	var bottom: Callable
	if mouth == "o":
		top = func(u): return Vector2(u * half, my + .0065 * sqrt(maxf(0.0, 1.0 - u * u)) + .0006)
		bottom = func(u): return Vector2(u * half, my - .0065 * sqrt(maxf(0.0, 1.0 - u * u)) - .0006)
	else:
		var t := .0021
		top = func(u): return Vector2(u * half, my + mw[0] * u * u + t * (1.0 - .5 * u * u))
		bottom = func(u): return Vector2(u * half, my + mw[0] * u * u - t * (1.0 - .5 * u * u) - mw[2] * (1.0 - u * u))
	mug.mouth.mesh = _band(top, bottom)


## Where to look at someone: their face.
static func face_of(n: Node3D) -> Vector3:
	return n.eye_world() if n is Pal else n.global_position + Vector3(0, 1.25, 0)


## Just said something that wasn't so: for a few seconds the eyes slide off whoever heard it, dart back, and
## slide off again, and a blink comes quick.
func shifty(s := 3.5) -> void:
	nervous = s
	blink = minf(blink, .2)
	glance_n = 0
	glance_t = .4


## What body language makes of where the eyes go (gp: where they'd look anyway).
func _mood_gaze(dt: float, gp):
	glance_t -= dt
	var wp = face_of(with_node) if with_node != null and is_instance_valid(with_node) else null
	var fear_glance: float = feel.get("glance", 0.0)
	# Something to hide, or a grudge: eyes off them, with a quick look back now and then (quicker when it's a fib)
	if feel.get("away", false) and wp != null:
		if glance_t <= 0:
			glance_n += 1
			var b := glance_n % 3 == 2
			glance_t = (.3 if b else .7) if nervous > 0 else (.8 if b else 2.4)
		return wp if glance_n % 3 == 2 else _aside(wp, glance_n)
	# Scared: looking all about, now one way, now the other (at no set times, but the same every run)
	if fear_glance > 0:
		if glance_t <= 0:
			glance_n += 1
			glance_len = (.5 + Skills.roll("%s|look|%d" % [id, glance_n])) / fear_glance
			glance_t = glance_len
		if glance_n % 2 == 1 and glance_t > glance_len - .5:
			var r := Skills.roll("%s|way|%d" % [id, glance_n])
			var a := yaw + (1.0 if r > .5 else -1.0) * lerpf(.6, 1.1, absf(r - .5) * 2.0)
			var e := eye_world()
			return e + Vector3(sin(a), -.15 + .3 * Skills.roll("%s|up|%d" % [id, glance_n]), cos(a)) * 4.0
	# Talking with someone: at them (when they're who's talking, or being talked to)
	if wp != null and (talk or (with_node is Pal and with_node.talk) or (with_node == game.kid and game.kid.talk)):
		return wp
	# Nothing much going on: now and then, a look toward what's on their mind (where they're off to, what they
	# mean to do), unless they've been told to look somewhere
	if think_at is Vector3 and not talk and _gaze_free() and fmod(since + (0.0 if id == "mo" else 3.5 if id == "bo" else 1.7 * layer_bit), 7.0) < 2.5:
		return Vector3(think_at.x, eye_world().y, think_at.z)
	# With someone, and not told to look anywhere: at them
	if wp != null and _gaze_free():
		return wp
	return gp


## Not told to look anywhere in particular (only at the light, by default).
func _gaze_free() -> bool:
	return gaze == null or (gaze is Object and gaze == game.wisp)


## A point off to one side of p and down a little (alternating sides), as eyes avoiding someone go.
func _aside(p: Vector3, n: int) -> Vector3:
	var e := eye_world()
	var to := p - e
	var a := atan2(to.x, to.z) + (.75 if n % 2 == 0 else -.75)
	return e + Vector3(sin(a), -.35, cos(a)) * maxf(1.5, Vector2(to.x, to.z).length())


## Ease what shows toward how they feel, and pose the body for it (once a frame).
func _express(dt: float) -> void:
	since += dt
	nervous = maxf(0.0, nervous - dt)
	var on := expressive and not feel.is_empty() and lying < .5
	var k := minf(1.0, dt * 2.5)
	for key in shown:
		var want: float = feel.get(key, 1.0 if key == "walk" else 0.0) if on else (1.0 if key == "walk" else 0.0)
		shown[key] = lerpf(shown[key], want, k)
	bearing.slump = shown.slump
	bearing.hunch = shown.hunch
	bearing.shiver = shown.shiver
	bearing.lift = shown.bounce * .6
	mug.at.visible = expressive and not far
	if not expressive:
		return
	var brows: String = feel.get("brows", "neutral") if on else "neutral"
	var mouth: String = feel.get("mouth", "flat") if on else "flat"
	mutter = maxf(0.0, mutter - dt)
	if talk or mutter > 0:
		# Talking, the mouth goes: open, and back, a few times a second
		mouth = "o" if int(since * 8.0) % 2 == 0 else ("flat" if mouth == "o" else mouth)
	_show_face(brows, mouth)


## A place at someone's side, behind them a little.
func _beside(who: Node3D) -> Vector2:
	var b: Vector3 = who.position
	var f := Vector3(sin(who.rotation.y), 0, cos(who.rotation.y))
	var side := -1.0 if id in ["mo", "nell", "odo"] else 1.0
	return Vector2(b.x - f.x * .7 - f.z * side * .7, b.z - f.z * .7 + f.x * side * .7)


## Far from you, or near again: far away nobody can see the pose layers, the face, or the clips at full rate.
func set_far(on: bool) -> void:
	if on == far:
		return
	far = on
	gait.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if on else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	for mod in [gait.lock, bearing, looker]:
		mod.active = not on
	mug.at.visible = expressive and not on


## Toward the pace they want, eased in, and slowing so as to stop where they're going (`left` away).
func _ease(now: float, want: float, left: float, dt: float) -> float:
	want = maxf(minf(want, sqrt(2 * DECEL * maxf(left, 0))), .3)
	return move_toward(now, want, (ACCEL if want > now else DECEL * 1.5) * dt)


func head() -> Vector3:
	return to_global(Vector3(0, cy * 2 + .5 + inner.position.y, 0))


func gaze_point():
	if gaze is Node3D:
		return gaze.global_position
	return gaze


func update(dt: float, _t: float) -> void:
	var pos := position
	var moving := false
	var room := spot_inside()
	if inside != "":
		inner.visible = not room.is_empty()
	lift = room.get("lift", 0.0)
	if not room.is_empty():
		# Indoors, in the room: in bed or at the table
		pos.x = room.at.x
		pos.z = room.at.z
		t_yaw = room.yaw
	elif path != null:
		var to: Vector3 = path[0]
		var dx := to.x - pos.x
		var dz := to.z - pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > .001:
			t_yaw = atan2(dx, dz)
		var left := d
		for i in range(1, path.size()):
			left += path[i - 1].distance_to(path[i])
		pace = _ease(pace, speed * shown.walk, left, dt)
		var step := pace * dt
		if d <= step:
			pos.x = to.x
			pos.z = to.z
			path.pop_front()
			if path.is_empty():
				position = pos
				stop()
		else:
			pos.x += dx / d * step
			pos.z += dz / d * step
		moving = true
	elif mode == "follow":
		var s: Vector2 = game.slot(self) if follow_who == null or follow_who == game.wisp else _beside(follow_who)
		var dx := s.x - pos.x
		var dz := s.y - pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > .62:
			going = true
		elif d < .22:
			going = false
		if going:
			pace = _ease(pace, min(3.6, .9 + d * 1.6) * shown.walk, d - .22, dt)
			var step: float = min(d, pace * dt)
			pos.x += dx / d * step
			pos.z += dz / d * step
			t_yaw = atan2(dx, dz)
			moving = true
		else:
			face(look if look_t > 0 else game.wisp_g)
	elif mode == "stay":
		# Staying put, looking where they were looking (unless something catches their eye)
		if look_t > 0:
			face(look)
	elif mode == "free" and look_t > 0:
		# Off on their own (mind.gd turns them); a sudden sight still turns their head
		face(look)
	if look_t > 0:
		look_t -= dt
		if look_t <= 0:
			gaze = game.wisp
	if not moving:
		pace = 0
	bump_t = maxf(0.0, bump_t - dt)
	if mode != "stay" and game.level and (moving or pos != position) and room.is_empty():
		var want := pos
		pos = game.level.collide(pos, .34, false)
		# Pushed back more than half the step: walked into something
		var step := Vector2(want.x - position.x, want.z - position.z)
		var got := Vector2(pos.x - position.x, pos.z - position.z)
		if moving and step.length() > .002 and got.dot(step.normalized()) < step.length() * .5 and bump_t <= 0:
			bump_t = 2.5
			bumped.emit("thing", game.level.touch_at(want, .34))
	if moving and bump_t <= 0 and game.level:
		# Walked into someone
		for n in game.people() + [game.kid]:
			if n != self and n.visible and (n == game.kid or n.inside == "") and Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length() < .5:
				bump_t = 2.5
				bumped.emit("person", n)
				break
	var v := pos.distance_to(position) / dt if dt > 0 else 0.0
	position = pos
	recoil = max(0, recoil - dt)
	var dy := t_yaw - yaw
	dy = atan2(sin(dy), cos(dy))
	var was_yaw := yaw
	yaw += dy * min(1, dt * 7)
	rotation.y = yaw
	if jump > 0 or jv > 0:
		jv -= 13 * dt
		jump += jv * dt
		if jump <= 0:
			jump = 0
			jv = 0
			sq = 1
	sq *= exp(-dt * 7)
	_express(dt)
	# A spring in the step: up on every footfall when going, a little bob standing
	var spring := 0.0
	if shown.bounce > .01:
		spring = shown.bounce * (.05 * absf(sin(gait.phase * TAU)) if moving else .018 * (.5 + .5 * sin(since * TAU * 1.7)))
	inner.position.y = jump + spring
	inner.rotation = gait.tilt(dt, v, (yaw - was_yaw) / dt if dt > 0 else 0.0)
	# Lying down on their back, and getting up again
	lying = move_toward(lying, 1.0 if lie or lift > 0 else 0.0, dt / .9)
	if lying > 0:
		var k := Game.ease_io(lying)
		inner.rotation = inner.rotation.lerp(Vector3(-PI / 2, 0, 0), k)
		inner.position.y += .14 * k
	# The body's clips (gait.gd). A gesture plays once while standing: wave on being chosen, point at
	# what they've spotted, pick up when crouching for something, jump on a bounce. Otherwise walk, jog
	# or run while going (at the pace of their feet), talk while talking, or idle.
	var active: bool = game.active == self
	if active and not was_active:
		_gesture("wave")
	was_active = active
	if look_t > was_look + .5:
		_gesture("point")
	was_look = look_t
	if crouch > 0 and was_crouch <= 0:
		_gesture("pick_up")
	was_crouch = crouch
	if gesture_new:
		gesture_new = false
		if moving and gesture != "jump":
			gesture = ""
		else:
			gait.play(gesture, ONCE[gesture])
	elif moving and gait.playing() not in ["", "jump"]:
		gait.cancel()
	gait.airborne = jump > 0
	gait.update(dt, v, talk)
	gesture = gait.playing()
	# Blink now and then, or keep the eyes shut
	blink -= dt
	if closed and not shut:
		shut = true
		eye_anim.play("blink")
		eye_anim.seek(eye_anim.current_animation_length * .5, true)
		eye_anim.pause()
	elif not closed and shut:
		shut = false
		lids_at = -1.0
		eye_anim.play("blink")
		eye_anim.seek(eye_anim.current_animation_length * .5, true)
	elif blink < 0 and not shut:
		eye_anim.play("blink")
		eye_anim.seek(eye_anim.current_animation_length * .5 * shown.lids, true)
		blink = 2.4 + Build.rnd() * 3
		lids_at = -1.0
	elif not shut and not eye_anim.is_playing() and absf(shown.lids - lids_at) > .01:
		# Between blinks, the lids where the mood has them (heavy when tired, narrowed when cross)
		lids_at = shown.lids
		eye_anim.play("blink")
		eye_anim.seek(eye_anim.current_animation_length * .5 * shown.lids, true)
		eye_anim.pause()
	# The head turns to what they're looking at (lying down, it rests)
	var gp = gaze_point() if lying < .5 else null
	eyes_on = _mood_gaze(dt, gp) if expressive and lying < .5 and look_t <= 0 and not feel.is_empty() else gp
	looker.target = skel.to_local(eyes_on) if eyes_on != null else null
	if far:
		gait.tree.advance(dt)
