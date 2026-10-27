class_name Game
extends Node
## Wisp. You are a kid with a lantern (kid.gd), its flame your light. Mo and Bo are two kids with minds of their own (minds.gd): they go where
## they like, know only what they've perceived, remember it, and hear you when you talk.
##
## The game holds what goes everywhere with you: the light, Mo and Bo, the camera,
## the corner view of what the chosen one sees, speech, and the HUD. Places are
## separate scenes (scenes/island.tscn, scenes/dungeon.tscn) that bring their own puzzle.

const LEVELS := {"isle": "res://scenes/island.tscn", "cave": "res://scenes/dungeon.tscn"}
const PW := 176.0
const PH := 112.0
const WORD_MS := 330.0
const VOICES := {mo = {rate = 1.05}, bo = {rate = 1.08}, nell = {rate = .95}, tam = {rate = 1.0}, odo = {rate = .92}}
class Talk:
	extends RefCounted
	signal done
	var over := false
	var pal: Pal
	var words: PackedStringArray
	var t0 := 0.0
	var per := 0.0
	var total := 0.0
	var tok = null
	var me := 0
	var lit := 0
	## Said in their voice: the words light up with it, and it's over when the voice is
	var voice: Voice = null


var world: Node3D
var main_vp: SubViewport
var level: Level
var hud: Hud
var camera: Camera3D
var env: Environment
var pip_vp: SubViewport
var eye_cam: Camera3D
var pip_env: Environment
## Mo's and Bo's sight: a picture from their eyes when they think (eyes.gd)
var eyes: Eyes
## The time of day, everywhere (clock.gd); which morning it last was
var clock := Clock.new()
## Sounds, as Mo and Bo hear them (hearing.gd)
var hearing := Hearing.new(self)
var morning := -1

var wisp: Node3D
## You: the kid with the lantern (kid.gd). The light (Wisp's glow and light) is the lantern's flame.
var kid: Kid
var wisp_core: MeshInstance3D
var wisp_glow: MeshInstance3D
var wisp_light: OmniLight3D
var halo: MeshInstance3D
var wisp_g := Vector3()
var heading := Vector3(0, 0, -1)
var mo: Pal
var bo: Pal
## The island's other people (folk.gd): Nell, Tam and Odo
var folk: Array = []
## Beyond this far from you, the island's people are updated less often (Pal.set_far)
const FOLK_FAR := 25.0
var active: Pal
var sparks := []
var actors: Array = []

var az := .12
var pol := .9
var az_goal = null
var cam_focus = null
var shake := 0.0
var dist_now := 12.0
var cam_target := Vector3()

var joy := Vector2()
var controls := true
var moved := false

var run := 0
## Where the story is (the places move it on as things happen); each change is logged as WISP_STAGE
var stage := "island":
	set(v):
		if v != stage:
			print("WISP_STAGE %s %.1fs" % [v, Time.get_ticks_msec() / 1000.0])
		stage = v
var busy := false
var hot_tag = null
var seen_log = null
var light_r := 3.0
var light_now := 3.0
var wisp_flare := 0.0
var embers := 0
var cur: Array = []
var last_seen := {}
var talk_cur: Talk = null
## When the last line ended (minds.gd leaves a gap after it)
var line_ended_at := 0.0
var talking := 0
var speaker: Pal = null
var bubble_hide_at := -1.0
var bubble_me := 0
## Places made so far, kept for going back
var levels := {}
## How much world the device can afford: grass blades, little lights, render scale,
## and how often the corner view redraws. Phones get less, measured on a Galaxy A16.
var quality := {fx = 1.0, scale = 1.0, pip_every = 1, pip_scale = 3.0, msaa = 4, shadow = 2048, soft = 2, veg = 1.0, grass_range = 40.0, t3d_mesh = 32, terrain = "mobile", tree_near = 60.0}
var frame_n := 0
var look_hold := 0.0
var moving_now := false
## Feel: the light's velocity (it speeds up and slows down rather than snapping), a dash,
## the camera's swing that carries on after a swipe, and how far it's pulled in by walls.
var vel := Vector2()
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2()
var az_vel := 0.0
var drag_live := 0.0
var cam_pull := 0.0
var sfx: Sfx
var minds: Minds
var steps := {}
var interaction := {}
var hits := 0
## Seconds since you last moved or looked: when you leave it, your light drifts after them
var idle_t := 0.0
## Where the light drifts to when you're idle
const IDLE_AFTER := 6.0
var idle_walk := false
const ACCEL := 14.0
const DECEL := 20.0
const TURN := 9.0
const DASH_TIME := .28
const DASH_COOLDOWN := .9
const DASH_SPEED := 3.2
var prof := {pals = 0, tick = 0, senses = 0, rest = 0, n = 0, hud = 0}


func _ready() -> void:
	# Device tests: a file user://scene names another scene to run instead
	if FileAccess.file_exists("user://scene"):
		var other_scene := FileAccess.get_file_as_string("user://scene").strip_edges()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://scene"))
		get_tree().change_scene_to_file.call_deferred(other_scene)
		return
	Build.reseed(11)
	if OS.has_feature("mobile"):
		quality = {fx = .6, scale = .55, pip_every = 2, pip_scale = 1.4, msaa = 2, shadow = 1024, soft = 0, veg = .5, grass_range = 24.0, t3d_mesh = 16, terrain = "mobile", tree_near = 30.0}
	# For tuning on a device: a JSON file user://quality overrides any of these
	if FileAccess.file_exists("user://quality"):
		var o = JSON.parse_string(FileAccess.get_file_as_string("user://quality"))
		if o is Dictionary:
			quality.merge(o, true)
	print("WISP_QUALITY ", quality)
	var aa := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}
	RenderingServer.directional_shadow_atlas_set_size(int(quality.shadow), true)
	if not quality.get("vsync", true):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(quality.soft))
	# The world renders into its own see-through picture, laid over the sky gradient, so
	# tone mapping touches the 3D and leaves the sky's colours exactly as the mock has them.
	main_vp = SubViewport.new()
	main_vp.transparent_bg = true
	main_vp.msaa_3d = aa[int(quality.msaa)]
	main_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(main_vp)
	world = Node3D.new()
	world.name = "World"
	main_vp.add_child(world)
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# three.js ACESFilmic at exposure 1.04 (it divides by .6; Godot's ACES multiplies by 1.8)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.04 / 0.6 / 1.8
	env.tonemap_white = 16.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	camera = Camera3D.new()
	camera.fov = 38
	camera.near = .1
	camera.far = 140
	world.add_child(camera)
	camera.current = true
	# What's cut away for you (a house's roof and near walls while you're in it: houses.gd) stays in their eyes
	camera.cull_mask = 0xFFFFF & ~Houses.CUT_LAYER

	_make_wisp()
	mo = Pal.new()
	mo.setup({id = "mo", name = "Mo", color = "#FF7A52", h = 1.08, layer = 2}, self)
	world.add_child(mo)
	bo = Pal.new()
	bo.setup({id = "bo", name = "Bo", color = "#5AA9FF", h = 1.3, layer = 3}, self)
	world.add_child(bo)
	for w in Folk.IDS:
		var B: Dictionary = Folk.BODY[w]
		var f := Pal.new()
		f.setup({id = w, name = Folk.NAMES[w], color = B.color, layer = B.layer, model = B.model, scale = B.scale, hue = B.hue,
			desat = B.desat, tone = B.tone}, self)
		world.add_child(f)
		folk.append(f)
	active = mo
	for i in 30:
		var s := Build.glow("#ffffff", .3)
		s.visible = false
		world.add_child(s)
		sparks.append({s = s, v = Vector3(), life = 0.0, max = 1.0})
	actors = [{t = "mo", node = mo, live = true}, {t = "bo", node = bo, live = true}, {t = "you", node = kid, live = true}]
	for f in folk:
		actors.append({t = f.id, node = f, live = true})

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.pal.connect(_tap_pal_button)
	hud.restart.connect(start)
	hud.tap.connect(_tap_world)
	hud.look.connect(_drag_look)
	hud.steer.connect(func(v): joy = v)
	hud.dash.connect(dash)
	hud.interact.connect(interact)
	hud.mic.connect(_toggle_mic)
	sfx = Sfx.new()
	sfx.world = world
	add_child(sfx)
	hud.sound_off = sfx.muted
	hud.sound.connect(toggle_sound)
	minds = Minds.new()
	add_child(minds)
	minds.setup(self)
	hud.talk_any = minds.on
	main_vp.audio_listener_enable_3d = true

	# What the chosen one sees: a second camera on the same world, in the corner
	pip_vp = SubViewport.new()
	pip_vp.transparent_bg = true
	pip_vp.msaa_3d = aa[mini(int(quality.msaa), 2)]
	pip_vp.world_3d = main_vp.find_world_3d()
	pip_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pip_vp)
	eye_cam = Camera3D.new()
	eye_cam.fov = 74
	eye_cam.near = .05
	eye_cam.far = 60
	pip_env = env.duplicate()
	eye_cam.environment = pip_env
	pip_vp.add_child(eye_cam)
	eye_cam.current = true
	hud.pip_tex.texture = pip_vp.get_texture()
	eyes = Eyes.new()
	add_child(eyes)
	eyes.setup(self)
	hud.sky.texture = main_vp.get_texture()
	get_viewport().size_changed.connect(_fit)
	_fit()

	start()
	# Life went on while the game was closed: catch up, then today's plans
	_reopen.call_deferred()
	var args := Array(OS.get_cmdline_user_args())
	# On a phone there's no command line: a file user://autoplay holding the arguments does it
	if FileAccess.file_exists("user://autoplay"):
		args.append_array(FileAccess.get_file_as_string("user://autoplay").strip_edges().split(" ", false))
		args.append("--autoplay")
	# Body language off (to measure what it costs, on a phone too)
	if args.has("--still"):
		Pal.expressive = false
	if args.has("--autoplay"):
		var path := "res://tools/autoplay.gd"
		for a in args:
			if String(a).begins_with("--autoplay-script="):
				path = String(a).substr(18)
		var auto = load(path).new()
		auto.game = self
		auto.args = args
		add_child(auto)
	if OS.is_debug_build():
		_perf()


## Brackets every frame's scripts (all the nodes' _process, first to last), to tell script time from the rest.
class FrameEdge extends Node:
	var first := false
	var t0 := 0
	var spent := 0
	var n := 0
	var worst := 0
	var other: FrameEdge

	func _process(_dt: float) -> void:
		if first:
			t0 = Time.get_ticks_usec()
		else:
			var d := Time.get_ticks_usec() - other.t0
			spent += d
			worst = maxi(worst, d)
			n += 1


## Every two seconds, how fast the frame goes: `adb logcat -s godot | grep WISP_PERF` on a phone.
func _perf() -> void:
	for vp in [main_vp, pip_vp, get_viewport()]:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var head := FrameEdge.new()
	head.first = true
	head.process_priority = -100000
	var tail := FrameEdge.new()
	tail.process_priority = 100000
	tail.other = head
	get_tree().root.add_child.call_deferred(head)
	get_tree().root.add_child.call_deferred(tail)
	while is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		var gpu := ""
		for vp in [main_vp, pip_vp, get_viewport()]:
			gpu += "%.1f/" % RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		var n: int = max(1, prof.n)
		print("WISP_PROF us/frame pals=%d tick=%d senses=%d rest=%d hud=%d scripts=%d worst=%d" % [prof.pals / n, prof.tick / n, prof.senses / n, prof.rest / n, prof.hud / n,
			tail.spent / maxi(1, tail.n), tail.worst])
		tail.spent = 0
		tail.n = 0
		tail.worst = 0
		prof = {pals = 0, tick = 0, senses = 0, rest = 0, n = 0, hud = 0}
		print("WISP_PERF fps=%d cpu=%.1fms gpu(main/pip/hud)=%sms draws=%d prims=%dk objects=%d level=%s stage=%s" % [
			Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.TIME_PROCESS) * 1000, gpu,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			level.id if level else "-", stage])


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_SPACE:
			dash()
		elif e.physical_keycode == KEY_E:
			interact()
		elif e.physical_keycode == KEY_M:
			toggle_sound()


## The background sound (ambience, effects) off or on: never their voices. Remembered between launches.
func toggle_sound() -> void:
	sfx.set_muted(not sfx.muted)
	hud.sound_off = sfx.muted


## Render at the screen's real pixels, though the HUD is laid out at 844 x 390.
func _fit() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var base := get_viewport().get_visible_rect().size
	main_vp.size = Vector2i(maxi(1, int(win.x * quality.scale)), maxi(1, int(win.y * quality.scale)))
	var k := win.y / base.y
	k = min(k, quality.pip_scale)
	pip_vp.size = Vector2i(roundi(PW * max(1.0, k)), roundi(PH * max(1.0, k)))


## Where a point in the world shows on the HUD.
func to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) * get_viewport().get_visible_rect().size / Vector2(main_vp.size)


func _make_wisp() -> void:
	# You: the kid, carrying the lantern; the light lives in its flame
	kid = Kid.new()
	kid.name = "Kid"
	world.add_child(kid)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("tag", "you")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = .25
	cap.height = 1.4
	cs.shape = cap
	cs.position.y = .7
	body.add_child(cs)
	kid.add_child(body)
	wisp = Build.group(world, "light")
	wisp_core = Build.mesh(Build.sphere(.15, 20, 14), Build.basic("#FFF7DE"), 0, 0, 0, wisp)
	wisp_core.visible = false
	wisp_glow = Build.glow("#FFE6A6", .9)
	wisp.add_child(wisp_glow)
	wisp_light = Build.omni("#FFE2A8", 0, 7, 1.6)
	wisp.add_child(wisp_light)
	# A soft pool of light on the ground under you, so you always know where you are
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var m := ShaderMaterial.new()
	m.shader = Build.GLOW
	m.set_shader_parameter("tint", Color("#FFE6A6"))
	m.set_shader_parameter("opacity", .5)
	m.set_shader_parameter("billboard", false)
	halo = MeshInstance3D.new()
	halo.mesh = q
	halo.material_override = m
	halo.rotation.x = -PI / 2
	Build.noshadow(halo)
	world.add_child(halo)


# ---------- Places ----------

## Leave this place for another. The old one lingers, detached, until anything still waiting in it is done.
func travel(id: String, opts := {}) -> void:
	if level:
		# Places stay as they were left (a door opened, the ember gone, a lantern put down) for next time
		var old := level
		old.stage_saved = stage
		world.remove_child(old)
	hud.clear_boxes()
	if levels.has(id):
		level = levels[id]
		level.visits += 1
	else:
		level = load(LEVELS[id]).instantiate()
		level.game = self
		levels[id] = level
	world.add_child(level)
	if level.has_meta("new_day"):
		# Morning came while nobody was here
		level.remove_meta("new_day")
		level.new_day()
	hud.cave = level.theme == "cave"
	camera.fov = level.fov
	level.enter(opts)
	# Only those who are here are in view; whoever's just come through is placed at the way in (enter)
	for p in [mo, bo]:
		p.set_here(p.place_id == id)
		if p.place_id == id and minds:
			minds.of(p).entered()
	# The island's own people are wherever their day has them by now
	for p in folk:
		p.set_here(p.place_id == id)
		if p.place_id == id and minds:
			minds.of(p).back_to_day()
	aim(0, true)


## Who's where you are now (Mo and Bo).
func here() -> Array:
	return [mo, bo].filter(func(p): return p.place_id == level.id)


## Everyone with a mind: Mo, Bo and the island's other people.
func people() -> Array:
	return [mo, bo] + folk


## The island's other people somewhere else for now, out of sight and hearing (tests about Mo and Bo alone).
func folk_away() -> void:
	for p in folk:
		p.place_id = "away"
		p.set_here(false)


## Everyone where you are now.
func here_all() -> Array:
	return people().filter(func(p): return p.place_id == level.id)


## Starting over: every place is made anew.
func forget_places() -> void:
	for id in levels:
		var l: Level = levels[id]
		if l != level:
			l.free()
		else:
			world.remove_child(l)
			l.queue_free()
	levels.clear()
	level = null


## Depth fog: the dungeon's dark closing in, or the haze that softens far things outdoors.
func set_fog(on: bool, colour := Color("#09090E"), begin := 9.0, end := 21.0, density := 1.0) -> void:
	for e in [env, pip_env]:
		e.fog_enabled = on
		e.fog_mode = Environment.FOG_MODE_DEPTH
		e.fog_light_color = colour
		e.fog_light_energy = 1.0
		e.fog_density = density
		e.fog_sky_affect = 0.0
		e.fog_depth_begin = begin
		e.fog_depth_end = end
		e.fog_depth_curve = 1.0


func set_fog_depth(begin: float, end: float) -> void:
	for e in [env, pip_env]:
		e.fog_depth_begin = begin
		e.fog_depth_end = end


func set_fog_colour(colour: Color) -> void:
	env.fog_light_color = colour
	pip_env.fog_light_color = colour


## The hemisphere light: sky colour from above, ground colour from below (linear colours).
func set_hemi(sky_lin: Color, ground_lin: Color, intensity: float) -> void:
	var k := intensity / PI
	RenderingServer.global_shader_parameter_set("hemi_sky", Vector3(sky_lin.r, sky_lin.g, sky_lin.b) * k)
	RenderingServer.global_shader_parameter_set("hemi_ground", Vector3(ground_lin.r, ground_lin.g, ground_lin.b) * k)


func set_pal_glow(v: float) -> void:
	for p in people():
		Build.set_glow(p.skin, v)
	# You too, warmly, as if by your own lantern
	kid.skin.set_shader_parameter("emissive", Color("#FFD2A0"))
	Build.set_glow(kid.skin, v * 1.4)


## You arrive at w; so does whoever has just come through (pals already here stay where they are).
func place_party(w: Vector3, head: Vector3, mo_at: Vector2, bo_at: Vector2) -> void:
	wisp_g = w
	heading = head.normalized()
	wisp_g.y = level.ground(wisp_g.x, wisp_g.z)
	for p in [mo, bo]:
		if p.place_id == level.id and p.arriving:
			var at: Vector2 = mo_at if p == mo else bo_at
			p.place(at.x, at.y)
			p.position.y = level.ground(p.position.x, p.position.z)
			p.arriving = false


# ---------- Start and start over ----------

func start() -> void:
	run += 1
	hush()
	busy = false
	controls = true
	moved = false
	stage = "island"
	light_r = 3
	light_now = 3
	wisp_flare = 0
	hot_tag = null
	seen_log = null
	cam_focus = null
	shake = 0
	embers = 0
	hud.embers = 0
	hud.fade_on = false
	hud.vig_on = false
	hud.dusk_goal = 0
	hud.dusk = 0
	hud.stick_hint = true
	hud.you_on = false
	hud.you_typing = false
	hud.listening = false
	hud.bubble_on = false
	hud.reset_chips()
	for p in people():
		p.reset()
	for m in minds.all():
		m.body = Body.new(m.pal.id)
		m.task = {}
	idle_t = 0.0
	forget_places()
	for p in people():
		p.place_id = "isle"
		p.arriving = true
	travel("isle", {})
	set_active(mo)


# ---------- Every frame ----------

func _process(delta: float) -> void:
	var dt: float = min(.05, delta)
	var t := Time.get_ticks_msec() / 1000.0
	clock.step(delta)
	_mornings()
	# Keep the island's time and things, now and then (and on closing)
	if Time.get_ticks_msec() / 1000.0 > save_world_at:
		save_world_at = Time.get_ticks_msec() / 1000.0 + 30.0
		if levels.has("isle"):
			save_world()
	_update_talk()
	move_wisp(dt)
	aim(dt, false)
	wisp_g.y = level.ground(wisp_g.x, wisp_g.z)
	# You walk; the light swings in your lantern
	kid.position = wisp_g
	kid.rotation.y = atan2(heading.x, heading.z)
	kid.talk = hud.listening
	kid.look_at_point = active.head() if hud.listening else null
	wisp.position = kid.lantern.global_position if kid.lantern.is_inside_tree() and kid.lantern.global_position != Vector3.ZERO else wisp_g + Vector3(0, .9, 0)
	halo.position = Vector3(wisp_g.x, wisp_g.y + .06, wisp_g.z)
	halo.scale = Vector3.ONE * (1.2 if level.dark else .9 + sin(t * 1.7) * .05)
	wisp_flare = max(0, wisp_flare - dt * .9)
	light_now += (light_r - light_now) * min(1, dt * 1.5)
	wisp_glow.scale = Vector3.ONE * ((.35 + light_now * .14 if level.dark else .55) * (1 + wisp_flare * 1.8))
	Build.glow_opacity(wisp_glow, .85 + sin(t * 3.1) * .15)
	var t0 := Time.get_ticks_usec()
	# Only those here move (the others are somewhere else, waiting). The island's people far from you move a few
	# times a second (they're too far off to tell)
	for p in here_all():
		if p.folk:
			p.lod_dt += dt
			p.set_far(p.position.distance_to(wisp_g) > FOLK_FAR)
			if p.far and (frame_n + p.layer_bit) % 4 != 0:
				continue
			p.update(p.lod_dt, t)
			p.lod_dt = 0.0
		else:
			p.update(dt, t)
		# Mo and Bo stand on the ground, wherever it rises (or lie in bed)
		p.position.y = level.ground(p.position.x, p.position.z) + p.lift
	if active.place_id != level.id and here().size():
		set_active(here()[0])
	var t1 := Time.get_ticks_usec()
	for p in sparks:
		if p.life <= 0:
			continue
		p.life -= dt
		if p.life <= 0:
			p.s.visible = false
			continue
		p.s.position += p.v * dt
		p.v.y -= 2.2 * dt
		p.v *= .97
		var k: float = p.life / p.max
		p.s.scale = Vector3.ONE * ((.06 + .3 * k) / .3)
		Build.glow_opacity(p.s, k)
	level.tick(dt, t)
	var t2 := Time.get_ticks_usec()

	if speaker and hud.bubble_on:
		var h := speaker.head()
		if not camera.is_position_behind(h):
			hud.bubble_anchor = to_screen(h)
			hud.bubble_lean = -1 if speaker == mo else 1
	var o := other(active)
	var o_seen := senses(o, false)
	for tg in o_seen:
		o.known[key(tg)] = true
	last_seen = senses(active, true)
	for tg in last_seen:
		active.known[key(tg)] = true
	if seen_log != null:
		seen_log.merge(last_seen)
	var t3 := Time.get_ticks_usec()
	level.after_senses()
	aim_eye(active)
	eye_cam.cull_mask = 0xFFFFF & ~(1 << (active.layer_bit - 1))
	# On a phone the corner view redraws every other frame
	frame_n += 1
	if quality.pip_every > 1:
		pip_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if frame_n % quality.pip_every == 0 else SubViewport.UPDATE_DISABLED
	refresh_chips()
	_update_interaction()
	_footsteps()
	hud.dash_ready = 1.0 - dash_cd / DASH_COOLDOWN
	var t4 := Time.get_ticks_usec()
	prof.pals += t1 - t0
	prof.tick += t2 - t1
	prof.senses += t3 - t2
	prof.rest += t4 - t3
	prof.n += 1


# ---------- While you were away ----------

var save_world_at := 0.0
## The last catching up (for tests and the log)
var away := {}


## The island's time and its own things, kept beside Mo's and Bo's memories (user://world.json; tests' in
## their own folder).
func world_file() -> String:
	return minds.mo.file.get_base_dir().path_join("world.json")


func save_world() -> void:
	var isle = levels.get("isle")
	if isle == null or minds == null:
		return
	var f := FileAccess.open(world_file(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({v = 1, saved = Time.get_unix_time_from_system(), clock = clock.t, life = isle.life_state(),
			fire = isle.fire_evening >= 0}))


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED]:
		save_world()


## On starting: the island as it was left, then everything that would have happened since. (Tests that don't
## want it: --offline or --fresh-world start the island fresh; they call catch_up() themselves.)
func _reopen() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--offline") and not args.has("--fresh-world"):
		reopen_world()
	minds._first_plans()


## The island as it was saved, and catching up on the time since. Returns the catching up ({} if none).
func reopen_world() -> Dictionary:
	if not FileAccess.file_exists(world_file()):
		return {}
	var o = JSON.parse_string(FileAccess.get_file_as_string(world_file()))
	if not (o is Dictionary):
		return {}
	clock.t = float(o.get("clock", clock.t))
	morning = clock.day() - (0 if clock.hour() >= 6.0 else 1)
	var life: Dictionary = o.get("life", {})
	life.fire = o.get("fire", true)
	levels.isle.set_life_state(life)
	return catch_up(Time.get_unix_time_from_system() - float(o.get("saved", Time.get_unix_time_from_system())))


## `real_s` seconds have gone by with the game closed: the island and both of them catch up (life.gd), they're
## where their day has them now, they know Wisp's back, and a line says how long it's been. At most one
## reflection and one morning plan each, however long it's been. Logged as WISP_AWAY.
func catch_up(real_s: float) -> Dictionary:
	var hours := Life.away_hours(real_s, 24.0 / (Clock.DAY_MINUTES * 60.0))
	if hours < .05:
		return {}
	var isle = levels.isle
	var t0 := Time.get_ticks_usec()
	var world: Dictionary = isle.life_state()
	var start_t := clock.t
	var pals := []
	for m in minds.all():
		m.task = {}
		if m.body.asleep:
			m.body.asleep = false
		m.pal.go_out()
		m.pal.lie = false
		m.pal.closed = false
		pals.append({who = m.pal.id, mem = m.mem, body = m.body, heart = m.heart, plans = m.plans, skills = m.skills, news = m.news})
	var report := Life.catch_up(pals, world, start_t, hours)
	clock.t = start_t + hours
	morning = clock.day() - (0 if clock.hour() >= 6.0 else 1)
	isle.set_life_state(world)
	var words := Life.gap_words(hours, report.days, clock.hour())
	for m in minds.all():
		var p: Pal = m.pal
		var now: String = report.now[p.id]
		if p.folk:
			m.back_to_day()
			if report.days >= 1:
				minds.reflect(m)
			continue
		if p.place_id == level.id:
			if now == "sleep":
				var home: Dictionary = isle.shelter("house")
				p.position = home.door
				p.go_in("house")
				p.closed = true
				p.mode = "stay"
				m.body.asleep = true
				m.task = {act = "sleep", phase = "sleep", t = "house", word = "", door = home.door}
			else:
				var at: Vector3 = isle.life_spot(p.id, now)
				p.place(at.x, at.z)
				p.position.y = at.y
				p.mode = "stay"
		m.remember("event", "Wisp was gone %s, and now Wisp's back" % Life.gone_words(report.days), 6)
		m.dirty = true
		minds.after(m, "Wisp's back, after being away for a while")
		# One look back over the days away (the night's reflection), if a night went by
		if report.days >= 1:
			minds.reflect(m)
	hud.show_banner(words)
	report.ms = (Time.get_ticks_usec() - t0) / 1000.0
	report.real_s = real_s
	report.words = words
	away = report
	print("WISP_AWAY ", JSON.stringify(report))
	return report


## Each morning (six o'clock) what grows back grows back, wherever it is.
func _mornings() -> void:
	var m := clock.day() - (0 if clock.hour() >= 6.0 else 1)
	if m == morning:
		return
	var first := morning < 0
	morning = m
	if first:
		return
	for x in minds.all():
		x.morning()
	for id in levels:
		if levels[id] == level:
			level.new_day()
		else:
			levels[id].set_meta("new_day", true)


func key(tag: String) -> String:
	return level.id + ":" + tag


func other(p: Pal) -> Pal:
	return bo if p == mo else mo


func talking_now() -> bool:
	return people().any(func(p): return p.talk)


## Mo and Bo trail behind you, one on each side.
func slot(p: Pal) -> Vector2:
	var side := -1.0 if p == mo else 1.0
	return Vector2(wisp_g.x - heading.x * 2.0 - heading.z * side * 1.3, wisp_g.z - heading.z * 2.0 + heading.x * side * 1.3)


# ---------- Moving: the stick, or WASD and the arrow keys ----------

func move_wisp(dt: float) -> void:
	var ix := joy.x
	var iy := joy.y
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		iy -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		iy += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		ix -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		ix += 1
	var input := Vector2(ix, iy)
	# A small dead zone, then a gentle curve: fine control near the middle, full speed at the edge
	var l := input.length()
	if l < .12:
		input = Vector2.ZERO
	else:
		input = input / l * pow(clamp((l - .12) / .88, 0.0, 1.0), 1.25)
	dash_cd = max(0.0, dash_cd - dt)
	var fx := -sin(az)
	var fz := -cos(az)
	var rx := cos(az)
	var rz := -sin(az)
	var want := Vector2(rx * input.x - fx * input.y, rz * input.x - fz * input.y) * level.speed
	idle_t = 0.0 if input.length() > .05 else idle_t + dt
	if idle_t > IDLE_AFTER and not level.follow and level.idle_spot != Vector3.INF:
		# Left alone indoors, you step aside (out of their way, out of their light)
		var d := Vector2(level.idle_spot.x - wisp_g.x, level.idle_spot.z - wisp_g.z)
		want = d.normalized() * min(level.speed * .5, d.length() * 1.5) if d.length() > .3 else Vector2.ZERO
	if idle_t > IDLE_AFTER and level.follow:
		# Left alone, the light drifts after Mo and Bo, keeping its distance
		var w := watch_point()
		var d := Vector2(w.x - wisp_g.x, w.z - wisp_g.z)
		# Only once they've gone a way off: they shouldn't be trailing you while you trail them
		if d.length() > 8.0:
			idle_walk = true
		elif d.length() < 3.0:
			idle_walk = false
		want = d.normalized() * min(level.speed * .8, (d.length() - 3.0) * 1.2) if idle_walk else Vector2.ZERO
	if not controls:
		want = Vector2.ZERO
	if dash_t > 0:
		dash_t -= dt
		vel = dash_dir * level.speed * DASH_SPEED * (0.4 + 0.6 * dash_t / DASH_TIME)
	else:
		vel = vel.move_toward(want, (ACCEL if want.length() > vel.length() else DECEL) * dt)
	moving_now = vel.length() > .4
	if vel.length() < .01:
		return
	wisp_g.x += vel.x * dt
	wisp_g.z += vel.y * dt
	var before := Vector2(wisp_g.x, wisp_g.z)
	wisp_g = level.collide(wisp_g, .3, true)
	# Bumping into something takes the speed out of that direction
	var pushed := Vector2(wisp_g.x, wisp_g.z) - before
	if pushed.length() > 1e-4:
		var nrm := pushed.normalized()
		vel -= nrm * min(0.0, vel.dot(nrm))
	wisp_g.y = level.ground(wisp_g.x, wisp_g.z)
	# Turn toward where you're going, quickly but not instantly
	if vel.length() > .3:
		var cur := atan2(heading.x, heading.z)
		var to := atan2(vel.x, vel.y)
		var diff := atan2(sin(to - cur), cos(to - cur))
		var a: float = cur + clamp(diff, -TURN * dt, TURN * dt)
		heading = Vector3(sin(a), 0, cos(a))
	if not moved:
		moved = true
		hud.stick_hint = false


## What to keep in view when you're idle: both of them if they're together, or the one you chose.
func watch_point() -> Vector3:
	var h := here()
	if h.size() == 2 and mo.position.distance_to(bo.position) < 10.0:
		return (mo.position + bo.position) / 2
	if h.size():
		return h[0].position if not h.has(active) else active.position
	return wisp_g


## A quick burst of light in the direction you're facing (or going).
func dash() -> void:
	if not controls or dash_cd > 0 or not level:
		return
	dash_dir = vel.normalized() if vel.length() > .3 else Vector2(heading.x, heading.z).normalized()
	dash_t = DASH_TIME
	dash_cd = DASH_COOLDOWN
	wisp_flare = max(wisp_flare, .7)
	sfx.play("dash", wisp.global_position, -4.0, randf_range(.95, 1.1))
	Input.vibrate_handheld(18)
	if level.has_method("on_dash"):
		level.on_dash()


func dashing() -> bool:
	return dash_t > 0


## The button for whatever's at hand: go through a door you're at, or boop whoever's near.
func interact() -> void:
	if busy or interaction.is_empty():
		return
	sfx.play("select_002", null, -6.0)
	if interaction.has("pal"):
		var p: Pal = interaction.pal
		set_active(p)
		p.face(wisp_g)
		p.bounce()
		_booped(p)
	elif interaction.has("way"):
		follow_to(interaction.way.to, interaction.way.opts)


func _update_interaction() -> void:
	interaction = {}
	if busy or not level:
		hud.interact_label = ""
		return
	for p in here():
		if Vector2(p.position.x - wisp_g.x, p.position.z - wisp_g.z).length() < 2.4:
			interaction = {label = "Boop " + p.pal_name, pal = p}
			break
	if interaction.is_empty():
		# A way through somewhere else, right by you
		for T in level.things:
			var w: Dictionary = level.way(T.t)
			if not w.is_empty() and level.thing_pos(T.t).distance_to(wisp_g) < 3.0:
				interaction = {label = "Go in" if w.to == "cave" else "Go up", way = w}
				break
	hud.interact_label = interaction.get("label", "")


## Light landing a blow (on the shadow): a flash, sparks, a shake, a thud and a buzz.
func hit(at: Vector3, strength := 1.0) -> void:
	hits += 1
	shake = max(shake, .05 * strength)
	sfx.play_any("impactSoft_medium" if strength < 2 else "impactSoft_heavy", 3, at, -2.0 + strength, 1.15 - .1 * strength)
	Input.vibrate_handheld(int(20 * strength))
	var n := int(6 * strength)
	for p in sparks:
		if n <= 0:
			break
		if p.life > 0:
			continue
		n -= 1
		p.s.visible = true
		Build.glow_tint(p.s, Color("#D9C8FF"))
		p.s.position = at
		p.v = Vector3(Build.rnd() - .5, Build.rnd() * .8 + .2, Build.rnd() - .5).normalized() * (1.5 + Build.rnd() * 2.5)
		p.life = .35 + Build.rnd() * .35
		p.max = p.life


## Mo's and Bo's footsteps, from how far they've walked.
func _footsteps() -> void:
	for p in here_all() + [kid]:
		var at: Vector3 = p.position
		var last: Vector3 = steps.get(p, at)
		var d := Vector2(at.x - last.x, at.z - last.z).length()
		if d > 2.0:
			steps[p] = at
			continue
		if d > .55:
			steps[p] = at
			var ground: String = level.surface(at.x, at.z) if level.has_method("surface") else "grass"
			var pitch := 1.15 if p == mo else (1.05 if p == kid else .92)
			if ground == "wood":
				sfx.play_any("footstep_wood", 3, at, -13.0, pitch)
			elif ground == "stone":
				sfx.play_any("footstep_concrete", 5, at, -14.0, pitch)
			else:
				sfx.play_any("footstep_grass", 5, at, -12.0, pitch * (.85 if ground == "dirt" else 1.0))
		elif not steps.has(p):
			steps[p] = at


# ---------- Camera: behind you, drag to look around ----------

func aim(dt: float, snap: bool) -> void:
	if level and level.follow and cam_focus == null:
		_follow(dt, snap)
		return
	_coast(dt)
	if az_goal != null:
		az += atan2(sin(az_goal - az), cos(az_goal - az)) * (1 - exp(-dt * 1.8))
	var fx := -sin(az)
	var fz := -cos(az)
	var d := level.cam_dist if level else 12.0
	var want: Vector3
	if cam_focus != null:
		want = cam_focus.p
		d = cam_focus.dist
	else:
		var at := watch_point() if idle_t > IDLE_AFTER else wisp_g
		want = level.clamp_cam(Vector3(at.x + fx * 1.1, .4, at.z + fz * 1.1))
	if snap:
		cam_target = want
		dist_now = d
	cam_target = cam_target.lerp(want, 1 - exp(-dt * (1.6 if cam_focus != null else 3.2)))
	dist_now += (d - dist_now) * (1 - exp(-dt * 1.6))
	var s := sin(pol)
	var pos := Vector3(cam_target.x + dist_now * s * sin(az), cam_target.y + dist_now * cos(pol), cam_target.z + dist_now * s * cos(az))
	if shake > 0:
		pos.x += (randf() - .5) * shake
		pos.y += (randf() - .5) * shake
		shake = max(0, shake - dt * .25)
	camera.look_at_from_position(pos, cam_target)


## Outdoors: a third-person camera behind the light. It swings round behind you as you
## go, unless you've just dragged to look somewhere else; it never dips into the ground.
func _follow(dt: float, snap: bool) -> void:
	look_hold = max(0.0, look_hold - dt)
	_coast(dt)
	if az_goal != null:
		az += atan2(sin(az_goal - az), cos(az_goal - az)) * (1 - exp(-dt * 1.8))
	elif look_hold <= 0 and moving_now:
		var behind := atan2(-heading.x, -heading.z)
		az += atan2(sin(behind - az), cos(behind - az)) * (1 - exp(-dt * 1.6))
	var want := Vector3(wisp_g.x, wisp_g.y + 1.0, wisp_g.z)
	if snap:
		cam_target = want
		dist_now = level.cam_dist
	cam_target = cam_target.lerp(want, 1 - exp(-dt * 6.0))
	dist_now += (level.cam_dist - dist_now) * (1 - exp(-dt * 2.0))
	var s := sin(pol)
	var pos := Vector3(cam_target.x + dist_now * s * sin(az), cam_target.y + dist_now * cos(pol), cam_target.z + dist_now * s * cos(az))
	# Keep clear of hills between the camera and the light
	for k in [1.0, .66, .33]:
		var q := cam_target.lerp(pos, k)
		var floor_y := level.ground(q.x, q.z) + 1.0
		if q.y < floor_y:
			pos.y += (floor_y - q.y) / k
	# And of anything solid in the way: pull in fast, ease back out
	var look_at := cam_target + Vector3(0, .3, 0)
	var space := world.get_world_3d().direct_space_state
	var hit_q := PhysicsRayQueryParameters3D.create(look_at, pos, Level.WORLD_LAYER, level.cam_exclude())
	var hit_r := space.intersect_ray(hit_q)
	var full := look_at.distance_to(pos)
	var want_pull := 0.0
	if not hit_r.is_empty():
		want_pull = max(0.0, full - look_at.distance_to(hit_r.position) + .4)
	cam_pull = want_pull if want_pull > cam_pull else lerp(cam_pull, want_pull, 1 - exp(-dt * 3.0))
	if cam_pull > 0:
		pos = look_at + (pos - look_at).normalized() * max(1.2, full - cam_pull)
	if shake > 0:
		pos.x += (randf() - .5) * shake
		pos.y += (randf() - .5) * shake
		shake = max(0, shake - dt * .25)
	camera.look_at_from_position(pos, look_at)


## After a swipe the view keeps swinging, slowing to a stop.
func _coast(dt: float) -> void:
	drag_live = max(0.0, drag_live - dt)
	if drag_live > 0 or absf(az_vel) < .01:
		return
	az += az_vel * dt
	az_vel *= exp(-dt * 4.0)
	if level.az_limit > 0:
		az = clamp(az, -level.az_limit, level.az_limit)


func _drag_look(d: Vector2) -> void:
	idle_t = 0.0
	az_goal = null
	look_hold = 2.5
	drag_live = .08
	var dt: float = max(get_process_delta_time(), .001)
	# Remember how fast the finger was swinging the view, so it carries on after you let go
	az_vel = lerp(az_vel, -d.x * .007 / dt, .5)
	az -= d.x * .007
	pol = clamp(pol - d.y * .004, .78, 1.18)
	if level.az_limit > 0:
		az = clamp(az, -level.az_limit, level.az_limit)


func _tap_world(pos: Vector2) -> void:
	if busy:
		return
	pos *= Vector2(main_vp.size) / get_viewport().get_visible_rect().size
	var from := camera.project_ray_origin(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(pos) * 100, Pal.PAL_LAYER)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var tag: String = hit.collider.get_meta("tag", "")
	var p: Pal = people().filter(func(x): return x.id == tag).front() if people().any(func(x): return x.id == tag) else bo
	if not p.folk:
		set_active(p)
	p.face(wisp_g)
	p.bounce()
	_booped(p)


## Bumped by the light: they react as themselves (or with their written line, offline).
## You can't see who bumps you from behind.
func _booped(p: Pal) -> void:
	var m := minds.of(p)
	if m._sees(kid):
		m.touch("Wisp just bumped into you on purpose, playfully (a boop)")
		# Mo loves it; Bo doesn't, much, and less the more it happens
		var t := Time.get_ticks_msec() / 1000.0
		m.boops = m.boops.filter(func(x): return t - x < 120.0) + [t]
		if p == mo:
			m.heart.change("wisp", 0.0, .02)
			m.heart.feel(.06, .05)
		else:
			m.heart.change("wisp", 0.0, -.01 * m.boops.size())
			m.heart.feel(-.02 * m.boops.size(), .03)
			if m.boops.size() >= 3:
				m.heart.grudge("wisp", "Wisp keeps booping you", .3, m.mem.life_h)
	else:
		var side := Hearing.side(Hearing.angle_to(p, wisp_g))
		m.touch("someone bumped into you, %s" % side.replace("ahead of you", "from in front").replace("behind you", "from behind"))


func _tap_pal_button(id: String) -> void:
	if busy:
		return
	set_active(mo if id == "mo" else bo)


func set_active(p: Pal) -> void:
	active = p
	hud.active_id = p.id
	hud.pip_name = p.pal_name


# ---------- Things a character can see ----------

func aim_eye(p: Pal) -> Vector3:
	var eye := p.eye_world()
	eye_cam.look_at_from_position(eye, Vector3(eye.x + sin(p.yaw), eye.y - .14, eye.z + cos(p.yaw)))
	return eye


func senses(p: Pal, draw: bool) -> Dictionary:
	var eye := aim_eye(p)
	var seen := {}
	var vs := Vector2(pip_vp.size)
	var space := world.get_world_3d().direct_space_state
	for T in level.things + actors:
		var ok := false
		if T.t != p.id and T.node.is_visible_in_tree():
			if T.get("live", false) or not T.has("box"):
				T.box = Level.box_of(T.node)
			var c: Vector3 = T.box.get_center()
			if T.has("hi"):
				c.y = T.box.position.y + T.box.size.y * T.hi
			if not eye_cam.is_position_behind(c) and eye.distance_to(c) < eye_cam.far:
				var q := eye_cam.unproject_position(c)
				var nx := q.x / vs.x * 2 - 1
				var ny := 1 - q.y / vs.y * 2
				if absf(nx) < 1.02 and absf(ny) < 1.05 and level.lit(T.t, c):
					var dir := c - eye
					var dist := dir.length()
					var hit := ray(space, eye, dir / dist * (dist + .4), p.body.get_rid())
					ok = hit.is_empty() or hit.tag == T.t or hit.distance > dist - .3
		if ok:
			seen[T.t] = true
		if not draw:
			continue
		var rect := Rect2()
		if ok:
			rect = _screen_box(T.box, vs)
		hud.set_box(level.id + ":" + T.t, level.names.get(T.t, T.t), ok, rect, T.t == hot_tag)
	return seen


## What a ray from the eye bumps into first, skipping the looker and anything hidden.
func ray(space: PhysicsDirectSpaceState3D, from: Vector3, along: Vector3, me: RID) -> Dictionary:
	var skip := [me]
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(from, from + along, 0xFFFFFFFF, skip)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var body = hit.collider
		if not (body is Node):
			# The terrain's own collision: solid ground with no name
			return {tag = "", distance = from.distance_to(hit.position)}
		var holder: Node = body.get_parent()
		if holder is Node3D and not holder.is_visible_in_tree():
			skip.append(hit.rid)
			continue
		return {tag = body.get_meta("tag", ""), distance = from.distance_to(hit.position)}
	return {}


func _screen_box(b: AABB, vs: Vector2) -> Rect2:
	var x0 := 1e9
	var y0 := 1e9
	var x1 := -1e9
	var y1 := -1e9
	for i in 8:
		var c := Vector3(b.end.x if i & 1 else b.position.x, b.end.y if i & 2 else b.position.y, b.end.z if i & 4 else b.position.z)
		if eye_cam.is_position_behind(c):
			continue
		var q := eye_cam.unproject_position(c)
		var x := q.x / vs.x * PW
		var y := q.y / vs.y * PH
		x0 = min(x0, x)
		y0 = min(y0, y)
		x1 = max(x1, x)
		y1 = max(y1, y)
	x0 = max(3, x0)
	y0 = max(3, y0)
	x1 = min(PW - 3, x1)
	y1 = min(PH - 3, y1)
	if x1 - x0 < 14:
		var m := (x0 + x1) / 2
		x0 = m - 7
		x1 = m + 7
	if y1 - y0 < 14:
		var m := (y0 + y1) / 2
		y0 = m - 7
		y1 = m + 7
	return Rect2(x0, y0, x1 - x0, y1 - y0)


# ---------- Speech ----------

## Say something out loud: the bubble lights up word by word. Returns at once; see speak().
## voiced: "stream" is a thought's line whose voice is coming (minds.gd); "none" is words only.
func say(p: Pal, text: String, tok = null, voiced := "none") -> Talk:
	hush()
	var tk := Talk.new()
	tk.pal = p
	tk.words = text.split(" ", false)
	tk.per = WORD_MS / VOICES[p.id].rate / 1000.0
	tk.total = tk.words.size() * tk.per + .3
	tk.t0 = Time.get_ticks_msec() / 1000.0
	tk.tok = tok
	if minds.on and voiced == "stream":
		tk.voice = p.voice
	minds.line_said(p, text)
	for x in people():
		x.talk = false
	p.talk = true
	talking += 1
	tk.me = talking
	talk_cur = tk
	speaker = p
	bubble_hide_at = -1
	hud.show_bubble(tk.words, 0)
	if hud.bubble_alpha <= 0:
		var h := p.head()
		if not camera.is_position_behind(h):
			hud.bubble_anchor = to_screen(h)
			hud.bubble_lean = -1 if p == mo else 1
	return tk


## Say something and wait until it's said.
func speak(p: Pal, text: String, tok = null) -> void:
	var tk := say(p, text, tok)
	if not tk.over:
		await tk.done


func hush() -> void:
	if talk_cur and not talk_cur.over:
		if talk_cur.voice:
			talk_cur.voice.hush()
		_finish(talk_cur)


func _finish(tk: Talk) -> void:
	if tk.over:
		return
	tk.over = true
	line_ended_at = Time.get_ticks_msec() / 1000.0
	tk.lit = tk.words.size()
	tk.pal.talk = false
	if tk.me == talking:
		hud.bubble_lit = tk.lit
		bubble_hide_at = Time.get_ticks_msec() / 1000.0 + 1.6
		bubble_me = tk.me
	# Like a promise: whoever waits hears about it after this frame's work, not in the middle of it
	tk.done.emit.call_deferred()


func _update_talk() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var tk := talk_cur
	if tk and not tk.over:
		if (tk.tok != null and tk.tok != run) or tk.me != talking:
			if tk.voice:
				tk.voice.hush()
			_finish(tk)
		elif tk.voice:
			# In their voice: nothing lights until it's heard; then the words follow it
			var v := tk.voice
			if not v.sounding():
				tk.lit = 0
				hud.bubble_lit = 0
				if now - tk.t0 > 4.0 or v.done():
					# The voice didn't come: words only
					tk.voice = null
					tk.t0 = now
			else:
				var est: float = max(tk.words.size() * tk.per, v.length_s()) if not v.ended else v.length_s()
				tk.lit = clampi(int(v.heard_s() / max(.1, est) * tk.words.size()) + 1, 1, tk.words.size())
				hud.bubble_lit = tk.lit
				if v.done():
					_finish(tk)
		else:
			tk.lit = min(tk.words.size(), int((now - tk.t0) / tk.per) + 1)
			hud.bubble_lit = tk.lit
			if now - tk.t0 >= tk.total:
				_finish(tk)
	if bubble_hide_at > 0 and now >= bubble_hide_at:
		bubble_hide_at = -1
		if bubble_me == talking:
			hud.bubble_on = false


# ---------- Waiting ----------

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## Run fn(k) for k from 0 to 1 over sec seconds; stops early if the story moved on.
func tween(sec: float, fn: Callable, tok = null) -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		if tok != null and tok != run:
			return
		var k: float = min(1.0, (Time.get_ticks_msec() - t0) / (sec * 1000.0))
		fn.call(k)
		if k >= 1:
			return
		await get_tree().process_frame


func fade(on: bool) -> void:
	hud.fade_on = on
	await wait(.48)


static func ease_io(k: float) -> float:
	return 2 * k * k if k < .5 else 1 - pow(-2 * k + 2, 2) / 2


static func back_out(k: float) -> float:
	return 1 + 2.70158 * pow(k - 1, 3) + 1.70158 * pow(k - 1, 2)


func burst(at: Vector3, color: String) -> void:
	for p in sparks:
		p.s.visible = true
		Build.glow_tint(p.s, Color(color))
		p.s.position = at
		p.v = Vector3(Build.rnd() - .5, Build.rnd() * .9 + .1, Build.rnd() - .5).normalized() * (1.4 + Build.rnd() * 2.4)
		p.life = .7 + Build.rnd() * .7
		p.max = p.life


## Someone gave the light the ember: it shines brighter (and can carry it to the brazier itself).
func take_ember() -> void:
	burst(wisp.position, "#FFC873")
	wisp_flare = 1
	light_r = 4.4
	set_embers(embers + 1)
	sfx.play("confirmation_002", null, -4.0)
	if level.id == "cave" and stage == "ember":
		stage = "exit"


func set_embers(n: int) -> void:
	embers = n
	hud.pop_ember(n)


# ---------- Talking with Mo and Bo ----------

## No phrases to tap any more: you just talk (minds.gd listens).
func refresh_chips() -> void:
	hud.talk_any = minds.on
	hud.set_chips([], false)


## What you said, as it was heard, shown as your words for a moment.
func show_you(text: String) -> void:
	hud.you_typing = false
	hud.you_text = text
	hud.you_on = true
	get_tree().create_timer(2.5).timeout.connect(_hide_you.bind(text))


func _hide_you(text: String) -> void:
	if hud.you_text == text:
		hud.you_on = false


## The mic button: listening on or off.
func _toggle_mic() -> void:
	minds.ears.muted = not minds.ears.muted
	hud.mic_muted = minds.ears.muted
	sfx.play("select_001", null, -8.0)


## Mo or Bo went through a way somewhere else (a door, the steps). They go alone: the other one and you stay,
## unless you're leaving it to them (idle) and nobody's left here, then you follow.
func go_through(p: Pal, to: String, opts: Dictionary) -> void:
	if not controls:
		return
	var from := level.id
	# Whether the other one's watching them go (before they're gone)
	var watched := minds.of(other(p))._sees(p)
	p.came_from = from
	p.place_id = to
	p.arriving = true
	p.away_since = Time.get_ticks_msec() / 1000.0
	sfx.play("doorOpen_1", p.global_position, -6.0)
	var o := other(p)
	if o.place_id == from:
		# The other one sees them go if they're looking, and makes up their own mind about it (and may well mind
		# being left behind)
		var om := minds.of(o)
		if not om.body.asleep and watched:
			om.heart.left_behind(p.id, om.mem.life_h)
			# They'd said it wouldn't open
			om.saw_through(p.id)
		minds.saw(o, "%s just went off through there, on %s own" % [p.pal_name, "her" if p == mo else "his"], p.global_position + Vector3(0, .7, 0))
	minds.news_seen(p.global_position + Vector3(0, .7, 0), p.id, "%s went off through %s on %s own" % [p.pal_name, level.labels.get(way_t_of(to), "a way out"), Folk.HIS[p.id]], -.05)
	# What it sounds like, here (and, through the way, there)
	var way_t := ""
	for T in level.things:
		if not level.way(T.t).is_empty() and level.way(T.t).to == to:
			way_t = T.t
	hearing.make(p.global_position, from, level.way_sound(way_t), 20.0, p)
	p.set_here(false)
	if here().is_empty() and idle_t > IDLE_AFTER:
		await follow_to(to, opts)


## Which thing here leads to `to` ("" if none).
func way_t_of(to: String) -> String:
	for T in level.things:
		if not level.way(T.t).is_empty() and level.way(T.t).to == to:
			return T.t
	return ""


## You go through to another place (the interact button at a way, or following them when you're idle).
func follow_to(to: String, opts: Dictionary) -> void:
	if not controls:
		return
	# Anyone watching sees you go through (after saying it wouldn't open?)
	for m in minds.all():
		if m.pal.place_id == level.id and m._sees(kid):
			m.saw_through("wisp")
	controls = false
	sfx.play("doorOpen_1", null, -6.0)
	await fade(true)
	travel(to, opts)
	await wait(.3)
	await fade(false)
	controls = true
