extends Node
## Mood and feelings in the real game, with no model (a scripted stand-in speaks and reflects for them):
##   godot --path . -- --autoplay --autoplay-script=res://tools/heart_world_test.gd --offline
## Mood lasting from thought to thought and drifting with what happens, the body and time; feelings toward each
## other and Wisp changed by help, promises kept and broken (to give, to wait, and ones only the night's
## reflection can judge), teasing, things shared (inside jokes), being left behind and boops; a moment of
## their own when Wisp's away, and what they say about Wisp then rubbing off; all of it as words for the
## model, saved and loaded. Prints ok:/FAIL:, exits non-zero on a failure.

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
	isle = game.level
	standin = StandIn.new(game)
	game.minds.quiet = true
	game.controls = false
	game.clock.stopped = true
	game.clock.set_hour(12)
	game.set_active(mo)
	await game.wait(.5)
	await _mood()
	await _help_and_promises()
	await _waiting()
	await _teasing()
	await _together()
	await _boops()
	await _wisp_away()
	await _night()
	await _words_and_saving()
	note("FAILED" if failed else "DONE: mood and feelings")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[heart %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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


## Hours lived, quickly (`per_s` game hours a real second).
func live(hours: float, per_s := 4.0) -> void:
	var start: float = game.clock.t
	game.clock.rate = per_s
	game.clock.stopped = false
	await until(func(): return game.clock.t - start >= hours, hours / per_s + 10.0)
	game.clock.stopped = true
	game.clock.rate = 24.0 / (Clock.DAY_MINUTES * 60.0)


func calm(x: Mind) -> void:
	x.body.hunger = .2
	x.body.tired = .1
	x.body.cold = 0.0
	x.body.fear = 0.0
	x.body.bored = 0.0
	x.heart.v = x.heart.base_v
	x.heart.a = x.heart.base_a


# ---------- Mood ----------

func _mood() -> void:
	game.clock.set_hour(6)
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, 3.0, 2.0, Vector3(.5, 0, -20))
	put_kid(-1.0, 6.0)
	calm(m)
	var first: String = m.feel()[0]
	check(first == "you're in a good mood", "Mo, before anything: \"%s\"" % first)
	await game.wait(.3)
	check(m.feel()[0] == first, "the next thought, nothing having happened: the same mood")
	m.touch("something cold lunged at you and you jumped back")
	var after_fright: String = m.feel()[0]
	check(after_fright != first and m.heart.v < 0.0, "a fright: \"%s\"" % after_fright)
	await game.wait(.3)
	check(m.feel()[0] == after_fright, "and it lasts into the next thought")
	await live(2.0)
	var later: String = m.feel()[0]
	check(m.heart.v > -0.05 and m.heart.v < m.heart.base_v, "two hours on, she's getting over it (\"%s\")" % later)
	m.body.hunger = 0.0
	await live(6.0)
	check(m.feel()[0] == first, "eight hours on (she's had something to eat), she's herself again")
	m.body.hunger = .95
	m.body.tired = .85
	await live(4.0)
	check(m.heart.v < -.1 and m.feel()[0] != first, "hungry and worn out for hours, it gets to her: \"%s\"" % m.feel()[0])
	calm(m)


# ---------- Help, and promises to give ----------

func _give_apple(from: Pal, to: Pal) -> void:
	var T: Dictionary = {}
	for x in isle.things:
		if isle.edible(x.t) > 0:
			T = x
			break
	isle.taken(T)
	from.hold(T)
	T.what = "an apple"
	var g: Mind = game.minds.of(from)
	g.start("give", {who = to.pal_name})
	await until(func(): return g.task.is_empty(), 10)


func _help_and_promises() -> void:
	game.clock.set_hour(12)
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, 3.5, 2.5, mo.position)
	var t: float = m.heart.rel.bo.trust
	var f: float = m.heart.rel.bo.fond
	await _give_apple(bo, mo)
	check(mo.held != null and m.heart.rel.bo.trust > t and m.heart.rel.bo.fond > f, "Bo gives Mo an apple: she likes and trusts him a little more")
	if mo.held:
		mo.let_go().node.queue_free()
	game.minds.line_said(bo, "Mo, I'll give you the torch later.")
	var open: Array = m.heart.open_from("bo", "give")
	check(open.size() == 1 and m.heart.about("bo").contains("Bo promised you \"Mo, I'll give you the torch later.\""), "Bo promises Mo something: she holds him to it")
	t = m.heart.rel.bo.trust
	await _give_apple(bo, mo)
	check(open[0].status == "kept" and m.heart.rel.bo.trust > t + .05, "he gives her something: promise kept, more trust than a plain gift")
	if mo.held:
		mo.let_go().node.queue_free()
	game.minds.line_said(bo, "Mo, I'll bring you an apple, promise.")
	var p: Dictionary = m.heart.open_from("bo", "give")[0]
	t = m.heart.rel.bo.trust
	await live(25.0, 10.0)
	check(p.status == "broken" and m.heart.rel.bo.trust < t, "a promise to bring her an apple, a day goes by, nothing: broken")
	calm(m)


# ---------- Wisp's promises to wait ----------

func _waiting() -> void:
	game.clock.set_hour(12)
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, 30, -15)
	put_kid(-1.0, 3.0)
	game.minds._got_words("Mo, I'll wait here for you.")
	var p: Dictionary = m.heart.open_from("wisp", "wait")[0]
	put(mo, .5, -12.0)
	await game.wait(.3)
	check(p.status == "open", "Mo goes off; Wisp's still there")
	put(mo, .5, 1.0)
	await game.wait(.3)
	check(p.status == "kept", "she comes back and Wisp waited: kept")
	var t: float = m.heart.rel.wisp.trust
	game.minds._got_words("I'll wait right here, I promise.")
	var q: Dictionary = m.heart.open_from("wisp", "wait")[0]
	put(mo, .5, -12.0)
	await game.wait(.2)
	put_kid(-20.0, 20.0)
	await game.wait(.3)
	check(q.status == "broken" and m.heart.rel.wisp.trust < t, "this time Wisp wanders off: broken")
	check(m.heart.about("wisp").contains("sore that Wisp promised (\"I'll wait right here, I promise.\") and didn't"), "and she's sore about it: \"%s\"" % m.heart.about("wisp"))
	put_kid(-1.0, 6.0)


# ---------- Teasing ----------

func _teasing() -> void:
	game.clock.set_hour(12)
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, 3.0, 2.0, Vector3(.5, 0, -20))
	put_kid(-1.0, 6.0)
	var f: float = b.heart.rel.mo.fond
	game.minds.line_said(mo, "Bo, you slowpoke!")
	check(b.heart.rel.mo.fond >= f, "Mo calls Bo a slowpoke: from her, he doesn't mind")
	game.set_active(bo)
	var fw: float = b.heart.rel.wisp.fond
	game.minds._got_words("Bo, you scaredy cat!")
	check(b.heart.rel.wisp.fond < fw and b.heart.about("wisp").contains("sore that Wisp kept teasing you"), "Wisp calls him a scaredy cat: he minds (\"%s\")" % b.heart.about("wisp"))
	game.set_active(mo)
	var fm: float = m.heart.rel.wisp.fond
	game.minds._got_words("Mo, you silly goofball!")
	check(m.heart.rel.wisp.fond > fm, "Mo gets the same from Wisp: she loves it")


# ---------- Things done together ----------

func _together() -> void:
	# Walking right into each other, face to face, in broad daylight
	game.clock.set_hour(12)
	await game.wait(.1)
	put(mo, .5, 2.0, Vector3(.5, 0, -20))
	put(bo, .5, -.2, Vector3(.5, 0, 20))
	put_kid(-6.0, 9.0)
	mo.bump_t = 0.0
	mo.mode = "free"
	mo.walk([[.5, -3.0]])
	await until(func(): return m.heart.rel.bo.jokes.size() > 0, 4)
	mo.stop()
	mo.mode = "script"
	check(m.heart.about("bo").contains("you and Bo still laugh about the time you walked right into Bo"), "they walk smack into each other: a joke for Mo")
	check(b.heart.about("mo").contains("you and Mo still laugh about the time Mo walked right into you"), "and for Bo")
	# Bo boings off the mushroom with Mo watching
	var mush: Vector3 = isle.mush.global_position
	put(bo, mush.x + 1.0, mush.z + .8, mush)
	put(mo, mush.x + 1.0, mush.z + 6.0, mush)
	await game.wait(.2)
	await isle.use(bo, "mushroom")
	check(m.heart.rel.bo.jokes.any(func(j): return j.what == "the time Bo went boing off the giant mushroom"), "Bo boings off the mushroom in front of her: another one")
	# Bo goes off through the door, with Mo watching
	var door: Vector3 = isle.thing_pos("door")
	put(bo, door.x + .5, door.z + 2.0, door)
	put(mo, door.x, door.z + 6.0, bo.position)
	put_kid(door.x + 3, door.z + 8)
	game.controls = true
	game.idle_t = 0.0
	game.go_through(bo, "cave", {})
	await game.wait(.2)
	game.controls = false
	check(m.heart.rel.bo.grudges.any(func(g): return g.why == "Bo went off without you"), "he goes off through the door without her, as she watches: she's a bit sore")
	bo.place_id = "isle"
	bo.arriving = false
	bo.set_here(true)
	put(bo, 3.0, 2.0)


# ---------- Boops ----------

func _boops() -> void:
	game.clock.set_hour(12)
	put(mo, .5, 2.0, Vector3(.5, 0, 10))
	put(bo, 3.0, 2.0, Vector3(3.0, 0, 10))
	put_kid(1.5, 4.0)
	await game.wait(.2)
	var f: float = m.heart.rel.wisp.fond
	game._booped(mo)
	check(m.heart.rel.wisp.fond > f, "Wisp boops Mo: she loves it")
	var fb: float = b.heart.rel.wisp.fond
	for i in 3:
		game._booped(bo)
	check(b.heart.rel.wisp.fond < fb and b.heart.about("wisp").contains("Wisp keeps booping you"), "Wisp boops Bo three times: he's had enough (\"%s\")" % b.heart.about("wisp"))


# ---------- Wisp away ----------

func _wisp_away() -> void:
	game.minds.alone_after = 1.5
	game.clock.set_hour(12)
	put(mo, .5, 2.0, Vector3(3.0, 0, 2.0))
	put(bo, 3.0, 2.0, Vector3(.5, 0, 2.0))
	calm(m)
	calm(b)
	put_kid(1.5, 4.5)
	var n: int = game.minds.alone_moments
	await game.wait(2.5)
	check(game.minds.alone_moments == n and not mentions(m.feel(), "Wisp isn't around"), "with Wisp right there: no moment of their own")
	put_kid(-40.0, 40.0)
	await until(func(): return game.minds.alone_moments > n, 6)
	check(game.minds.alone_moments == n + 1, "Wisp off out of sight and earshot: a moment of their own (WISP_ALONE)")
	check(mentions(m.feel(), "Wisp isn't around: it's just you and Bo"), "and Mo knows it's just the two of them")
	var said: String = standin.gossip(m)
	check(b.heard_lines.back().said == said, "Mo says what she thinks of Wisp, and Bo hears it: \"%s\"" % said)
	var fb: float = b.heart.rel.wisp.fond
	var line2: String = "Honestly, Wisp is brave and funny. I like Wisp."
	game.minds.line_said(mo, line2)
	check(b.heart.rel.wisp.fond > fb, "she says Wisp's brave and funny: Bo, who trusts her, warms to Wisp a little")
	await game.wait(2.5)
	check(game.minds.alone_moments == n + 1, "not another moment straight away (a few hours lived between)")
	put_kid(-1.0, 6.0)


func mentions(lines: Array, word: String) -> bool:
	return lines.any(func(l): return String(l).contains(word))


# ---------- The night: feelings turned over ----------

func _night() -> void:
	game.minds.reflector = standin.reflect
	game.clock.set_hour(21)
	await game.wait(.1)
	# The night by the campfire: warm, and some light
	var fire: Vector3 = isle.campfire.global_position
	put(mo, fire.x + 1.8, fire.z + 1.0, fire)
	put(bo, fire.x - 1.8, fire.z + 1.0, fire)
	game.minds.line_said(bo, "Mo, I promise I'll find you a light.")
	var p: Dictionary = m.heart.open_from("bo", "other")[0]
	var tb: float = m.heart.rel.bo.trust
	var fw: float = m.heart.rel.wisp.fond
	standin.reflect_extra.mo = {people = [{who = "bo", trust = 1, fond = 1, why = "he found me a light"}, {who = "wisp", trust = 0, fond = -1, why = "Wisp laughed when I fell over"}],
		promises = [{n = 1, kept = true}]}
	m.body.tired = .8
	m.body.hunger = .2
	m.body.cold = 0.0
	m.body.fear = 0.0
	m.start("sleep", {})
	await game.wait(.3)
	var rec: Dictionary = game.minds.reflections.back()
	check(p.status == "kept", "the night's reflection judges the promise only it could: kept")
	check(m.heart.rel.bo.trust > tb and m.heart.rel.bo.trust - tb < .3, "she trusts Bo a bit more (a small step, whatever the reflection says)")
	check(m.heart.rel.wisp.fond < fw and m.heart.rel.wisp.grudges.any(func(g): return g.why == "Wisp laughed when I fell over"), "and likes Wisp a bit less, for a reason she'll remember")
	check(rec.get("people", []).size() == 3, "and it's logged: %s" % [rec.get("people", [])])
	var before: float = m.heart.v
	await live(10.0, 5.0)
	if m.body.asleep:
		m.wake("rested")
	check(absf(m.heart.v - m.heart.base_v) < .2, "a night's sleep: her mood's back to her usual (\"%s\")" % m.heart.mood_words())


# ---------- What the model gets, and keeping it ----------

func _words_and_saving() -> void:
	game.clock.set_hour(12)
	var lines: Array = m.heart.bonds() + b.heart.bonds() + [m.feel()[0], b.feel()[0]]
	for l in lines:
		note("  %s" % l)
	var re := RegEx.create_from_string("[0-9]")
	check(lines.all(func(l): return re.search(l) == null), "all of it, as it goes to the model, is words: no numbers")
	check(m.heart.bonds().size() == Folk.others("mo").size() and m.heart.bonds().slice(-2).any(func(l): return l.begins_with("Wisp: ")) and m.heart.bonds().slice(-2).any(func(l): return l.begins_with("Bo: ")),
		"how she feels about each of them, one line each (Wisp and Bo, who matter most, last)")
	m.save()
	b.save()
	var hm := JSON.stringify(m.heart.to_save())
	var hb := JSON.stringify(b.heart.to_save())
	m.load_memory()
	b.load_memory()
	check(JSON.stringify(m.heart.to_save()) == hm and JSON.stringify(b.heart.to_save()) == hb, "saved and loaded: moods, feelings, grudges, jokes and promises all kept")
	var f = JSON.parse_string(FileAccess.get_file_as_string(m.file))
	check(f is Dictionary and f.has("heart") and int(f.heart.v) == Heart.VERSION, "in their own memory file")
