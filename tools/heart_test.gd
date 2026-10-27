extends SceneTree
## Mood and feelings on their own, with fixed steps (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/heart_test.gd
## Who they are at the start, mood lasting and drifting (events, the body, time, sleep), feelings toward each
## other and Wisp moving slowly (help, teasing, promises kept and broken, shared moments, what others say),
## grudges fading, inside jokes, what reaches the model (words only), saving, and files from before hearts
## (including the game's own Mo and Bo files, read only).

var failed := false


func _init() -> void:
	_who_they_are()
	_mood()
	_slowly()
	_teasing()
	_promises()
	_grudges_and_jokes()
	_talk()
	_words()
	_saving()
	print("FAILED" if failed else "DONE: mood and feelings")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func body(hunger := .2, tired := .1, cold := 0.0, fear := 0.0) -> Body:
	var b := Body.new("mo")
	b.hunger = hunger
	b.tired = tired
	b.cold = cold
	b.fear = fear
	return b


func _who_they_are() -> void:
	var mo := Heart.fresh("mo")
	var bo := Heart.fresh("bo")
	check(mo.mood_words().begins_with("in a ") and bo.mood_words() == "all right, nothing special", "Mo starts bubbly (\"%s\"), Bo even (\"%s\")" % [mo.mood_words(), bo.mood_words()])
	check(mo.rel.wisp.fond > bo.rel.wisp.fond and bo.rel.wisp.trust < .25, "Mo already likes Wisp; Bo isn't sure about Wisp yet")
	check(mo.rel.bo.fond > .5 and bo.rel.mo.trust > .5, "and they're old friends")


func _mood() -> void:
	var h := Heart.fresh("mo")
	var before := h.mood_words()
	h.pass_time(0.0, 0.0, null)
	check(h.mood_words() == before, "nothing happening, no time passing: the mood stays as it was")
	h.feel(-.6, .5)
	check(h.v < -.2 and h.a > .8 and (h.mood_words().begins_with("grumpy and on edge") or h.mood_words() == "upset and cross"), "a fright: \"%s\"" % h.mood_words())
	for i in 3:
		h.pass_time(.5, 0.0, body())
	check(h.v < h.base_v - .1, "an hour and a half on, still not over it")
	for i in 12:
		h.pass_time(.5, 0.0, body())
	check(absf(h.v - h.base_v) < .05 and h.mood_words() == before, "six hours on, back to herself (\"%s\")" % h.mood_words())
	var low := Heart.fresh("mo")
	for i in 8:
		low.pass_time(1.0, 0.0, body(.9, .7, .7))
	check(low.v < -.2 and low.mood_words().begins_with("grumpy"), "hungry, tired and cold for hours: \"%s\"" % low.mood_words())
	var scared := Heart.fresh("bo")
	for i in 4:
		scared.pass_time(1.0, 0.0, body(.2, .1, 0.0, .9))
	check(scared.mood_words() == "upset and cross" or scared.mood_words().begins_with("grumpy and on edge") or scared.mood_words().begins_with("really"), "scared stiff for a while: \"%s\"" % scared.mood_words())
	low.slept(true)
	check(low.v > 0.0, "a good night's sleep and she's mostly herself again (\"%s\")" % low.mood_words())


func _slowly() -> void:
	var h := Heart.fresh("bo")
	var t0: float = h.rel.wisp.trust
	h.helped("wisp")
	check(h.rel.wisp.trust - t0 > 0 and h.rel.wisp.trust - t0 < .1, "one good turn: a little more trust (%.2f to %.2f), not a lot" % [t0, h.rel.wisp.trust])
	for i in 30:
		h.helped("wisp")
	check(h.rel.wisp.trust > .6 and h.rel.wisp.trust < 1.0, "thirty: trusted, but never all the way (%.2f)" % h.rel.wisp.trust)
	var f: float = h.rel.wisp.fond
	h.change("wisp", 0.0, -.2)
	check(f - h.rel.wisp.fond < .2, "near the top, it takes more to move")


func _teasing() -> void:
	var mo := Heart.fresh("mo")
	var f: float = mo.rel.bo.fond
	mo.teased("bo")
	check(mo.rel.bo.fond > f, "Mo teased by Bo: she likes it")
	var bo := Heart.fresh("bo")
	var fw: float = bo.rel.wisp.fond
	bo.teased("wisp")
	check(bo.rel.wisp.fond < fw and bo.rel.wisp.grudges.size() == 1, "Bo teased by Wisp, whom he's not sure about: he minds")
	var fm: float = bo.rel.mo.fond
	bo.teased("mo")
	check(bo.rel.mo.fond >= fm, "but from Mo, whom he likes, he lets it go")
	check(Heart.is_tease("Bo, you slowpoke!") and Heart.is_tease("haha, scaredy cat") and not Heart.is_tease("Let's go to the door"), "teasing is told from plain talk")


func _promises() -> void:
	check(Heart.promise_kind("I'll give you the torch later") == "give" and Heart.promise_kind("Don't worry, I will bring you an apple") == "give", "a promise to give")
	check(Heart.promise_kind("I'll wait here for you") == "wait" and Heart.promise_kind("I promise I'll wait") == "wait", "a promise to wait")
	check(Heart.promise_kind("I promise I'll find you a light") == "other" and Heart.promise_kind("I'll look over there") == "", "any other promise, and not every \"I'll\"")
	var h := Heart.fresh("mo")
	var p := h.promised("wisp", "I'll give you the torch later", 10.0)
	check(p.kind == "give" and h.open_from("wisp").size() == 1 and h.about("wisp").contains("Wisp promised you \"I'll give you the torch later\", and hasn't yet"), "a promise to her is remembered as one, and she knows it's still open")
	var t: float = h.rel.wisp.trust
	h.resolve(p, true, 11.0)
	check(h.rel.wisp.trust > t and not h.about("wisp").contains("hasn't yet"), "kept: she trusts Wisp more")
	var q := h.promised("wisp", "I'll wait here for you", 12.0)
	t = h.rel.wisp.trust
	h.resolve(q, false, 12.5)
	check(h.rel.wisp.trust < t - .1 and h.about("wisp").contains("really sore that Wisp promised (\"I'll wait here for you\") and didn't"), "broken: trust drops, and it hurts: \"%s\"" % h.about("wisp"))
	h.resolve(q, true, 13.0)
	check(q.status == "broken", "once broken, it stays broken")
	var r := h.promised("bo", "I'll bring you an apple", 20.0)
	check(h.pass_time(1.0, 30.0).is_empty() and h.pass_time(1.0, 45.0).has(r), "a promise comes due after a day")


func _grudges_and_jokes() -> void:
	var h := Heart.fresh("mo")
	h.left_behind("bo", 0.0)
	check(h.about("bo").contains("a bit sore that Bo went off without you"), "left behind: \"%s\"" % h.about("bo"))
	for i in 24:
		h.pass_time(2.0, 2.0 * i)
	check(not h.about("bo").contains("sore"), "two days on, she's over it")
	h.shared("bo", "the time Bo walked right into you", 0.0, true)
	h.shared("bo", "the time Bo went boing off the giant mushroom", 0.0, true)
	h.shared("bo", "the time Bo walked right into you", 1.0, true)
	check(h.rel.bo.jokes.size() == 2 and h.about("bo").contains("you and Bo still laugh about the time Bo walked right into you"), "inside jokes, the one that's come up most first: \"%s\"" % h.about("bo"))
	var f: float = h.rel.bo.fond
	h.shared("bo", "the time you two opened the big stone door together", 2.0)
	check(h.rel.bo.fond > f and h.rel.bo.jokes.size() == 2, "something big done together brings them closer (not a joke)")
	var g := Heart.fresh("bo")
	g.left_behind("mo", 0.0)
	var s: float = g.rel.mo.grudges[0].s
	g.helped("mo")
	check(g.rel.mo.grudges[0].s < s, "a kindness eases a grudge")


func _talk() -> void:
	var mo := Heart.fresh("mo")
	var f: float = mo.rel.wisp.fond
	mo.heard_about("wisp", "bo", Heart.sentiment("Wisp is really annoying and creepy"))
	check(mo.rel.wisp.fond < f, "Bo, whom she trusts, says Wisp's annoying: it rubs off a little")
	var bo := Heart.fresh("bo")
	bo.rel.mo.trust = -.5
	var fb: float = bo.rel.wisp.fond
	bo.heard_about("wisp", "mo", 1.0)
	check(bo.rel.wisp.fond == fb, "from someone he doesn't trust, it doesn't")
	check(Heart.sentiment("Wisp is brave and funny") > .5 and Heart.sentiment("I don't trust Wisp") < 0 and Heart.sentiment("Wisp is not nice") < 0 and Heart.sentiment("Wisp went that way") == 0.0, "warm, cold and plain talk are told apart")


func _words() -> void:
	var lines := []
	for who in ["mo", "bo"]:
		var h := Heart.fresh(who)
		for o in h.rel:
			for t in [-.9, -.3, 0.0, .4, .9]:
				for f in [-.9, -.3, 0.0, .4, .9]:
					h.rel[o].trust = t
					h.rel[o].fond = f
					lines.append(h.about(o))
		for v in [-.9, -.4, 0.0, .3, .8]:
			for a in [.1, .5, .9]:
				h.v = v
				h.a = a
				lines.append(h.mood_words())
	var re := RegEx.create_from_string("[0-9]")
	check(lines.all(func(l): return re.search(l) == null), "%d ways of putting it, none with a number" % lines.size())
	check(lines.all(func(l): return not RegEx.create_from_string("\\b(him|her|it|his)\\b").search(l)), "and they name the others rather than guess at he or she")


func _saving() -> void:
	var h := Heart.fresh("bo")
	h.feel(-.4, .3)
	h.promised("wisp", "I'll wait here for you", 3.0)
	h.left_behind("mo", 4.0)
	h.shared("mo", "the time Mo walked right into you", 5.0, true)
	var again := Heart.from_save(JSON.parse_string(JSON.stringify(h.to_save())), "bo")
	check(JSON.stringify(again.to_save()) == JSON.stringify(h.to_save()), "saved and loaded: mood, feelings, grudges, jokes and promises all as they were")
	check(JSON.stringify(Heart.from_save(null, "mo").to_save()) == JSON.stringify(Heart.fresh("mo").to_save()), "a file from before hearts: they start as they were at the beginning")
	for who in ["mo", "bo"]:
		var path := "user://mind_%s.json" % who
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var o = JSON.parse_string(text)
		var m := Memory.from_save(o, who, preload("res://scripts/mind.gd").SEEDS[who])
		var hh := Heart.from_save(o.get("heart"), who)
		check(m.entries.size() == o.memory.size() and JSON.stringify(hh.to_save()) == JSON.stringify(Heart.fresh(who).to_save()), "%s's own file (read only): every memory kept, and a heart to start from" % who.capitalize())
		check(FileAccess.get_file_as_string(path) == text, "%s's file is untouched" % who.capitalize())
