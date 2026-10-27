extends Level
## The dungeon under the hill. Dark: Mo and Bo see only what some light reaches: yours, the torch by the
## way in if they carry it, the ember. Two stone plates open the door while both are held down at once.
## Behind it, a shadow that hates light guards an ember. Nothing here is scripted: it's all what they do.

const PILLARS := [[-3.0, -2.4], [3.0, -2.4], [-4.6, 1.5], [4.6, 1.7]]
## KayKit's stone, leaned toward the mock's purple-grey
const TINT := "#D3CCDA"

var CAVE := {sky = Color("#7A88B8").srgb_to_linear(), gnd = Color("#1E1926").srgb_to_linear(), warm = Color("#FFB27A").srgb_to_linear()}

var door: Node3D
var slab: MeshInstance3D
var seal_m: ShaderMaterial
var plates := []
var torches := []
var ember: Node3D
var ember_light: OmniLight3D
var gloom: Node3D
var puffs := []
var g_eyes := []

var door_open := false
var torches_on := false
var torch_t := 0.0
var gloom_s := 1.0
var gloom_t := 0.0
var gloom_idle := 0.0
var hinted := false
var spotted := {}
var gloom_m: ShaderMaterial
var torch: Node3D
var steps: Node3D
## The flames of carried lights, to flicker
var torches_carried := []
## The fight's feel: each pulse of light lands as a hit; the shadow flashes and flinches
var hit_t := 0.0
var flash := 0.0
var flinch := 0.0


func _init() -> void:
	id = "cave"
	cam_dist = 11.0
	az_limit = .6
	theme = "cave"
	dark = true
	names.merge({plateA = "plate", plateB = "plate", ember = "ember", gloom = "shadow"})
	said = {plateA = "a stone plate", plateB = "a stone plate", ember = "an ember", gloom = "something with eyes"}
	idle_spot = Vector3(3.6, 0, 3.0)
	# Only the way they came in: the rest they have to find
	places = {"the way back up (where you came in)": Vector3(0, 0, 3.6)}
	# Getting there, they look up the steps (and the daylight at the top)
	place_looks = {"the way back up (where you came in)": Vector3(0, 1.0, 5.2)}
	for w in ["stairs", "steps", "daylight", "outside", "island", "home", "entrance", "exit", "out"]:
		place_words[w] = "the way back up (where you came in)"
	labels = {door = "the big stone door", plateA = "the left stone plate", plateB = "the right stone plate", ember = "the ember",
		gloom = "the shadow", torch = "the torch", way = "the steps up to the island"}
	obstacles = PILLARS.map(func(q): return [q[0], q[1], .6])


## Anywhere up on the island ("the glowing door on the hill", "the campfire", "our house") is the way back up:
## the words of the island's places and things lead to the steps, except any that name something down here.
func _up_words() -> void:
	var isle: Level = game.levels.get("isle")
	if isle == null:
		return
	var here_words := {}
	for k in labels.keys() + labels.values() + names.values() + said.values():
		for w in _plain_words(String(k)):
			here_words[w] = true
	var up: String = places.keys()[0]
	for k in isle.places.keys() + isle.place_words.keys():
		for w in _plain_words(String(k)):
			if not here_words.has(w) and not place_words.has(w):
				place_words[w] = up
	# What they see from out there that names the door they came in by
	for w in ["glowing", "hill", "humming", "rune", "sunlight", "sun", "sky", "surface", "upstairs", "up"]:
		place_words[w] = up


static func _plain_words(s: String) -> Array:
	var out := []
	for w in s.get_slice("(", 0).to_lower().replace("'s", "").replace("-", " ").replace(",", " ").split(" ", false):
		if w.length() > 2 and not w in ["the", "and", "with", "over", "old", "little", "our", "her", "his", "way", "back", "where", "you", "came"]:
			out.append(w)
	return out


func stone(c: String) -> ShaderMaterial:
	return Build.mat(c, {roughness = .95})


func wall(w: float, h: float, d: float, x: float, y: float, z: float, m: Material) -> MeshInstance3D:
	return Build.mesh(Build.box(w, h, d), m, x, y, z, self)


func _ready() -> void:
	Build.reseed(23)
	var kk := func(n: String, pos: Vector3, yaw := 0.0, sc = 1.0, o := {}) -> Node3D:
		var p := o.duplicate()
		p.shadow = false
		p.tint = TINT
		if sc is Vector3:
			p.scale3 = sc
			return Props.kaykit(self, n, pos, yaw, 1.0, p)
		return Props.kaykit(self, n, pos, yaw, sc, p)
	# Floor: KayKit stone tiles on the mock's 1.3 grid, some cracked, some grown over with moss
	var x := -5.85
	while x < 6:
		var z := -4.6
		while z < 5.5:
			var r := Build.rnd()
			var n := "floor_tile_small"
			if r < .14:
				n = "floor_tile_small_broken_A"
			elif r < .27:
				n = "floor_tile_small_weeds_A"
			elif r < .38:
				n = "floor_tile_small_weeds_B"
			kk.call(n, Vector3(x, -.0325, z), floori(Build.rnd() * 4) * PI / 2, .65)
			z += 1.3
		x += 1.3
	# Walls where the mock has them: the back wall either side of the door, its lintel,
	# and side walls that drop to a low rubble wall toward you
	for s in [-1, 1]:
		kk.call("wall" if s < 0 else "wall_cracked", Vector3(s * 4.96, 0, -5.3), 0.0, Vector3(.646, .8, .8))
		kk.call("wall_cracked" if s < 0 else "wall", Vector3(s * 2.37, 0, -5.3), 0.0, Vector3(.646, .8, .8))
		kk.call("wall", Vector3(s * 6.6, 0, -4.48), PI / 2, Vector3(.5875, .8, .7))
		kk.call("wall_cracked", Vector3(s * 6.6, 0, -2.13), PI / 2, Vector3(.5875, .8, .7))
		for i in 5:
			kk.call("rubble_half", Vector3(s * (6.55 + Build.rnd() * .1), 0, -.4 + i * 1.18), PI / 2 + (Build.rnd() - .5) * .3, Vector3(.3, .26 + Build.rnd() * .08, .3))
	kk.call("wall", Vector3(0, 2.6, -5.3), 0.0, Vector3(.55, .15, .8))
	# The alcove behind the door
	Build.noshadow(Build.mesh(Build.box(2.3, .3, 2.2), stone("#5E5866"), 0, -.15, -6.45, self))
	kk.call("wall", Vector3(0, 0, -7.65), 0.0, Vector3(.725, .8, .5))
	kk.call("wall", Vector3(-1.35, 0, -6.5), PI / 2, Vector3(.6, .8, .5))
	kk.call("wall", Vector3(1.35, 0, -6.5), PI / 2, Vector3(.6, .8, .5))
	wall(3.2, .4, 2.8, 0, 3.0, -6.5, stone("#6A6472"))
	# Pillars: the far two stand, the near two are broken stumps so they never hide the action
	for q in PILLARS:
		if q[1] < 0:
			kk.call("pillar_decorated" if q[0] < 0 else "pillar", Vector3(q[0], 0, q[1]), 0.0, Vector3(.45, .78, .45) if q[0] < 0 else Vector3(.62, .78, .62))
		else:
			kk.call("pillar", Vector3(q[0], 0, q[1]), Build.rnd() * TAU, Vector3(.62, .24 + Build.rnd() * .06, .62))
			for i in 2:
				kk.call("rubble_half", Vector3(q[0] + (Build.rnd() - .5) * 1.2, 0, q[1] + .55 + Build.rnd() * .4), Build.rnd() * TAU, .13 + Build.rnd() * .05)
	# Odds and ends against the walls
	kk.call("barrel_large", Vector3(-5.5, 0, -4.35), .3, .42)
	kk.call("barrel_small", Vector3(-4.8, 0, -4.55), 0.0, .42)
	kk.call("keg", Vector3(-5.55, 0, -3.35), PI / 2, .36)
	kk.call("crates_stacked", Vector3(5.45, 0, -4.3), -.2, .4)
	kk.call("box_small", Vector3(5.6, 0, -3.35), .5, .4)
	kk.call("barrel_small", Vector3(5.55, 0, .9), 0.0, .38)
	kk.call("banner_patternA_red", Vector3(-4.2, 0, -4.86), 0.0, .55)
	kk.call("banner_thin_red", Vector3(4.2, 0, -4.86), 0.0, .55)
	kk.call("sword_shield_broken", Vector3(-6.2, 1.9, -3.4), PI / 2, .45)
	for c in [[-1.6, -4.62, "candle_triple", .45], [1.6, -4.62, "candle_triple", .45], [-.75, -7.15, "candle_lit", .35], [.75, -7.15, "candle_lit", .35]]:
		kk.call(c[2], Vector3(c[0], 0, c[1]), Build.rnd() * TAU, c[3])
		var cg := Build.glow("#FFC46A", .45)
		cg.position = Vector3(c[0], (.9 if c[2] == "candle_triple" else 1.1) * c[3], c[1])
		add_child(cg)
	# Moss hanging down the walls
	for m in [[-5.4, -4.88, 0.0], [-1.55, -4.88, 0.0], [1.75, -4.88, 0.0], [5.6, -4.88, 0.0], [-6.24, -1.6, PI / 2], [6.24, -4.0, -PI / 2], [6.24, -1.3, -PI / 2]]:
		Props.kenney(self, "hanging_moss", m[0], m[1], 1.5 + Build.rnd() * .4, {y = 2.2 + Build.rnd() * .3, yaw = m[2], nohit = true, shadow = false, colours = {grass = "#4A6E3E"}, sway = 0.0})
	obstacles.append_array([[-5.5, -4.35, .5, 1], [-4.8, -4.55, .3, 1], [-5.55, -3.35, .45, 1], [5.45, -4.3, .55, 1], [5.6, -3.35, .3, 1], [5.55, .9, .3, 1]])

	door = Build.group(self, "door")
	slab = Build.mesh(Build.box(2.16, 2.6, .36), stone("#857E8D"), 0, 1.3, 0, door)
	slab.set_meta("body", true)
	var grooves := []
	for s in [-1, 1]:
		var m := Build.smooth("#2B3440", {emissive = "#6BE7FF", ei = .3, roughness = .6, unique = true})
		Build.noshadow(Build.mesh(Build.box(.08, 1.9, .05), m, s * .45, 1.25 - 1.3, .2, slab))
		grooves.append(m)
	seal_m = Build.smooth("#2B3440", {emissive = "#6BE7FF", ei = .3, roughness = .6, unique = true})
	Build.noshadow(Build.mesh(Build.torus(.28, .045, 8, 28), seal_m, 0, .52, .2, slab))
	door.position = Vector3(0, 0, -5.2)

	plates = [_plate(-4.5, -3.7, "plateA", grooves[0]), _plate(4.5, -3.55, "plateB", grooves[1])]

	var spots := [[-2.4, -4.9, 0.0], [2.4, -4.9, 0.0], [-6.2, -2.4, PI / 2], [6.2, -2.4, -PI / 2]]
	for i in spots.size():
		var q: Array = spots[i]
		var g := Build.group(self)
		g.position = Vector3(q[0], 2.0, q[1])
		g.rotation.y = q[2]
		Props.kaykit(g, "torch_mounted", Vector3(0, -.12, .08), 0.0, .5, {shadow = false, tint = TINT})
		var fl := Build.flames(g, [["#FF7A2F", .11, .34], ["#FFB547", .07, .24], ["#FFE491", .04, .15]])
		fl.g.position = Vector3(0, .27, .14)
		var L := Build.omni("#FF9A4A", 0, 9, 1.4)
		L.position = Vector3(0, .5, .5)
		g.add_child(L)
		torches.append({g = fl.g, fs = fl.fs, L = L, on = false, I = 0.0, i = i})

	Build.mesh(Build.cyl(.3, .4, .85, 10), stone("#857E8D"), 0, .42, -6.45, self)
	ember = Build.group(self, "ember")
	Build.noshadow(Build.mesh(Build.octa(.2), Build.mat("#FFB547", {emissive = "#FF9A2F", ei = 1.8, roughness = .3}), 0, 0, 0, ember))
	ember.add_child(Build.glow("#FFB04A", 1.2))
	ember_light = Build.omni("#FFA347", 0, 6, 1.5)
	ember.add_child(ember_light)
	ember.position = Vector3(0, 1.12, -6.45)

	gloom = Build.group(self, "gloom")
	Build.nohit(gloom)
	gloom_m = Build.smooth("#0D0A14", {emissive = "#2A1446", ei = .8, roughness = 1.0, opacity = .95, unique = true})
	Build.mesh(Build.ico(.75, 2), gloom_m, 0, 0, 0, gloom)
	for i in 8:
		var m := Build.mesh(Build.ico(.2 + Build.rnd() * .16, 1), gloom_m, 0, 0, 0, gloom)
		m.set_meta("a", i / 8.0 * TAU)
		m.set_meta("r", .6 + Build.rnd() * .25)
		m.set_meta("s", .8 + Build.rnd() * 1.2)
		puffs.append(m)
	for s in [-1, 1]:
		var e := Build.mesh(Build.sphere(.11, 12, 8), Build.basic("#E4DAFF"), s * .24, .12, .68, gloom)
		e.scale = Vector3(1, .6, .5)
		Build.noshadow(e)
		g_eyes.append(e)
	var gg := Build.glow("#8A5CFF", 2.6)
	Build.glow_opacity(gg, .55)
	gloom.add_child(gg)
	gloom.visible = false

	# A torch stuck in the rubble by the way in, burning: theirs to take
	torch = Build.group(self, "torch")
	Build.mesh(Build.cyl(.035, .045, .62, 7), Build.mat("#6B4A33", {roughness = 1.0}), 0, .31, 0, torch)
	Build.mesh(Build.cyl(.06, .05, .1, 8), Build.mat("#3B3B42", {roughness = .7}), 0, .62, 0, torch)
	var tf := Build.flames(torch, [["#FF7A2F", .1, .32], ["#FFB547", .065, .24], ["#FFE491", .035, .15]])
	tf.g.position = Vector3(0, .7, 0)
	tf.g.visible = true
	Build.nohit(tf.g)
	torches_carried.append({g = tf.g, fs = tf.fs, L = null, on = true, I = 0.0, i = 9})
	# The warm halo of a burning torch (the candles have the same)
	var halo := Build.glow("#FFB04A", 1.4)
	Build.glow_opacity(halo, .55)
	halo.position = Vector3(0, .8, 0)
	Build.nohit(halo)
	torch.add_child(halo)
	var tl := Build.omni("#FF9A4A", 3.5, 6.0, 1.4)
	tl.position = Vector3(0, .85, 0)
	torch.add_child(tl)
	# Just inside the room, ahead on the left as you come in: the first thing you'd see burning in the dark
	torch.position = Vector3(-1.9, .05, .9)
	torch.rotation.z = .25
	for i in 3:
		kk.call("rubble_half", Vector3(-1.9 + (Build.rnd() - .5) * .5, 0, .9 + (Build.rnd() - .5) * .5), Build.rnd() * TAU, .12)
	# The way out: steps up toward daylight
	steps = Build.group(self, "way")
	for i in 4:
		Build.mesh(Build.box(2.2, .2 + i * .22, .5), stone("#6E6876"), 0, (.2 + i * .22) / 2, 4.35 + i * .5, steps)
	var day := Build.glow("#DDEBFF", 1.2)
	Build.glow_opacity(day, .18)
	day.position = Vector3(0, 1.6, 5.6)
	steps.add_child(day)
	things = [{t = "door", node = door, live = true}, {t = "plateA", node = plates[0].g}, {t = "plateB", node = plates[1].g},
		{t = "ember", node = ember, live = true, carry = true, light = 2.2, hold_scale = .8, hold_y = .1, rest_y = .2},
		{t = "gloom", node = gloom, live = true}, {t = "torch", node = torch, live = true, carry = true, light = 5.5, hold_y = -.25},
		{t = "way", node = steps}]
	solidify()
	settle()
	Build.merge_static(self)
	# Dust turning in the torchlight
	var dust := Build.motes(int(40 * game.quality.fx), Vector3(5.4, 1.4, 4.4), "#FFD9A6", .05, 9.0)
	dust.position = Vector3(0, 1.5, -.5)
	add_child(dust)
	# The shadow is a round lump to the eye: a ball that moves and shrinks with it
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("tag", "gloom")
	var cs := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = .9
	cs.shape = ball
	body.add_child(cs)
	gloom.add_child(body)


func _plate(x: float, z: float, t: String, groove: ShaderMaterial) -> Dictionary:
	var g := Build.group(self, t)
	Build.mesh(Build.cyl(.62, .66, .1, 20), stone("#615B69"), 0, .05, 0, g)
	var top := Build.mesh(Build.cyl(.46, .48, .1, 20), stone("#958D9C"), 0, .13, 0, g)
	# Its ring glows faintly like the door's own rings: the same mark, there to be found in the dark
	var ring_m := Build.smooth("#2B3440", {emissive = "#6BE7FF", ei = .8, unique = true})
	var ring := Build.mesh(Build.torus(.33, .03, 6, 26), ring_m, 0, .185, 0, g)
	ring.rotation.x = -PI / 2
	Build.noshadow(ring)
	# A faint teal haze over it, as over the door's rings: something there, in the dark
	var haze := Build.glow("#6BE7FF", 1.1)
	Build.glow_opacity(haze, .22)
	haze.position = Vector3(0, .35, 0)
	Build.nohit(haze)
	g.add_child(haze)
	g.position = Vector3(x, 0, z)
	return {tag = t, g = g, top = top, ring = ring, ring_m = ring_m, groove = groove, pos = Vector3(x, 0, z), by = null}


func enter(_opts: Dictionary) -> void:
	_up_words()
	game.set_fog(true)
	game.sfx.ambience("cave", -5.0)
	game.set_pal_glow(.16)
	game.stage = stage_saved if stage_saved != "" else "dark"
	if door_open and gloom.visible:
		game.hud.vig_on = true
	game.az = 0.0
	game.pol = .86
	game.az_goal = null
	game.place_party(Vector3(0, 0, 2.5), Vector3(0, 0, -1), Vector2(-.8, 3.45), Vector2(.8, 3.45))
	# Coming in, they look into the room
	for p in game.here():
		if p.position.z > 3.0:
			p.yaw = PI
			p.t_yaw = PI
			p.mode = "stay"


func bounds(p: Vector3, _r: float, is_wisp: bool) -> Vector3:
	if p.z < -4.6:
		p.x = clamp(p.x, -.8, .8)
	p.x = clamp(p.x, -5.75, 5.75)
	var deep := door_open and absf(p.x) < .82
	p.z = clamp(p.z, ((-5.7 if is_wisp else -6.0) if deep else -4.5), 3.8)
	return p


func clamp_cam(want: Vector3) -> Vector3:
	want.x = clamp(want.x, -3.3, 3.3)
	want.z = clamp(want.z, -4.2, 3.0)
	return want


## In the dark, Mo and Bo only see what some light reaches: yours, a light they carry, the torches once lit.
func lit(t: String, c: Vector3) -> bool:
	if torches_on:
		return true
	if t in ["you", "door", "gloom", "torch", "way"]:
		return true
	if t == "ember":
		return door_open
	if Vector2(c.x - game.wisp_g.x, c.z - game.wisp_g.z).length() < game.light_now:
		return true
	if lit_by_lights(c):
		return true
	return door_open and Vector2(c.x, c.z + 6.45).length() < 2.4


func surface(_x: float, _z: float) -> String:
	return "stone"


func underfoot(_at: Vector3) -> String:
	return "cold stone underfoot"


func touch_at(at: Vector3, r: float) -> String:
	for o in obstacles:
		if Vector2(at.x - o[0], at.z - o[1]).length() < o[2] + r + .05:
			return super.touch_at(at, r)
	return "you bumped into cold stone: a wall"


## Torches once they're lit, and the shadow while it's out.
func sounds_around(p: Pal) -> Array:
	var out := []
	if torches_on and torches.size():
		var near: Dictionary = torches[0]
		for T in torches:
			if T.g.global_position.distance_to(p.position) < near.g.global_position.distance_to(p.position):
				near = T
		out.append([near.g.global_position, "torches hissing and crackling", 10.0])
	if gloom.visible:
		out.append([gloom.global_position, "a low, cold hiss", 14.0])
	return out


func way_sound(t: String) -> String:
	return "footsteps on stone steps" if t == "way" else super.way_sound(t)


## Under the hill it's dark (day or night) and cold, until the torches are lit.
func ambient_light() -> float:
	return .9 if torches_on else 0.0


func chill() -> float:
	return .25 if torches_on else .45


func too_dark() -> bool:
	return not torches_on


func say_of(t: String) -> String:
	match t:
		"door":
			if door_open:
				return "the big stone door, slid open for good (it stays open now, nobody needs to hold the plates); a warm glow behind it"
			var lit_n := plates.filter(func(P): return P.by != null).size()
			return "a big stone door, shut, with two rings carved on it (%s); a groove runs down from each ring and off along the floor, one to the left and one to the right, into the dark" % ["both dark", "one glowing", "both glowing"][lit_n]
		"plateA", "plateB":
			var P: Dictionary = plates[0] if t == "plateA" else plates[1]
			if P.by:
				return "a stone plate in the floor, held down by %s, its ring glowing" % P.by.pal_name
			return "a stone plate in the floor with a ring carved on it, like the ones on the big door"
		"ember":
			return "a glowing ember on a stone stand"
		"gloom":
			return "a shadow with glowing eyes; it shrinks from light"
		"torch":
			return "a burning torch"
		"way":
			return "the steps back up to the island"
	return said.get(t, "")


func noticed(seen: Dictionary) -> void:
	for P in plates:
		if seen.has(P.tag):
			spotted[P.tag] = true


# ---------- For Mo's and Bo's minds ----------

func place_of(p: Vector3) -> String:
	var where := "in the dungeon under the hill"
	if p.z < -5.0:
		where += ", in the little room behind the big door"
	elif p.z < -3.2:
		where += ", by the big stone door"
	elif p.z > 2.0:
		where += ", near the way in"
	return where


func region() -> String:
	return "in the dungeon under the hill"


func scenery(p: Vector3) -> Array:
	if torches_on:
		return ["torches burning on the walls", "stone pillars"]
	var near_light := false
	for L in lights():
		if Vector2(L[0].x - p.x, L[0].z - p.z).length() < 2.0:
			near_light = true
	if near_light:
		return ["the light lets you see a few metres; beyond it, darkness: there could be anything out there", "stone floor"]
	return ["darkness all round: you only see what some light reaches", "stone floor"]


func remarkable(t: String) -> bool:
	return t != "door" or not door_open


func use_reach(t: String) -> float:
	if t == "plateA" or t == "plateB":
		return 0.0
	if t == "ember" or t == "torch":
		return .6
	if t == "gloom":
		return 1.3
	return -1.0


func way(t: String) -> Dictionary:
	if t == "way":
		return {to = "isle", opts = {back = true}}
	return {}


func way_hint(t: String) -> String:
	if t == "way":
		return "looked up: daylight at the top. I could go up them"
	return super.way_hint(t)


## How far from a plate's middle your feet are still on it.
const ON_PLATE := .5


## Moving off a plate lets it up again (until the door has opened). Only once they've stepped off it: standing
## there doing something else, it stays down.
func released(p: Pal) -> void:
	for P in plates:
		if P.by == p and Vector2(p.position.x - P.pos.x, p.position.z - P.pos.z).length() > ON_PLATE:
			P.by = null
			p.plate = null
			if not door_open:
				_press(P, 0.0)
				game.hearing.make(P.pos, id, "stone grinding back up", 25.0)
				game.minds.changed()


## Stepping onto a plate (walking over it, or meaning to stand on it) presses it down, whoever it is. Returns
## what it was like, in their words.
func _step_on(P: Dictionary, p: Pal) -> String:
	P.by = p
	p.plate = P
	p.sq = 1
	game.sfx.play_any("impactSoft_heavy", 3, P.pos, -2.0, .7)
	game.hearing.make(P.pos, id, "a heavy stone click", 30.0, p)
	_press(P, 1.0)
	game.minds.changed()
	if plates.all(func(q): return q.by != null) and not door_open:
		# Both of them, one on each: they did it together
		var a: Pal = plates[0].by
		var b: Pal = plates[1].by
		if a != b:
			game.minds.of(a).heart.shared(b.id, "the time you two opened the big stone door together", game.minds.of(a).mem.life_h)
			game.minds.of(b).heart.shared(a.id, "the time you two opened the big stone door together", game.minds.of(b).mem.life_h)
		_open_door()
		return "it sank under my feet with a heavy click, and a deep grinding of stone started up ahead"
	return "it sank under my feet with a heavy click, and one of the two glowing rings up ahead lit up bright; the other stayed dull. It feels like it would rise again if I stepped off"


## Feet on the plates: whoever steps on one presses it, and stepping off lets it up.
func _feet() -> void:
	for P in plates:
		var on: Pal = null
		for p in game.here():
			if Vector2(p.position.x - P.pos.x, p.position.z - P.pos.z).length() < ON_PLATE:
				on = p
		if P.by != null and P.by != on:
			released(P.by)
		if P.by == null and on != null and not door_open:
			var m: Mind = game.minds.of(on)
			var meant: bool = m.task.get("act", "") == "use" and m.task.get("t", "") == P.tag
			_step_on(P, on)
			if not meant:
				# Walking over it: they feel it go (what else happened, they'd hear or see)
				m.touch("the stone under your feet sank with a heavy click")


func taken(T: Dictionary) -> void:
	super.taken(T)
	if T.t == "ember":
		Build.set_light(ember_light, 2.5)
		if game.stage == "ember":
			game.stage = "exit"


func use(p: Pal, t: String) -> String:
	match t:
		"plateA", "plateB":
			var P: Dictionary = plates[0] if t == "plateA" else plates[1]
			if P.by and P.by != p:
				return "someone is already standing on it"
			if door_open:
				return "stood on it; nothing happens"
			if P.by == p:
				# Pressed as they stepped onto it
				var lit_n := plates.filter(func(q): return q.by != null).size()
				return "stood on it: it sank under my feet with a heavy click, and %s" % ("a deep grinding of stone started up ahead" if lit_n == 2 or door_open or game.stage == "opening" else "one of the two glowing rings up ahead lit up bright; the other stayed dull. It feels like it would rise again if I stepped off")
			return "stood on it: " + _step_on(P, p)
		"door":
			if door_open:
				return "looked through it: there's a little room behind"
			p._gesture("point")
			return "pushed and pulled it: heavy stone, it won't budge"
		"gloom":
			if not gloom.visible:
				return "there's nothing there now"
			if p.held and p.held.get("light", 0.0) > 0:
				p._gesture("point")
				var t0 := Time.get_ticks_msec()
				while gloom.visible and Time.get_ticks_msec() - t0 < 4000:
					p.face(gloom.position)
					await get_tree().process_frame
				return ("pushed %s at it: it shrank back from the light, hissing" % p.held.get("what", "my light")) if gloom.visible else "kept the light on it until it burst and was gone"
			p.recoil = 2
			p.bounce()
			return "went at it with nothing in my hands: it loomed up, cold, and I jumped back"
		"way":
			return ""
	return await super.use(p, t)


func _press(P: Dictionary, to: float) -> void:
	var from: float = P.get("k", 0.0)
	P.k = to
	var press := func(k):
		var v: float = lerp(from, to, k)
		P.top.position.y = .13 - .06 * v
		P.ring.position.y = .185 - .06 * v
		Build.set_glow(P.ring_m, .8 + 1.6 * v)
		Build.set_glow(P.groove, .3 + 1.2 * v)
	game.tween(.26, press)


## Both plates held: the door rises, and what was behind it comes out. Nobody's stopped to watch.
func _open_door() -> void:
	game.stage = "opening"
	game.shake = .1
	Build.set_glow(seal_m, 2.5)
	game.sfx.play("doorOpen_1", door.global_position, -2.0, .6)
	var lift := func(k):
		slab.position.y = 1.3 - 2.8 * Game.ease_io(k)
		Build.set_light(ember_light, 5 * k)
	game.hearing.make(door.global_position, id, "a long, deep grinding of stone", 70.0)
	await game.tween(2.6, lift)
	door_open = true
	game.shake = 0
	game.hearing.make(door.global_position, id, "a deep thud of stone", 70.0)
	game.minds.changed()
	gloom.visible = true
	gloom.position = Vector3(0, .95, -6.3)
	gloom_s = .25
	game.hud.vig_on = true
	var creep := func(k):
		gloom.position.z = -6.3 + 2.9 * Game.ease_io(k)
		gloom_s = .25 + .75 * k
	await game.tween(1.7, creep)
	game.hearing.make(gloom.global_position, id, "a low, cold hiss", 25.0)
	for p in game.here():
		if p.position.distance_to(gloom.position) < 8.0:
			game.minds.of(p).touch("a cold draught on your skin")
	game.stage = "gloom"
	gloom_idle = 0


func _struck(strength: float) -> void:
	flash = 1.0
	flinch = 1.0
	game.hit(gloom.global_position, strength)


## Dashing through the shadow is the big hit.
func on_dash() -> void:
	if game.stage != "gloom" or not gloom.visible:
		return
	var g := gloom.position
	if Vector2(g.x - game.wisp_g.x, g.z - game.wisp_g.z).length() < 2.6:
		gloom_s -= .2
		_struck(3.0)


func pop_gloom() -> void:
	game.sfx.play("impactBell_heavy_000", gloom.global_position, 0.0, .8)
	Input.vibrate_handheld(140)
	game.stage = "won"
	game.burst(gloom.position, "#C9B8FF")
	gloom.visible = false
	game.hud.vig_on = false
	game.wisp_flare = 1
	game.hearing.make(gloom.global_position, id, "a sharp hiss and a pop, then a whoosh of flames all round", 40.0)
	game.minds.changed()
	for T in torches:
		T.g.visible = true
		T.on = true
		await game.wait(.24)
	torches_on = true
	game.stage = "ember" if ember.get_parent() == self else "exit"


# ---------- Every frame ----------

func tick(dt: float, t: float) -> void:
	torch_t += ((1.0 if torches_on else 0.0) - torch_t) * min(1, dt * 1.2)
	game.set_hemi(CAVE.sky.lerp(CAVE.warm, torch_t), CAVE.gnd, lerp(.1, .5, torch_t))
	Build.set_light(game.wisp_light, (5 + game.light_now * 2.2) * (1 + game.wisp_flare))
	game.wisp_light.omni_range = game.light_now * 2.4
	for T in torches:
		Build.flicker(T, t, dt)
		T.I += ((7 + sin(t * 15 + T.i) * .8 if T.on else 0.0) - T.I) * min(1, dt * 4)
		Build.set_light(T.L, T.I)
	for T in torches_carried:
		Build.flicker(T, t, dt)
	# A lantern brought down from the village shines properly in here
	for p in [game.mo, game.bo]:
		if p.held and p.held.t == "lantern":
			for L in p.held.node.find_children("*", "OmniLight3D", true, false):
				Build.set_light(L, 3.0)
				L.omni_range = 5.0
	ember.rotation.y += dt * 1.2
	if gloom.visible:
		_gloom(dt)
	if game.stage == "dark":
		_notice()
	_feet()


## How strongly light reaches the shadow now: your light, and any they carry.
func _light_on_gloom(g: Vector3) -> bool:
	if Vector2(g.x - game.wisp_g.x, g.z - game.wisp_g.z).length() < game.light_now * .8:
		return true
	for L in lights():
		if L[0].distance_to(g) < 2.6 and L[1] >= 2.0 and Vector2(L[0].x - g.x, L[0].z - g.z).length() < 2.4:
			return true
	return false


func _gloom(dt: float) -> void:
	gloom_t += dt
	for m in puffs:
		var a: float = m.get_meta("a") + gloom_t * m.get_meta("s")
		var r: float = m.get_meta("r")
		m.position = Vector3(cos(a) * r, sin(gloom_t * 2 + a) * .16, sin(a) * r * .8)
	if game.stage == "gloom":
		var g := gloom.position
		# What it backs away from: the nearest light
		var away := Vector3()
		if _light_on_gloom(g):
			gloom_s -= dt * .3
			hit_t -= dt
			if hit_t <= 0:
				hit_t = .32
				_struck(1.0)
			var src := game.wisp_g
			var best := Vector2(g.x - src.x, g.z - src.z).length()
			for L in lights():
				var d := Vector2(g.x - L[0].x, g.z - L[0].z).length()
				if d < best:
					best = d
					src = L[0]
			away = Vector3(g.x - src.x, 0, g.z - src.z).normalized()
			g += away * 1.1 * dt
			gloom_idle = 0
			for e in g_eyes:
				e.scale.y += (.18 - e.scale.y) * min(1, dt * 10)
		else:
			# Left alone, it grows back and creeps toward Mo or Bo
			gloom_s = min(1, gloom_s + dt * .05)
			gloom_idle += dt
			var h: Array = game.here()
			var near: Pal = null
			for q in h:
				if near == null or q.position.distance_to(g) < near.position.distance_to(g):
					near = q
			if near == null:
				near = game.mo
			var px := near.position.x - g.x
			var pz := near.position.z - g.z
			var pl := sqrt(px * px + pz * pz)
			if pl == 0:
				pl = 1
			if pl > .7:
				g.x += px / pl * .55 * dt
				g.z += pz / pl * .55 * dt
			for e in g_eyes:
				e.scale.y += (.6 - e.scale.y) * min(1, dt * 6)
		g.x = clamp(g.x, -5.2, 5.2)
		g.z = clamp(g.z, -4.1, 3.4)
		for q in PILLARS:
			var ox: float = g.x - q[0]
			var oz: float = g.z - q[1]
			var d := sqrt(ox * ox + oz * oz)
			if d < 1 and d > 1e-3:
				g.x = q[0] + ox / d
				g.z = q[1] + oz / d
		gloom.position = g
		gloom.rotation.y = atan2(-(g.x - game.wisp_g.x), -(g.z - game.wisp_g.z))
		for p in game.here():
			if p.recoil <= 0 and p.position.distance_to(Vector3(g.x, 0, g.z)) < .95:
				p.recoil = 3
				p.bounce()
				game.minds.of(p).touch("something cold lunged at you and you jumped back")
		if gloom_s < .3:
			pop_gloom()
	gloom.position.y = .95 + sin(gloom_t * 2) * .08
	flash = max(0.0, flash - dt * 6.0)
	flinch = max(0.0, flinch - dt * 5.0)
	Build.set_glow(gloom_m, .8 + flash * 6.0)
	gloom.scale = Vector3.ONE * max(.01, gloom_s * (1 + sin(gloom_t * 5) * .04) * (1.0 - .18 * flinch))


## Light catching something new makes Mo or Bo turn and look at it.
func _notice() -> void:
	var space := get_world_3d().direct_space_state
	for p in game.here():
		if p.mode == "script" or p.look_t > 0 or p.path != null:
			continue
		for P in plates:
			if P.by or p.knows(game.key(P.tag)):
				continue
			var c: Vector3 = P.pos + Vector3(0, .15, 0)
			if not lit(P.tag, c):
				continue
			var eye: Vector3 = p.eye_world()
			var dir := c - eye
			var dist := dir.length()
			var hit: Dictionary = game.ray(space, eye, dir / dist * (dist + .4), p.body.get_rid())
			if not hit.is_empty() and hit.tag != P.tag and hit.distance < dist - .3:
				continue
			p.look = P.pos
			p.look_t = 2.5
			p.gaze = P.pos
			break
