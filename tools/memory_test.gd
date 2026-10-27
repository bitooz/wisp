extends SceneTree
## The memory stream on its own, with fixed steps (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/memory_test.gd
## Importance, fading (hazy, then forgotten) and how recalling something keeps it, blurring and misremembering,
## what's picked for a thought (recent + important + relevant, not just the newest), when things were, what
## goes to the night's reflection and how beliefs are kept, and bringing older memory files up to date with
## nothing lost (including a dry run on the game's own Mo and Bo files, read only: nothing is written).

const SEEDS := preload("res://scripts/mind.gd").SEEDS

var failed := false


func _init() -> void:
	_importance()
	_fading()
	_recall_keeps()
	_blur()
	_retrieval()
	_when()
	_reflection()
	_cap()
	_migration()
	_real_files()
	print("FAILED" if failed else "DONE: the memory stream")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


## Live `hours` of game time an hour at a time.
func live(m: Memory, hours: int) -> void:
	for i in hours:
		m.pass_time(1.0)


func find(m: Memory, text: String) -> Dictionary:
	for e in m.entries:
		if e.s == text or e.get("was", "") == text:
			return e
	return {}


func _importance() -> void:
	var lunge := Memory.importance("felt", "something cold lunged at you and you jumped back")
	var walk := Memory.importance("did", "walked over to the spot I'd pointed at")
	check(lunge > walk + 2, "a fright matters more than a stroll (%d against %d)" % [lunge, walk])
	check(Memory.importance("note", "I want to see what's behind the door") == 7, "a note they chose to keep: 7")
	check(Memory.importance("told", "Wisp said: \"I promise I'll help\"") > Memory.importance("heard", "a soft thud, behind you, close by"), "a promise from Wisp matters more than a thud")
	var m := Memory.seeded("mo", SEEDS.mo)
	check(m.entries.size() == 6 and m.entries.all(func(e): return e.seed and e.imp == 10), "what they knew before: six seeds, importance 10")
	var n := m.entries.size()
	m.add("saw", "a red apple")
	m.add("saw", "a red apple")
	check(m.entries.size() == n + 1, "the same thing twice in a row is once")


func _fading() -> void:
	var m := Memory.seeded("mo", SEEDS.mo)
	var small := m.add("did", "walked over to the spot I'd pointed at, by the stump")
	var big := m.add("felt", "something cold lunged at you and you jumped back")
	m.add("belief", "Bo is braver than he lets on.", 8)
	check(small.imp <= 2 and big.imp >= 5, "a small thing and a big one (%d, %d)" % [small.imp, big.imp])
	live(m, 12)
	check(m.strength(small) < .5 and m.strength(big) > .7, "half a day on, the small thing is fading (%.2f), the big one isn't (%.2f)" % [m.strength(small), m.strength(big)])
	live(m, 12)
	var s := find(m, "walked over to the spot I'd pointed at, by the stump")
	check(not s.is_empty() and s.get("hazy", false) and s.s == "walked over to the spot I'd pointed at", "a day on, it's hazy: the details have gone (\"%s\")" % s.get("s", ""))
	live(m, 24)
	check(find(m, "walked over to the spot I'd pointed at, by the stump").is_empty() and m.forgotten == 1, "two days on, it's forgotten")
	check(not find(m, "something cold lunged at you and you jumped back").is_empty(), "the fright is still there")
	live(m, 24 * 14)
	check(find(m, "something cold lunged at you and you jumped back").is_empty(), "two weeks on, even the fright has gone")
	check(m.entries.filter(func(e): return e.get("seed", false)).size() == 6 and not find(m, "Bo is braver than he lets on.").is_empty(), "but Grandma's stories, their goals and what they believe never fade")


func _recall_keeps() -> void:
	var m := Memory.new("bo")
	m.add("told", "Mo said: \"the plates have rings like the door\"")
	m.add("told", "Mo said: \"my shoelace is untied\"")
	for i in 24:
		live(m, 4)
		m.recall("plates rings door", 0, 1)
	check(not find(m, "Mo said: \"the plates have rings like the door\"").is_empty(), "something brought to mind again and again stays (four days on)")
	check(find(m, "Mo said: \"my shoelace is untied\"").is_empty(), "the same kind of thing never thought of again is forgotten")


func _blur() -> void:
	check(Memory.blur("saw the old brazier on the shore, cold and empty", 1) == "saw the old brazier on the shore", "hazy: the detail after the gist goes")
	check(Memory.blur("heard a splash of water, to your left, close by", 3) == "heard a splash of water", "a sound's direction is one of the first details to go")
	check(Memory.blur("the ember is on the left plate", 3) == "the ember is on the right plate", "now and then a detail comes back wrong: left for right")
	check(Memory.blur("Bo said: \"take the torch\"", 6, "mo") == "Wisp said: \"take the torch\"", "or who said it")
	check(Memory.blur("Bo said the torch is on the left", 6, "mo") == "Wisp said the torch is on the left", "who said what gets muddled, for Mo between Bo and Wisp")
	check(Memory.blur("the ember is on the left plate", 4) == "the ember is on the left plate", "but mostly what's left of it is right")
	check(Memory.blur("saw a big, red apple, under the tree", 9) == Memory.blur("saw a big, red apple, under the tree", 9), "the same memory always blurs the same way")
	var m := Memory.new("mo")
	var e := m.add("saw", "a lantern on a stump, glowing")
	live(m, 30)
	var h := find(m, "a lantern on a stump, glowing")
	check(h.get("hazy", false) and h.was == "a lantern on a stump, glowing" and m.lines([h])[0].ends_with("(I don't remember it clearly)"), "a hazy memory says so when it comes to mind: \"%s\"" % m.lines([h])[0])


func _retrieval() -> void:
	var m := Memory.seeded("mo", SEEDS.mo)
	m.add("event", "something cold lunged at you and you jumped back")
	m.add("told", "Bo said: \"the two plates both have to be held down\"")
	live(m, 30)
	for i in 120:
		m.add("did", "walked over to the spot I'd pointed at (%d)" % i)
		m.pass_time(.05)
	var newest := m.entries.slice(m.entries.size() - 8)
	var got := m.recall("two plates and the big door, how do they open", 8, 28)
	check(got.size() == 28, "a thought gets 28 memories, out of %d" % m.entries.size())
	check(newest.all(func(e): return got.has(e)), "the last 8 things are always there (what they were just doing)")
	check(got.any(func(e): return e.s.contains("two plates both have to be held")), "an old one that's to do with what's on her mind comes back")
	check(got.any(func(e): return e.s.contains("lunged")), "and an old fright, because it mattered")
	check(got.any(func(e): return e.s.contains("only opens for two") or e.s.contains("hums when it wants to be opened")), "and what Grandma said about the door")
	var ids := got.map(func(e): return int(e.id))
	var sorted := ids.duplicate()
	sorted.sort()
	check(ids == sorted, "in the order they happened")
	var plain := m.recall("", 8, 28)
	check(plain.filter(func(e): return e.s.begins_with("walked over")).size() < 28, "even with nothing on her mind, it's not just the newest")
	check(got.all(func(e): return e.k != "said"), "her own lines don't come back this way (they go as lines not to repeat)")
	var before := m.strength(find(m, "Bo said: \"the two plates both have to be held down\""))
	check(is_equal_approx(before, 1.0), "recalled just now: as strong as new")


func _when() -> void:
	var m := Memory.new("mo")
	var a := m.add("did", "ate an apple")
	check(m.when(a) == "just now", "just now")
	m.pass_time(1.0)
	check(m.when(a) == "a little while ago", "an hour on: a little while ago")
	m.pass_time(4.0)
	check(m.when(a) == "earlier today", "five hours on: earlier today")
	m.day += 1
	check(m.when(a) == "yesterday", "the next morning: yesterday")
	m.day += 2
	check(m.when(a) == "3 days ago", "and then: 3 days ago")


func _reflection() -> void:
	var m := Memory.seeded("bo", SEEDS.bo)
	m.reflected_h = m.life_h
	m.pass_time(.1)
	m.add("said", "I said: \"Let's go\"")
	m.add("felt", "the stone under your feet sank with a heavy click")
	m.add("heard", "a long, deep grinding of stone, muffled, ahead of you, far off")
	var list := m.for_reflection()
	check(list.size() == 2 and list.all(func(x): return not x.line.contains("Let's go")), "the day to reflect on: since last time, not what they said themselves, nor the seeds")
	for i in 80:
		m.add("did", "wandered about a bit (%d)" % i)
	m.add("event", "the big stone door slid open")
	list = m.for_reflection()
	check(list.size() == 40 and list.any(func(x): return x.line.contains("door slid open")) and list.any(func(x): return x.line.contains("sank with a heavy click")), "a long day: the 40 that matter most (the door opening is in)")
	var ids := list.map(func(x): return int(x.id))
	var s := ids.duplicate()
	s.sort()
	check(ids == s, "in order")
	var added := m.add_beliefs([{text = "The door only opens with both of us on the plates.", importance = 9, from = [ids[0]]},
		{text = "Mo rushes in.", importance = 7}, {text = "The door only opens with both of us on the plates.", importance = 9},
		{text = "Fourth thing.", importance = 7}])
	check(added.size() == 2, "beliefs added: at most three, no repeats (%d)" % added.size())
	check(added[0].k == "belief" and added[0].imp == 9 and added[0].from == [ids[0]], "a belief remembers what it came from")
	for i in 20:
		m.add_beliefs([{text = "Small belief %d." % i, importance = 6}])
	var beliefs := m.entries.filter(func(e): return e.k == "belief")
	check(beliefs.size() == Memory.BELIEFS and beliefs.any(func(e): return e.s.begins_with("The door only opens")), "at most %d beliefs, the most important kept" % Memory.BELIEFS)
	m.reflected_h = m.life_h
	m.pass_time(.1)
	m.add("did", "ate an apple")
	check(m.for_reflection().size() == 1, "after reflecting, the next night's starts from there")


func _cap() -> void:
	var m := Memory.seeded("mo", SEEDS.mo)
	m.add("belief", "Wisp is a friend.", 8)
	for i in 700:
		m.add("did", "did thing %d" % i, 1 + i % 5)
	check(m.entries.size() == Memory.CAP, "never more than %d memories" % Memory.CAP)
	check(m.entries.filter(func(e): return e.get("seed", false)).size() == 6 and not find(m, "Wisp is a friend.").is_empty(), "the ones that make room are never seeds or beliefs")


func _migration() -> void:
	# A file from before: {who, plan, memory: [{t, k, s}]}
	var old := {who = "mo", plan = "find the torch", memory = []}
	for s in SEEDS.mo:
		old.memory.append({t = 1000.0, k = s[0], s = s[1]})
	for i in 50:
		old.memory.append({t = 2000.0 + i, k = ["saw", "did", "told", "said", "event"][i % 5], s = "thing %d, with a detail" % i})
	var m := Memory.from_save(old, "mo", SEEDS.mo)
	check(m.entries.size() == old.memory.size(), "brought up to date: all %d memories kept" % old.memory.size())
	var same := true
	for i in old.memory.size():
		var a: Dictionary = old.memory[i]
		var b: Dictionary = m.entries[i]
		if a.k != b.k or a.s != b.s or a.t != b.t:
			same = false
	check(same, "each one as it was (kind, words, time), in the same order")
	check(m.entries.slice(0, 6).all(func(e): return e.get("seed", false)) and m.entries.slice(6).all(func(e): return not e.get("seed", false)), "Grandma's stories and their goals are known as such")
	check(m.entries.all(func(e): return e.has("imp") and m.when(e) == "yesterday"), "each has an importance, and it all happened before today")
	var again := Memory.from_save(JSON.parse_string(JSON.stringify(m.to_save())), "mo", SEEDS.mo)
	check(JSON.stringify(again.to_save()) == JSON.stringify(m.to_save()), "saved and loaded again, nothing changes")
	live(m, 1)
	check(m.entries.size() == old.memory.size(), "and nothing starts fading straight away")


## The game's own Mo and Bo files, read only: would they come through with nothing lost?
func _real_files() -> void:
	for who in ["mo", "bo"]:
		var path := "user://mind_%s.json" % who
		if not FileAccess.file_exists(path):
			print("(no %s to try)" % path)
			continue
		var text := FileAccess.get_file_as_string(path)
		var o = JSON.parse_string(text)
		var list: Array = o.memory
		var m := Memory.from_save(o, who, SEEDS[who])
		var kept := m.entries.size() == list.size()
		for i in list.size():
			if not kept:
				break
			kept = list[i].k == m.entries[i].k and list[i].s == m.entries[i].s and float(list[i].t) == float(m.entries[i].t)
		check(kept, "%s's own file (%d memories): every one comes through, in order (read only)" % [who.capitalize(), list.size()])
		# The seeds are the entries written first, all at the same moment
		var lead := 0
		while lead < list.size() and float(list[lead].t) == float(list[0].t):
			lead += 1
		var flagged := m.entries.filter(func(e): return e.get("seed", false)).size()
		check(flagged == mini(lead, SEEDS[who].size()) if int(o.get("v", 1)) < Memory.VERSION else true, "%s's seeds are found (%d)" % [who.capitalize(), flagged])
		check(FileAccess.get_file_as_string(path) == text, "%s's file is untouched" % who.capitalize())
