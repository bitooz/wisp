extends SceneTree
## Plans on their own, with fixed steps (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/plan_test.gd
## A day's plan, what they're on and the next step; finishing and giving up; three failed tries, dawdling and
## news calling for a rethink; a need that won't wait going first and then back to what they were on; the
## game's own plan when there's no model; in words for the model and the night; saving, and files from before.

var failed := false


func _init() -> void:
	_a_day()
	_rethinks()
	_needs()
	_fallback()
	_words()
	_saving()
	print("FAILED" if failed else "DONE: plans")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func plan() -> Plans:
	var p := Plans.new()
	p.make(1, [{text = "find out what's inside the glowing door", why = "I want to"}, "find a light", {text = "be home by dark"}], "model", 0.0)
	return p


func _a_day() -> void:
	var p := plan()
	check(p.day == 1 and p.items.size() == 3 and p.made_by == "model", "a plan for day one: three things")
	check(p.current().text == "find out what's inside the glowing door" and p.items[0].status == "doing", "what she's on now: the first")
	check(p.current() == p.current(), "and asking again doesn't change it (it's kept from thought to thought)")
	p.step = "walk up the path to the hill"
	p.finish(1.0)
	check(p.items[0].status == "done" and p.current().text == "find a light" and p.step == "", "done: on to the next, with a new step to choose")
	p.finish(2.0, "dropped")
	check(p.items[1].status == "dropped" and p.current().text == "be home by dark", "given up: on to the next")
	p.finish(3.0)
	check(p.current().is_empty(), "everything done: nothing left to be on")
	var long := Plans.new()
	long.make(1, ["a", "b", "c", "d", "e", "f", "g", ""], "model", 0.0)
	check(long.items.size() == 5, "never more than five things in a day")


func _rethinks() -> void:
	var p := plan()
	p.failed(1.0)
	p.failed(1.1)
	check(p.replan == "", "two tries that didn't work: keep at it")
	p.failed(1.2)
	check(p.replan.begins_with("three tries at \"find out what's inside the glowing door\""), "the third: time to rethink (\"%s\")" % p.replan)
	p.rethink(["find the second plate", "get Bo to stand on the other one"], 1.5)
	check(p.replan == "" and p.items.size() == 2 and p.current().text == "find the second plate", "rethought: the rest of the day is the new list")
	var d := plan()
	d.finish(0.5)
	for i in Plans.DAWDLE_THOUGHTS - 1:
		d.thought(1.0)
	check(d.replan == "", "eleven thoughts getting nowhere: not yet")
	d.thought(1.0)
	check(d.replan.begins_with("you've been at \"find a light\" a while and got nowhere"), "twelve: she notices she's dawdling (\"%s\")" % d.replan)
	var h := plan()
	h.thought(Plans.DAWDLE_H + .1)
	check(h.replan.begins_with("you've been at"), "or two hours lived without getting anywhere")
	var g := plan()
	for i in 20:
		g.thought(.1 * i)
		if i % 5 == 4:
			g.progressed(.1 * i)
	check(g.replan == "", "getting somewhere every few thoughts: no dawdling")
	var n := plan()
	n.news("the big stone door slid open", 1.0)
	check(n.replan == "something's changed: the big stone door slid open", "big news: time to rethink")
	n.news("something else", 1.1)
	check(n.replan.ends_with("door slid open"), "one rethink at a time")
	var keep := plan()
	keep.finish(1.0)
	keep.rethink(["x", "y"], 2.0)
	check(keep.items[0].status == "done" and keep.items[0].text == "find out what's inside the glowing door" and keep.items.size() == 3, "what's done stays done after a rethink")
	keep.rethink([], 3.0)
	check(keep.items.size() == 3, "a rethink with nothing in it changes nothing")


func _needs() -> void:
	var p := plan()
	p.urgent("hunger", "get something to eat", 1.0)
	check(p.current().text == "get something to eat" and p.items[1].status == "todo", "hungry: getting something to eat comes first; the door waits")
	p.urgent("hunger", "get something to eat", 1.1)
	check(p.items.filter(func(i): return i.get("need", "") == "hunger").size() == 1, "and only once")
	for i in 20:
		p.thought(1.2)
	check(p.replan == "", "seeing to a need isn't dawdling")
	p.needs_met(func(_n): return false, 1.3)
	check(p.current().text == "get something to eat", "still hungry: still on it")
	p.needs_met(func(n): return n == "hunger", 1.4)
	check(p.items[0].status == "done" and p.current().text == "find out what's inside the glowing door", "fed: back to what she was on")


func _fallback() -> void:
	var mo := Plans.fallback("mo", null, Heart.fresh("mo"), [], 8.0)
	var bo := Plans.fallback("bo", null, Heart.fresh("bo"), [], 8.0)
	check(mo[0].text == "gather windfalls for the larder" and mo[1].text == "find out what's inside the glowing door on the hill" and bo[1].text == "find a way across to the next island", "with no model, each plans their chore first thing, then what they want most")
	check(mo.any(func(i): return i.text == "look for shells for my jar") and bo.any(func(i): return i.text == "work on my model boat"), "and their hobby")
	check(mo.any(func(i): return i.text == "do it with Bo") and mo.back().text == "be home and in bed by dark", "Mo, fond of Bo, wants to do it with him; and home by dark")
	var b := Body.new("mo")
	b.hunger = .6
	var hungry := Plans.fallback("mo", b, Heart.fresh("mo"), ["find a light"], 8.0)
	check(hungry[0].text == "get something to eat" and hungry[1].text == "find a light", "hungry, food first; then what she didn't get to yesterday")
	check(JSON.stringify(Plans.fallback("mo", b, Heart.fresh("mo"), ["find a light"], 8.0)) == JSON.stringify(hungry), "the same every time")
	check(Plans.fallback("mo", null, null, [], 17.0).all(func(i): return i.text != "gather windfalls for the larder" and i.text != "look for shells for my jar"), "planning late in the day: no chore or hobby left to fit in")


func _words() -> void:
	var p := plan()
	p.finish(1.0)
	p.urgent("cold", "get warm", 1.5)
	check(p.lines() == ["(now) get warm", "(done) find out what's inside the glowing door", "(later) find a light", "(later) be home by dark"], "for the model: %s" % [p.lines()])
	var re := RegEx.create_from_string("[0-9]")
	check(p.lines().all(func(l): return re.search(l) == null), "words, no numbers")
	p.needs_met(func(_n): return true, 2.0)
	p.finish(3.0, "dropped")
	check(p.summary() == "did: get warm; find out what's inside the glowing door. gave up on: find a light. didn't get to: be home by dark", "for the night: \"%s\"" % p.summary())
	check(p.unfinished() == ["be home by dark"], "and what's left for tomorrow")


func _saving() -> void:
	var p := plan()
	p.step = "walk to the hill"
	p.failed(1.0)
	p.urgent("hunger", "get something to eat", 1.0)
	p.thought(1.2)
	var again := Plans.from_save(JSON.parse_string(JSON.stringify(p.to_save())))
	check(JSON.stringify(again.to_save()) == JSON.stringify(p.to_save()), "saved and loaded: just as it was")
	var old := Plans.from_save(null, "find a light so I can see in here")
	check(old.day == -1 and old.items.is_empty() and old.step == "find a light so I can see in here", "a file from before plans: the line they kept is their next step, and a day's plan comes on starting")
	for who in ["mo", "bo"]:
		var path := "user://mind_%s.json" % who
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var o = JSON.parse_string(text)
		var r := Plans.from_save(o.get("plans"), String(o.get("plan", "")))
		check(r.step == String(o.get("plan", "")) and r.day == -1, "%s's own file (read only): her plan line is kept as the next step" % who.capitalize() if who == "mo" else "%s's own file (read only): his plan line is kept as the next step" % who.capitalize())
		check(FileAccess.get_file_as_string(path) == text, "%s's file is untouched" % who.capitalize())
