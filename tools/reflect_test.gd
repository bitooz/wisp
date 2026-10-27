extends Node
## Memory in the real game, with no model (a stand-in reflects for them):
##   godot --path . -- --autoplay --autoplay-script=res://tools/reflect_test.gd --offline
## Going to sleep at night turns the day over into beliefs: once per pal per night, only the day since the last
## time, kept through a failed night, saved and loaded, and brought to mind in later thoughts. Time lived and
## days counted go with the game's clock. Prints ok:/FAIL:, exits non-zero on a failure.

const StandIn := preload("res://tools/standin.gd")

var game: Game
var args: Array = []
var failed := false
var standin
var m: Mind
var b: Mind


func _ready() -> void:
	if game.minds.on:
		note("FAIL: the minds are on; run with --offline (this test must not call the model)")
		get_tree().quit(2)
		return
	m = game.minds.mo
	b = game.minds.bo
	for x in [m, b]:
		if not x.file.contains("/offline/"):
			note("FAIL: the minds' memories aren't the test's own (%s)" % x.file)
			get_tree().quit(2)
			return
	await _old_file()
	for x in [m, b]:
		x.forget_all()
	standin = StandIn.new(game)
	game.minds.quiet = true
	game.controls = false
	game.clock.stopped = true
	await game.wait(.5)
	await _nights()
	await _no_model_no_call()
	note("FAILED" if failed else "DONE: reflecting each night")
	get_tree().quit(1 if failed else 0)


func note(s: String) -> void:
	print("[reflect %6.1fs] %s" % [Time.get_ticks_msec() / 1000.0, s])


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


func beliefs(x: Mind) -> Array:
	return x.memory.filter(func(e): return e.k == "belief")


## Fall asleep where they stand (tired enough), and wait a moment for the night's reflection.
func sleep(x: Mind) -> void:
	x.task = {}
	x.body.tired = .8
	x.body.hunger = .2
	x.body.cold = 0.0
	x.body.fear = 0.0
	x.start("sleep", {})
	await game.wait(.3)


func wake(x: Mind) -> void:
	if x.body.asleep:
		x.wake("rested")


## The clock on to `hour` (the next time it comes round), an hour a third of a second.
func until_hour(hour: float) -> void:
	game.clock.rate = 3.0
	game.clock.stopped = false
	await until(func(): return absf(game.clock.hour() - hour) < .1, 30)
	game.clock.stopped = true
	game.clock.rate = 24.0 / (Clock.DAY_MINUTES * 60.0)


func _nights() -> void:
	game.minds.reflector = standin.reflect
	game.clock.set_hour(20)
	var life0: float = m.mem.life_h
	var day0: int = m.mem.day
	# A day: something big, a fright, and a lot of small things
	m.remember("event", "the big stone door slid open")
	m.remember("felt", "something cold lunged at you and you jumped back")
	for i in 10:
		m.remember("did", "wandered about a bit (%d)" % i)
	var first_ids: Array = m.memory.slice(-12).map(func(e): return int(e.id))
	var seed_ids: Array = m.memory.filter(func(e): return e.get("seed", false)).map(func(e): return int(e.id))
	await sleep(m)
	check(m.body.asleep and standin.reflect_calls.mo == 1, "Mo falls asleep at night: her day is turned over once")
	var got: Array = standin.reflect_got.mo[0]
	var got_ids: Array = got.map(func(x): return int(x.id))
	check(first_ids.all(func(i): return got_ids.has(i)) and not got_ids.any(func(i): return seed_ids.has(i)), "it's the day she had (%d memories, with falling asleep), not what she knew before" % got.size())
	var bel := beliefs(m)
	check(bel.size() == 2 and bel.all(func(e): return e.imp >= 6 and e.from.size() == 1), "two beliefs come of it, each pointing back at what it came from")
	check(bel.any(func(e): return e.s.contains("door slid open")) and bel.any(func(e): return e.s.contains("lunged")), "from what mattered most: the door and the fright: %s" % [bel.map(func(e): return e.s)])
	check(game.minds.reflections.size() == 1 and game.minds.reflections[0].beliefs.size() == 2, "and it's logged (WISP_REFLECT)")
	# Woken and back to sleep the same night: no second reflection
	game._booped(m.pal)
	check(not m.body.asleep, "a boop wakes her")
	await sleep(m)
	check(m.body.asleep and standin.reflect_calls.mo == 1, "back to sleep the same night: no second reflection")
	# Bo has his own
	b.remember("told", "Mo said: \"the plates have rings like the door\"")
	await sleep(b)
	check(standin.reflect_calls.bo == 1 and beliefs(b).size() >= 1, "Bo reflects on his own day, once")
	# Morning
	await until_hour(7)
	check(m.mem.day == day0 + 1 and b.mem.day == day0 + 1, "a new morning: one more day lived, for each of them")
	check(m.mem.life_h - life0 > 10.0, "and the hours of the night were lived (%.1f h)" % (m.mem.life_h - life0))
	check(beliefs(m)[0].get("d", 0) == day0 and m.mem.when(beliefs(m)[0]) == "yesterday", "last night's beliefs are from yesterday now")
	wake(m)
	wake(b)
	# Day two
	var mark: int = m.mem.next_id
	var b_beliefs := beliefs(b).size()
	m.remember("told", "Wisp said: \"I'll hold the torch for you\"")
	m.remember("did", "ate an apple")
	b.remember("did", "stood on a stone plate and it sank")
	var b_mark: int = b.mem.next_id - 1
	standin.reflect_fail.bo = true
	await until_hour(21)
	await sleep(m)
	await sleep(b)
	check(standin.reflect_calls.mo == 2, "the next night, Mo reflects again")
	var second: Array = standin.reflect_got.mo[1]
	var ids2: Array = second.map(func(x): return int(x.id))
	check(not ids2.any(func(i): return got_ids.has(i)) and ids2.has(mark) and ids2.has(mark + 1), "on what's happened since only (%d memories: the day, and waking in the night)" % second.size())
	check(standin.reflect_calls.bo == 2 and beliefs(b).size() == b_beliefs, "Bo's second night: the reflection fails, and no beliefs come of it")
	await until_hour(7)
	wake(m)
	wake(b)
	standin.reflect_fail.bo = false
	await until_hour(21)
	await sleep(b)
	var third: Array = standin.reflect_got.bo[2]
	check(standin.reflect_calls.bo == 3 and third.any(func(x): return int(x.id) == b_mark), "the night after, his reflection takes in the day it missed too")
	# Saved and loaded
	m.save()
	var n_bel := beliefs(m).size()
	var life: float = m.mem.life_h
	var day: int = m.mem.day
	m.load_memory()
	check(beliefs(m).size() == n_bel and is_equal_approx(m.mem.life_h, life) and m.mem.day == day, "saved and loaded: beliefs, hours lived and days all kept (%d/%d beliefs, %.4f/%.4f h, day %d/%d)" % [beliefs(m).size(), n_bel, m.mem.life_h, life, m.mem.day, day])
	var f = JSON.parse_string(FileAccess.get_file_as_string(m.file))
	check(f is Dictionary and int(f.v) == Memory.VERSION and f.memory.any(func(e): return e.k == "belief"), "the file is the new kind, beliefs and all")
	# Later, they come to mind
	wake(m)
	var lines := m.memory_lines(m.on_mind("the stone door"))
	check(lines.any(func(l): return l.contains("(something I've come to believe)") and l.contains("door slid open")), "thinking about the door later, her belief about it comes to mind")
	await until_hour(7)
	wake(m)
	wake(b)


## An old memory file (a copy of the game's own Mo file, read only, put in the test's folder) is brought up to
## date on loading: nothing lost, and the old one kept beside it.
func _old_file() -> void:
	var real := "user://mind_mo.json"
	var text := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else ""
	var o = JSON.parse_string(text) if text != "" else null
	if not (o is Dictionary) or int(o.get("v", 1)) >= Memory.VERSION:
		# No old file to copy: make one the old way
		o = {who = "mo", plan = "see inside the door", memory = Mind.SEEDS.mo.map(func(s): return {t = 1000.0, k = s[0], s = s[1]})}
		for i in 40:
			o.memory.append({t = 2000.0 + i, k = "did", s = "did thing %d" % i})
		text = JSON.stringify(o)
	var old_copy := m.file.get_basename() + ".v1.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_copy))
	var f := FileAccess.open(m.file, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	m.load_memory()
	var kept: bool = m.memory.size() == o.memory.size()
	for i in o.memory.size():
		if not kept:
			break
		kept = m.memory[i].s == o.memory[i].s and m.memory[i].k == o.memory[i].k
	check(kept, "an old file (%d memories) comes through on loading with every memory, in order" % o.memory.size())
	check(FileAccess.file_exists(old_copy) and FileAccess.get_file_as_string(old_copy) == text, "the old file is kept beside it, as it was")
	var now = JSON.parse_string(FileAccess.get_file_as_string(m.file))
	check(now is Dictionary and int(now.v) == Memory.VERSION and now.memory.size() == o.memory.size() and String(now.plan) == String(o.get("plan", "")), "and it's saved the new way (plan and all)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_copy))


## With no model and no stand-in, falling asleep calls nothing (and the day waits for a night that can).
func _no_model_no_call() -> void:
	game.minds.reflector = Callable()
	await until_hour(21)
	var n: int = game.minds.reflections.size()
	var was: int = m.mem.reflected_day
	m.remember("did", "ate an apple")
	await sleep(m)
	check(game.minds.reflections.size() == n and m.mem.reflected_day == was, "offline, going to sleep calls nothing, and the day keeps")
	wake(m)
