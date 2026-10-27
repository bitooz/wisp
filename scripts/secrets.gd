class_name Secrets
extends RefCounted
## What Mo or Bo keeps to themselves: secrets (and who they've told), and things they said that weren't true
## (lies, and bluffs: "I'm not scared"), with who heard them and what's really so. It's theirs alone: it goes to
## their own thoughts (so what they say later stays consistent) and their own memory, never to anyone else.
## Whoever was listening only ever got the words.
##
## Pure data: tools/secret_test.gd runs it.

const VERSION := 1
## How many it keeps in mind at once (the oldest settle into memory only)
const MOST := 8
## How much of a secret's words a line has to share to give it away
const GIVES_AWAY := .5

## [{id, kind: secret|lie|bluff, text (the secret, or what's really so), said (for lies: the words), to: [who
## heard the lie / who's been told the secret], h}]
var items: Array = []
var next_id := 1


## A secret to keep (to themselves, so far). The same secret twice is once.
func keep(text: String, now_h: float) -> Dictionary:
	text = text.strip_edges().left(140)
	if text == "":
		return {}
	for s in items:
		if s.kind == "secret" and Memory.relevance(Memory.words(s.text), text) > .7:
			return s
	var s := {id = next_id, kind = "secret", text = text, said = "", to = [], h = now_h}
	next_id += 1
	_add(s)
	return s


## Something said that wasn't so ("bluff" if it was putting on a front), to whoever heard it.
func lied(said: String, truth: String, to: Array, now_h: float, kind := "lie") -> Dictionary:
	if said.strip_edges() == "" or to.is_empty():
		return {}
	var s := {id = next_id, kind = kind if kind in ["lie", "bluff"] else "lie", text = truth.strip_edges().left(140), said = said.strip_edges().left(200),
		to = to.duplicate(), h = now_h}
	next_id += 1
	_add(s)
	return s


func _add(s: Dictionary) -> void:
	items.append(s)
	if items.size() > MOST:
		items = items.slice(items.size() - MOST)


## They said something to these people: any secret it gives away is now known to them. Returns those given away.
func spoke(said: String, to: Array) -> Array:
	var out := []
	var w := Memory.words(said)
	for s in items:
		if s.kind != "secret" or to.is_empty():
			continue
		var mine := Memory.words(s.text)
		if mine.is_empty():
			continue
		var common := 0
		for k in mine:
			if w.has(k):
				common += 1
		if float(common) / mine.size() >= GIVES_AWAY:
			var new_ones := to.filter(func(x): return not s.to.has(x))
			if not new_ones.is_empty():
				s.to.append_array(new_ones)
				out.append(s)
	return out


const NAMES := Folk.NAMES


static func _who(list: Array) -> String:
	var n := list.map(func(x): return NAMES.get(x, x))
	if n.is_empty():
		return "nobody"
	if n.size() == 1:
		return n[0]
	return ", ".join(n.slice(0, n.size() - 1)) + " and " + n.back()


## What they're keeping to themselves, in words, for their own thoughts only.
func lines() -> Array:
	var out := []
	for s in items:
		match String(s.kind):
			"secret":
				out.append("a secret: %s (%s)" % [s.text, "you haven't told anyone" if s.to.is_empty() else "only %s %s" % [_who(s.to), "knows" if s.to.size() == 1 else "know"]])
			"lie":
				out.append("you told %s \"%s\", and it isn't true%s" % [_who(s.to), s.said, (": " + s.text) if s.text != "" else ""])
			"bluff":
				out.append("you told %s \"%s\", putting on a front%s" % [_who(s.to), s.said, (": really, " + s.text) if s.text != "" else ""])
	return out


func to_save() -> Dictionary:
	return {v = VERSION, items = items, next_id = next_id}


## From a saved file (nothing there, for files from before: no secrets yet).
static func from_save(o) -> Secrets:
	var s := Secrets.new()
	if o is Dictionary and o.get("items") is Array:
		s.items = o.items
		for x in s.items:
			x.id = int(x.id)
		s.next_id = int(o.get("next_id", s.items.size() + 1))
	return s
