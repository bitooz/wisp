extends Node
## Sight, hearing and touch in the real game, with no model (a scripted stand-in reacts for them):
##   godot --path . -- --autoplay --autoplay-script=res://tools/senses_test.gd --offline [--shots=dir]
## Checks that nothing behind them reaches them until they turn (or turn their head); that sounds come to each
## of them from a direction and a rough distance, muffled through walls, from indoors or between places, and
## that a quiet one doesn't wake a sleeper but a loud one does; that voices carry where they were said from;
## and that touch (bumping into things and people, what's underfoot, wading, wet hands, a fire's heat, a plate
## sinking underfoot) comes to them as feelings. Then the stand-in turns to what it hears and steps out of the
## water, through the same actions the model uses. Prints ok:/FAIL:, exits non-zero on a failure.

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
var isle


func _ready() -> void:
	for a in args:
		if a.begins_with("--shots="):
			shots = a.substr(8)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
	if game.minds.on:
		note("FAIL: the minds are on; run with --offline (this test must not call the model)")
		get_tree().quit(2)
		return
	standin = StandIn.new(game)
	mo = game.mo
	bo = game.bo
	m = game.minds.mo
	b = game.minds.bo
	isle = game.level
	for x in [m, b]:
		if x.file.contains("/offline/"):
			x.forget_all()
		else:
			note("FAIL: the minds' memories aren't the test's own (%s)" % x.file)
			get_tree().quit(2)
			return
	game.minds.quiet = true
	game.clock.stopped = true
	game.clock.set_hour(12)
	game.controls = false
	await game.wait(1.0)
	# Under the hill once, so that place exists to hear between
	for p in [mo, bo]:
		p.place_id = "cave"
		p.arriving = true
	game.travel("cave", {})
	await game.wait(.3)
	for p in [mo, bo]:
		p.place_id = "isle"
		p.arriving = true
	game.travel("isle", {})
	isle = game.level
	await game.wait(.5)
	await _field_of_view()
	await _seeing_events()
	await _hearing()
	await _voices_and_sleep()
	await _touch()
	await _plates_underfoot()
	await _standin_reacts()
	note("FAILED" if failed else "DONE: sight, hearing and touch")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[senses %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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


func save_frame(f: Dictionary, name: String) -> void:
	if shots != "":
		(f.image as Image).save_png(shots.path_join(name + ".png"))


## Stand someone somewhere, facing a point, doing nothing.
func put(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	var mind: Mind = game.minds.of(p)
	mind.task = {}
	if mind.body.asleep:
		mind.body.asleep = false
		p.closed = false
	p.go_out()
	p.lie = false
	p.lying = 0.0
	p.stop()
	p.pace = 0.0
	p.position = Vector3(x, game.level.ground(x, z), z)
	p.mode = "script"
	p.gaze = null
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)
	game.kid.position = game.wisp_g


## The latest of a kind of memory ("heard", "felt", "told", "event", "did").
func last(mind: Mind, kind: String) -> String:
	for i in range(mind.memory.size() - 1, -1, -1):
		if mind.memory[i].k == kind:
			return mind.memory[i].s
	return ""


func count(mind: Mind, kind: String, has: String) -> int:
	return mind.memory.filter(func(x): return x.k == kind and String(x.s).contains(has)).size()


func mentions(lines: Array, word: String) -> bool:
	return lines.any(func(l): return String(l).contains(word))


func at_side(p: Pal, angle: float, dist: float) -> Vector3:
	# A point `dist` m from p, `angle` radians from where they face (+ to their left)
	var f := p.yaw + angle
	return p.position + Vector3(sin(f), 0, cos(f)) * dist


func ahead_of(p: Pal, dist: float) -> Vector3:
	return at_side(p, 0.0, dist)


# ---------- Only what's in front of them ----------

func _field_of_view() -> void:
	# On the path halfway to the hill, facing the hill; Bo three metres behind, standing still
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	var behind := at_side(mo, PI, 3.0)
	put(bo, behind.x, behind.z, mo.position)
	put_kid(-6, 9)
	await game.wait(.3)
	var f: Dictionary = await game.eyes.look(mo)
	save_frame(f, "mo-ahead-bo-behind")
	var q: Vector2 = game.eyes.project(f, bo.global_position + Vector3(0, .7, 0))
	check(q.x < 0 or q.x > 1, "Bo, right behind Mo, isn't in her picture")
	check(not game.eyes.sees(mo, bo.global_position + Vector3(0, .7, 0), bo), "she can't see him")
	var feel := m.feel()
	check(not mentions(feel, "Bo"), "nothing she feels or hears mentions him: %s" % [feel.filter(func(l): return not l.contains("(you know the way"))])
	# He walks about behind her: she hears footsteps, not him
	bo.mode = "free"
	bo.walk([[behind.x + 2.5, behind.z + .5], [behind.x, behind.z]])
	await game.wait(.7)
	feel = m.feel()
	check(mentions(feel, "you can hear footsteps, behind you") and not mentions(feel, "Bo"), "he walks about behind her: she hears footsteps behind her, close by, and nothing says who: %s" % [feel.filter(func(l): return l.contains("hear"))])
	await until(func(): return bo.path == null, 5)
	bo.mode = "script"
	# She turns round: now she sees him
	check(m.start("turn", {dir = "around"}), "she turns round")
	await until(func(): return m.task.is_empty(), 5)
	f = await game.eyes.look(mo)
	save_frame(f, "mo-turned-round")
	q = game.eyes.project(f, bo.global_position + Vector3(0, .7, 0))
	check(q.x > 0 and q.x < 1 and q.y > 0 and q.y < 1 and game.eyes.sees(mo, bo.global_position + Vector3(0, .7, 0), bo), "turned round, he's in her picture")
	feel = m.feel()
	check(mentions(feel, "Bo is about 3 m away"), "and she knows where he is: \"%s\"" % [feel.filter(func(l): return l.begins_with("Bo"))])
	# Turning her head: Bo off to her left, out of the corner of the picture
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	var left := at_side(mo, PI / 2, 3.0)
	put(bo, left.x, left.z, mo.position)
	await game.wait(.2)
	check(not game.eyes.sees(mo, bo.global_position + Vector3(0, .7, 0), bo), "Bo off to her left: she can't see him looking ahead")
	var yaw := mo.yaw
	check(m.start("look", {dir = "left"}), "she turns her head to the left")
	await game.wait(.3)
	f = await game.eyes.look(mo)
	save_frame(f, "mo-looks-left")
	check(game.eyes.sees(mo, bo.global_position + Vector3(0, .7, 0), bo) and is_equal_approx(mo.yaw, yaw), "looking left, she sees him, without turning her body")
	check(m.start("look", {dir = "ahead"}) and not game.eyes.sees(mo, bo.global_position + Vector3(0, .7, 0), bo), "looking ahead again, he's out of sight")
	m.start("look", {dir = "up"})
	check(Eyes.pose(mo).xf.basis.z.y < -.5, "she can look up at the sky")
	m.start("look", {dir = "ahead"})
	# Wisp, idle behind her: she doesn't notice how long Wisp's been standing there
	put_kid(at_side(mo, PI, 4.0).x, at_side(mo, PI, 4.0).z)
	game.idle_t = 60.0
	game.minds.last_heard_t = -100.0
	check(not mentions(m.feel(), "Wisp"), "Wisp standing about behind her: nothing about Wisp")
	put_kid(ahead_of(mo, 4.0).x, ahead_of(mo, 4.0).z)
	await game.wait(.1)
	game.idle_t = 60.0
	check(mentions(m.feel(), "Wisp hasn't moved"), "with Wisp in front of her, she notices Wisp hasn't moved")
	put_kid(-6, 9)


# ---------- Things they'd only see happen ----------

func _seeing_events() -> void:
	var door: Vector3 = isle.thing_pos("door")
	# Bo at the door in the hill; Mo a few metres off, her back to it
	var from_door := Vector3(door.x, 0, door.z + 5.0)
	put(bo, door.x + .5, door.z + 2.0, door)
	put(mo, from_door.x, from_door.z, from_door + Vector3(0, 0, 10))
	put_kid(from_door.x + 3, from_door.z + 6)
	game.controls = true
	game.idle_t = 0.0
	var events := count(m, "event", "went off through there")
	game.go_through(bo, "cave", {})
	await game.wait(.2)
	check(count(m, "event", "went off through there") == events, "Bo goes through the door behind Mo: she doesn't see it")
	check(last(m, "heard").begins_with("a heavy door creaking, behind you"), "but hears it, behind her: \"%s\"" % last(m, "heard"))
	# Back, and this time she's watching
	bo.place_id = "isle"
	bo.arriving = false
	bo.set_here(true)
	put(bo, door.x + .5, door.z + 2.0, door)
	put(mo, from_door.x, from_door.z, bo.position)
	await game.wait(.2)
	game.go_through(bo, "cave", {})
	await game.wait(.2)
	check(count(m, "event", "Bo just went off through there") == events + 1, "facing him, she sees him go: \"%s\"" % last(m, "event"))
	bo.place_id = "isle"
	bo.arriving = false
	bo.set_here(true)
	game.controls = false
	put(bo, 30, -15)


# ---------- Sounds: where from, how far, and through what ----------

func _hearing() -> void:
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, 30, -15)
	var H: Hearing = game.hearing
	var right: Dictionary = H.heard(mo, at_side(mo, -PI / 2, 3.0) + Vector3(0, .5, 0), "isle", 12.0)
	check(right.get("words", "") == "to your right, close by", "a sound three metres to her right: \"%s\"" % right.get("words", ""))
	var near: Dictionary = H.heard(mo, ahead_of(mo, 1.0) + Vector3(0, .8, 0), "isle", 12.0)
	check(near.get("words", "") == "ahead of you, right next to you", "one just in front: \"%s\"" % near.get("words", ""))
	var behind_far: Dictionary = H.heard(mo, at_side(mo, PI, 25.0) + Vector3(0, 1, 0), "isle", 60.0)
	check(String(behind_far.get("words", "")).ends_with("behind you, far off"), "a loud one far behind: \"%s\"" % behind_far.get("words", ""))
	check(H.heard(mo, at_side(mo, PI, 25.0), "isle", 10.0).is_empty(), "a quiet one that far off isn't heard at all")
	check(H.heard(mo, ahead_of(mo, 3.0), "isle", 12.0).level > H.heard(mo, ahead_of(mo, 9.0), "isle", 12.0).level, "nearer is louder")
	# A sound made: remembered, from where it was
	H.make(at_side(mo, PI * .8, 4.0) + Vector3(0, .5, 0), "isle", "a soft thud", 12.0)
	check(last(m, "heard").begins_with("a soft thud, behind you on your left, close by"), "a thud behind her on the left: \"%s\"" % last(m, "heard"))
	check(absf(m.last_heard.angle) > 2.0, "and she knows which way it came from")
	# Through the house
	var house: Vector3 = Level.box_of(isle.house).get_center()
	var hc := Vector3(house.x, 0, house.z)
	var dirv := Vector3(1, 0, .3).normalized()
	put(mo, hc.x + dirv.x * 4.0, hc.z + dirv.z * 4.0, hc)
	var far_side := hc - dirv * 4.0 + Vector3(0, .8, 0)
	var thru: Dictionary = H.heard(mo, far_side, "isle", 40.0)
	check(thru.get("muffled", false) and String(thru.words).begins_with("muffled, ahead of you"), "a sound on the far side of the house is muffled: \"%s\"" % thru.get("words", ""))
	var open_side: Dictionary = H.heard(mo, mo.position + (mo.position - hc).normalized() * 8.0 + Vector3(0, .8, 0), "isle", 40.0)
	check(not open_side.get("muffled", true), "the same distance with nothing between isn't: \"%s\"" % open_side.get("words", ""))
	# Indoors
	mo.go_in("house")
	var outdoors: Dictionary = H.heard(mo, mo.position + Vector3(3, .8, 0), "isle", 20.0)
	check(outdoors.get("muffled", false), "indoors, a sound outside is muffled: \"%s\"" % outdoors.get("words", ""))
	mo.go_out()
	# Between places: Mo under the hill, near the steps; a door creaking up on the island by the door
	var cave: Level = game.levels.cave
	var steps: Vector3 = cave.way_to("isle")
	mo.place_id = "cave"
	mo.set_here(false)
	mo.position = Vector3(steps.x, 0, steps.z - 2.5)
	mo.yaw = 0.0
	var door: Vector3 = isle.thing_pos("door")
	var up: Dictionary = H.heard(mo, door + Vector3(0, 1, 2), "isle", 12.0)
	check(up.get("muffled", false) and String(up.get("words", "")).begins_with("muffled, ahead of you"), "under the hill, facing the steps, a sound up by the island's door comes muffled, down the steps ahead of her: \"%s\"" % up.get("words", ""))
	check(H.heard(mo, Vector3(0, 1, 20), "isle", 12.0).is_empty(), "a sound down in the village doesn't reach her down there")
	mo.position = Vector3(0, 0, -4.0)
	check(H.heard(mo, door + Vector3(0, 1, 2), "isle", 12.0).is_empty(), "nor the one by the door, once she's deep in the room")
	# And the other way: a loud grinding under the hill, heard on the island by the door
	put(bo, door.x + 1, door.z + 3, door + Vector3(0, 0, 10))
	var grind: Dictionary = H.heard(bo, Vector3(0, 1, -6), "cave", 70.0)
	check(grind.get("muffled", false) and String(grind.get("words", "")).contains("behind you"), "on the island by the door, Bo hears a grinding from under the hill, muffled, behind him: \"%s\"" % grind.get("words", ""))
	mo.place_id = "isle"
	mo.set_here(true)
	put(bo, 30, -15)
	# What's going on around: the fire at night, behind her
	game.clock.set_hour(22)
	await game.wait(.2)
	var fire: Vector3 = isle.campfire.global_position
	put(mo, fire.x, fire.z + 5.0, fire + Vector3(0, 0, 20))
	var feel := m.feel()
	check(mentions(feel, "you can hear a fire crackling, behind you"), "at night she hears the fire crackling behind her: %s" % [feel.filter(func(l): return l.contains("hear"))])
	game.clock.set_hour(12)
	await game.wait(.1)
	var beach := Vector3(0, 0, 53)
	put(mo, beach.x, beach.z, Vector3(0, 0, 0))
	check(mentions(m.feel(), "waves washing on the shore, behind you"), "on the beach, facing inland, the waves are behind her")


# ---------- Voices, and sleeping through sounds ----------

func _voices_and_sleep() -> void:
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	var behind := at_side(mo, PI, 3.0)
	put(bo, behind.x, behind.z, mo.position)
	game.minds.line_said(bo, "Hey Mo, wait up.")
	check(last(m, "told") == "Bo said (behind you, close by): \"Hey Mo, wait up.\"", "Bo says something behind her: she hears it from behind: \"%s\"" % last(m, "told"))
	check(m.heard_lines.back().get("where", "") == "behind you, close by", "and that's how the line comes to her mind")
	# From inside the house, a way off: his voice, not the words
	var house: Vector3 = Level.box_of(isle.house).get_center()
	put(bo, house.x, house.z)
	bo.go_in("house")
	put(mo, house.x + 6.0, house.z + 3.0)
	game.minds.line_said(bo, "Anyone seen my goggles?")
	check(last(m, "heard").begins_with("Bo's voice, muffled") and last(m, "heard").ends_with("but not the words"), "from inside the house: \"%s\"" % last(m, "heard"))
	bo.go_out()
	put(bo, 30, -15)
	# Your voice, from where you are
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put_kid(at_side(mo, -PI / 2, 4.0).x, at_side(mo, -PI / 2, 4.0).z)
	game.minds._got_words("Mo, over here!")
	check(last(m, "told") == "Wisp said (to your right, close by): \"Mo, over here!\"", "Wisp calls from her right: \"%s\"" % last(m, "told"))
	put_kid(-6, 9)
	# Asleep: a quiet sound doesn't wake her, a loud one right by her does
	m.body.asleep = true
	m.body.tired = .5
	mo.closed = true
	mo.lie = true
	game.hearing.make(at_side(mo, 1.0, 2.5), "isle", "crunching", 4.0)
	check(m.body.asleep, "asleep, she sleeps through quiet crunching nearby")
	game.hearing.make(at_side(mo, PI, 1.5) + Vector3(0, .8, 0), "isle", "a heavy door creaking", 20.0)
	check(not m.body.asleep and last(m, "did").begins_with("woke up to a heavy door creaking, behind you"), "a door creaking right behind her wakes her: \"%s\"" % last(m, "did"))


# ---------- Touch ----------

func _touch() -> void:
	var house: Vector3 = Level.box_of(isle.house).get_center()
	var hc := Vector3(house.x, 0, house.z)
	put(bo, 30, -15)
	# Walking into the house (from the side away from Bo's boat, which sits by its wall)
	put(mo, hc.x - 4.5, hc.z + 1.0, hc)
	mo.mode = "free"
	mo.walk([[hc.x, hc.z]])
	await until(func(): return count(m, "felt", "bumped into something hard") > 0, 6)
	check(count(m, "felt", "you bumped into something hard") > 0, "she walks into the house: \"%s\"" % last(m, "felt"))
	mo.stop()
	mo.mode = "script"
	# Into Bo, standing with his back to her
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	var ahead := ahead_of(mo, 2.0)
	put(bo, ahead.x, ahead.z, ahead_of(mo, 10.0))
	mo.bump_t = 0.0
	mo.mode = "free"
	mo.walk([[ahead_of(mo, 4.0).x, ahead_of(mo, 4.0).z]])
	await until(func(): return count(m, "felt", "bumped into") > 1, 4)
	mo.stop()
	mo.mode = "script"
	check(last(m, "felt") == "you bumped into Bo", "she walks into Bo, in front of her: \"%s\"" % last(m, "felt"))
	check(last(b, "felt") == "someone bumped into you, from behind", "he, facing away, feels someone bump him from behind: \"%s\"" % last(b, "felt"))
	# A boop from behind, then from in front
	put(bo, 30, -15)
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put_kid(at_side(mo, PI, 1.0).x, at_side(mo, PI, 1.0).z)
	game._booped(mo)
	check(last(m, "felt") == "someone bumped into you, from behind", "Wisp boops her from behind: she doesn't know who: \"%s\"" % last(m, "felt"))
	put_kid(ahead_of(mo, 1.5).x, ahead_of(mo, 1.5).z)
	await game.wait(.1)
	game._booped(mo)
	check(last(m, "felt").begins_with("Wisp just bumped into you"), "from in front, she sees it's Wisp")
	put_kid(-6, 9)
	# What's underfoot
	check(m.feel().has("packed earth underfoot"), "on the path: packed earth underfoot")
	put(mo, 6, 0)
	check(m.feel().has("grass underfoot"), "on the grass: grass underfoot")
	put(mo, 0, 53)
	check(m.feel().has("soft sand underfoot"), "on the beach: soft sand underfoot")
	# Wading in, and out as far as it goes
	var wade := _wading_spot()
	put(mo, wade.x, wade.z, wade * 2.0)
	await game.wait(.3)
	check(m.body.in_water and m.body.wet_feet == 1.0 and m.feel().has("standing in water: it's cold round your ankles"), "in the shallows her feet are in the water")
	mo.bump_t = 0.0
	mo.mode = "free"
	mo.walk([[wade.x * 1.3, wade.z * 1.3]])
	await until(func(): return count(m, "felt", "too deep") > 0, 6)
	mo.stop()
	mo.mode = "script"
	check(last(m, "felt") == "the water gets deeper: too deep to go on", "wading out, it gets too deep to go on")
	put(mo, 0, 53)
	await game.wait(.2)
	check(not m.body.in_water and m.feel().has("your feet are wet"), "back on the sand, her feet are still wet")
	# Splashing at the pond: wet hands, and Bo nearby hears it
	m.body.wet_hands = 0.0
	var pond: Vector3 = isle.thing_pos("pond")
	put(mo, pond.x + 5.2, pond.z, pond)
	put(bo, pond.x + 9.0, pond.z + 2.0, pond + Vector3(30, 0, 0))
	await isle.use(mo, "pond")
	check(m.body.wet_hands == 1.0 and m.feel().has("your hands are wet"), "a hand in the pond: her hand's wet")
	check(last(b, "heard").begins_with("a splash of water, behind you"), "Bo, with his back to it, hears the splash: \"%s\"" % last(b, "heard"))
	put(bo, 30, -15)
	# Right by the fire at night: its heat
	game.clock.set_hour(22)
	await game.wait(.2)
	var fire: Vector3 = isle.campfire.global_position
	put(mo, fire.x + 1.2, fire.z + .8, fire)
	check(m.feel().has("the fire's heat on your face"), "right by the campfire she feels its heat")
	game.clock.set_hour(12)


## A spot in the shallows (ankle deep) on the south beach.
func _wading_spot() -> Vector3:
	for i in 60:
		var z := 52.0 + i * .2
		var at := Vector3(0, 0, z)
		if isle.in_water(at) and isle.bounds(at, .34, false).distance_to(at) < .01:
			return at
	return Vector3(0, 0, 60)


# ---------- Stepping on a plate under the hill ----------

func _plates_underfoot() -> void:
	for p in [mo, bo]:
		p.place_id = "cave"
		p.arriving = true
	game.travel("cave", {})
	await game.wait(.3)
	var cave: Level = game.level
	var A: Dictionary = cave.plates[0]
	put(bo, 0, 1.5, Vector3(0, 0, 10))
	put(mo, A.pos.x - .6, A.pos.z + 1.1, A.pos)
	put_kid(-1.5, 2.5)
	await game.wait(.2)
	mo.mode = "free"
	# Across it, out toward the middle of the room (the corner behind it is full of rubble)
	mo.walk([[A.pos.x + 1.6, A.pos.z - .7]])
	await until(func(): return A.by == mo, 4)
	check(A.by == mo and last(m, "felt") == "the stone under your feet sank with a heavy click", "walking across a plate, Mo feels it sink: \"%s\"" % last(m, "felt"))
	check(last(b, "heard").begins_with("a heavy stone click"), "Bo, across the room, hears the click: \"%s\"" % last(b, "heard"))
	await until(func(): return mo.path == null, 4)
	await game.wait(.2)
	check(A.by == null and last(b, "heard").begins_with("stone grinding back up"), "she walks on off it: it rises, and Bo hears that too (%s, %.2f m from it; \"%s\")" % ["up" if A.by == null else "still down", Vector2(mo.position.x - A.pos.x, mo.position.z - A.pos.z).length(), last(b, "heard")])
	mo.mode = "script"
	for p in [mo, bo]:
		p.place_id = "isle"
		p.arriving = true
	game.travel("isle", {})
	await game.wait(.3)


# ---------- The stand-in, reacting to what it hears and feels ----------

func _standin_reacts() -> void:
	# Bo bounces on the mushroom behind Mo: she hears it, turns round to look, and sees him there
	var mush: Vector3 = isle.mush.global_position
	put(bo, mush.x + 1.0, mush.z + .8, mush)
	put(mo, mush.x + 1.0, mush.z + 7.0, mush + Vector3(0, 0, 20))
	put_kid(-6, 4)
	await game.wait(.2)
	check(not m._sees(bo), "Mo has her back to Bo, by the mushroom")
	await isle.use(bo, "mushroom")
	var chose: String = await standin.react(m)
	await until(func(): return m.task.is_empty(), 5)
	check(chose == "turn", "she hears a boing behind her, and the stand-in turns her round (%s)" % chose)
	check(m._sees(bo) and mentions(m.feel(), "Bo is about"), "now she sees Bo there")
	# A splash off to her left: she turns her head
	var pond: Vector3 = isle.thing_pos("pond")
	put(mo, pond.x + 6.5, pond.z, Vector3(pond.x + 6.5, 0, pond.z - 30))
	put(bo, pond.x + 4.8, pond.z, pond)
	put_kid(pond.x + 9.0, pond.z + 4.0)
	await game.wait(.2)
	check(not m._sees(bo), "by the pond, Bo is off to her side")
	await isle.use(bo, "pond")
	chose = await standin.react(m)
	await game.wait(.3)
	check(chose.begins_with("look"), "hearing the splash beside her, she turns her head that way (%s)" % chose)
	check(m._sees(bo), "and sees Bo at the water")
	# In the water: the stand-in walks her out
	var wade := _wading_spot()
	put(mo, wade.x, wade.z, wade * 2.0)
	put_kid(wade.x + 3.0, wade.z - 6.0)
	await game.wait(.3)
	chose = await standin.react(m)
	await until(func(): return m.task.is_empty(), 10)
	check(chose == "go" and not m.body.in_water, "standing in the cold water, she walks out of it (%s)" % chose)
	put(bo, 30, -15)
