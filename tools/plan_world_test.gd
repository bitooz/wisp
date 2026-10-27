extends Node
## Plans in the real game, with no model (a stand-in plans the morning and acts on it):
##   godot --path . -- --autoplay --autoplay-script=res://tools/plan_world_test.gd --offline
## A day's plan on first start and each morning (one call per pal per morning; the game's own plan with no
## model; asleep at dawn, on waking), kept in every thought with what they're on and the next step; the
## model's replies moving it on; failures, a need that won't wait, news and dawdling calling for a rethink;
## the plan in the night's reflection, saved and loaded; and a pal acting on the plan getting where it says.
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
		calm(x)
	# The stand-in plans from the very start (the game asks for each one's first plan as it starts)
	standin = StandIn.new(game)
	game.minds.planner = standin.plan
	game.minds.quiet = true
	game.controls = false
	game.clock.stopped = true
	game.clock.set_hour(8)
	await game.wait(.5)
	await _first_plans()
	await _in_each_thought()
	await _replies()
	await _rethinks()
	await _mornings()
	await _night_and_saving()
	await _acting_on_it()
	note("FAILED" if failed else "DONE: plans")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[plans %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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


func put(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	var mind: Mind = game.minds.of(p)
	mind.task = {}
	p.go_out()
	p.stop()
	p.pace = 0.0
	p.position = Vector3(x, game.level.ground(x, z), z)
	p.mode = "script"
	p.gaze = null
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func calm(x: Mind) -> void:
	x.body.hunger = .1
	x.body.tired = .1
	x.body.cold = 0.0
	x.body.fear = 0.0
	x.body.bored = 0.0


func body_of(x: Mind) -> Dictionary:
	return game.minds.thought_body(x, "idle", {}, {jpg = ""})


# ---------- A plan to start the day ----------

func _first_plans() -> void:
	check(standin.plan_calls.mo == 1 and standin.plan_calls.bo == 1, "on starting, each makes a plan for the day: one call each")
	check(m.plans.day == m.mem.day and m.plans.made_by == "standin" and m.plans.current().text == "find out what's inside the glowing door on the hill", "Mo's day starts with what she wants most")
	check(b.plans.current().text == "find a way across to the next island", "Bo's with his")
	check(m.plans.step == "head up the path to the hill", "and a first step")
	check(m.memory.any(func(e): return e.k == "note" and String(e.s).begins_with("my plan for today: find out what's inside")), "she remembers making it")
	var got: Dictionary = standin.plan_got.mo[0]
	check(got.goals.size() == 1 and got.feel.size() >= 1 and got.bonds.size() == Folk.others("mo").size() and got.has("beliefs"), "made from her goals, how she is, how she feels about the others, what she believes")
	game.minds.plan_day(m)
	game._mornings()
	await game.wait(.1)
	check(standin.plan_calls.mo == 1, "asked again the same day: no second call")
	check(game.minds.plans_made.size() == 2 and game.minds.plans_made[0].by == "standin", "logged (WISP_PLAN)")


# ---------- In every thought ----------

func _in_each_thought() -> void:
	var one := body_of(m)
	var two := body_of(m)
	check(one.day_plan == ["(now) find out what's inside the glowing door on the hill", "(later) be home and in bed by dark"], "the day's plan goes in each thought: %s" % [one.day_plan])
	check(two.day_plan == one.day_plan and two.plan == one.plan and one.plan == "head up the path to the hill", "and stays the same from thought to thought, with the next step")
	check(one.replan == "", "no rethink due")
	var re := RegEx.create_from_string("[0-9]")
	check(one.day_plan.all(func(l): return re.search(l) == null), "words, no numbers")


# ---------- The model's replies ----------

func _replies() -> void:
	game.minds._plan_reply(m, {next = "walk up the path"})
	check(m.plans.step == "walk up the path" and m.plans.current().text.contains("glowing door"), "a new next step, still on the same thing")
	game.minds._plan_reply(m, {plan = "old-style step"})
	check(m.plans.step == "old-style step", "a reply in the old way still sets the step")
	game.minds._plan_reply(m, {day = ["something else"]})
	check(m.plans.items.size() == 2, "a new day's list when no rethink was asked for: ignored (the morning makes the plan)")
	game.minds._plan_reply(m, {activity = "done", next = "head home"})
	check(m.plans.items[0].status == "done" and m.plans.current().text == "be home and in bed by dark" and m.plans.step == "head home", "done: on to the next thing")
	# Back to a fresh plan for what follows
	m.plans.day = -1
	game.minds.plan_day(m)
	await game.wait(.1)


# ---------- Rethinks ----------

func _rethinks() -> void:
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, 3.0, 2.0)
	game.wisp_g = Vector3(-1, game.level.ground(-1, 6), 6)
	# Three tries that don't work (reaching for the sky)
	for i in 3:
		m.frame = await game.eyes.look(mo)
		m.start("pick_up", {at = [.5, .02], what = "a cloud"})
		await game.wait(.05)
	check(m.plans.replan.begins_with("three tries at"), "three tries that don't work: time to rethink (\"%s\")" % m.plans.replan)
	await game.wait(.1)
	check(m.replan_told == m.plans.replan, "they're nudged to think about it (once)")
	var body := body_of(m)
	check(body.replan == m.plans.replan, "and the next thought asks for the rest of the day")
	game.minds._plan_reply(m, {day = ["ask Bo how to get through the door", "find a light first"], next = "go over to Bo"})
	check(m.plans.replan == "" and m.plans.current().text == "ask Bo how to get through the door", "the thought rethinks it: the new plan's what she's on")
	# A rethink left alone twice: what she was on is given up
	m.plans.failed(m.mem.life_h)
	m.plans.failed(m.mem.life_h)
	m.plans.failed(m.mem.life_h)
	game.minds._plan_reply(m, {next = "hmm"})
	game.minds._plan_reply(m, {next = "hmm"})
	check(m.plans.replan == "" and m.plans.current().text == "find a light first", "asked twice to rethink and didn't: that one's given up")
	# A need that won't wait
	m.body.hunger = .6
	await game.wait(.1)
	check(m.plans.current().text == "get something to eat", "hungry: getting something to eat comes first")
	m.body.hunger = .1
	await game.wait(.1)
	check(m.plans.current().text == "find a light first", "fed: back to what she was on")
	# News
	m.remember("event", "the big stone door slid open")
	check(m.plans.replan == "something's changed: the big stone door slid open", "big news: time to rethink")
	game.minds._plan_reply(m, {day = ["go through the open door"]})
	# Dawdling: thought after thought, getting nowhere
	for i in Plans.DAWDLE_THOUGHTS:
		body_of(m)
	check(m.plans.replan.begins_with("you've been at \"go through the open door\" a while"), "thought after thought getting nowhere: she notices she's dawdling")
	game.minds._plan_reply(m, {day = ["really go through the open door"]})
	for i in Plans.DAWDLE_THOUGHTS - 2:
		body_of(m)
	await _eat_apple(m)
	for i in 4:
		body_of(m)
	check(m.plans.replan == "", "doing something real in between: not dawdling")


func _eat_apple(x: Mind) -> void:
	var isle = game.level
	for T in isle.things:
		if isle.edible(T.t) > 0:
			isle.taken(T)
			x.pal.hold(T)
			break
	x.body.hunger = .5
	x.start("eat", {})
	x.body.hunger = .1


# ---------- Mornings ----------

func _mornings() -> void:
	var day: int = m.mem.day
	var before: int = standin.plan_calls.mo
	m.morning()
	await game.wait(.1)
	check(m.mem.day == day + 1 and standin.plan_calls.mo == before + 1 and m.plans.day == m.mem.day, "a new morning: a new plan (one call)")
	var got: Dictionary = standin.plan_got.mo.back()
	check(String(got.yesterday).begins_with("did:") or String(got.yesterday).contains("didn't get to"), "made knowing how yesterday went: \"%s\"" % got.yesterday)
	# Asleep at dawn: on waking
	b.body.asleep = true
	b.body.tired = .8
	var bb: int = standin.plan_calls.bo
	b.morning()
	await game.wait(.1)
	check(standin.plan_calls.bo == bb, "Bo, asleep at dawn: no plan yet")
	b.wake("rested")
	await game.wait(.1)
	check(standin.plan_calls.bo == bb + 1 and b.plans.day == b.mem.day, "he wakes: his plan for the day")
	# No model at all: the game's own plan, no call
	game.minds.planner = Callable()
	var n: int = game.minds.plans_made.size()
	m.morning()
	await game.wait(.1)
	check(game.minds.plans_made.size() == n + 1 and game.minds.plans_made.back().by == "fallback" and m.plans.made_by == "fallback", "with no model: the game's own plan, and no call")
	check(m.plans.items.any(func(i): return i.text == "find out what's inside the glowing door on the hill"), "around what she wants most: %s" % [m.plans.items.map(func(i): return i.text)])
	game.minds.planner = standin.plan


# ---------- The night, and keeping it ----------

func _night_and_saving() -> void:
	m.plans.finish(m.mem.life_h)
	var body: Dictionary = game.minds.reflect_body(m, [])
	check(String(body.plan).begins_with("did: "), "the night's reflection gets how the day's plan went: \"%s\"" % body.plan)
	m.save()
	var saved := JSON.stringify(m.plans.to_save())
	m.load_memory()
	check(JSON.stringify(m.plans.to_save()) == saved, "saved and loaded: the plan, what she's on and her next step")
	var f = JSON.parse_string(FileAccess.get_file_as_string(m.file))
	check(f is Dictionary and f.has("plans") and int(f.plans.v) == Plans.VERSION and f.plan == m.plans.step, "in her own memory file")


# ---------- Acting on it ----------

## With the plan "find out what's inside the glowing door", a stand-in acting on what she's on gets her
## through the door, instead of wandering about the island.
func _acting_on_it() -> void:
	game.clock.set_hour(9)
	calm(m)
	m.plans.day = -1
	game.minds.planner = standin.plan
	game.minds.plan_day(m)
	await game.wait(.1)
	put(mo, 0.0, 20.0, Vector3(0, 0, 0))
	put(bo, 3.0, 22.0)
	game.wisp_g = Vector3(2, game.level.ground(2, 24), 24)
	game.controls = true
	var t0 := Time.get_ticks_msec()
	var did := []
	while mo.place_id != "cave" and Time.get_ticks_msec() - t0 < 60000:
		var x: String = await standin.follow_plan(m)
		if x != "":
			did.append(x)
		await game.wait(.5)
	await game.wait(.2)
	var x2: String = await standin.follow_plan(m)
	game.controls = false
	check(mo.place_id == "cave", "Mo, acting on her plan, heads up to the door and goes in (%.0f s): %s" % [(Time.get_ticks_msec() - t0) / 1000.0, did])
	check(x2 == "done" and m.plans.current().text == "be home and in bed by dark", "and that part of her day is done")
	mo.place_id = "isle"
	mo.arriving = false
	mo.set_here(true)
