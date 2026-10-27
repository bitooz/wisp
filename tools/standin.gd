extends RefCounted
## A stand-in for the model, for tests that mustn't call it (tools/world_test.gd). It looks after its body by
## simple rules (eat when hungry or before bed, sleep indoors when tired at night, warm up by a fire when cold, get to a light
## when scared, wander when bored), and acts the way the model does: it looks (a picture from the pal's own
## eyes) and points at a spot in that picture, through the same Mind.start(). Unlike the model, it peeks at the
## body's numbers and the world's positions to choose; it's a test, never what the model gets.

var game: Game
## What it chose, each time: [time, who, verb, why]
var log: Array = []
## Print every point it makes (--standin-verbose)
var verbose := OS.get_cmdline_user_args().has("--standin-verbose")


func _init(g: Game) -> void:
	game = g


## Turn to face a spot, look, and say where it shows in the picture ([x, y] from 0 to 1), or [] if it doesn't.
func point(m: Mind, target: Vector3) -> Array:
	var p := m.pal
	p.face(target)
	p.yaw = p.t_yaw
	p.rotation.y = p.yaw
	p.gaze = target
	await game.get_tree().process_frame
	m.frame = await game.eyes.look(p)
	var q: Vector2 = game.eyes.project(m.frame, target)
	if q.x < 0 or q.x > 1 or q.y < 0 or q.y > 1:
		return []
	return [q.x, q.y]


## Do something pointed at a spot in their picture. Far off, walk closer first (pointing at the ground on the
## way), as a kid would; with someone or something in the way, step round it.
func act(m: Mind, verb: String, target: Vector3, what := "") -> bool:
	var p := m.pal
	var flat := Vector3(target.x - p.position.x, 0, target.z - p.position.z)
	var goal := target
	if flat.length() > 8.0 and verb != "rest":
		goal = target - flat.normalized() * 3.0
		goal.y = game.level.ground(goal.x, goal.z)
		verb = "go"
		what = "over there"
	var at := await point(m, goal)
	if at.is_empty():
		return m.start("go", {at = [.5, .6], what = "that way"})
	var hit: Dictionary = game.eyes.resolve(m.frame, at[0], at[1], [p.body.get_rid()])
	if verbose:
		print("[standin] %s at %s: %s %s -> point %s hits %s at %.1f m" % [p.id, p.position.snapped(Vector3.ONE * .1), verb, goal.snapped(Vector3.ONE * .1),
			at, hit.get("tag", "-"), hit.get("distance", -1.0)])
	if not hit.is_empty() and hit.node is Node and Build.tag_of(hit.node) != "" and hit.distance < m.frame.eye.distance_to(goal) - 1.0 \
			and hit.pos.distance_to(goal) > 3.0:
		# Something's in the way (someone, the mushroom): step round it
		var side := flat.normalized().rotated(Vector3.UP, .9 if randf() < .5 else -.9) * 3.0
		var spot := p.position + side
		spot.y = game.level.ground(spot.x, spot.z)
		var go_at := await point(m, spot)
		return m.start("go", {at = go_at if not go_at.is_empty() else [.5, .7], what = "round them"})
	return m.start(verb, {at = at, what = what})


## Standing in for the model's reflection at night (minds.gd, Minds.reflector): from the day's memories, the
## two that mattered most become beliefs, pointing back at them. Counts the calls; `fail` makes it fail.
var reflect_calls := {mo = 0, bo = 0, nell = 0, tam = 0, odo = 0}
var reflect_got := {mo = [], bo = [], nell = [], tam = [], odo = []}
var reflect_fail := {}
## What else the stand-in's reflection says, per pal: {people: [...], promises: [...]}
var reflect_extra := {}


func reflect(m: Mind, day: Array) -> Dictionary:
	reflect_calls[m.pal.id] += 1
	reflect_got[m.pal.id].append(day)
	if reflect_fail.get(m.pal.id, false):
		return {error = "stand-in told to fail"}
	var order := range(day.size())
	order.sort_custom(func(a, b): return m.mem.entries.filter(func(e): return e.id == day[a].id)[0].imp > m.mem.entries.filter(func(e): return e.id == day[b].id)[0].imp)
	var out := []
	for i in order.slice(0, 2):
		var gist: String = String(day[i].line).get_slice("] ", 1)
		out.append({text = "What happened stays with me: %s." % gist, importance = 8, from = [i + 1]})
	var r := {beliefs = out}
	r.merge(reflect_extra.get(m.pal.id, {}))
	return r


## Standing in for the morning's plan (Minds.planner): the first of what they want most, then home by dark.
## Counts the calls, and keeps what it was given.
var plan_calls := {mo = 0, bo = 0, nell = 0, tam = 0, odo = 0}
var plan_got := {mo = [], bo = [], nell = [], tam = [], odo = []}


func plan(m: Mind, body: Dictionary) -> Dictionary:
	plan_calls[m.pal.id] += 1
	plan_got[m.pal.id].append(body)
	if m.pal.folk:
		# The island's other people: their own day, as the game would make it (and anyone's want they'd help with)
		return {day = Plans.fallback(m.pal.id, m.body, m.heart, [], 7.0, body.get("helping", [])), step = "get on with my day"}
	var want: String = "find out what's inside the glowing door on the hill" if m.pal.id == "mo" else "find a way across to the next island"
	var day := [{text = want, why = String(body.goals[0]) if body.goals.size() else ""}]
	for h in body.get("helping", []):
		day.push_front({text = h, why = "they'd be so pleased"})
	return {day = day + [{text = "be home and in bed by dark", why = ""}], step = "head up the path to the hill"}


## Acting on the plan, as the model would: what they're on decides what they do next. Returns what it did.
func follow_plan(m: Mind) -> String:
	var c: Dictionary = m.plans.current()
	if c.is_empty() or not m.task.is_empty() or m.body.asleep:
		return ""
	var text: String = c.text
	if text.contains("glowing door"):
		if m.pal.place_id == "cave":
			game.minds._plan_reply(m, {next = "look round under the hill", activity = "done"})
			return "done"
		var lvl = game.level
		var door: Vector3 = Level.box_of(lvl.arch).get_center()
		if Vector2(m.pal.position.x - door.x, m.pal.position.z - door.z).length() > 10.0:
			m.start("head_to", {place = "the hill with the glowing door"})
			game.minds._plan_reply(m, {next = "go up to the glowing door"})
			return "head_to"
		await act(m, "use", door, "the glowing door")
		game.minds._plan_reply(m, {next = "push the door open and go in"})
		return "use"
	return ""


## Standing in for a whole reply to a thought, as the model would send it ({say, to, think, true, keep, ...}):
## the line goes the way a thought's line goes (said out loud, heard by whoever's near), then the rest of the
## reply is taken as the game takes the model's. Returns the thought's record.
func reply(m: Mind, r: Dictionary, why := "heard") -> Dictionary:
	var th := Brain.Thought.new()
	var rec := {who = m.pal.id, why = why, t_end = Time.get_ticks_msec(), depth = 0, heard = "", event = ""}
	var said := String(r.get("say", ""))
	if said != "":
		await game.minds._on_said(said, m, th, rec)
	await game.minds._on_decided(r, m, th, rec)
	await game.get_tree().process_frame
	await game.get_tree().process_frame
	return rec


## Talking about Wisp when it's just the two of them: what it says follows how it feels about Wisp.
func gossip(m: Mind) -> String:
	var f: float = m.heart.rel.wisp.fond
	var line := "What do you reckon Wisp is up to?"
	if f > .3:
		line = "Wisp's really nice and brave, isn't it?"
	elif f < -.1:
		line = "I don't know, Wisp is a bit annoying."
	game.minds.line_said(m.pal, line)
	return line


## Reacting to the senses, as anyone would: a sound behind them makes them turn round, one off to the side makes
## them turn their head; standing in cold water, they walk out of it. Returns what it did ("" for nothing).
func react(m: Mind) -> String:
	if m.body.asleep or m.pal.inside != "":
		return ""
	if m.body.in_water:
		var land: Vector3 = m.pal.position * .9
		land.y = game.level.ground(land.x, land.z)
		await act(m, "go", land, "dry land")
		return "go"
	var h: Dictionary = m.last_heard
	if h.is_empty() or Time.get_ticks_msec() / 1000.0 - float(h.t) > 3.0:
		return ""
	var a := float(h.angle)
	if absf(a) > 2.2:
		m.start("turn", {dir = "around"})
		return "turn"
	if absf(a) > .7:
		var dir := "left" if a > 0 else "right"
		m.start("look", {dir = dir})
		return "look " + dir
	return ""


## One decision, if they're free to make one. Returns what it chose ("" for nothing).
func decide(m: Mind) -> String:
	var b := m.body
	if b.asleep or m.pal.inside != "" or (not m.task.is_empty() and m.task.get("phase", "") != "rest"):
		return ""
	var lvl = game.level
	var why := ""
	var verb := ""
	var target = null
	var what := ""
	var bedtime: bool = b.tired > .55 and (game.clock.night() > .5 or b.tired > .8)
	# Hungry, or peckish at bedtime (supper first)
	if (b.hunger > .55 or bedtime and b.hunger > .3) and b.can_eat():
		why = "hungry"
		verb = "eat"
		target = _food(m)
		what = "something to eat"
		if target == null:
			return ""
	elif bedtime and b.can_sleep() == "":
		why = "tired"
		verb = "sleep"
		target = _home()
		what = "our house"
	elif b.cold > .45 and lvl.has_method("fire_burning") and lvl.fire_burning():
		why = "cold"
		verb = "rest"
		target = _by_fire(m)
		what = "by the fire"
	elif b.cold > .45:
		why = "cold"
		verb = "sleep" if b.can_sleep() == "" else "go"
		target = _home()
		what = "our house"
	elif b.fear > .5 and lvl.has_method("fire_burning") and lvl.fire_burning():
		why = "scared"
		verb = "go"
		target = _by_fire(m)
		what = "the fire"
	elif b.bored > .6:
		why = "bored"
		verb = "wander"
	if verb == "":
		return ""
	if m.task.get("phase", "") == "rest" and verb == "rest":
		return ""
	log.append([game.clock.t, m.pal.id, verb, why])
	if verb == "wander":
		m.start("wander", {})
	else:
		await act(m, verb, target, what)
	return verb


## The nearest food it knows of: an apple on the ground, or home (the larder).
func _food(m: Mind) -> Variant:
	var lvl = game.level
	var best = null
	var bd := 1e9
	for T in lvl.things:
		if lvl.edible(T.t) > 0:
			var at := Level.box_of(T.node).get_center()
			var d := at.distance_to(m.pal.position)
			if d < bd:
				bd = d
				best = at
	if best != null and bd < 25.0:
		return best
	if lvl.has_method("fire_burning") and lvl.larder > 0:
		return _home()
	return best


func _home() -> Vector3:
	var lvl = game.level
	return Level.box_of(lvl.house).get_center()


## A spot on the ground beside the campfire, on their side of it.
func _by_fire(m: Mind) -> Vector3:
	var lvl = game.level
	var c: Vector3 = lvl.campfire.global_position
	var d := m.pal.position - c
	d.y = 0
	if d.length() < .1:
		d = Vector3(0, 0, 1)
	var at := c + d.normalized() * 2.2
	at.y = lvl.ground(at.x, at.z)
	return at
