extends SceneTree
## How Mo and Bo look, from how they are, on its own (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/looks_test.gd
## Tired slumps and slows them, cold hunches and shivers them, fear hunches them and sets them glancing about,
## a good mood puts a spring in their step; faces for each; warmer toward a friend, guarded toward someone
## they hold a grudge against, and eyes that slide off whoever they've just fibbed to.

var failed := false


func _init() -> void:
	_body()
	_faces()
	_who_with()
	_fibs()
	print("FAILED" if failed else "DONE: looks")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func body(tired := .1, cold := 0.0, fear := 0.0, bored := .2) -> Body:
	var b := Body.new("mo")
	b.tired = tired
	b.cold = cold
	b.fear = fear
	b.bored = bored
	return b


func heart(v := 0.0, a := .4) -> Heart:
	var h := Heart.fresh("mo")
	h.v = v
	h.a = a
	return h


func _body() -> void:
	var calm := Looks.of(body(), heart(.1))
	check(calm.slump < .05 and calm.hunch < .05 and calm.shiver == 0.0 and calm.bounce < .05 and absf(calm.walk - 1.0) < .05 and calm.glance == 0.0,
		"rested, warm, calm: standing easy, walking at her usual pace")
	var tired := Looks.of(body(.9), heart(.1))
	check(tired.slump > .6 and tired.walk < .85 and tired.lids > .3, "worn out: slumped (%.2f), slower (%.2f of her pace), heavy-lidded (%.2f)" % [tired.slump, tired.walk, tired.lids])
	var low := Looks.of(body(), heart(-.6, .3))
	check(low.slump > .2 and low.bounce == 0.0, "low in mood: slumped a little (%.2f), no spring" % low.slump)
	var cold := Looks.of(body(.1, .8), heart(.1))
	check(cold.hunch > .6 and cold.shiver > .9 and cold.walk < 1.0, "freezing: hunched (%.2f), shivering (%.2f)" % [cold.hunch, cold.shiver])
	check(Looks.of(body(.1, .3), heart(.1)).shiver == 0.0, "a bit chilly: no shivers yet")
	var scared := Looks.of(body(.1, 0.0, .8), heart(-.1, .8))
	check(scared.hunch > .5 and scared.glance > .6 and scared.shiver == 0.0, "scared: hunched (%.2f), looking all about (%.2f a second)" % [scared.hunch, scared.glance])
	var happy := Looks.of(body(), heart(.8, .7))
	check(happy.bounce > .8 and happy.walk > 1.1 and happy.slump == 0.0, "happy and lively: a spring in her step (%.2f), quicker (%.2f)" % [happy.bounce, happy.walk])
	check(Looks.of(body(), heart(.8, .15)).bounce < .1, "happy but sleepy-calm: content, no bouncing")
	check(Looks.of(body(.95), heart(.8, .7)).bounce < .1, "happy but worn out: too tired to bounce")
	var worst := Looks.of(body(1.0, 1.0, 1.0, 1.0), heart(-1.0, 1.0))
	check(worst.walk >= .55 and worst.slump <= 1.0 and worst.hunch <= 1.0, "however bad it gets, they still walk (%.2f of the pace)" % worst.walk)


func _faces() -> void:
	var cases := {
		"happy": [body(), heart(.8, .7), "happy", "grin"],
		"content": [body(), heart(.3), "neutral", "smile"],
		"calm": [body(), heart(0.0), "neutral", "flat"],
		"sad": [body(), heart(-.5, .3), "sad", "frown"],
		"cross": [body(), heart(-.6, .8), "cross", "frown"],
		"worried (cold)": [body(.1, .7), heart(0.0), "worried", "flat"],
		"worried (uneasy)": [body(.1, 0.0, .4), heart(0.0), "worried", "flat"],
		"scared": [body(.1, 0.0, .8), heart(.2), "scared", "o"],
	}
	var ok := true
	for k in cases:
		var c: Array = cases[k]
		var e := Looks.of(c[0], c[1])
		if e.brows != c[2] or e.mouth != c[3]:
			ok = false
			print("  %s: %s/%s, not %s/%s" % [k, e.brows, e.mouth, c[2], c[3]])
	check(ok, "a face for each: " + ", ".join(cases.keys()))
	var sc := Looks.of(body(.9, 0.0, .8), heart())
	check(sc.lids == 0.0, "scared: eyes wide, however tired")
	check(Looks.of(body(), heart(-.6, .8)).lids > .1, "cross: eyes narrowed")
	var a := Looks.of(body(.7, .5, .3), heart(.2, .5), "bo")
	check(JSON.stringify(a) == JSON.stringify(Looks.of(body(.7, .5, .3), heart(.2, .5), "bo")), "the same every time")


func _who_with() -> void:
	var h := heart(.1)
	check(Looks.of(body(), h).mouth == "flat", "on her own, in a so-so mood: a flat mouth")
	h.rel.bo.fond = 1.0
	check(Looks.of(body(), h, "bo").mouth == "smile", "with Bo, who she's fond of: a smile")
	h.rel.wisp.fond = -.4
	h.grudge("wisp", "teased me", .6, 1.0)
	var e := Looks.of(body(), h, "wisp")
	check(e.brows == "cross" and e.away, "with Wisp, who she's sore at: cross, and eyes off Wisp")
	check(not Looks.of(body(), h, "bo").away, "but not with Bo")


func _fibs() -> void:
	var e := Looks.of(body(), heart(.3), "bo", 1.0)
	check(e.away and e.glance >= .8 and e.brows == "worried", "just fibbed to Bo: eyes slide off him, a worried look")
	var later := Looks.of(body(), heart(.3), "bo", .1)
	check(not later.away and later.brows == "neutral", "a few seconds later: herself again")
	check(Looks.of(body(), heart(.8, .7), "bo", 1.0).brows == "happy", "a happy bluffer keeps smiling (only the eyes give it away)")
