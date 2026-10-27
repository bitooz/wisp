extends SceneTree
## The gait bench: `godot --path . -s res://tools/gait_test.gd -- [--shots=DIR] [mo bo player]`.
## Each character goes through the same course (standing, easing up to a walk, a jog and a run, slowing
## to a stop, then a circle at a jog), and the planted foot's slide is measured: how fast the lowest toe
## moves over the ground while it's down (m/s; 0 is no sliding). With --shots, frames of each from the
## side and from behind (the game's own viewport).

const MODELS := {mo = "res://art/pals/mo.glb", bo = "res://art/pals/bo.glb", player = "res://art/player/player.glb"}
## The course: [seconds, speed (m/s), turn (rad/s)]
const COURSE := [[1.0, 0.0, 0.0], [3.0, 1.0, 0.0], [3.0, 2.2, 0.0], [3.0, 4.0, 0.0], [1.5, 0.0, 0.0],
	[4.0, 2.4, .8], [1.5, 0.0, 0.0]]

var shots := ""
## --strip: eight poses through each step clip's cycle, side on (in shots)
var strip := false
## --old: the clips played as before gait.gd (walk below 1.6 m/s sped up by the speed, run above), to compare
var old := false
var who := []
var cam: Camera3D
var lines := []
## The toes where the final pose (after the skeleton's modifiers) has them, each frame
var final_feet := []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
		elif a == "--old":
			old = true
		elif a == "--strip":
			strip = true
		elif MODELS.has(a):
			who.append(a)
	if who.is_empty():
		who = ["mo", "bo"]
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-.9, .6, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.78, .84, .9)
	env.environment.ambient_light_color = Color(.8, .8, .85)
	env.environment.ambient_light_energy = .6
	world.add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _checker()
	gm.uv1_scale = Vector3(100, 100, 1)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ground.material_override = gm
	world.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	root.size = Vector2i(640, 640)
	for id in who:
		if not ResourceLoader.exists(MODELS[id]):
			print("no ", MODELS[id])
			continue
		if strip:
			await _strip(world, id)
		else:
			await _course(world, id)
	for l in lines:
		print(l)
	quit()


func _course(world: Node3D, id: String) -> void:
	var body := Node3D.new()
	world.add_child(body)
	var inner := Node3D.new()
	body.add_child(inner)
	var kid: Kid = null
	var model: Node3D = load(MODELS[id]).instantiate()
	var src: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var gait: Gait
	if id == "player" and not old:
		# The kid as the game would have it (kid.gd: the lantern hanging), stepped here
		model.free()
		kid = Kid.new()
		body.add_child(kid)
		kid.set_process(false)
		gait = kid.gait
		model = gait.tree.get_parent()
	else:
		inner.add_child(model)
		gait = Gait.new(model, src, {jump = 1.0}, func(b): return not (b as String).begins_with("lid") and b != "lantern")
	gait.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if old:
		gait.tree.active = false
		gait.lock.active = false
		src.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		src.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
		src.get_animation("run").loop_mode = Animation.LOOP_LINEAR
		src.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	elif kid == null:
		src.queue_free()
	var skel := gait.skel
	lines.append("%s: natural pace walk %.2f, jog %.2f, run %.2f m/s; stride walk %.2f, jog %.2f, run %.2f m; left foot lands at %.2f/%.2f/%.2f" % [
		id, gait.natural.walk, gait.natural.jog, gait.natural.run, gait.stride.walk, gait.stride.jog, gait.stride.run,
		gait.touch.walk, gait.touch.jog, gait.touch.run])
	var toes := [skel.find_bone("DEF-toe.L"), skel.find_bone("DEF-toe.R")]
	# (on the body, not counting its lean: that lifts one foot and lowers the other a centimetre or so)
	skel.skeleton_updated.connect(func(): final_feet = toes.map(func(b): return body.global_transform * skel.get_bone_global_pose(b).origin))
	var hip := skel.get_bone_global_rest(skel.find_bone("DEF-thigh.L")).origin.y
	var dt := 1.0 / 30
	var v := 0.0
	var yaw := 0.0
	var t := 0.0
	var seg := 0
	var seg_t := 0.0
	var last_feet := []
	var slide := {}
	var shot_i := 0
	while seg < COURSE.size():
		var want: float = COURSE[seg][1]
		var turn: float = COURSE[seg][2]
		v = move_toward(v, want, (4.5 if want > v else 5.0) * dt)
		yaw += turn * dt * minf(1, v / 1.5)
		body.rotation.y = yaw
		body.position += Vector3(sin(yaw), 0, cos(yaw)) * v * dt
		if old:
			var want_c := "idle" if v < .05 else ("run" if v > 1.6 else "walk")
			if src.current_animation != want_c:
				src.play(want_c, .2)
			src.speed_scale = clampf(v / 1.1, .6, 1.6) if want_c == "walk" else (clampf(v / 2.4, .7, 1.5) if want_c == "run" else 1.0)
			src.advance(dt)
		elif kid:
			kid.step(dt)
			gait.tree.advance(dt)
		else:
			gait.update(dt, v, false)
			inner.rotation = gait.tilt(dt, v, turn * minf(1, v / 1.5))
			gait.tree.advance(dt)
		# (the final pose, after the skeleton's modifiers: the feet held down)
		await process_frame
		# The lowest toe, while it's down: how far it moved over the ground since the last frame
		var feet := final_feet
		if last_feet.size() == 2:
			var low := 0 if feet[0].y < feet[1].y else 1
			# (down: the lower toe, within 2 cm of the ground, and still the lower one)
			if feet[low].y < .02 and (last_feet[0].y < last_feet[1].y) == (low == 0) and v > .05:
				var band := "walk" if v < 1.6 else ("jog" if v < 3.0 else "run")
				if turn != 0:
					band = "turn"
				var s: Vector2 = Vector2(feet[low].x - last_feet[low].x, feet[low].z - last_feet[low].z)
				if not slide.has(band):
					slide[band] = []
				slide[band].append(s.length() / dt)
		last_feet = feet
		cam.position = body.position + Vector3(3.2, 1.0, 0) if seg < 5 else body.position + Vector3(-sin(yaw), 0, -cos(yaw)) * 3.6 + Vector3(0, 1.4, 0)
		cam.look_at(body.position + Vector3(0, .65, 0))
		if shots != "" and int(t * 30) % 6 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%03d.png" % [shots, id, shot_i])
			shot_i += 1
		t += dt
		seg_t += dt
		if seg_t >= COURSE[seg][0]:
			seg += 1
			seg_t = 0
	var out := id + (" (old)" if old else "") + " slide (median / 90th percentile, m/s):"
	for band in ["walk", "jog", "run", "turn"]:
		if slide.has(band):
			var a: Array = slide[band]
			a.sort()
			out += " %s %.2f/%.2f" % [band, a[a.size() / 2], a[int(a.size() * .9)]]
	lines.append(out)
	body.queue_free()


func _strip(world: Node3D, id: String) -> void:
	var body := Node3D.new()
	world.add_child(body)
	var model: Node3D = load(MODELS[id]).instantiate()
	body.add_child(model)
	var src: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var gait := Gait.new(model, src, {jump = 1.0}, func(b): return not (b as String).begins_with("lid") and b != "lantern")
	src.queue_free()
	cam.position = Vector3(3.0, .75, 0)
	cam.look_at(Vector3(0, .65, 0))
	for c in Gait.STEPS:
		for i in 8:
			var v: float = gait.natural[c]
			gait.phase = i / 8.0
			gait.move_w = 1
			gait.update(0.0, v, false)
			gait.tree.advance(0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/strip_%s_%s_%d.png" % [shots, id, c, i])
	body.queue_free()


func _checker() -> ImageTexture:
	var im := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 8:
			im.set_pixel(x, y, Color(.55, .6, .5) if (x < 4) == (y < 4) else Color(.62, .67, .56))
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)
