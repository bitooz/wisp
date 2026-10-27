class_name Memory
extends RefCounted
## One person's memory, as a stream: everything that happens to them goes in, in order, with how much it
## mattered (importance, 1 to 10). Like a person's, it fades: a memory weakens with the time lived since it was
## last brought to mind (small things fast, big ones slowly), goes hazy (details drop out, and now and then one
## comes back wrong: left for right, who said it), and in the end is forgotten. Calling it to mind (it goes into
## a thought) makes it stronger again. What they knew before the game began (Grandma's stories, their goals) and
## the beliefs they've come to (reflection, each night as they sleep) don't fade.
##
## Time here is time lived: game hours, counted only while the game runs (`life_h`), and days (`day`, one more
## each morning). recall() picks what goes into a thought by how recent, important and relevant to what's on
## their mind each memory is, plus the last few things (what they were just doing).
##
## Pure data and arithmetic (no nodes): tools/memory_test.gd runs it with fixed steps.

const VERSION := 2
## Never more than this many (the weakest go first; seeds and beliefs never)
const CAP := 600
## How long a memory of importance 1 lasts before it's half gone (game hours); more important ones last longer
const HALF_LIFE_H := 4.0
## Below this it's hazy (details go), below the next it's forgotten
const HAZY := .4
const GONE := .1
## What goes into each thought: the last few, and the best of the rest
const RECENT := 8
const RECALL := 28
## Beliefs kept (the least important make room for new ones)
const BELIEFS := 12

var who := ""
var entries: Array = []
var life_h := 0.0
var day := 1
## The last day they reflected on, and the life hour reflection had got up to
var reflected_day := 0
var reflected_h := -1e9
var next_id := 1
## How many memories have been forgotten altogether
var forgotten := 0
var _faded_at := 0.0


func _init(who_: String = "") -> void:
	who = who_


# ---------- Loading, saving, and older files ----------

## From a saved file's contents. Files from before (version 1: just {t, k, s}) are brought up to date with
## nothing lost: every memory kept, in order, given an importance, and placed in the past ("yesterday").
static func from_save(o: Dictionary, who_: String, seeds: Array) -> Memory:
	var m := Memory.new(who_)
	var list: Array = o.get("memory", []) if o.get("memory") is Array else []
	if int(o.get("v", 1)) >= VERSION:
		# JSON brings whole numbers back as floats
		for e in list:
			for k in ["id", "d", "imp", "n"]:
				if e.has(k):
					e[k] = int(e[k])
		m.entries = list
		m.life_h = float(o.get("life_h", 0.0))
		m.day = int(o.get("day", 1))
		m.reflected_day = int(o.get("reflected_day", 0))
		m.reflected_h = float(o.get("reflected_h", -1e9))
		m.next_id = int(o.get("next_id", list.size() + 1))
		m.forgotten = int(o.get("forgotten", 0))
		m._faded_at = m.life_h
		return m
	# Version 1: all of it happened before today. Spread it over the day before, oldest first.
	m.day = 2
	m.life_h = 24.0
	var seed_texts := seeds.map(func(s): return s[1])
	# The seeds were written first, all at once (one time), so they're known even if their words have changed
	var first_t: float = float(list[0].get("t", -1.0)) if list.size() else -1.0
	var n := list.size()
	for i in n:
		var e: Dictionary = list[i]
		var h := 24.0 * float(i) / maxf(1.0, float(n))
		var x := {id = m.next_id, t = float(e.get("t", 0.0)), k = String(e.get("k", "note")), s = String(e.get("s", "")),
			h = h, d = 1, last = h}
		m.next_id += 1
		if seed_texts.has(x.s) or i < seeds.size() and x.t == first_t:
			x.seed = true
		x.imp = 10 if x.get("seed", false) else importance(x.k, x.s)
		m.entries.append(x)
	m._faded_at = m.life_h
	return m


func to_save() -> Dictionary:
	return {v = VERSION, life_h = life_h, day = day, reflected_day = reflected_day, reflected_h = reflected_h,
		next_id = next_id, forgotten = forgotten, memory = entries}


## Fresh: only what they knew before the game began.
static func seeded(who_: String, seeds: Array) -> Memory:
	var m := Memory.new(who_)
	for s in seeds:
		var e := m.add(s[0], s[1], 10)
		e.seed = true
	return m


# ---------- Writing ----------

## How much something matters, from what kind of memory it is and what it's about (no model call: cheap,
## the same every time). 1 is nothing much, 10 is unforgettable.
static func importance(kind: String, text: String) -> int:
	var base: int = {belief = 8, note = 7, lied = 7, secret = 7, lesson = 7, caught = 8, event = 6, told = 4, did = 3, felt = 3, thought = 3, heard = 2, saw = 2, said = 2}.get(kind, 3)
	var t := text.to_lower()
	for w in ["lunged", "scared", "terrified", "roar", "bridge", "ember", "shadow", "grandma", "never", "first",
			"opened", "swung open", "slid open", "grinding", "brazier", "gave me", "freezing", "really hungry",
			"wisp said", "promise", "sorry", "love", "hate", "the next island", "glowing door"]:
		if t.contains(w):
			base += 2
			break
	for w in ["nothing happened", "nothing changes", "walked over to", "wandered", "underfoot", "footsteps"]:
		if t.contains(w):
			base -= 1
			break
	return clampi(base, 1, 10)


## Something new for the stream. The same thing twice in a row is once.
func add(kind: String, text: String, imp := -1) -> Dictionary:
	text = text.strip_edges()
	if text == "":
		return {}
	if entries.size() and entries[-1].k == kind and entries[-1].s == text:
		return entries[-1]
	var e := {id = next_id, t = Time.get_unix_time_from_system(), k = kind, s = text, h = life_h, d = day, last = life_h,
		imp = imp if imp > 0 else importance(kind, text)}
	next_id += 1
	entries.append(e)
	if entries.size() > CAP:
		_drop_weakest(entries.size() - CAP)
	return e


## What they've come to believe, from reflecting on a day: [{text, importance, from: [ids]}].
func add_beliefs(list: Array) -> Array:
	var added := []
	for b in list.slice(0, 3):
		var text := String(b.get("text", "")).strip_edges()
		if text == "" or entries.any(func(e): return e.k == "belief" and e.s.to_lower() == text.to_lower()):
			continue
		var e := add("belief", text, clampi(int(b.get("importance", 8)), 6, 10))
		e.from = b.get("from", [])
		added.append(e)
	var beliefs := entries.filter(func(e): return e.k == "belief")
	if beliefs.size() > BELIEFS:
		beliefs.sort_custom(func(a, b): return a.imp < b.imp or a.imp == b.imp and a.h < b.h)
		for e in beliefs.slice(0, beliefs.size() - BELIEFS):
			entries.erase(e)
	return added


# ---------- Fading ----------

## Lasting: seeds and beliefs.
static func lasting(e: Dictionary) -> bool:
	return e.get("seed", false) or e.k == "belief"


## How much of it is left, 0 to 1: halves every (importance-scaled) while since it was last brought to mind,
## and each time it's been recalled it lasts longer.
func strength(e: Dictionary) -> float:
	if lasting(e):
		return 1.0
	var half := HALF_LIFE_H * pow(float(e.imp), 1.3) * (1.0 + .5 * float(e.get("n", 0)))
	return pow(.5, maxf(0.0, life_h - float(e.last)) / half)


## Time lived. Every game hour or so, memories fade: weak ones go hazy, the weakest are forgotten.
func pass_time(hours: float) -> void:
	life_h += hours
	if life_h - _faded_at >= 1.0:
		_faded_at = life_h
		fade()


func fade() -> void:
	var i := 0
	while i < entries.size():
		var e: Dictionary = entries[i]
		var s := strength(e)
		if s < GONE and not lasting(e):
			entries.remove_at(i)
			forgotten += 1
			continue
		if s < HAZY and not e.get("hazy", false) and not lasting(e):
			var b := blur(e.s, int(e.id), who)
			e.was = e.s
			e.s = b
			e.hazy = true
		i += 1


## A memory going hazy: the details after the gist drop away, and now and then (one in three) one detail comes
## back wrong. Always the same for the same memory (no dice: it's seeded by the memory itself).
static func blur(s: String, seed: int, who_ := "") -> String:
	var out := s
	for cut in [": ", "; ", ", ", " (", " but "]:
		var at := out.find(cut)
		if at > 0 and out.substr(0, at).split(" ", false).size() >= 3:
			out = out.substr(0, at)
			break
	if seed % 3 == 0:
		var swaps := [["left", "right"], ["red", "orange"], ["blue", "green"], ["two", "three"], ["big", "small"],
			["north", "south"], ["east", "west"], ["behind", "in front of"]]
		# Who said it gets muddled with someone else who was there
		var others := {mo = ["Bo said", "Wisp said"], bo = ["Mo said", "Wisp said"]}
		if others.has(who_):
			swaps.push_front(others[who_])
		for pair in swaps:
			for k in 2:
				var a: String = pair[k]
				var b: String = pair[1 - k]
				var re := RegEx.create_from_string("\\b" + a + "\\b")
				if re.search(out) != null:
					return re.sub(out, b)
	return out


func _drop_weakest(n: int) -> void:
	var weak := entries.filter(func(e): return not lasting(e))
	weak.sort_custom(func(a, b): return strength(a) * a.imp < strength(b) * b.imp)
	for e in weak.slice(0, n):
		entries.erase(e)
		forgotten += 1


# ---------- Remembering ----------

const STOP := ["the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "it", "is", "was", "i", "you",
	"me", "my", "your", "we", "our", "us", "he", "she", "him", "her", "his", "they", "them", "that", "this", "with",
	"for", "from", "up", "down", "just", "now", "then", "there", "here", "what", "so", "be", "are", "were", "did",
	"do", "not", "no", "yes", "into", "out", "over", "by", "as", "if", "all", "some", "about", "said", "saw", "can",
	"could", "would", "got", "go", "went", "get", "one", "too", "very", "really", "away", "off", "back", "again"]


## The words that carry meaning, roughly stemmed.
static func words(text: String) -> Dictionary:
	var out := {}
	for w in RegEx.create_from_string("[a-z]+").search_all(text.to_lower()):
		var s: String = w.get_string()
		if s.length() < 3 or STOP.has(s):
			continue
		for suf in ["ing", "ed", "es", "s"]:
			if s.length() > 4 and s.ends_with(suf):
				s = s.substr(0, s.length() - suf.length())
				break
		out[s] = true
	return out


## How much a memory has to do with what's on their mind (0 to 1): words in common.
static func relevance(query: Dictionary, text: String) -> float:
	if query.is_empty():
		return 0.0
	var w := words(text)
	if w.is_empty():
		return 0.0
	var common := 0
	for k in w:
		if query.has(k):
			common += 1
	return float(common) / sqrt(float(query.size()) * float(w.size()))


## How recent (0 to 1): fades by a tenth every game hour.
func recency(e: Dictionary) -> float:
	return pow(.9, maxf(0.0, life_h - float(e.h)))


## What comes to mind for a thought, with `on_mind` (what they see, hear, plan and feel now): the last few
## things, then the rest by recency + importance + relevance. Those recalled are strengthened. In order.
func recall(on_mind: String, recent := RECENT, total := RECALL) -> Array:
	var q := words(on_mind)
	var picked := {}
	var n := entries.size()
	for i in range(maxi(0, n - recent), n):
		if entries[i].k != "said":
			picked[i] = true
	var scored := []
	for i in n:
		var e: Dictionary = entries[i]
		if picked.has(i) or e.k == "said":
			continue
		# Recency counts for less than what mattered and what's to do with now (lots of little recent things
		# shouldn't crowd out an old one that matters)
		var score := .5 * recency(e) + float(e.imp) / 10.0 + 2.0 * relevance(q, e.s) + (.3 if e.get("seed", false) else 0.0)
		scored.append([score, i])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	for x in scored.slice(0, maxi(0, total - picked.size())):
		picked[x[1]] = true
	var ids := picked.keys()
	ids.sort()
	var out := []
	for i in ids:
		var e: Dictionary = entries[i]
		e.last = life_h
		e.n = int(e.get("n", 0)) + 1
		out.append(e)
	return out


## When it was, as they'd say it (from time lived, not the clock on the wall).
func when(e: Dictionary) -> String:
	var ago := life_h - float(e.h)
	var days := day - int(e.get("d", day))
	if days <= 0:
		if ago < .25:
			return "just now"
		if ago < 2.0:
			return "a little while ago"
		return "earlier today"
	if days == 1:
		return "yesterday"
	return "%d days ago" % days


## Memories as lines for the model: when, and what, in their own words; hazy ones say so.
func lines(list: Array) -> Array:
	var out := []
	for e in list:
		var s: String = e.s
		match String(e.k):
			"saw": s = "saw " + s
			"note": s = "(a thought) " + s
			"did": s = "I " + s
			"heard": s = "heard " + s
			"felt": s = "felt: " + s
			"belief": s = "(something I've come to believe) " + s
			"thought": s = "(thought to myself) " + s
			"lied": s = "I " + s
			"secret": s = "(a secret I'm keeping) " + s
			"lesson": s = "(learned the hard way) " + s
		if e.get("hazy", false):
			s += " (I don't remember it clearly)"
		out.append("[%s] %s" % [when(e), s])
	return out


# ---------- Reflecting ----------

## What there is to reflect on: everything since they last did (but what they said), the most important first
## if there's a lot, in order. [{id, line}]
func for_reflection(most := 40) -> Array:
	var list := entries.filter(func(e): return float(e.h) > reflected_h and e.k != "said" and e.k != "belief" and not e.get("seed", false))
	if list.size() > most:
		var by := list.duplicate()
		by.sort_custom(func(a, b): return a.imp > b.imp)
		var keep := by.slice(0, most)
		list = list.filter(func(e): return keep.has(e))
	return list.map(func(e): return {id = e.id, line = lines([e])[0]})


func beliefs() -> Array:
	return entries.filter(func(e): return e.k == "belief").map(func(e): return e.s)
