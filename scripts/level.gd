class_name Level
extends Node3D
## A place you can be: an island, a dungeon. Each is its own scene with its own puzzle.
## The game keeps you, Mo and Bo, the camera and the HUD; a level brings the ground,
## what there is to see, where you can walk, how it's lit, and what you can ask for there.

const WORLD_LAYER := 1

## Set by the game before the level enters the tree.
var game: Game
## A short id ("isle", "cave"), used to remember what Mo and Bo have seen here.
var id := ""
## Things Mo and Bo can see: {t, node, live, hi}. Each gets a box in the corner view.
var things: Array = []
## [x, z, radius, low]: round things to go around. You float over the low ones.
var obstacles: Array = []
## Camera: how far it sits, and how far you can swing it (0 means all the way round).
var cam_dist := 12.0
var az_limit := 0.0
## The HUD's look: "day" or "cave".
var theme := "day"
## Darker places shrink your glow to the reach of your light.
var dark := false
## Under the sky (the time of day shows), or not
var outdoors := false
## Outdoors the camera follows behind the light; indoors it holds the room's view.
var follow := false
## How fast the light moves (m/s) and how wide the camera sees (vertical degrees).
var speed := 2.8
var fov := 38.0

## What the corner view calls things.
var names := {door = "door", mo = "Mo", bo = "Bo", you = "you", nell = "Nell", tam = "Tam", odo = "Odo"}
## How Mo and Bo say them out loud.
var said := {}
## What they call them when they mean to do something with them (mind.gd), whatever state they're in
var labels := {}
## Where you stand aside, indoors, when you're leaving it to them (INF: nowhere in particular)
var idle_spot := Vector3.INF
## Places they know by name and can head for, even out of sight: name -> where
var places := {}
## Other words for places they know ("stairs": the way back up), as a word in what they call it
var place_words := {}
## Where they look on getting to a place (what they went there for): name -> where
var place_looks := {}
## Where the story was here when everyone left, and how often they've come back
var stage_saved := ""
var visits := 0


## Called once the level is in the tree, with whatever the way in passed along.
func enter(_opts: Dictionary) -> void:
	pass


## Every frame, before Mo and Bo look around.
func tick(_dt: float, _t: float) -> void:
	pass


## Every frame, after Mo and Bo looked (and learned).
func after_senses() -> void:
	pass


## Can a character see this here? The dark hides things your light doesn't reach.
func lit(_t: String, _c: Vector3) -> bool:
	return true


## Mo or Bo just looked all the way round and saw these.
func noticed(_seen: Dictionary) -> void:
	pass


## Is some of it out of reach of any light right now?
func too_dark() -> bool:
	return false


func say_of(t: String) -> String:
	return said.get(t, "")


# ---------- What Mo and Bo can do here (mind.gd) ----------
#
# Things are {t, node, live?, hi?} plus, for them: carry (they can pick it up), light (how far it lights the
# dark, in metres, carried or not) and held (who has it). use() is what doing something with a thing does: the
# level decides, and says what happened, which goes into their memory.

## What they call a thing when they mean to do something with it: short, and the same whatever its state.
func label_of(t: String) -> String:
	return labels.get(t, say_of(t))


## Someone stopped what they were doing (a plate they stood on rises again).
func released(_p: Pal) -> void:
	pass


## Where a point is, as they'd put it.
func place_of(_p: Vector3) -> String:
	return ""


## The place as a whole ("on the island").
func region() -> String:
	return ""


## What's around them that isn't a thing to point at (the sea, the trees), as lines for the model.
func scenery(_p: Vector3) -> Array:
	return []


func thing(t: String) -> Dictionary:
	for T in things:
		if T.t == t:
			return T
	return {}


## Where a thing is, on the ground.
func thing_pos(t: String) -> Vector3:
	var T := thing(t)
	if T.is_empty():
		return Vector3()
	var b: AABB = T.box if T.has("box") and not T.get("live", false) else Level.box_of(T.node)
	var c := b.get_center()
	return Vector3(c.x, ground(c.x, c.z), c.z)


## Is this worth a word when first seen?
func remarkable(_t: String) -> bool:
	return true


## Lights that go about with Mo and Bo (a torch, the lantern, the ember): [[where, how far], ...]
func lights() -> Array:
	var out := []
	for p in game.people():
		if p.place_id == id and p.held and p.held.get("light", 0.0) > 0:
			out.append([p.global_position + Vector3(0, 1, 0), float(p.held.light)])
	for T in things:
		if T.get("light", 0.0) > 0:
			out.append([T.node.global_position, float(T.light)])
	return out


# ---------- What a body feels here (body.gd) ----------

## Light from the sky (or none), 0 to 1, before any lamp or fire.
func ambient_light() -> float:
	return 1.0


## How cold the air is here, 0 to 1.
func chill() -> float:
	return 0.0


## Every light here: what they carry, things that glow, your lantern, and the level's own (fires, windows).
func light_spots() -> Array:
	var out := lights()
	if game.level == self:
		out.append([game.wisp.global_position, maxf(2.5, game.light_now)])
	return out


## How much light there is at a spot, 0 (pitch dark) to 1 (broad day).
func light_at(at: Vector3) -> float:
	var l := ambient_light()
	if not is_inside_tree() or l >= .8:
		# Nobody's watching here: the sky's light will do (and no lamp outshines the day)
		return l
	for L in _spots_now():
		var d := Vector2(at.x - L[0].x, at.z - L[0].z).length()
		l = maxf(l, smoothstep(float(L[1]), float(L[1]) * .3, d) * .8)
	return l


## light_spots(), worked out once a frame (light_at() asks for every thing there is to see)
var _spots_frame := -1
var _spots := []


func _spots_now() -> Array:
	var f := Engine.get_process_frames()
	if f != _spots_frame:
		_spots_frame = f
		_spots = light_spots()
	return _spots


## Warmth at a spot from a fire, 0 to 1.
func warmth_at(_at: Vector3) -> float:
	return 0.0


## What's around someone, for their body.
func surroundings(p: Pal) -> Body.Ctx:
	var c := Body.Ctx.new()
	c.moving = p.pace > .3
	if p.inside != "":
		c.light = .6
		c.warmth = 1.0
		c.chill = chill()
		c.company = true
		return c
	c.light = light_at(p.position)
	c.chill = chill()
	c.warmth = warmth_at(p.position)
	c.in_water = in_water(p.position)
	c.company = game.people().any(func(o): return o != p and o.place_id == p.place_id and o.inside == "" and o.position.distance_to(p.position) < 7.0)
	if game.level == self and game.wisp_g.distance_to(p.position) < 7.0:
		c.company = true
	return c


## Eat at a thing (the larder in a house): {food: how filling, said: what happened, in their words}; empty if
## there's nothing to eat there.
func eat_at(_p: Pal, _t: String) -> Dictionary:
	return {}


## Somewhere indoors to go into for a sleep or a meal (a house): its door, or empty.
func shelter(_t: String) -> Dictionary:
	return {}


## A new day (morning): what grows back, grows back.
func new_day() -> void:
	pass


# ---------- What a body hears and touches here (hearing.gd, mind.gd) ----------

## Where the way to another place is here (sounds from there come through it), or INF if there's none.
func way_to(other_id: String) -> Vector3:
	for T in things:
		var w := way(T.t)
		if not w.is_empty() and w.to == other_id:
			return thing_pos(T.t) + Vector3(0, 1, 0)
	return Vector3.INF


## What can be heard going on here, wherever you are: [[where, what it sounds like, how far it carries], ...].
func sounds_around(_p: Pal) -> Array:
	return []


## What's under someone's feet, as it feels.
func underfoot(_at: Vector3) -> String:
	return ""


## Standing in water here (it wets your feet)?
func in_water(_at: Vector3) -> bool:
	return false


## What someone going through a way here sounds like.
func way_sound(_t: String) -> String:
	return "footsteps going away"


## What stopped someone at `at` (they walked into it), as it feels.
func touch_at(at: Vector3, r: float) -> String:
	for o in obstacles:
		if Vector2(at.x - o[0], at.z - o[1]).length() < o[2] + r + .05:
			return "you stumbled against something low" if o.size() > 3 and o[3] else "you bumped into something hard"
	return "something stopped you going any further"


func lit_by_lights(c: Vector3) -> bool:
	for L in lights():
		if Vector2(c.x - L[0].x, c.z - L[0].z).length() < L[1]:
			return true
	return false


## Somewhere to wander to on their own: a thing they've seen here and haven't been to lately, or a spot
## nearby. {at, stand, what, tag?}; empty for nowhere.
func spot_for(m: Mind) -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var best := {}
	var bs := -1e9
	for T in things:
		var t: String = T.t
		if now - float(m.visited.get(t, -1e9)) < 90.0:
			continue
		var at := thing_pos(t)
		var d := Vector2(at.x - m.pal.position.x, at.z - m.pal.position.z).length()
		if d > 30.0:
			continue
		var sc := randf() * 4.0 - d * .2
		if sc > bs:
			bs = sc
			best = spot_at(t, m)
	if not best.is_empty() and randf() < .6:
		return best
	for i in 12:
		var a := randf() * TAU
		var r := randf_range(3.0, 12.0)
		var at := Vector3(m.pal.position.x + cos(a) * r, 0, m.pal.position.z + sin(a) * r)
		if walkable(at):
			at.y = ground(at.x, at.z)
			return {at = at, stand = at, what = "what's over there"}
	return best


## Where to stand to reach a thing (r: how close).
func spot_at(t: String, m: Mind, r := -1.0) -> Dictionary:
	var T := thing(t)
	if T.is_empty() or m == null:
		return {}
	var at := thing_pos(t)
	var b: AABB = Level.box_of(T.node)
	if r < 0:
		r = max(b.size.x, b.size.z) * .5 + .55
	var from := m.pal.position - at
	from.y = 0
	var dir := from.normalized() if from.length() > .01 else Vector3(0, 0, 1)
	var stand := collide(at + dir * r, .34, false)
	return {at = at, stand = stand, what = say_of(t), tag = t}


func walkable(p: Vector3) -> bool:
	return collide(p, .34, false).distance_to(p) < .05


## How close to stand to use a thing (plates: on it).
func use_reach(_t: String) -> float:
	return -1.0


## Doing something with a thing: returns what happened, in their words for memory ("" for nothing much).
## It may take a while (it's awaited).
func use(p: Pal, t: String) -> String:
	p._gesture("point")
	return "touched it; nothing happened"


## Picking a thing up: false (and why, in p.why_not) when it can't be.
func can_carry(t: String) -> bool:
	return thing(t).get("carry", false)


## Can it be eaten as it is (an apple)? How filling it is, or 0.
func edible(t: String) -> float:
	return float(thing(t).get("food", 0.0))


## Took a thing off the ground (the pal holds it now).
func taken(T: Dictionary) -> void:
	things.erase(T)


## Put a thing down here.
func put_down(T: Dictionary, at: Vector3) -> void:
	T.node.reparent(self, true)
	T.node.global_position = Vector3(at.x, ground(at.x, at.z) + T.get("rest_y", 0.0), at.z)
	T.node.rotation = Vector3.ZERO
	T.erase("box")
	if not things.has(T):
		things.append(T)


## The way somewhere else, if this thing is one: {to, opts}; empty if not.
func way(_t: String) -> Dictionary:
	return {}


## Where someone comes out, coming back from another place through this place's way to it.
func arrival_from(other_id: String) -> Vector3:
	for T in things:
		var w := way(T.t)
		if not w.is_empty() and w.to == other_id:
			var at := thing_pos(T.t)
			var back := (Vector3(game.wisp_g.x, 0, game.wisp_g.z) - at)
			back.y = 0
			return collide(at + back.normalized() * 1.6, .34, false)
	return game.wisp_g


## The opts for going to another place from here (the way that leads there).
func way_opts_to(other_id: String) -> Dictionary:
	for T in things:
		var w := way(T.t)
		if not w.is_empty() and w.to == other_id:
			return w.opts
	return {}


## Whether using this way takes you through it (a door you push open), or only looks (stairs: "enter" to go).
func through_by_use(_t: String) -> bool:
	return false


## What they find when they try a way (before going through it).
func way_hint(t: String) -> String:
	return "it leads somewhere else; I could go into it"


## Keep a point inside the level, out of the obstacles.
func collide(p: Vector3, r: float, is_wisp: bool) -> Vector3:
	if _grid_n != obstacles.size() or not is_same(_grid_of, obstacles):
		_build_grid()
	for o in _grid.get(Vector2i(floori(p.x / CELL), floori(p.z / CELL)), []):
		if is_wisp and o.size() > 3 and o[3]:
			continue
		var dx: float = p.x - o[0]
		var dz: float = p.z - o[1]
		var d := sqrt(dx * dx + dz * dz)
		var m: float = o[2] + r
		if d < m and d > 1e-4:
			p.x = o[0] + dx / d * m
			p.z = o[1] + dz / d * m
	return bounds(p, r, is_wisp)


## The obstacles by where they are (squares CELL wide): each in every square within a metre of it, so a
## point only needs those in its own square (radii up to a metre). Made again when the obstacles change.
const CELL := 8.0
var _grid := {}
var _grid_n := -1
var _grid_of = null


func _build_grid() -> void:
	_grid = {}
	_grid_n = obstacles.size()
	_grid_of = obstacles
	for o in obstacles:
		var reach: float = float(o[2]) + 1.0
		for cx in range(floori((o[0] - reach) / CELL), floori((o[0] + reach) / CELL) + 1):
			for cz in range(floori((o[1] - reach) / CELL), floori((o[1] + reach) / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not _grid.has(k):
					_grid[k] = []
				_grid[k].append(o)


## The height of the ground at (x, z).
func ground(_x: float, _z: float) -> float:
	return 0.0


func bounds(p: Vector3, _r: float, _is_wisp: bool) -> Vector3:
	return p


func clamp_cam(want: Vector3) -> Vector3:
	return want


## Solid things the camera may look through (what's cut away for you), as physics RIDs.
func cam_exclude() -> Array:
	return []


## Give every solid mesh a collider so Mo and Bo can't see through things.
## Each tagged group (and anything marked "body") gets its own, so it moves and hides with it.
func solidify() -> void:
	var groups := {}
	_collect(self, self, groups)
	for owner_node in groups:
		var inv: Transform3D = owner_node.global_transform.affine_inverse()
		var faces := PackedVector3Array()
		for mi in groups[owner_node]:
			var xf: Transform3D = inv * mi.global_transform
			for f in mi.mesh.get_faces():
				faces.append(xf * f)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		body.set_meta("tag", Build.tag_of(owner_node))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		owner_node.add_child(body)


func _collect(node: Node, owner_node: Node, groups: Dictionary) -> void:
	for child in node.get_children():
		if child.has_meta("nohit"):
			continue
		var o := owner_node
		if child.has_meta("tag") or child.has_meta("body"):
			o = child
		if child is MeshInstance3D:
			if not groups.has(o):
				groups[o] = []
			groups[o].append(child)
		_collect(child, o, groups)


## Something you can carry gets a small solid volume where you'd see it (a flame, a lantern's glass), so
## a look at it lands on it rather than passing through to whatever's behind.
func grab_volume(T: Dictionary) -> void:
	var n: Node3D = T.node
	var b := Level.box_of(n)
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("tag", T.t)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = clampf(maxf(b.size.x, b.size.y) * .5, .2, .45)
	cs.shape = sh
	body.add_child(cs)
	n.add_child(body)
	body.global_position = b.get_center() + Vector3(0, b.size.y * .15, 0)


## Work out where the still things are, once.
func settle() -> void:
	for T in things:
		T.box = Level.box_of(T.node)
		if T.get("carry", false):
			grab_volume(T)


## The solid part of a thing: glows and flames (not solid) left out, so a torch is its stick and flame,
## not its halo. (A thing that's all glow keeps its glow.)
static func box_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var glow := AABB()
	var any_glow := false
	var stack := [n]
	while stack.size():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and c.mesh:
			var b: AABB = c.global_transform * c.get_aabb()
			var m = c.material_override
			if m is ShaderMaterial and (m as ShaderMaterial).shader == Build.GLOW:
				glow = b if not any_glow else glow.merge(b)
				any_glow = true
			else:
				box = b if first else box.merge(b)
				first = false
		for k in c.get_children():
			if k != n and k.has_meta("nohit") and not (k is MeshInstance3D):
				continue
			stack.append(k)
	return glow if first and any_glow else box
