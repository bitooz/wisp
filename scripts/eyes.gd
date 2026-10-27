class_name Eyes
extends Node
## Sight, the only way Mo and Bo know the world: when one of them thinks, a small picture from their eyes,
## rendered just then (a viewport that's idle the rest of the time). Lit as the world is lit: the dark stays
## dark. Nothing is drawn on it and nothing about what's in it is sent along.
##
## They act by pointing at a spot in that picture; resolve() turns the spot back into a ray from the eye where
## the picture was taken, and says what's there. The game knows what the ray hit, they don't: it only decides
## what's physically possible (a thing can only be picked up if it's there and can be carried).
##
## Other senses go alongside sight: hearing (hearing.gd) and touch and the body (mind.gd, body.gd). What they
## see is only what's in the picture: sees() says whether something would be in it right now (in front, not
## hidden, not lost in the dark), and everything else they'd only know by seeing is gated by it.

const SIZE := Vector2i(448, 252)
const FOV := 60.0
## How far off a point can be and still reach a thing (a share of the picture's width): a hand finds what's
## next to where the eye was looking
const REACH_SLOP := .1

var game: Game
var vp: SubViewport
var cam: Camera3D
## One look at a time: the camera is shared, so a second look waits for the first
var busy := false


func setup(g: Game) -> void:
	game = g
	vp = SubViewport.new()
	vp.size = SIZE
	vp.msaa_3d = Viewport.MSAA_2X
	vp.transparent_bg = true
	vp.world_3d = g.main_vp.find_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = .05
	cam.far = 90
	vp.add_child(cam)
	cam.current = true


## Where p's eyes are and which way they look: {xf, eye}, as a picture taken now would have it. Looking at what
## they just went up to (even down at their feet), where they turned their head, or straight ahead.
static func pose(p: Pal) -> Dictionary:
	var eye := p.eye_world()
	var ahead := Vector3(eye.x + sin(p.yaw), eye.y - .12, eye.z + cos(p.yaw))
	var at = p.gaze
	if at is Vector3 and at.distance_to(eye) < 6.0 and at.distance_to(eye) > .3:
		var to: Vector3 = (at - eye).normalized()
		var flat := Vector2(to.x, to.z).normalized()
		if flat.dot(Vector2(sin(p.yaw), cos(p.yaw))) > .2:
			ahead = eye + to
	var xf := Transform3D(Basis(), eye).looking_at(ahead if absf((ahead - eye).normalized().y) < .99 else ahead + Vector3(0, 0, .01), Vector3.UP)
	return {xf = xf, eye = eye}


## Which way they're looking, flat on the ground (radians, like Pal.yaw).
static func facing(p: Pal) -> float:
	var f: Vector3 = -pose(p).xf.basis.z
	return atan2(f.x, f.z) if Vector2(f.x, f.z).length() > .05 else p.yaw


## Would p see this point now: in the picture, nothing solid in front of it, and some light on it?
## node: what's there (its own body doesn't count as in the way).
func sees(p: Pal, at: Vector3, node: Node = null) -> bool:
	if not p.visible or p.inside != "" or p.closed:
		return false
	var f := pose(p)
	var q := project(f, at)
	if q.x < 0 or q.x > 1 or q.y < 0 or q.y > 1:
		return false
	var lvl: Level = game.levels.get(p.place_id)
	# Sharper eyes (practice in the dark) need less light
	var need := .08
	if game.minds:
		need = game.minds.of(p).skills.dark_need()
	if lvl == null or not lvl.is_inside_tree() or lvl.light_at(at) < need:
		return false
	var skip := [p.body.get_rid()]
	var hit := resolve(f, q.x, q.y, skip)
	if hit.is_empty():
		return true
	if node != null and hit.node is Node and (hit.node == node or node.is_ancestor_of(hit.node)):
		return true
	return hit.distance > f.eye.distance_to(at) - .4


func look(p: Pal) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	while busy:
		await get_tree().process_frame
	busy = true
	var f := pose(p)
	var eye: Vector3 = f.eye
	cam.global_transform = f.xf
	cam.cull_mask = 0xFFFFF & ~(1 << (p.layer_bit - 1))
	cam.environment = game.pip_env
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	# The world comes out see-through where there's only sky: lay it over the sky as the screen shows it
	var world_img := vp.get_texture().get_image()
	world_img.convert(Image.FORMAT_RGBA8)
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var top: Color = game.hud.sky_top()
	var bottom: Color = game.hud.sky_bottom()
	for row in SIZE.y:
		img.fill_rect(Rect2i(0, row, SIZE.x, 1), top.lerp(bottom, float(row) / (SIZE.y - 1)))
	img.blend_rect(world_img, Rect2i(Vector2i.ZERO, SIZE), Vector2i.ZERO)
	img.convert(Image.FORMAT_RGB8)
	var jpg := img.save_jpg_to_buffer(.8)
	busy = false
	return {jpg = Marshalls.raw_to_base64(jpg), bytes = jpg.size(), image = img, xf = cam.global_transform, eye = eye,
		ms = (Time.get_ticks_usec() - t0) / 1000}


## Where a point in a picture (x, y from 0 to 1, from the top left) lands: what a ray from the eye through it
## hits first. {pos, tag, node, distance}; empty if it's only sky.
func resolve(frame: Dictionary, x: float, y: float, skip: Array = []) -> Dictionary:
	var xf: Transform3D = frame.xf
	var from := xf.origin
	var along := (xf.basis * _dir(x, y)) * 90.0
	var space := game.world.get_world_3d().direct_space_state
	var ex := skip.duplicate()
	for i in 8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + along, 0xFFFFFFFF, ex))
		if hit.is_empty():
			return {}
		var body = hit.collider
		if not (body is Node):
			return {pos = hit.position, tag = "", node = null, distance = from.distance_to(hit.position)}
		var holder: Node = body.get_parent()
		if (holder is Node3D and not holder.is_visible_in_tree()) or body.collision_layer == 0:
			ex.append(hit.rid)
			continue
		return {pos = hit.position, tag = String(body.get_meta("tag", "")), node = body, distance = from.distance_to(hit.position)}
	return {}


## The thing a hand would find at a point: what the ray hit, or else the nearest thing (wanted() true) that
## was in the picture right next to the point and not hidden behind something. "" if none.
func reach(frame: Dictionary, x: float, y: float, wanted: Callable, skip: Array = []) -> String:
	var hit := resolve(frame, x, y, skip)
	var best := ""
	var bd := REACH_SLOP
	for T in game.level.things:
		if not wanted.call(T.t) or not T.node.is_visible_in_tree():
			continue
		var bx := Level.box_of(T.node)
		var c := bx.get_center()
		# Its middle, its top (a flame above a torch) or its foot: whichever the point is nearest
		var d := 1e9
		for at in [c, Vector3(c.x, bx.end.y + .15, c.z), Vector3(c.x, bx.position.y, c.z)]:
			var q := project(frame, at)
			if q.x >= 0:
				d = minf(d, Vector2((q.x - x) * float(SIZE.x) / SIZE.y, q.y - y).length() * float(SIZE.y) / SIZE.x)
		if d < bd:
			# Only if nothing stands in between
			var qc := project(frame, c)
			var h := resolve(frame, qc.x, qc.y, skip) if qc.x >= 0 else {}
			if h.get("tag", "") == T.t or h.is_empty() or h.distance > frame.eye.distance_to(c) - .5:
				bd = d
				best = T.t
	# What the eye's ray landed on, unless something wanted is right there and nearer
	if hit.get("tag", "") != "" and wanted.call(hit.tag):
		if best == "" or best == hit.tag:
			return hit.tag
		if frame.eye.distance_to(Level.box_of(game.level.thing(best).node).get_center()) > hit.distance - 1.0:
			return hit.tag
	return best


## Where a world point shows in a picture (x, y from 0 to 1), or (-1, -1) if behind the eye.
func project(frame: Dictionary, c: Vector3) -> Vector2:
	var xf: Transform3D = frame.xf
	var d := xf.basis.inverse() * (c - xf.origin)
	if d.z > -.05:
		return Vector2(-1, -1)
	var t := tan(deg_to_rad(FOV) / 2.0)
	var aspect := float(SIZE.x) / SIZE.y
	return Vector2(((d.x / -d.z) / (t * aspect) + 1) / 2, (1 - (d.y / -d.z) / t) / 2)


func _dir(x: float, y: float) -> Vector3:
	var t := tan(deg_to_rad(FOV) / 2.0)
	var aspect := float(SIZE.x) / SIZE.y
	return Vector3((clampf(x, 0, 1) * 2 - 1) * t * aspect, (1 - clampf(y, 0, 1) * 2) * t, -1).normalized()
