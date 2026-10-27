class_name Gait
extends RefCounted
## How Mo, Bo and the kid move (art/pals): standing (idle, or talk), walk, jog and run blended by speed,
## each step clip played by the distance covered at its own stride, so the planted foot stays put; the
## gestures once over the top; leaning into turns, forward into a start and back into a stop.
## Every clip's time is set here each frame (TimeSeek), so the step clips stay in step with each other.
## What's left (a foot rolling heel to toe, blends, turns) FootLock takes up: a foot that's down stays
## where it landed, the leg bending to reach it.

## The step clips, slowest first. The jog and the run are made here from the library's run, which
## covers six hip heights a second in long bounds, a sprint: they swing the legs and arms only this much
## of the way, for a child's shorter, quicker strides.
const STEPS := ["walk", "jog", "run"]
const SWUNG := {jog = .35, run = .7}
## Limbs the jog and run swing less, and how much of that (the knees bend nearly as much, so the
## feet still clear the ground)
const SWING := {"DEF-thigh": 1.0, "DEF-shin": .5, "DEF-foot": 1.0, "DEF-toe": 1.0, "DEF-upper_arm": 1.0,
	"DEF-forearm": 1.0, "DEF-hand": 1.0}
## Fading a gesture in and out (s)
const FADE_IN := .12
const FADE_OUT := .2

var tree: AnimationTree
var skel: Skeleton3D
## Per step clip: ground speed at its own pace (m/s), length (s), distance a cycle covers (m), and where
## in its cycle the left foot lands (0..1)
var natural := {}
var length := {}
var stride := {}
var touch := {}
var stand_len := {}
var phase := 0.0
var t_idle := 0.0
var t_talk := 0.0
var talk_w := 0.0
var move_w := 0.0
var gesture := ""
var gesture_t := 0.0
var gesture_rate := 1.0
var gesture_w := 0.0
var gesture_len := 0.0
var lean := Vector2.ZERO
var last_v := 0.0
var lock: FootLock
## Off the ground (a jump): no foot is down
var airborne := false


## model: the instanced GLB; src: its AnimationPlayer; gestures: {clip: playback rate}; keep(bone):
## the bones this tree may move (the others are other players').
func _init(model: Node3D, src: AnimationPlayer, gestures: Dictionary, keep: Callable) -> void:
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var lib := AnimationLibrary.new()
	var clips := ["idle", "talk", "walk"] + gestures.keys()
	for c in clips:
		var a: Animation = src.get_animation(c).duplicate(true)
		for i in range(a.get_track_count() - 1, -1, -1):
			if not keep.call(str(a.track_get_path(i)).get_slice(":", 1)):
				a.remove_track(i)
		a.loop_mode = Animation.LOOP_NONE if gestures.has(c) else Animation.LOOP_LINEAR
		lib.add_animation(c, a)
	var run: Animation = src.get_animation("run").duplicate(true)
	for i in range(run.get_track_count() - 1, -1, -1):
		if not keep.call(str(run.track_get_path(i)).get_slice(":", 1)):
			run.remove_track(i)
	run.loop_mode = Animation.LOOP_LINEAR
	for c in SWUNG:
		lib.add_animation(c, _swing_less(run, SWUNG[c]))
	for c in STEPS:
		_measure(c, lib.get_animation(c))
	for c in ["idle", "talk"]:
		stand_len[c] = lib.get_animation(c).length
	for c in gestures:
		stand_len[c] = lib.get_animation(c).length

	var bt := AnimationNodeBlendTree.new()
	var x := 0
	for c in ["idle", "talk"] + STEPS + gestures.keys():
		var an := AnimationNodeAnimation.new()
		an.animation = c
		bt.add_node(c, an, Vector2(x, 0))
		var ts := AnimationNodeTimeSeek.new()
		bt.add_node(c + "_t", ts, Vector2(x, 100))
		bt.connect_node(c + "_t", 0, c)
		x += 200
	bt.add_node("stand", AnimationNodeBlend2.new())
	bt.connect_node("stand", 0, "idle_t")
	bt.connect_node("stand", 1, "talk_t")
	bt.add_node("wj", AnimationNodeBlend2.new())
	bt.connect_node("wj", 0, "walk_t")
	bt.connect_node("wj", 1, "jog_t")
	bt.add_node("jr", AnimationNodeBlend2.new())
	bt.connect_node("jr", 0, "wj")
	bt.connect_node("jr", 1, "run_t")
	bt.add_node("move", AnimationNodeBlend2.new())
	bt.connect_node("move", 0, "stand")
	bt.connect_node("move", 1, "jr")
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0
	for c in gestures:
		tr.add_input(c)
	bt.add_node("which", tr)
	var i := 0
	for c in gestures:
		bt.connect_node("which", i, c + "_t")
		i += 1
	bt.add_node("gest", AnimationNodeBlend2.new())
	bt.connect_node("gest", 0, "move")
	bt.connect_node("gest", 1, "which")
	bt.connect_node("output", 0, "gest")

	lock = FootLock.new()
	lock.setup(skel)
	skel.add_child(lock)

	tree = AnimationTree.new()
	tree.name = "Gait"
	model.add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.add_animation_library("", lib)
	tree.tree_root = bt
	tree.active = true


## Start a gesture (one of the gestures given at _init) at this playback rate.
func play(g: String, rate: float) -> void:
	gesture = g
	gesture_t = 0.0
	gesture_rate = rate
	gesture_len = stand_len[g]
	tree.set("parameters/which/transition_request", g)


func playing() -> String:
	return gesture


## Each frame: v the ground speed (m/s), talking or not. Returns nothing; poses the tree.
func update(dt: float, v: float, talking: bool) -> void:
	# Where between the step clips: walk at its own pace, the jog at its, the run at its
	var w_j := 0.0
	var w_r := 0.0
	var vw: float = natural.walk
	var vj: float = natural.jog
	var vr: float = natural.run
	if v > vw * 1.25:
		w_j = smoothstep(vw * 1.25, vj, v)
	if v > vj:
		w_r = smoothstep(vj, vr, v)
	var cyc: float = lerpf(lerpf(stride.walk, stride.jog, w_j), stride.run, w_r)
	phase = fmod(phase + v * dt / cyc, 1.0)
	for c in STEPS:
		tree.set("parameters/%s_t/seek_request" % c, fmod(touch[c] + phase, 1.0) * length[c])
	tree.set("parameters/wj/blend_amount", w_j)
	tree.set("parameters/jr/blend_amount", w_r)
	# Going at all: from standing to stepping by half the walk's pace (stopping, the legs stay where
	# they were and settle into standing)
	var want_move := smoothstep(.04, vw * .45, v)
	move_w = move_toward(move_w, want_move, dt * 5)
	tree.set("parameters/move/blend_amount", move_w)
	# Standing: idle, or talking
	t_idle = fmod(t_idle + dt, stand_len.idle)
	t_talk = fmod(t_talk + dt, stand_len.talk)
	talk_w = move_toward(talk_w, 1.0 if talking else 0.0, dt * 4)
	tree.set("parameters/idle_t/seek_request", t_idle)
	tree.set("parameters/talk_t/seek_request", t_talk)
	tree.set("parameters/stand/blend_amount", talk_w)
	# A gesture, once
	if gesture != "":
		gesture_t += dt * gesture_rate
		var left := gesture_len - gesture_t
		gesture_w = minf(1.0, gesture_t / (FADE_IN * gesture_rate)) if left > FADE_OUT * gesture_rate else maxf(0.0, left / (FADE_OUT * gesture_rate))
		tree.set("parameters/%s_t/seek_request" % gesture, minf(gesture_t, gesture_len))
		if left <= 0:
			gesture = ""
			gesture_w = 0.0
	tree.set("parameters/gest/blend_amount", gesture_w)
	# The feet stay put while going (standing turns move them as the clips do)
	lock.want = 0.0 if airborne else move_w * (1.0 - gesture_w)


## Stop the gesture (fading out from where it is).
func cancel() -> void:
	if gesture != "" and gesture_len - gesture_t > FADE_OUT * gesture_rate:
		gesture_t = gesture_len - FADE_OUT * gesture_rate * gesture_w


## The body's tilt (x: forward, z: to the side, radians) for a speed v and a turn rate (rad/s, + to the
## left): into the turn as a runner does (the turn's pull against gravity), forward into speeding up
## and back into slowing down. Smoothed.
func tilt(dt: float, v: float, turn: float) -> Vector3:
	var acc := (v - last_v) / dt if dt > 0 else 0.0
	last_v = v
	var side := clampf(atan(v * turn / 9.8) * .7, -.2, .2)
	var fwd := clampf(acc / 9.8 * .5, -.08, .1) + clampf(v * .012, 0, .04)
	var k := 1 - exp(-dt * 6)
	lean = lean.lerp(Vector2(fwd, side), k)
	return Vector3(lean.x, 0, -lean.y)


## The run, its limbs swinging only `amount` of the way about their middle, the hips moved so that the
## foot that's down in the run stays where it was (and the bounds between steps are as much lower).
func _swing_less(run: Animation, amount: float) -> Animation:
	var a: Animation = run.duplicate(true)
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(a.track_get_path(i)).get_slice(":", 1)
		if not SWING.has(bone.get_slice(".", 0)):
			continue
		var k_: float = pow(amount, SWING[bone.get_slice(".", 0)])
		var n := a.track_get_key_count(i)
		var sum := Vector4.ZERO
		var first: Quaternion = a.track_get_key_value(i, 0)
		for k in n:
			var q: Quaternion = a.track_get_key_value(i, k)
			if q.dot(first) < 0:
				q = -q
			sum += Vector4(q.x, q.y, q.z, q.w)
		sum = sum.normalized()
		var mid := Quaternion(sum.x, sum.y, sum.z, sum.w)
		for k in n:
			var q: Quaternion = a.track_get_key_value(i, k)
			a.track_set_key_value(i, k, mid.slerp(q, k_))
	var hips := _track(a, "DEF-hips", Animation.TYPE_POSITION_3D)
	if hips >= 0:
		var toes := [skel.find_bone("DEF-toe.L"), skel.find_bone("DEF-toe.R")]
		for k in a.track_get_key_count(hips):
			var t := a.track_get_key_time(hips, k)
			var was := toes.map(func(f): return _fk(run, t, f).origin.y)
			var down: int = toes[0] if was[0] < was[1] else toes[1]
			var p: Vector3 = a.track_get_key_value(hips, k)
			# (the hips' track is in their parent's space: the root bone stands the skeleton up)
			var up := _fk(a, t, skel.get_bone_parent(skel.find_bone("DEF-hips"))).basis.inverse()
			var want: float = minf(was[0], was[1])
			if want > 0:
				want *= amount
			a.track_set_key_value(hips, k, p + up * Vector3(0, want - _fk(a, t, down).origin.y, 0))
	return a


## Someone bigger (scale k, the model grown): each step covers that much more ground.
func grow(k: float) -> void:
	for c in stride:
		stride[c] *= k
		natural[c] *= k


## A step clip's pace: how fast the foot that bears the body goes back (the lower toe, while it's on the
## ground: within 1.5 cm of the lowest either gets); and where the left one lands (when it's furthest
## forward).
func _measure(c: String, a: Animation) -> void:
	var N := 120
	var dt := a.length / N
	var ys := [[], []]
	var zs := [[], []]
	for s in 2:
		var toe := skel.find_bone("DEF-toe." + ("L" if s == 0 else "R"))
		for i in N:
			var o := _fk(a, i * dt, toe).origin
			ys[s].append(o.y)
			zs[s].append(o.z)
	var low: float = minf(ys[0].min(), ys[1].min()) + .015
	var speeds := []
	touch[c] = float(zs[0].find(zs[0].max())) / N
	for i in N:
		var j := (i + 1) % N
		var s := 0 if ys[0][i] < ys[1][i] else 1
		if ys[s][i] < low and ys[s][j] < low and (ys[0][j] < ys[1][j]) == (s == 0):
			speeds.append((zs[s][i] - zs[s][j]) / dt)
	speeds.sort()
	natural[c] = speeds[speeds.size() / 2] if speeds.size() > 0 else 1.0
	length[c] = a.length
	stride[c] = natural[c] * a.length


## A bone's transform in the skeleton's space at time t of the clip (from its tracks, the rest where
## it has none).
func _fk(a: Animation, t: float, bone: int) -> Transform3D:
	var g := Transform3D()
	var b := bone
	while b >= 0:
		var rest := skel.get_bone_rest(b)
		var p := rest.origin
		var q := rest.basis.get_rotation_quaternion()
		var name := skel.get_bone_name(b)
		var k := _track(a, name, Animation.TYPE_POSITION_3D)
		if k >= 0:
			p = a.position_track_interpolate(k, t)
		k = _track(a, name, Animation.TYPE_ROTATION_3D)
		if k >= 0:
			q = a.rotation_track_interpolate(k, t)
		g = Transform3D(Basis(q), p) * g
		b = skel.get_bone_parent(b)
	return g


static func _track(a: Animation, bone: String, type: int) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == type and str(a.track_get_path(i)).get_slice(":", 1) == bone:
			return i
	return -1


## Keeps a foot that's down where it landed: while the ball of the foot is on the ground (in the pose the
## clips give), it's held at the place it first touched, and not below the ground; the thigh and shin
## turn to reach it (two-bone IK, the knee bending the way the clip has it, the foot turned as the clip
## has it). Lifting, what it was moved by eases off in the air.
class FootLock extends SkeletonModifier3D:
	## How much to hold the feet (0..1), from Gait: while going
	var want := 0.0
	var legs := []

	func setup(sk: Skeleton3D) -> void:
		for side in ["L", "R"]:
			legs.append({thigh = sk.find_bone("DEF-thigh." + side), shin = sk.find_bone("DEF-shin." + side),
				foot = sk.find_bone("DEF-foot." + side), toe = sk.find_bone("DEF-toe." + side),
				at = Vector3.INF, off = Vector3.ZERO})

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var to_world := sk.global_transform
		var to_skel := to_world.affine_inverse()
		for L in legs:
			var hip := sk.get_bone_global_pose(L.thigh)
			var knee := sk.get_bone_global_pose(L.shin)
			var ankle := sk.get_bone_global_pose(L.foot)
			var toe := sk.get_bone_global_pose(L.toe)
			var down: bool = want > .05 and toe.origin.y < .03 and ankle.origin.y < .16
			if down:
				if L.at == Vector3.INF:
					L.at = to_world * toe.origin
				var held: Vector3 = to_skel * L.at
				var off := Vector3(held.x - toe.origin.x, maxf(0.0, -toe.origin.y), held.z - toe.origin.z)
				if Vector2(off.x, off.z).length() > .4:
					# (too far behind to reach: put it down again here)
					L.at = to_world * toe.origin
					off = Vector3(0, off.y, 0)
				L.off = off
			else:
				L.at = Vector3.INF
				L.off *= exp(-delta / .07)
			var by: Vector3 = L.off * minf(1.0, want * 1.5)
			if by.length() < 1e-4:
				continue
			_reach(sk, L, hip, knee, ankle, ankle.origin + by)

	## Turn the thigh and the shin so the ankle reaches goal, the knee in the plane the clip bends it in.
	func _reach(sk: Skeleton3D, L: Dictionary, hip: Transform3D, knee: Transform3D, ankle: Transform3D, goal: Vector3) -> void:
		var a := hip.origin.distance_to(knee.origin)
		var b := knee.origin.distance_to(ankle.origin)
		var to := goal - hip.origin
		var d := clampf(to.length(), absf(a - b) + .001, a + b - .001)
		var dir := to.normalized()
		# The bend's side: where the clip has the knee, off the hip-to-goal line
		var pole := (knee.origin - hip.origin)
		pole = (pole - dir * pole.dot(dir))
		if pole.length() < 1e-4:
			pole = hip.basis.z
		pole = pole.normalized()
		var cos_a := clampf((a * a + d * d - b * b) / (2 * a * d), -1, 1)
		var new_knee := hip.origin + dir * (a * cos_a) + pole * (a * sqrt(1 - cos_a * cos_a))
		var new_ankle := hip.origin + dir * d
		var t1 := Quaternion((knee.origin - hip.origin).normalized(), (new_knee - hip.origin).normalized())
		sk.set_bone_global_pose(L.thigh, Transform3D(Basis(t1) * hip.basis, hip.origin))
		var k2 := sk.get_bone_global_pose(L.shin)
		var t2 := Quaternion((ankle.origin - knee.origin).normalized(), (new_ankle - new_knee).normalized())
		sk.set_bone_global_pose(L.shin, Transform3D(Basis(t2) * knee.basis, k2.origin))
		# The foot keeps the clip's turn
		sk.set_bone_global_pose(L.foot, Transform3D(ankle.basis, sk.get_bone_global_pose(L.foot).origin))
