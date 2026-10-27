class_name Grass
extends RefCounted
## A lawn: thousands of grass blades in clumps, built into one mesh (one draw call),
## swaying in the wind (shaders/grass.gdshader).

const SHADER := preload("res://shaders/grass.gdshader")


## count blades where accept(Vector2 xz) says so, within half_size of the centre.
static func lawn(count: int, accept: Callable, half_size := 5.2, seed := 7) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var c := Vector2(rng.randf_range(-half_size, half_size), rng.randf_range(-half_size, half_size))
		if not accept.call(c):
			continue
		var clump := rng.randi_range(5, 11)
		var tall := rng.randf_range(.75, 1.25)
		for k in clump:
			var p := c + Vector2(rng.randfn(0, .13), rng.randfn(0, .13))
			if not accept.call(p):
				continue
			_blade(verts, cols, uvs, idx, rng, p, tall)
			placed += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Build.nohit(mi)
	mi.set_meta("keep", true)
	return mi


static func _blade(verts: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array, rng: RandomNumberGenerator, p: Vector2, tall: float) -> void:
	var h := rng.randf_range(.11, .24) * tall
	var w := rng.randf_range(.035, .06)
	var yaw := rng.randf() * TAU
	var lean := Vector2(rng.randfn(0, .05), rng.randfn(0, .05))
	var side := Vector2(cos(yaw), sin(yaw)) * w * .5
	var base := Vector3(p.x, 0, p.y)
	var i0 := verts.size()
	verts.append_array([
		base + Vector3(-side.x, 0, -side.y), base + Vector3(side.x, 0, side.y),
		base + Vector3(-side.x * .6 + lean.x * .45, h * .55, -side.y * .6 + lean.y * .45),
		base + Vector3(side.x * .6 + lean.x * .45, h * .55, side.y * .6 + lean.y * .45),
		base + Vector3(lean.x, h, lean.y)])
	uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, .55), Vector2(1, .55), Vector2(.5, 1)])
	# Each blade a little different: some fresher, some drier
	var t := Color(rng.randf_range(.85, 1.1), rng.randf_range(.9, 1.08), rng.randf_range(.8, 1.05))
	if rng.randf() < .12:
		t = Color(1.15, 1.08, .8)
	for k in 5:
		cols.append(t)
	idx.append_array([i0, i0 + 1, i0 + 3, i0, i0 + 3, i0 + 2, i0 + 2, i0 + 3, i0 + 4])


## One clump of blades, for Terrain3D's instancer to scatter (it repeats it thousands of times).
static func clump(blades := 28, radius := .45, seed := 3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in blades:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		_blade(verts, cols, uvs, idx, rng, Vector2(cos(a), sin(a)) * r, 1.15)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	m.surface_set_material(0, mat)
	return m
