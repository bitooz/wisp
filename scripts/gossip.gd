class_name Gossip
extends RefCounted
## What someone knows that's worth passing on: things they saw happen (Mo found Nell's float; Bo told Mo
## something that wasn't true), things they heard said, and what people want. Each story keeps who it's about,
## how it feels (good or bad for them), and how it got here: who saw it first and everyone it went through
## ("chain"), so a listener knows who told them and where they had it from.
##
## Passing it on (chat()): when two people are together with time to talk, one tells the other something they
## haven't heard (not about the listener themselves, not back to whoever it came from). It changes a little in
## the telling (retell(): a word made bigger, a detail drifting, the same every time for the same telling), and
## it shapes the listener: how they feel about whoever it's about (as far as they trust the teller), and their
## plans (someone's want becomes something to help with, a quest; news that it's been done takes it off).
##
## Pure data: tools/folk_test.gd runs it. The game passes stories on live (minds.gd) and while it's closed
## (life.gd, at the campfire of an evening); with the model, a thought gets these as news it could pass on and
## says it its own way ("tell").

const VERSION := 1
## At most this many stories each (the oldest, least juicy go first; wants stay)
const MOST := 24
## Stories older than this (hours lived) aren't worth telling any more
const STALE_H := 96.0
## How a story grows in the telling: [this, becomes this]
const GROW := [["a little", "a lot"], ["a bit", "really"], ["fell in", "fell right in"], ["lost", "gone and lost"],
	["somewhere", "somewhere or other"], ["cross", "furious"], ["scared", "terrified"], ["old", "ancient"],
	["wasn't true", "was a big fat fib"], ["went off", "stormed off"], ["walked", "marched"], ["laughed", "roared with laughter"],
	["a shell", "a great big shell"], ["can't find", "has looked high and low for"], ["a big", "an enormous"],
	["found", "went and found"], ["teased", "made fun of"], ["two", "three"], ["this morning", "yesterday"],
	["north-east shore", "north shore"], ["gave it back", "handed it straight back"], ["kind", "ever so kind"]]
## How each is spoken of (for "Nell told me she ...")
const SHE := {mo = "she", bo = "he", nell = "she", tam = "she", odo = "he", wisp = "Wisp"}

var who := ""
## [{id, about, kind: news|want|done, text, s, from, chain: [first, ..., me], h, told: [who], quest}]
var items: Array = []


func _init(who_ := "") -> void:
	who = who_


## The same event seen by two people is the same story (and the same want, however it's put).
static func id_of(kind: String, text: String, quest := "") -> String:
	return "%s:%s" % [kind, quest if quest != "" else text.md5_text().left(10)]


func knows(id: String) -> bool:
	return items.any(func(x): return x.id == id)


func find(id: String) -> Dictionary:
	for x in items:
		if x.id == id:
			return x
	return {}


## Something they saw or found out themselves (or want themselves): a story to tell. `about`: who it's about
## ("" for nobody in particular); s: how it reflects on them (-1 to 1); quest: whose want it is (for want/done).
func witness(about: String, text: String, s: float, now_h: float, kind := "news", quest := "") -> Dictionary:
	var id := id_of(kind, text, quest)
	var had := find(id)
	if not had.is_empty():
		return had
	var x := {id = id, about = about, kind = kind, text = text, s = clampf(s, -1.0, 1.0), from = "", chain = [who],
		h = now_h, told = [], quest = quest}
	_add(x)
	return x


func _add(x: Dictionary) -> void:
	# Someone's want that's been done: the want's old news
	if x.kind == "done":
		var w := find(id_of("want", "", x.quest))
		if not w.is_empty():
			w.stale = true
	items.append(x)
	while items.size() > MOST:
		var worst := -1
		var low := 1e9
		for i in items.size():
			var y: Dictionary = items[i]
			var v: float = absf(float(y.s)) + float(y.h) / 24.0 + (5.0 if y.kind == "want" and not y.get("stale", false) else 0.0)
			if v < low:
				low = v
				worst = i
		items.remove_at(worst)


## The best thing to tell `to` now: something they haven't had from us or passed to us, not about them, still
## fresh; someone's want, or what's been done about it, first, then the juiciest and newest. {} if nothing.
func pick(to: String, now_h: float) -> Dictionary:
	var best := {}
	var top := -1e9
	for x in items:
		if x.told.has(to) or x.chain.has(to) or x.about == to or x.get("stale", false) or now_h - float(x.h) > STALE_H:
			continue
		# Someone's want is theirs to tell, or anyone's who'd help: never back to the one who wants it
		if x.kind in ["want", "done"] and x.quest == to:
			continue
		var v: float = (2.0 if x.kind in ["want", "done"] else 0.0) + absf(float(x.s)) - (now_h - float(x.h)) / 48.0
		if v > top:
			top = v
			best = x
	return best


## Pass a story on to someone (their Gossip): it may change a little; they know who told them and where it came
## from. Returns their copy, or {} if they'd heard it already.
static func tell(x: Dictionary, teller: String, listener: Gossip, now_h: float) -> Dictionary:
	if not x.told.has(listener.who):
		x.told.append(listener.who)
	if listener.knows(x.id):
		return {}
	var text := retell(x.text, "%s|%s|%s" % [x.id, teller, listener.who])
	var copy := {id = x.id, about = x.about, kind = x.kind, text = text,
		s = clampf(float(x.s) * (1.15 if text != x.text else 1.0), -1.0, 1.0), from = teller,
		chain = x.chain + [listener.who], h = now_h, told = [teller], quest = x.quest}
	listener._add(copy)
	return copy


## A story changes a little in the telling: one word made bigger, or a detail drifting; with nothing to make
## bigger, it's hedged ("apparently"). Now and then it's passed on just as it was. The same every time for the
## same telling.
static func retell(text: String, key: String) -> String:
	var r := Skills.roll(key)
	if r > .88:
		return text
	var start := int(r * 1000.0) % GROW.size()
	for i in GROW.size():
		var pair: Array = GROW[(start + i) % GROW.size()]
		if text.contains(pair[1]):
			continue
		var re := RegEx.create_from_string("\\b" + pair[0] + "\\b")
		if re.search(text) != null:
			return re.sub(text, pair[1])
	if not text.begins_with("apparently"):
		var named: bool = Folk.NAMES.values().has(text.get_slice(" ", 0))
		return "apparently " + (text if named else text.left(1).to_lower() + text.substr(1))
	return text


## Two people together with time to talk: one passes something on to the other (a: who goes first if both have
## something). a and b: anything with who, news, heart, plans and mem (a Mind, or the catch-up's dicts).
## Returns {from, to, story: the listener's copy}, or {} if nothing was passed on.
static func chat(a, b, now_h: float) -> Dictionary:
	var sa: Dictionary = a.news.pick(b.who, now_h)
	var sb: Dictionary = b.news.pick(a.who, now_h)
	if sa.is_empty() and sb.is_empty():
		return {}
	var teller = a if not sa.is_empty() else b
	var listener = b if teller == a else a
	var x: Dictionary = sa if teller == a else sb
	var copy := tell(x, teller.who, listener.news, now_h)
	if copy.is_empty():
		return {}
	take_in(listener, copy, now_h)
	teller.mem.add("did", "told %s: %s" % [Folk.NAMES[listener.who], x.text], 3)
	return {from = teller.who, to = listener.who, story = copy}


## What hearing a story does to someone: it goes in their memory (with who told them, and where they had it from),
## it colours how they feel about whoever it's about, and someone's want becomes something to help with (or
## stops being one, when they hear it's done).
static func take_in(m, x: Dictionary, now_h: float) -> void:
	var teller: String = x.from
	m.mem.add("told", "%s told me%s: %s" % [Folk.NAMES[teller], _source(x), _as_said(x.text, teller)], 5 if x.kind in ["want", "done"] or absf(float(x.s)) >= .5 else 4)
	if x.about != "" and x.about != m.who:
		m.heart.gossip(x.about, teller, float(x.s))
	var w: Dictionary = Folk.WANTS.get(x.quest, {})
	if w.is_empty() or x.quest == m.who:
		return
	if x.kind == "want" and m.heart.rel.has(x.quest) and float(m.heart.rel[x.quest].fond) > .1 and not m.news.knows(id_of("done", "", x.quest)):
		m.plans.help(w.todo, "%s wants it" % Folk.NAMES[x.quest], now_h)
	elif x.kind == "done":
		m.plans.not_needed(w.todo, now_h)


## Where they had it from, as a listener would say it: "" (the teller saw it), or " (she had it from Odo)".
static func _source(x: Dictionary) -> String:
	var c: Array = x.chain
	if c.size() < 3:
		return ""
	var before: String = c[c.size() - 3]
	return " (%s had it from %s)" % [SHE.get(c[c.size() - 2], "they"), Folk.NAMES.get(before, before)]


## "Nell has lost her float", told by Nell herself: "she has lost her float".
static func _as_said(text: String, teller: String) -> String:
	var n: String = Folk.NAMES.get(teller, "")
	if n != "" and text.begins_with(n + " "):
		return SHE.get(teller, "they") + text.substr(n.length())
	return text


## Whether what was said carries the story (a thought's "tell" is only a telling if the words are in it): two of
## its words, or the name of whoever it's about and one more. Small words don't count.
static func carried(said: String, x: Dictionary) -> bool:
	var mine := _content(String(x.text))
	var got := _content(said)
	var common := got.filter(func(w): return mine.has(w)).size()
	var about: String = Folk.NAMES.get(x.get("about", ""), "").to_lower()
	var quest: String = Folk.NAMES.get(x.get("quest", ""), "").to_lower()
	var named := about != "" and said.to_lower().contains(about) or quest != "" and said.to_lower().contains(quest)
	return common >= 2 or named and common >= 1


static func _content(text: String) -> Array:
	var out := []
	for w in text.to_lower().replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").replace("\"", " ").replace(";", " ").split(" ", false):
		var t := w.trim_suffix("'s").trim_suffix("s")
		if t.length() >= 4 and not t in ["that", "with", "this", "from", "have", "there", "about", "just", "somewhere", "they", "your", "what", "it'", "been", "wasn't", "told", "said", "apparently"] and not out.has(t):
			out.append(t)
	return out


## The wants of others they've heard about and would help with (still to be done, as far as they know).
func wants_to_help(heart) -> Array:
	var out := []
	for x in items:
		if x.kind == "want" and not x.get("stale", false) and x.quest != who and heart.rel.has(x.quest) and float(heart.rel[x.quest].fond) > .1:
			out.append(Folk.WANTS[x.quest].todo)
	return out


## What they could pass on, in words, for their thoughts (the model): numbered, newest last.
func lines(now_h: float) -> Array:
	var out := []
	for x in items:
		if x.get("stale", false) or now_h - float(x.h) > STALE_H:
			continue
		var how := "you saw it yourself" if x.from == "" else ("%s told you%s" % [Folk.NAMES[x.from], _source(x)])
		if x.kind == "want" and x.quest == who:
			how = "it's what you want"
		out.append("%s (%s)" % [x.text, how])
	return out.slice(-8)


## The story they mean by the n-th of lines() (1 = first), for "tell" in a thought's reply.
func nth(n: int, now_h: float) -> Dictionary:
	var live := items.filter(func(x): return not x.get("stale", false) and now_h - float(x.h) <= STALE_H).slice(-8)
	return live[n - 1] if n >= 1 and n <= live.size() else {}


func to_save() -> Dictionary:
	return {v = VERSION, items = items}


static func from_save(o, who_: String) -> Gossip:
	var g := Gossip.new(who_)
	if o is Dictionary and o.get("items") is Array:
		g.items = o.items
	return g
