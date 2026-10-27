extends Node
## Day and night, and bodies, in the real game, with no model (a scripted stand-in points for them):
##   godot --path . -- --autoplay --autoplay-script=res://tools/world_test.gd --offline [--shots=dir] [--no-day|--only-day]
##   (--standin-verbose prints every point the stand-in makes)
## Checks that night is dark in Mo's own eyes (and a fire or a lantern lights it), that eating, resting and
## sleeping work in the world (apples, the larder, a bed indoors, lying by the campfire; refusals when the body
## won't), what wakes a sleeper, that the dark under the hill frightens and a torch calms, that apples and the
## larder come back each morning, and (unless --no-day) a whole day lived by the stand-in for both of them.
## Prints ok:/FAIL: and exits non-zero on a failure. Screenshots and their pictures go to --shots.

const StandIn := preload("res://tools/standin.gd")

var game: Game
var args: Array = []
var shots := ""
var failed := false
var standin
var full_day := true
## Just the day (after coming back up from under the hill, as the full run does)
var only_day := false


func _ready() -> void:
	for a in args:
		if a.begins_with("--shots="):
			shots = a.substr(8)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
		if a == "--no-day":
			full_day = false
		if a == "--only-day":
			only_day = true
	if game.minds.on:
		note("FAIL: the minds are on; run with --offline (this test must not call the model)")
		get_tree().quit(2)
		return
	standin = StandIn.new(game)
	# Their memories here are the test's own (--offline keeps them in user://offline/): start them fresh
	for m in [game.minds.mo, game.minds.bo]:
		if m.file.contains("/offline/"):
			m.forget_all()
	# Nobody wanders off on their own, the clock waits for the test, and you (the kid) stand where you're put
	game.minds.quiet = true
	game.clock.stopped = true
	game.controls = false
	await game.wait(1.0)
	if only_day:
		await _dark_under_the_hill()
		await _a_day()
		note("FAILED" if failed else "DONE: a day")
		get_tree().quit(1 if failed else 0)
		return
	await _night_is_dark()
	await _axe_and_logs()
	await _eating()
	await _sleeping()
	await _resting_by_the_fire()
	await _waking()
	await _feelings()
	await _dark_under_the_hill()
	if full_day:
		await _a_day()
	note("FAILED" if failed else "DONE: day and night, and their bodies")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[world %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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


func save_frame(f: Dictionary, name: String) -> void:
	if shots != "":
		(f.image as Image).save_png(shots.path_join(name + ".png"))


## The time of day, and a moment for the sky and lights to settle.
func at_hour(h: float) -> void:
	game.clock.set_hour(h)
	game.hud.dusk = game.hud.dusk_goal
	await game.wait(.4)
	game.hud.dusk = game.hud.dusk_goal
	await game.wait(.2)


## Stand someone somewhere, facing a way, doing nothing.
func put(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	var m: Mind = game.minds.of(p)
	m.task = {}
	p.go_out()
	p.lie = false
	p.lying = 0.0
	p.stop()
	p.position = Vector3(x, game.level.ground(x, z), z)
	p.mode = "script"
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw
	p.gaze = null


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)


## How bright a picture is: mean luminance, 0 to 1.
static func brightness(img: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			sum += .2126 * c.r + .7152 * c.g + .0722 * c.b
			n += 1
	return sum / n


func last_did(m: Mind) -> String:
	for i in range(m.memory.size() - 1, -1, -1):
		if m.memory[i].k == "did":
			return m.memory[i].s
	return ""


func look(p: Pal) -> Dictionary:
	await get_tree().process_frame
	return await game.eyes.look(p)


# ---------- Night is dark ----------

func _night_is_dark() -> void:
	var isle = game.level
	var mo := game.mo
	var bo := game.bo
	# On the path halfway up to the hill: away from the fire, the house and the lantern on its stump
	put(mo, .5, 2.0, Vector3(0, 1.0, -20))
	put(bo, 30, -15)
	put_kid(-25, 30)
	await at_hour(12)
	var noon: Dictionary = await look(mo)
	var l_noon := brightness(noon.image)
	save_frame(noon, "mo-sees-noon")
	await at_hour(0)
	var night: Dictionary = await look(mo)
	var l_night := brightness(night.image)
	save_frame(night, "mo-sees-midnight")
	check(l_noon > .3, "at noon Mo sees a bright island (brightness %.3f)" % l_noon)
	check(l_night < .06 and l_night < l_noon * .15, "at midnight, away from any light, Mo's picture is dark (brightness %.3f, %.0f%% of noon)" % [l_night, 100 * l_night / l_noon])
	check(isle.light_at(mo.position) < .1 and isle.ambient_light() < .1, "at midnight there's next to no light out on the path (%.2f)" % isle.light_at(mo.position))
	# Your lantern next to her
	put_kid(.5, .4)
	await game.wait(.3)
	var lantern: Dictionary = await look(mo)
	save_frame(lantern, "mo-sees-midnight-wisps-lantern")
	var l_lantern := brightness(lantern.image)
	check(l_lantern > l_night * 1.5, "with Wisp's lantern beside her she sees more (%.3f)" % l_lantern)
	put_kid(-25, 30)
	# By the campfire, lit for the night
	var fire: Vector3 = isle.campfire.global_position
	check(isle.fire_burning(), "the campfire burns at night")
	put(mo, fire.x - 1.0, fire.z + 4.0, fire)
	await game.wait(.3)
	var by_fire: Dictionary = await look(mo)
	save_frame(by_fire, "mo-sees-midnight-campfire")
	var l_fire := brightness(by_fire.image)
	check(l_fire > l_night * 2.0, "by the campfire at midnight she can see (%.3f)" % l_fire)
	check(isle.light_at(mo.position) > .5 and isle.warmth_at(mo.position + (fire - mo.position) * .6) > .5, "by the fire there's light and warmth")
	await at_hour(12)
	check(not isle.fire_burning(), "by day the campfire is out")
	# The view, through the day
	put_kid(fire.x + 3.0, fire.z + 5.0)
	put(mo, fire.x + 1.5, fire.z + 2.5, fire)
	put(bo, fire.x + 3.0, fire.z + 2.0, fire)
	game.heading = Vector3(-.5, 0, -1).normalized()
	for h in [12.0, 18.0, 19.5, 0.0, 6.0]:
		await at_hour(h)
		await game.wait(.6)
		await shot("island-%02d%02d" % [int(h), int(fmod(h, 1.0) * 60)])
		if h == 0.0:
			check(game.hud.night > .9 and game.hud.sky_top().get_luminance() < .05, "the sky at midnight is night-dark")


# ---------- Eating ----------

func _eating() -> void:
	var isle = game.level
	var mo := game.mo
	var m: Mind = game.minds.of(mo)
	await at_hour(12)
	var apple: Dictionary = isle.thing("apple_0")
	var a0: Vector3 = Level.box_of(apple.node).get_center()
	put_kid(a0.x + 4, a0.z + 6)
	put(mo, a0.x + 1.5, a0.z + 4.5, a0)
	m.body.hunger = .7
	var at: Array = await standin.point(m, a0)
	check(not at.is_empty(), "Mo can see an apple under the big tree in her picture (at %s)" % [at])
	check(m.start("eat", {at = at, what = "the red apple"}), "pointing at it, she goes to eat it")
	await until(func(): return m.task.is_empty(), 20)
	check(is_equal_approx(m.body.hunger, .7 - isle.APPLE_FOOD), "she ate it: less hungry (%.2f)" % m.body.hunger)
	check(isle.thing("apple_0").is_empty() and not is_instance_valid(apple.node), "and the apple's gone")
	check(last_did(m) == "picked up the red apple and ate it", "she remembers: \"%s\"" % last_did(m))
	# Picked up, then eaten from her hand
	var a1: Vector3 = Level.box_of(isle.thing("apple_1").node).get_center()
	put(mo, a1.x + 1.2, a1.z + 1.2, a1)
	at = await standin.point(m, a1)
	m.start("pick_up", {at = at, what = "an apple"})
	await until(func(): return m.task.is_empty(), 15)
	check(mo.held != null and mo.held.t == "apple_1", "she picks up another one")
	var h := m.body.hunger
	check(m.start("eat", {}), "and eats what's in her hand")
	check(mo.held == null and m.body.hunger < h, "the apple in her hand is eaten")
	m.body.hunger = .7
	check(m.start("eat", {}) and last_did(m).contains("nothing to eat in my hands"), "with empty hands there's nothing to eat")
	# Full up: no room
	m.body.hunger = .05
	var a2: Vector3 = Level.box_of(isle.thing("apple_2").node).get_center()
	put(mo, a2.x + 1.2, a2.z + 1.2, a2)
	at = await standin.point(m, a2)
	m.start("eat", {at = at, what = "an apple"})
	await until(func(): return m.task.is_empty(), 15)
	check(last_did(m).contains("I'm full") and not isle.thing("apple_2").is_empty(), "full up, she can't eat another (it stays where it is)")
	# Pointing at something you can't eat
	m.body.hunger = .7
	var pond: Vector3 = isle.thing_pos("pond")
	put(mo, pond.x + 2, pond.z + 7, pond)
	at = await standin.point(m, pond)
	m.start("eat", {at = at, what = "the pond"})
	await until(func(): return m.task.is_empty(), 20)
	check(last_did(m).contains("nothing there I could eat") and m.body.hunger == .7, "there's nothing to eat at the pond")
	# A meal at home
	var house: Vector3 = Level.box_of(isle.house).get_center()
	put(mo, house.x + 5, house.z + 7, house)
	put_kid(house.x + 7, house.z + 9)
	at = await standin.point(m, house)
	check(m.start("eat", {at = at, what = "our house"}), "hungry, she heads home to eat")
	await until(func(): return mo.inside == "house", 20)
	check(mo.inside == "house", "she goes in")
	await game.wait(.3)
	var H = isle.homes.house
	check(mo.inner.visible and H.contains(mo.position) and mo.lift == 0.0, "and is seen in the room, at the table")
	check(not m.start("go", {at = [.5, .5]}), "busy indoors, she isn't deciding anything")
	await until(func(): return m.task.is_empty(), 20)
	check(mo.inside == "" and mo.inner.visible and m.body.hunger < .2, "and comes out fed (%.2f)" % m.body.hunger)
	check(isle.larder == isle.LARDER - 1 and last_did(m).contains("larder"), "the larder has one meal fewer: \"%s\"" % last_did(m))
	isle.larder = 0
	m.body.hunger = .7
	at = await standin.point(m, house)
	m.start("eat", {at = at, what = "our house"})
	await until(func(): return m.task.is_empty() and mo.inside == "", 25)
	check(last_did(m).contains("bare") and m.body.hunger > .69, "once it's all eaten, there's nothing left in the larder")


# ---------- Bo's chore: the axe, the woodpile, a log for the fire ----------

func _axe_and_logs() -> void:
	var isle = game.level
	var bo := game.bo
	var m: Mind = game.minds.of(bo)
	await at_hour(11)
	var axe: Vector3 = Level.box_of(isle.thing("axe").node).get_center()
	put_kid(axe.x + 4, axe.z + 5)
	put(bo, axe.x + 1.4, axe.z + 1.6, axe)
	var at: Array = await standin.point(m, axe)
	check(not at.is_empty(), "Bo can see the axe in the chopping block")
	m.start("pick_up", {at = at, what = "the axe"})
	await until(func(): return m.task.is_empty(), 15)
	check(bo.held != null and bo.held.t == "axe", "he picks up the axe: \"%s\"" % last_did(m))
	var wood: int = isle.wood
	var pile: Vector3 = Level.box_of(isle.woodpile).get_center()
	put(bo, pile.x + 1.6, pile.z + 1.4, pile)
	m.skills.level.chopping = 1.0
	at = await standin.point(m, pile)
	m.start("use", {at = at, what = "the woodpile"})
	await until(func(): return m.task.is_empty(), 15)
	check(isle.wood > wood and last_did(m).contains("axe"), "and chops wood with it: %d -> %d, \"%s\"" % [wood, isle.wood, last_did(m)])
	# Put the axe down, and carry a log to the fire
	var A: Dictionary = bo.let_go()
	isle.put_down(A, bo.position + Vector3(-3.0, 0, 2.0))
	var logs: Array = isle.things.filter(func(T): return String(T.t).begins_with("log_"))
	check(logs.size() >= 1, "there are split logs lying by the block (%d)" % logs.size())
	var lg: Vector3 = Level.box_of(logs[0].node).get_center()
	put(bo, lg.x + 1.0, lg.z + 1.2, lg)
	at = await standin.point(m, lg)
	m.start("pick_up", {at = at, what = "a log"})
	await until(func(): return m.task.is_empty(), 15)
	check(bo.held != null and String(bo.held.t).begins_with("log_"), "he picks up a log: \"%s\"" % last_did(m))
	var fire: Vector3 = Level.box_of(isle.campfire).get_center()
	put(bo, fire.x + 1.6, fire.z + 1.6, fire)
	wood = isle.wood
	at = await standin.point(m, fire)
	m.start("use", {at = at, what = "the campfire"})
	await until(func(): return m.task.is_empty(), 15)
	check(bo.held == null and isle.wood == wood + 1, "and lays it by the fire pit: \"%s\"" % last_did(m))
	# Next morning the axe is back in its block
	isle.new_day()
	var back: Vector3 = Level.box_of(isle.thing("axe").node).get_center()
	var bc: Vector3 = isle.block.global_position
	check(Vector2(back.x - bc.x, back.z - bc.z).length() < .5 and back.y > bc.y, "next morning the axe is back in the block (%.2f m off)" % Vector2(back.x - bc.x, back.z - bc.z).length())


# ---------- Sleeping ----------

func _sleeping() -> void:
	var isle = game.level
	var bo := game.bo
	var m: Mind = game.minds.of(bo)
	var house: Vector3 = Level.box_of(isle.house).get_center()
	await at_hour(21)
	put(bo, house.x + 6, house.z + 6, house)
	put_kid(house.x + 8, house.z + 8)
	m.body.tired = .3
	m.body.hunger = .3
	m.body.cold = 0
	m.body.fear = 0
	check(m.start("sleep", {}) and not m.body.asleep and last_did(m).contains("not sleepy"), "not sleepy at nine: Bo can't get to sleep")
	m.body.tired = .8
	var at: Array = await standin.point(m, house)
	check(m.start("sleep", {at = at, what = "our house"}), "tired, he goes to bed")
	await until(func(): return m.body.asleep, 20)
	check(m.body.asleep and bo.inside == "house" and bo.closed, "he's gone in, asleep: \"%s\"" % last_did(m))
	await game.wait(1.2)
	check(bo.inner.visible and isle.homes.house.contains(bo.position) and bo.lift > 0 and bo.lying > .9, "and lies in his bed in the room")
	check(not m.start("go", {at = [.5, .5]}), "asleep, he decides nothing")
	check(m.feel().is_empty() or not m.feel().any(func(l): return l.contains("hungry")), "asleep, he feels nothing")
	# The night goes by, an hour a second
	game.clock.rate = 1.0
	game.clock.stopped = false
	var woke := await until(func(): return not m.body.asleep, 20)
	game.clock.stopped = true
	game.clock.rate = 24.0 / (Clock.DAY_MINUTES * 60.0)
	check(woke and game.clock.hour() > 5.5 and game.clock.hour() < 8.0, "he sleeps through the night and wakes in the morning (%.2f o'clock)" % game.clock.hour())
	check(m.body.tired < .12 and last_did(m) == "woke up feeling rested", "rested: \"%s\"" % last_did(m))
	check(bo.inside == "" and bo.inner.visible and bo.position.distance_to(isle.shelter("house").door) < .5, "and comes out of the door")
	check(m.body.feel().any(func(l): return l.contains("rested")) , "he feels rested: %s" % [m.body.feel()])
	# A new morning: the apples are back, the larder's full
	check(not isle.thing("apple_0").is_empty() and not isle.thing("apple_1").is_empty() and isle.larder == isle.LARDER, "morning: new apples under the tree, the larder full again")


# ---------- Resting by the fire ----------

func _resting_by_the_fire() -> void:
	var isle = game.level
	var mo := game.mo
	var m: Mind = game.minds.of(mo)
	await at_hour(23)
	var fire: Vector3 = isle.campfire.global_position
	put(mo, fire.x - 2.0, fire.z + 6.0, fire)
	put_kid(fire.x + 4, fire.z + 6)
	m.body.cold = .7
	m.body.tired = .5
	m.body.hunger = .2
	var spot: Vector3 = fire + (mo.position - fire).normalized() * 2.0
	spot.y = isle.ground(spot.x, spot.z)
	var at: Array = await standin.point(m, spot)
	check(m.start("rest", {at = at, what = "the grass by the fire"}), "cold at night, Mo goes to lie by the campfire")
	await until(func(): return m.task.get("phase", "") == "rest", 20)
	await game.wait(1.2)
	check(mo.lie and mo.lying > .99 and m.body.resting, "she lies down by it")
	check(isle.warmth_at(mo.position) > .5, "where she lies, the fire's warm (%.2f)" % isle.warmth_at(mo.position))
	var tired := m.body.tired
	game.clock.rate = .25
	game.clock.stopped = false
	await game.wait(6.0)
	game.clock.stopped = true
	check(m.body.cold < .2, "an hour and a half there, she's warm again (%.2f)" % m.body.cold)
	check(m.body.tired < tired, "and a little rested (%.2f from %.2f)" % [m.body.tired, tired])
	check(m.start("wait", {}) and mo.lie, "waiting, she stays lying there")
	check(m.start("wave", {}) and not mo.lie and m.task.is_empty(), "doing something else, she gets up")
	await shot("mo-rested-by-the-fire")


# ---------- What wakes them ----------

func _waking() -> void:
	var isle = game.level
	var mo := game.mo
	var bo := game.bo
	var m: Mind = game.minds.of(mo)
	var b: Mind = game.minds.of(bo)
	await at_hour(23)
	var fire: Vector3 = isle.campfire.global_position
	put(mo, fire.x - 1.8, fire.z + 1.0, fire)
	put_kid(fire.x + 3, fire.z + 4)
	m.body.tired = .8
	m.body.cold = .1
	check(m.start("sleep", {}) and m.body.asleep and mo.lie, "by the fire, Mo falls asleep on the ground")
	await game.wait(1.2)
	await shot("mo-asleep-by-the-fire")
	game._booped(mo)
	check(not m.body.asleep and not mo.closed and last_did(m).begins_with("woke up"), "a boop wakes her: \"%s\"" % last_did(m))
	# On the cold ground, far from the fire: the cold wakes you
	put(bo, .5, 2.0)
	put_kid(-25, 30)
	b.body.tired = .8
	b.body.cold = 0
	b.body.hunger = .2
	b.body.fear = 0
	b.start("sleep", {})
	check(b.body.asleep, "Bo falls asleep out on the path")
	game.clock.rate = 1.0
	game.clock.stopped = false
	await until(func(): return not b.body.asleep, 10)
	game.clock.stopped = true
	game.clock.rate = 24.0 / (Clock.DAY_MINUTES * 60.0)
	check(not b.body.asleep and last_did(b) == "woke up shivering with cold", "out in the night air he's woken by the cold: \"%s\"" % last_did(b))


# ---------- What they feel ----------

func _feelings() -> void:
	var m: Mind = game.minds.of(game.mo)
	await at_hour(20.5)
	put(game.mo, .5, 2.0)
	put_kid(-25, 30)
	m.body.hunger = .65
	m.body.tired = .2
	m.body.cold = .6
	m.body.fear = 0
	m.body.bored = 0
	m.body.since_ate = 9
	m.body.since_woke = 9
	var f := m.feel()
	note("Mo feels: %s" % [f])
	check(f.has("hungry: your tummy is rumbling") and f.has("cold: you're shivering") and f.has(game.clock.sense()), "her hunger, the cold and the time of day come to her as feelings")
	var body_lines: Array = m.body.feel()
	check(body_lines.all(func(l): return RegEx.create_from_string("[0-9]").search(l) == null), "none of them is a number")


# ---------- Under the hill ----------

func _dark_under_the_hill() -> void:
	for p in [game.mo, game.bo]:
		p.place_id = "cave"
		p.arriving = true
	game.travel("cave", {})
	await game.wait(.5)
	var cave: Level = game.level
	var m: Mind = game.minds.of(game.mo)
	put(game.mo, 4.5, -3.5, Vector3(0, 0, -4))
	put(game.bo, -4.0, -3.0)
	put_kid(-4.5, 3.3)
	m.body.fear = 0
	check(cave.light_at(game.mo.position) < .05, "in a corner under the hill there's no light (%.2f)" % cave.light_at(game.mo.position))
	await game.wait(15.0)
	check(m.body.fear > .55, "fifteen seconds alone in the dark: Mo's scared (%.2f)" % m.body.fear)
	check(m.feel().any(func(l): return l.begins_with("scared") or l.begins_with("terrified")), "and feels it")
	var T: Dictionary = cave.thing("torch")
	cave.taken(T)
	game.mo.hold(T)
	await game.wait(15.0)
	check(m.body.fear < .2, "with the torch in her hand, she calms down (%.2f)" % m.body.fear)
	game.mo.recoil = 3.0
	await game.wait(.1)
	check(m.body.fear > .4, "something lunging at her is a fright (%.2f)" % m.body.fear)
	game.mo.recoil = 0
	# Back out, as you were
	var held: Dictionary = game.mo.let_go()
	cave.put_down(held, Vector3(-1.9, 0, .9))
	for p in [game.mo, game.bo]:
		p.place_id = "isle"
		p.arriving = true
	# Back up the steps: out of the door in the hill, at whatever time it is
	game.travel("isle", {back = true})
	await game.wait(.5)
	check(game.wisp_g.distance_to(Vector3(0, game.wisp_g.y, -23)) < 1.5 and game.level.dusk_t == game.clock.twilight(), "back up on the island at the door, in the light of the hour it is")


# ---------- A whole day ----------

## A day, an hour every ten seconds, with the stand-in looking after both of them from the morning: they eat,
## warm up and sleep when their bodies want, and are up again the next morning.
func _a_day() -> void:
	await at_hour(7)
	for p in [game.mo, game.bo]:
		var m: Mind = game.minds.of(p)
		m.body = Body.new(p.id)
		m.task = {}
		p.go_out()
		p.lie = false
		p.mode = "follow"
	game.controls = true
	game.idle_t = 100.0
	game.clock.rate = .1
	game.clock.stopped = false
	var start: float = game.clock.t
	# What they did before today isn't today's
	var before := {mo = game.minds.mo.mem.next_id, bo = game.minds.bo.mem.next_id}
	var slept := {mo = false, bo = false}
	var ate := {mo = 0, bo = 0}
	var woke := {mo = false, bo = false}
	var worst := {}
	var next := 0.0
	var shots_at := [12.0, 20.0, 1.0]
	while game.clock.t < start + 24.5:
		await get_tree().process_frame
		game.idle_t = 100.0
		for p in [game.mo, game.bo]:
			var m: Mind = game.minds.of(p)
			if m.body.asleep:
				slept[p.id] = true
			elif slept[p.id] and last_did(m).begins_with("woke up"):
				woke[p.id] = true
			for k in ["hunger", "tired", "cold", "fear"]:
				worst["%s %s" % [p.id, k]] = maxf(worst.get("%s %s" % [p.id, k], 0.0), m.body.get(k))
		if game.clock.t > next:
			next = game.clock.t + .25
			for p in [game.mo, game.bo]:
				await standin.decide(game.minds.of(p))
		if shots_at.size() and game.clock.hour() >= shots_at[0] and game.clock.hour() < shots_at[0] + 1:
			await shot("day-%02d" % int(shots_at.pop_front()))
	game.clock.stopped = true
	for e in standin.log:
		if e[2] == "eat":
			ate[e[1]] += 1
	note("the stand-in chose: %s" % [standin.log.map(func(e): return "%s %s %s (%s)" % [_clock_str(e[0]), e[1], e[2], e[3]])])
	note("the worst each need got: %s" % [worst])
	for id in ["mo", "bo"]:
		var m: Mind = game.minds.of(game.mo if id == "mo" else game.bo)
		var today: Array = m.memory.filter(func(x): return int(x.id) >= before[id])
		var meals := today.filter(func(x): return x.k == "did" and (String(x.s).contains("ate it") or String(x.s).begins_with("ate ") or String(x.s).contains("from the larder")))
		check(meals.size() >= 1, "%s ate during the day (%d times)" % [id, meals.size()])
		check(slept[id] and woke[id], "%s slept at night and was up again in the morning" % id)
		var wakings := today.filter(func(x): return x.k == "did" and String(x.s).begins_with("woke up"))
		check(wakings.size() == 1, "%s slept the night through (woke %d times: %s)" % [id, wakings.size(), wakings.map(func(x): return x.s)])
		check(worst["%s hunger" % id] < .9 and worst["%s cold" % id] < .85, "%s never starved or froze" % id)


static func _clock_str(t: float) -> String:
	var h := fposmod(t, 24.0)
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60)]
