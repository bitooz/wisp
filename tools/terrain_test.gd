extends Node3D
## Smoke test for Terrain3D: generated hills, four texture layers, instanced grass.
## Prints T3D lines and frame rate; saves user://shots/terrain_test.png.

var terrain: Terrain3D
var cam: Camera3D
var t := 0.0

var opt := {shadows = true, instances = true, light_shader = false, scale = 1.0, msaa = 0, aniso = 2, shader = "", mesh_size = 48, spacing = 1.0, lods = 7}

func _ready() -> void:
	if FileAccess.file_exists("user://t3dopts"):
		opt.merge(JSON.parse_string(FileAccess.get_file_as_string("user://t3dopts")), true)
	print("T3D opts ", opt)
	get_viewport().scaling_3d_scale = opt.scale
	get_viewport().anisotropic_filtering_level = int(opt.aniso)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(opt.msaa) / 2]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9FD2FF")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#CFE3F5")
	env.ambient_light_energy = .5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.shadow_enabled = opt.shadows; add_child(sun)
	sun.look_at_from_position(Vector3(6, 11, 6), Vector3.ZERO)
	cam = Camera3D.new(); cam.far = 400; add_child(cam); cam.current = true

	terrain = Terrain3D.new()
	terrain.mesh_size = int(opt.mesh_size)
	terrain.mesh_lods = int(opt.lods)
	terrain.vertex_spacing = opt.spacing
	add_child(terrain)
	terrain.set_camera(cam)
	terrain.material.world_background = Terrain3DMaterial.NONE
	if opt.shader != "":
		terrain.material.shader_override = load(opt.shader)
		terrain.material.shader_override_enabled = true
	elif opt.light_shader:
		terrain.material.shader_override = load("res://addons/terrain_3d/extras/shaders/lightweight.gdshader")
		terrain.material.shader_override_enabled = true
	var assets := Terrain3DAssets.new()
	var names := ["grass", "dirt", "rock", "sand"]
	for i in names.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = names[i]
		ta.albedo_texture = load("res://assets/terrain/%s_albedo_height.png" % names[i])
		ta.normal_texture = load("res://assets/terrain/%s_normal_rough.png" % names[i])
		ta.uv_scale = .2
		assets.set_texture(i, ta)
	var ma := Terrain3DMeshAsset.new()
	ma.scene_file = load("res://assets/kenney_nature/plant_bushSmall.glb")
	ma.material_override = Build.mat("#7CC062", {sway = .5})
	assets.set_mesh_asset(0, ma)
	terrain.assets = assets
	print("T3D version ", terrain.version)

	var n := 512
	var h := Image.create_empty(n, n, false, Image.FORMAT_RF)
	var c := Image.create_empty(n, n, false, Image.FORMAT_RF)
	for y in n:
		for x in n:
			var p := Vector2(x - n / 2.0, y - n / 2.0)
			var hill := 14.0 * exp(-p.distance_squared_to(Vector2(30, -40)) / 900.0) + 6.0 * exp(-p.distance_squared_to(Vector2(-40, 20)) / 600.0)
			var shore := clampf((90.0 - p.length()) / 20.0, -1, 1) * 3.0
			var hh := hill + shore + sin(x * .1) * .6 + cos(y * .13) * .5
			h.set_pixel(x, y, Color(hh, 0, 0))
			var base := 0 if hh > 1.0 else 3
			var over := 2
			var blend := int(clampf((hill - 6.0) * 30.0, 0, 255))
			c.set_pixel(x, y, Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(over) | Terrain3DUtil.enc_blend(blend)), 0, 0))
	terrain.data.import_images([h, c, null], Vector3(-n / 2.0, 0, -n / 2.0), 0.0, 1.0)
	print("T3D regions ", terrain.data.get_region_count(), " height(0,0)=", terrain.data.get_height(Vector3(0, 0, 0)), " hill=", terrain.data.get_height(Vector3(30, 0, -40)))
	var xf: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	for i in 6000:
		var p := Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-70, 70))
		p.y = terrain.data.get_height(p)
		if p.y < 1.0:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 2.0), p))
	if opt.instances:
		terrain.instancer.add_transforms(0, xf)
	print("T3D instances ", xf.size())

func _process(dt: float) -> void:
	t += dt
	var a := t * .15
	var target := Vector3(0, terrain.data.get_height(Vector3.ZERO) if terrain else 0.0, 0)
	cam.look_at_from_position(target + Vector3(sin(a) * 40, 22, cos(a) * 40), target)
	if int(t * 10) % 20 == 0:
		pass

func _enter_tree() -> void:
	_report()

func _report() -> void:
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shots"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shots/terrain_test.png")
	for i in 3:
		print("T3D_PERF fps=%d draws=%d prims=%dk" % [Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
		await get_tree().create_timer(2.0).timeout
	print("T3D done")
	get_tree().quit()
