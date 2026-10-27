class_name Build
extends RefCounted
## Little helpers for building the low-poly world out of code, the way the mock does.
## Shapes follow three.js: same sizes, same orientation, same segment counts.

const LIT := preload("res://shaders/lit.gdshader")
const LIT_ALPHA := preload("res://shaders/lit_alpha.gdshader")
const LIT_CUTOUT := preload("res://shaders/lit_cutout.gdshader")
const GLOW := preload("res://shaders/glow.gdshader")

static var _seed := 11


## The mock's seeded random numbers (mulberry32), so the world comes out the same each time.
static func rnd() -> float:
	_seed = (_seed + 0x6D2B79F5) & 0xFFFFFFFF
	var t := _imul(_seed ^ (_seed >> 15), 1 | _seed)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


static func reseed(s: int) -> void:
	_seed = s


static func _imul(a: int, b: int) -> int:
	a &= 0xFFFFFFFF
	b &= 0xFFFFFFFF
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


# ---------- Materials ----------

## Flat-shaded, like the mock's mat(): roughness .9, faceted. Materials with the same
## settings are shared (so the level can batch them into few draw calls); pass
## unique = true for one the game changes later (a glow that lights up, a colour that fades in).
static var _mats := {}


static func mat(color: String, o := {}) -> ShaderMaterial:
	var key := ""
	if not o.get("unique", false):
		key = color + str(o)
		if _mats.has(key):
			return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = LIT_ALPHA if o.has("opacity") else (LIT_CUTOUT if o.get("cutout", false) else LIT)
	m.set_shader_parameter("albedo", Color(color))
	m.set_shader_parameter("roughness", o.get("roughness", 0.9))
	m.set_shader_parameter("metallic", o.get("metal", 0.0))
	m.set_shader_parameter("flat_shading", o.get("flat", true))
	m.set_shader_parameter("emissive", Color(o.get("emissive", "#000000")))
	m.set_shader_parameter("emissive_energy", o.get("ei", 1.0 if o.has("emissive") else 0.0))
	m.set_shader_parameter("sway", o.get("sway", 0.0))
	if o.has("opacity"):
		m.set_shader_parameter("opacity", o.opacity)
	if o.has("tex"):
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("albedo_tex", load(o.tex) if o.tex is String else o.tex)
	if o.get("vcol", false):
		m.set_shader_parameter("use_vcol", true)
	if o.has("sky"):
		m.set_shader_parameter("sky_seen", o.sky)
	if o.has("ao"):
		m.set_shader_parameter("base_ao", o.ao)
		m.set_shader_parameter("base_ao_from", o.get("ao_from", 0.0))
		m.set_shader_parameter("base_ao_h", o.get("ao_h", .9))
	if o.has("patches"):
		m.set_shader_parameter("patches", o.patches)
		m.set_shader_parameter("albedo2", Color(o.albedo2))
	if key != "":
		_mats[key] = m
	return m


## Smooth-shaded, like a plain MeshStandardMaterial (roughness 1 unless told).
static func smooth(color: String, o := {}) -> ShaderMaterial:
	var p := o.duplicate()
	p.flat = false
	if not p.has("roughness"):
		p.roughness = 1.0
	return mat(color, p)


## Unlit, like MeshBasicMaterial.
static func basic(color: String, opacity := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color)
	if opacity < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = opacity
	return m


static func set_color(m: ShaderMaterial, c: Color) -> void:
	m.set_shader_parameter("albedo", c)


static func set_glow(m: ShaderMaterial, energy: float) -> void:
	m.set_shader_parameter("emissive_energy", energy)


# ---------- Nodes ----------

static func mesh(shape: Mesh, material: Material, x := 0.0, y := 0.0, z := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = shape
	mi.material_override = material
	mi.position = Vector3(x, y, z)
	mi.rotation_order = EULER_ORDER_XYZ
	if parent:
		parent.add_child(mi)
	return mi


static func noshadow(n: GeometryInstance3D) -> GeometryInstance3D:
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## Something to see but not to bump into or hide behind.
static func nohit(n: Node) -> Node:
	n.set_meta("nohit", true)
	return n


static func tag(n: Node3D, t: String) -> Node3D:
	n.set_meta("tag", t)
	return n


static func group(parent: Node3D = null, t := "") -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_XYZ
	if t != "":
		tag(g, t)
	if parent:
		parent.add_child(g)
	return g


static func tag_of(n: Node) -> String:
	while n:
		if n.has_meta("tag"):
			return n.get_meta("tag")
		n = n.get_parent()
	return ""


## A glow sprite, s across.
static func glow(color: String, s: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	var m := ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_parameter("tint", Color(color))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	noshadow(mi)
	nohit(mi)
	return mi


## Little drifting lights: pollen in the sun, fireflies at dusk, dust in torchlight.
## One emitter is one draw call.
static func motes(amount: int, extents: Vector3, color: String, size: float, life := 7.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0, 1, 0)
	p.spread = 180
	p.gravity = Vector3(0, .015, 0)
	p.initial_velocity_min = .03
	p.initial_velocity_max = .14
	p.scale_amount_min = .6
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(.25, Color(1, 1, 1, 1))
	ramp.add_point(.75, Color(1, 1, 1, .8))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_parameter("tint", Color(color))
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nohit(p)
	return p


static func glow_opacity(g: MeshInstance3D, a: float) -> void:
	(g.material_override as ShaderMaterial).set_shader_parameter("opacity", a)


static func glow_tint(g: MeshInstance3D, c: Color) -> void:
	(g.material_override as ShaderMaterial).set_shader_parameter("tint", c)


## Flames: a few cones, hidden until lit.
static func flames(parent: Node3D, sizes: Array) -> Dictionary:
	var g := group(parent)
	g.visible = false
	var fs := []
	for s in sizes:
		var f := mesh(cone(s[1], s[2], 7), basic(s[0], 0.94), 0, s[2] / 2.0, 0, g)
		noshadow(f)
		nohit(f)
		fs.append(f)
	return {g = g, fs = fs}


static func flicker(fl: Dictionary, t: float, dt: float) -> void:
	if not fl.g.visible:
		return
	for i in fl.fs.size():
		var m: MeshInstance3D = fl.fs[i]
		m.scale = Vector3(1 + sin(t * 9 + i) * .08, 1 + sin(t * 13 + i * 2) * .16, 1 + cos(t * 10 + i) * .08)
		m.rotation.y += dt * (1.5 + i)


static func omni(color: String, intensity: float, distance: float, decay: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color(color)
	l.omni_range = distance
	l.omni_attenuation = decay
	l.shadow_enabled = false
	set_light(l, intensity)
	return l


## three.js light intensity to Godot energy (Godot scales by pi, three's Lambert divides by it).
static func set_light(l: Light3D, intensity: float) -> void:
	l.light_energy = intensity / PI
	# A light at zero still costs every pixel it reaches
	l.visible = intensity > 0.001


# ---------- Shapes ----------

static func cyl(rt: float, rb: float, h: float, seg := 16, hseg := 1) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = hseg - 1
	return c


static func cone(r: float, h: float, seg := 16, hseg := 1) -> CylinderMesh:
	return cyl(0.0, r, h, seg, hseg)


static func box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


## A torus around the Z axis, like three's.
static func torus(r: float, tube: float, rseg: int, tseg: int) -> ArrayMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - tube
	t.outer_radius = r + tube
	t.rings = tseg
	t.ring_segments = rseg
	var arr := t.get_mesh_arrays()
	var turn := Basis(Vector3.RIGHT, PI / 2)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = turn * v[i]
		n[i] = turn * n[i]
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TANGENT] = null
	return _array_mesh(arr)


## A sphere like three's SphereGeometry, optionally only its top part (theta_len < PI).
static func sphere(r: float, ws := 16, hs := 12, theta_len := PI) -> ArrayMesh:
	var grid := []
	for iy in hs + 1:
		var row := []
		var v := float(iy) / hs
		for ix in ws + 1:
			var u := float(ix) / ws
			row.append(Vector3(-r * cos(u * TAU) * sin(v * theta_len), r * cos(v * theta_len), r * sin(u * TAU) * sin(v * theta_len)))
		grid.append(row)
	var pts := PackedVector3Array()
	for iy in hs:
		for ix in ws:
			var a: Vector3 = grid[iy][ix + 1]
			var b: Vector3 = grid[iy][ix]
			var c: Vector3 = grid[iy + 1][ix]
			var d: Vector3 = grid[iy + 1][ix + 1]
			if iy != 0:
				_tri(pts, a, b, d, Vector3.ZERO)
			if iy != hs - 1 or theta_len < PI:
				_tri(pts, b, c, d, Vector3.ZERO)
	return _tris(pts, true)


## A flat disc in the XY plane facing +Z, like three's CircleGeometry.
static func disc(r: float, seg: int) -> ArrayMesh:
	var pts := PackedVector3Array()
	for i in seg:
		var a := float(i) / seg * TAU
		var b := float(i + 1) / seg * TAU
		_tri_facing(pts, Vector3.ZERO, Vector3(cos(a), sin(a), 0) * r, Vector3(cos(b), sin(b), 0) * r, Vector3(0, 0, 1))
	return _tris(pts, false, Vector3(0, 0, 1))


const _T := 1.618033988749895
const ICO_V := [-1, _T, 0, 1, _T, 0, -1, -_T, 0, 1, -_T, 0, 0, -1, _T, 0, 1, _T, 0, -1, -_T, 0, 1, -_T, _T, 0, -1, _T, 0, 1, -_T, 0, -1, -_T, 0, 1]
const ICO_I := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
const _R := 1.0 / 1.618033988749895
const DODECA_V := [-1, -1, -1, -1, -1, 1, -1, 1, -1, -1, 1, 1, 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, 1, 1,
	0, -_R, -_T, 0, -_R, _T, 0, _R, -_T, 0, _R, _T,
	-_R, -_T, 0, -_R, _T, 0, _R, -_T, 0, _R, _T, 0,
	-_T, 0, -_R, _T, 0, -_R, -_T, 0, _R, _T, 0, _R]
const DODECA_I := [3, 11, 7, 3, 7, 15, 3, 15, 13, 7, 19, 17, 7, 17, 6, 7, 6, 15, 17, 4, 8, 17, 8, 10, 17, 10, 6, 8, 0, 16, 8, 16, 2, 8, 2, 10, 0, 12, 1, 0, 1, 18, 0, 18, 16, 6, 10, 2, 6, 2, 13, 6, 13, 15, 2, 16, 18, 2, 18, 3, 2, 3, 13, 18, 1, 9, 18, 9, 11, 18, 11, 3, 4, 14, 12, 4, 12, 0, 4, 0, 8, 11, 9, 5, 11, 5, 19, 11, 19, 7, 19, 5, 14, 19, 14, 4, 19, 4, 17, 1, 12, 14, 1, 14, 5, 1, 5, 9]
const OCTA_V := [1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1]
const OCTA_I := [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2]


static func ico(r: float, detail := 0) -> ArrayMesh:
	return _poly(ICO_V, ICO_I, r, detail)


static func dodeca(r: float, detail := 0) -> ArrayMesh:
	return _poly(DODECA_V, DODECA_I, r, detail)


static func octa(r: float, detail := 0) -> ArrayMesh:
	return _poly(OCTA_V, OCTA_I, r, detail)


## three's PolyhedronGeometry: split each face, push the points out onto the sphere.
static func _poly(vs: Array, ids: Array, r: float, detail: int) -> ArrayMesh:
	var pts := PackedVector3Array()
	var cols := detail + 1
	for f in range(0, ids.size(), 3):
		var a := Vector3(vs[ids[f] * 3], vs[ids[f] * 3 + 1], vs[ids[f] * 3 + 2])
		var b := Vector3(vs[ids[f + 1] * 3], vs[ids[f + 1] * 3 + 1], vs[ids[f + 1] * 3 + 2])
		var c := Vector3(vs[ids[f + 2] * 3], vs[ids[f + 2] * 3 + 1], vs[ids[f + 2] * 3 + 2])
		var v := []
		for i in cols + 1:
			var row := []
			var aj := a.lerp(c, float(i) / cols)
			var bj := b.lerp(c, float(i) / cols)
			var rows := cols - i
			for j in rows + 1:
				row.append(aj if (j == 0 and i == cols) else aj.lerp(bj, float(j) / rows))
			v.append(row)
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := j / 2
				if j % 2 == 0:
					_tri(pts, v[i][k + 1].normalized() * r, v[i + 1][k].normalized() * r, v[i][k].normalized() * r, Vector3.ZERO)
				else:
					_tri(pts, v[i][k + 1].normalized() * r, v[i + 1][k + 1].normalized() * r, v[i + 1][k].normalized() * r, Vector3.ZERO)
	return _tris(pts, detail > 0)


# Godot's front faces wind clockwise: keep each triangle facing away from the centre.
static func _tri(pts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, centre: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	_tri_facing(pts, a, b, c, (a + b + c) / 3.0 - centre)


static func _tri_facing(pts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) > 0:
		pts.append_array([a, c, b])
	else:
		pts.append_array([a, b, c])


static func _tris(pts: PackedVector3Array, smooth_normals: bool, facing := Vector3.ZERO) -> ArrayMesh:
	var n := PackedVector3Array()
	n.resize(pts.size())
	for i in range(0, pts.size(), 3):
		var fn := (pts[i + 2] - pts[i]).cross(pts[i + 1] - pts[i]).normalized()
		for k in 3:
			if facing != Vector3.ZERO:
				n[i + k] = facing
			elif smooth_normals:
				n[i + k] = pts[i + k].normalized()
			else:
				n[i + k] = fn
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_NORMAL] = n
	return _array_mesh(arr)


static func _array_mesh(arr: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The island's ragged edge.
static func edge(a: float) -> float:
	return 1 + .045 * sin(3 * a) + .03 * sin(7 * a + 1) + .02 * sin(13 * a + 2)


## Bend a cylinder's rim into the island's outline; rough also crumbles everything below its top.
static func wobble(prim: PrimitiveMesh, rough := 0.0) -> ArrayMesh:
	var arr := prim.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var top := -INF
	for p in v:
		top = max(top, p.y)
	var jitter := {}
	for i in v.size():
		var p := v[i]
		var key := Vector3i(roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000))
		if Vector2(p.x, p.z).length() >= .01:
			var k := edge(atan2(p.z, p.x))
			p.x *= k
			p.z *= k
		if rough > 0 and p.y <= top - .01:
			if not jitter.has(key):
				jitter[key] = Vector3((rnd() - .5) * rough, (rnd() - .5) * rough * .6, (rnd() - .5) * rough)
			p += jitter[key]
		v[i] = p
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TANGENT] = null
	return _array_mesh(arr)


# ---------- Things the island and its neighbours share ----------

static func floating(parent: Node3D, m: Array) -> void:
	noshadow(mesh(wobble(cyl(5.4, 5.3, .5, 40, 1)), m[0], 0, -.25, 0, parent))
	noshadow(mesh(wobble(cyl(5.32, 4.7, .8, 40, 1)), m[1], 0, -.88, 0, parent))
	var rock := mesh(wobble(cone(4.75, 4.4, 14, 5), .55), m[2], 0, -3.48, 0, parent)
	rock.rotation.x = PI
	noshadow(rock)


static func tree(parent: Node3D, x: float, z: float, s: float, c1: String, c2: String, t := "", mk := Callable()) -> Node3D:
	if not mk.is_valid():
		mk = func(c: String) -> ShaderMaterial: return mat(c)
	var g := group(null, t)
	mesh(cyl(.13 * s, .22 * s, 1.05 * s, 7), mk.call("#9C6B4E"), 0, .52 * s, 0, g)
	mesh(ico(.82 * s, 0), mk.call(c1), 0, 1.38 * s, 0, g)
	mesh(ico(.56 * s, 0), mk.call(c2), .16 * s, 1.98 * s, .06 * s, g).rotation.y = .6
	g.position = Vector3(x, 0, z)
	g.rotation.y = rnd() * 6
	parent.add_child(g)
	return g


static func pine(parent: Node3D, x: float, z: float, s: float, mk := Callable()) -> Node3D:
	if not mk.is_valid():
		mk = func(c: String) -> ShaderMaterial: return mat(c)
	var g := group()
	mesh(cyl(.08 * s, .12 * s, .5 * s, 6), mk.call("#9C6B4E"), 0, .25 * s, 0, g)
	mesh(cone(.62 * s, 1.1 * s, 7), mk.call("#4FA866"), 0, .95 * s, 0, g)
	mesh(cone(.45 * s, .85 * s, 7), mk.call("#5DBA72"), 0, 1.45 * s, 0, g)
	g.position = Vector3(x, 0, z)
	g.rotation.y = rnd() * 6
	parent.add_child(g)
	return g


## Batch the still, untagged meshes under root into one mesh per material, so a level
## costs a few dozen draw calls instead of hundreds. Tagged things (what Mo and Bo can
## name), bodies that move, and anything marked "keep" stay as they are.
static func merge_static(root: Node3D) -> void:
	var groups := {}
	var inv := root.global_transform.affine_inverse()
	var done := []
	_merge_collect(root, groups, done)
	for k in groups:
		var g: Dictionary = groups[k]
		var st := SurfaceTool.new()
		for part in g.parts:
			st.append_from(part[0], part[1], inv * part[2].global_transform)
		var am := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = g.mat
		mi.cast_shadow = g.shadow
		mi.set_meta("merged", true)
		root.add_child(mi)
	for n in done:
		n.get_parent().remove_child(n)
		n.free()


static func _merge_collect(node: Node, groups: Dictionary, done: Array) -> void:
	for c in node.get_children():
		if c.has_meta("tag") or c.has_meta("body") or c.has_meta("keep") or c.has_meta("merged"):
			continue
		if c is Node3D and not c.visible:
			continue
		if c is MeshInstance3D and c.mesh and c.get_child_count() == 0:
			var ok := true
			for si in c.mesh.get_surface_count():
				var m: Material = c.get_active_material(si)
				if not (m is ShaderMaterial) or (m as ShaderMaterial).shader == GLOW:
					ok = false
			if not ok:
				continue
			for si in c.mesh.get_surface_count():
				var m: Material = c.get_active_material(si)
				var k := [m, c.cast_shadow]
				if not groups.has(k):
					groups[k] = {mat = m, shadow = c.cast_shadow, parts = []}
				groups[k].parts.append([c.mesh, si, c])
			done.append(c)
		elif not (c is MeshInstance3D):
			_merge_collect(c, groups, done)


static func rot(n: Node3D, x: float, y: float, z: float) -> Node3D:
	n.rotation = Vector3(x, y, z)
	return n
