extends Node
## Body language in the real game, with no model: how Mo and Bo feel shows in how they stand, walk, look and
## what their faces do, and the other one sees it in their own pictures.
##   godot --path . -- --autoplay --autoplay-script=res://tools/body_language_test.gd --offline [--shots=dir]
## Each state is set in their body and heart (as the day would leave them), and measured on the posed skeleton:
## slumped and slow when worn out, hunched and shivering when freezing, hunched and glancing about when scared,
## bouncy and quick when happy, heavy or narrowed eyelids, a face for each; eyes on whoever's talking with
## them, a look now and then toward what's on their mind, eyes sliding off the one they've just bluffed to (with
## a quick look back), and away from someone they're sore at; Bo slumped or bouncing as Mo's eyes see him. Then
## what it costs a frame, with it all on and off. Prints ok:/FAIL:, exits non-zero on a failure.

const StandIn := preload("res://tools/standin.gd")

var game: Game
var args: Array = []
var shots := ""
var failed := false
var standin
var mo: Pal
var bo: Pal
var m: Mind
var b: Mind
## Bones followed to measure the pose: {pal: {head, arm_l, arm_r, hand_l, hand_r}}
var marks := {}
## The state each one is held in: [body {…}, heart {v, a}]
var hold := {}
## Just these sections (--only=stances,faces), to look again at one thing
var only := []

## The states: body (tired, cold, fear, bored), heart (v, a), and the face they should make
const STATES := {
	neutral = [[.1, 0.0, 0.0, .2], [.05, .4], "neutral|flat"],
	tired = [[.92, 0.0, 0.0, .2], [.05, .3], "neutral|flat"],
	cold = [[.1, .85, 0.0, .2], [0.0, .4], "worried|flat"],
	scared = [[.1, 0.0, .85, .2], [-.1, .8], "scared|o"],
	happy = [[.1, 0.0, 0.0, .1], [.85, .75], "happy|grin"],
	sad = [[.2, 0.0, 0.0, .3], [-.5, .3], "sad|frown"],
	cross = [[.1, 0.0, 0.0, .2], [-.65, .8], "cross|frown"],
}


func _ready() -> void:
	for a in args:
		if a.begins_with("--shots="):
			shots = a.substr(8)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	if game.minds.on:
		note("FAIL: the minds are on; run with --offline (this test must not call the model)")
		get_tree().quit(2)
		return
	mo = game.mo
	bo = game.bo
	m = game.minds.mo
	b = game.minds.bo
	for x in [m, b]:
		if not x.file.contains("/offline/"):
			note("FAIL: the minds' memories aren't the test's own (%s)" % x.file)
			get_tree().quit(2)
			return
		x.forget_all()
	standin = StandIn.new(game)
	game.minds.quiet = true
	game.minds.ears.muted = true
	game.controls = false
	game.clock.stopped = true
	game.clock.set_hour(11)
	for p in [mo, bo]:
		marks[p] = {}
		var bones := {head = "DEF-head", arm_l = "DEF-upper_arm.L", arm_r = "DEF-upper_arm.R", hand_l = "DEF-hand.L", hand_r = "DEF-hand.R"}
		for k in bones:
			var at := BoneAttachment3D.new()
			at.bone_name = bones[k]
			p.skel.add_child(at)
			marks[p][k] = at
	await game.wait(.5)
	for s in ["stances", "walking", "faces", "glancing", "eyes_on_them", "on_her_mind", "a_bluff", "a_grudge", "in_her_eyes", "cost"]:
		if only.is_empty() or only.has(s):
			await call("_" + s)
	note("FAILED" if failed else "DONE: body language")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[body language %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


func check(ok: bool, what: String) -> void:
	note(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func put(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	var mind: Mind = game.minds.of(p)
	mind.task = {}
	mind.body.asleep = false
	p.closed = false
	p.go_out()
	p.stop()
	p.position = Vector3(x, game.level.ground(x, z), z)
	p.mode = "script"
	p.gaze = null
	p.talk = false
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)
	game.kid.position = game.wisp_g


## Hold them in a state (set again every frame, so the day doesn't move it on while we look).
func be(p: Pal, state: String) -> void:
	hold[p] = STATES[state]
	_keep(p)


func _keep(p: Pal) -> void:
	var s: Array = hold[p]
	var x: Mind = game.minds.of(p)
	x.body.tired = s[0][0]
	x.body.cold = s[0][1]
	x.body.fear = s[0][2]
	x.body.bored = s[0][3]
	x.body.hunger = .1
	x.heart.v = s[1][0]
	x.heart.a = s[1][1]


func _process(_dt: float) -> void:
	for p in hold:
		_keep(p)


## Wait while holding the states.
func wait(s: float) -> void:
	await game.wait(s)


## The camera in front of p, all of them in view (the picture cut down to them).
func frame(p: Pal) -> void:
	game.az = p.yaw + .3
	game.az_goal = null
	game.pol = 1.45
	var h: float = p.eye_world().y - p.position.y
	game.cam_focus = {p = p.position + Vector3(0, h * .55, 0), dist = 1.9}
	game.aim(0.0, true)
	await game.wait(.05)


## The screen as it is, cut to a box round a point (width and height as shares of the screen's height).
func cut(name: String, at: Vector3, w: float, h: float, out_w := 640) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var c: Vector2 = game.to_screen(at)
	var k: float = float(img.get_height()) / get_viewport().get_visible_rect().size.y
	var W := int(img.get_height() * w)
	var H := int(img.get_height() * h)
	var r := Rect2i(int(c.x * k) - W / 2, int(c.y * k) - H / 2, W, H).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.resize(out_w, out_w * r.size.y / maxi(1, r.size.x), Image.INTERPOLATE_LANCZOS)
	crop.save_png(shots.path_join(name + ".png"))


## Mo and Bo side by side (standing as together() puts them), from in front, cut to their heads and shoulders.
func pair_shot(name: String) -> void:
	var mid := (Pal.face_of(mo) + Pal.face_of(bo)) / 2.0
	game.az = 0.0
	game.az_goal = null
	game.pol = 1.55
	game.cam_focus = {p = mid + Vector3(0, -.15, 0), dist = 2.0}
	game.aim(0.0, true)
	await get_tree().process_frame
	game.aim(0.0, true)
	await cut(name, mid + Vector3(0, -.12, 0), 2.0, .7, 900)


## A close look at p's face: the camera near, in front of the face (whichever way the head's turned), a little
## below it, and the picture cut down to the head.
func face_shot(p: Pal, name: String) -> void:
	var at: Node3D = p.mug.at
	var c0: Vector3 = at.global_transform * (p.mug.bind * Vector3(0, p.mug.F.mouth.y + .03, .05))
	var c1: Vector3 = at.global_transform * (p.mug.bind * Vector3(0, p.mug.F.mouth.y + .03, .15))
	var fwd := (c1 - c0).normalized()
	game.az = atan2(fwd.x, fwd.z)
	game.az_goal = null
	game.pol = clampf(acos(fwd.y), 1.6, 2.3)
	game.cam_focus = {p = c0, dist = .5}
	game.aim(0.0, true)
	await get_tree().process_frame
	game.aim(0.0, true)
	await cut(name, c0, .7, .7, 480)


## The pose now, in p's own space: where the head and arms are, and which way the head points.
func pose(p: Pal) -> Dictionary:
	var M: Dictionary = marks[p]
	var to := func(n: Node3D) -> Vector3: return p.to_local(n.global_position)
	var hd: Node3D = M.head
	var fwd: Vector3 = p.global_transform.basis.inverse() * (hd.global_transform.basis * Vector3(0, 0, 1)).normalized()
	return {head = to.call(M.head), fwd = fwd, arm_l = to.call(M.arm_l), arm_r = to.call(M.arm_r),
		hands = (to.call(M.hand_l) - to.call(M.hand_r)).length(), hand_z = (to.call(M.hand_l).z + to.call(M.hand_r).z) / 2.0}


## Over a second: the pose on average, how much it trembles frame to frame, and how far they bob up and down.
func watch(p: Pal, secs := 1.0) -> Dictionary:
	var n := 0
	var sum := {}
	var jitter := 0.0
	var lo := 1e9
	var hi := -1e9
	var was = null
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		var q := pose(p)
		for k in q:
			sum[k] = sum.get(k, Vector3.ZERO if q[k] is Vector3 else 0.0) + q[k]
		if was != null:
			jitter += (q.head - was.head).length() + (q.arm_l - was.arm_l).length()
		was = q
		lo = minf(lo, p.inner.position.y)
		hi = maxf(hi, p.inner.position.y)
		n += 1
	var out := {}
	for k in sum:
		out[k] = sum[k] / n
	out.jitter = jitter / maxf(1, n - 1)
	out.bob = hi - lo
	out.lids = p.eye_anim.current_animation_position / (p.eye_anim.current_animation_length * .5) if p.eye_anim.assigned_animation == "blink" else 0.0
	out.face = p.mug.get("shape", "")
	return out


# ---------- Standing ----------

func _stances() -> void:
	put(mo, .5, 2.0, Vector3(.5, 0, 6.0))
	put(bo, 9.0, -6.0, Vector3(9.0, 0, 0.0))
	put_kid(-6.0, 9.0)
	var got := {}
	for st in ["neutral", "tired", "cold", "scared", "happy"]:
		be(mo, st)
		await wait(2.0)
		got[st] = await watch(mo, 1.2)
		await frame(mo)
		await wait(.4)
		await cut("mo_%s" % st, mo.position + Vector3(0, (mo.eye_world().y - mo.position.y) * .55, 0), .75, .9, 520)
		await face_shot(mo, "mo_%s_face" % st)
		note("  %s: head %s, pointing %s, upper arm %s, hands %.2f apart, jitter %.4f, bob %.3f, lids %.2f, face %s" % [st,
			got[st].head.snapped(Vector3.ONE * .001), got[st].fwd.snapped(Vector3.ONE * .01), got[st].arm_l.snapped(Vector3.ONE * .001),
			got[st].hands, got[st].jitter, got[st].bob, got[st].lids, got[st].face])

	var N: Dictionary = got.neutral
	var T: Dictionary = got.tired
	check(T.head.y < N.head.y - .015 and T.head.z > N.head.z + .04 and T.fwd.y < N.fwd.y - .3,
		"worn out, Mo slumps: her head drops %.0f cm and forward %.0f cm, and hangs" % [(N.head.y - T.head.y) * 100, (T.head.z - N.head.z) * 100])
	check(T.lids > .4 and N.lids < .1, "and her eyelids are heavy (%.0f%% shut)" % (T.lids * 100))
	var C: Dictionary = got.cold
	check(C.arm_l.y > N.arm_l.y + .015 and C.hands < N.hands - .1, "freezing, she hunches: shoulders up %.0f cm, arms drawn in (hands %.0f cm closer)" % [(C.arm_l.y - N.arm_l.y) * 100, (N.hands - C.hands) * 100])
	check(C.jitter > N.jitter * 3.0 and C.jitter > .002, "and shivers (moving %.1f mm a frame, against %.1f standing easy)" % [C.jitter * 1000, N.jitter * 1000])
	var S: Dictionary = got.scared
	check(S.arm_l.y > N.arm_l.y + .01 and S.jitter < C.jitter * .5, "scared, she hunches too (shoulders up %.0f cm), without the shivers" % ((S.arm_l.y - N.arm_l.y) * 100))
	var H: Dictionary = got.happy
	check(H.bob > .012 and N.bob < .004 and H.head.y > N.head.y - .005 and H.fwd.y > N.fwd.y, "happy, she bobs on her toes (%.1f cm) and holds her head up" % (H.bob * 100))
	var ok := true
	for st in got:
		if got[st].face != STATES[st][2]:
			ok = false
			note("  %s: face %s" % [st, got[st].face])
	check(ok, "a face for each: " + ", ".join(got.keys().map(func(k): return "%s (%s)" % [k, STATES[k][2]])))
	hold.erase(mo)


func _walking() -> void:
	var pace := {}
	for st in ["neutral", "tired", "cold", "happy"]:
		put(mo, -2.0, 1.0, Vector3(4.0, 0, 1.0))
		be(mo, st)
		await wait(1.5)
		var t0 := Time.get_ticks_msec()
		var top := 0.0
		var bob := 0.0
		mo.walk([[4.0, 1.0]])
		while mo.path != null and Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
			top = maxf(top, mo.pace)
			if mo.pace > 1.0:
				bob = maxf(bob, mo.inner.position.y)
		pace[st] = [top, (Time.get_ticks_msec() - t0) / 1000.0, bob]
		note("  walking %s: up to %.2f m/s, 6 m in %.1f s, springing up to %.1f cm" % [st, top, pace[st][1], bob * 100])
	check(pace.tired[0] < pace.neutral[0] * .85 and pace.tired[1] > pace.neutral[1], "worn out, she trudges: %.2f m/s against %.2f" % [pace.tired[0], pace.neutral[0]])
	check(pace.cold[0] < pace.neutral[0], "hunched with cold, a little slower (%.2f m/s)" % pace.cold[0])
	check(pace.happy[0] > pace.neutral[0] * 1.1 and pace.happy[2] > .03 and pace.neutral[2] < .01, "happy, a quicker step (%.2f m/s) with a spring in it (%.0f cm up)" % [pace.happy[0], pace.happy[2] * 100])
	hold.erase(mo)


# ---------- Faces ----------

func _faces() -> void:
	put(bo, .5, 2.0, Vector3(.5, 0, 6.0))
	put(mo, 9.0, -6.0, Vector3(9.0, 0, 0.0))
	for st in ["neutral", "happy", "sad", "cross", "scared", "tired"]:
		be(bo, st)
		await wait(1.5)
		await face_shot(bo, "bo_%s_face" % st)
		check(bo.mug.shape == STATES[st][2], "Bo %s: %s" % [st, bo.mug.shape])
	hold.erase(bo)
	put(bo, 9.0, -6.0, Vector3(9.0, 0, 0.0))
	put(mo, .5, 2.0, Vector3(.5, 0, 6.0))
	for st in ["sad", "cross"]:
		be(mo, st)
		await wait(1.5)
		await face_shot(mo, "mo_%s_face" % st)
	hold.erase(mo)


# ---------- Where the eyes go ----------

## How far off p's eyes are from looking at q (radians, from where they're looking).
func off(p: Pal, q: Vector3) -> float:
	if not (p.eyes_on is Vector3):
		return PI
	var e := p.eye_world()
	return (p.eyes_on - e).normalized().angle_to((q - e).normalized())


## Which way p's eyes are going, against where they face (radians; 0 straight ahead).
func eyes_way(p: Pal) -> float:
	if not (p.eyes_on is Vector3):
		return 0.0
	var e := p.eye_world()
	var a := atan2(p.eyes_on.x - e.x, p.eyes_on.z - e.z) - p.yaw
	return atan2(sin(a), cos(a))


## Scared, alone: she keeps glancing about, one way and the other; at ease, she doesn't.
func _glancing() -> void:
	put(mo, .5, 2.0, Vector3(.5, 0, 6.0))
	put(bo, 9.0, -6.0, Vector3(9.0, 0, 0.0))
	put_kid(-8.0, 12.0)
	m.plans.make(m.mem.day, [], "test", m.mem.life_h)
	var runs := {}
	for st in ["neutral", "scared"]:
		be(mo, st)
		await wait(1.0)
		var looks := 0
		var left := false
		var right := false
		var was := false
		var t := 0.0
		var shot_taken := false
		while t < 6.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var w := eyes_way(mo)
			var off_ := absf(w) > .45
			if off_ and not was:
				looks += 1
				left = left or w > 0
				right = right or w < 0
				if st == "scared" and not shot_taken:
					shot_taken = true
					await wait(.2)
					await frame(mo)
					await cut("mo_scared_glancing", mo.position + Vector3(0, (mo.eye_world().y - mo.position.y) * .55, 0), .75, .9, 520)
			was = off_
		runs[st] = [looks, left and right]
	check(runs.neutral[0] == 0, "at ease, alone, her eyes stay put")
	check(runs.scared[0] >= 2 and runs.scared[1], "scared, she glances about: %d looks in 6 s, both ways" % runs.scared[0])
	hold.erase(mo)


func together() -> void:
	put(mo, .5, 2.0, Vector3(3.0, 0, 2.0))
	put(bo, 3.0, 2.0, Vector3(.5, 0, 2.0))
	put_kid(1.75, 7.0)
	be(mo, "neutral")
	be(bo, "neutral")
	for x in [m, b]:
		x.plans.make(x.mem.day, [], "test", x.mem.life_h)
	await wait(.6)


func _eyes_on_them() -> void:
	await together()
	game.say(bo, "Mo, look at this, I found a really good stick for the fire, it's nearly as long as me")
	await wait(.8)
	check(m.with_who() == bo and off(mo, Pal.face_of(bo)) < .05, "Bo talking to her: Mo looks at him (%.2f off)" % off(mo, Pal.face_of(bo)))
	check(off(bo, Pal.face_of(mo)) < .05, "and he looks at her while he talks")
	await pair_shot("talking_eyes_on")
	game.hush()
	await wait(.5)


func _on_her_mind() -> void:
	await together()
	put(bo, 9.0, -6.0, Vector3(9.0, 0, 0.0))
	put_kid(-8.0, 12.0)
	m.plans.make(m.mem.day, ["look for shells on the beach for my jar"], "test", m.mem.life_h)
	var beach: Vector3 = game.level.places["the beach in the south"]
	await wait(.5)
	check(m.thinking_of() == beach, "shells on her mind: the beach comes to mind")
	var looked := 0.0
	var t := 0.0
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if mo.eyes_on is Vector3 and Vector2(mo.eyes_on.x - beach.x, mo.eyes_on.z - beach.z).length() < 1.0:
			looked += get_process_delta_time()
	check(looked > 1.5 and looked < 5.0, "standing about, she looks off toward the beach now and then (%.1f s of 8)" % looked)
	m.plans.make(m.mem.day, [], "test", m.mem.life_h)
	await wait(.5)
	check(m.thinking_of() == null, "nothing on her mind: nowhere in particular")


## A bluff: Bo says he's not scared of the dark (he is). His eyes slide off Mo, with a quick look back.
func _a_bluff() -> void:
	await together()
	var fixed := 0.0
	var t := 0.0
	while t < 2.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		if off(bo, Pal.face_of(mo)) < .1:
			fixed += get_process_delta_time()
	check(fixed > 2.0, "talking with Mo, nothing to hide: Bo looks at her (%.1f s of 2.5)" % fixed)
	var r := {"say": "Dark? I'm not scared of the dark at all.", "to": "mo", "think": "I'm terrified of the dark under the hill", "true": "bluff", "do": "none"}
	standin.reply(b, r)
	await wait(.3)
	var away := 0.0
	var back := 0
	var was_on := true
	t = 0.0
	var snapped := false
	while t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var on := off(bo, Pal.face_of(mo)) < .1
		if not on:
			away += get_process_delta_time()
			if not snapped and t > .5:
				snapped = true
				await pair_shot("bluff_eyes_slide_off")
		if on and not was_on:
			back += 1
		was_on = on
	check(bo.nervous > 0.0 or away > 1.5, "his bluff (\"%s\") makes him shifty" % r.say)
	check(away > 1.5 and back >= 1, "his eyes slide off her (%.1f s of 3), with %d quick look%s back" % [away, back, "" if back == 1 else "s"])
	check(b.secrets.items.back().kind == "bluff", "and he knows it was a bluff")
	await wait(3.0)
	fixed = 0.0
	t = 0.0
	while t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if off(bo, Pal.face_of(mo)) < .1:
			fixed += get_process_delta_time()
	check(fixed > 1.6, "a few seconds on, he can look her in the eye again (%.1f s of 2)" % fixed)
	game.hush()


func _a_grudge() -> void:
	await together()
	put_kid(1.75, 4.0)
	await wait(.3)
	m.heart.grudge("wisp", "laughed at me when I fell in the pond", .7, m.mem.life_h)
	put(bo, 9.0, -6.0, Vector3(9.0, 0, 0.0))
	put(mo, 1.75, 2.0, game.wisp_g)
	await wait(1.0)
	var away := 0.0
	var t := 0.0
	while t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if off(mo, Pal.face_of(game.kid)) > .3:
			away += get_process_delta_time()
	check(m.with_who() == game.kid and mo.feel.get("away", false) and mo.mug.shape.begins_with("cross"), "sore at Wisp, Mo's cross with you (%s)" % mo.mug.shape)
	check(away > 1.8, "and won't look at you much (%.1f s of 3 looking away)" % away)
	await face_shot(mo, "mo_sore_at_wisp")
	m.heart.rel.wisp.grudges.clear()


# ---------- In their own pictures ----------

## Mo looks at Bo slumped, bouncing, then hunched with cold: her own pictures show it. Where his face and
## shoulders come out in her picture, and the pictures themselves.
func _in_her_eyes() -> void:
	put(mo, .5, 2.0, Vector3(2.5, 0, 2.0))
	put(bo, 2.5, 2.0, Vector3(.5, 0, 2.0))
	put_kid(-6.0, 9.0)
	be(mo, "neutral")
	var pics := {}
	var seen := {}
	for st in ["tired", "happy", "cold"]:
		be(bo, st)
		await wait(2.0)
		mo.gaze = Pal.face_of(bo) + Vector3(0, -.3, 0)
		await get_tree().process_frame
		var f: Dictionary = await game.eyes.look(mo)
		pics[st] = f.image
		var hd: Node3D = marks[bo].head
		var nose: Vector3 = hd.global_transform * (bo.mug.bind * Vector3(0, bo.mug.F.mouth.y + .03, .25))
		var head: Vector3 = hd.global_transform * (bo.mug.bind * Vector3(0, bo.mug.F.mouth.y + .03, 0))
		seen[st] = {head = game.eyes.project(f, head), nose = game.eyes.project(f, nose),
			shoulders = (game.eyes.project(f, marks[bo].arm_l.global_position) + game.eyes.project(f, marks[bo].arm_r.global_position)) / 2.0}
		if shots != "":
			(f.image as Image).save_png(shots.path_join("mo_sees_bo_%s.png" % st))
	var droop := func(st: String) -> float: return seen[st].nose.y - seen[st].head.y
	note("  in Mo's picture: Bo's face pointing down by %.3f tired, %.3f happy; shoulders at %.3f cold, %.3f happy" % [
		droop.call("tired"), droop.call("happy"), seen.cold.shoulders.y, seen.happy.shoulders.y])
	check(droop.call("tired") > droop.call("happy") + .03, "in Mo's own picture, worn-out Bo's head hangs (his face points down %.0f%% of the picture further)" % ((droop.call("tired") - droop.call("happy")) * 100))
	check(seen.cold.shoulders.y < seen.happy.shoulders.y - .005, "and cold Bo's shoulders are up round his ears")
	check(_diff(pics.tired, pics.happy) > .01 and _diff(pics.cold, pics.happy) > .01, "her pictures of him differ: tired against happy %.1f%% of the pixels, cold against happy %.1f%%" % [_diff(pics.tired, pics.happy) * 100, _diff(pics.cold, pics.happy) * 100])
	hold.erase(mo)
	hold.erase(bo)


## The share of pixels that differ noticeably.
func _diff(a: Image, b: Image) -> float:
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var c1 := a.get_pixel(x, y)
			var c2 := b.get_pixel(x, y)
			if absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) > .15:
				n += 1
	return float(n) / (a.get_width() * a.get_height() / 4.0)


# ---------- What it costs ----------

## The island with both of them on screen, shivering and bouncing, body language on and off, in turns.
func _cost() -> void:
	put(mo, .5, 2.0, Vector3(1.75, 0, 6.0))
	put(bo, 3.0, 2.0, Vector3(1.75, 0, 6.0))
	put_kid(1.75, 7.0)
	be(mo, "cold")
	be(bo, "happy")
	game.cam_focus = null
	game.az = 0.0
	game.pol = 1.2
	game.aim(0.0, true)
	await wait(1.0)
	# Unhurried by the screen's refresh while measuring, so the frame rate is what the Mac can do
	var vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var max_fps := Engine.max_fps
	Engine.max_fps = 0
	var on := {draws = [], fps = [], pals = [], pose = [], show = []}
	var off_ := {draws = [], fps = [], pals = [], pose = [], show = []}
	for round_ in 4:
		for state in [false, true]:
			Pal.expressive = state
			await wait(.6)
			var into: Dictionary = on if state else off_
			var t0 := Time.get_ticks_usec()
			var frames := 0
			var draws := 0.0
			var pals := 0.0
			var pal_frames := 0
			var pose0: int = Pal.Bearing.us
			var show0: int = Mind.show_us
			while Time.get_ticks_usec() - t0 < 2500000:
				var p0: int = game.prof.pals
				var n0: int = game.prof.n
				await get_tree().process_frame
				frames += 1
				if game.prof.n == n0 + 1:
					pals += game.prof.pals - p0
					pal_frames += 1
				draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			into.draws.append(draws / frames)
			into.fps.append(frames / ((Time.get_ticks_usec() - t0) / 1e6))
			into.pose.append(float(Pal.Bearing.us - pose0) / frames)
			into.show.append(float(Mind.show_us - show0) / frames)
			into.pals.append(pals / maxf(1, pal_frames) + into.pose.back() + into.show.back())
	Pal.expressive = true
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	var avg := func(a: Array) -> float: return a.reduce(func(x, y): return x + y, 0.0) / a.size()
	var p_on: float = avg.call(on.pals)
	var p_off: float = avg.call(off_.pals)
	var line := "Mac, both on screen (Mo shivering, Bo bouncing), vsync off. Body language off: %.0f fps, the pals' own work %.0f µs a frame, %.0f draw calls. On: %.0f fps, %.0f µs (+%.0f µs: posing %.0f, mood to looks %.0f, the rest in their update), %.0f draw calls (+%.0f)." % [
		avg.call(off_.fps), p_off, avg.call(off_.draws), avg.call(on.fps), p_on, p_on - p_off, avg.call(on.pose), avg.call(on.show), avg.call(on.draws), avg.call(on.draws) - avg.call(off_.draws)]
	note("  " + line)
	if shots != "":
		var f := FileAccess.open(shots.path_join("frame_cost.txt"), FileAccess.WRITE)
		f.store_line(line)
		f.store_line("rounds (off, on) fps: %s / %s" % [off_.fps, on.fps])
		f.store_line("rounds (off, on) pals us: %s / %s" % [off_.pals, on.pals])
	check(avg.call(on.fps) > avg.call(off_.fps) * .95, "the frame rate holds (%.0f fps with it, %.0f without)" % [avg.call(on.fps), avg.call(off_.fps)])
	check(p_on - p_off < 300.0, "and it costs little: %+.0f µs a frame for the two of them on the Mac" % (p_on - p_off))
	hold.clear()
