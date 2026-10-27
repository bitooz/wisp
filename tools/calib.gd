extends Node
## Checks that Godot turns light into the same pixels three.js does in the mock:
## the sun, the hemisphere light, emission, glow sprites and ACES, rendered the way
## the game renders (a see-through SubViewport with 4x MSAA and a shadowed sun).
##   godot --path . res://tools/calib.tscn

var env: Environment
var sun: DirectionalLight3D
var m: ShaderMaterial
var vp: SubViewport
var root3d: Node3D
var failed := false


func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	root3d = Node3D.new()
	vp.add_child(root3d)
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 5, 0.001), Vector3.ZERO)
	cam.current = true
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	root3d.add_child(sun)
	sun.look_at_from_position(Vector3(0, 5, 0.0001), Vector3.ZERO)
	m = Build.mat("#808080", {roughness = 1.0})
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	Build.mesh(plane, m, 0, 0, 0, root3d)
	Build.mesh(Build.box(.5, .5, .5), Build.mat("#808080"), 6, 1, 0, root3d)
	_run()


func srgb(x: float) -> int:
	x = clamp(x, 0, 1)
	return roundi(255 * (12.92 * x if x <= 0.0031308 else 1.055 * pow(x, 1 / 2.4) - 0.055))


func aces(x: float) -> float:
	var v := x * 1.04 / 0.6
	return (v * (v + 0.0245786) - 0.000090537) / (v * (0.983729 * v + 0.4329510) + 0.238081)


func check(what: String, want: int) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var c := vp.get_texture().get_image().get_pixel(32, 32)
	var ok := absi(c.r8 - want) <= 4
	failed = failed or not ok
	print("%s %s: %d (want %d)" % ["ok:  " if ok else "FAIL:", what, c.r8, want])


func hemi(v: float) -> void:
	RenderingServer.global_shader_parameter_set("hemi_sky", Vector3(v, v, v))
	RenderingServer.global_shader_parameter_set("hemi_ground", Vector3(v, v, v))


func _run() -> void:
	var grey := pow((0.502 + 0.055) / 1.055, 2.4)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	hemi(0)
	sun.light_energy = 1.0
	await check("sun on grey", srgb(grey))
	sun.light_energy = 0
	hemi(1.0)
	await check("hemisphere light on grey", srgb(grey))
	hemi(0)
	m.set_shader_parameter("emissive", Color.WHITE)
	Build.set_glow(m, .25)
	await check("emission .25", srgb(.25))
	Build.set_glow(m, 0)
	var g := Build.glow("#808080", 40)
	(g.material_override as ShaderMaterial).set_shader_parameter("billboard", false)
	g.rotation.x = -PI / 2
	g.position.y = .05
	root3d.add_child(g)
	await check("glow centre", srgb(grey))
	g.queue_free()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.04 / 0.6 / 1.8
	env.tonemap_white = 16.0
	sun.light_energy = .25
	await check("ACES: sun .25 on grey", srgb(aces(.25 * grey)))
	hemi(.25)
	await check("ACES: shadowed sun + hemisphere", srgb(aces(.5 * grey)))
	print("FAILED" if failed else "DONE: renderer matches three.js")
	get_tree().quit(1 if failed else 0)
