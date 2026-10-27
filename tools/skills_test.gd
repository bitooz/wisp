extends SceneTree
## Skills on their own, with fixed steps (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/skills_test.gd
## Who's good at what to start with, tries that fail more for a beginner but never more than three in a row,
## getting better with practice and slipping without it, sharper eyes in the dark, lessons, what they could
## catch someone out on, in words, and saving.

var failed := false


func _init() -> void:
	_who()
	_tries()
	_practice()
	_slipping()
	_eyes_and_words()
	_claims()
	_saving()
	print("FAILED" if failed else "DONE: skills")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func _who() -> void:
	var mo := Skills.fresh("mo")
	var bo := Skills.fresh("bo")
	check(bo.level.mechanisms > mo.level.mechanisms and bo.level.chopping > mo.level.chopping and bo.level.building > mo.level.building, "Bo starts handier: tools, building, mechanisms")
	check(mo.level.wayfinding > bo.level.wayfinding and mo.level.night_eyes > bo.level.night_eyes, "Mo starts better at finding her way, and sharper-eyed in the dark")
	check(mo.chance("chopping") < bo.chance("chopping") and bo.chance("chopping", .2) < bo.chance("chopping"), "a beginner's try goes less often; a harder one, less often still")


## n tries; how many worked, and the longest run of failures.
func run(s: Skills, skill: String, n: int, difficulty := 0.0) -> Dictionary:
	var ok := 0
	var row := 0
	var worst := 0
	for i in n:
		if s.attempt(skill, difficulty, float(i)):
			ok += 1
			row = 0
		else:
			row += 1
			worst = maxi(worst, row)
	return {ok = ok, worst = worst}


func _tries() -> void:
	var first := run(Skills.fresh("mo"), "chopping", 20)
	check(first.ok > 0 and first.ok < 20, "Mo's first twenty goes at chopping: %d worked, %d didn't" % [first.ok, 20 - first.ok])
	var a := run(Skills.fresh("mo"), "chopping", 20)
	check(JSON.stringify(a) == JSON.stringify(first), "the same every run")
	var worst := 0
	for who in ["mo", "bo"]:
		for k in Skills.ALL:
			worst = maxi(worst, run(Skills.fresh(who), k, 300, .25).worst)
	check(worst <= Skills.MOST_FAILS, "never more than %d failures in a row, at anything, even when it's hard (worst: %d)" % [Skills.MOST_FAILS, worst])
	var s := Skills.fresh("mo")
	s.level.chopping = .95
	var expert := run(s, "chopping", 100)
	check(expert.ok >= 85, "someone really good at it hardly ever fails (%d of 100)" % expert.ok)


func _practice() -> void:
	var s := Skills.fresh("mo")
	var early := run(s, "chopping", 30)
	var l: float = s.level.chopping
	var late := run(s, "chopping", 30)
	check(l > .55 and s.level.chopping > l, "practice makes her better at it (%.2f after thirty goes, %.2f after sixty)" % [l, s.level.chopping])
	check(late.ok > early.ok, "and it shows: %d of the first thirty went, %d of the next" % [early.ok, late.ok])
	var f := Skills.fresh("bo")
	var b: float = f.level.building
	f.practice("building", false, 0.0)
	check(f.level.building > b and f.level.building - b < .05, "failing teaches a little too")
	check(f.lessons.is_empty(), "practice alone leaves no lesson")
	for i in 3:
		f.attempt("building", .9, 1.0)
	check(f.lessons.get("building", "") == Skills.LESSONS.building and f.learned(["building", "chopping"]) == [Skills.LESSONS.building], "failing leaves a lesson, about what failed")


func _slipping() -> void:
	var s := Skills.fresh("bo")
	for i in 40:
		s.attempt("chopping", 0.0, 10.0)
	var high: float = s.level.chopping
	s.pass_time(20.0, 30.0)
	check(s.level.chopping == high, "a day off: nothing lost")
	s.pass_time(24.0 * 7, 10.0 + 24.0 * 8)
	var week: float = s.level.chopping
	check(week < high and week > s.base.chopping + (high - s.base.chopping) * .6, "a week without chopping: a little rusty (%.2f from %.2f)" % [week, high])
	s.pass_time(24.0 * 90, 10.0 + 24.0 * 98)
	check(s.level.chopping >= s.base.chopping and s.level.chopping < week, "months without: back near where he started, never below (%.2f)" % s.level.chopping)


func _eyes_and_words() -> void:
	var s := Skills.fresh("mo")
	s.level.night_eyes = 0.0
	var blind := s.dark_need()
	s.level.night_eyes = 1.0
	check(s.dark_need() < blind, "sharp eyes need less light to see by (%.2f against %.2f)" % [s.dark_need(), blind])
	var said := []
	for l in [0.0, .4, .6, .9]:
		for k in Skills.ALL:
			s.level[k] = l
			said.append(s.words(k))
	var re := RegEx.create_from_string("[0-9]")
	check(said.all(func(w): return re.search(w) == null) and said.has("you're new to chopping wood and still learning") and said.has("you're really good at finding your way"), "in words, no numbers")


func _claims() -> void:
	var yes := {"I don't have the torch": ["not_holding", "torch"], "Mo, I haven't got your apple!": ["not_holding", "apple"],
		"I'm not holding the lantern.": ["not_holding", "lantern"], "Me? I'm not scared.": ["not_scared", ""], "Not scared at all.": ["not_scared", ""],
		"The door won't open, Mo.": ["door_stuck", "door"], "The door's stuck.": ["door_stuck", "door"], "I can't open the door.": ["door_stuck", "door"]}
	var ok := true
	for t in yes:
		var c := Skills.claim(t)
		if c.get("kind", "") != yes[t][0] or c.get("subject", "") != yes[t][1]:
			ok = false
			print("  %s -> %s" % [t, c])
	check(ok, "things they could catch someone out on are noticed (%d kinds of saying)" % yes.size())
	check(["I don't know", "I don't think so", "Let's go to the door", "I'm scared", "Open the door!"].all(func(t): return Skills.claim(t).is_empty()), "and plain talk isn't taken for one")


func _saving() -> void:
	var s := Skills.fresh("bo")
	run(s, "mechanisms", 7, .5)
	var again := Skills.from_save(JSON.parse_string(JSON.stringify(s.to_save())), "bo")
	check(JSON.stringify(again.to_save()) == JSON.stringify(s.to_save()), "saved and loaded: as they were")
	check(JSON.stringify(Skills.from_save(null, "mo").to_save()) == JSON.stringify(Skills.fresh("mo").to_save()), "a file from before: where they start")
