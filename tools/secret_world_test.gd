extends Node
## Private thoughts, secrets and fibs in the real game, with no model (a stand-in replies for them, through the
## same path the model's replies take):
##   godot --path . -- --autoplay --autoplay-script=res://tools/secret_world_test.gd --offline
## What they think goes only into their own memory; a fib or a bluff is kept by the one who told it, with who
## heard it and what's really so, and comes back in their later thoughts; secrets are tracked, and who they've
## been told to; the listener (Bo, or you through the speech bubble) only ever gets the words. Prints
## ok:/FAIL:, exits non-zero on a failure.

const StandIn := preload("res://tools/standin.gd")

var game: Game
var args: Array = []
var failed := false
var standin
var mo: Pal
var bo: Pal
var m: Mind
var b: Mind
## Everything Mo and Bo think to themselves in this test (to look for where it mustn't be)
var private_words := []


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
	# Nobody else about: this is between Mo, Bo and you
	game.folk_away()
	standin = StandIn.new(game)
	game.minds.quiet = true
	game.minds.ears.muted = true
	game.controls = false
	game.clock.stopped = true
	game.clock.set_hour(11)
	await game.wait(.5)
	await _a_fib()
	await _a_bluff()
	await _a_secret()
	await _nobody_listening()
	await _never_said()
	await _nothing_leaks()
	await _kept()
	note("FAILED" if failed else "DONE: private thoughts")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[secrets %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


func check(ok: bool, what: String) -> void:
	note(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func put(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	game.minds.of(p).task = {}
	p.stop()
	p.position = Vector3(x, game.level.ground(x, z), z)
	p.mode = "script"
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)
	game.kid.position = game.wisp_g


func kinds(x: Mind, kind: String) -> Array:
	return x.memory.filter(func(e): return e.k == kind).map(func(e): return String(e.s))


func together() -> void:
	put(mo, .5, 2.0, Vector3(3.0, 0, 2.0))
	put(bo, 3.0, 2.0, Vector3(.5, 0, 2.0))
	put_kid(1.5, 5.0)
	await game.wait(.1)


# ---------- A fib ----------

func _a_fib() -> void:
	await together()
	var r := {"say": "Bo, I'll wait right here for you.", "to": "bo", "think": "no way, I'm going in alone", "true": false, "do": "none"}
	private_words.append(r.think)
	await standin.reply(m, r)
	check(game.hud.bubble_words == PackedStringArray(r.say.split(" ", false)), "what you see in the bubble is what she said, nothing else")
	check(kinds(m, "thought").has(r.think), "what she really thinks goes into her own memory: \"%s\"" % r.think)
	check(kinds(m, "lied").has("told Bo and Wisp \"Bo, I'll wait right here for you.\", and it wasn't true: no way, I'm going in alone"), "and that she fibbed, to whom, and what's really so")
	check(m.secrets.lines() == ["you told Bo and Wisp \"Bo, I'll wait right here for you.\", and it isn't true: no way, I'm going in alone"], "she keeps it in mind: %s" % [m.secrets.lines()])
	check(kinds(b, "told").back() == "Mo said (to your left, close by): \"Bo, I'll wait right here for you.\"" or kinds(b, "told").back().ends_with(": \"Bo, I'll wait right here for you.\""), "Bo hears the words: \"%s\"" % kinds(b, "told").back())
	check(b.heart.open_from("mo", "wait").size() == 1, "and takes them at their word (she promised to wait)")
	var next := game.minds.thought_body(m, "idle", {}, {jpg = ""})
	check(next.inner == m.secrets.lines(), "her next thought has her fib in it, so she can keep her story straight")
	var bos := game.minds.thought_body(b, "idle", {}, {jpg = ""})
	check(bos.inner.is_empty(), "his has nothing of hers")


# ---------- A bluff ----------

func _a_bluff() -> void:
	await together()
	var r := {"say": "Dark? I'm not scared of the dark at all.", "to": "mo", "think": "I'm terrified of the dark under the hill", "true": "bluff", "do": "none"}
	private_words.append(r.think)
	await standin.reply(b, r)
	check(b.secrets.items.back().kind == "bluff" and b.secrets.lines().back() == "you told Mo and Wisp \"Dark? I'm not scared of the dark at all.\", putting on a front: really, I'm terrified of the dark under the hill", "Bo puts on a brave face, and knows it: \"%s\"" % b.secrets.lines().back())
	check(kinds(m, "told").back().ends_with("\"Dark? I'm not scared of the dark at all.\""), "Mo only hears the brave face")


# ---------- A secret ----------

func _a_secret() -> void:
	await together()
	var r := {say = "", think = "this key could open something", keep = "I found a shiny key under the mushroom", do = "none"}
	private_words.append_array([r.think, "shiny key"])
	await standin.reply(m, r)
	check(m.secrets.lines().has("a secret: I found a shiny key under the mushroom (you haven't told anyone)") and kinds(m, "secret").has(r.keep), "Mo keeps a secret: she found a key")
	check(not kinds(b, "told").any(func(s): return s.contains("key")), "saying nothing, nobody knows")
	# Later, with you out of earshot, she tells Bo
	put_kid(-40.0, 40.0)
	await game.wait(.1)
	await standin.reply(m, {"say": "Bo, guess what, I found a shiny key under the mushroom!", "to": "bo", "think": "he'll know what it opens", "true": true, "do": "none"})
	private_words.append("he'll know what it opens")
	check(m.secrets.lines().has("a secret: I found a shiny key under the mushroom (only Bo knows)"), "she tells Bo: now only Bo knows")
	check(kinds(m, "did").has("told Bo my secret: I found a shiny key under the mushroom"), "and she remembers telling him")
	check(kinds(b, "told").back().ends_with("\"Bo, guess what, I found a shiny key under the mushroom!\""), "Bo hears it now")
	private_words.erase("shiny key")
	put_kid(1.5, 5.0)


# ---------- Nobody listening ----------

func _nobody_listening() -> void:
	put(mo, .5, 2.0)
	put(bo, 30.0, -15.0)
	put_kid(-40.0, 40.0)
	await game.wait(.1)
	var n: int = m.secrets.items.size()
	await standin.reply(m, {"say": "I'm the bravest kid on the whole island.", "think": "I hope that's true", "true": false, "do": "none"})
	private_words.append("I hope that's true")
	check(m.secrets.items.size() == n and kinds(m, "thought").has("I hope that's true"), "a fib with nobody to hear it isn't one (she just thinks to herself)")


# ---------- A line that never got said ----------

func _never_said() -> void:
	await together()
	var n: int = m.secrets.items.size()
	var rec := {who = "mo", why = "idle", dropped = ["no gap to talk"], say = "I never touched your boat, Bo."}
	await game.minds._on_decided({"say": "I never touched your boat, Bo.", "think": "I broke the mast", "true": false, "do": "none"}, m, Brain.Thought.new(), rec)
	await game.wait(.1)
	private_words.append("I broke the mast")
	check(m.secrets.items.size() == n and not kinds(b, "told").any(func(s): return s.contains("boat")), "a fib she never got to say isn't one, and Bo hears nothing")


# ---------- Nothing leaks ----------

## Every place Bo (or you) could get anything from: his memory (all of it, hazy or not), what he's heard, his
## feelings, his plans, his secrets, what goes into his thoughts and into his night's reflection.
func _nothing_leaks() -> void:
	var bo_all := []
	for e in b.memory:
		bo_all.append(String(e.s))
		bo_all.append(String(e.get("was", "")))
	bo_all.append_array(b.heard_lines.map(func(h): return String(h.said)))
	bo_all.append(JSON.stringify(b.heart.to_save()))
	bo_all.append(JSON.stringify(b.plans.to_save()))
	bo_all.append(JSON.stringify(game.minds.thought_body(b, "idle", {}, {jpg = ""})))
	bo_all.append(JSON.stringify(game.minds.reflect_body(b, b.mem.for_reflection())))
	var mo_private := private_words.filter(func(w): return w in ["no way, I'm going in alone", "this key could open something", "he'll know what it opens", "I hope that's true", "I broke the mast"])
	var leaked := mo_private.filter(func(w): return bo_all.any(func(s): return String(s).contains(w)))
	check(leaked.is_empty(), "none of what Mo thought to herself reaches Bo, anywhere (%s)" % [leaked])
	var mo_all := []
	for e in m.memory:
		mo_all.append(String(e.s))
	mo_all.append_array(m.heard_lines.map(func(h): return String(h.said)))
	check(not mo_all.any(func(s): return s.contains("I'm terrified of the dark under the hill")), "nor what Bo thought, to Mo")
	check(not game.hud.bubble_words.has("terrified") and not "".join(game.hud.bubble_words).contains("goingin"), "and you only ever see what's said")
	var mine := JSON.stringify(game.minds.reflect_body(m, m.mem.for_reflection()))
	check(mine.contains("no way, I'm going in alone") and mine.contains("I told Bo and Wisp"), "her own night's reflection has her thoughts and her fib in it")
	var told := m.memory_lines(m.on_mind("Bo is waiting for me"))
	check(told.any(func(l): return l.contains("and it wasn't true")), "thinking about Bo waiting, her fib comes back to her")


# ---------- Kept ----------

func _kept() -> void:
	m.save()
	b.save()
	var mine := JSON.stringify(m.secrets.to_save())
	m.load_memory()
	check(JSON.stringify(m.secrets.to_save()) == mine and m.secrets.items.size() >= 2, "saved and loaded: her secrets and fibs")
	var bo_file := FileAccess.get_file_as_string(b.file)
	check(not bo_file.contains("going in alone") and not bo_file.contains("I broke the mast"), "and Bo's own file has none of her thoughts in it")
