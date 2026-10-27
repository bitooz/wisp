class_name Life
extends RefCounted
## Mo's and Bo's own lives: a daily round on the island (sleep, breakfast, a chore, time of their own, lunch,
## their hobby, supper, the evening by the campfire together), and what goes on while the game's closed.
##
## Mo's chore is gathering windfalls for the larder; her hobby, collecting shells for her jar. Bo's chore is
## chopping wood for the campfire; his hobby, building a model boat (one day, a real one). The woodpile, the
## boat and the jar are in the world, and change.
##
## Catching up (catch_up()): when the game opens again, the time that's passed is lived quickly, as a summary
## rather than a simulation: the last few days an hour at a time (their bodies, moods, chores, hobbies, meals,
## evenings together, what they remember), anything before that in one go (the same, added up). However long
## it's been, it costs the same, and it calls the model at most twice per pal afterwards (one reflection, one
## morning plan: minds.gd). Pure data and arithmetic: tools/life_test.gd runs it.

## Days lived an hour at a time when catching up; anything longer goes in one step
const DETAIL_DAYS := 3
## Away for longer than this many days and it's "a long time": no more is added up past it
const MOST_DAYS := 60

## Each one's day: [from hour, what], in order (the first runs on from midnight)
const ROUND := {
	mo = [[0.0, "sleep"], [7.0, "breakfast"], [7.75, "chore"], [10.0, "own"], [12.5, "lunch"], [13.25, "hobby"],
		[17.0, "free"], [18.5, "supper"], [19.25, "campfire"], [21.5, "sleep"]],
	bo = [[0.0, "sleep"], [6.5, "breakfast"], [7.25, "chore"], [10.0, "own"], [12.5, "lunch"], [13.25, "hobby"],
		[17.0, "free"], [18.5, "supper"], [19.25, "campfire"], [21.0, "sleep"]],
}
const CHORE := {mo = "gather windfalls for the larder", bo = "chop wood for the campfire"}
const HOBBY := {mo = "look for shells for my jar", bo = "work on my model boat"}
const CHORE_ING := {mo = "gathering windfalls for the larder", bo = "chopping wood for the campfire"}
const HOBBY_ING := {mo = "looking for shells for my jar", bo = "working on my model boat"}
const OTHER := {mo = "bo", bo = "mo"}
const NAME := {mo = "Mo", bo = "Bo"}
## The boat, as it comes along
const BOAT := [[0.0, "just a keel and a few ribs"], [.25, "the hull's taking shape"], [.5, "the hull's done and the mast is up"],
	[.75, "it's got a sail now"], [1.0, "it's finished: painted, sail and all"]]


## What they're usually doing at this hour (Mo, Bo, or one of the island's other people: Folk).
static func doing(who: String, hour: float) -> String:
	var now := "sleep"
	for x in (ROUND[who] if ROUND.has(who) else Folk.ROUND[who]):
		if hour >= float(x[0]):
			now = x[1]
	return now


static func chore_of(who: String) -> String:
	return CHORE[who] if CHORE.has(who) else Folk.CHORE[who]


static func hobby_of(who: String) -> String:
	return HOBBY[who] if HOBBY.has(who) else Folk.HOBBY[who]


## Their usual day, in words (for the morning's plan).
static func routine(who: String) -> Array:
	if Folk.has(who):
		return ["your work: %s, in the morning" % Folk.CHORE[who], "afternoons: %s" % Folk.HOBBY[who],
			"evenings: supper at home, then the campfire in the village, where everyone gathers"]
	return ["your chore: %s, in the morning" % CHORE[who], "your hobby: %s, in the afternoon" % HOBBY[who],
		"evenings: supper at home, then the campfire with %s" % NAME[OTHER[who]]]


static func boat_words(k: float) -> String:
	var w := ""
	for x in BOAT:
		if k >= float(x[0]):
			w = x[1]
	return w


## How long it's been, as you'd say it on coming back.
static func gap_words(hours: float, days: int, now_hour := 12.0) -> String:
	if days <= 0:
		if hours < 2.0:
			return "A little later"
		return "Later that night" if now_hour >= 21.0 or now_hour < 6.0 else "Later that day"
	if days == 1:
		return "The next day"
	if days < 7:
		return "%s days later" % ["Two", "Three", "Four", "Five", "Six"][days - 2]
	if days < 14:
		return "A week later"
	if days < MOST_DAYS:
		return "Weeks later"
	return "A long time later"


## How long someone was gone, as they'd say it.
static func gone_words(days: int) -> String:
	if days <= 0:
		return "for a bit"
	if days == 1:
		return "since yesterday"
	if days < 7:
		return "for %s days" % ["two", "three", "four", "five", "six"][days - 2]
	if days < 14:
		return "for about a week"
	if days < MOST_DAYS:
		return "for weeks"
	return "for a long, long time"


## Game hours that real time away comes to: at the usual pace for the first island day (24 real minutes), then
## one island day for each real day.
static func away_hours(real_s: float, rate: float) -> float:
	var first_s := 24.0 / rate
	if real_s <= first_s:
		return maxf(0.0, real_s * rate)
	return 24.0 + (real_s - first_s) / 3600.0


## The world's own counters, as the island keeps them.
static func fresh_world() -> Dictionary:
	return {wood = 6, boat = 0.0, jar = 0, beach_shells = 3, larder = 6, apples = 4}


# ---------- Catching up ----------

## Live `hours` from clock time `start_t` for each of them (pals: [{who, mem, body, heart, plans}]), and the
## world (counters, changed in place). Returns what happened: {hours, days, now: {who: what they're doing},
## remembered: {who: how many new memories (still there) came of it}, jar, wood, boat}.
static func catch_up(pals: Array, world: Dictionary, start_t: float, hours: float) -> Dictionary:
	var end_t := start_t + hours
	var report := {hours = hours, days = _mornings(start_t, end_t), now = {}, remembered = {}, told = []}
	var first_id := {}
	for p in pals:
		first_id[p.who] = p.mem.next_id
	# The early part, in one go: whole days before the last few
	# (from just before the first of the last few mornings, so each of those days is lived whole)
	var last_morning := floorf((end_t - 6.0) / 24.0)
	var detail_from := maxf(start_t, (last_morning - (DETAIL_DAYS - 1)) * 24.0 + 6.0 - .5)
	if detail_from > start_t:
		_quick(pals, world, start_t, detail_from)
	# The last few days, an hour at a time
	var t := maxf(start_t, detail_from)
	var was := {}
	for p in pals:
		was[p.who] = doing(p.who, fposmod(t, 24.0))
	while t < end_t - 1e-6:
		var dt := minf(1.0, end_t - t)
		var before_day := floorf((t - 6.0) / 24.0)
		t += dt
		if floorf((t - 6.0) / 24.0) > before_day:
			_new_day(world)
			for p in pals:
				p.mem.day += 1
				if floorf((t - 6.0) / 24.0) < last_morning:
					# A day's plan without the model (today's is made when the game starts: one call)
					p.plans.make(p.mem.day, Plans.fallback(p.who, p.body, p.heart, p.plans.unfinished(), 6.0, _helping(p)), "routine", p.mem.life_h)
		var hour := fposmod(t, 24.0)
		for p in pals:
			var now := doing(p.who, hour)
			if now != was[p.who]:
				_begin(p, now, world, pals)
				was[p.who] = now
			_hour(p, now, t, dt)
		_fireside(pals, hour, report)
	for p in pals:
		report.now[p.who] = doing(p.who, fposmod(end_t, 24.0))
		report.remembered[p.who] = p.mem.entries.filter(func(e): return int(e.id) >= int(first_id[p.who])).size()
		p.body.asleep = report.now[p.who] == "sleep"
		p.body.resting = false
	report.merge({wood = world.wood, boat = world.boat, jar = world.jar})
	return report


## An hour of an evening round the campfire: whoever's there (and has news) passes something on to whoever's
## sitting next to them (gossip.gd). Only those with news (a `news`) take part.
static func _fireside(pals: Array, hour: float, report: Dictionary) -> void:
	var there := pals.filter(func(p): return p.has("news") and doing(p.who, hour) == "campfire")
	for i in there.size():
		for j in range(i + 1, there.size()):
			var a: Dictionary = there[i]
			var b: Dictionary = there[j]
			var got := Gossip.chat(a, b, a.mem.life_h)
			if not got.is_empty():
				report.told.append("%s told %s: %s" % [got.from, got.to, got.story.text])


## The wants of others they've heard about and would help with (still to be done).
static func _helping(p) -> Array:
	return p.news.wants_to_help(p.heart) if p.has("news") else []


static func _mornings(a: float, b: float) -> int:
	return int(floorf((b - 6.0) / 24.0) - floorf((a - 6.0) / 24.0))


static func _new_day(world: Dictionary) -> void:
	world.larder = 6
	world.apples = 4
	world.beach_shells = 3


## An hour of it: the body and mood go on (asleep in bed, warm at home or by the fire, out and about).
static func _hour(p: Dictionary, now: String, t: float, dt: float) -> void:
	var c := Clock.new()
	c.stopped = true
	c.t = t
	var ctx := Body.Ctx.new()
	ctx.light = maxf(c.daylight(), .6 if now in ["sleep", "breakfast", "supper", "campfire"] else .03)
	ctx.chill = .7 * (1.0 - c.daylight())
	ctx.warmth = 1.0 if now in ["sleep", "breakfast", "supper", "campfire"] else 0.0
	ctx.company = now not in ["own", "chore"]
	p.body.asleep = now == "sleep"
	p.body.step(dt, dt * 60.0, ctx, false)
	p.heart.pass_time(dt, p.mem.life_h, p.body)
	p.mem.pass_time(dt)


## Starting something in their day: what it does, and what they'll remember of it.
static func _begin(p: Dictionary, now: String, world: Dictionary, pals: Array) -> void:
	var who: String = p.who
	match now:
		"breakfast", "supper":
			if world.larder > 0:
				world.larder -= 1
				p.body.eat(.55, "a meal")
		"lunch":
			if world.apples > 0:
				world.apples -= 1
				p.body.eat(.3, "an apple")
			elif world.larder > 0:
				world.larder -= 1
				p.body.eat(.55, "a meal")
		"chore", "hobby" when Folk.has(who):
			# Their work and their pastime: a good day or a poor one
			var good := Skills.roll("%s|%s|%d" % [who, now, p.mem.day]) < .75
			p.mem.add("did", Folk.DID[who][now][0 if good else 1], 2)
			p.heart.feel(.04 if good else -.03)
		"chore":
			if who == "bo":
				# With skill (if they have it): a good morning's chopping, or a poor one
				var good: bool = not p.has("skills") or p.skills.attempt("chopping", .05, p.mem.life_h)
				world.wood = mini(12, int(world.wood) + (2 if good else 1))
				p.mem.add("did", "chopped wood for the campfire and stacked it on the pile" if good else "chopped a little wood, but kept missing the logs", 2)
			else:
				var got := mini(2, int(world.apples))
				world.apples -= got
				world.larder += got
				p.mem.add("did", "gathered %s for the larder" % ("a couple of windfalls" if got == 2 else "a windfall" if got == 1 else "nothing: no windfalls today"), 2)
		"hobby":
			if who == "bo":
				var before := boat_words(world.boat)
				var fit: bool = not p.has("skills") or p.skills.attempt("building", .1, p.mem.life_h)
				if not fit:
					p.mem.add("did", "worked on my model boat, but nothing would fit today", 3)
					return
				world.boat = minf(1.0, float(world.boat) + .1)
				var after := boat_words(world.boat)
				if after != before:
					p.mem.add("did", "worked on my model boat: %s" % after, 6)
				else:
					p.mem.add("did", "worked on my model boat", 2)
			else:
				var got := mini(2, int(world.beach_shells))
				world.beach_shells -= got
				world.jar = int(world.jar) + got
				if got > 0:
					p.mem.add("did", "found %s on the beach for my jar" % ("two shells" if got == 2 else "a shell"), 3 if int(world.jar) % 10 >= got else 6)
				else:
					p.mem.add("did", "looked for shells on the beach, but didn't find any", 2)
		"campfire":
			# An evening together: a little closer to whoever's there
			var with := []
			for o in pals:
				if o.who != who and p.heart.rel.has(o.who):
					p.heart.change(o.who, .01, .02)
					with.append(o.who)
			p.heart.feel(.05)
			p.mem.add("did", "sat by the campfire with %s in the evening" % Secrets._who(with) if not with.is_empty() else "sat by the campfire in the evening", 2)
			# The fire takes a log (once an evening)
			if who == "mo" and int(world.wood) > 0:
				world.wood -= 1


## Whole days, quickly: the same round added up, memory faded in one step, moods back to themselves, and one
## memory for all of it.
static func _quick(pals: Array, world: Dictionary, a: float, b: float) -> void:
	var days := _mornings(a, b)
	var counted := mini(days, MOST_DAYS)
	for i in counted:
		_new_day(world)
		world.wood = mini(12, int(world.wood) + 2 - 1)
		world.boat = minf(1.0, float(world.boat) + .1)
		var got := mini(2, int(world.beach_shells))
		world.jar = int(world.jar) + got
		world.beach_shells -= got
	for p in pals:
		p.mem.pass_time(b - a)
		p.mem.day += days
		p.heart.pass_time(b - a, p.mem.life_h, null)
		for o in pals:
			if o.who != p.who:
				p.heart.change(o.who, .01 * minf(counted, 20), .02 * minf(counted, 20))
		var span := "the day before that"
		if days >= MOST_DAYS:
			span = "a long time before that"
		elif days >= 14:
			span = "the weeks before that"
		elif days >= 7:
			span = "the week or so before that"
		elif days > 1:
			span = "the %s days before that" % ["two", "three", "four", "five", "six"][days - 2]
		if Folk.has(p.who):
			p.mem.add("did", "%s went by much as usual: %s, %s, and evenings by the campfire with everyone" % [span, Folk.CHORE_ING[p.who], Folk.HOBBY_ING[p.who]], 5)
		else:
			p.mem.add("did", "%s went by much as usual: %s, %s, and evenings by the campfire with %s" % [span, CHORE_ING[p.who], HOBBY_ING[p.who], NAME[OTHER[p.who]]], 5)
		p.body.hunger = .2
		p.body.tired = .1
		p.body.cold = 0.0
		p.body.fear = 0.0
		p.body.bored = .2
