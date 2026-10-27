class_name Plans
extends RefCounted
## Mo's or Bo's plans, at three levels: what they mean to do today (a short list, made each morning from their
## goals, needs, beliefs and feelings), what they're on now (one of those), and the next step (their own words,
## each thought). The list is kept across thoughts and only changes when something does: an activity done or
## given up, three tries that didn't work, a need that won't wait (they deal with it, then go back to what
## they were doing), news, or getting nowhere for too long (dawdling). Then a rethink is due, and the next
## thought rewrites the rest of the day.
##
## Pure data (time is hours lived, from their memory): tools/plan_test.gd runs it with fixed steps.

const VERSION := 1
## Tries at the same activity before it's time to rethink it
const TRIES := 3
## Getting nowhere: this many thoughts, or this many game hours, without anything done toward what they're on
const DAWDLE_THOUGHTS := 12
const DAWDLE_H := 2.0
## At most this many things to do in a day
const MOST := 5

## Which day (Memory.day) the list is for; -1 for none yet
var day := -1
## [{text, why, status: todo|doing|done|dropped, tries, need?}] in order
var items: Array = []
## The next step, in their words
var step := ""
## Who made today's list: "model", "fallback" (the game's, when there's no model), "standin" (tests)
var made_by := ""
## Why a rethink is due ("" if not)
var replan := ""
## Hours lived when they last got somewhere with what they're on; thoughts since
var progress_h := 0.0
var thoughts_since := 0
## What changed in the plan today, for the night's reflection: ["h|what"]
var log: Array = []


# ---------- Making and keeping a plan ----------

## Today's list: [{text, why}] (or strings).
func make(for_day: int, list: Array, by: String, now_h: float) -> void:
	day = for_day
	items = []
	for x in list.slice(0, MOST):
		var text := String(x.get("text", "")) if x is Dictionary else String(x)
		text = text.strip_edges().left(120)
		if text != "":
			items.append({text = text, why = String(x.get("why", "")).left(120) if x is Dictionary else "", status = "todo", tries = 0})
	made_by = by
	replan = ""
	log = ["%.1f|planned the day: %s" % [now_h, "; ".join(items.map(func(i): return i.text))]]
	progressed(now_h)
	current()


## What they're on now (the first thing not done; it becomes "doing"), or {}.
func current() -> Dictionary:
	for i in items:
		if i.status == "doing":
			return i
	for i in items:
		if i.status == "todo":
			i.status = "doing"
			return i
	return {}


## They finished what they were on ("done"), or gave it up ("dropped"); on to the next.
func finish(now_h: float, how := "done") -> void:
	var c := current()
	if c.is_empty():
		return
	c.status = how
	log.append("%.1f|%s: %s" % [now_h, how, c.text])
	step = ""
	if replan.begins_with("three tries") or replan.begins_with("you've been at"):
		replan = ""
	progressed(now_h)
	current()


## Something toward it went well.
func progressed(now_h: float) -> void:
	progress_h = now_h
	thoughts_since = 0


## Something toward it didn't work. The third time, it's time to think again.
func failed(now_h: float) -> void:
	var c := current()
	if c.is_empty():
		return
	c.tries = int(c.tries) + 1
	if int(c.tries) >= TRIES and replan == "":
		replan = "three tries at \"%s\" and it isn't working" % c.text
		log.append("%.1f|stuck: %s" % [now_h, c.text])


## A thought: if they've been getting nowhere for a while, they notice.
func thought(now_h: float) -> void:
	thoughts_since += 1
	var c := current()
	if c.is_empty() or replan != "" or c.get("need", "") != "":
		return
	if thoughts_since >= DAWDLE_THOUGHTS or now_h - progress_h >= DAWDLE_H:
		replan = "you've been at \"%s\" a while and got nowhere" % c.text
		log.append("%.1f|dawdling: %s" % [now_h, c.text])


## Something important happened: worth rethinking the rest of the day.
func news(what: String, now_h: float) -> void:
	if replan == "":
		replan = "something's changed: %s" % what.left(100)
		log.append("%.1f|news: %s" % [now_h, what.left(100)])


## Someone wants something they could help with (gossip.gd): it goes in the plan, after what they're on (once;
## if the day's full, in place of the last thing for later).
func help(text: String, why: String, now_h: float) -> void:
	if items.any(func(i): return i.text == text):
		return
	var x := {text = text, why = why, status = "todo", tries = 0, quest = true}
	var later := items.filter(func(i): return i.status == "todo" and i.get("need", "") == "" and not i.get("quest", false))
	if items.filter(func(i): return i.status in ["todo", "doing"]).size() >= MOST and not later.is_empty():
		items.erase(later.back())
	var at := 0
	for i in items.size():
		if items[i].status in ["done", "dropped", "doing"]:
			at = i + 1
	items.insert(at, x)
	log.append("%.1f|to help: %s" % [now_h, text])
	current()


## Someone else has done it: off the list.
func not_needed(text: String, now_h: float) -> void:
	for i in items:
		if i.text == text and i.status in ["todo", "doing"]:
			i.status = "dropped"
			log.append("%.1f|done by someone else: %s" % [now_h, text])
	current()


## They did it themselves.
func did(text: String, now_h: float) -> void:
	for i in items:
		if i.text == text and i.status in ["todo", "doing"]:
			i.status = "done"
			log.append("%.1f|done: %s" % [now_h, text])
			progressed(now_h)
	current()


## A need that won't wait: dealt with first, then back to what they were on.
func urgent(need: String, text: String, now_h: float) -> void:
	for i in items:
		if i.get("need", "") == need and i.status in ["todo", "doing"]:
			return
	for i in items:
		if i.status == "doing":
			i.status = "todo"
	items.push_front({text = text, why = "", status = "doing", tries = 0, need = need})
	log.append("%.1f|first: %s" % [now_h, text])
	progressed(now_h)


## Needs that have been seen to: those items are done.
func needs_met(met: Callable, now_h: float) -> void:
	var c := current()
	if not c.is_empty() and c.get("need", "") != "" and met.call(c.need):
		c.status = "done"
		log.append("%.1f|done: %s" % [now_h, c.text])
		progressed(now_h)
		current()


## The rest of the day, thought out again: what's done stays done, the rest is the new list.
func rethink(list: Array, now_h: float) -> void:
	var kept := items.filter(func(i): return i.status in ["done", "dropped"])
	var fresh := []
	for x in list.slice(0, MOST):
		var text := String(x.get("text", "")) if x is Dictionary else String(x)
		text = text.strip_edges().left(120)
		if text != "":
			fresh.append({text = text, why = "", status = "todo", tries = 0})
	if fresh.is_empty():
		return
	items = kept + fresh
	log.append("%.1f|rethought: %s" % [now_h, "; ".join(fresh.map(func(i): return i.text))])
	replan = ""
	step = ""
	progressed(now_h)
	current()


# ---------- In words ----------

## The day's plan as the model gets it: what's done, what they're on, what's for later.
func lines() -> Array:
	return items.map(func(i): return "%s %s" % [{todo = "(later)", doing = "(now)", done = "(done)", dropped = "(gave up)"}[i.status], i.text])


## How the day went, for the night's reflection.
func summary() -> String:
	if items.is_empty():
		return ""
	var done := items.filter(func(i): return i.status == "done").map(func(i): return i.text)
	var not_done := items.filter(func(i): return i.status in ["todo", "doing"]).map(func(i): return i.text)
	var gave_up := items.filter(func(i): return i.status == "dropped").map(func(i): return i.text)
	var out := []
	if done.size():
		out.append("did: " + "; ".join(done))
	if gave_up.size():
		out.append("gave up on: " + "; ".join(gave_up))
	if not_done.size():
		out.append("didn't get to: " + "; ".join(not_done))
	return ". ".join(out)


## What's left over from a day (to carry into the next morning's plan).
func unfinished() -> Array:
	return items.filter(func(i): return i.status in ["todo", "doing"] and i.get("need", "") == "").map(func(i): return i.text)


# ---------- When there's no model ----------

## A day's plan without the model (offline, or the morning call failed): what they want most, what their body
## needs, what's left from yesterday, and being home by dark. The same every time for the same state.
static func fallback(who: String, body, heart, leftover: Array, hour: float, helping: Array = []) -> Array:
	var out := []
	if body != null and body.hunger > .45:
		out.append({text = "get something to eat", why = "I'm hungry"})
	var goal: String
	if who == "mo":
		goal = "find out what's inside the glowing door on the hill"
	elif who == "bo":
		goal = "find a way across to the next island"
	else:
		goal = Folk.WANTS[who].goal if Folk.WANTS.has(who) else "get things back to rights"
	for t in leftover:
		if out.size() < 3 and t != goal and t != "get something to eat" and t != "be home and in bed by dark":
			out.append({text = t, why = "didn't get to it yesterday"})
	# Someone they're fond of wants something they could help with (they heard about it)
	for t in helping:
		if out.size() < 3 and not out.any(func(x): return x.text == t):
			out.append({text = t, why = "they'd be so pleased"})
	var chore: String = Life.chore_of(who)
	if hour < 11.0:
		out.append({text = chore, why = "it's my job"})
	out.append({text = goal, why = "it's what I want most"})
	if who in ["mo", "bo"]:
		var other := "bo" if who == "mo" else "mo"
		if heart != null and heart.rel.has(other) and heart.rel[other].fond > .5:
			out.append({text = "do it with %s" % ("Bo" if who == "mo" else "Mo"), why = "it's more fun together"})
	if hour < 16.0:
		out.append({text = Life.hobby_of(who), why = "I love it"})
	out.append({text = "be home and in bed by dark", why = ""})
	return out.slice(0, MOST)


# ---------- Saving ----------

func to_save() -> Dictionary:
	return {v = VERSION, day = day, items = items, step = step, made_by = made_by, replan = replan, progress_h = progress_h,
		thoughts_since = thoughts_since, log = log}


## From a saved file. Files from before (just {plan: "..."}): that was their next step; the day's plan is made
## when the game starts.
static func from_save(o, old_step := "") -> Plans:
	var p := Plans.new()
	if not (o is Dictionary) or not o.has("items"):
		p.step = old_step
		return p
	p.day = int(o.day)
	p.items = o.items
	for i in p.items:
		i.tries = int(i.get("tries", 0))
	p.step = String(o.get("step", ""))
	p.made_by = String(o.get("made_by", ""))
	p.replan = String(o.get("replan", ""))
	p.progress_h = float(o.get("progress_h", 0.0))
	p.thoughts_since = int(o.get("thoughts_since", 0))
	p.log = o.get("log", [])
	return p
