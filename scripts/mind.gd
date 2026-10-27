class_name Mind
extends RefCounted
## Mo or Bo (or one of the island's other people: folk.gd) on the inside: their own memory (a file of their own, kept across restarts), their plan, and what
## they're doing. They know the world only by sight (eyes.gd: a picture from their eyes when they think) and
## by what they hear and feel; they act by pointing at a spot in what they see (go there, pick up, use or go
## into what's there), by turning to look elsewhere, or with someone they know by name (give, follow). The game
## finds what they pointed at with a ray from their eyes and only decides what's physically possible; what
## happens comes back as what they'd feel or hear, and goes into memory. What they noticed is in their own words.
## Their body (body.gd) gets hungry, tired, cold, scared and bored, and they feel it; they can eat, rest and sleep
## when and where they choose, if their body lets them (you can't sleep when you're not sleepy).
## Senses: they see only what's in front of them (Eyes.sees; they turn, or turn their head, to see more); they
## hear sounds from a direction and a rough distance (hearing.gd); and they feel what they touch: bumping into
## things or people, what's underfoot, getting wet, a fire's heat.

## Without the Worker, they still wander off on their own
const BORED_AFTER := {mo = 5.0, bo = 9.0}

var pal: Pal
var game: Game
## Their memory (memory.gd): a stream that fades, with beliefs from reflecting each night
var mem: Memory
## Their mood, and how they feel about the others (heart.gd)
var heart: Heart
## The stream itself (mem.entries): [{k, s, imp, ...}], oldest first
var memory: Array = []
## Hours lived when last saved
var saved_h := 0.0
var file := ""
var dirty := false
var save_at := 0.0
## Places they've been, for wandering (the game's, never sent to them)
var visited := {}
## The picture of their last thought, to resolve where they point (eyes.gd)
var frame := {}
## The last few lines they heard, for the model
var heard_lines: Array = []
var thought: Brain.Thought = null
## When to think next on their own, and about what ("" for nothing in particular)
var next_think := 3.0
var next_event := ""
var last_event := -100.0
## Their plans (plans.gd): the day's, what they're on now, and the next step
var plans: Plans
## What they keep to themselves (secrets.gd): secrets, and what they said that wasn't so
var secrets: Secrets
## What they're good at, and learning (skills.gd)
var skills: Skills
## What they know that's worth passing on (gossip.gd): what they saw, what they were told, what people want
var news: Gossip
## Who they are ("mo", "nell"...), for gossip.gd
var who: String:
	get:
		return pal.id
## Things others told them that they could see for themselves are wrong: [{from, text, kind, subject, h, status}]
var claims: Array = []
var claims_at := 0.0
## The last thing they said out loud, and who heard it: {text, to: ["mo"|"bo"|"wisp"], h}
var last_line := {}
## Asking for today's plan (once a morning)
var planning := false
## The rethink they've been told about (so it's said once), and thoughts since that left it be
var replan_told := ""
var replan_ignored := 0
## The next step, in their own words (the model keeps it): plans.step
var plan: String:
	get:
		return plans.step if plans else ""
	set(v):
		if plans:
			plans.step = v
## What they're doing: {act, t, label, phase, stand, ...}; empty for nothing
var task := {}
var stuck_at := Vector3()
var stuck_t := 0.0
var bored := 0.0
## When they last did something (an action started or finished): standing about too long gets boring
var since := 0.0
## The last thing they did, and how many times in a row
var last_sig := ""
var repeats := 0
## What didn't work, and how often: "use|<their word for it>" -> 2
var failed := {}
## Their body: needs, and whether they're asleep
var body: Body
## How bad each need was last (a band), to notice when one gets worse
var bands := {}
var startled := false
var bored_said := false
## The last sound they heard, and where it seemed to come from: {t, text, angle, from, level}
var last_heard := {}
## When Wisp booped them lately (real seconds)
var boops: Array = []


func _init(p: Pal, g: Game) -> void:
	pal = p
	game = g
	# Tests can keep their memories apart (--mind-dir=name), so runs side by side don't share them
	var dir := "user://"
	var args := Array(OS.get_cmdline_user_args())
	if FileAccess.file_exists("user://autoplay"):
		# On a phone the test's arguments come in a file (game.gd)
		args.append_array(FileAccess.get_file_as_string("user://autoplay").strip_edges().split(" ", false))
	# Offline tests (no model) never write into the game's own memories
	if args.has("--offline"):
		dir = "user://offline/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for a in args:
		if a.begins_with("--mind-dir="):
			dir = "user://" + a.substr(11) + "/"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	file = dir + "mind_%s.json" % p.id
	next_think = 2.0 if p.id == "mo" else 5.0 if p.id == "bo" else 20.0
	since = Time.get_ticks_msec() / 1000.0
	body = Body.new(p.id)
	p.bumped.connect(_bumped)
	load_memory()


# ---------- Memory ----------

## What they knew before the game began: their goals, and what Grandma told them.
const SEEDS := {
	mo = [["told", "Grandma told us the door on the hill hums when it wants to be opened."],
		["told", "Grandma said shadows live under the hill, and they hate fire."],
		["saw", "the door on the hill glowing again, from our house"],
		["note", "I really, really want to know what's inside the glowing door."],
		["saw", "Wisp, a kid with a glowing lantern who turned up on the island and hangs around with us: curly brown hair, a green jacket and a big backpack"],
		["saw", "Bo: a beanie with a red bobble, goggles, a blue vest, dark jeans"]],
	bo = [["told", "Grandma said an ember from under the hill once lit the old brazier on the north-east shore, and a bridge to the next island grew from it."],
		["told", "Grandma said that deep under the hill, behind the glowing door, there's a stone door that only opens for two."],
		["saw", "the next island, far out over the sea"],
		["note", "I want to get across to that island, more than anything."],
		["saw", "Wisp, a kid with a glowing lantern who turned up on the island and hangs around with us: curly brown hair, a green jacket, a big backpack. Not sure about Wisp yet."],
		["saw", "Mo: curly red hair, a red hoodie, a satchel, brown shorts"]],
}


## What they knew before the game began (Mo's and Bo's above; the island's other people: Folk.SEEDS).
static func seeds_of(who_: String) -> Array:
	return SEEDS[who_] if SEEDS.has(who_) else Folk.SEEDS[who_]


func load_memory() -> void:
	news = null
	mem = null
	heart = null
	plans = null
	secrets = null
	skills = null
	claims = []
	if FileAccess.file_exists(file):
		var o = JSON.parse_string(FileAccess.get_file_as_string(file))
		if o is Dictionary and o.get("memory") is Array and not o.memory.is_empty():
			mem = Memory.from_save(o, pal.id, seeds_of(pal.id))
			news = Gossip.from_save(o.get("news"), pal.id)
			# Their plans (from before: the one line they kept is their next step)
			plans = Plans.from_save(o.get("plans"), String(o.get("plan", "")))
			# What they keep to themselves (files from before: nothing yet)
			secrets = Secrets.from_save(o.get("secrets"))
			# What they're good at (files from before: where they start), and claims they could check
			skills = Skills.from_save(o.get("skills"), pal.id)
			claims = o.get("claims", []) if o.get("claims") is Array else []
			# Their heart (from before hearts: as they were at the start)
			heart = Heart.from_save(o.get("heart"), pal.id)
			if not (o.get("heart") is Dictionary):
				dirty = true
			# A file from before memories faded: brought up to date (nothing lost), and saved that way, with a
			# copy of it as it was kept beside it
			if int(o.get("v", 1)) < Memory.VERSION:
				var old := file.get_basename() + ".v%d.json" % int(o.get("v", 1))
				if not FileAccess.file_exists(old):
					DirAccess.copy_absolute(ProjectSettings.globalize_path(file), ProjectSettings.globalize_path(old))
				dirty = true
	if mem == null:
		mem = Memory.seeded(pal.id, seeds_of(pal.id))
		dirty = true
	if news == null:
		news = Gossip.new(pal.id)
	# What they want themselves (the island's other people): theirs to tell anyone who'll listen
	if Folk.has(pal.id) and not news.knows(Gossip.id_of("want", "", pal.id)) and not news.knows(Gossip.id_of("done", "", pal.id)):
		news.witness(pal.id, Folk.WANTS[pal.id].text, .2, mem.life_h, "want", pal.id)
	if heart == null:
		heart = Heart.fresh(pal.id)
	if skills == null:
		skills = Skills.fresh(pal.id)
	if secrets == null:
		secrets = Secrets.new()
	if plans == null:
		plans = Plans.new()
	memory = mem.entries
	save()


func save() -> void:
	# Nothing new, not even time lived: nothing to write
	if not dirty and is_equal_approx(mem.life_h, saved_h):
		return
	dirty = false
	saved_h = mem.life_h
	var o := mem.to_save()
	o.who = pal.id
	o.plan = plan
	o.heart = heart.to_save()
	o.plans = plans.to_save()
	o.secrets = secrets.to_save()
	o.skills = skills.to_save()
	o.claims = claims
	o.news = news.to_save()
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(o))


func forget_all() -> void:
	plan = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	load_memory()


func remember(kind: String, text: String, imp := -1) -> void:
	var e := mem.add(kind, text, imp)
	if e.is_empty():
		return
	dirty = true
	# Big news: worth rethinking the day
	if int(e.imp) >= 8 and kind in ["event", "heard", "felt", "told", "saw"]:
		plans.news(text, mem.life_h)


## What comes to mind for a thought (memory.gd): the last few things, and what's most recent, important and to
## do with what's on their mind now. In order, with when.
func memory_lines(on_mind := "") -> Array:
	dirty = true
	return mem.lines(mem.recall(on_mind))


## What's on their mind now, to call up memories by: their plan, what they're doing and feel, what they've just
## heard or felt, and what they last noticed.
func on_mind(extra := "") -> String:
	var parts := [plan, plans.current().get("text", ""), doing(), extra]
	parts.append_array(body.feel())
	for h in heard_lines.slice(-2):
		parts.append(String(h.said))
	for i in range(memory.size() - 1, maxi(-1, memory.size() - 6), -1):
		if memory[i].k in ["saw", "heard", "felt", "event"]:
			parts.append(String(memory[i].s))
	return " ".join(parts)


## Their own last lines, so they don't say them again.
func said_lately(n := 10) -> Array:
	var out := []
	for i in range(memory.size() - 1, -1, -1):
		if memory[i].k == "said":
			out.push_front(String(memory[i].s).trim_prefix("I said: ").trim_prefix("\"").trim_suffix("\""))
			if out.size() >= n:
				break
	return out


## What they hear said (the last few lines), for the model.
func hear_line(who: String, text: String, where := "") -> void:
	body.perked(.1)
	heard_lines.append({who = who, said = text, where = where})
	if heard_lines.size() > 8:
		heard_lines.pop_front()


func entered() -> void:
	failed.clear()
	visited.clear()
	task = {}
	frame = {}
	# Just come in: they stand where they came in, looking in (not trailing after you onto the steps)
	pal.mode = "stay"
	pal.follow_who = null
	pal.gaze = null
	next_think = 1.5


## How their body feels and what's in their hands: what they'd know without looking.
func feel() -> Array:
	var out := []
	# Their mood (heart.gd), their body: hungry, tired, cold, scared, bored (body.gd), and roughly what time of
	# day it is, outdoors
	out.append("you're " + heart.mood_words())
	out.append_array(body.feel())
	if not pal.folk and alone_together():
		out.append("Wisp isn't around: it's just you and %s" % game.other(pal).pal_name)
	var lvl: Level = game.levels.get(pal.place_id)
	if lvl and lvl.outdoors:
		out.append(game.clock.sense())
	# A sense of the time of their own day: up long past when they'd be in bed
	var h := game.clock.hour()
	if not body.asleep and Life.doing(pal.id, h) == "sleep" and (h > 18.0 or h < 5.0):
		out.append("you'd usually be in bed by now")
	if pal.held:
		out.append("holding %s in your hand" % pal.held.get("what", "something"))
	if pal.plate:
		out.append("standing on something that sank under your feet: it would rise again if you stepped off")
	if pal.recoil > 0:
		out.append("your heart is pounding")
	# Touch: what's underfoot, a fire's heat
	if lvl and pal.inside == "" and pal.lying < .5:
		var under := lvl.underfoot(pal.position)
		if under != "" and not pal.plate:
			out.append(under)
		if lvl.warmth_at(pal.position) > .85:
			out.append("the fire's heat on your face")
	# What they can hear going on: a fire, the waves, footsteps of someone they can't see
	out.append_array(game.hearing.around(pal))
	# What you've noticed about Wisp lately, watching (only while Wisp's in sight)
	var quiet_for: float = minf(game.idle_t, Time.get_ticks_msec() / 1000.0 - game.minds.last_heard_t)
	if quiet_for > 20.0 and _sees(game.kid):
		out.append("Wisp hasn't moved or said a word for %d s" % int(quiet_for))
	# A sense of where places you know are, like knowing your way round home
	var known: Array = []
	for name in game.level.places:
		var at: Vector3 = game.level.places[name]
		known.append([pal.position.distance_to(at), name, at])
	known.sort_custom(func(a, b): return a[0] < b[0])
	for k in known.slice(0, 7):
		if k[0] > 3.0:
			out.append("%s is %s (you know the way: head_to)" % [k[1], where(k[2])])
	# Friends they can see now (in front of them, in the light): never someone behind them
	for n in [game.kid] + game.people():
		if n != pal and n.global_position.distance_to(pal.position) > 2.0 and _sees(n):
			out.append("%s is %s (head_to works for them too)" % ["Wisp" if n == game.kid else n.pal_name, where(n.global_position)])
	return out


## Bumped into by someone: they know who if they can see them, or if it happened right in front of them (too
## close to be in the picture, but you'd know) where there's any light.
func _knows_who(n: Node3D) -> bool:
	if _sees(n):
		return true
	var lvl: Level = game.levels.get(pal.place_id)
	return absf(Hearing.angle_to(pal, n.global_position)) < 1.0 and lvl != null and lvl.light_at(pal.position) > .08 and not body.asleep


## Can they see this person now (where they are, in front of them, in some light)?
func _sees(n: Node3D) -> bool:
	if n == pal or not n.visible:
		return false
	if n == game.kid:
		if game.level.id != pal.place_id:
			return false
	elif n.place_id != pal.place_id or n.inside != "":
		return false
	# Their middle or their face, whichever's in sight (up close, it's the face)
	return game.eyes.sees(pal, n.global_position + Vector3(0, .7, 0), n) or game.eyes.sees(pal, n.global_position + Vector3(0, 1.05, 0), n)


## Which way a place is from here, as they'd feel it (from the way they're looking).
func where(at: Vector3) -> String:
	var d := Vector2(at.x - pal.position.x, at.z - pal.position.z)
	var dist := d.length()
	var f := Eyes.facing(pal)
	var fwd := Vector2(sin(f), cos(f))
	var right := Vector2(-cos(f), sin(f))
	var a := atan2(d.dot(right), d.dot(fwd))
	var side := "straight ahead"
	if absf(a) > 2.4:
		side = "behind you"
	elif a > .35:
		side = "ahead on your right" if a < 1.2 else "to your right"
	elif a < -.35:
		side = "ahead on your left" if a > -1.2 else "to your left"
	return "about %d m away, %s" % [roundi(dist / 5.0) * 5 if dist > 10 else roundi(dist), side]


func doing() -> String:
	match task.get("act", ""):
		"": pass
		"go": return "walking to the spot you pointed at%s" % _w()
		"head_to": return "heading for %s" % task.word
		"pick_up": return "going to pick up%s" % _w()
		"use": return "going to use%s" % _w()
		"enter": return "going into%s" % _w()
		"give": return "taking %s to %s" % [pal.held.get("what", "it") if pal.held else "it", task.who_name]
		"turn": return "turning to look"
		"wander": return "wandering about"
		"eat": return "going to eat" + (_w() if task.get("word", "") != "" else "")
		"rest": return "lying down, resting" if task.get("phase", "") == "rest" else "going to lie down and rest"
		"sleep": return "asleep" if body.asleep else "going to sleep"
	if pal.folk:
		var d := Life.doing(pal.id, game.clock.hour())
		var words := {chore = Folk.CHORE_ING[pal.id], hobby = Folk.HOBBY_ING[pal.id], own = "a bit of time to yourself",
			free = "pottering about at home", breakfast = "breakfast at home", lunch = "lunch at home", supper = "supper at home",
			campfire = "the evening at the campfire", sleep = "time for bed"}
		return "going about your day: %s" % words.get(d, d)
	if pal.mode == "stay":
		return "waiting here"
	if pal.mode == "follow":
		var with: String = "Wisp" if pal.follow_who == null or pal.follow_who == game.wisp else pal.follow_who.pal_name
		return "going along with %s" % with
	return "standing about"


func _w() -> String:
	return " " + task.word if task.get("word", "") != "" else " what you pointed at"


# ---------- What they can do ----------

## The actions they can take, as the model is told. Places and things are pointed at in the picture ("at"),
## people named ("who"). Nothing here says what's in the picture.
## Actions that count as getting somewhere (walking about, looking round and waiting don't)
const PROGRESS := ["pick_up", "use", "enter", "give", "eat", "sleep", "head_to"]
const VERBS := ["go", "pick_up", "use", "enter", "head_to", "give", "drop", "turn", "look", "wait", "wander", "wave", "jump", "eat", "rest", "sleep"]
## Turning your head: how far to the side (radians), and up or down
const HEAD_SIDE := 1.2


func people() -> Array:
	return ["Wisp"] + game.people().filter(func(p): return p != pal).map(func(p): return p.pal_name)


## Which known place they mean by what they called it ("south beach", "the campfire by the house", "home"):
## the place whose words are in it (the main part, before any "by" or "near"; ties go to the nearest), or "".
func place_key(name: String) -> String:
	var places: Dictionary = game.level.places
	var n := name.strip_edges().to_lower().replace("_", " ")
	if n == "":
		return ""
	for k in places:
		if k.to_lower() == n:
			return k
	for k in places:
		if k.to_lower().contains(n) and n.length() > 3:
			return k
	var head := n
	for sep in [" by ", " near ", " next to ", " at ", " behind ", " past ", " beside ", " in front of ", " on ", " for "]:
		var i := head.find(sep)
		if i > 0:
			head = head.left(i)
	var words := _words(head)
	# Home, as they'd say it
	var mine: String = Folk.HOME[pal.id].what if pal.folk else "the house in the village"
	var homely: bool = words.size() <= 1 and (words.is_empty() or words[0] in ["home", "house", "hut", "cottage", "place"])
	if places.has(mine) and homely and (n.contains("home") or n.contains("my ") or n.contains("our ") or not pal.folk and words == ["house"]):
		return mine
	if words.is_empty():
		return ""
	var best := ""
	var top := 0.0
	for k in places:
		var kw := _words(k)
		var common := kw.filter(func(w): return words.has(w)).size()
		if common == 0 or float(common) / kw.size() < .5:
			continue
		# The last word of what they said is what they mean (the woodpile, in "village woodpile")
		var score := float(common) / kw.size() + float(common) / words.size() + (.5 if kw.has(words.back()) else 0.0)
		var at: Vector3 = places[k]
		score -= pal.position.distance_to(at) / 1000.0
		if score > top:
			top = score
			best = k
	if top >= .9:
		return best
	# Other words for the same places (the stairs up, the boat by the house, the fire)
	for w in words:
		var k: String = game.level.place_words.get(w, "")
		if k != "" and places.has(k):
			return k
	return ""


static func _words(s: String) -> Array:
	var out := []
	# What's in brackets is only a hint ("the way back up (where you came in)")
	var bare := s.get_slice("(", 0) if s.contains("(") and not s.begins_with("(") else s
	for w in bare.to_lower().replace("'s", "").replace("-", " ").replace(",", " ").split(" ", false):
		if not w in ["the", "a", "an", "my", "our", "to", "of", "in", "and", "with", "over", "old", "little"]:
			out.append(w)
	return out


func _person(name: String) -> Node3D:
	if name.to_lower() == "wisp":
		return game.kid
	for p in game.people():
		if p != pal and p.pal_name.to_lower() == name.to_lower():
			return p
	return null


func _tag_of_person(n: Node3D) -> String:
	return "you" if n == game.kid else n.id


# ---------- Doing it ----------

## Start what the model chose. a: {at: [x, y] from 0 to 1, what: their word for it, dir, who}. Returns false
## (and why, in memory) if it can't even begin.
func start(act: String, a: Dictionary) -> bool:
	if body.asleep or pal.inside != "":
		# Asleep, or indoors having something to eat: no deciding now
		return false
	if task.get("phase", "") == "rest" and act == "wait":
		return true
	if pal.lie:
		_get_up()
	if act not in ["wave", "jump", "wait", "follow"]:
		since = Time.get_ticks_msec() / 1000.0
	if act not in ["wave", "jump"]:
		# Whatever they were doing stops: a plate they stood on rises again
		game.level.released(pal)
		if pal.path != null:
			pal.stop()
	task = {}
	var word: String = String(a.get("what", "")).strip_edges()
	var pointed: bool = a.get("at") is Array and a.at.size() >= 2 and not frame.is_empty()
	if act in ["eat", "rest", "sleep"] and not pointed:
		# Right where they are (eat: what's in their hands)
		task = {act = act, t = pal.held.t if act == "eat" and pal.held else "", word = word, phase = "do"}
		_act()
		return true
	match act:
		"wave":
			pal._gesture("wave")
			return true
		"jump":
			pal.bounce()
			return true
		"wait":
			pal.mode = "stay"
			return true
		"follow":
			var n := _person(a.get("who", ""))
			if n == null:
				return false
			pal.mode = "follow"
			pal.follow_who = game.wisp if n == game.kid else n
			remember("did", "started going along with %s" % a.who)
			return true
		"drop":
			if not pal.held:
				return false
			var T: Dictionary = pal.let_go()
			game.level.put_down(T, pal.global_position + Vector3(sin(pal.yaw), 0, cos(pal.yaw)) * .5)
			remember("did", "put down %s" % T.get("what", "what I held"))
			return true
		"look":
			# Turning the head (the body stays put): left, right, up, down or ahead; behind is turning round
			var dir := String(a.get("dir", "ahead")).to_lower()
			if dir in ["behind", "back", "around"]:
				return start("turn", {dir = "around"})
			var y: float = pal.yaw + {left = HEAD_SIDE, right = -HEAD_SIDE}.get(dir, 0.0)
			var up: float = {up = 2.2, down = -1.3}.get(dir, -.12)
			var eye := pal.eye_world()
			pal.gaze = eye + Vector3(sin(y), 0, cos(y)) * (1.0 if dir in ["up", "down"] else 3.0) + Vector3(0, up, 0)
			if dir == "ahead":
				pal.gaze = null
			pal.mode = "stay"
			game.minds.after(self, "you looked %s" % ("straight ahead" if dir == "ahead" else ("to your " + dir if dir in ["left", "right"] else dir)))
			return true
		"turn":
			pal.gaze = null
			var turn: float = {left = PI / 3, right = -PI / 3, around = PI, back = PI}.get(String(a.get("dir", "around")).to_lower(), PI)
			task = {act = act, phase = "turn", from = pal.yaw, by = turn, k = 0.0, word = ""}
			pal.mode = "script"
			return true
		"head_to":
			var name: String = String(a.get("place", "")).strip_edges()
			var key := place_key(name)
			if key == "":
				# Someone you know, here: you know where they are (you can hear them)
				var n := _person(name)
				if n != null and n.visible:
					var at: Vector3 = n.global_position
					task = {act = "go", t = "", word = name, person = n, at = at, stand = at + (pal.position - at).normalized() * 1.0, phase = "walk"}
					pal.mode = "free"
					pal.follow_who = null
					pal.gaze = at
					stuck_at = pal.position
					stuck_t = 0
					pal.walk([[task.stand.x, task.stand.z]])
					return true
				_done("wanted to head for %s, but I don't know the way there" % (name if name != "" else "somewhere"), false)
				return false
			var p: Vector3 = game.level.places[key]
			p.y = game.level.ground(p.x, p.z)
			task = {act = act, t = "", word = key, at = game.level.place_looks.get(key, p + (p - pal.position).normalized() * 5.0), stand = p, phase = "walk"}
			# Finding the way: further is harder, and a beginner can take a wrong turn
			var dist := Vector2(p.x - pal.position.x, p.z - pal.position.z).length()
			# (it's home: going wrong is the exception, more so the further it is; a short way never)
			if dist > 15.0 and not try_skill("wayfinding", -.35 + clampf(dist / 250.0, 0.0, .3)):
				var off := (p - pal.position).rotated(Vector3.UP, .9 if skills.tries.wayfinding % 2 == 0 else -.9) * .6
				var wrong: Vector3 = game.level.collide(pal.position + off, .34, false)
				wrong.y = game.level.ground(wrong.x, wrong.z)
				# Ending up in the same part of the island isn't getting lost
				if not game.level.has_method("place_of") or game.level.place_of(wrong) != game.level.place_of(p):
					task.stand = wrong
					task.at = wrong + off.normalized() * 4.0
					task.lost = true
		"wander":
			var spot: Dictionary = game.level.spot_for(self)
			if spot.is_empty():
				return false
			task = {act = act, t = spot.get("tag", ""), word = "", stand = spot.stand, at = spot.at, phase = "walk"}
		"give":
			var n := _person(a.get("who", ""))
			if n == null or not pal.held:
				_done("wanted to give something to %s, but %s" % [a.get("who", "someone"), "there was nothing in my hands" if not pal.held else "they aren't here"], false)
				return false
			var at: Vector3 = n.global_position
			task = {act = act, t = _tag_of_person(n), who_name = a.who, person = n, word = "", at = at, stand = at + (pal.position - at).normalized() * .9, phase = "walk"}
		"go", "pick_up", "use", "enter", "eat", "rest", "sleep":
			if not pointed:
				return false
			var x: float = float(a.at[0])
			var y: float = float(a.at[1])
			var skip := [pal.body.get_rid()]
			var hit: Dictionary = game.eyes.resolve(frame, x, y, skip)
			if hit.is_empty() and act != "go":
				# Past the edge of something (a glow, a thin rim): a hand finds what's right there
				var near := game.eyes.reach(frame, x, y, func(tag): return not game.level.thing(tag).is_empty(), skip)
				if near != "":
					hit = {pos = game.level.thing_pos(near), tag = near, distance = frame.eye.distance_to(game.level.thing_pos(near))}
			if hit.is_empty() and act == "eat" and pal.held and float(pal.held.get("food", 0.0)) > 0:
				# Pointing nowhere in particular with food in hand: that's what they mean
				return start("eat", {at = []})
			if hit.is_empty():
				if act != "go":
					_done("reached toward the sky; there's nothing there to %s" % act.replace("_", " "), false)
					return false
				# Toward the horizon: walk that way a good stretch
				var d: Vector3 = (frame.xf.basis * game.eyes._dir(x, y))
				d.y = 0
				var far: Vector3 = pal.position + d.normalized() * 15.0
				hit = {pos = game.level.collide(far, .34, false), tag = "", distance = 15.0}
			var t := ""
			if act == "pick_up":
				t = game.eyes.reach(frame, x, y, func(tag): return game.level.can_carry(tag), skip)
			elif act == "eat":
				t = game.eyes.reach(frame, x, y, func(tag): return game.level.edible(tag) > 0 or not game.level.shelter(tag).is_empty(), skip)
			elif act == "sleep":
				t = game.eyes.reach(frame, x, y, func(tag): return not game.level.shelter(tag).is_empty(), skip)
			elif act == "rest":
				t = ""
			elif act == "enter":
				# A way through, or someone's door (a knock)
				t = game.eyes.reach(frame, x, y, func(tag): return not game.level.way(tag).is_empty() or not game.level.shelter(tag).is_empty(), skip)
			else:
				t = game.eyes.reach(frame, x, y, func(tag): return not game.level.thing(tag).is_empty(), skip)
			# The hand only finds what's where the eye landed, not something across the room; but a point that
			# grazes past a small thing far off and lands on the ground behind it was meant for the thing
			if t != "" and hit.has("pos") and game.level.thing_pos(t).distance_to(hit.pos) > 2.5 and String(hit.tag) != t:
				var past: bool = hit.distance > frame.eye.distance_to(Level.box_of(game.level.thing(t).node).get_center())
				if not past:
					t = ""
			var at: Vector3 = hit.pos
			var stand: Vector3
			if t != "" and not game.level.shelter(t).is_empty() and act in ["eat", "sleep"]:
				# A house: in at its door
				at = game.level.thing_pos(t)
				stand = game.level.shelter(t).door
			elif t != "":
				var spot: Dictionary = game.level.spot_at(t, self, game.level.use_reach(t) if act != "go" else -1.0)
				at = spot.at
				stand = spot.stand
			else:
				# Somewhere on the ground (or a wall): walk there, stopping short of anything solid
				var back := (pal.position - at)
				back.y = 0
				stand = game.level.collide(at + back.normalized() * (.6 if hit.tag != "" else 0.0), .34, false)
				if act == "rest" or act == "sleep":
					# Lying down there, on the ground (not up against whatever's there)
					stand = game.level.collide(at + back.normalized() * (1.0 if hit.tag != "" else 0.0), .6, false)
			task = {act = act, t = t, word = word, at = at, stand = stand, phase = "walk", dist = hit.distance}
		_:
			return false
	pal.mode = "free"
	pal.follow_who = null
	pal.gaze = task.get("at")
	stuck_at = pal.position
	stuck_t = 0
	pal.walk([[task.stand.x, task.stand.z]])
	return true


func update(dt: float) -> void:
	_show(dt)
	if dirty and Time.get_ticks_msec() / 1000.0 > save_at:
		save_at = Time.get_ticks_msec() / 1000.0 + 3.0
		save()
	if task.is_empty() and pal.folk:
		# The island's other people: their own day goes on
		_day(dt)
		return
	if task.is_empty():
		if pal.mode == "stay" and not pal.plate and pal.position.distance_to(game.wisp_g) > 14.0:
			pal.mode = "follow"
			pal.follow_who = null
		if not game.minds.on and not game.minds.quiet and pal.mode == "follow" and not pal.plate:
			# No Worker: they still get bored and go and look at things
			bored += dt
			if bored > BORED_AFTER[pal.id]:
				bored = randf() * 3.0
				start("wander", {})
		return
	match task.phase:
		"turn":
			task.k += dt / .8
			pal.yaw = task.from + Game.ease_io(minf(1.0, task.k)) * task.by
			pal.t_yaw = pal.yaw
			if task.k >= 1.0:
				pal.mode = "stay"
				# A new view: they look again straight away
				task = {}
				game.minds.after(self, "you turned to look")
		"walk":
			# People move: keep heading for them
			if task.has("person"):
				var who: Vector3 = task.person.global_position
				if who.distance_to(task.at) > .8:
					task.at = who
					task.stand = who + (pal.position - who).normalized() * .9
					pal.walk([[task.stand.x, task.stand.z]])
			if pal.path == null:
				task.phase = "do"
				_act()
			elif pal.position.distance_to(stuck_at) > .4:
				stuck_at = pal.position
				stuck_t = 0
			else:
				stuck_t += dt
				if stuck_t > 2.0:
					pal.stop()
					task.phase = "do"
					if pal.position.distance_to(task.stand) > 1.6:
						_done("tried to get there%s but something was in the way" % (" (to " + task.word + ")" if task.word != "" else ""), false)
					else:
						_act()


# ---------- What shows ----------

var show_in := 0.0
## Time spent on it, both of them together (µs, for the frame-cost numbers)
static var show_us := 0


## How they feel shows on them (looks.gd, drawn by pal.gd), a few times a second: from their body, their
## mood, and how they feel about whoever they're with.
func _show(dt: float) -> void:
	show_in -= dt
	if show_in > 0 or not Pal.expressive:
		return
	show_in = .25
	var t0 := Time.get_ticks_usec()
	var w := with_who()
	pal.with_node = w
	var tag: String = "" if w == null else ("wisp" if w == game.kid else w.id)
	pal.feel = Looks.of(body, heart, tag, clampf(pal.nervous / 2.0, 0.0, 1.0))
	pal.think_at = task.get("at") if task.get("at") is Vector3 else thinking_of()
	show_us += Time.get_ticks_usec() - t0


## Words in what they mean to do, and the place they bring to mind
const THINK_OF := [["door", "the hill with the glowing door"], ["hill", "the hill with the glowing door"],
	["island", "the north-east shore"], ["brazier", "the north-east shore"], ["ember", "the north-east shore"],
	["bridge", "the north-east shore"], ["shell", "the beach in the south"], ["beach", "the beach in the south"],
	["pond", "the pond"], ["home", "the village"], ["house", "the village"], ["village", "the village"],
	["eat", "the village"], ["larder", "the village"], ["sleep", "the village"], ["bed", "the village"]]


## Where what's on their mind is (what they're on in today's plan, or a need that won't wait), if it's
## somewhere here they know: their eyes go there now and then.
func thinking_of():
	var lvl: Level = game.levels.get(pal.place_id)
	if lvl == null or lvl.places.is_empty():
		return null
	var text := String(plans.current().get("text", "")).to_lower()
	if body.hunger > .55 or body.tired > .7:
		text = "home"
	for w in THINK_OF:
		if text.contains(w[0]) and lvl.places.has(w[1]):
			return lvl.places[w[1]]
	return null


## Who they're with now: whoever they're talking to or who's talking to them, else the nearest one they can see
## close by (or null).
func with_who() -> Node3D:
	var near := func(n: Node3D) -> bool: return n.visible and n.global_position.distance_to(pal.position) < 6.0
	var now: float = mem.life_h
	if pal.talk and not last_line.is_empty() and now - float(last_line.h) < .05:
		for id in last_line.to:
			var o = _speaker(id)
			if o is Pal and near.call(o):
				return o
		if last_line.to.has("wisp"):
			return game.kid
	for o in game.people():
		if o != pal and (o.talk or o.mutter > 0) and o.place_id == pal.place_id and near.call(o):
			return o
	if game.kid.talk and game.active == pal:
		return game.kid
	var best: Node3D = null
	var bd := 6.0
	for n in [game.kid] + game.people():
		if n == pal:
			continue
		var d: float = n.global_position.distance_to(pal.position)
		if d < bd and _sees(n):
			best = n
			bd = d
	return best


# ---------- Their own day (the island's other people) ----------

## What part of their day they're in, and what they've begun of it ("day|part")
var day_part := ""
var day_begun := ""
var day_in := 0.0


## Where their day has them by now, straight away (back on the island, or after the game was closed).
func back_to_day() -> void:
	var isle = game.levels.get(pal.place_id)
	if not pal.folk or isle == null or not isle.has_method("life_spot"):
		return
	task = {}
	var now := Life.doing(pal.id, game.clock.hour())
	day_part = now
	# (begun when they next look: they're there)
	day_begun = ""
	if now == "sleep":
		day_begun = "%d|%s" % [mem.day, now]
		_turn_in(true)
		return
	body.asleep = false
	pal.closed = false
	pal.go_out()
	var at: Vector3 = isle.life_spot(pal.id, now)
	pal.place(at.x, at.z)
	pal.position.y = at.y
	pal.mode = "free"
	pal.gaze = null


## Their day, a second at a time: to wherever this part of it has them (their work, the garden, home for a
## meal, the campfire of an evening, bed), and when they get there, doing it (Folk.DID).
func _day(dt: float) -> void:
	day_in -= dt
	if day_in > 0 or body.asleep or pal.inside != "":
		return
	day_in = 1.0
	var isle = game.levels.get(pal.place_id)
	if isle == null or not isle.has_method("life_spot"):
		return
	var now := Life.doing(pal.id, game.clock.hour())
	day_part = now
	var at: Vector3 = isle.life_spot(pal.id, now)
	if Vector2(at.x - pal.position.x, at.z - pal.position.z).length() > 1.0:
		if pal.path == null:
			pal.mode = "free"
			pal.gaze = null
			pal.walk([[at.x, at.z]])
		return
	var key := "%d|%s" % [mem.day, now]
	if key == day_begun:
		return
	day_begun = key
	match now:
		"sleep":
			_turn_in()
		"breakfast", "lunch", "supper":
			_meal()
		"chore", "hobby":
			var good := Skills.roll("%s|%s|%d" % [pal.id, now, mem.day]) < .75
			remember("did", Folk.DID[pal.id][now][0 if good else 1], 2)
			heart.feel(.04 if good else -.03)
			pal._gesture("pick_up")
		"campfire":
			var fire: Vector3 = isle.campfire.position
			pal.face(fire)
			remember("did", "sat down by the campfire for the evening", 2)
		_:
			pal.face(game.wisp_g if pal.position.distance_to(game.wisp_g) < 8.0 else at + Vector3(sin(pal.yaw), 0, cos(pal.yaw)))


## Home for a meal: in, a while at the table, and out again.
func _meal() -> void:
	var isle = game.levels.get(pal.place_id)
	var t := "hut_" + pal.id
	var home: Dictionary = isle.shelter(t)
	if home.is_empty():
		return
	pal.go_in(t)
	game.hearing.make(home.door, pal.place_id, "a door opening and shutting", 8.0, pal)
	await game.wait(6.0)
	if pal.inside == "" or body.asleep:
		return
	body.eat(.55, "a meal")
	heart.feel(.05)
	pal.go_out(home.door)
	game.hearing.make(home.door, pal.place_id, "a door opening and shutting", 8.0, pal)
	remember("did", "had a meal at home", 1)


## Bed, at home (now: straight in, without the walk, when catching up).
func _turn_in(now := false) -> void:
	var isle = game.levels.get(pal.place_id)
	var t := "hut_" + pal.id
	var home: Dictionary = isle.shelter(t) if isle != null else {}
	if home.is_empty():
		return
	if now:
		pal.position = home.door
	pal.go_in(t)
	pal.closed = true
	pal.mode = "stay"
	body.asleep = true
	body.resting = false
	task = {act = "sleep", phase = "sleep", t = t, word = "", door = home.door}
	if not now:
		remember("did", "went home to bed", 2)
		if game.clock.night() > .3 or game.clock.hour() >= 18.0:
			game.minds.reflect(self)


# ---------- Their body ----------

## What a need that won't wait puts first in the plan, and when it's been seen to.
const NEED_TODO := {hunger = "get something to eat", cold = "get warm", fear = "get somewhere safe, with some light", tired = "get some sleep"}


func _need_met(need: String) -> bool:
	match need:
		"hunger": return body.hunger < .3
		"cold": return body.cold < .25
		"fear": return body.fear < .25
		"tired": return not body.asleep and body.tired < .3
	return true


## Just the two of them, with Wisp neither in sight nor in earshot.
func alone_together() -> bool:
	if pal.folk:
		return false
	var o: Pal = game.other(pal)
	if o.place_id != pal.place_id or o.inside != "" or pal.inside != "" or o.position.distance_to(pal.position) > 7.0:
		return false
	if game.level.id != pal.place_id:
		return true
	return not _sees(game.kid) and game.minds.voice_from(self, game.kid.global_position + Vector3(0, 1.2, 0), game.level.id) == ""


## A promise that's come due: one to give, not kept by now, is broken; one to wait, still waiting, is kept;
## anything else waits for the night's reflection a while longer, then is let go.
func _promise_due(p: Dictionary) -> void:
	match String(p.kind):
		"give":
			heart.resolve(p, false, mem.life_h)
		"wait":
			heart.resolve(p, true, mem.life_h)
		_:
			if mem.life_h > float(p.due) + Heart.PROMISE_DUE_H:
				p.status = "dropped"
	dirty = true


## Promises to wait: kept if they're still there when you come back, broken if they wander off.
func _watch_promises() -> void:
	for p in heart.promises.filter(func(x): return x.status == "open" and x.kind == "wait"):
		var who: Node3D = _speaker(p.from)
		if who == null:
			continue
		var place: String = game.level.id if p.from == "wisp" else who.place_id
		var spot := Vector2(float(p.spot[0]), float(p.spot[1]))
		var at := Vector2(who.global_position.x, who.global_position.z)
		if place != pal.place_id or at.distance_to(spot) > 10.0:
			heart.resolve(p, false, mem.life_h)
			dirty = true
		elif Vector2(pal.position.x, pal.position.z).distance_to(at) < 4.0 and p.get("away", false):
			heart.resolve(p, true, mem.life_h)
			dirty = true
		elif Vector2(pal.position.x, pal.position.z).distance_to(at) > 8.0:
			p.away = true


# ---------- Learning, and finding out ----------

## A try at something that takes skill: whether it worked. A failure leaves a lesson in memory (once), which
## comes back when they're at it again.
func try_skill(skill: String, difficulty := 0.0) -> bool:
	var ok := skills.attempt(skill, difficulty, mem.life_h)
	if not ok:
		var lesson: String = Skills.LESSONS[skill]
		if not memory.any(func(e): return e.k == "lesson" and e.s == lesson):
			remember("lesson", lesson)
	dirty = true
	return ok


## The skills that matter where they are and in what they're doing.
func skills_now() -> Array:
	var out := []
	var lvl: Level = game.levels.get(pal.place_id)
	if lvl == null:
		return out
	var near := func(t: String) -> bool:
		var T: Dictionary = lvl.thing(t)
		return not T.is_empty() and lvl.thing_pos(t).distance_to(pal.position) < 4.5
	if near.call("woodpile"):
		out.append("chopping")
	if near.call("boat"):
		out.append("building")
	if near.call("door") or task.get("act", "") in ["use", "enter"] and lvl.way(task.get("t", "")).size():
		out.append("mechanisms")
	if task.get("act", "") == "head_to" or plans.current().get("text", "").contains("find") and lvl.outdoors:
		out.append("wayfinding")
	if lvl.is_inside_tree() and lvl.light_at(pal.position) < .3:
		out.append("night_eyes")
	return out


## Someone told them something that what they see can prove wrong: kept to check (a day at most).
func heard_claim(from: String, text: String) -> void:
	var c := Skills.claim(text)
	if c.is_empty():
		return
	# Said to someone else in their hearing (named, and not them): who it was said to
	var to := ""
	if RegEx.create_from_string("(?i)\\b" + pal.pal_name + "\\b").search(text) == null:
		for w in Folk.NAMES:
			if w != pal.id and w != from and RegEx.create_from_string("(?i)\\b" + Folk.NAMES[w] + "\\b").search(text) != null:
				to = w
				break
	c.merge({from = from, text = text.left(160), h = mem.life_h, status = "open", to = to})
	claims.append(c)
	if claims.size() > 10:
		claims.pop_front()


func _speaker(from: String) -> Node3D:
	if from == "wisp":
		return game.kid
	for p in game.people():
		if p.id == from:
			return p
	return null


## What they can see now against what they were told: someone said they didn't have it, and there it is in
## their hand; said they weren't scared, and jumped back in fright.
func _check_claims() -> void:
	if body.asleep or claims.is_empty():
		return
	for c in claims:
		if c.status != "open":
			continue
		if mem.life_h - float(c.h) > 24.0:
			c.status = "dropped"
			continue
		var n := _speaker(c.from)
		if not (n is Pal) or not _sees(n):
			continue
		var who: String = Heart.NAMES[c.from]
		match String(c.kind):
			"not_holding":
				if n.held and (String(n.held.get("what", "")) + " " + String(n.held.t)).to_lower().contains(String(c.subject)):
					caught(c, "saw %s holding %s" % [who, n.held.get("what", "it")])
			"not_scared":
				if n.recoil > 0:
					caught(c, "saw %s jump back in fright" % who)


## They saw someone go through a door they'd said wouldn't open.
func saw_through(from: String) -> void:
	for c in claims:
		if c.status == "open" and c.from == from and c.kind == "door_stuck":
			caught(c, "saw %s go straight through it" % Heart.NAMES[from])


## Caught out: what they were told wasn't so. It costs trust, and they won't forget it.
func caught(c: Dictionary, evidence: String) -> void:
	c.status = "caught"
	var who: String = Heart.NAMES[c.from]
	var to: String = c.get("to", "")
	var told: String = Folk.NAMES.get(to, "someone") if to != "" else ""
	heart.change(c.from, -.2, -.05)
	heart.grudge(c.from, "%s told %s \"%s\", and it wasn't true" % [who, told if told != "" else "you", c.text], .5, mem.life_h)
	heart.feel(-.08, .1)
	remember("caught", "%s told %s \"%s\", but I %s: it wasn't true" % [who, told if told != "" else "me", c.text, evidence], 8)
	# Something to tell the others
	news.witness(c.from, "%s told %s \"%s\", and it wasn't true" % [who, told if told != "" else pal.pal_name, String(c.text).left(80)], -.6, mem.life_h)
	game.minds.after(self, "you've just caught %s out: %s told you \"%s\", but you %s" % [who, who, c.text, evidence])
	print("WISP_CAUGHT %s caught %s: %s" % [pal.id, c.from, c.text])
	dirty = true


## A new morning: one more day lived.
func morning() -> void:
	mem.day += 1
	dirty = true
	# A new day's plan (asleep, when they wake)
	if not body.asleep:
		game.minds.plan_day(self)


## Every frame, wherever they are: the body goes on (hungry, tired, cold...), and they notice when it gets worse.
func live(dt: float) -> void:
	var lvl: Level = game.levels.get(pal.place_id)
	if lvl == null:
		return
	if pal.recoil > 2.0 and not startled:
		startled = true
		body.scared(.5)
	elif pal.recoil <= 0:
		startled = false
	# Time lived: memories fade with it (and it's saved with them); mood drifts; promises come due
	var hours := game.clock.hours(dt)
	mem.pass_time(hours)
	for p in heart.pass_time(hours, mem.life_h, body):
		_promise_due(p)
	_watch_promises()
	skills.pass_time(hours, mem.life_h)
	# Now and then: has what someone told them turned out not to be so?
	claims_at -= dt
	if claims_at <= 0.0:
		claims_at = .3
		_check_claims()
	# Wisp staying with them while they're scared: that counts
	if hours > 0 and body.fear > .4 and not body.asleep and game.level.id == pal.place_id and game.wisp_g.distance_to(pal.position) < 4.0:
		heart.change("wisp", .05 * hours, .04 * hours)
	if mem.life_h - saved_h > .25:
		dirty = true
	body.resting = task.get("phase", "") == "rest"
	var idle: bool = (task.is_empty() or body.resting) and not pal.talk and not pal.plate
	body.step(game.clock.hours(dt), dt, lvl.surroundings(pal), idle)
	var why := body.wakes(game.clock.daylight())
	if why != "":
		wake(why)
	if body.asleep:
		return
	# A need that's got worse is something you notice, whatever you're doing
	for k in ["hunger", "tired", "cold", "fear"]:
		var v: float = body.get(k)
		var band := 0
		for edge in [.3, .55, .8]:
			if v >= edge:
				band += 1
		if band > bands.get(k, 0) and band >= 2:
			game.minds.after(self, "you notice you're %s" % {hunger = "getting hungry", tired = "getting tired", cold = "getting cold", fear = "getting scared"}[k])
			# A need that won't wait goes first in the plan (tiredness only once it's night)
			if k != "tired" or game.clock.night() > .5:
				plans.urgent(k, NEED_TODO[k], mem.life_h)
		bands[k] = band
	plans.needs_met(func(need): return _need_met(need), mem.life_h)
	# Bored of standing about: they notice (once, until it passes)
	if body.bored > .6 and not bored_said:
		bored_said = true
		game.minds.after(self, "you're bored: nothing's happening")
	elif body.bored < .4:
		bored_said = false


## Up off the ground (stopped resting).
func _get_up() -> void:
	pal.lie = false
	body.resting = false
	if task.get("phase", "") == "rest":
		task = {}


## Woken (by their body, or by someone): up, out of bed, and thinking again.
func wake(why: String, by := "") -> void:
	if not body.asleep:
		return
	if why == "rested":
		heart.slept(true)
	elif why in ["cold", "hungry"]:
		heart.slept(false)
	else:
		heart.feel(-.05, .1)
	body.asleep = false
	body.since_woke = 0.0
	pal.closed = false
	pal.lie = false
	if pal.inside != "":
		pal.go_out(task.get("door"))
		game.hearing.make(pal.position, pal.place_id, "a door opening and shutting", 8.0, pal)
	task = {}
	since = Time.get_ticks_msec() / 1000.0
	var what: String = {rested = "woke up feeling rested", hungry = "woke up hungry", cold = "woke up shivering with cold"}.get(why, "woke up")
	if by != "":
		what += (" " if by.begins_with("to ") else ": ") + by
	remember("did", what)
	game.minds.after(self, "You just %s." % what)
	# Up for a new day: today's plan, if there isn't one yet
	if plans.day != mem.day:
		game.minds.plan_day(self)


## A sound reached them (hearing.gd): it goes into memory, and one loud enough to notice makes them think.
## Asleep, only a loud one gets through, and wakes them.
func hear(sound: String, level: float, h := {}) -> void:
	last_heard = {t = Time.get_ticks_msec() / 1000.0, text = sound, angle = h.get("angle", 0.0), from = h.get("from", pal.position), level = level}
	if body.asleep:
		if not body.woken_by(level):
			return
		remember("heard", sound)
		wake("", "to " + sound)
		return
	remember("heard", sound)
	body.perked(.1 * level)
	if level > .12:
		game.minds.after(self, "you hear " + sound)


## Something touched them, or they touched something: they feel it (and it wakes them if they're asleep).
func touch(text: String, think := true) -> void:
	if text.contains("lunged"):
		heart.feel(-.6, .5)
	else:
		heart.feel(-.02, .04)
	if body.asleep:
		remember("felt", text)
		wake("", text)
		return
	remember("felt", text)
	body.perked(.15)
	if think:
		game.minds.after(self, "you felt: " + text)


## Ways they've had a look at (using one again goes through)
var hinted := {}
## When each bump was last felt (who or what), and how long before the same one counts again
var bumps_felt := {}
const BUMP_AGAIN_S := 30.0


## Walked into something or someone (pal.gd).
func _bumped(kind: String, what) -> void:
	# The same bump again and again (sliding along a wall, jostling in a crowd): felt once, not every time
	var key: String = (what as Node3D).name if kind == "person" else String(what)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(bumps_felt.get(key, -1e9)) < BUMP_AGAIN_S and not body.asleep:
		return
	bumps_felt[key] = now
	if kind == "person":
		var n: Node3D = what
		var who: String = ("Wisp" if n == game.kid else n.pal_name) if _knows_who(n) else "someone"
		touch("you bumped into %s" % who)
		if n is Pal:
			var o: Mind = game.minds.of(n)
			var knew := o._knows_who(pal)
			o.touch(("%s bumped into you" % pal.pal_name) if knew else "someone bumped into you, %s" % Hearing.side(Hearing.angle_to(n, pal.position)).replace("ahead of you", "from in front").replace("behind you", "from behind"))
			# Walking smack into each other: something to laugh about (if they both know it was them)
			if who != "someone":
				heart.shared(o.pal.id, "the time you walked right into %s" % o.pal.pal_name, mem.life_h, true)
			if knew:
				o.heart.shared(pal.id, "the time %s walked right into you" % pal.pal_name, o.mem.life_h, true)
	else:
		# Trailing along after someone, brushing past things isn't worth stopping to think about
		touch(String(what), pal.mode != "follow")


## Arrived: do the thing. What happens comes back as they'd feel or hear it; names are theirs.
func _act() -> void:
	var t: String = task.get("t", "")
	var word: String = task.word if task.word != "" else "it"
	pal.gaze = task.get("at")
	if task.get("at") is Vector3:
		pal.face(task.at)
	match task.act:
		"eat":
			_eat(t, word)
		"rest":
			pal.lie = true
			pal.mode = "stay"
			pal.gaze = null
			task = {act = "rest", phase = "rest", word = ""}
			body.resting = true
			since = Time.get_ticks_msec() / 1000.0
			remember("did", "lay down on the ground to rest")
		"sleep":
			_sleep(t)
		"head_to" when task.get("lost", false):
			_done("went the wrong way for a bit and ended up %s, not at %s" % [game.level.place_of(pal.position), task.word], false)
		"go", "head_to":
			if t != "":
				visited[t] = Time.get_ticks_msec() / 1000.0
			var what := "walked over to %s" % (task.word if task.word != "" else "the spot I'd pointed at")
			if t != "" and game.level.can_carry(t) and not pal.held:
				what += "; it's right by me, small enough to pick up"
			elif t != "" and not game.level.way(t).is_empty():
				what += "; " + game.level.way_hint(t).get_slice(". ", game.level.way_hint(t).get_slice_count(". ") - 1)
			_done(what, true)
		"wander":
			if t != "":
				visited[t] = Time.get_ticks_msec() / 1000.0
			_done("wandered about a bit", true, false)
		"pick_up":
			if t == "" or not game.level.can_carry(t):
				# Got there and looked down: something you could pick up right where you pointed
				t = _at_hand(task.get("at", pal.position), String(task.get("word", "")))
				if t != "":
					word = game.level.label_of(t) if game.level.has_method("label_of") else word
			var T: Dictionary = game.level.thing(t)
			if t == "" or T.is_empty() or not game.level.can_carry(t):
				pal._gesture("pick_up")
				_done("reached for %s, but there was nothing there I could lift" % word, false)
				return
			if pal.held:
				var old: Dictionary = pal.let_go()
				game.level.put_down(old, pal.global_position + Vector3(sin(pal.yaw + 1.2), 0, cos(pal.yaw + 1.2)) * .5)
				remember("did", "put down %s to pick up %s" % [old.get("what", "what I held"), word])
			game.level.taken(T)
			T.what = word
			pal.hold(T)
			_done("picked up %s" % word, true)
		"give":
			if not pal.held:
				_done("went to give %s something, but my hands are empty" % task.who_name, false)
				return
			var T: Dictionary = pal.held
			if t == "you":
				if T.t == "ember":
					pal.let_go()
					T.node.queue_free()
					game.take_ember()
					_done("gave %s to Wisp, who put it in the lantern: it shone much brighter" % T.get("what", "it"), true)
				else:
					_done("held %s out to Wisp, but Wisp's hands are full with the lantern" % T.get("what", "it"), false)
				return
			var o: Pal = task.person
			if o.held:
				_done("tried to give %s %s, but %s's hands are full" % [task.who_name, T.get("what", "it"), task.who_name], false)
				return
			pal.let_go()
			o.hold(T)
			# Being given something: they helped; and if they'd promised to, they kept their word
			var om: Mind = game.minds.of(o)
			om.heart.helped(pal.id)
			for p in om.heart.open_from(pal.id, "give"):
				om.heart.resolve(p, true, om.mem.life_h)
			game.minds.of(o).remember("event", "%s gave me %s" % [pal.pal_name, T.get("what", "something")])
			_done("gave %s to %s" % [T.get("what", "it"), task.who_name], true)
			# Was it what they wanted? (a quest done: minds.gd)
			game.minds.gave(self, o, T)
		"enter":
			var way: Dictionary = game.level.way(t) if t != "" else {}
			var home: Dictionary = game.level.shelter(t) if t != "" else {}
			if way.is_empty() and not home.is_empty():
				_knock(t, home)
				return
			if way.is_empty():
				_done("tried to go into %s, but there's no way through there" % word, false)
				return
			_done("went through %s" % word, true, false)
			game.go_through(pal, way.to, way.opts)
		"use":
			if t == "":
				pal._gesture("point")
				_done("touched %s; nothing happened" % word, false)
				return
			if game.level.can_carry(t) and not pal.held:
				# Using something you can carry (a torch, a lantern) starts with taking it
				var C: Dictionary = game.level.thing(t)
				game.level.taken(C)
				C.what = word
				pal.hold(C)
				_done("took %s in my hand" % word, true)
				return
			var way: Dictionary = game.level.way(t)
			if not way.is_empty():
				# Steps and the like: the first time, a look at where they go; after that, using them is going
				if not game.level.through_by_use(t) and not hinted.has(t):
					hinted[t] = true
					_done(game.level.way_hint(t), true)
					return
				if not game.level.through_by_use(t):
					_done("went up %s" % word if game.level.id == "cave" else "went through %s" % word, true, false)
					game.go_through(pal, way.to, way.opts)
					return
				# Pushing a door open: there's a knack to it
				if not try_skill("mechanisms", .15):
					pal._gesture("point")
					_done("pushed it, but it didn't budge; maybe there's a knack to it", false)
					return
				# Using a door is going through it
				_done("%s, and went in" % game.level.way_hint(t).get_slice(". I could", 0), true, false)
				game.go_through(pal, way.to, way.opts)
				return
			task.phase = "busy"
			var stage_was: String = game.stage
			var held_was = pal.held
			var what: String = await game.level.use(pal, t)
			if task.get("act", "") != "use" or task.get("t", "") != t:
				return
			# Nothing changed: it didn't work. Twice is enough to know.
			var key := "use|" + word
			if game.stage == stage_was and pal.held == held_was and (what.contains("won't") or what.contains("nothing") or what.contains("didn't")):
				failed[key] = failed.get(key, 0) + 1
				if failed[key] >= 2:
					what += " (I've tried that %d times now; doing it again won't help)" % failed[key]
			else:
				failed.erase(key)
			_done(what if what != "" else "used %s" % word, true)


## Eat what's in their hands, what they went up to, or at home (the larder).
## Something you could pick up within reach of a spot (what you meant, if anything's named like it).
func _at_hand(at: Vector3, word: String) -> String:
	var best := ""
	var bd := 1.3
	for T in game.level.things:
		if not game.level.can_carry(T.t) or not T.node.is_visible_in_tree() or (pal.held and pal.held == T):
			continue
		var d := Vector2(T.node.global_position.x - at.x, T.node.global_position.z - at.z).length()
		# What they called it counts for a lot
		if word != "" and String(game.level.label_of(T.t) if game.level.has_method("label_of") else T.t).to_lower().contains(word.to_lower().get_slice(" ", word.get_slice_count(" ") - 1)):
			d -= .5
		if d < bd:
			bd = d
			best = T.t
	return best


## At a house's door, going in: your own (in for a moment, nothing to do in there now), or someone else's
## (a knock: whoever lives there hears it, and if they're home, comes to the door).
func _knock(t: String, home: Dictionary) -> void:
	var owners: Array = [home.who] if home.has("who") else ["mo", "bo"]
	# Going in hungry is going in for something to eat (at home, or at a neighbour's who's in)
	if body.hunger > .35:
		task.act = "eat"
		_eat(t, home.what)
		return
	if owners.has(pal.id):
		_done("went into %s for a moment and came back out; nothing to do in there just now" % home.what, true)
		return
	var what: String = home.what if home.has("who") else "the house in the village"
	game.hearing.make(home.door, pal.place_id, "a knock at a door", 10.0, pal)
	var in_: Array = []
	for w in owners:
		var x: Mind = game.minds.by_id(w)
		if x != null and x.pal.place_id == pal.place_id and not x.body.asleep and x.pal.position.distance_to(home.door) < 8.0:
			in_.append(x)
	if in_.is_empty():
		_done("knocked at the door of %s, but nobody answered: nobody's home" % what, false)
		return
	var o: Mind = in_[0]
	_done("knocked at the door of %s; %s's at home" % [what, o.pal.pal_name], true)
	o.remember("event", "%s knocked at my door" % pal.pal_name)
	game.minds.after(o, "%s's knocking at your door" % pal.pal_name)


func _eat(t: String, word: String) -> void:
	var lvl: Level = game.level
	if not body.can_eat():
		_done("thought about eating, but I'm full: I couldn't eat a thing", false)
		return
	if pal.held and (t == "" or t == pal.held.t) and float(pal.held.get("food", 0.0)) > 0:
		var T: Dictionary = pal.let_go()
		pal._gesture("pick_up")
		T.node.queue_free()
		game.hearing.make(pal.position, lvl.id, "crunching", 4.0, pal)
		heart.feel(.1 if body.hunger > .45 else .03)
		body.eat(float(T.food), T.get("what", word))
		_done("ate %s" % T.get("what", "it"), true)
		return
	if t != "" and lvl.edible(t) > 0:
		var T: Dictionary = lvl.thing(t)
		var food := lvl.edible(t)
		lvl.taken(T)
		pal._gesture("pick_up")
		T.node.queue_free()
		game.hearing.make(pal.position, lvl.id, "crunching", 4.0, pal)
		heart.feel(.1 if body.hunger > .45 else .03)
		body.eat(food, word)
		_done("picked up %s and ate it" % word, true)
		return
	var home: Dictionary = lvl.shelter(t) if t != "" else {}
	if not home.is_empty():
		task.phase = "busy"
		pal.go_in(t)
		game.hearing.make(home.door, lvl.id, "a door opening and shutting", 8.0, pal)
		await game.wait(5.0)
		var r: Dictionary = lvl.eat_at(pal, t)
		pal.go_out(home.door)
		game.hearing.make(home.door, lvl.id, "a door opening and shutting", 8.0, pal)
		if task.get("act", "") != "eat":
			return
		if r.get("food", 0.0) > 0:
			heart.feel(.1 if body.hunger > .45 else .03)
			body.eat(r.food, "a meal")
		_done(r.get("said", "went in, but found nothing to eat"), r.get("food", 0.0) > 0)
		return
	if t == "" and task.get("phase", "") == "do" and not task.has("stand"):
		_done("wanted to eat, but there's nothing to eat in my hands", false)
		return
	pal._gesture("point")
	_done("looked for something to eat %s, but there was nothing there I could eat" % ("at " + word if word != "" else "there"), false)


## Go to sleep: in bed indoors, or on the ground where they are; only if their body lets them.
func _sleep(t: String) -> void:
	var why := body.can_sleep()
	if why != "":
		_done("lay down and shut my eyes, but I'm %s: I couldn't sleep, so I got up again" % why, false)
		return
	var lvl: Level = game.level
	var home: Dictionary = lvl.shelter(t) if t != "" else {}
	var what := ""
	if not home.is_empty():
		pal.go_in(t)
		game.hearing.make(home.door, lvl.id, "a door opening and shutting", 8.0, pal)
		what = "went into %s, got into bed and fell asleep" % home.what
	else:
		pal.lie = true
		what = "lay down on the ground and fell asleep"
	body.asleep = true
	body.resting = false
	pal.closed = true
	pal.mode = "stay"
	pal.gaze = null
	task = {act = "sleep", phase = "sleep", t = t, word = "", door = home.get("door")}
	since = Time.get_ticks_msec() / 1000.0
	remember("did", what)
	# Asleep for the night: the day is turned over in their mind (once a night)
	if game.clock.night() > .3 or game.clock.hour() >= 18.0:
		game.minds.reflect(self)
	for o in game.minds.all():
		if o != self and game.minds.earshot(o, pal.position):
			# What the others see of it
			game.minds.saw(o.pal, "%s %s" % [pal.pal_name, "went into %s" % home.what if not home.is_empty() else "lay down on the ground and shut %s eyes" % Folk.HIS.get(pal.id, "their")], pal.position + Vector3(0, .7, 0))


## Finished (or failed): it goes into memory, and soon they think again about what's next.
func _done(what: String, ok: bool, think := true) -> void:
	body.perked(.25 if ok else .1)
	# Getting things done in the dim trains the eyes
	var lvl: Level = game.levels.get(pal.place_id)
	if lvl != null and lvl.is_inside_tree() and lvl.light_at(pal.position) < .3 and task.get("act", "") not in ["", "wait", "wave", "jump"]:
		skills.practice("night_eyes", ok, mem.life_h)
	heart.feel(.03 if ok else -.05)
	# Toward the plan: something real done is progress; something real that didn't work is a try that failed
	var act: String = task.get("act", "")
	if ok and act in PROGRESS:
		plans.progressed(mem.life_h)
	elif not ok and act not in ["wander", "turn", "look", "wave", "jump", "wait", "go"]:
		plans.failed(mem.life_h)
	# The same thing again and again, with nothing changing: they notice
	var sig: String = String(task.get("act", "")) + "|" + String(task.get("word", "")) + "|" + game.stage
	repeats = repeats + 1 if sig == last_sig else 1
	last_sig = sig
	if repeats >= 3:
		what += " (that's %d times in a row now, and nothing changes)" % repeats
	task = {}
	since = Time.get_ticks_msec() / 1000.0
	if pal.mode == "free":
		# They stay where they got to, looking that way; they only tag along again if you go a way off
		pal.mode = "stay"
	remember("did", what)
	if think:
		game.minds.after(self, ("You just %s." if ok else "You just %s.") % what)
