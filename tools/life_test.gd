extends SceneTree
## Their own lives and catching up, on their own, with fixed steps (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/life_test.gd
## Each one's daily round, how real time away becomes island time, and catching up after gaps from minutes to a
## year: their bodies, moods, feelings, chores, hobbies, meals, what they remember (and forget), plans for the
## days between, and the island's own things. However long the gap, it stays quick and the same every time.

var failed := false
const SEEDS := preload("res://scripts/mind.gd").SEEDS


func _init() -> void:
	_round()
	_time_away()
	_short()
	_a_day()
	_a_week()
	_a_year()
	_same_every_time()
	print("FAILED" if failed else "DONE: their own lives")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


## The two of them as they'd be, with a little history.
func pals() -> Array:
	var out := []
	for who in ["mo", "bo"]:
		var mem := Memory.seeded(who, SEEDS[who])
		mem.add("did", "walked over to the spot I'd pointed at, by the stump", 2)
		mem.add("event", "the big stone door slid open", 8)
		var body := Body.new(who)
		var plans := Plans.new()
		plans.make(mem.day, Plans.fallback(who, body, Heart.fresh(who), [], 8.0), "fallback", mem.life_h)
		out.append({who = who, mem = mem, body = body, heart = Heart.fresh(who), plans = plans})
	return out


func find(p: Dictionary, has: String) -> Array:
	return p.mem.entries.filter(func(e): return String(e.s).contains(has) or String(e.get("was", "")).contains(has))


func _round() -> void:
	var mo := [3.0, 7.5, 9.0, 11.0, 13.0, 14.0, 17.5, 19.0, 20.0, 22.0].map(func(h): return Life.doing("mo", h))
	check(mo == ["sleep", "breakfast", "chore", "own", "lunch", "hobby", "free", "supper", "campfire", "sleep"], "Mo's day: %s" % [mo])
	check(Life.doing("bo", 6.75) == "breakfast" and Life.doing("mo", 6.75) == "sleep" and Life.doing("bo", 21.2) == "sleep" and Life.doing("mo", 21.2) == "campfire", "Bo's up earlier and in bed earlier")
	check(Life.routine("mo")[0] == "your chore: gather windfalls for the larder, in the morning" and Life.routine("bo")[1] == "your hobby: work on my model boat, in the afternoon", "their chores and hobbies, in words for the morning's plan")


func _time_away() -> void:
	var rate := 24.0 / (Clock.DAY_MINUTES * 60.0)
	check(Life.away_hours(0.0, rate) == 0.0 and is_equal_approx(Life.away_hours(600.0, rate), 10.0), "ten minutes away: ten hours on the island (the usual pace)")
	check(is_equal_approx(Life.away_hours(1440.0, rate), 24.0), "twenty-four minutes: a day")
	var day := Life.away_hours(86400.0, rate)
	var week := Life.away_hours(7 * 86400.0, rate)
	check(day > 47.0 and day < 48.0 and week > 191.0 and week < 192.0, "after that, a day for a day: a real day away is about two island days (%.1f h), a week about eight (%.1f h)" % [day, week])
	check(Life.gap_words(1.0, 0) == "A little later" and Life.gap_words(10.0, 0) == "Later that day" and Life.gap_words(20.0, 0, 5.0) == "Later that night" and Life.gap_words(30.0, 1) == "The next day" and Life.gap_words(80.0, 3) == "Three days later" and Life.gap_words(200.0, 8) == "A week later" and Life.gap_words(9000.0, 366) == "A long time later", "how long it's been, in words")
	check(Life.gone_words(2) == "for two days" and Life.gone_words(9) == "for about a week", "and how long someone was gone")


func _short() -> void:
	var ps := pals()
	var world := Life.fresh_world()
	var h0: float = ps[0].body.hunger
	var r := Life.catch_up(ps, world, 9.0, 3.0)
	check(r.days == 0 and r.now.mo == "own" and r.now.bo == "own", "three hours from nine: same day, they're off on their own now")
	check(ps[0].body.hunger > h0 and not ps[0].body.asleep, "a bit hungrier, still up")
	check(ps[0].mem.day == 1 and is_equal_approx(ps[0].mem.life_h, 3.0), "three hours lived")


func _a_day() -> void:
	var ps := pals()
	var world := Life.fresh_world()
	var fond: float = ps[0].heart.rel.bo.fond
	var r := Life.catch_up(ps, world, 20.0, 24.6)
	var mo: Dictionary = ps[0]
	var bo: Dictionary = ps[1]
	check(r.days == 1 and mo.mem.day == 2 and bo.mem.day == 2, "from eight in the evening to the next evening: a day")
	check(r.now.mo == "campfire" and not mo.body.asleep, "back by the campfire")
	check(world.boat > 0.0 and world.jar == 2 and world.wood == 6 + 2 - 1, "Bo worked on his boat, Mo found two shells, Bo chopped wood, and the fire took a log this evening (last night's was lit before; %s)" % [world])
	check(find(bo, "chopped wood").size() == 1 and find(bo, "worked on my model boat").size() == 1 and find(mo, "found two shells").size() == 1 and find(mo, "gathered").size() == 1, "and each remembers their day")
	check(find(mo, "sat by the campfire with Bo").size() == 1 and mo.heart.rel.bo.fond > fond, "an evening by the campfire together: a little closer")
	check(r.remembered.mo < 10 and r.remembered.bo < 10, "a handful of memories for a day, not every minute (%d, %d)" % [r.remembered.mo, r.remembered.bo])
	check(mo.body.hunger < .6 and mo.body.cold < .3 and mo.body.fear < .3, "fed and warm, as you'd be by the fire after supper")
	check(mo.plans.day == mo.mem.day - 1, "today's plan isn't made here (the game asks for it, once)")


func _a_week() -> void:
	var ps := pals()
	var world := Life.fresh_world()
	var t0 := Time.get_ticks_usec()
	var hours := Life.away_hours(7 * 86400.0, 24.0 / (Clock.DAY_MINUTES * 60.0))
	var r := Life.catch_up(ps, world, 14.0, hours)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var mo: Dictionary = ps[0]
	check(r.days == 8 and mo.mem.day == 9, "a week away: eight island days")
	check(find(mo, "went by much as usual").size() == 1 and find(mo, "the five days before that went by much as usual: gathering windfalls for the larder, looking for shells for my jar").size() == 1, "the days before the last few, in one memory: \"%s\"" % [find(mo, "much as usual").map(func(e): return e.get("was", e.s))])
	check(find(mo, "found two shells").size() == 3, "the last three days, day by day")
	check(r.remembered.mo < 20, "a few dozen memories at most for a week (%d)" % r.remembered.mo)
	check(find(mo, "by the stump").is_empty() and not find(mo, "door slid open").is_empty(), "a week on, a small thing from before is forgotten; the big one isn't")
	check(world.boat >= .79 and world.jar == 16 and world.wood <= 12, "Bo's boat is nearly done (%s), Mo's jar has sixteen shells, the woodpile's never more than full" % Life.boat_words(world.boat))
	check(absf(mo.heart.v - mo.heart.base_v) < .25, "Mo's mood is her usual")
	check(mo.plans.day == mo.mem.day - 1 and mo.plans.made_by == "routine", "the days between had plans of their own (no model); today's is still to make")
	check(ms < 100.0, "and it took %.1f ms" % ms)


func _a_year() -> void:
	var ps := pals()
	var world := Life.fresh_world()
	var t0 := Time.get_ticks_usec()
	var hours := Life.away_hours(365 * 86400.0, 24.0 / (Clock.DAY_MINUTES * 60.0))
	var r := Life.catch_up(ps, world, 10.0, hours)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var mo: Dictionary = ps[0]
	check(r.days > 360 and mo.mem.day > 360, "a year away: %d island days" % r.days)
	check(not find(mo, "a long time before that went by much as usual").is_empty(), "\"a long time\", in one memory")
	check(world.boat == 1.0 and world.wood <= 12, "Bo's boat is long finished")
	check(mo.mem.entries.filter(func(e): return e.get("seed", false)).size() == 6, "Grandma's stories are still there")
	check(r.remembered.mo < 20 and ms < 150.0, "and it costs no more than a week did (%d memories, %.1f ms)" % [r.remembered.mo, ms])
	var re := RegEx.create_from_string("[0-9]")
	check(mo.mem.entries.slice(-r.remembered.mo).all(func(e): return re.search(String(e.s)) == null), "what they remember of it is in words, no numbers")


func _same_every_time() -> void:
	var a := pals()
	var b := pals()
	var wa := Life.fresh_world()
	var wb := Life.fresh_world()
	Life.catch_up(a, wa, 7.0, 100.0)
	Life.catch_up(b, wb, 7.0, 100.0)
	var same := JSON.stringify(wa) == JSON.stringify(wb)
	for i in 2:
		same = same and a[i].mem.entries.map(func(e): return e.s) == b[i].mem.entries.map(func(e): return e.s)
		same = same and JSON.stringify(a[i].heart.to_save()) == JSON.stringify(b[i].heart.to_save())
		same = same and JSON.stringify(a[i].body.to_dict()) == JSON.stringify(b[i].body.to_dict())
	check(same, "the same gap from the same start comes out exactly the same")
