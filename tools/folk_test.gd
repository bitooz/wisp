extends SceneTree
## The island's other people, and gossip, on their own (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/folk_test.gd
## Who Nell, Tam and Odo are (homes, days, feelings, skills, plans), what each wants; a story passed from one
## to the next, changing a little each time and carrying who told whom; what it does to how they feel and to
## their plans (a want becomes a quest, news that it's done takes it off); and evenings round the campfire
## while the game's closed, where the news goes round.

var failed := false


func _init() -> void:
	_who()
	_a_story()
	_wants()
	_fireside()
	_carried()
	_saving()
	print("FAILED" if failed else "DONE: islanders and gossip")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


## Someone, as the catch-up has them: who, memory, body, heart, plans, skills, news.
func person(who: String) -> Dictionary:
	var mem := Memory.seeded(who, Mind.SEEDS[who] if Mind.SEEDS.has(who) else Folk.SEEDS[who])
	var p := {who = who, mem = mem, body = Body.new(who), heart = Heart.fresh(who), plans = Plans.new(), skills = Skills.fresh(who), news = Gossip.new(who)}
	if Folk.has(who):
		var w: Dictionary = Folk.WANTS[who]
		p.news.witness(who, w.text, .2, 0.0, "want", who)
	return p


func _who() -> void:
	check(Folk.IDS.size() >= 3 and Folk.IDS.all(func(w): return Folk.HOME.has(w) and Folk.ROUND.has(w) and Folk.WANTS.has(w) and Folk.SEEDS.has(w) and Folk.BODY.has(w)),
		"%d islanders, each with a home, a day, a want, memories to start with and a body" % Folk.IDS.size())
	var ok := true
	for w in Folk.everyone():
		var h := Heart.fresh(w)
		if Folk.others(w).any(func(o): return not h.rel.has(o)) or h.bonds().size() != Folk.others(w).size():
			ok = false
	check(ok, "everyone has feelings about everyone else, and Wisp")
	check(Heart.fresh("nell").rel.mo.fond > Heart.fresh("odo").rel.mo.fond and Heart.fresh("odo").rel.bo.fond > Heart.fresh("odo").rel.nell.fond,
		"their own feelings: Nell dotes on Mo, Odo gets on with Bo better than with Nell")
	check(Heart.fresh("mo").rel.has("nell") and Heart.fresh("mo").bonds().back().begins_with("Wisp") or Heart.fresh("mo").bonds().back().begins_with("Bo"),
		"Mo and Bo know them too (those who matter most come last: %s)" % Heart.fresh("mo").bonds().back().get_slice(":", 0))
	check(Skills.fresh("nell").level.wayfinding > Skills.fresh("mo").level.wayfinding and Skills.fresh("odo").level.building > Skills.fresh("bo").level.building,
		"what they're good at: Nell knows every path, Odo's handier than Bo")
	check(Life.doing("nell", 6.5) == "chore" and Life.doing("odo", 6.5) == "sleep" and Life.doing("tam", 20.0) == "campfire" and Life.doing("odo", 20.5) == "campfire",
		"their own days: Nell out fishing at dawn while Odo sleeps; everyone at the campfire of an evening")
	var plan := Plans.fallback("tam", null, Heart.fresh("tam"), [], 8.0)
	check(plan.any(func(i): return i.text == "get my bee smoker back") and plan.any(func(i): return i.text == "tend the bees"), "a day's plan of their own, without the model: %s" % "; ".join(plan.map(func(i): return i.text)))
	check(Folk.wanted_by("float") == "nell" and Folk.wanted_by("smoker") == "tam" and Folk.wanted_by("shell_2") == "odo" and Folk.wanted_by("apple_1") == "", "what each wants, and what would do it")


## Bo fibs to Mo; Mo tells Nell, Nell tells Tam, Tam tells Odo.
func _a_story() -> void:
	var p := {}
	for w in ["mo", "bo", "nell", "tam", "odo"]:
		p[w] = person(w)
	var first: Dictionary = p.mo.news.witness("bo", "Bo told Mo the door on the hill was stuck, and it wasn't true", -.5, 10.0)
	var texts := [first.text]
	var got := []
	var pairs := [["mo", "nell"], ["nell", "tam"], ["tam", "odo"]]
	var trust_before: float = p.tam.heart.rel.bo.trust
	var fond_before: float = p.odo.heart.rel.bo.fond
	for pr in pairs:
		# Their own wants go first: the story comes once those are told
		var g := {}
		for i in 4:
			g = Gossip.chat(p[pr[0]], p[pr[1]], 11.0 + i)
			if not g.is_empty() and g.story.id == first.id:
				break
		got.append(g)
		texts.append(g.story.text if not g.is_empty() else "")
	var last: Dictionary = got.back()
	check(got.all(func(g): return not g.is_empty() and g.story.id == first.id), "the story goes from Mo to Nell to Tam to Odo")
	check(not last.is_empty() and last.story.chain == ["mo", "nell", "tam", "odo"] and last.story.from == "tam", "and carries who told whom: %s" % (" → ".join(last.story.chain) if not last.is_empty() else "-"))
	var changed := 0
	for i in range(1, texts.size()):
		if texts[i] != texts[i - 1]:
			changed += 1
	check(changed >= 1 and texts.back() != texts[0], "it changes a little in the telling (%d of 3 times): \"%s\"" % [changed, texts.back()])
	check(texts.back().contains("door") and texts.back().contains("Bo"), "but it's still the same story")
	check(absf(float(last.story.s)) >= absf(float(first.s)), "and if anything it gets worse (%.2f from %.2f)" % [last.story.s, first.s])
	var heard := String(p.odo.mem.entries.back().s)
	check(heard.begins_with("Tam told me (she had it from Nell)"), "Odo remembers who told him, and where they had it: \"%s\"" % heard.left(70))
	check(p.tam.heart.rel.bo.trust < trust_before and p.odo.heart.rel.bo.fond < fond_before, "it colours how they feel about Bo (Tam trusts him less: %.2f from %.2f)" % [p.tam.heart.rel.bo.trust, trust_before])
	check(p.nell.news.pick("mo", 20.0).get("id", "") != first.id and p.odo.news.pick("bo", 20.0).get("id", "") != first.id, "it isn't told back to where it came from, nor to Bo about himself")
	# The same every time
	var q := {}
	for w in ["mo", "bo", "nell", "tam", "odo"]:
		q[w] = person(w)
	q.mo.news.witness("bo", first.text, -.5, 10.0)
	var again := []
	for pr in pairs:
		var g := {}
		for i in 4:
			g = Gossip.chat(q[pr[0]], q[pr[1]], 11.0 + i)
			if not g.is_empty() and g.story.id == first.id:
				break
		again.append(g.story.text)
	check(again == texts.slice(1), "the same every run")


func _wants() -> void:
	var p := {}
	for w in ["mo", "bo", "nell", "tam", "odo"]:
		p[w] = person(w)
	var g := Gossip.chat(p.nell, p.mo, 9.0)
	check(not g.is_empty() and g.from == "nell" and g.story.kind == "want", "Nell tells Mo what she wants")
	var todo: String = Folk.WANTS.nell.todo
	check(p.mo.plans.items.any(func(i): return i.text == todo), "and it's a quest for Mo now: \"%s\"" % todo)
	check(String(p.mo.mem.entries.back().s).begins_with("Nell told me: she has lost her lucky float"), "she remembers Nell telling her: \"%s\"" % String(p.mo.mem.entries.back().s).left(60))
	# Bo hears it from Mo
	var g2 := Gossip.chat(p.mo, p.bo, 9.5)
	check(not g2.is_empty() and g2.story.quest == "nell" and p.bo.plans.items.any(func(i): return i.text == todo), "Mo passes it on, and Bo takes it up too")
	# Someone who doesn't care for Nell doesn't
	p.tam.heart.rel.nell.fond = -.3
	Gossip.chat(p.nell, p.tam, 9.6)
	check(p.tam.news.knows(Gossip.id_of("want", "", "nell")) and not p.tam.plans.items.any(func(i): return i.text == todo), "Tam's cross with Nell: she hears about the float, but won't go looking")
	# Bo finds it: the news goes round, and Mo needn't look any more
	var mo_fond: float = p.mo.heart.rel.bo.fond
	p.nell.news.witness("bo", "Bo " + Folk.WANTS.nell.done, .7, 12.0, "done", "nell")
	Gossip.chat(p.nell, p.mo, 12.5)
	var mine: Array = p.mo.plans.items.filter(func(i): return i.text == todo)
	check(not mine.is_empty() and mine[0].status == "dropped", "Nell tells Mo that Bo found it: it's off Mo's list")
	check(p.mo.heart.rel.bo.fond > mo_fond, "and Mo thinks the better of Bo for it")
	check(p.mo.news.pick("tam", 13.0).get("kind", "") == "done", "and passes on that it's done, not that Nell's still looking")


## Two days with the game closed: the news goes round at the campfire.
func _fireside() -> void:
	var run := func() -> Dictionary:
		var ps := []
		for w in ["mo", "bo", "nell", "tam", "odo"]:
			ps.append(person(w))
		var world := Life.fresh_world()
		var r := Life.catch_up(ps, world, 10.0, 48.0)
		return {r = r, ps = ps}
	var a: Dictionary = run.call()
	var b: Dictionary = run.call()
	var told: Array = a.r.told
	check(told.size() >= 6, "two evenings round the campfire: %d things passed on (first: %s)" % [told.size(), told[0].left(80) if told.size() else "-"])
	check(JSON.stringify(told) == JSON.stringify(b.r.told), "the same every time")
	var mo: Dictionary = a.ps[0]
	var wants := Folk.IDS.filter(func(w): return mo.news.knows(Gossip.id_of("want", "", w)))
	check(wants.size() == Folk.IDS.size(), "by now Mo's heard what each of them wants (%s)" % ", ".join(wants))
	var odo: Dictionary = a.ps[4]
	check(odo.news.items.any(func(x): return x.chain.size() >= 3), "and some of it reached Odo second-hand")
	check(mo.plans.items.any(func(i): return i.get("quest", false) or Folk.IDS.any(func(w): return i.text == Folk.WANTS[w].todo)), "Mo's plan this morning has someone's want in it: %s" % "; ".join(mo.plans.items.map(func(i): return i.text)))
	var nell: Dictionary = a.ps[2]
	check(nell.mem.entries.any(func(e): return String(e.s).contains("went fishing off the south beach")), "and Nell's been out fishing, as she does")


## A thought that says it passes something on only does if the words carry it (lines from round 18's runs).
func _carried() -> void:
	var fib := {text = "Bo told Mo \"Mo, I don't have the apple, honest.\", and it wasn't true", about = "bo", quest = ""}
	var float_ := {text = Folk.WANTS.nell.text, about = "nell", quest = "nell"}
	var shell := {text = Folk.WANTS.odo.text, about = "odo", quest = "odo"}
	check(Gossip.carried("Bo, you totally had an apple earlier!", fib) and Gossip.carried("Storm took me lucky float, green glass one. Washed up north-east shore somewhere.", float_)
		and Gossip.carried("A ridged shell. From the beach.", shell), "a line that tells the story passes it on")
	check(not Gossip.carried("It's humming! Grandma was right.", float_) and not Gossip.carried("Aye, I'm here! Who's bumping about in the dark?", float_)
		and not Gossip.carried("Finally. Food.", fib), "a line about something else doesn't")


func _saving() -> void:
	var g := Gossip.new("tam")
	g.witness("bo", "Bo fell in the pond", .2, 3.0)
	var again := Gossip.from_save(JSON.parse_string(JSON.stringify(g.to_save())), "tam")
	check(JSON.stringify(again.to_save()) == JSON.stringify(g.to_save()), "saved and loaded: as it was")
	check(Gossip.from_save(null, "mo").items.is_empty(), "a file from before: nothing to tell yet")
