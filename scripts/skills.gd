class_name Skills
extends RefCounted
## What Mo or Bo can do well, and what they're still learning: chopping wood, building (the boat), mechanisms
## (doors and things with a knack to them), finding their way, and seeing in the dark. Each goes from 0 (never
## done it) to 1 (could do it in their sleep). Practice makes it better (failing teaches a little too), and
## left alone for days it slips back toward where it started. A try can fail, more often for a beginner, but
## never more than three times running: the fourth goes (nobody gets stuck forever).
##
## Whether a try works is worked out from who, what and how many tries so far (no dice): the same every run.
## Failing leaves a lesson (lessons), which comes back to them when they're at it again.
## Pure data: tools/skills_test.gd runs it.

const VERSION := 1
const ALL := ["chopping", "building", "mechanisms", "wayfinding", "night_eyes"]
## Where each starts: Bo's handy with tools and mechanisms, Mo has a nose for the way and sharp eyes
const START := {
	mo = {chopping = .2, building = .15, mechanisms = .2, wayfinding = .45, night_eyes = .4},
	bo = {chopping = .45, building = .4, mechanisms = .45, wayfinding = .25, night_eyes = .3},
}
const WORDS := {chopping = "chopping wood", building = "building things", mechanisms = "doors and mechanisms",
	wayfinding = "finding your way", night_eyes = "seeing in the dark"}
## What failing at each teaches (their words, with what it's about, so it comes back to mind there)
const LESSONS := {
	chopping = "chopping wood: line the axe up with the crack in the log, and don't rush the swing",
	building = "building the boat: try each piece for fit before fixing it, or it won't sit right",
	mechanisms = "pushing the door and mechanisms: there's a knack; push slowly and evenly and feel for where it gives",
	wayfinding = "finding my way: pick a landmark first (the hill, the big tree, the house) and keep it in sight",
	night_eyes = "seeing in the dark: stand still a moment and let my eyes get used to it",
}
## Fails in a row before a try is sure to go
const MOST_FAILS := 3
## Days unused before a skill starts to slip, and how much of what's above the start goes each day after
const SLIPS_AFTER_H := 24.0
const SLIPS_PER_DAY := .04

var who := ""
var level := {}
var base := {}
var tries := {}
var fails_in_row := {}
var last_h := {}
var lessons := {}


func _init(who_: String = "") -> void:
	who = who_


static func fresh(who_: String) -> Skills:
	var s := Skills.new(who_)
	var start: Dictionary = START[who_] if START.has(who_) else Folk.SKILLS[who_]
	for k in ALL:
		s.level[k] = float(start[k])
		s.base[k] = float(start[k])
		s.tries[k] = 0
		s.fails_in_row[k] = 0
		s.last_h[k] = 0.0
	return s


## How likely a try is to work, at this level and difficulty.
func chance(skill: String, difficulty := 0.0) -> float:
	return clampf(.3 + .7 * float(level[skill]) - difficulty, .15, .97)


## A try at something: whether it worked. Practice either way; a failure the fourth time running doesn't happen.
func attempt(skill: String, difficulty: float, now_h: float) -> bool:
	var n: int = tries[skill]
	tries[skill] = n + 1
	var roll := Skills.roll("%s|%s|%d" % [who, skill, n])
	var ok := roll < chance(skill, difficulty) or int(fails_in_row[skill]) >= MOST_FAILS
	practice(skill, ok, now_h)
	if ok:
		fails_in_row[skill] = 0
	else:
		fails_in_row[skill] = int(fails_in_row[skill]) + 1
		lessons[skill] = LESSONS[skill]
	return ok


## A number from 0 to 1 for this try, the same every run (a string hash, well mixed: hashes of near-identical
## strings sit close together, which would make tries come in streaks).
static func roll(key: String) -> float:
	var x: int = hash(key) & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff
	x = x ^ (x >> 16)
	return float(x % 10000) / 10000.0


## Doing it gets you better at it (less from a failure, and less the better you are).
func practice(skill: String, ok: bool, now_h: float) -> void:
	var l: float = level[skill]
	level[skill] = minf(1.0, l + (.03 if ok else .015) * (1.0 - l))
	last_h[skill] = now_h


## Days without it: what's above where they started slips back a little.
func pass_time(hours: float, now_h: float) -> void:
	for k in ALL:
		var idle := now_h - float(last_h[k]) - SLIPS_AFTER_H
		if idle <= 0.0:
			continue
		var days := minf(hours, idle) / 24.0
		level[k] = float(base[k]) + (float(level[k]) - float(base[k])) * pow(1.0 - SLIPS_PER_DAY, days)


## How much light they need to make something out (sharper eyes need less).
func dark_need() -> float:
	return lerpf(.16, .04, float(level.night_eyes))


## How good they are at something, in words.
func words(skill: String) -> String:
	var l: float = level[skill]
	var what: String = WORDS[skill]
	if l < .3:
		return "you're new to %s and still learning" % what
	if l < .5:
		return "you're getting the hang of %s" % what
	if l < .75:
		return "you're good at %s" % what
	return "you're really good at %s" % what


## What they've learned from failing, about these (if anything), in their words.
func learned(skills: Array) -> Array:
	return skills.filter(func(k): return lessons.has(k)).map(func(k): return lessons[k])


func to_save() -> Dictionary:
	return {v = VERSION, level = level, base = base, tries = tries, fails_in_row = fails_in_row, last_h = last_h, lessons = lessons}


## From a saved file (files from before skills: where they start).
static func from_save(o, who_: String) -> Skills:
	var s := Skills.fresh(who_)
	if not (o is Dictionary) or not (o.get("level") is Dictionary):
		return s
	for k in ALL:
		s.level[k] = float(o.level.get(k, s.level[k]))
		s.base[k] = float(o.get("base", {}).get(k, s.base[k]))
		s.tries[k] = int(o.get("tries", {}).get(k, 0))
		s.fails_in_row[k] = int(o.get("fails_in_row", {}).get(k, 0))
		s.last_h[k] = float(o.get("last_h", {}).get(k, 0.0))
	s.lessons = o.get("lessons", {})
	return s


# ---------- Claims they can check (catching a lie) ----------

## A claim someone made that what you see could prove wrong: {kind, subject} or {} if it's not one.
## "I don't have the torch" (they're seen holding it), "I'm not scared" (seen jumping back in fright), "the door
## won't open" (seen going through it).
static func claim(text: String) -> Dictionary:
	var t := text.to_lower()
	var m := RegEx.create_from_string("\\bi (?:(?:don't|do not) (?:have|got)|haven't(?: got)?|have not(?: got)?|ain't got) (?:the |a |an |any |your |my )?([a-z]+)").search(t)
	if m == null:
		m = RegEx.create_from_string("\\bi'm not (?:holding|carrying) (?:the |a |an |any )?([a-z]+)").search(t)
	if m != null and m.get_string(1) not in ["know", "think", "want", "like", "care", "see", "mind", "time", "idea"]:
		return {kind = "not_holding", subject = m.get_string(1)}
	if RegEx.create_from_string("\\bi'?m not (?:even |a bit |one bit )?(?:scared|afraid|frightened)|\\bnot scared (?:at all|one bit)").search(t):
		return {kind = "not_scared", subject = ""}
	if RegEx.create_from_string("\\bdoor (?:won't|will not|doesn't|does not|didn't|can't) (?:open|budge|move)|\\bdoor(?:'s| is) (?:locked|stuck)|\\bcan't (?:open|budge) (?:the|that) door").search(t):
		return {kind = "door_stuck", subject = "door"}
	return {}
