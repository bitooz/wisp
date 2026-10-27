extends Node
## Their own lives in the real game, and coming back to it, with no model (a stand-in reflects and plans):
##   godot --path . -- --autoplay --autoplay-script=res://tools/life_world_test.gd --offline [--shots=dir]
## Their things in the world (woodpile, model boat, shell jar, shells on the beach) and their chores and hobbies
## changing them; the campfire burning wood; then the island saved and opened again after twenty minutes, a
## day and a week: the time passed, the world and both of them caught up, where their day has them, what they
## remember (and can tell), a line saying how long it's been, and never more than one reflection and one
## morning plan each. Prints ok:/FAIL:, exits non-zero on a failure.

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
	check(game.world_file().contains("/offline/"), "the island's file is the test's own too (%s)" % game.world_file())
	standin = StandIn.new(game)
	game.minds.planner = standin.plan
	game.minds.reflector = standin.reflect
	game.minds.quiet = true
	game.controls = false
	game.clock.stopped = true
	game.clock.set_hour(9)
	isle = game.level
	await game.wait(.5)
	await _their_things()
	await _chores_and_hobbies()
	await _the_fire()
	await _coming_back()
	note("FAILED" if failed else "DONE: their own lives")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[life %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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


func shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


func put(p: Pal, at: Vector3, face_to := Vector3.INF) -> void:
	var mind: Mind = game.minds.of(p)
	mind.task = {}
	mind.body.asleep = false
	p.closed = false
	p.go_out()
	p.stop()
	p.position = Vector3(at.x, game.level.ground(at.x, at.z), at.z)
	p.mode = "script"
	p.gaze = null
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func last(x: Mind, kind: String) -> String:
	for i in range(x.memory.size() - 1, -1, -1):
		if x.memory[i].k == kind:
			return x.memory[i].s
	return ""


## How many logs the woodpile shows (it's drawn as one mesh: island.gd keeps the count it was made from)
func logs() -> int:
	return int(isle._logs.get_meta("logs", -1))


func jar_shells() -> int:
	return isle._jar_shells.get_children().filter(func(c): return not c.is_queued_for_deletion()).size()


func boat_parts() -> int:
	return isle._boat_parts.filter(func(n): return n.visible).size()


## A view of the house, the boat and the jar, and the woodpile by the fire.
func look_at_home() -> void:
	var at: Vector3 = isle.house.to_global(Vector3(2.0, 0, 7.0))
	game.wisp_g = Vector3(at.x, isle.ground(at.x, at.z), at.z)
	game.kid.position = game.wisp_g
	var to: Vector3 = isle.house.to_global(Vector3(.5, 0, 2.0))
	game.heading = Vector3(to.x - at.x, 0, to.z - at.z).normalized()
	game.az = atan2(-game.heading.x, -game.heading.z)
	game.pol = 1.0
	await game.wait(.8)


# ---------- Their things ----------

func _their_things() -> void:
	check(isle.wood == 6 and logs() == 6, "Bo's woodpile, by the campfire: six logs")
	check(isle.boat_k == 0.0 and boat_parts() == 1, "his model boat, on its trestle: just a keel")
	check(isle.jar_n == 0 and jar_shells() == 0, "Mo's shell jar on the step: empty")
	check(isle.things.filter(func(T): return String(T.t).begins_with("shell")).size() == 3, "three shells on the beach")
	await look_at_home()
	await shot("home-at-the-start")


# ---------- Chores and hobbies, as they happen ----------

func _chores_and_hobbies() -> void:
	game.wisp_g = Vector3(-30, isle.ground(-30, 30), 30)
	game.kid.position = game.wisp_g
	# Bo chops wood (Mo nearby hears it)
	var wp: Vector3 = isle.woodpile.position
	put(bo, wp + Vector3(-.6, 0, 2.2), wp)
	put(mo, wp + Vector3(6.0, 0, 3.0), wp + Vector3(20, 0, 20))
	var at: Array = await standin.point(b, Level.box_of(isle.woodpile).get_center())
	b.start("use", {at = at, what = "the woodpile"})
	await until(func(): return b.task.is_empty(), 10)
	check(isle.wood == 7 and logs() == 7 and last(b, "did").begins_with("chopped some wood"), "Bo chops wood: one more log on the pile (\"%s\")" % last(b, "did"))
	check(last(m, "heard").begins_with("the thock of an axe on wood"), "Mo hears it: \"%s\"" % last(m, "heard"))
	# Bo works on his boat
	var bt: Vector3 = Level.box_of(isle.boat).get_center()
	put(bo, isle.life_spot("bo", "hobby"), bt)
	for i in 3:
		at = await standin.point(b, bt)
		b.start("use", {at = at, what = "my boat"})
		await until(func(): return b.task.is_empty(), 10)
	check(is_equal_approx(isle.boat_k, .3) and boat_parts() == 2 and last(b, "did") == "worked on my model boat" or last(b, "did").contains("taking shape"), "three goes at his boat: the hull's taking shape (%s)" % Life.boat_words(isle.boat_k))
	put(mo, bt + Vector3(-1.2, 0, 2.0), bt)
	at = await standin.point(m, bt)
	m.start("use", {at = at, what = "Bo's boat"})
	await until(func(): return m.task.is_empty(), 10)
	check(last(m, "did").begins_with("had a look at Bo's model boat") and is_equal_approx(isle.boat_k, .3), "Mo only has a look (it's his): \"%s\"" % last(m, "did"))
	# Mo finds a shell on the beach and puts it in her jar
	var shell: Dictionary = isle.thing("shell_0")
	var sp: Vector3 = Level.box_of(shell.node).get_center()
	put(mo, sp + Vector3(1.0, 0, -1.2), sp)
	at = await standin.point(m, sp)
	m.start("pick_up", {at = at, what = "a pink shell"})
	await until(func(): return m.task.is_empty(), 10)
	check(mo.held != null and String(mo.held.t).begins_with("shell"), "Mo picks up a shell on the beach")
	var jp: Vector3 = Level.box_of(isle.jar).get_center()
	put(mo, isle.house.to_global(Vector3(.9, 0, isle.homes.house.d / 2 + 1.3)), jp)
	at = await standin.point(m, jp)
	m.start("use", {at = at, what = "my jar"})
	await until(func(): return m.task.is_empty(), 10)
	check(isle.jar_n == 1 and jar_shells() == 1 and mo.held == null and last(m, "did").begins_with("put the shell in my jar"), "and puts it in her jar: \"%s\"" % last(m, "did"))
	# Mo's chore: an apple for the larder
	var larder: int = isle.larder
	var apple: Dictionary = isle.thing("apple_0")
	isle.taken(apple)
	mo.hold(apple)
	apple.what = "an apple"
	var hc: Vector3 = Level.box_of(isle.house).get_center()
	put(mo, isle.homes.house.door_at(1.4), hc)
	at = await standin.point(m, hc)
	m.start("use", {at = at, what = "our house"})
	await until(func(): return m.task.is_empty(), 10)
	check(isle.larder == larder + 1 and last(m, "did") == "went in and put an apple in the larder", "her chore: an apple into the larder")


# ---------- The campfire burns wood ----------

func _the_fire() -> void:
	var wood: int = isle.wood
	game.clock.set_hour(18)
	await game.wait(.2)
	check(isle.fire_burning() and isle.wood == wood - 1 and logs() == wood - 1, "the evening's fire takes a log from the pile")
	game.clock.set_hour(23)
	await game.wait(.1)
	check(isle.fire_burning() and isle.wood == wood - 1, "and burns the night on that one")
	isle.wood = 0
	isle._show_wood()
	game.clock.t += 24.0
	game.clock.set_hour(19)
	await game.wait(.2)
	check(not isle.fire_burning(), "no wood the next evening: no fire")
	isle.wood = wood - 1
	isle._show_wood()
	game.clock.set_hour(9)
	await game.wait(.2)


# ---------- Closing the game, and coming back ----------

## Save as if closing the game `ago` real seconds ago, then open it again.
func reopen(ago: float) -> Dictionary:
	game.save_world()
	var f = JSON.parse_string(FileAccess.get_file_as_string(game.world_file()))
	f.saved = float(f.saved) - ago
	var w := FileAccess.open(game.world_file(), FileAccess.WRITE)
	w.store_string(JSON.stringify(f))
	w.close()
	for x in [m, b]:
		x.save()
	var r: Dictionary = game.reopen_world()
	game.minds._first_plans()
	await game.wait(.3)
	return r


func _coming_back() -> void:
	game.clock.set_hour(9)
	put(mo, Vector3(.5, 0, 2.0))
	put(bo, Vector3(3.0, 0, 2.0))
	await look_at_home()
	var reflects := {mo = standin.reflect_calls.mo, bo = standin.reflect_calls.bo}
	var plans := {mo = standin.plan_calls.mo, bo = standin.plan_calls.bo}
	var day0: int = m.mem.day
	# Twenty minutes away: twenty hours, into the night
	var r := await reopen(20 * 60.0)
	check(absf(r.hours - 20.0) < .01 and absf(game.clock.hour() - 5.0) < .01, "closed for twenty minutes at nine in the morning: it's five the next morning on the island")
	check(game.hud.banner == "Later that night", "a line says so: \"%s\"" % game.hud.banner)
	check(m.body.asleep and mo.inside == "house" and b.body.asleep and bo.inside == "house", "they're both asleep in the house")
	check(last(m, "event") == "Wisp was gone for a bit, and now Wisp's back", "Mo knows Wisp's been away")
	check(m.memory.any(func(e): return String(e.s).begins_with("found") and String(e.s).contains("for my jar")) and b.memory.any(func(e): return String(e.s).begins_with("worked on my model boat")), "and they remember their afternoon: shells, the boat")
	check(standin.reflect_calls.mo - reflects.mo == 0 and standin.plan_calls.mo - plans.mo == 0, "no morning yet: no reflection or plan called for")
	check(r.ms < 200.0, "it took %.1f ms" % r.ms)
	# Up for the day
	m.wake("rested")
	b.wake("rested")
	await game.wait(.2)
	reflects = {mo = standin.reflect_calls.mo, bo = standin.reflect_calls.bo}
	plans = {mo = standin.plan_calls.mo, bo = standin.plan_calls.bo}
	# A day away (in real time)
	var wood_before: int = isle.wood
	r = await reopen(86400.0)
	check(r.days >= 1 and game.hud.banner == Life.gap_words(r.hours, r.days, game.clock.hour()), "closed for a day: \"%s\" (%.1f island hours)" % [game.hud.banner, r.hours])
	check(standin.reflect_calls.mo - reflects.mo == 1 and standin.reflect_calls.bo - reflects.bo == 1, "one reflection each on the days away")
	check(standin.plan_calls.mo - plans.mo <= 1 and standin.plan_calls.bo - plans.bo <= 1, "and at most one morning plan each")
	await look_at_home()
	# A week away
	reflects = {mo = standin.reflect_calls.mo, bo = standin.reflect_calls.bo}
	plans = {mo = standin.plan_calls.mo, bo = standin.plan_calls.bo}
	var jar_before: int = isle.jar_n
	var boat_before: float = isle.boat_k
	var day1: int = m.mem.day
	# Left at three in the afternoon, a week ago
	if m.body.asleep:
		m.wake("rested")
	if b.body.asleep:
		b.wake("rested")
	await game.wait(.2)
	game.clock.set_hour(15)
	reflects = {mo = standin.reflect_calls.mo, bo = standin.reflect_calls.bo}
	plans = {mo = standin.plan_calls.mo, bo = standin.plan_calls.bo}
	r = await reopen(7 * 86400.0)
	check(r.days >= 7 and m.mem.day - day1 == r.days, "closed for a week: %d island days" % r.days)
	check(game.hud.banner == "A week later", "\"%s\"" % game.hud.banner)
	check(standin.reflect_calls.mo - reflects.mo == 1 and standin.reflect_calls.bo - reflects.bo == 1 and standin.plan_calls.mo - plans.mo <= 1 and standin.plan_calls.bo - plans.bo <= 1, "still only one reflection and at most one plan each, for the whole week")
	check(isle.jar_n > jar_before and jar_shells() == mini(isle.jar_n, 16) and isle.boat_k > boat_before and boat_parts() >= 3 and logs() == isle.wood, "the world shows the week: Mo's jar has %s, Bo's boat: %s, %d logs on the pile" % [isle.jar_words(), Life.boat_words(isle.boat_k), isle.wood])
	var now: String = r.now.mo
	if now == "sleep":
		check(mo.inside == "house" and m.body.asleep, "Mo's asleep in the house (it's %s)" % game.clock.sense())
	else:
		check(mo.inside == "" and mo.position.distance_to(isle.life_spot("mo", now)) < 1.0, "Mo's where her day has her (%s, %s)" % [now, game.clock.sense()])
	check(last(m, "event") == "Wisp was gone for about a week, and now Wisp's back", "\"%s\"" % last(m, "event"))
	if m.body.asleep:
		m.wake("rested")
	if b.body.asleep:
		b.wake("rested")
	await game.wait(.2)
	var told := m.memory_lines(m.on_mind("what did you do while Wisp was away"))
	check(told.any(func(l): return l.contains("much as usual")) and told.any(func(l): return l.contains("shells")), "asked what she's been up to, it comes to mind: the days much as usual, the shells")
	check(r.ms < 200.0, "a week caught up in %.1f ms" % r.ms)
	await look_at_home()
	await shot("home-a-week-later")
	# A year
	r = await reopen(365 * 86400.0)
	check(game.hud.banner == "A long time later" and r.ms < 200.0 and standin.reflect_calls.mo - reflects.mo <= 2, "a year: \"%s\", %.1f ms, still a reflection and a plan at most" % [game.hud.banner, r.ms])
	check(isle.boat_k == 1.0 and boat_parts() == 5, "Bo's boat finished and painted")
	await shot("home-a-year-later")
