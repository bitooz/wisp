extends SceneTree
## Secrets and fibs on their own, with fixed steps (no game, no model, the same every run):
##   godot --headless --path . -s res://tools/secret_test.gd
## Keeping a secret, giving it away (and to whom), lies and bluffs with who heard them and what's really so, in
## words for their own thoughts, how they sit in memory, and saving.

var failed := false


func _init() -> void:
	_secrets()
	_lies()
	_in_memory()
	_saving()
	print("FAILED" if failed else "DONE: secrets")
	quit(1 if failed else 0)


func check(ok: bool, what: String) -> void:
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		failed = true


func _secrets() -> void:
	var s := Secrets.new()
	var k := s.keep("I found a shiny key under the mushroom", 1.0)
	check(k.kind == "secret" and s.lines() == ["a secret: I found a shiny key under the mushroom (you haven't told anyone)"], "a secret kept: %s" % [s.lines()])
	s.keep("found a shiny key under the mushroom!", 1.5)
	check(s.items.size() == 1, "the same secret again is the same secret")
	check(s.spoke("Let's go to the pond", ["bo"]).is_empty() and k.to.is_empty(), "talking about something else gives nothing away")
	var gone := s.spoke("Bo! I found a key, under the giant mushroom!", ["bo"])
	check(gone.size() == 1 and k.to == ["bo"] and s.lines()[0].ends_with("(only Bo knows)"), "telling Bo gives it away, to Bo only: %s" % [s.lines()])
	check(s.spoke("the key under the mushroom", ["bo"]).is_empty(), "telling him again isn't news")
	s.spoke("the key under the mushroom, Wisp", ["wisp"])
	check(k.to == ["bo", "wisp"] and s.lines()[0].ends_with("(only Bo and Wisp know)"), "then Wisp: \"%s\"" % s.lines()[0])
	check(s.spoke("the key under the mushroom", []).is_empty(), "said to nobody, nobody's told")


func _lies() -> void:
	var s := Secrets.new()
	var l := s.lied("Bo, I'll wait right here for you.", "no way, I'm going in alone", ["bo", "wisp"], 2.0)
	check(l.kind == "lie" and s.lines() == ["you told Bo and Wisp \"Bo, I'll wait right here for you.\", and it isn't true: no way, I'm going in alone"], "a fib, with who heard it and what's really so: %s" % [s.lines()])
	var b := s.lied("I'm not scared at all.", "I'm terrified of the dark", ["mo"], 3.0, "bluff")
	check(b.kind == "bluff" and s.lines()[1] == "you told Mo \"I'm not scared at all.\", putting on a front: really, I'm terrified of the dark", "a bluff: \"%s\"" % s.lines()[1])
	check(s.lied("I'm the bravest kid on the island", "", [], 4.0).is_empty() and s.items.size() == 2, "a fib nobody heard isn't one")
	for i in 10:
		s.lied("fib %s" % "abcdefghij"[i], "", ["bo"], 5.0)
	check(s.items.size() == Secrets.MOST and s.items.back().said == "fib j", "at most %d kept in mind at once (the latest)" % Secrets.MOST)
	var re := RegEx.create_from_string("[0-9]")
	check(s.lines().all(func(x): return re.search(x) == null), "in words, no numbers")


func _in_memory() -> void:
	var m := Memory.new("mo")
	var t := m.add("thought", "no way, I'm going in alone")
	var l := m.add("lied", "told Bo \"I'll wait here\", and it wasn't true: no way, I'm going in alone")
	var k := m.add("secret", "I found a shiny key under the mushroom")
	check(t.imp == 3 and l.imp == 7 and k.imp == 7, "a passing thought matters a little; a fib told, or a secret kept, a lot (so they stay in mind)")
	var lines := m.lines([t, l, k])
	check(lines[0].ends_with("(thought to myself) no way, I'm going in alone") and lines[1].ends_with("I told Bo \"I'll wait here\", and it wasn't true: no way, I'm going in alone") and lines[2].ends_with("(a secret I'm keeping) I found a shiny key under the mushroom"), "in their memory, as their own: %s" % [lines])
	var got := m.recall("Bo is waiting for me here", 0, 3)
	check(got.any(func(e): return e.k == "lied"), "thinking about Bo waiting, the fib comes back to mind")


func _saving() -> void:
	var s := Secrets.new()
	s.keep("I found a shiny key", 1.0)
	s.spoke("a shiny key!", ["bo"])
	s.lied("I'm fine", "I'm not", ["wisp"], 2.0, "bluff")
	var again := Secrets.from_save(JSON.parse_string(JSON.stringify(s.to_save())))
	check(JSON.stringify(again.to_save()) == JSON.stringify(s.to_save()), "saved and loaded: as they were")
	check(Secrets.from_save(null).items.is_empty(), "a file from before: no secrets yet")
