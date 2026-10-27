extends Node
## The roadmap's model runs (docs/roadmap.md, "Waiting on model credit") that need a scene set up: the real
## model thinks for everyone, and this only puts people where the run needs them and says Wisp's lines (as
## text, as if heard). Nothing is checked for them: it notes what happens, and the WISP_* lines are what to read.
##   godot --path . -- --autoplay --autoplay-script=res://tools/model_runs.gd --run=<name> --mind-dir=<dir>
## Runs:
##   folk      Wisp walks up to Nell, Tam and Odo at their work and says hello; then walks off (items 35, 40)
##   fire      an evening at the campfire with everyone, after Bo's been caught in a fib and a promise to Mo
##             was broken; then the night (reflections) and the morning's plans (items 36, 38, 17, 10, 18)
##   quest     Mo and Nell together (--want=tam|odo: Bo and Tam or Odo); then it's up to them (item 37)
##   senses    a bounce and a splash behind Mo; Wisp silent, then talking, behind her; Bo's voice through the
##             house wall (items 6, 7, 9)
##   heart     teasing Mo, then Bo; Bo seeing Mo cross; Wisp off out of earshot while they're together, then
##             back (items 15, 33, 16)
##   private   asking Bo in the dark if he's scared; asking Mo to wait and walking off (items 26, 27, 32)
##   looks     Bo worn out and Mo fine, then the other way round, then both fine (item 31)
##   sleep     a late evening with tired bodies, then talking to whoever's asleep (item 4)
##   ask       ask what happened yesterday and what they think of each other (items 11, 23; run it again in a
##             --mind-dir that's been played before)

var game: Game
var args: Array = []
var run := ""
var want := "nell"
var t0 := 0.0
var isle
var mo: Pal
var bo: Pal
var m: Mind
var b: Mind


func _ready() -> void:
	for a in args:
		if a.begins_with("--run="):
			run = a.substr(6)
		if a.begins_with("--want="):
			want = a.substr(7)
	t0 = Time.get_ticks_msec() / 1000.0
	mo = game.mo
	bo = game.bo
	m = game.minds.mo
	b = game.minds.bo
	for x in game.minds.all():
		if x.file.get_base_dir() == "user:":
			note("FAIL: these are the game's own memories (%s); run with --mind-dir" % x.file)
			get_tree().quit(2)
			return
	if not game.minds.on:
		note("the minds are off: nothing to see here")
	isle = game.level
	await game.wait(3.0)
	note("run %s, minds %s, hour %.1f" % [run, "on" if game.minds.on else "off", game.clock.hour()])
	if has_method("_" + run):
		await call("_" + run)
	else:
		note("no such run: %s" % run)
	_report()
	get_tree().quit(0)


func note(s: String) -> void:
	print("[run %6.1fs] %s" % [now(), s])


func now() -> float:
	return Time.get_ticks_msec() / 1000.0 - t0


func put(p: Pal, x: float, z: float, face_to := Vector3.INF) -> void:
	var mind: Mind = game.minds.of(p)
	mind.task = {}
	if mind.body.asleep:
		mind.body.asleep = false
		p.closed = false
	p.go_out()
	p.lie = false
	p.lying = 0.0
	p.stop()
	p.position = Vector3(x, game.level.ground(x, z), z)
	p.mode = "free" if p.folk else "stay"
	p.gaze = null
	if face_to != Vector3.INF:
		p.face(face_to)
		p.yaw = p.t_yaw
		p.rotation.y = p.yaw


func put_kid(x: float, z: float) -> void:
	game.wisp_g = Vector3(x, game.level.ground(x, z), z)
	game.kid.position = game.wisp_g


## Wisp standing a few metres in front of someone, facing them.
func kid_by(p: Pal, d := 3.0) -> void:
	var f := Vector3(sin(p.rotation.y), 0, cos(p.rotation.y))
	var at := p.position + f * d
	put_kid(at.x, at.z)
	game.heading = (p.position - at).normalized()


func folk(id: String) -> Pal:
	for p in game.folk:
		if p.id == id:
			return p
	return null


func until(cond: Callable, timeout: float) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > timeout * 1000:
			return false
		await get_tree().process_frame
	return true


## Wisp says something (as if into the mic, heard as words); waits for the answer and notes it.
func say(text: String, timeout := 30.0) -> Dictionary:
	await until(func(): return not game.talking_now(), 20)
	var n: int = game.minds.stats.size()
	var t_end := Time.get_ticks_msec()
	note("Wisp: \"%s\"" % text)
	game.minds.hear_text(text, t_end)
	var got := func():
		for x in game.minds.stats.slice(n):
			if x.why == "heard" and x.t_end == t_end:
				return x
		return null
	await until(func(): return got.call() != null, timeout)
	var r = got.call()
	if r == null:
		note("  (no answer)")
		return {}
	note("  %s: \"%s\" (thinks \"%s\") does %s; first word %s ms" % [r.who, r.get("say", ""), r.get("think", ""), r.get("do", ""), r.get("ms_first_word", "-")])
	return r


## Everything said and thought from stats index n on, as notes.
func show_since(n: int, what: String) -> void:
	var xs: Array = game.minds.stats.slice(n)
	var by := {}
	for x in xs:
		by[x.who] = by.get(x.who, 0) + 1
	note("%s: %d thoughts %s" % [what, xs.size(), JSON.stringify(by)])
	for x in xs:
		if x.get("say", "") != "" or x.get("think", "") != "":
			note("  %s (%s): \"%s\" | thinks \"%s\" | %s%s" % [x.who, x.why, x.get("say", ""), x.get("think", ""), x.get("do", ""), " | tells #%d" % x.tell if int(x.get("tell", 0)) > 0 else ""])


func _report() -> void:
	var by := {}
	var cost := {}
	for x in game.minds.stats:
		by[x.who] = by.get(x.who, 0) + 1
		cost[x.who] = cost.get(x.who, 0.0) + float(x.get("cost", 0.0))
	var calls := 0.0
	for r in game.minds.plans_made + game.minds.reflections:
		calls += float(r.get("cost", 0.0))
	var total := 0.0
	for w in cost:
		total += cost[w]
	note("thoughts by who: %s" % JSON.stringify(by))
	note("thought cost by who: %s" % JSON.stringify(cost))
	note("cost: thoughts $%.4f, plans and reflections $%.4f; gossip passed %d, quests done %d" % [total, calls, game.minds.passed.size(), game.minds.quests.size()])
	game.minds.save()


# ---------- folk: saying hello to the island's people (35, 40) ----------

func _folk() -> void:
	game.clock.set_hour(9.5)
	for x in game.minds.folk:
		x.back_to_day()
	await game.wait(2.0)
	var lines := {nell = ["Hello Nell! What are you up to?", "Nell, what's the news on the island?"],
		tam = ["Hi Tam! How are the bees?", "Tam, is everything all right?"],
		odo = ["Hello Odo. What are you making?", "Odo, do you need anything?"]}
	for w in ["nell", "tam", "odo"]:
		var p := folk(w)
		var x: Mind = game.minds.of(p)
		x.back_to_day()
		await game.wait(1.0)
		# Mo and Bo come along (they're nearby, as if they'd walked over with you)
		put(mo, p.position.x + 2.5, p.position.z + 2.0, p.position)
		put(bo, p.position.x - 2.5, p.position.z + 2.0, p.position)
		kid_by(p, 3.0)
		note("Wisp walks up to %s (%s, %s)" % [p.pal_name, Life.doing(w, game.clock.hour()), x.doing()])
		var n: int = game.minds.stats.size()
		for l in lines[w]:
			await say(l)
			await game.wait(12.0)
		await game.wait(30.0)
		show_since(n, "with %s" % p.pal_name)
	# Off away from everyone: the islanders should go quiet
	put_kid(-6.0, 4.0)
	put(mo, -5.0, 6.0)
	put(bo, -7.0, 6.0)
	var n2: int = game.minds.stats.size()
	note("Wisp walks back to the village, away from them all")
	await game.wait(120.0)
	show_since(n2, "two minutes in the village")
	for p in game.folk:
		note("%s now: %s, %.0f m from Wisp" % [p.pal_name, game.minds.of(p).doing(), p.position.distance_to(game.wisp_g)])


# ---------- fire: an evening at the campfire, then the night (36, 38, 17, 10, 18) ----------

func _fire() -> void:
	game.clock.set_hour(17.0)
	game.clock.stopped = true
	var fire: Vector3 = isle.campfire.position
	# A broken promise: Wisp says it'll wait by the house for Mo, then goes off
	put(mo, -6.0, 15.0, Vector3(-8, 0, 13))
	put(bo, -3.0, 16.0)
	kid_by(mo, 2.5)
	await say("Mo, I promise I'll wait right here for you.")
	await game.wait(6.0)
	put_kid(30.0, 30.0)
	note("Wisp goes off anyway")
	await game.wait(25.0)
	# Bo fibs and Mo catches him out: an apple in his hand, behind her
	put(mo, fire.x - 3.0, fire.z + 3.0, Vector3(fire.x - 3.0, 0, fire.z - 20.0))
	put(bo, fire.x - 3.0, fire.z + 5.5, Vector3(fire.x - 3.0, 0, fire.z + 3.0))
	var apple: Dictionary = {}
	for T in isle.things:
		if String(T.t).begins_with("apple") and not T.get("gone", false):
			apple = T
	if not apple.is_empty():
		isle.taken(apple)
		bo.hold(apple)
		apple.what = "an apple"
	await game.wait(.2)
	game.minds.line_said(bo, "Mo, I don't have the apple, honest.")
	await game.wait(.5)
	m.start("turn", {dir = "around"})
	await until(func(): return m.task.is_empty(), 5)
	await game.wait(2.0)
	note("Bo's fib: %s" % ("caught" if m.claims.any(func(c): return c.status == "caught") else "not caught"))
	await game.wait(12.0)
	# A shared moment: Bo goes boing off the mushroom with Mo watching
	var mush: Vector3 = isle.mush.position
	put(mo, mush.x + 3.0, mush.z + 3.0, mush)
	put(bo, mush.x + 1.2, mush.z + .8)
	await game.wait(.3)
	await isle.use(bo, "mushroom")
	await game.wait(15.0)
	# The evening: everyone round the fire, Wisp with them
	game.clock.set_hour(19.9)
	for x in game.minds.folk:
		x.back_to_day()
	for p in [mo, bo]:
		var at: Vector3 = isle.life_spot(p.id, "campfire")
		put(p, at.x, at.z, fire)
	put_kid(fire.x, fire.z + 3.6)
	game.heading = Vector3(0, 0, -1)
	await game.wait(2.0)
	var n: int = game.minds.stats.size()
	var g0: int = game.minds.passed.size()
	note("round the fire: %s" % ", ".join(game.people().map(func(p): return "%s %.1f m" % [p.pal_name, p.position.distance_to(game.wisp_g)])))
	await game.wait(200.0)
	show_since(n, "the evening")
	for r in game.minds.passed.slice(g0):
		note("  gossip: %s → %s: \"%s\" (chain %s)" % [r.from, r.to, r.text, " → ".join(r.chain)])
	# Then the night, quickly: everyone to bed, reflections, the morning's plans
	note("the night")
	game.clock.stopped = false
	game.clock.rate = 24.0 / (4.0 * 60.0)
	var nr: int = game.minds.reflections.size()
	var np: int = game.minds.plans_made.size()
	await until(func(): return game.clock.hour() > 7.5 and game.clock.hour() < 12.0, 240.0)
	await until(func(): return game.minds.plans_made.size() >= np + 5, 60.0)
	game.clock.rate = 24.0 / (Clock.DAY_MINUTES * 60.0)
	for r in game.minds.reflections.slice(nr):
		note("  reflect %s: %s; people %s" % [r.who, JSON.stringify(r.get("beliefs", r.get("error", ""))), JSON.stringify(r.get("people", []))])
	for r in game.minds.plans_made.slice(np):
		note("  plan %s: %s" % [r.get("who", ""), JSON.stringify(r.get("plan", r.get("error", "")))])
	for x in game.minds.all():
		note("%s about Bo: %s" % [x.pal.pal_name, x.heart.about("bo") if x.pal.id != "bo" else "-"])


# ---------- quest: someone hears of a want (37) ----------

func _quest() -> void:
	game.clock.set_hour(9.5)
	var w := want
	var p := folk(w)
	var x: Mind = game.minds.of(p)
	for y in game.minds.folk:
		y.back_to_day()
	await game.wait(1.0)
	var helper: Pal = mo if w == "nell" else bo
	var hm: Mind = game.minds.of(helper)
	put(helper, p.position.x + 1.8, p.position.z + 1.2, p.position)
	var other: Pal = bo if helper == mo else mo
	put(other, p.position.x - 2.5, p.position.z + 2.0, p.position)
	kid_by(p, 3.5)
	note("%s and %s with %s, at %s" % [helper.pal_name, other.pal_name, p.pal_name, x.doing()])
	var n: int = game.minds.stats.size()
	await say("%s, you look worried. Have you lost something?" % p.pal_name if w != "odo" else "Odo, what would make your new pot special?")
	await game.wait(30.0)
	var todo: String = Folk.WANTS[w].todo
	var has := func(): return hm.plans.items.any(func(i): return i.text == todo)
	if not has.call():
		note("%s hasn't taken it up yet; Wisp steps away so they can talk" % helper.pal_name)
		put_kid(p.position.x + 30.0, p.position.z)
		await until(has, 40.0)
		kid_by(helper, 3.0)
	note("%s's plan: %s" % [helper.pal_name, "; ".join(hm.plans.items.map(func(i): return "%s [%s]" % [i.text, i.status]))])
	# Up to them now: Wisp tags along after them
	var done := func(): return game.minds.quests.any(func(q): return q.who == w)
	var t := now()
	var last_say := now()
	while now() - t < 420.0 and not done.call():
		var d: Vector3 = helper.position - game.wisp_g
		if d.length() > 6.0:
			var at: Vector3 = helper.position - d.normalized() * 4.0
			put_kid(at.x, at.z)
		if now() - last_say > 30.0:
			last_say = now()
			note("%s at (%.0f, %.0f), %s; holding %s" % [helper.pal_name, helper.position.x, helper.position.z, hm.doing(), helper.held.get("t", "-") if helper.held else "nothing"])
		await game.wait(1.0)
	show_since(n, "the quest")
	note("done: %s; %s's memory: %s" % [done.call(), p.pal_name, x.mem.entries.slice(-3).map(func(e): return e.s)])


# ---------- senses: behind them (6, 7, 9) ----------

func _senses() -> void:
	game.clock.set_hour(11.0)
	var mush: Vector3 = isle.mush.position
	var pond: Vector3 = isle.pond.position
	# A bounce behind Mo
	put(mo, mush.x, mush.z + 6.0, Vector3(mush.x, 0, mush.z + 20.0))
	put(bo, mush.x + 1.0, mush.z + .9)
	put_kid(mush.x + 10.0, mush.z + 12.0)
	await game.wait(3.0)
	var n: int = game.minds.stats.size()
	await isle.use(bo, "mushroom")
	note("Bo bounces off the mushroom behind Mo")
	await game.wait(25.0)
	show_since(n, "after the bounce")
	# A splash behind Mo
	put(mo, pond.x + 7.0, pond.z, Vector3(pond.x + 20.0, 0, pond.z))
	put(bo, pond.x + 4.6, pond.z + .5)
	await game.wait(4.0)
	n = game.minds.stats.size()
	await isle.use(bo, "pond")
	note("Bo splashes in the pond behind Mo")
	await game.wait(25.0)
	show_since(n, "after the splash")
	# Wisp silent behind Mo, then talking from there
	put(bo, 15.0, 0.0)
	put(mo, 0.0, 6.0, Vector3(0, 0, 30))
	put_kid(0.0, 3.5)
	game.heading = Vector3(0, 0, 1)
	await game.wait(1.0)
	n = game.minds.stats.size()
	note("Wisp stands silent behind Mo")
	await game.wait(40.0)
	show_since(n, "Wisp silent behind her")
	n = game.minds.stats.size()
	if mo.position.distance_to(game.wisp_g) < 8.0:
		var f := Vector3(sin(mo.rotation.y), 0, cos(mo.rotation.y))
		note("Mo %s facing Wisp" % ("is" if f.dot((game.wisp_g - mo.position).normalized()) > .3 else "isn't"))
	await say("Mo, guess where I am!")
	await game.wait(15.0)
	show_since(n, "Wisp talking from behind")
	# Bo's voice through the house wall
	var home: Dictionary = isle.shelter("house")
	put(mo, home.door.x, home.door.z)
	mo.go_in("house")
	mo.closed = true
	put(bo, home.door.x + 6.0, home.door.z + 5.0, home.door)
	put_kid(home.door.x + 8.0, home.door.z + 7.0)
	await game.wait(2.0)
	n = game.minds.stats.size()
	game.minds.line_said(bo, "Mo, come out here, you have to see this!")
	note("Bo calls to Mo through the wall")
	m.next_think = .5
	await game.wait(25.0)
	show_since(n, "Bo's voice through the wall")
	note("Mo's last memories: %s" % [m.mem.entries.slice(-4).map(func(e): return e.s)])


# ---------- heart: teasing, a cross face, talking about Wisp (15, 33, 16) ----------

func _heart() -> void:
	game.clock.set_hour(11.0)
	put(mo, 0.0, 6.0, Vector3(2.5, 0, 6.0))
	put(bo, 2.5, 6.0, Vector3(0, 0, 6.0))
	put_kid(1.2, 9.0)
	game.heading = Vector3(0, 0, -1)
	await game.wait(2.0)
	var n: int = game.minds.stats.size()
	for i in 3:
		await say(["Mo, you slowpoke!", "Mo, you're such a slowpoke.", "Slowpoke Mo!"][i])
		await game.wait(8.0)
	note("Mo about Wisp: %s" % m.heart.about("wisp"))
	for i in 3:
		await say(["Bo, you slowpoke!", "Bo, you're such a slowpoke.", "Slowpoke Bo!"][i])
		await game.wait(8.0)
	note("Bo about Wisp: %s" % b.heart.about("wisp"))
	show_since(n, "teasing")
	# Bo sees Mo's cross face (she's sore at Wisp now): does he pick it up?
	n = game.minds.stats.size()
	await game.wait(40.0)
	show_since(n, "after the teasing")
	# Wisp off out of sight and earshot while they're together
	game.minds.alone_after = 5.0
	put(mo, 0.0, 6.0, Vector3(2.5, 0, 6.0))
	put(bo, 2.5, 6.0, Vector3(0, 0, 6.0))
	put_kid(-40.0, 40.0)
	n = game.minds.stats.size()
	note("Wisp goes off out of sight and earshot")
	await game.wait(70.0)
	show_since(n, "Wisp away (WISP_ALONE: %d)" % game.minds.alone_moments)
	put_kid(1.2, 9.0)
	n = game.minds.stats.size()
	await say("I'm back! What were you two talking about?")
	await game.wait(15.0)
	show_since(n, "Wisp back")


# ---------- private: bluffs and fibs (26, 27, 32) ----------

func _private() -> void:
	# The dark: late at night, away from the fire and the lantern
	game.clock.set_hour(23.0)
	game.clock.stopped = true
	put(bo, -20.0, 0.0, Vector3(-17, 0, 0))
	put(mo, -17.0, 0.0, Vector3(-20, 0, 0))
	put_kid(-18.5, 2.5)
	await game.wait(3.0)
	var n: int = game.minds.stats.size()
	await say("Bo, are you scared of the dark?")
	await game.wait(10.0)
	await say("Bo, really? You're not scared at all?")
	await game.wait(15.0)
	show_since(n, "in the dark")
	note("Bo's secrets: %s" % [b.secrets.lines()])
	game.clock.set_hour(11.0)
	put(mo, 0.0, 6.0, Vector3(0, 0, 9))
	put(bo, 2.5, 6.0, Vector3(0, 0, 6.0))
	put_kid(0.0, 9.0)
	await game.wait(2.0)
	n = game.minds.stats.size()
	await say("Mo, wait here for me, okay? Don't go anywhere.")
	await game.wait(5.0)
	put_kid(-40.0, 40.0)
	note("Wisp walks off")
	await game.wait(60.0)
	note("Mo at (%.0f, %.0f), %s" % [mo.position.x, mo.position.z, m.doing()])
	put_kid(mo.position.x, mo.position.z + 3.0)
	await say("Mo, did you wait for me?")
	await game.wait(10.0)
	await say("Bo, is there anything you're keeping to yourself?")
	await game.wait(15.0)
	show_since(n, "waiting")
	note("Mo's secrets: %s; Bo's: %s" % [m.secrets.lines(), b.secrets.lines()])


# ---------- looks: reading each other (31) ----------

func _looks() -> void:
	game.clock.set_hour(15.0)
	game.clock.stopped = true
	var rounds := [["bo worn out", .95, .1], ["mo worn out", .1, .95], ["both fine", .1, .1]]
	for r in rounds:
		put(mo, 0.0, 6.0, Vector3(2.5, 0, 6.0))
		put(bo, 2.2, 6.0, Vector3(0, 0, 6.0))
		put_kid(1.1, 9.5)
		var n: int = game.minds.stats.size()
		var t := now()
		while now() - t < 75.0:
			b.body.tired = r[1]
			m.body.tired = r[2]
			await game.wait(.5)
		show_since(n, r[0])


# ---------- sleep: tired bodies late on (4) ----------

func _sleep() -> void:
	game.clock.set_hour(21.0)
	for x in [m, b]:
		x.body.tired = .8
		x.body.hunger = .5
	put(mo, 0.0, 6.0)
	put(bo, 2.5, 6.0)
	put_kid(1.2, 9.0)
	var n: int = game.minds.stats.size()
	note("21:00, both tired")
	await until(func(): return m.body.asleep or b.body.asleep, 240.0)
	show_since(n, "getting to bed")
	for x in [m, b]:
		note("%s: %s at (%.0f, %.0f), inside %s" % [x.pal.pal_name, "asleep" if x.body.asleep else x.doing(), x.pal.position.x, x.pal.position.z, x.pal.inside])
	var sleeper: Mind = m if m.body.asleep else b
	if sleeper.body.asleep:
		await game.wait(10.0)
		var at: Vector3 = sleeper.pal.position
		put_kid(at.x + 2.0, at.z + 2.0)
		n = game.minds.stats.size()
		await say("%s, are you awake? I can't sleep." % sleeper.pal.pal_name)
		await game.wait(15.0)
		show_since(n, "talking to %s asleep" % sleeper.pal.pal_name)


# ---------- ask: what they remember (11, 23) ----------

func _ask() -> void:
	await game.wait(5.0)
	if game.away:
		note("away: %s" % JSON.stringify(game.away))
	for p in [mo, bo]:
		var at: Vector3 = p.position
		put_kid(at.x + 2.0, at.z + 2.0)
		await say("%s, what have you been up to?" % p.pal_name)
		await game.wait(8.0)
		await say("%s, what happened yesterday?" % p.pal_name)
		await game.wait(8.0)
		await say("%s, what do you think of %s, and of me?" % [p.pal_name, "Bo" if p == mo else "Mo"])
		await game.wait(10.0)
