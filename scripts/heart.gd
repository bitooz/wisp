class_name Heart
extends RefCounted
## Mo's or Bo's heart: a mood that lasts (how good they feel, and how stirred up) and how they feel about each
## of the others (Wisp, and each other): trust, fondness, grudges that fade, inside jokes from things they went
## through together, and promises made to them. It all changes slowly, through what happens, and reaches the
## model only as words (mood_words(), about()).
##
## Mood is pushed by what happens (a fright, a good meal, something not working), pulled down by a body that's
## hungry, tired, cold or scared, and drifts back to their own way of being (Mo bubbly, Bo even). A night's
## sleep sets it mostly back. Relationships move in small steps that get smaller near the ends, so one thing
## never makes or breaks a friendship.
##
## Time is time lived (game hours, from their memory). Pure data and arithmetic: tools/heart_test.gd runs it.

const VERSION := 1
## How fast mood goes back to how they usually are (per game hour, a share of the way)
const MOOD_SETTLES := .35
## Grudges halve every this many game hours; promises are due within this many
const GRUDGE_HALF_H := 36.0
const PROMISE_DUE_H := 24.0
## Who's who (everyone on the island, and Wisp); each has feelings about all the others (Folk.others)
const NAMES := Folk.NAMES

var who := ""
## Mood: v how good (-1 to 1), a how stirred up (0 to 1)
var v := 0.0
var a := .4
## How they usually are
var base_v := 0.0
var base_a := .4
## Each other: {trust, fond (-1 to 1), grudges: [{why, s, h}], jokes: [{what, n, h}]}
var rel := {}
## Promises made to them: [{id, from, text, kind, h, due, spot, status}]
var promises: Array = []
var next_id := 1
## When they last had a moment alone together without Wisp (game hours lived)
var alone_h := -1e9
## How they take teasing: Mo loves it, Bo puts up with it from someone he likes
var likes_teasing := .5


func _init(who_: String = "") -> void:
	who = who_


## How they are at the start: their personas and what they knew before the game began.
static func fresh(who_: String) -> Heart:
	var h := Heart.new(who_)
	if who_ == "mo":
		h.base_v = .35
		h.base_a = .6
		h.likes_teasing = 1.0
		h.rel = {wisp = _bond(.3, .55), bo = _bond(.6, .65)}
	elif who_ == "bo":
		h.base_v = .1
		h.base_a = .3
		h.likes_teasing = -.4
		h.rel = {wisp = _bond(0.0, .05), mo = _bond(.7, .55)}
	elif Folk.has(who_):
		var t: Array = Folk.TEMPER[who_]
		h.base_v = t[0]
		h.base_a = t[1]
		h.likes_teasing = t[2]
	# The island's other people (and, for them, everyone): as Folk.BONDS has it, or barely known
	var b: Dictionary = Folk.BONDS.get(who_, {})
	for o in Folk.others(who_):
		if not h.rel.has(o):
			var tf: Array = b.get(o, [.3, .2])
			h.rel[o] = _bond(tf[0], tf[1])
	h.v = h.base_v
	h.a = h.base_a
	return h


static func _bond(trust: float, fond: float) -> Dictionary:
	return {trust = trust, fond = fond, grudges = [], jokes = []}


# ---------- Saving ----------

func to_save() -> Dictionary:
	return {v = VERSION, mood = [v, a], base = [base_v, base_a], rel = rel, promises = promises, next_id = next_id,
		alone_h = alone_h, likes_teasing = likes_teasing}


## From a saved file (or nothing: a file from before hearts, which starts them as they were at the beginning).
static func from_save(o, who_: String) -> Heart:
	var h := Heart.fresh(who_)
	if not (o is Dictionary) or not o.has("rel"):
		return h
	h.v = float(o.mood[0])
	h.a = float(o.mood[1])
	h.base_v = float(o.base[0])
	h.base_a = float(o.base[1])
	for k in Folk.others(who_):
		if o.rel.has(k):
			var r: Dictionary = o.rel[k]
			var jokes: Array = r.get("jokes", [])
			for j in jokes:
				j.n = int(j.n)
			h.rel[k] = {trust = float(r.trust), fond = float(r.fond), grudges = r.get("grudges", []), jokes = jokes}
	h.promises = o.get("promises", [])
	for p in h.promises:
		p.id = int(p.id)
	h.next_id = int(o.get("next_id", h.promises.size() + 1))
	h.alone_h = float(o.get("alone_h", -1e9))
	h.likes_teasing = float(o.get("likes_teasing", h.likes_teasing))
	return h


# ---------- Mood ----------

## Something happened that made them feel better or worse (dv) and more or less stirred up (da).
func feel(dv: float, da := 0.0) -> void:
	v = clampf(v + dv, -1.0, 1.0)
	a = clampf(a + da, 0.0, 1.0)


## Time lived: mood drifts back to how they usually are, held down by what the body's going through; grudges
## fade; promises come due. `body`: the Body (or null). `now_h`: hours lived. Returns promises that fell due.
func pass_time(hours: float, now_h: float, body = null) -> Array:
	if hours <= 0.0:
		return []
	var want_v := base_v
	var want_a := base_a
	if body != null:
		want_v -= .6 * maxf(0.0, body.hunger - .4) + .5 * maxf(0.0, body.tired - .5) + .7 * maxf(0.0, body.cold - .3) + .8 * body.fear + .4 * maxf(0.0, body.bored - .4)
		want_a += .6 * body.fear - .3 * maxf(0.0, body.tired - .4) + .2 * maxf(0.0, body.bored - .5)
	var k := 1.0 - pow(1.0 - MOOD_SETTLES, hours)
	v += (clampf(want_v, -1.0, 1.0) - v) * k
	a += (clampf(want_a, 0.0, 1.0) - a) * k
	for o in rel:
		var g: Array = rel[o].grudges
		for x in g:
			x.s = float(x.s) * pow(.5, hours / GRUDGE_HALF_H)
		rel[o].grudges = g.filter(func(x): return x.s > .08)
	var due := []
	for p in promises:
		if p.status == "open" and now_h > float(p.due):
			due.append(p)
	return due


## A night's sleep: mostly back to how they usually are (better if they slept well).
func slept(well: bool) -> void:
	v = lerpf(v, base_v + (.1 if well else -.1), .7)
	a = lerpf(a, base_a, .7)


func mood_words() -> String:
	if v > .5:
		return "in a great mood: bouncy and full of beans" if a > .5 else "in a lovely, easy mood"
	if v > .2:
		return "in a good mood" + (", excited" if a > .65 else "")
	if v > -.2:
		if a > .7:
			return "restless and jumpy"
		if a < .2:
			return "a bit flat"
		return "all right, nothing special"
	if v > -.5:
		return "grumpy" + (" and on edge" if a > .6 else "")
	return "really fed up and miserable" if a < .6 else "upset and cross"


# ---------- How they feel about the others ----------

## Small steps, smaller near the ends: nothing makes or breaks a friendship at once. Going further toward an end
## gets harder the closer it is (never quite there); a strong bond (either way) also resists being undone.
static func _nudge(x: float, d: float) -> float:
	var toward := signf(d) == signf(x)
	return clampf(x + d * ((1.0 - absf(x)) if toward else (1.0 - .5 * absf(x))), -1.0, 1.0)


func change(o: String, trust: float, fond: float) -> void:
	if not rel.has(o):
		return
	rel[o].trust = _nudge(rel[o].trust, trust)
	rel[o].fond = _nudge(rel[o].fond, fond)


func grudge(o: String, why: String, s: float, now_h: float) -> void:
	if not rel.has(o):
		return
	for x in rel[o].grudges:
		if x.why == why:
			x.s = minf(1.0, float(x.s) + s * .5)
			x.h = now_h
			return
	rel[o].grudges.append({why = why, s = s, h = now_h})


## Being nice eases a grudge.
func _ease(o: String, by: float) -> void:
	for x in rel[o].grudges:
		x.s = float(x.s) * (1.0 - by)


## They did something for them (gave them something, helped them).
func helped(o: String) -> void:
	change(o, .08, .07)
	if rel.has(o):
		_ease(o, .3)
	feel(.12, .05)


## Teased by someone: depends who you are, and how much you like them.
func teased(o: String, now_h := 0.0) -> void:
	if not rel.has(o):
		return
	var take := likes_teasing + (.6 if rel[o].fond > .5 else 0.0)
	change(o, 0.0, .04 * take)
	feel(.05 * take, .05)
	if take < 0:
		grudge(o, "%s kept teasing you" % NAMES[o], .3, now_h)


## Something they went through together, that they'll remember: closer, and maybe a joke between them.
func shared(o: String, what: String, now_h: float, funny := false) -> void:
	change(o, .03, .06)
	feel(.08 if funny else .04, .05)
	if funny and rel.has(o):
		for j in rel[o].jokes:
			if j.what == what:
				j.n = int(j.n) + 1
				return
		rel[o].jokes.append({what = what, n = 1, h = now_h})
		if rel[o].jokes.size() > 5:
			rel[o].jokes.pop_front()


## Left behind (they went off without them).
func left_behind(o: String, now_h: float) -> void:
	change(o, -.03, -.03)
	grudge(o, "%s went off without you" % NAMES[o], .3, now_h)
	feel(-.08)


## Gossip about someone (gossip.gd), from someone: it rubs off, as far as they trust whoever told them.
func gossip(o: String, by: String, s: float) -> void:
	if not rel.has(o) or not rel.has(by):
		return
	var w := maxf(0.0, float(rel[by].trust))
	change(o, .12 * s * w, .08 * s * w)


## Someone they trust said something about someone else: it rubs off a little.
func heard_about(o: String, by: String, sentiment: float) -> void:
	if not rel.has(o) or not rel.has(by):
		return
	change(o, 0.0, .05 * sentiment * maxf(0.0, rel[by].trust))


# ---------- What's said ----------

const TEASE := ["slowpoke", "scaredy", "chicken", "silly", "nerd", "goofball", "dummy", "so slow", "haha", "ha ha",
	"bet you can't", "you're so", "beat you", "copycat", "smarty", "know-it-all", "worrywart", "grumpy"]
const WARM := ["great", "nice", "kind", "brave", "funny", "cool", "awesome", "love", "like", "best", "clever", "helped",
	"friend", "trust", "good", "fun", "sweet", "amazing"]
const COLD := ["annoying", "weird", "creepy", "useless", "boring", "mean", "liar", "lied", "don't trust", "not sure about",
	"scary", "rude", "slow", "never helps", "bossy", "strange", "suspicious"]


## Teasing (playful digs)?
static func is_tease(text: String) -> bool:
	var t := text.to_lower()
	return TEASE.any(func(w): return t.contains(w))


## How warm or cold something said is, -1 to 1 (a rough count of warm and cold words).
static func sentiment(text: String) -> float:
	var t := text.to_lower()
	var n := 0
	for w in COLD:
		if t.contains(w):
			n -= 1
			t = t.replace(w, "")
	for w in WARM:
		if RegEx.create_from_string("\\b" + w + "\\b").search(t) != null:
			n += 1
	if RegEx.create_from_string("\\b(not|isn't|don't|never)\\b").search(t) != null and n > 0:
		n = -n
	return clampf(n / 2.0, -1.0, 1.0)


# ---------- Promises ----------

## Was that a promise? "I'll give you the torch", "I'll wait here for you", "I promise ...": its kind, or "".
static func promise_kind(text: String) -> String:
	var t := text.to_lower()
	if RegEx.create_from_string("\\b(i'll|i will|i'm going to|i promise to) (give|bring|hand) you\\b").search(t):
		return "give"
	if RegEx.create_from_string("\\b(i'll|i will|i promise to|i promise i'll) wait\\b").search(t):
		return "wait"
	if RegEx.create_from_string("\\bi promise\\b").search(t):
		return "other"
	return ""


## A promise made to them (from someone, with what they said; spot: where the one who promised was).
func promised(o: String, text: String, now_h: float, spot := Vector3.ZERO) -> Dictionary:
	var kind := promise_kind(text)
	if kind == "" or not rel.has(o):
		return {}
	var p := {id = next_id, from = o, text = text, kind = kind, h = now_h, due = now_h + (2.0 if kind == "wait" else PROMISE_DUE_H),
		spot = [spot.x, spot.z], status = "open"}
	next_id += 1
	promises.append(p)
	feel(.05)
	return p


func open_from(o: String, kind := "") -> Array:
	return promises.filter(func(p): return p.status == "open" and p.from == o and (kind == "" or p.kind == kind))


## A promise kept or broken: trust (and how they feel) follows.
func resolve(p: Dictionary, kept: bool, now_h: float) -> void:
	if p.status != "open":
		return
	p.status = "kept" if kept else "broken"
	var o: String = p.from
	if kept:
		change(o, .14, .05)
		_ease(o, .3)
		feel(.12)
	else:
		change(o, -.22, -.06)
		grudge(o, "%s promised (\"%s\") and didn't" % [NAMES[o], p.text], .6, now_h)
		feel(-.15, .05)


# ---------- In words (what the model gets) ----------

## How they feel about someone, in words; no numbers.
func about(o: String) -> String:
	if not rel.has(o):
		return ""
	var r: Dictionary = rel[o]
	var n: String = NAMES[o]
	var t: float = r.trust
	var f: float = r.fond
	var parts := []
	if f > .6:
		parts.append("you love being around %s" % n)
	elif f > .25:
		parts.append("you like %s" % n)
	elif f > -.15:
		parts.append("you don't feel much either way about %s yet" % n)
	elif f > -.5:
		parts.append("%s gets on your nerves" % n)
	else:
		parts.append("you can't stand %s right now" % n)
	if t > .6:
		parts.append("you trust %s completely" % n)
	elif t > .25:
		parts.append("you mostly trust %s" % n)
	elif t > -.15:
		parts.append("you're not sure you can trust %s yet" % n)
	elif t > -.5:
		parts.append("you don't really trust %s" % n)
	else:
		parts.append("you don't trust %s at all" % n)
	var worst = null
	for g in r.grudges:
		if float(g.s) > .2 and (worst == null or float(g.s) >= float(worst.s)):
			worst = g
	if worst != null:
		parts.append("you're still %s that %s" % ["really sore" if float(worst.s) > .5 else "a bit sore", worst.why])
	if r.jokes.size():
		var best: Dictionary = r.jokes[0]
		for j in r.jokes:
			if int(j.n) >= int(best.n):
				best = j
		parts.append("you and %s still laugh about %s" % [n, best.what])
	for p in open_from(o):
		parts.append("%s promised you \"%s\", and hasn't yet" % [n, p.text])
	return "%s: %s" % [n, "; ".join(parts)]


## Everyone they have feelings about, as lines (those who matter most to them last).
func bonds() -> Array:
	var os := Folk.others(who)
	os.sort_custom(func(x, y): return _weight(x) < _weight(y))
	return os.map(func(o): return about(o))


func _weight(o: String) -> float:
	var r: Dictionary = rel[o]
	return absf(float(r.fond)) + absf(float(r.trust)) * .5 + r.grudges.size() * .3 + (1.0 if o == "wisp" else 0.0)
