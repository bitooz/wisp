extends Node
## Bakes the far LOD for each tree: its colour, seen from the side, into a transparent
## PNG that shaders/impostor.gdshader stands up facing the camera. Run once after
## changing the trees:  godot --path . res://tools/bake_impostors.tscn

const TREES := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "Pine_5", "Bush_Common_Flowers"]
const OUT := "res://assets/quaternius_nature/impostors/"
const SIZE := 256

func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	# Pure colour: the hemisphere light at 1 everywhere, nothing else
	RenderingServer.global_shader_parameter_set("hemi_sky", Vector3.ONE)
	RenderingServer.global_shader_parameter_set("hemi_ground", Vector3.ONE)
	var info := {}
	for t in TREES:
		var root := Node3D.new()
		vp.add_child(root)
		var box := AABB()
		var first := true
		for part in Props.model(Props.QUAT + t + ".gltf", {}, 0.0):
			var mi := MeshInstance3D.new()
			mi.mesh = part.mesh
			mi.transform = part.xf
			root.add_child(mi)
			var b: AABB = part.xf * part.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var side: float = max(box.size.y, max(box.size.x, box.size.z)) * 1.02
		var c := box.get_center()
		cam.size = side
		cam.look_at_from_position(Vector3(c.x, c.y, c.z + 50), c)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + t + ".png"))
		# Where the picture sits relative to the model's origin, in model units
		info[t] = {side = side, cx = c.x, cy = c.y - side / 2.0}
		print("baked ", t, " side ", side)
		root.free()
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "impostors.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	get_tree().quit()
