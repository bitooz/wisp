extends SceneTree
## The body and the clock on their own, with fixed steps (no game, no model, same result every run):
##   godot --headless --path . -s res://tools/body_test.gd
## Checks the day's light, how each need rises and falls with time and surroundings, what wakes a sleeper and
## what stops one falling asleep, and that what they feel comes as words: no numbers, nothing named but
## their own body. Ends with three days lived by a simple stand-in (eat when hungry, sleep when tired at
## night, warm up when cold) to show the needs can all be met in the world's terms. Exits non-zero on a failure.

var failed := false

## Words for things in the world: never in what a body feels
const THINGS := ["apple", "larder", "campfire", "fire", "house", "bed", "torch", "lantern", "tree", "door", "brazier", "mo", "bo", "wisp"]


func _init() -> void:
	_clock()
	_hunger_and_tiredness()
	_sleep()
	_cold()
	_fear()
	_boredom()
	_wet()
	_words()
	_three_days()
	print("FAILED" if failed else "DONE: the body and the clock")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func ctx(light := 1.0, chill := 0.0, warmth := 0.0, company := true, moving := false) -> Body.Ctx:
	var c := Body.Ctx.new()
	c.light = light
	c.chill = chill
	c.warmth = warmth
	c.company = company
	c.moving = moving
	return c


## Live `hours` of game time in one-minute steps (a minute of game time is 2.5 real seconds at 24 minutes a day).
func live(b: Body, hours: float, c: Body.Ctx, idle := false) -> void:
	var n := int(round(hours * 60))
	for i in n:
		b.step(1.0 / 60.0, 2.5, c, idle)


func _clock() -> void:
	var c := Clock.new()
	c.stopped = true
	c.set_hour(12)
	check(is_equal_approx(c.daylight(), 1.0) and c.night() == 0.0 and c.twilight() < .05, "noon: full day, no night, no twilight")
	c.set_hour(0)
	check(c.daylight() == 0.0 and is_equal_approx(c.night(), 1.0), "midnight: no daylight, full night")
	c.set_hour(18)
	check(c.twilight() > .9 and c.daylight() < .5 and c.night() < .1, "six in the evening: twilight, the light going (daylight %.2f)" % c.daylight())
	c.set_hour(21)
	check(c.night() > .99 and c.daylight() == 0.0, "nine at night: dark")
	c.set_hour(6.5)
	check(c.twilight() > .5 and c.night() < .5, "half six in the morning: dawn")
	c.stopped = false
	c.set_hour(23.5)
	var d := c.day()
	for i in 60:
		c.step(1.0)
	check(c.day() == d + 1 and c.hour() < 1.0, "a minute of real time is an hour, and midnight starts a new day")
	var seen := {}
	for h in 24:
		c.set_hour(h + .5)
		seen[c.sense()] = true
		check(not c.sense().contains(str(h)), "the time of day at %d:30 is a sense, not a number: \"%s\"" % [h, c.sense()])
	check(seen.size() >= 8, "the time of day reads differently through the day (%d ways)" % seen.size())


func _hunger_and_tiredness() -> void:
	var b := Body.new("mo")
	b.hunger = .2
	b.tired = .1
	live(b, 6.0, ctx())
	check(b.hunger > .6 and b.hunger < .7, "six hours awake: hungry (from a little peckish)")
	check(b.tired > .35 and b.tired < .45, "six hours awake: getting tired")
	var walker := Body.new("mo")
	walker.tired = .1
	live(walker, 6.0, ctx(1.0, 0.0, 0.0, true, true))
	check(walker.tired > b.tired + .1, "walking about all day tires you more than standing")
	b.eat(.3, "an apple")
	check(b.hunger < .4 and b.since_ate == 0.0, "an apple takes the edge off")
	b.eat(.55, "a meal")
	check(b.hunger == 0.0, "a meal fills you up")
	check(not b.can_eat(), "full up: no room for more")
	var r := Body.new("mo")
	r.tired = .6
	r.resting = true
	live(r, 2.0, ctx())
	check(r.tired < .55 and r.tired > .45, "two hours lying resting: a bit less tired, not slept")


func _sleep() -> void:
	var b := Body.new("bo")
	b.tired = .3
	check(b.can_sleep() == "not sleepy", "not tired enough: can't fall asleep")
	b.tired = .75
	b.hunger = .9
	check(b.can_sleep() == "too hungry", "starving: can't sleep")
	b.hunger = .3
	b.cold = .85
	check(b.can_sleep() == "too cold", "freezing: can't sleep")
	b.cold = 0
	b.fear = .8
	check(b.can_sleep() == "too scared", "terrified: can't sleep")
	b.fear = 0
	check(b.can_sleep() == "", "tired, fed, warm and calm: can sleep")
	# A night in bed from nine: warm, and it rests you; they wake in the morning
	var c := Clock.new()
	c.set_hour(21)
	b.asleep = true
	var hours := 0.0
	while b.wakes(c.daylight()) == "" and hours < 14:
		live(b, .25, ctx(.6, .7, 1.0))
		c.t += .25
		hours += .25
	check(b.wakes(c.daylight()) == "rested" and c.hour() > 6.0 and c.hour() < 8.0, "in bed at nine, up rested in the morning (%.2f o'clock)" % c.hour())
	check(b.tired < .12, "a night's sleep: not tired")
	check(b.hunger < .75 and b.hunger > .45, "asleep, you get hungry more slowly: hungry by breakfast (%.2f)" % b.hunger)
	check(b.cold < .05, "in bed indoors, warm all night")
	var nap := Body.new("bo")
	nap.tired = .5
	nap.asleep = true
	live(nap, 5.0, ctx(1.0))
	check(nap.wakes(1.0) == "rested", "a nap in the day: up once rested")
	# Asleep outdoors in the night air, away from a fire: the cold wakes you
	var o := Body.new("bo")
	o.tired = .8
	o.asleep = true
	hours = 0.0
	while o.wakes(0.0) == "" and hours < 12:
		live(o, .25, ctx(.03, .7, 0.0))
		hours += .25
	check(o.wakes(0.0) == "cold" and hours < 1.5, "asleep on the ground on a cold night: woken by the cold within the hour or so (%.1f h)" % hours)
	var f := Body.new("bo")
	f.tired = .8
	f.asleep = true
	live(f, 3.0, ctx(.8, .7, .9))
	check(f.wakes(0.0) == "" and f.cold < .1, "asleep by the fire on a cold night: warm, sleeps on")
	var h := Body.new("bo")
	h.tired = .9
	h.hunger = .85
	h.asleep = true
	live(h, 2.0, ctx(.6, 0.0, 1.0))
	check(h.wakes(0.0) == "hungry", "asleep hungry: hunger wakes you")


func _cold() -> void:
	var b := Body.new("mo")
	live(b, 2.0, ctx(.03, .7))
	check(b.cold > .55, "two hours out on a cold night: cold, shivering (%.2f)" % b.cold)
	live(b, 1.0, ctx(.8, .7, 1.0))
	check(b.cold < .1, "an hour right by the fire: warm again (%.2f)" % b.cold)
	var day := Body.new("mo")
	live(day, 4.0, ctx(1.0, 0.0))
	check(day.cold == 0.0, "a day in the sun: never cold")
	var cave := Body.new("mo")
	live(cave, 2.0, ctx(0.0, .45))
	check(cave.cold > .3 and cave.cold < .55, "under the hill: chilly, not freezing (%.2f)" % cave.cold)


func _fear() -> void:
	var b := Body.new("mo")
	for i in 20:
		b.step(0.0, 1.0, ctx(0.0, 0.0, 0.0, false), false)
	check(b.fear > .7, "twenty seconds alone in the dark: scared (%.2f)" % b.fear)
	for i in 20:
		b.step(0.0, 1.0, ctx(.8), false)
	check(b.fear < .1, "twenty seconds in the light with friends: calm again (%.2f)" % b.fear)
	var mo := Body.new("mo")
	var bo := Body.new("bo")
	for i in 30:
		mo.step(0.0, 1.0, ctx(0.0), false)
		bo.step(0.0, 1.0, ctx(0.0), false)
	check(mo.fear > bo.fear, "Mo minds the dark more than Bo does")
	var lit := Body.new("mo")
	for i in 30:
		lit.step(0.0, 1.0, ctx(.5), false)
	check(lit.fear == 0.0, "where some light reaches: not scared")
	lit.scared(.5)
	check(lit.fear == .5, "a fright scares you at once")
	var sleeper := Body.new("mo")
	sleeper.asleep = true
	for i in 30:
		sleeper.step(0.0, 1.0, ctx(0.0), false)
	check(sleeper.fear == 0.0, "asleep, the dark doesn't frighten you")
	sleeper.tired = .8
	check(not sleeper.woken_by(.8) and sleeper.woken_by(.9), "dead tired, only a loud sound wakes you")
	sleeper.tired = .1
	check(sleeper.woken_by(.55) and not sleeper.woken_by(.4), "near morning, a much quieter one does")


func _boredom() -> void:
	var b := Body.new("bo")
	for i in 90:
		b.step(0.0, 1.0, ctx(), true)
	check(b.bored > .55 and b.bored < .65, "a minute and a half standing about: bored (%.2f)" % b.bored)
	for i in 15:
		b.step(0.0, 1.0, ctx(), false)
	check(b.bored < .35, "doing something: the boredom goes (%.2f)" % b.bored)
	b.perked(1.0)
	check(b.bored == 0.0, "something new happening: not bored")


func _wet() -> void:
	var b := Body.new("mo")
	var water := ctx(1.0, 0.0)
	water.in_water = true
	live(b, .1, water)
	check(b.wet_feet == 1.0 and b.feel().has("standing in water: it's cold round your ankles"), "standing in the water: wet feet, and she feels it")
	live(b, .25, ctx(1.0, 0.0))
	check(b.wet_feet > .5 and b.feel().has("your feet are wet"), "just out of the water, her feet are still wet")
	live(b, 1.5, ctx(1.0, 0.0))
	check(b.wet_feet == 0.0 and not b.feel().has("your feet are wet"), "in an hour or so on a warm day they dry")
	var fire := Body.new("mo")
	fire.wet_feet = 1.0
	var plain := Body.new("mo")
	plain.wet_feet = 1.0
	live(fire, .3, ctx(.8, .7, .9))
	live(plain, .3, ctx(.03, .7))
	check(fire.wet_feet < plain.wet_feet - .3, "by a fire you dry much faster (%.2f against %.2f)" % [fire.wet_feet, plain.wet_feet])
	var wet := Body.new("bo")
	var dry := Body.new("bo")
	var night_water := ctx(.03, .6)
	night_water.in_water = true
	live(wet, 1.0, night_water)
	live(dry, 1.0, ctx(.03, .6))
	check(wet.cold > dry.cold + .2, "wet on a cold night, you get colder (%.2f against %.2f)" % [wet.cold, dry.cold])
	var hands := Body.new("bo")
	hands.wet_hands = 1.0
	check(hands.feel().has("your hands are wet"), "wet hands are felt")
	live(hands, 1.0, ctx())
	check(hands.wet_hands == 0.0, "and dry within the hour")


func _words() -> void:
	# Every mix of needs, in steps: what they feel is words, never numbers or things
	var lines := {}
	var steps := [0.0, .32, .58, .82, .95]
	for h in steps:
		for t in steps:
			for c in steps:
				for f in steps:
					for bd in [0.0, .55, .85]:
						var b := Body.new("mo")
						b.hunger = h
						b.tired = t
						b.cold = c
						b.fear = f
						b.bored = bd
						b.wet_feet = h
						b.wet_hands = t
						b.in_water = c > .9
						for line in b.feel():
							lines[line] = true
	var bad := []
	var re := RegEx.create_from_string("[0-9]")
	for line in lines:
		if re.search(line) != null:
			bad.append(line)
		for w in THINGS:
			if RegEx.create_from_string("(?i)\\b" + w + "\\b").search(line) != null:
				bad.append(line)
	check(bad.is_empty(), "%d different feelings, none with a number or a thing's name in it %s" % [lines.size(), bad])
	var fresh := Body.new("mo")
	fresh.hunger = .1
	fresh.tired = .1
	check(fresh.feel().is_empty(), "nothing wrong: nothing to feel")
	var all := Body.new("mo")
	all.hunger = .9
	all.tired = .9
	all.cold = .9
	all.fear = .9
	all.bored = .9
	check(all.feel().size() == 5, "everything at once: five feelings, %s" % [all.feel()])
	var asleep := Body.new("mo")
	asleep.hunger = .9
	asleep.asleep = true
	check(asleep.feel().is_empty(), "asleep: they feel nothing (they're not thinking)")


## Three days, lived by a stand-in that looks after itself (eat when hungry, warm up by a fire when cold, sleep
## indoors when tired at night): nothing ever gets to its worst for long.
func _three_days() -> void:
	var c := Clock.new()
	c.set_hour(8)
	var b := Body.new("mo")
	var worst := {hunger = 0.0, tired = 0.0, cold = 0.0}
	var meals := 0
	var nights := 0
	var cold_spells := 0
	var by_fire := false
	var minutes := 0
	while minutes < 3 * 24 * 60:
		minutes += 1
		c.t += 1.0 / 60.0
		var night := c.night()
		var outdoors := ctx(maxf(c.daylight(), .03), .7 * (1.0 - c.daylight()), .9 if by_fire else 0.0)
		if b.asleep:
			outdoors = ctx(.6, .7 * (1.0 - c.daylight()), 1.0)
		b.step(1.0 / 60.0, 2.5, outdoors, false)
		if b.wakes(c.daylight()) != "":
			b.asleep = false
			b.since_woke = 0
		if b.asleep:
			continue
		if b.hunger > .6:
			b.eat(.55, "a meal")
			meals += 1
		if b.cold > .5 and not by_fire:
			by_fire = true
			cold_spells += 1
		elif b.cold < .1:
			by_fire = false
		if night > .5 and b.can_sleep() == "":
			b.asleep = true
			by_fire = false
			nights += 1
		for k in worst:
			worst[k] = maxf(worst[k], b.get(k))
	check(meals >= 3 and meals <= 9, "three days: ate %d times" % meals)
	check(nights == 3, "three days: slept %d nights" % nights)
	check(worst.hunger < .7 and worst.tired < .85 and worst.cold < .7, "looked after, nothing got to its worst %s" % [worst])
