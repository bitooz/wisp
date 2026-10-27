class_name Hearing
extends RefCounted
## What Mo and Bo hear: sounds in the world reach each of them as they'd hear them, from a direction (as they're
## looking now), roughly how far, and muffled when something solid is in between, when they're indoors, or when
## the sound's in another place (it comes through the way between, from that way's direction). A sound that's
## too far off for its loudness isn't heard at all. Sounds are described as sounds ("a heavy door creaking"),
## never as the thing that made them: what it was, they'd have to go and see.
##
## make(): a sound that happens once (a door, a splash, a voice). around(): what they can hear going on (a fire
## crackling, waves, someone's footsteps), for how they feel. Both work out the same way (heard()).

## How much of a sound gets through something solid, or between places
const MUFFLE := .4

var game: Game


func _init(g: Game) -> void:
	game = g


## A sound at `at` in place `place`, carrying `reach` metres in the open. `source`: who or what made it (they
## don't hear themselves as a sound). Each who hears it remembers it and, if it's loud enough to notice, thinks.
func make(at: Vector3, place: String, sound: String, reach: float, source: Node = null) -> void:
	for m in game.minds.all():
		if source != null and source == m.pal:
			continue
		var h := heard(m.pal, at, place, reach, source)
		if not h.is_empty():
			m.hear("%s, %s" % [sound, h.words], h.level, h)


## How a sound reaches someone: {level (0 to 1), words ("behind you, close by"), muffled, from (where it seems
## to come from), angle (radians from where they look; + is to their left)}; empty if they can't hear it.
func heard(p: Pal, at: Vector3, place: String, reach: float, source: Node = null) -> Dictionary:
	var ears := p.eye_world()
	var from := at
	var d := 0.0
	var muffled := p.inside != ""
	if p.place_id == place:
		d = ears.distance_to(at)
		if not muffled and _blocked(at, ears, place, p, source):
			muffled = true
	else:
		# In another place: through the way between, if there is one
		var here: Level = game.levels.get(p.place_id)
		var there: Level = game.levels.get(place)
		if here == null or there == null:
			return {}
		var way_here := here.way_to(place)
		var way_there := there.way_to(p.place_id)
		if way_here == Vector3.INF or way_there == Vector3.INF:
			return {}
		from = way_here
		d = ears.distance_to(way_here) + at.distance_to(way_there)
		muffled = true
	var r := reach * (MUFFLE if muffled else 1.0)
	if d >= r:
		return {}
	var a := angle_to(p, from)
	var words := "%s, %s" % [side(a), far(d)]
	if muffled:
		words = "muffled, " + words
	return {level = 1.0 - d / r, words = words, muffled = muffled, from = from, angle = a, distance = d}


## Something solid between the sound and their ears (walls, the house, a hill)? Only where you are (the rest
## isn't in the world just now).
func _blocked(at: Vector3, ears: Vector3, place: String, p: Pal, source: Node) -> bool:
	var lvl: Level = game.levels.get(place)
	if lvl == null or not lvl.is_inside_tree():
		return false
	var space := lvl.get_world_3d().direct_space_state
	var skip := [p.body.get_rid()]
	if source is Node:
		for b in source.find_children("*", "CollisionObject3D", true, false):
			skip.append(b.get_rid())
		if source is CollisionObject3D:
			skip.append(source.get_rid())
	# From a little above where it is (not from inside whatever made it, or the ground)
	var start := at + Vector3(0, .6, 0)
	var hit := {}
	for i in 4:
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(start, ears, Level.WORLD_LAYER, skip))
		# Small things you could pick up (an axe, an apple) don't stand in a sound's way
		if hit.is_empty() or not (hit.collider is Node) or not lvl.can_carry(String(hit.collider.get_meta("tag", ""))):
			break
		skip.append(hit.rid)
	# Not what made it (right where the sound is), nor right at their ears
	return not hit.is_empty() and hit.position.distance_to(ears) > .3 and hit.position.distance_to(start) > .8


## Which way a point is from where they're looking (radians; + to their left).
static func angle_to(p: Pal, at: Vector3) -> float:
	var f := Eyes.facing(p)
	var d := Vector2(at.x - p.position.x, at.z - p.position.z)
	if d.length() < .01:
		return 0.0
	var fwd := Vector2(sin(f), cos(f))
	var right := Vector2(-cos(f), sin(f))
	return -atan2(d.dot(right), d.dot(fwd))


static func side(a: float) -> String:
	var x := absf(a)
	var lr := "left" if a > 0 else "right"
	if x < .4:
		return "ahead of you"
	if x < 1.15:
		return "ahead on your " + lr
	if x < 2.0:
		return "to your " + lr
	if x < 2.75:
		return "behind you on your " + lr
	return "behind you"


static func far(d: float) -> String:
	if d < 2.0:
		return "right next to you"
	if d < 6.0:
		return "close by"
	if d < 15.0:
		return "a little way off"
	return "far off"


## What they can hear going on around them now (for how they feel): the level's own sounds (a fire, the waves)
## and anyone moving about they can't see.
func around(p: Pal) -> Array:
	var out := []
	var lvl: Level = game.levels.get(p.place_id)
	if lvl == null:
		return out
	for s in lvl.sounds_around(p):
		var h := heard(p, s[0], lvl.id, s[2])
		if not h.is_empty():
			out.append("you can hear %s, %s" % [s[1], h.words])
	# Footsteps of someone you can't see
	var people := game.people().map(func(x): return [x, x.pace > .3]) + [[game.kid, game.moving_now]]
	for q in people:
		var n: Node3D = q[0]
		if n == p or not q[1]:
			continue
		var place: String = game.level.id if n == game.kid else n.place_id
		if n != game.kid and (not n.visible or n.inside != ""):
			continue
		var at: Vector3 = n.global_position
		if place == p.place_id and game.eyes.sees(p, at + Vector3(0, .7, 0), n):
			continue
		var h := heard(p, at, place, 14.0 if lvl.surface(at.x, at.z) == "stone" else 9.0, n)
		if not h.is_empty():
			out.append("you can hear footsteps, %s" % h.words)
	return out
