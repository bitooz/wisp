extends Node
## The island's other people in the real game, with no model (a stand-in acts for whoever needs to):
##   godot --path . -- --autoplay --autoplay-script=res://tools/folk_world_test.gd --offline [--shots=dir] [--only=a,b]
## Nell, Tam and Odo live on the island: each has a home, goes about their own day (work, meals at home, the
## campfire of an evening, bed), has the same mind as Mo and Bo (memory, mood, plans, body, skills, body
## language), and wants something. Two people together pass on what they know: a story goes from one to the
## next, changing a little each time and carrying who told whom, and it shapes how they feel and what they mean to
## do. Someone's want becomes Mo's quest: she finds Nell's float and gives it to her (the stand-in pointing for
## her), and the news goes round. Then what they all cost a frame. Prints ok:/FAIL:, exits non-zero on a failure.

const StandIn := preload("res://tools/standin.gd")

var game: Game
var args: Array = []
var shots := ""
var only := []
var failed := false
var standin
var mo: Pal
var bo: Pal
var m: Mind
var b: Mind
var isle
var folk := {}
var fm := {}


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
	for x in game.minds.all():
		if not x.file.contains("/offline/"):
			note("FAIL: the minds' memories aren't the test's own (%s)" % x.file)
			get_tree().quit(2)
			return
		x.forget_all()
	for p in game.folk:
		folk[p.id] = p
		fm[p.id] = game.minds.of(p)
	standin = StandIn.new(game)
	game.minds.planner = standin.plan
	game.minds.reflector = standin.reflect
	game.minds.quiet = true
	game.minds.ears.muted = true
	game.controls = false
	game.clock.stopped = true
	game.clock.set_hour(9)
	isle = game.level
	for x in game.minds.folk:
		x.back_to_day()
	await game.wait(.5)
	for s in ["who", "homes", "days", "gossip", "quest", "in_a_thought", "cost"]:
		if only.is_empty() or only.has(s):
			await call("_" + s)
	note("FAILED" if failed else "DONE: the island's people")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[folk %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)
	game.kid.position = game.wisp_g


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


func shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


## The camera on a point, from a direction (az), at a distance.
func look(at: Vector3, az: float, dist: float, pol := 1.4) -> void:
	game.cam_focus = {p = at, dist = dist}
	game.az = az
	game.az_goal = null
	game.pol = pol
	game.aim(0.0, true)
	await get_tree().process_frame
	game.aim(0.0, true)


## A close look at p's face: the camera in front of it (whichever way the head's turned), cut down to the head.
func face_shot(p: Pal, name: String) -> void:
	var at: Node3D = p.mug.at
	var c0: Vector3 = at.global_transform * (p.mug.bind * Vector3(0, p.mug.F.mouth.y + .03, .05))
	var c1: Vector3 = at.global_transform * (p.mug.bind * Vector3(0, p.mug.F.mouth.y + .03, .15))
	var fwd := (c1 - c0).normalized()
	await look(c0, atan2(fwd.x, fwd.z), .5 * p.size.y, clampf(acos(fwd.y), 1.6, 2.3))
	await game.wait(.2)
	await cut(name, c0, .7, .7, 420)


# ---------- Who they are ----------

func _who() -> void:
	check(game.folk.size() >= 3 and game.minds.folk.size() == game.folk.size(), "%d islanders on the island, each with a mind of their own" % game.folk.size())
	var ok := true
	for w in folk:
		var x: Mind = fm[w]
		if x.mem == null or x.heart == null or x.plans == null or x.body == null or x.skills == null or x.secrets == null or x.news == null:
			ok = false
	check(ok, "the same mind as Mo and Bo: memory, mood and feelings, plans, a body, skills, secrets, news")
	check(fm.nell.memory.any(func(e): return String(e.s).contains("lucky float")) and fm.nell.news.knows(Gossip.id_of("want", "", "nell")), "Nell remembers losing her float, and it's hers to tell")
	check(folk.nell.size.y > 1.2 and folk.odo.model_id == "bo" and folk.tam.skin.get_shader_parameter("hue") != 0.0, "grown-up bodies from Mo's and Bo's, in their own colours")
	# Line them up by the house for a look
	put(folk.nell, -2.4, 7.0, Vector3(-.6, 0, 11.0))
	put(folk.tam, -.6, 7.0, Vector3(-.6, 0, 11.0))
	put(folk.odo, 1.2, 7.0, Vector3(-.6, 0, 11.0))
	put(mo, -3.8, 7.4, Vector3(-.6, 0, 11.0))
	put(bo, 2.6, 7.4, Vector3(-.6, 0, 11.0))
	put_kid(-.6, 13.0)
	await look(Vector3(-.6, game.level.ground(-.6, 7.0) + .9, 7.0), 0.0, 6.0, 1.45)
	await game.wait(.8)
	await cut("everyone", Vector3(-.6, game.level.ground(-.6, 7.0) + .85, 7.0), 1.6, .8, 900)
	for w in folk:
		await face_shot(folk[w], "face_%s" % w)
	check(folk.nell.mug.at.visible and fm.nell.with_who() != null, "with faces, and eyes for whoever they're with")


# ---------- Homes ----------

func _homes() -> void:
	var ok := true
	for w in folk:
		var home: Dictionary = isle.shelter("hut_" + w)
		if home.is_empty() or not isle.places.has(Folk.HOME[w].what):
			ok = false
	check(ok, "each has a home of their own (a place anyone can head for by name: %s)" % ", ".join(Folk.IDS.map(func(w): return Folk.HOME[w].what)))
	var hut: Node3D = isle.huts.nell
	await look(hut.global_position + Vector3(0, 1.0, 0), hut.rotation.y + .5, 9.0, 1.3)
	await game.wait(.4)
	await shot("nells_hut")
	# Places as they call them (round 18's runs, with the model: these all came back "I don't know the way")
	var said := {"south beach": "the beach in the south", "campfire": "the campfire", "village woodpile": "the woodpile",
		"campfire by the house": "the campfire", "the big tree": "the big tree", "house": "the house in the village",
		"Tam's cottage door": "Tam's cottage", "glowing door": "the hill with the glowing door", "path": ""}
	var wrong := said.keys().filter(func(k): return m.place_key(k) != said[k])
	check(wrong.is_empty(), "where they mean, as they say it: %s" % ", ".join(said.keys().map(func(k): return "\"%s\" → %s" % [k, m.place_key(k) if m.place_key(k) != "" else "(nowhere)"])))
	check(fm.nell.place_key("my hut") == "Nell's hut" and fm.nell.place_key("home") == "Nell's hut" and m.place_key("home") == "the house in the village", "and home is home: Nell's hut for Nell, the house for Mo")
	# Knocking at someone's door, and a bite to eat
	var door: Vector3 = isle.shelter("hut_tam").door
	put(folk.tam, door.x + 1.5, door.z + 1.0)
	put(mo, door.x - 1.0, door.z + 1.0)
	m._knock("hut_tam", isle.shelter("hut_tam"))
	var knocked := String(m.mem.entries.back().s)
	var fed: Dictionary = isle.eat_at(mo, "hut_tam")
	check(knocked.contains("Tam's at home") and fm.tam.mem.entries.slice(-3).any(func(e): return e.s == "Mo knocked at my door"), "Mo knocks at Tam's cottage: Tam's in, and hears it (\"%s\")" % knocked)
	check(float(fed.get("food", 0.0)) > 0 and String(fed.said).contains("bread and honey"), "and hungry, Tam gives her something: \"%s\"" % fed.get("said", ""))
	put(folk.tam, 40.0, 40.0)
	check(float(isle.eat_at(mo, "hut_tam").food) == 0.0, "with Tam out, there's nothing to be had there")
	fm.tam.back_to_day()
	# The same bump over and over is felt once
	var n0: int = m.mem.entries.filter(func(e): return String(e.s) == "you bumped into something hard").size()
	for i in 3:
		m._bumped("thing", "you bumped into something hard")
	check(m.mem.entries.filter(func(e): return String(e.s) == "you bumped into something hard").size() == n0 + 1, "sliding along a wall: bumped once, not every step")
	# Watching Bo fib to Mo: Tam knows it was Mo he told, not her
	put(mo, 0.0, 6.0, Vector3(0, 0, -20))
	put(bo, 0.0, 8.0, Vector3(0, 0, 6))
	hold(folk.tam, 2.5, 9.5, bo.position)
	var apple: Dictionary = {}
	for T in isle.things:
		if String(T.t).begins_with("apple") and T.node.is_visible_in_tree():
			apple = T
	isle.taken(apple)
	bo.hold(apple)
	apple.what = "an apple"
	await game.wait(.2)
	game.minds.line_said(bo, "Mo, I don't have the apple, honest.")
	await until(func(): return fm.tam.mem.entries.any(func(e): return e.k == "caught"), 5.0)
	var seen: Array = fm.tam.mem.entries.filter(func(e): return e.k == "caught")
	check(not seen.is_empty() and String(seen.back().s).begins_with("Bo told Mo \"Mo, I don't have the apple"), "Tam sees Bo fib to Mo, apple in hand: \"%s\"" % (seen.back().s if seen.size() else "-"))
	bo.let_go()
	fm.tam.back_to_day()


# ---------- Their days ----------

## How far someone is from where their day has them now.
func off_spot(w: String) -> float:
	var at: Vector3 = isle.life_spot(w, Life.doing(w, game.clock.hour()))
	return Vector2(at.x - folk[w].position.x, at.z - folk[w].position.z).length()


func _days() -> void:
	put_kid(0.0, 30.0)
	# Everyone in the village to start with
	for w in folk:
		put(folk[w], -1.0 + Folk.IDS.find(w) * 1.5, 17.0)
		folk[w].mode = "free"
	game.clock.set_hour(9.5)
	await game.wait(.3)
	var start := {}
	for w in folk:
		start[w] = off_spot(w)
	# The morning: off to their work
	await until(func(): return folk.keys().all(func(w): return off_spot(w) < 1.5), 90.0)
	check(folk.keys().all(func(w): return off_spot(w) < 1.5), "in the morning each goes to their work: Nell to the beach, Tam to her hives, Odo to his clay (%s)" % ", ".join(folk.keys().map(func(w): return "%s %.0f m" % [w, start[w]])))
	await game.wait(1.5)
	check(fm.tam.memory.any(func(e): return String(e.s).contains("tended the bees")) and fm.odo.memory.any(func(e): return String(e.s).contains("clay")), "and does it: \"%s\"" % fm.tam.memory.filter(func(e): return String(e.s).contains("bees")).back().s if fm.tam.memory.any(func(e): return String(e.s).contains("bees")) else "-")
	# Lunch at home
	game.clock.set_hour(12.6)
	await until(func(): return folk.tam.inside != "", 40.0)
	check(folk.tam.inside == "hut_tam", "at lunchtime Tam goes home to eat")
	await until(func(): return folk.tam.inside == "", 15.0)
	check(fm.tam.memory.any(func(e): return String(e.s) == "had a meal at home"), "and comes out again fed")
	# The evening: everyone at the campfire
	game.clock.set_hour(20.3)
	for w in folk:
		fm[w].back_to_day()
	put(mo, isle.campfire.position.x - 1.8, isle.campfire.position.z + 1.2, isle.campfire.position)
	put(bo, isle.campfire.position.x + 1.8, isle.campfire.position.z + 1.2, isle.campfire.position)
	put_kid(isle.campfire.position.x, isle.campfire.position.z + 6.0)
	await game.wait(1.5)
	check(folk.keys().all(func(w): return folk[w].position.distance_to(isle.campfire.position) < 3.5), "of an evening they're all round the campfire")
	await look(isle.campfire.position + Vector3(0, .9, 0), 0.0, 6.5, 1.3)
	await game.wait(.5)
	await shot("campfire_evening")
	# Bed
	game.clock.set_hour(23.2)
	await until(func(): return folk.keys().all(func(w): return fm[w].body.asleep), 90.0)
	check(folk.keys().all(func(w): return fm[w].body.asleep and folk[w].inside == "hut_" + w), "late at night each goes home to bed")
	game.clock.set_hour(9.0)
	for w in folk:
		fm[w].back_to_day()


func until(cond: Callable, timeout: float) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > timeout * 1000:
			return false
		await get_tree().process_frame
	return true


# ---------- Gossip ----------

## Hold someone where they are (their day waits): standing, with nothing to do.
func hold(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	put(p, x, z, face_to)
	game.minds.of(p).task = {act = "wait", phase = "hold", word = ""}


## Wait until `who` has heard the story with this id (from anyone); returns their copy.
func hears(who: Mind, id: String, timeout := 120.0) -> Dictionary:
	await until(func(): return who.news.knows(id), timeout)
	return who.news.find(id)


func _gossip() -> void:
	game.clock.set_hour(11.0)
	var far := Vector3(-30.0, 0, 40.0)
	put_kid(far.x, far.z)
	# Everyone apart, so nothing's passed on before it should be
	# (the island's people out of earshot: they'd turn to his voice and see the apple for themselves)
	var spots := {mo = Vector2(-4, 4), bo = Vector2(-2, 4), nell = Vector2(26, 2), tam = Vector2(28, 10), odo = Vector2(-28, 2)}
	for p in game.people():
		hold(p, spots[p.id].x, spots[p.id].y)
	# Bo tells Mo he hasn't got the apple, while holding it where she can see: she catches him out
	var apple: Dictionary = isle.thing("apple_0")
	isle.taken(apple)
	game.minds.line_said(bo, "I don't have the apple, Mo, honest.")
	bo.face(mo.position)
	bo.yaw = bo.t_yaw
	mo.face(bo.position)
	mo.yaw = mo.t_yaw
	bo.hold(apple)
	var lie_id := ""
	await until(func(): return m.news.items.any(func(x): return x.about == "bo" and String(x.text).contains("apple")), 5.0)
	for x in m.news.items:
		if x.about == "bo" and String(x.text).contains("apple"):
			lie_id = x.id
	check(lie_id != "", "Mo catches Bo out (he said he hadn't got the apple, and there it is in his hand): something to tell")
	var original: String = m.news.find(lie_id).get("text", "")
	# Mo and Nell, together, out of your hearing
	var bo_trust := {}
	for w in folk:
		bo_trust[w] = fm[w].heart.rel.bo.trust
	hold(mo, 10.0, 2.0, Vector3(11.5, 0, 2.0))
	hold(folk.nell, 11.5, 2.0, Vector3(10.0, 0, 2.0))
	await game.wait(.3)
	await look(Vector3(10.75, isle.ground(10.75, 2.0) + .9, 2.0), 0.0, 4.0, 1.42)
	var n: Dictionary = await hears(fm.nell, lie_id)
	await shot("gossip_mo_tells_nell")
	check(not n.is_empty() and n.from == "mo" and n.chain == ["mo", "nell"], "Mo passes it on to Nell (she has it from Mo)")
	check(fm.nell.memory.any(func(e): return String(e.s).begins_with("Mo told me")), "and Nell remembers who told her")
	# Nell to Tam, Tam to Odo
	hold(mo, -4.0, 4.0)
	hold(folk.tam, 13.0, 2.0, Vector3(11.5, 0, 2.0))
	var t: Dictionary = await hears(fm.tam, lie_id)
	check(not t.is_empty() and t.chain == ["mo", "nell", "tam"], "Nell tells Tam (%s)" % (" → ".join(t.chain) if not t.is_empty() else "-"))
	hold(folk.nell, 24.0, -6.0)
	hold(folk.odo, 14.5, 2.0, Vector3(13.0, 0, 2.0))
	var o: Dictionary = await hears(fm.odo, lie_id)
	check(not o.is_empty() and o.chain == ["mo", "nell", "tam", "odo"] and o.from == "tam", "and Tam tells Odo: Mo → Nell → Tam → Odo, each knowing who told them")
	var texts := [original, n.get("text", ""), t.get("text", ""), o.get("text", "")]
	note("  as told: " + " | ".join(texts))
	check(o.get("text", "") != original and String(o.get("text", "")).contains("apple"), "it changed a little on the way (\"%s\" became \"%s\")" % [original, o.get("text", "")])
	check(fm.odo.memory.any(func(e): return String(e.s).begins_with("Tam told me (she had it from Nell)")), "Odo heard it from Tam, who had it from Nell")
	check(fm.tam.heart.rel.bo.trust < bo_trust.tam and fm.odo.heart.rel.bo.trust < bo_trust.odo, "and none of them trusts Bo quite as much now (Odo: %.2f from %.2f)" % [fm.odo.heart.rel.bo.trust, bo_trust.odo])
	# Nell told Mo what she wants: it's Mo's quest now
	check(m.news.knows(Gossip.id_of("want", "", "nell")) and m.plans.items.any(func(i): return i.text == Folk.WANTS.nell.todo), "Nell told Mo about her lost float, and Mo means to find it: \"%s\"" % Folk.WANTS.nell.todo)
	check(game.minds.passed.size() >= 4, "%d things passed on in all, quietly (out of your hearing, no model)" % game.minds.passed.size())
	bo.let_go()


# ---------- A quest ----------

func _quest() -> void:
	game.clock.set_hour(11.5)
	var F: Dictionary = isle.lost.float
	var at: Vector3 = isle.thing_pos("float")
	if not m.plans.items.any(func(i): return i.text == Folk.WANTS.nell.todo):
		m.plans.help(Folk.WANTS.nell.todo, "Nell wants it", m.mem.life_h)
	# Mo on the north-east shore; Nell at home
	var toward := Vector3(at.x, 0, at.z) * .93
	put(mo, toward.x, toward.z, at)
	put_kid(toward.x * .9, toward.z * .9)
	hold(folk.nell, toward.x * .85 - 2.0, toward.z * .85)
	await game.wait(.5)
	var nell_v: float = fm.nell.heart.v
	var nell_fond: float = fm.nell.heart.rel.mo.fond
	var ok: bool = await standin.act(m, "pick_up", at + Vector3(0, .15, 0), "the green glass float")
	await until(func(): return m.task.is_empty(), 15.0)
	check(mo.held != null and String(mo.held.t) == "float", "Mo finds Nell's float on the shore and picks it up (the stand-in pointing for her)")
	m.start("give", {who = "Nell"})
	await until(func(): return game.minds.quests.size() > 0 or m.task.is_empty(), 30.0)
	await look(folk.nell.eye_world() + Vector3(0, -.3, 0), folk.nell.yaw + .6, 3.0, 1.45)
	await game.wait(.3)
	await shot("quest_float_for_nell")
	check(game.minds.quests.size() == 1 and game.minds.quests[0].who == "nell" and game.minds.quests[0].by == "mo", "and gives it to her: Nell's want, done")
	check(fm.nell.heart.v > nell_v + .2 and fm.nell.heart.rel.mo.fond > nell_fond, "Nell's over the moon, and fonder of Mo than ever (%.2f from %.2f)" % [fm.nell.heart.rel.mo.fond, nell_fond])
	check(fm.nell.memory.any(func(e): return String(e.s) == "Mo found my lucky float and gave it back to me"), "she won't forget it")
	check(m.plans.items.any(func(i): return i.text == Folk.WANTS.nell.todo and i.status == "done"), "Mo's quest is done in her plan")
	check(isle.found.has("float"), "and the float stays found")
	# The news goes round: Nell tells Tam
	var done_id := Gossip.id_of("done", "", "nell")
	var tam_fond: float = fm.tam.heart.rel.mo.fond
	hold(folk.tam, folk.nell.position.x + 1.5, folk.nell.position.z, folk.nell.position)
	put_kid(folk.nell.position.x + 30.0, folk.nell.position.z)
	var heard: Dictionary = await hears(fm.tam, done_id)
	check(not heard.is_empty() and String(heard.text).begins_with("Mo"), "Tam hears it from Nell: \"%s\"" % heard.get("text", "-"))
	check(fm.tam.heart.rel.mo.fond > tam_fond, "and thinks the better of Mo for it")
	check(not fm.tam.news.pick("odo", fm.tam.mem.life_h).get("kind", "") == "want" or fm.tam.news.pick("odo", fm.tam.mem.life_h).get("quest", "") != "nell", "nobody goes on about Nell's lost float once it's found")


# ---------- With the model ----------

## Passing news on in a thought, as the model would (the stand-in sends the reply the model would): Nell tells
## Tam, in her own words, with "tell"; and they only think for themselves when you're near.
func _in_a_thought() -> void:
	game.clock.set_hour(11.0)
	hold(folk.nell, 2.0, 30.0, Vector3(3.5, 0, 30.0))
	hold(folk.tam, 3.5, 30.0, Vector3(2.0, 0, 30.0))
	hold(folk.odo, -20.0, 15.0)
	put_kid(2.8, 33.0)
	var now: float = fm.nell.mem.life_h
	var x: Dictionary = fm.nell.news.witness("odo", "Odo dropped a whole tray of pots this morning", -.2, now)
	var n := 0
	for i in range(1, 9):
		if fm.nell.news.nth(i, now).get("id", "") == x.id:
			n = i
	check(n > 0 and fm.nell.news.lines(now)[n - 1].begins_with("Odo dropped a whole tray of pots"), "Nell's thought gets her news, numbered (%d: \"%s\")" % [n, fm.nell.news.lines(now)[n - 1].left(60) if n > 0 else "-"])
	var before := game.minds.passed.size()
	await standin.reply(fm.nell, {"say": "Tam, you'll never guess: Odo dropped a whole tray of pots!", "to": "tam", "tell": n, "think": "poor Odo", "do": "none"}, "idle")
	await until(func(): return fm.tam.news.knows(x.id), 15.0)
	var got: Dictionary = fm.tam.news.find(x.id)
	check(not got.is_empty() and got.from == "nell" and game.minds.passed.size() > before and game.minds.passed.back().from == "nell", "she says it her way, and Tam has it from Nell: \"%s\"" % got.get("text", "-"))
	check(fm.tam.memory.any(func(e): return String(e.s).contains("Nell said") and String(e.s).contains("tray of pots")), "Tam heard her say it, too")
	# Thinking for themselves: only near you
	check(game.minds.near_you(fm.nell) and not game.minds.near_you(fm.odo), "Nell, near you, may think for herself; Odo, across the island, just gets on with his day")
	check(Minds.IDLE.folk[0] >= 20.0 and Minds.IDLE.folk[0] > Minds.IDLE.bo[1], "and even near you they think seldom (every %d to %d s, against Bo's %d to %d)" % [Minds.IDLE.folk[0], Minds.IDLE.folk[1], Minds.IDLE.bo[0], Minds.IDLE.bo[1]])


# ---------- What it costs ----------

## The frame rate and the pals' own work, with the island's people there and not (somewhere else), in turns,
## for as the camera is now: {on: {fps, pals}, off: {...}}.
func measure(rounds := 4) -> Dictionary:
	var vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var max_fps := Engine.max_fps
	Engine.max_fps = 0
	var out := {on = {fps = [], draws = [], pals = []}, off = {fps = [], draws = [], pals = []}}
	var where := {}
	for p in game.folk:
		where[p] = p.place_id
	for round_ in rounds:
		for state in [false, true]:
			for p in game.folk:
				p.place_id = where[p] if state else "elsewhere"
				p.set_here(state)
			await game.wait(.6)
			var into: Dictionary = out.on if state else out.off
			var t0 := Time.get_ticks_usec()
			var frames := 0
			var draws := 0.0
			var pals := 0.0
			var pal_frames := 0
			var pose0: int = Pal.Bearing.us
			var show0: int = Mind.show_us
			while Time.get_ticks_usec() - t0 < 2000000:
				var p0: int = game.prof.pals
				var n0: int = game.prof.n
				await get_tree().process_frame
				frames += 1
				if game.prof.n == n0 + 1:
					pals += game.prof.pals - p0
					pal_frames += 1
				draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			into.fps.append(frames / ((Time.get_ticks_usec() - t0) / 1e6))
			into.draws.append(draws / frames)
			into.pals.append(pals / maxf(1, pal_frames) + float(Pal.Bearing.us - pose0) / frames + float(Mind.show_us - show0) / frames)
	for p in game.folk:
		p.place_id = where[p]
		p.set_here(true)
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	var avg := func(a: Array) -> float: return a.reduce(func(x, y): return x + y, 0.0) / a.size()
	for k in ["on", "off"]:
		for q in ["fps", "draws", "pals"]:
			out[k][q + "_avg"] = avg.call(out[k][q])
	return out


## Everyone round the village, on screen; then the usual (the island's people about their day across the
## island): with them and without, the same view.
func _cost() -> void:
	game.clock.set_hour(11.0)
	put_kid(0.0, 24.0)
	hold(mo, -1.5, 19.0)
	hold(bo, 1.5, 19.0)
	hold(folk.nell, -3.5, 16.0)
	hold(folk.tam, 0.0, 15.0)
	hold(folk.odo, 3.5, 16.0)
	game.cam_focus = null
	game.az = 0.0
	game.pol = 1.2
	game.aim(0.0, true)
	await game.wait(1.0)
	var near: Dictionary = await measure()
	var line := "Mac, vsync off, the village on screen with Mo and Bo. Without the island's people: %.0f fps, the pals' own work %.0f µs a frame, %.0f draw calls. With Nell, Tam and Odo there too: %.0f fps, %.0f µs, %.0f draw calls." % [
		near.off.fps_avg, near.off.pals_avg, near.off.draws_avg, near.on.fps_avg, near.on.pals_avg, near.on.draws_avg]
	note("  " + line)
	check(near.on.fps_avg > near.off.fps_avg * .93, "with all three on screen, the frame rate holds (%.0f fps with them, %.0f without)" % [near.on.fps_avg, near.off.fps_avg])
	# The usual: about their day across the island (the morning: at their work), you by the hill
	game.clock.set_hour(9.0)
	for w in folk:
		fm[w].task = {}
		fm[w].back_to_day()
	put_kid(-2.0, 0.0)
	await game.wait(1.5)
	var far_n := game.folk.filter(func(p): return p.far).size()
	var about: Dictionary = await measure(3)
	var line2 := "Going about their day across the island (%d of 3 far off, updated a few times a second), the same view: %.0f fps with them, %.0f without; the pals' own work %.0f µs a frame against %.0f." % [
		far_n, about.on.fps_avg, about.off.fps_avg, about.on.pals_avg, about.off.pals_avg]
	note("  " + line2)
	if shots != "":
		var f := FileAccess.open(shots.path_join("frame_cost.txt"), FileAccess.WRITE)
		f.store_line(line)
		f.store_line(line2)
		f.store_line("village rounds (without, with) fps: %s / %s" % [near.off.fps, near.on.fps])
		f.store_line("about their day rounds (without, with) fps: %s / %s" % [about.off.fps, about.on.fps])
	check(about.on.fps_avg > about.off.fps_avg * .95, "and as usual, with them about their day: %.0f fps (against %.0f without them)" % [about.on.fps_avg, about.off.fps_avg])
