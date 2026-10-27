class_name Minds
extends Node
## Mo and Bo thinking for themselves, through the Worker (brain.gd). Each thought carries their senses: sight,
## a picture from their own eyes rendered just then (eyes.gd), what they hear (you, each other, sounds), and
## how their body feels; nothing else about the world. The mic is always open (ears.gd): each
## thing you say is written down by the model (/hear), and whoever you named, or the one you chose, hears it
## and answers that. They also think when the other one talks to them, when something happens to them, when
## they've finished what they were doing, and every few seconds when they're not doing anything. Each thought
## gets what that one perceives, remembers and plans (mind.gd), and comes back as words in their own voice and
## one action, which the game checks against what's possible now before doing it. Asleep, they don't think
## until something wakes them (their body, someone talking to them, a boop).
##
## The island's other people (folk.gd) have minds of their own too: they think for themselves only when you're
## near (and seldom), otherwise they live their day. When two people are together with time to talk, news
## passes between them (gossip.gd); someone's want, done, is news for everyone who sees it (gave()).
##
## Every thought is logged as a WISP_TALK line of JSON (time to their first word, cost); every thing heard as
## WISP_HEAR; every story passed on as WISP_GOSSIP, and every want done as WISP_QUEST.

const EARSHOT := {isle = 15.0, cave = 30.0}
## At most this many thoughts a minute of their own (idle, events, chat); what you say always goes
const OWN_PER_MIN := 24
## Quiet (seconds) before they say anything of their own: room for you to talk
const QUIET_GAP := 4.0
## How often they think when not doing anything (the island's other people: only when you're near, and seldom)
const IDLE := {mo = [6.0, 10.0], bo = [8.0, 13.0], folk = [25.0, 40.0]}
## The island's other people think for themselves only within this far of you (otherwise they live their day)
const FOLK_NEAR := 12.0
## Two people this close, with time to talk, pass on what they know now and then (seconds between)
const CHAT_NEAR := 3.5
const CHAT_EVERY := 8.0

var game: Game
var brain: Brain
var ears: Ears
var mo: Mind
var bo: Mind
## The island's other people's minds (Folk), and everyone's by their body
var folk: Array = []
var by_pal := {}
var on := false
## While true, they don't think on their own (tests)
var quiet := false
var own_times: Array = []
var stats: Array = []
var hears: Array = []
var pending_first: Array = []
## When you last said something they heard (seconds)
var last_heard_t := -1e9
## --dump-minds prints every thought's request (WISP_THINK); dump_frames (a folder) keeps what they saw
var dump := OS.get_cmdline_user_args().has("--dump-minds")
var dump_frames := ""
## Each night's reflection (reflect()); tests put a stand-in for the model here: (mind, memories) -> {beliefs}
var reflector: Callable
var reflections: Array = []


func setup(g: Game) -> void:
	game = g
	brain = Brain.new()
	add_child(brain)
	ears = Ears.new()
	ears.deaf = _voices_playing
	add_child(ears)
	ears.heard.connect(_on_heard)
	ears.speaking.connect(func(v): game.hud.listening = v)
	mo = Mind.new(g.mo, g)
	bo = Mind.new(g.bo, g)
	for p in g.folk:
		folk.append(Mind.new(p, g))
	for m in all():
		by_pal[m.pal] = m
	# --offline: no Worker at all (tests that mustn't call the model)
	on = brain.on and g.quality.get("minds", true) and not OS.get_cmdline_user_args().has("--offline")
	print("WISP_MINDS on=%s host=%s:%d minds=%s" % [on, brain.host, brain.port, JSON.stringify(brain.minds)])



## Today's plan for each, if there isn't one yet (on starting, after catching up: game.gd).
func _first_plans() -> void:
	# The island's very first morning (nothing saved yet): Mo and Bo have had their breakfast already, as they
	# would have before you turned up
	if on and not FileAccess.file_exists(game.world_file()) and game.clock.hour() > 7.5 and game.clock.hour() < 11.0:
		for m in [mo, bo]:
			if not m.memory.any(func(e): return String(e.s).contains("breakfast")):
				m.remember("did", "had breakfast at home this morning", 3)
				m.body.since_ate = game.clock.hour() - 7.0
	for m in all():
		if m.plans.day != m.mem.day and not m.body.asleep:
			plan_day(m)


func of(p: Pal) -> Mind:
	return by_pal.get(p, mo if p == game.mo else bo)


## Everyone's minds: Mo, Bo and the island's other people.
func all() -> Array:
	return [mo, bo] + folk


## Someone's mind by who they are ("mo", "nell"...), or null.
func by_id(who: String) -> Mind:
	for m in all():
		if m.pal.id == who:
			return m
	return null


## Mo's other half (Bo's, Mo); for anyone else, Mo.
func other(m: Mind) -> Mind:
	return bo if m == mo else mo


func save() -> void:
	for m in all():
		m.save()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE]:
		if mo:
			save()


## Near enough to hear (and in the same place: someone through a door hears nothing of here).
func earshot(m: Mind, from: Vector3) -> bool:
	return m.pal.place_id == game.level.id and m.pal.position.distance_to(from) < EARSHOT.get(game.level.id, 15.0)


func here(m: Mind) -> bool:
	return m.pal.place_id == game.level.id


## Seconds since anyone last stopped talking.
func _since_line() -> float:
	if game.talking_now():
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - game.line_ended_at


## Their voices are playing, or one of the game's own sounds (so whatever the mic hears now isn't you).
func _voices_playing() -> bool:
	if game.sfx and Time.get_ticks_msec() / 1000.0 < game.sfx.loud_until:
		return true
	for p in game.people():
		if p.voice.sounding() and not p.voice.done():
			return true
	return game.talking_now()


func _process(dt: float) -> void:
	if not mo or not game.level:
		return
	for m in all():
		# Bodies go on wherever they are
		m.live(dt)
		if here(m):
			m.update(dt)
	_first_words()
	_apart()
	_just_us()
	_gossip(dt)
	# A rethink due: they think again soon (once for each reason)
	for m in all():
		if m.plans.replan != "" and m.replan_told != m.plans.replan:
			m.replan_told = m.plans.replan
			after(m, "time to rethink your plan for today: " + m.plans.replan)
	if not on or quiet or not game.controls:
		return
	for m in all():
		if not here(m) or (m.thought and not m.thought.over) or m.body.asleep or m.pal.inside != "":
			continue
		# The island's other people think for themselves only when you're about (otherwise their day goes on)
		if m.pal.folk and not near_you(m):
			continue
		# Busy doing something, they think when it's done (or something happens); lying resting, they think on
		if not m.task.is_empty() and m.next_event == "" and m.task.get("phase", "") != "rest":
			continue
		m.next_think -= dt
		if m.next_think > 0 or game.talking_now() or ears.listening():
			continue
		var ev: String = m.next_event
		m.next_event = ""
		var span: Array = IDLE["folk" if m.pal.folk else m.pal.id]
		m.next_think = randf_range(span[0], span[1]) * (2.0 if m.pal.plate or m.body.resting else 1.0)
		if not _own_ok():
			continue
		if ev != "":
			think(m, "event", {event = ev})
		else:
			think(m, "idle")


## Asleep for the night: the day is turned over in their mind and a few lasting beliefs come of it. One call
## per pal per night (text only: what they remember of the day, and what they already believe), whatever comes
## back. If it fails, tomorrow night's takes in both days. Logged as WISP_REFLECT.
func reflect(m: Mind) -> void:
	if m.mem.reflected_day >= m.mem.day or not (reflector.is_valid() or on):
		return
	var day: Array = m.mem.for_reflection()
	m.mem.reflected_day = m.mem.day
	m.dirty = true
	if day.is_empty():
		return
	var upto: float = m.mem.life_h
	var rec := {who = m.pal.id, day = m.mem.day, memories = day.size(), t0 = Time.get_ticks_msec()}
	var r: Dictionary
	if reflector.is_valid():
		r = await reflector.call(m, day)
	else:
		r = await brain.reflect(reflect_body(m, day))
	rec.ms = Time.get_ticks_msec() - rec.t0
	rec.erase("t0")
	if r.get("beliefs") is Array:
		# "from" comes back as positions in the list sent (1 = first): back to which memories they were
		var list: Array = []
		for b in r.beliefs:
			if b is Dictionary:
				var from := []
				for n in b.get("from", []):
					var i := int(n) - 1
					if i >= 0 and i < day.size():
						from.append(day[i].id)
				list.append({text = b.get("text", ""), importance = b.get("importance", 8), from = from})
		var added: Array = m.mem.add_beliefs(list)
		m.mem.reflected_h = upto
		m.dirty = true
		rec.people = _settle_feelings(m, r)
		rec.beliefs = added.map(func(e): return e.s)
		rec.cost = r.get("cost", 0.0)
	else:
		rec.error = r.get("error", "no beliefs")
	reflections.append(rec)
	print("WISP_REFLECT ", JSON.stringify(rec))


## Wisp nowhere about, and the two of them together with nothing much going on: a moment of their own (they
## might talk about Wisp). Not more than once every few hours lived.
const ALONE_EVERY_H := 3.0
## How long (real seconds) they've been on their own together before it counts as a moment of their own
var alone_after := 20.0
var alone_for := 0.0
## How many such moments there have been (for tests and the log)
var alone_moments := 0


func _just_us() -> void:
	if not mo.alone_together() or mo.body.asleep or bo.body.asleep:
		alone_for = 0.0
		return
	alone_for += get_process_delta_time()
	if alone_for < alone_after:
		return
	var m := mo if mo.task.is_empty() else bo
	if not m.task.is_empty() or m.mem.life_h - m.heart.alone_h < ALONE_EVERY_H:
		return
	for x in [mo, bo]:
		x.heart.alone_h = x.mem.life_h
		x.dirty = true
	alone_for = 0.0
	alone_moments += 1
	print("WISP_ALONE %s and %s, Wisp away" % [m.pal.pal_name, other(m).pal.pal_name])
	after(m, "Wisp isn't around: it's just you and %s for a bit" % other(m).pal.pal_name)


## Someone through a door on their own: waiting on the other side, they can't see what you see. If you're
## leaving it to them and nobody's left here, you go after them; if nobody comes for a minute, they come back.
func _apart() -> void:
	if not game.controls:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var away := [mo, bo].filter(func(m): return not here(m))
	if away.is_empty():
		return
	if away.size() == 2 and game.idle_t > Game.IDLE_AFTER and away[0].pal.place_id == away[1].pal.place_id:
		game.follow_to(away[0].pal.place_id, game.level.way_opts_to(away[0].pal.place_id))
		return
	for m in away:
		var p: Pal = m.pal
		if now - p.away_since > 45.0 and p.came_from == game.level.id:
			# Nobody followed: back the way they went
			var spot: Vector3 = game.level.arrival_from(p.place_id)
			p.place_id = game.level.id
			p.arriving = false
			p.place(spot.x, spot.z)
			p.position.y = game.level.ground(p.position.x, p.position.z)
			p.set_here(true)
			m.entered()
			m.remember("event", "went through and waited on the other side, but nobody came, so I came back")
			if earshot(other(m), p.position):
				saw(other(m).pal, "%s came back through there" % p.pal_name, p.position + Vector3(0, .7, 0))
				game.hearing.make(p.position, p.place_id, game.level.way_sound(""), 15.0, p)
			m.next_think = .5


## Something one of them sees happen (if they're near enough).
func _own_ok() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	own_times = own_times.filter(func(t): return now - t < 60.0)
	if own_times.size() >= OWN_PER_MIN:
		return false
	own_times.append(now)
	return true


# ---------- What they perceive and what happens to them ----------

## What the night's reflection made of how they feel about the others: a little warmer or cooler, more or less
## trust (a small step each, whatever the model says), a grudge if they're hurt, and promises it judged kept
## or broken (by position in the list it was given).
func _settle_feelings(m: Mind, r: Dictionary) -> Array:
	var done := []
	for x in r.get("people", []):
		if not (x is Dictionary):
			continue
		var o := String(x.get("who", "")).to_lower()
		if not m.heart.rel.has(o):
			continue
		var t := clampi(int(x.get("trust", 0)), -1, 1)
		var f := clampi(int(x.get("fond", 0)), -1, 1)
		m.heart.change(o, .06 * t, .06 * f)
		var why := String(x.get("why", "")).strip_edges().left(120)
		if f < 0 and why != "":
			m.heart.grudge(o, why, .3, m.mem.life_h)
		done.append("%s trust %+d fond %+d" % [o, t, f])
	var open := m.heart.promises.filter(func(p): return p.status == "open" and p.kind == "other")
	for x in r.get("promises", []):
		if x is Dictionary:
			var i := int(x.get("n", 0)) - 1
			if i >= 0 and i < open.size():
				m.heart.resolve(open[i], bool(x.get("kept", false)), m.mem.life_h)
				done.append("promise %d %s" % [i + 1, "kept" if x.get("kept", false) else "broken"])
	return done


## What goes to the night's reflection: the day's memories, what they believe, how their plan for the day went,
## their mood and feelings, and promises only it can judge.
func reflect_body(m: Mind, day: Array) -> Dictionary:
	return {who = m.pal.id, memories = day.map(func(x): return x.line), beliefs = m.mem.beliefs(),
		plan = m.plans.summary() if m.plans.summary() != "" else m.plan,
		mood = m.heart.mood_words(), bonds = m.heart.bonds(),
		promises = m.heart.promises.filter(func(p): return p.status == "open" and p.kind == "other").map(func(p): return "%s promised you: \"%s\"" % [Heart.NAMES[p.from], p.text])}


# ---------- Plans for the day ----------

## Tests put a stand-in for the morning's plan here: (mind, body) -> {day: [{text, why}], step}
var planner: Callable
var plans_made: Array = []


## Each morning (and on first start): today's plan, from what they want, how they are, what they believe and
## feel, and how yesterday went. One small text-only call per pal per morning; with no model (or if it
## fails), the game's own plan for them (Plans.fallback). Logged as WISP_PLAN.
func plan_day(m: Mind) -> void:
	if m.planning or m.plans.day == m.mem.day:
		return
	m.planning = true
	var body := plan_body(m)
	var r: Dictionary = {}
	var by := "fallback"
	if planner.is_valid():
		r = await planner.call(m, body)
		by = "standin"
	elif on:
		r = await brain.plan(body)
		by = "model"
	var list: Array = r.get("day", []) if r.get("day") is Array else []
	if list.is_empty():
		list = Plans.fallback(m.pal.id, m.body, m.heart, m.plans.unfinished(), game.clock.hour(), m.news.wants_to_help(m.heart))
		by = "fallback" if not r.has("error") else "fallback (%s)" % String(r.error).left(60)
	m.plans.make(m.mem.day, list, by.get_slice(" ", 0), m.mem.life_h)
	if String(r.get("step", "")).strip_edges() != "":
		m.plans.step = String(r.step).strip_edges().left(160)
	# Remembered, but not as something that happened (the night gets the plan and how it went on its own)
	m.remember("note", "my plan for today: " + "; ".join(m.plans.items.map(func(i): return i.text)), 3)
	m.replan_told = ""
	m.planning = false
	m.dirty = true
	var rec := {who = m.pal.id, day = m.mem.day, by = by, plan = m.plans.items.map(func(i): return i.text), cost = r.get("cost", 0.0)}
	plans_made.append(rec)
	print("WISP_PLAN ", JSON.stringify(rec))


## What goes into the morning's plan: who they are is the Worker's; this is how they are today.
func plan_body(m: Mind) -> Dictionary:
	return {who = m.pal.id, time = game.clock.sense(),
		goals = Mind.seeds_of(m.pal.id).filter(func(s): return s[0] == "note").map(func(s): return s[1]),
		helping = m.news.wants_to_help(m.heart),
		beliefs = m.mem.beliefs(), feel = [m.heart.mood_words()] + m.body.feel(), bonds = m.heart.bonds(), routine = Life.routine(m.pal.id),
		yesterday = m.plans.summary(), leftover = m.plans.unfinished(), today = _done_today(m)}


## What they've done already today, as they remember it (their meals and work since they got up).
func _done_today(m: Mind) -> Array:
	var since: float = m.mem.life_h - game.clock.hour()
	var out := []
	for e in m.mem.entries:
		if e.k == "did" and float(e.get("h", 0.0)) >= since and out.size() < 4:
			out.append(String(e.s))
	return out


## What the model said about the plan, in a thought: the next step; the activity done or given up; and, when a
## rethink was due, the rest of the day. A rethink left alone twice: what they were on is given up.
func _plan_reply(m: Mind, r: Dictionary) -> void:
	var p: Plans = m.plans
	var now: float = m.mem.life_h
	match String(r.get("activity", "")).strip_edges().to_lower():
		"done":
			p.finish(now, "done")
		"drop", "dropped", "give up":
			p.finish(now, "dropped")
	var step := String(r.get("next", r.get("plan", ""))).strip_edges()
	if step != "":
		p.step = step.left(160)
	if p.replan != "":
		if r.get("day") is Array and not r.day.is_empty():
			p.rethink(r.day, now)
			m.replan_ignored = 0
		else:
			m.replan_ignored += 1
			if m.replan_ignored >= 2:
				p.finish(now, "dropped")
				p.replan = ""
				m.replan_ignored = 0
	m.dirty = true


## The private part of a thought: what they really think (their own memory only), a secret they mean to keep,
## and whether what they said was so. A line that wasn't (a lie, or a bluff) is kept with who heard it and what's
## really so, for their own later thoughts. Nobody else ever gets any of it: listeners only had the words.
func _private(m: Mind, r: Dictionary, rec: Dictionary) -> void:
	var now: float = m.mem.life_h
	var think := String(r.get("think", "")).strip_edges().left(160)
	if think != "":
		m.remember("thought", think)
	var keep := String(r.get("keep", "")).strip_edges().left(140)
	if keep != "":
		m.secrets.keep(keep, now)
		m.remember("secret", keep)
	# "false", "bluff" or "true" (as text from the Worker; a plain true/false is fine too)
	var truth := str(r.get("true", "true")).strip_edges().to_lower()
	var said := String(r.get("say", rec.get("say", ""))).strip_edges()
	if said == "" or truth not in ["false", "bluff"]:
		return
	# The line may still be waiting its turn to be said
	var waited := 0.0
	while m.last_line.get("text", "") != said and not rec.has("dropped") and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if rec.has("dropped") or m.last_line.get("text", "") != said or m.last_line.to.is_empty():
		return
	var s := m.secrets.lied(said, think, m.last_line.to, now, "bluff" if truth == "bluff" else "lie")
	# It shows a little: the eyes slide off whoever heard it
	m.pal.shifty()
	m.remember("lied", "told %s \"%s\", and it %s%s" % [Secrets._who(s.to), said,
		"was putting on a front" if s.kind == "bluff" else "wasn't true", (": " + think) if think != "" else ""])
	m.dirty = true


## Passing something on in a thought ("tell": which of their news, by number): once the line's said, whoever heard
## it has it now (as gossip.gd keeps it: from whom, and where it came from); their own words were the telling.
func _passed_on(m: Mind, r: Dictionary, rec: Dictionary) -> void:
	var n := int(r.get("tell", 0))
	var said := String(r.get("say", rec.get("say", ""))).strip_edges()
	var x: Dictionary = m.news.nth(n, m.mem.life_h)
	if n <= 0 or said == "" or x.is_empty():
		return
	# Only if the words carry it: a line about something else passes nothing on
	if not Gossip.carried(said, x):
		rec.tell_dropped = n
		return
	var waited := 0.0
	while m.last_line.get("text", "") != said and not rec.has("dropped") and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if rec.has("dropped") or m.last_line.get("text", "") != said:
		return
	for id in m.last_line.to:
		var o := by_id(id)
		if o != null:
			_pass(m, o, x)


## One story from one to another (live): gossip.gd does the rest. Logged as WISP_GOSSIP.
func _pass(teller: Mind, listener: Mind, x: Dictionary) -> Dictionary:
	var now: float = listener.mem.life_h
	var copy := Gossip.tell(x, teller.pal.id, listener.news, now)
	if copy.is_empty():
		return {}
	Gossip.take_in(listener, copy, now)
	teller.mem.add("did", "told %s: %s" % [listener.pal.pal_name, x.text], 3)
	teller.dirty = true
	listener.dirty = true
	var rec := {from = teller.pal.id, to = listener.pal.id, about = copy.about, kind = copy.kind, text = copy.text, chain = copy.chain}
	passed.append(rec)
	print("WISP_GOSSIP ", JSON.stringify(rec))
	return rec


# ---------- Gossip, and the island's other people ----------

## Everything passed on (for tests and the log)
var passed: Array = []
var chats := {}
var chat_in := 0.0


## Near enough to you to think for themselves (the island's other people), and awake and about.
func near_you(m: Mind) -> bool:
	return here(m) and m.pal.inside == "" and m.pal.position.distance_to(game.wisp_g) < FOLK_NEAR


## Two people standing together with time to talk pass on what they know, now and then. Where you can hear
## them and they think for themselves, they do it in their own words (a thought's "tell"); otherwise (out of
## your hearing, or no model) it happens quietly: they turn to each other and talk, and you don't hear what.
func _gossip(dt: float) -> void:
	chat_in -= dt
	if chat_in > 0:
		return
	chat_in = .5
	var now_s := Time.get_ticks_msec() / 1000.0
	var ms := all().filter(func(m): return here(m) and not m.body.asleep and m.pal.inside == "" and not m.pal.talk and m.pal.lying < .5)
	for i in ms.size():
		for j in range(i + 1, ms.size()):
			var a: Mind = ms[i]
			var b: Mind = ms[j]
			var key := a.pal.id + "|" + b.pal.id
			if a.pal.position.distance_to(b.pal.position) > CHAT_NEAR:
				chats.erase(key)
				continue
			if not chats.has(key):
				# A moment's hello first
				chats[key] = now_s + 4.0
				continue
			if now_s < float(chats[key]):
				continue
			chats[key] = now_s + CHAT_EVERY
			if on and not quiet and earshot(a, game.wisp_g) and earshot(b, game.wisp_g):
				continue
			var first := a if Skills.roll("%s|%d" % [key, passed.size()]) < .5 else b
			var second := b if first == a else a
			var x: Dictionary = first.news.pick(second.pal.id, first.mem.life_h)
			if x.is_empty():
				x = second.news.pick(first.pal.id, second.mem.life_h)
				var t := first
				first = second
				second = t
			if x.is_empty():
				continue
			if _pass(first, second, x).is_empty():
				continue
			# They turn to each other and talk quietly
			first.pal.face(second.pal.position)
			second.pal.face(first.pal.position)
			first.pal.mutter = 2.5


## Something happened that everyone who sees it (and these: `also`) will know about and talk about: a story for
## each of them (gossip.gd). at: where it happened.
func news_seen(at: Vector3, about: String, text: String, s: float, kind := "news", quest := "", also: Array = []) -> void:
	for m in all():
		if also.has(m) or (here(m) and not m.body.asleep and m.pal.inside == "" and game.eyes.sees(m.pal, at)):
			m.news.witness(about, text, s, m.mem.life_h, kind, quest)
			m.dirty = true


## Quests done (for tests and the log)
var quests: Array = []


## Something put in someone's hands (Mind give): if it's what they wanted (Folk.WANTS), that's their want done.
func gave(giver: Mind, to: Pal, T: Dictionary) -> void:
	var w := Folk.wanted_by(String(T.t))
	if w == "" or w != to.id:
		return
	var om := of(to)
	var did_id := Gossip.id_of("done", "", w)
	if om.news.knows(did_id):
		om.remember("event", "%s brought me %s, kind of them" % [giver.pal.pal_name, T.get("what", "something")])
		om.heart.helped(giver.pal.id)
		return
	var W: Dictionary = Folk.WANTS[w]
	var now: float = om.mem.life_h
	# Over the moon, and grateful
	om.heart.feel(.35, .2)
	om.heart.helped(giver.pal.id)
	om.heart.change(giver.pal.id, .12, .18)
	om.remember("event", "%s %s" % [giver.pal.pal_name, W.thanks], 9)
	om.plans.did(W.goal, now)
	giver.plans.did(W.todo, giver.mem.life_h)
	giver.heart.feel(.15)
	giver.remember("did", "%s; %s was so pleased" % [W.done, Folk.NAMES[w]], 7)
	# Everyone who sees it (and the two of them) has something to tell
	var text := "%s %s" % [giver.pal.pal_name, W.done]
	news_seen(to.global_position + Vector3(0, .8, 0), giver.pal.id, text, .7, "done", w, [giver, om])
	# Kept safe at home (what's lost stays found)
	var isle = game.levels.get("isle")
	if isle != null and isle.lost.has(String(T.t)):
		isle.found.append(String(T.t))
	game.get_tree().create_timer(3.0).timeout.connect(func():
		if to.held == T:
			to.let_go()
			T.node.queue_free())
	var rec := {who = w, by = giver.pal.id, what = String(T.t), h = now}
	quests.append(rec)
	print("WISP_QUEST ", JSON.stringify(rec))


## Something said to (or near) them, by `from`: a promise to them, teasing aimed at them, and what's said about
## someone else (talk about Wisp rubs off a little, by how much they trust who said it).
func _heard_from(x: Mind, from: String, text: String, at: Vector3, to_them: bool) -> void:
	var now: float = x.mem.life_h
	# Something they could see for themselves isn't so
	x.heard_claim(from, text)
	if to_them and Heart.promise_kind(text) != "":
		x.heart.promised(from, text, now, at)
	if to_them and Heart.is_tease(text):
		x.heart.teased(from, now)
	if to_them and Heart.is_tease(text):
		x.news.witness(x.pal.id, "%s teased %s" % [Heart.NAMES[from], x.pal.pal_name], -.25, now)
	for o in Heart.NAMES:
		if o != from and o != x.pal.id and _names(text, Heart.NAMES[o]):
			var s := Heart.sentiment(text)
			if s != 0.0:
				x.heart.heard_about(o, from, s)
				# Something worth passing on: what someone said about someone
				if absf(s) >= .5:
					x.news.witness(o, "%s said \"%s\"" % [Heart.NAMES[from], text.left(90)], s * .6, now)
	x.dirty = true


## Something they'd only see happen (someone going off, coming back), at `at`: only if it's in front of them
## and they can see it (eyes.gd); asleep or looking the other way, they miss it (what it sounded like is
## hearing's).
func saw(p: Pal, text: String, at: Vector3) -> void:
	if not of(p).body.asleep and game.eyes.sees(p, at):
		happened(p, text)


## Something happened to them (a boop, the shadow lunging): they react; it wakes them if they're asleep.
func happened(p: Pal, text: String) -> void:
	var m := of(p)
	if m.body.asleep:
		m.wake("")
	m.remember("event", text)
	if on and not quiet:
		_soon(m, text)


## They finished something: what next?
func after(m: Mind, text: String) -> void:
	if on and not quiet:
		_soon(m, text)


func _soon(m: Mind, text: String) -> void:
	m.next_event = text if m.next_event == "" else m.next_event + "; and " + text
	m.next_think = minf(m.next_think, .8)


## Something happened that whoever's there sees: it goes into their memory (and what didn't work before
## might now).
## Something changed in the world (what they heard or saw tells them how): what didn't work before might now.
func changed() -> void:
	for m in all():
		m.failed.clear()


## Where your voice (or a friend's) comes from, for whoever hears it: "behind you, close by"; "" if they can't.
func voice_from(m: Mind, at: Vector3, place: String) -> String:
	var h: Dictionary = game.hearing.heard(m.pal, at, place, EARSHOT.get(place, 15.0) * 1.5)
	return h.get("words", "")


## A line said out loud: whoever it carries to hears it, from where it was said; muffled and far, only the voice,
## not the words. Asleep, only a voice close by gets through (and wakes them).
func line_said(p: Pal, text: String) -> void:
	var m := of(p)
	m.remember("said", "I said: \"%s\"" % text)
	m.hear_line(p.pal_name, text)
	# Who heard the words: anyone awake (or woken) near enough to make them out, and you, if you're near
	var to := []
	var heard := []
	for o in all():
		if o == m:
			continue
		var h: Dictionary = game.hearing.heard(o.pal, p.head(), p.place_id, EARSHOT.get(p.place_id, 15.0) * 1.5, p)
		if h.is_empty():
			continue
		heard.append([o, h])
		if not (h.muffled and h.level < .35) and (not o.body.asleep or o.body.woken_by(h.level)):
			to.append(o.pal.id)
	if game.level.id == p.place_id and game.kid.global_position.distance_to(p.position) < EARSHOT.get(p.place_id, 15.0):
		to.append("wisp")
	m.last_line = {text = text, to = to, h = m.mem.life_h}
	# A secret given away
	for s in m.secrets.spoke(text, to):
		m.remember("did", "told %s my secret: %s" % [Secrets._who(to), s.text], 6)
	for x in heard:
		var o: Mind = x[0]
		var h: Dictionary = x[1]
		if o.body.asleep:
			if not o.body.woken_by(h.level):
				continue
			o.wake("", "to %s's voice" % p.pal_name)
		if h.muffled and h.level < .35:
			o.remember("heard", "%s's voice, %s, but not the words" % [p.pal_name, h.words])
			continue
		o.remember("told", "%s said (%s): \"%s\"" % [p.pal_name, h.words, text])
		o.hear_line(p.pal_name, text, h.words)
		_heard_from(o, p.id, text, p.position, _names(text, o.pal.pal_name) or (not _names(text, "Wisp") and o.pal.position.distance_to(p.position) < 6.0))


# ---------- You talking ----------

## The mic caught something: it goes, as audio, to whoever you're talking to (the one you chose, if they're
## near enough to hear). The Worker writes your words down alongside: noise and fillers get no answer, and
## something said to the other one by name goes to them instead.
func _on_heard(wav: PackedByteArray, t_end: int) -> void:
	if not on:
		return
	var a := of(game.active)
	var m := a if earshot(a, game.wisp_g) or not earshot(other(a), game.wisp_g) else other(a)
	_cancel_thoughts()
	var rec := {t_end = t_end, bytes = wav.size(), seconds = snappedf((wav.size() - 44) / 32000.0, .01), to = m.pal.id}
	var kid_at := game.kid.global_position + Vector3(0, 1.2, 0)
	var th := think(m, "heard", {audio = Marshalls.raw_to_base64(wav), from = "wisp", where = voice_from(m, kid_at, game.level.id)}, {t_end = t_end})
	th.heard.connect(func(text: String):
		rec.heard = text
		rec.ms_hear = Time.get_ticks_msec() - t_end
		if text.strip_edges() != "":
			_got_words(text)
			# Someone else here you named (one of the island's people, near enough): they answer too
			for x in folk:
				if x != m and _names(text, x.pal.pal_name) and earshot(x, game.wisp_g) and not (x.thought and not x.thought.over) and not x.body.asleep:
					think(x, "heard", {text = text, from = "wisp", where = voice_from(x, kid_at, game.level.id)}, {t_end = t_end}))
	th.stopped.connect(func(kind: String, text: String):
		rec.stopped = kind
		if kind == "redirect":
			think(other(m), "heard", {text = text, from = "wisp", where = voice_from(other(m), kid_at, game.level.id)}, {t_end = t_end}))
	th.finished.connect(func(_r):
		rec.junk = rec.get("stopped", "") == "ignored"
		hears.append(rec)
		print("WISP_HEAR ", JSON.stringify(rec)))


func _cancel_thoughts() -> void:
	game.hush()
	for x in all():
		if x.thought and not x.thought.over:
			x.thought.cancelled = true


## Your words, once written down: shown, and remembered by whoever was in earshot.
func _got_words(text: String) -> void:
	last_heard_t = Time.get_ticks_msec() / 1000.0
	game.show_you(text)
	for x in all():
		if earshot(x, game.wisp_g):
			var where := voice_from(x, game.kid.global_position + Vector3(0, 1.2, 0), game.level.id)
			x.remember("told", "Wisp said%s: \"%s\"" % [" (%s)" % where if where != "" else "", text])
			x.hear_line("Wisp", text, where)
			_heard_from(x, "wisp", text, game.wisp_g, _names(text, x.pal.pal_name) or x == of(game.active))


## Words you said, as text (tests): to whoever you named, or the one you chose.
func hear_text(text: String, t_end: int) -> void:
	_got_words(text)
	var to: Array = []
	for x in all():
		if _names(text, x.pal.pal_name) and (not x.pal.folk or earshot(x, game.wisp_g)):
			to.append(x)
	# "Mo, what do you think of Bo?": the name said first, before a comma, is who it's said to
	for x in to.duplicate():
		if RegEx.create_from_string("(?i)^\\W*(hey |hi |hello |oi )?" + x.pal.pal_name + "\\b\\s*[,!?]").search(text) != null:
			to = [x]
			break
	if to.is_empty():
		to = [of(game.active)]
	_cancel_thoughts()
	for x in to:
		think(x, "heard", {text = text, from = "wisp", where = voice_from(x, game.kid.global_position + Vector3(0, 1.2, 0), game.level.id)}, {t_end = t_end})


static func _names(text: String, name: String) -> bool:
	var re := RegEx.create_from_string("(?i)\\b" + name + "\\b")
	return re.search(text) != null


# ---------- A thought ----------

func think(m: Mind, why: String, said := {}, meta := {}) -> Brain.Thought:
	if m.body.asleep:
		# Talked to while asleep: they wake up to it
		m.wake("", "someone was talking to me")
	var th := brain.make()
	m.thought = th
	var rec := {who = m.pal.id, why = why, t_end = meta.get("t_end", Time.get_ticks_msec()), depth = meta.get("depth", 0),
		heard = said.get("text", ""), event = said.get("event", "")}
	th.said.connect(_on_said.bind(m, th, rec))
	th.decided.connect(_on_decided.bind(m, th, rec))
	th.finished.connect(_on_finished.bind(m, th, rec))
	_send(m, th, why, said, rec)
	return th


## What they sense, then off to the Worker: the picture is taken now, as they think.
func _send(m: Mind, th: Brain.Thought, why: String, said: Dictionary, rec: Dictionary) -> void:
	if not on:
		# Offline (tests, or no Worker): nothing goes out, not even an answer to the other one
		brain.go(th, {})
		return
	var frame: Dictionary = await game.eyes.look(m.pal)
	if th.cancelled:
		brain.go(th, {})
		return
	m.frame = frame
	rec.ms_look = frame.ms
	rec.image_bytes = frame.bytes
	if dump_frames != "":
		frame.image.save_jpg(dump_frames.path_join("%s-%d.jpg" % [m.pal.id, Time.get_ticks_msec()]), .8)
	var body := thought_body(m, why, said, frame)
	if dump:
		var shown := body.duplicate()
		shown.sight = "<%d chars>" % String(body.sight).length()
		if shown.has("audio"):
			shown.audio = "<audio>"
		print("WISP_THINK ", JSON.stringify(shown))
	rec.t_send = Time.get_ticks_msec()
	brain.go(th, body)


## Everything that goes into one thought (and a thought counted toward noticing they're getting nowhere).
func thought_body(m: Mind, why: String, said: Dictionary, frame: Dictionary) -> Dictionary:
	m.plans.thought(m.mem.life_h)
	var body := {
		who = m.pal.id,
		why = why,
		# Their senses: sight (the picture), and how their body feels; what they hear is in "talk"
		sight = frame.jpg,
		feel = m.feel(),
		doing = m.doing(),
		memory = m.memory_lines(m.on_mind(String(said.get("text", "")) + " " + String(said.get("event", "")))),
		talk = m.heard_lines,
		people = m.people(),
		# How they feel about the others, in words (heart.gd)
		bonds = m.heart.bonds(),
		# Their plans: the day's (what's done, now, later), the next step, and a rethink if one's due
		plan = m.plan,
		day_plan = m.plans.lines(),
		# What they keep to themselves (their eyes only): secrets, and what they said that wasn't so
		inner = m.secrets.lines(),
		# How good they are at what matters here, and what they've learned the hard way about it
		skills = m.skills_now().map(func(k): return m.skills.words(k)),
		learned = m.skills.learned(m.skills_now()),
		replan = m.plans.replan,
		said = m.said_lately(),
		# What they could pass on (gossip.gd): things they saw or were told, and what people want
		news = m.news.lines(m.mem.life_h),
	}
	body.merge(said, true)
	return body


func _on_said(text: String, m: Mind, th: Brain.Thought, rec: Dictionary) -> void:
	text = text.strip_edges()
	rec.say = text
	if text == "" or th.cancelled:
		return
	# Their turn to talk: not over someone else, not while you're talking, and (unless they're answering you)
	# only after a few quiet seconds, so there's room for you to get a word in
	var gap := 0.0 if rec.why == "heard" else QUIET_GAP
	var waited := 0.0
	while (game.talking_now() or ears.listening() or _since_line() < gap) and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if game.talking_now() or ears.listening() or _since_line() < gap or th.cancelled:
		rec.dropped = ["no gap to talk"]
		return
	var tk := game.say(m.pal, text, null, "stream")
	m.pal.voice.begin()
	th.attach(m.pal.voice)
	rec.talk = tk
	rec.voice = m.pal.voice
	pending_first.append(rec)


func _on_decided(r: Dictionary, m: Mind, th: Brain.Thought, rec: Dictionary) -> void:
	rec.merge({do = r.get("do", "none"), at = r.get("at", []), what = r.get("what", ""), dir = r.get("dir", ""), who_to = r.get("who", ""),
		to = r.get("to", ""), plan = r.get("next", r.get("plan", "")), activity = r.get("activity", ""), see = r.get("see", ""), checked = r.get("checked", ""), model = r.get("model", ""),
		provider = r.get("provider", ""), cost = r.get("cost", 0.0), ms_model = r.get("ms", 0), ms_first_token = r.get("firstMs", 0),
		fell_back = r.get("fellBack", ""), engine = r.get("engine", "worker"), usage = r.get("usage", {}), think = r.get("think", ""), honest = r.get("true", "true"), keep = r.get("keep", ""), tell = r.get("tell", 0)}, true)
	# What they noticed, in their own words, is what they remember seeing
	if String(r.get("see", "")).strip_edges() != "":
		m.remember("saw", String(r.see).strip_edges())
	if r.get("remember", "") != "":
		m.remember("note", r.remember)
	_plan_reply(m, r)
	_private(m, r, rec)
	_passed_on(m, r, rec)
	if th.cancelled:
		return
	var act: String = r.get("do", "none")
	if act != "none" and act in Mind.VERBS:
		var at = r.get("at", [])
		if at is Array and at.size() >= 2:
			at = [float(at[0]) / 1000.0, float(at[1]) / 1000.0]
		rec.started = m.start(act, {at = at, what = r.get("what", ""), dir = r.get("dir", ""), who = r.get("who", ""), place = r.get("place", "")})
	# Said to someone: they may answer (whoever it was meant for, or named, and near enough)
	var say: String = rec.get("say", "")
	var to: String = String(r.get("to", "")).to_lower()
	var o: Mind = null
	for x in all():
		if x != m and (x.pal.id == to or (to == "" and _names(say, x.pal.pal_name))) and earshot(x, m.pal.position):
			o = x
			break
	if o != null and say != "" and not rec.has("dropped"):
		var depth: int = rec.get("depth", 0)
		if depth < 2:
			var tk: Game.Talk = rec.get("talk")
			if tk and not tk.over:
				await tk.done
			if not (o.thought and not o.thought.over):
				think(o, "chat", {text = say, from = m.pal.id}, {depth = depth + 1})


func _on_finished(r: Dictionary, m: Mind, th: Brain.Thought, rec: Dictionary) -> void:
	if r.get("type", "") == "error":
		rec.error = r.get("error", "")
	var a: Dictionary = r.get("audio", {})
	rec.voice_bytes = th.audio_bytes
	rec.voice_chars = a.get("chars", 0)
	rec.ms_say = th.say_ms
	rec.ms_audio_arrived = th.first_audio_ms
	rec.finished = true
	_maybe_log(rec)


## Watch for each line's first sound: from the end of what you said (as the mic heard it end) to their voice.
func _first_words() -> void:
	for rec in pending_first.duplicate():
		var v: Voice = rec.voice
		var tk: Game.Talk = rec.talk
		if v.sounding() and not rec.has("ms_first_word"):
			rec.ms_first_word = int(v.started_at * 1000.0) - rec.t_end
		if tk.over:
			pending_first.erase(rec)
			_maybe_log(rec)


func _maybe_log(rec: Dictionary) -> void:
	var tk = rec.get("talk")
	if rec.get("finished", false) and (tk == null or tk.over):
		_log(rec)


func _log(rec: Dictionary) -> void:
	if rec.get("logged", false):
		return
	rec.logged = true
	var out := rec.duplicate()
	for k in ["talk", "voice", "logged", "finished"]:
		out.erase(k)
	stats.append(out)
	print("WISP_TALK ", JSON.stringify(out))
