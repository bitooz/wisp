extends Node
## Tests that play the game by themselves and print ok:/FAIL: checks.
##   godot --path . -- --autoplay [--shots=dir]   nobody touches anything: Mo and Bo get through the island, the
##                                                 dungeon, the plates, the shadow, the ember and the bridge on
##                                                 their own (or the test gives up after 12 minutes)
##   ... --autoplay --talk                         a conversation: recorded lines (tools/voice/*.wav) go in through
##                                                 the always-on ears, as if said into the mic; checks what was
##                                                 heard, that every line gets its own reply, and that their own
##                                                 voices aren't heard as you
##   ... --autoplay --memory                       after a run: asks Mo what happened in the dungeon
##   ... --autoplay --mic                          the phone's real mic (tools/device_mic_test.sh says a line aloud)

var game: Game
var args: Array = []
var shots := ""
var failed := false
var mode := "idle"
var stage_times := {}
var t0 := 0.0

var LIMIT_S := 720.0
## --start=cave: begin in the dungeon (to watch the dark part on its own)
var start_at := ""


func _ready() -> void:
	for a in args:
		if a.begins_with("--shots="):
			shots = a.substr(8)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
		if a in ["--talk", "--memory", "--mic"]:
			mode = a.substr(2)
		if a.begins_with("--start="):
			start_at = a.substr(8)
		if a.begins_with("--limit="):
			LIMIT_S = float(a.substr(8))
		if a == "--dump-minds":
			game.minds.dump = true
		if a.begins_with("--frames="):
			# Keep every picture they think with
			game.minds.dump_frames = a.substr(9)
			DirAccess.make_dir_recursive_absolute(game.minds.dump_frames)
		if a == "--echo":
			# Their voices leak into the mic, as from a phone's speaker
			game.mo.voice.echo = game.minds.ears
			game.bo.voice.echo = game.minds.ears
	t0 = Time.get_ticks_msec() / 1000.0
	note("mode %s, minds %s" % [mode, "on" if game.minds.on else "off"])
	match mode:
		"idle": _idle()
		"talk": _talk()
		"memory": _memory()
		"mic": _mic()


func note(s: String) -> void:
	print("[autoplay %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


func check(ok: bool, what: String) -> void:
	note(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func now() -> float:
	return Time.get_ticks_msec() / 1000.0 - t0


func shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	note("shot " + name)


func until(cond: Callable, timeout: float, what: String) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > timeout * 1000:
			check(false, "waited for " + what)
			return false
		await get_tree().process_frame
	return true


func finish(done_line: String) -> void:
	_report()
	note("FAILED" if failed else "DONE: " + done_line)
	get_tree().quit(1 if failed else 0)


# ---------- Nobody playing: they do it all ----------

const MILESTONES := [
	["cave", "they went into the dungeon on their own"],
	["light", "someone picked up a light"],
	["opening", "both plates held: the big door opened"],
	["gloom", "the shadow came out"],
	["ember", "the shadow was driven off"],
	["exit", "someone took the ember"],
	["home", "they came back up to the island"],
	["end", "the ember lit the brazier and the bridge"],
]


func _idle() -> void:
	var seen := {}
	var last_shot := ""
	if start_at != "":
		for p in [game.mo, game.bo]:
			p.place_id = start_at
			p.arriving = true
		game.travel(start_at, {})
	await game.wait(2.0)
	await shot("00-start")
	while now() < LIMIT_S:
		var reached := []
		if game.level.id == "cave":
			reached.append("cave")
		for p in [game.mo, game.bo]:
			if p.held and p.held.get("light", 0.0) > 0 and p.held.t != "ember":
				reached.append("light")
		var cave: Level = game.levels.get("cave")
		if cave and cave.door_open or game.stage == "opening":
			reached.append("opening")
		if cave and (cave.gloom.visible or cave.torches_on):
			reached.append("gloom")
		if cave and cave.torches_on:
			reached.append("ember")
		if game.embers > 0 or [game.mo, game.bo].any(func(p): return p.held and p.held.t == "ember"):
			reached.append("exit")
		if game.level.id == "isle" and seen.has("exit"):
			reached.append("home")
		if game.stage == "end":
			reached.append("end")
		for r in reached:
			if not seen.has(r):
				seen[r] = now()
				note("reached %s at %.0f s" % [r, now()])
				if r != last_shot:
					last_shot = r
					await game.wait(1.5)
					await shot("%02d-%s" % [seen.size(), r])
		if seen.has("end"):
			break
		await game.wait(.5)
	stage_times = seen
	for m in MILESTONES:
		check(seen.has(m[0]), "%s%s" % [m[1], (" (%.0f s)" % seen[m[0]]) if seen.has(m[0]) else ""])
	var heard: Array = game.minds.hears
	note("the mic heard %d things while nobody was talking to them: %s" % [heard.size(), ", ".join(heard.map(func(h): return "\"%s\"%s" % [h.heard, " (junk)" if h.junk else ""]))])
	_memory_checks()
	await shot("99-end")
	finish("Mo and Bo got through the whole loop on their own")


# ---------- A conversation ----------

## Say a recorded line as if into the mic, and wait for whoever answers.
func say_wav(name: String, who := "") -> Dictionary:
	await until(func(): return not game.talking_now() and not game.minds.ears.listening(), 30, "a gap to talk")
	if who != "":
		game.set_active(game.mo if who == "mo" else game.bo)
	var nh: int = game.minds.hears.size()
	var nt: int = game.minds.stats.size()
	note("say %s" % name)
	game.minds.ears.feed_silence(.3)
	game.minds.ears.feed(FileAccess.get_file_as_bytes("res://tools/voice/%s.wav" % name))
	game.minds.ears.feed_silence(1.2)
	if not await until(func(): return game.minds.hears.size() > nh, 20, "the mic to hear '%s'" % name):
		return {}
	var h: Dictionary = game.minds.hears[nh]
	var got := func():
		for x in game.minds.stats:
			if x.why == "heard" and x.t_end == h.t_end and (x.get("say", "") != "" or x.has("model")):
				return x
		return null
	if not h.junk:
		await until(func(): return got.call() != null, 30, "an answer to '%s'" % name)
	var rec = got.call()
	var r: Dictionary = rec if rec is Dictionary else {}
	note("  heard \"%s\" (%s) → %s: \"%s\" does %s %s, first word %s ms after the mic heard you stop" % [h.heard, "junk" if h.junk else "words", r.get("who", "-"), r.get("say", ""), r.get("do", ""), r.get("target", ""), r.get("ms_first_word", "?")])
	return {h = h, r = r}


func _talk() -> void:
	game.minds.quiet = true
	await game.wait(3.0)
	var lines := [["hello", "mo", "Mo"], ["plan", "", "plan"], ["beach", "bo", "beach"], ["hello", "mo", "Mo"], ["joke", "", "joke"],
		["ember_where", "bo", "ember"]]
	var says := []
	for l in lines:
		var got := await say_wav(l[0], l[1])
		if got.is_empty():
			continue
		check(String(got.h.heard).to_lower().contains(l[2].to_lower()), "heard '%s' right (\"%s\")" % [l[0], got.h.heard])
		var say: String = got.r.get("say", "")
		check(say != "" or got.r.get("do", "none") != "none", "an answer to '%s'" % l[0])
		if say != "":
			check(not says.has(say), "a fresh line, not one said before (\"%s\")" % say)
			says.append(say)
		await until(func(): return not game.talking_now(), 20, "them to finish")
		await game.wait(1.0)
	# Their own voices must not come back in as you: what they say leaks into the mic, as from the speaker
	note("echo: their voices leak into the mic")
	game.mo.voice.echo = game.minds.ears
	game.bo.voice.echo = game.minds.ears
	var nh: int = game.minds.hears.size()
	game.minds.hear_text("Mo, tell me a long story about the sea.", Time.get_ticks_msec())
	await until(func(): return game.mo.voice.sounding() or game.bo.voice.sounding(), 20, "someone to talk")
	await until(func(): return not game.talking_now(), 25, "them to finish")
	await game.wait(2.5)
	check(game.minds.hears.size() == nh, "their own voices, leaking into the mic, weren't heard as you (%d heard)" % (game.minds.hears.size() - nh))
	# Noise isn't talk
	nh = game.minds.hears.size()
	game.minds.ears.feed(FileAccess.get_file_as_bytes("res://tools/voice/noise.wav"))
	await game.wait(6.0)
	var noise: Array = game.minds.hears.slice(nh)
	var answered := noise.filter(func(h): return game.minds.stats.any(func(x): return x.t_end == h.t_end and x.get("say", "") != ""))
	check(answered.is_empty(), "noise got no answer (%d phrases detected, %d answered)" % [noise.size(), answered.size()])
	finish("the conversation worked")


# ---------- Memory ----------

func _memory_checks() -> void:
	game.minds.save()
	for p in [game.mo, game.bo]:
		check(FileAccess.file_exists(game.minds.of(p).file), "%s's memory is saved in its own file" % p.pal_name)
	var mo_m: Array = game.minds.mo.memory
	var bo_m: Array = game.minds.bo.memory
	check(" ".join(mo_m.map(func(x): return x.s)) != " ".join(bo_m.map(func(x): return x.s)), "their memories are their own (%d and %d entries)" % [mo_m.size(), bo_m.size()])
	note("plans now: Mo \"%s\", Bo \"%s\"" % [game.minds.mo.plan, game.minds.bo.plan])


func _memory() -> void:
	game.minds.quiet = true
	await game.wait(4.0)
	var n: int = game.minds.mo.memory.size()
	check(n > 8, "Mo remembers %d things from before" % n)
	var got := await say_wav("remember", "mo")
	var say: String = String(got.get("r", {}).get("say", "")).to_lower()
	var hit := ["plate", "door", "shadow", "ember", "dark", "torch", "bridge", "brazier"].filter(func(w): return say.contains(w))
	check(hit.size() > 0, "asked about the dungeon, Mo talks about what happened there (%s)" % ", ".join(hit))
	await until(func(): return not game.talking_now(), 15, "Mo to finish")
	await shot("12-remembers")
	finish("they remember")


# ---------- The real mic ----------

func _mic() -> void:
	game.minds.quiet = true
	await game.wait(4.0)
	check(game.minds.ears.on, "the microphone is listening")
	game.set_active(game.mo)
	var nh: int = game.minds.hears.size()
	print("WISP_MIC_OPEN")
	await until(func(): return game.minds.hears.size() > nh, 25, "the mic to hear the line")
	if game.minds.hears.size() > nh:
		var h: Dictionary = game.minds.hears[nh]
		var words := String(h.heard).to_lower()
		check(words.contains("mo") or words.contains("doing") or words.contains("over there"), "what was said aloud was heard (\"%s\")" % words)
		var nt: int = game.minds.stats.size()
		await until(func(): return game.minds.stats.slice(nt).any(func(x): return x.why == "heard"), 30, "Mo's answer")
	await game.wait(3.0)
	finish("the mic works")


func _report() -> void:
	var lines: Array = game.minds.stats
	var heard := lines.filter(func(x): return x.why == "heard")
	var firsts := heard.filter(func(x): return x.has("ms_first_word")).map(func(x): return x.ms_first_word)
	firsts.sort()
	var cost := 0.0
	for x in lines:
		cost += float(x.get("cost", 0.0))
	var spoken := lines.filter(func(x): return x.get("say", "") != "" and not x.has("dropped"))
	var distinct := {}
	for x in spoken:
		distinct[x.say] = true
	note("thoughts: %d, lines spoken: %d (%d different), you spoke to them %d times" % [lines.size(), spoken.size(), distinct.size(), heard.size()])
	if firsts.size():
		note("first word after the mic heard you stop: median %d ms, %d to %d ms" % [firsts[firsts.size() / 2], firsts[0], firsts[-1]])
	note("model cost: $%.4f in all, $%.5f a thought" % [cost, cost / max(1, lines.size())])
	var dropped := lines.filter(func(x): return x.has("dropped"))
	var rejected := lines.filter(func(x): return x.has("rejected") or x.get("checked", "ok") != "ok")
	note("lines held back: %d; actions refused: %d; mic: %d phrases, %d false starts, %.0f s deaf while they talked" % [dropped.size(), rejected.size(), game.minds.ears.stats.utterances, game.minds.ears.stats.false_starts, game.minds.ears.stats.gated_s])
