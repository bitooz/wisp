extends Node
## Learning and failing in the real game, with no model (a scripted stand-in acts for them):
##   godot --path . -- --autoplay --autoplay-script=res://tools/learn_world_test.gd --offline
## Chopping, boat building, pushing the glowing door, finding the way and seeing in the dark, all with skills
## that change what happens (a beginner fails sometimes, never more than three times running, and gets better),
## lessons that come back at the same thing, and catching someone out when what you see shows they lied.
## Prints ok:/FAIL:, exits non-zero on a failure.

const StandIn := preload("res://tools/standin.gd")

var game: Game
var args: Array = []
var failed := false
var standin
var mo: Pal
var bo: Pal
var m: Mind
var b: Mind
var isle


func _ready() -> void:
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
	isle = game.level
	await game.wait(.5)
	await _chopping()
	await _the_boat()
	await _the_door()
	await _finding_the_way()
	await _in_the_dark()
	await _caught_out()
	await _kept()
	note("FAILED" if failed else "DONE: learning and failing")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[learn %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


func check(ok: bool, what: String) -> void:
	note(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func until(cond: Callable, timeout: float) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > timeout * 1000:
			return false
		await get_tree().process_frame
	return true


func put(p: Pal, at: Vector3, face_to := Vector3.INF) -> void:
	var mind: Mind = game.minds.of(p)
	mind.task = {}
	p.stop()
	p.go_out()
	p.position = Vector3(at.x, game.level.ground(at.x, at.z), at.z)
	p.mode = "script"
	p.gaze = null
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)
	game.kid.position = game.wisp_g


func last(x: Mind, kind: String) -> String:
	for i in range(x.memory.size() - 1, -1, -1):
		if x.memory[i].k == kind:
			return x.memory[i].s
	return ""


## Use a thing, as the model would (point at it in their picture), and say what happened.
func use(x: Mind, thing: Node3D, word: String) -> String:
	var at: Array = await standin.point(x, Level.box_of(thing).get_center())
	x.start("use", {at = at, what = word})
	await until(func(): return x.task.is_empty(), 10)
	return last(x, "did")


## Goes at something: how many worked, the longest run that didn't, and what was said each time.
func goes(x: Mind, thing: Node3D, word: String, n: int, worked: Callable) -> Dictionary:
	var ok := 0
	var row := 0
	var worst := 0
	for i in n:
		var what := await use(x, thing, word)
		if worked.call(what):
			ok += 1
			row = 0
		else:
			row += 1
			worst = maxi(worst, row)
	return {ok = ok, worst = worst}


# ---------- Chopping ----------

func _chopping() -> void:
	var wp: Vector3 = isle.woodpile.position
	put_kid(wp.x + 6, wp.z + 6)
	put(bo, wp + Vector3(2.0, 0, 1.0), wp)
	put(mo, wp + Vector3(-2.0, 0, 1.5), wp)
	var start: float = b.skills.level.chopping
	var wood: int = isle.wood
	isle.wood = 0
	isle._show_wood()
	var bo_goes := await goes(b, isle.woodpile, "the woodpile", 12, func(s): return s.begins_with("chopped"))
	check(bo_goes.ok > 0 and isle.wood == bo_goes.ok, "Bo chops twelve times: %d worked, and the pile has that many more logs" % bo_goes.ok)
	check(bo_goes.worst <= Skills.MOST_FAILS, "never more than three misses in a row (%d)" % bo_goes.worst)
	check(b.skills.level.chopping > start, "and he's better at it now (%.2f from %.2f)" % [b.skills.level.chopping, start])
	var mo_goes := await goes(m, isle.woodpile, "the woodpile", 12, func(s): return s.begins_with("chopped"))
	check(mo_goes.ok < bo_goes.ok, "Mo, new to it, gets fewer (%d against Bo's %d)" % [mo_goes.ok, bo_goes.ok])
	check(m.memory.any(func(e): return e.k == "lesson" and e.s == Skills.LESSONS.chopping), "missing the log taught her something: \"%s\"" % Skills.LESSONS.chopping)
	var body := game.minds.thought_body(m, "idle", {}, {jpg = ""})
	check(body.skills.has(m.skills.words("chopping")) and body.learned.has(Skills.LESSONS.chopping), "back at the woodpile, it comes to mind: %s; %s" % [body.skills, body.learned])
	put(mo, Vector3(.5, 0, 2.0))
	body = game.minds.thought_body(m, "idle", {}, {jpg = ""})
	check(not body.learned.has(Skills.LESSONS.chopping), "away from it, it doesn't (it's in her memory if she needs it)")
	isle.wood = wood + isle.wood
	isle._show_wood()


# ---------- The boat ----------

func _the_boat() -> void:
	var boat: Vector3 = isle.boat.position
	put(bo, isle.life_spot("bo", "hobby"), boat)
	var k: float = isle.boat_k
	var g := await goes(b, isle.boat, "my boat", 8, func(s): return s.begins_with("worked on my model boat"))
	check(is_equal_approx(isle.boat_k, minf(1.0, k + .1 * g.ok)), "eight goes at his boat: %d pieces fitted, and it came along by that much (%s)" % [g.ok, Life.boat_words(isle.boat_k)])
	check(g.worst <= Skills.MOST_FAILS, "never more than three tries that wouldn't fit, in a row")


# ---------- The door ----------

func _the_door() -> void:
	var door: Vector3 = isle.thing_pos("door")
	put(mo, Vector3(door.x, 0, door.z + 4.0), door)
	put_kid(door.x + 2, door.z + 7)
	game.controls = true
	var tries := 0
	while mo.place_id != "cave" and tries < 6:
		tries += 1
		await use(m, isle.arch, "the glowing door")
		await game.wait(.2)
		if mo.place_id != "cave":
			put(mo, Vector3(door.x, 0, door.z + 4.0), door)
	game.controls = false
	check(mo.place_id == "cave" and tries <= Skills.MOST_FAILS + 1, "Mo pushes at the glowing door: in, after %d go(es); a beginner may need a few, never more than four" % tries)
	if tries > 1:
		check(m.memory.any(func(e): return e.k == "lesson" and e.s == Skills.LESSONS.mechanisms), "and the knack to it is something she's learned")
	mo.place_id = "isle"
	mo.arriving = false
	mo.set_here(true)


# ---------- Finding the way ----------

## Setting off for somewhere they know (not walking all the way): would they take a wrong turn?
func wrong_turns(x: Mind, n: int) -> int:
	var lost := 0
	for i in n:
		put(x.pal, Vector3(30.0, 0, -15.0), Vector3(0, 0, 0))
		x.start("head_to", {place = "the pond"})
		if x.task.get("lost", false):
			lost += 1
		x.task = {}
		x.pal.stop()
	return lost


func _finding_the_way() -> void:
	var bo_lost := wrong_turns(b, 12)
	var mo_lost := wrong_turns(m, 12)
	check(bo_lost > 0 and mo_lost <= bo_lost, "heading for the pond from the east hills, twelve times: Bo takes %d wrong turns, Mo %d" % [bo_lost, mo_lost])
	# One all the way: a wrong turn ends up somewhere else, and she knows it
	var tries := 0
	while tries < 6:
		tries += 1
		put(bo, Vector3(30.0, 0, -15.0), Vector3(0, 0, 0))
		b.start("head_to", {place = "the pond"})
		if b.task.get("lost", false):
			break
		b.task = {}
		bo.stop()
	if b.task.get("lost", false):
		await until(func(): return b.task.is_empty(), 30)
		check(last(b, "did").begins_with("went the wrong way for a bit and ended up") and last(b, "did").ends_with("not at the pond"), "Bo takes a wrong turn: \"%s\"" % last(b, "did"))
		check(b.memory.any(func(e): return e.k == "lesson" and e.s == Skills.LESSONS.wayfinding), "and learns from it")
	else:
		check(false, "Bo never took a wrong turn to watch")


# ---------- Seeing in the dark ----------

func _in_the_dark() -> void:
	# A dim evening on the path, away from any light: just enough to see by, for sharp eyes
	put_kid(-40, 40)
	put(mo, Vector3(.5, 0, 2.0), Vector3(.5, 0, -20))
	put(bo, Vector3(.5, 0, -2.0), Vector3(.5, 0, 20))
	var h := 18.0
	while h < 21.0:
		game.clock.set_hour(h)
		var l: float = isle.light_at(bo.position + Vector3(0, .7, 0))
		if l > .06 and l < .14:
			break
		h += .05
	await game.wait(.2)
	var saved: float = m.skills.level.night_eyes
	m.skills.level.night_eyes = 0.0
	var dim := m._sees(bo)
	m.skills.level.night_eyes = 1.0
	var sharp := m._sees(bo)
	m.skills.level.night_eyes = saved
	check(not dim and sharp, "in the dusk (light %.2f), eyes new to the dark can't make Bo out; practised ones can" % isle.light_at(bo.position + Vector3(0, .7, 0)))
	game.clock.set_hour(11)
	put_kid(1.5, 5.0)


# ---------- Caught out ----------

func _caught_out() -> void:
	game.clock.set_hour(11)
	await game.wait(.2)
	# Bo, behind Mo, with an apple in his hand, says he hasn't got it
	put(mo, Vector3(.5, 0, 2.0), Vector3(.5, 0, -20))
	put(bo, Vector3(.5, 0, 5.0), Vector3(.5, 0, 2.0))
	put_kid(-40, 40)
	var apple: Dictionary = {}
	for T in isle.things:
		if String(T.t).begins_with("apple"):
			apple = T
	isle.taken(apple)
	bo.hold(apple)
	apple.what = "an apple"
	await game.wait(.1)
	var t0: float = m.heart.rel.bo.trust
	game.minds.line_said(bo, "Mo, I don't have the apple, honest.")
	await game.wait(.5)
	check(m.claims.size() == 1 and m.claims[0].status == "open" and m.heart.rel.bo.trust == t0, "behind her, Bo says he doesn't have the apple: she can't see, so she believes him")
	m.start("turn", {dir = "around"})
	await until(func(): return m.task.is_empty(), 5)
	await game.wait(.5)
	check(m.claims[0].status == "caught" and m.heart.rel.bo.trust < t0 - .1, "she turns round and there it is in his hand: caught out, and she trusts him less (%.2f from %.2f)" % [m.heart.rel.bo.trust, t0])
	check(last(m, "caught") == "Bo told me \"Mo, I don't have the apple, honest.\", but I saw Bo holding an apple: it wasn't true", "she won't forget it: \"%s\"" % last(m, "caught"))
	check(m.heart.about("bo").contains("Bo told you \"Mo, I don't have the apple, honest.\", and it wasn't true"), "and it rankles: \"%s\"" % m.heart.about("bo"))
	var T: Dictionary = bo.let_go()
	T.node.queue_free()
	# (you, nearby but off to the side, so Mo doesn't go trailing after you)
	put_kid(6.0, 3.5)
	put(mo, Vector3(.5, 0, 2.0), bo.position)
	await game.wait(.1)
	# A true one: he really hasn't got it
	var t1: float = m.heart.rel.bo.trust
	game.minds.line_said(bo, "I don't have the torch.")
	await game.wait(.6)
	check(m.claims.back().status == "open" and m.heart.rel.bo.trust == t1, "he says he hasn't got the torch, and he hasn't: nothing to catch")
	# "I'm not scared", then jumping back in fright, in front of her
	game.minds.line_said(bo, "Me? I'm not scared at all.")
	t1 = m.heart.rel.bo.trust
	bo.recoil = 3.0
	await game.wait(.5)
	bo.recoil = 0.0
	check(m.claims.back().status == "caught" and m.heart.rel.bo.trust < t1, "he says he's not scared, then jumps back in fright right in front of her: caught out")
	# "The door won't open", then going straight through it, as she watches
	var door: Vector3 = isle.thing_pos("door")
	put(bo, Vector3(door.x + .5, 0, door.z + 2.0), door)
	put(mo, Vector3(door.x, 0, door.z + 6.0), bo.position)
	put_kid(door.x - 6, door.z + 9)
	await game.wait(.1)
	game.minds.line_said(bo, "The door won't open, Mo. Forget it.")
	t1 = m.heart.rel.bo.trust
	game.controls = true
	game.go_through(bo, "cave", {})
	await game.wait(.2)
	game.controls = false
	check(m.claims.back().status == "caught" and last(m, "caught").ends_with("but I saw Bo go straight through it: it wasn't true"), "he says the door won't open, then goes straight through it: caught out")
	bo.place_id = "isle"
	bo.arriving = false
	bo.set_here(true)
	# Wisp says it too, then goes through
	put(mo, Vector3(door.x, 0, door.z + 6.0), door)
	put_kid(door.x + .5, door.z + 2.5)
	await game.wait(.1)
	game.set_active(mo)
	var tw: float = m.heart.rel.wisp.trust
	game.minds._got_words("Mo, the door's stuck.")
	game.controls = true
	await game.follow_to("cave", {})
	game.controls = false
	check(m.claims.back().from == "wisp" and m.claims.back().status == "caught" and m.heart.rel.wisp.trust < tw, "Wisp says the door's stuck and goes through it: Wisp's caught out too")
	game.travel("isle", {})
	await game.wait(.3)


func _kept() -> void:
	m.save()
	var s := JSON.stringify(m.skills.to_save())
	var c := JSON.stringify(m.claims)
	m.load_memory()
	check(JSON.stringify(m.skills.to_save()) == s and JSON.stringify(m.claims) == c, "saved and loaded: her skills, lessons and what she caught people out on")
