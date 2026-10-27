class_name Props
extends RefCounted
## Free CC0 models (see assets/LICENSES.md), dressed in the game's own lit material so they
## share the mock's light and palette: Kenney's Nature Kit for the island, KayKit's
## Dungeon Remastered for the dungeon.

const KENNEY := "res://assets/kenney_nature/"
const KAYKIT := "res://assets/kaykit_dungeon/"
const KAYKIT_TEX := "res://assets/kaykit_dungeon/dungeon_texture.png"
const QUAT := "res://assets/quaternius_nature/"

## Kenney's colours by material name, pulled onto the mock's palette.
const PALETTE := {
	grass = "#7CC062", leafsGreen = "#6CC06A", leafsDark = "#4FA866",
	woodBark = "#9C6B4E", woodBarkDark = "#7E5640", woodInner = "#E8C9A0",
	dirt = "#B4ADA4", stone = "#C9C3BA", colorRed = "#E9524B", colorYellow = "#FFD45C",
	colorPurple = "#B79CFF", colorTan = "#E8C9A0", _defaultMat = "#FFF8EE",
}
## How much each kind of plant gives to the wind.
const SWAY := {grass = .5, leafsGreen = .03, leafsDark = .03, woodBark = .03, woodBarkDark = .03, colorRed = .5, colorYellow = .5, colorPurple = .5}

static var _models := {}


## The parts of a model ({mesh, xf}), with materials swapped for the game's own.
## colours overrides the palette per material name; sway scales the wind (0 = still).
static func model(path: String, colours := {}, sway := 1.0, tint := "#FFFFFF") -> Array:
	var key := path + str(colours) + str(sway) + tint
	if _models.has(key):
		return _models[key]
	var parts := []
	var root: Node = load(path).instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p and p != root:
			xf = p.transform * xf
			p = p.get_parent()
		var mesh: Mesh = mi.mesh.duplicate()
		for s in mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			var nm := src.resource_name if src else "_defaultMat"
			var m: ShaderMaterial
			if path.begins_with(KAYKIT):
				m = Build.mat(tint, {tex = KAYKIT_TEX, flat = false, roughness = .85})
			elif path.begins_with(QUAT):
				# Quaternius: textured; leaves and petals are cut-out cards that sway
				var leafy: bool = src is BaseMaterial3D and src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				var bark := nm.begins_with("Bark")
				var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
				var o := {tex = tex, flat = false, roughness = .9, cutout = leafy, sway = (.012 if bark or leafy and nm.begins_with("Leaves_") else .3) * sway if (leafy or bark or nm == "Grass") else 0.0}
				if bark or path.contains("Rock"):
					# Trunks and rocks darken toward the ground they stand in
					o.merge({ao = .4, ao_h = .9})
				m = Build.mat(tint, o)
			else:
				var c: String = colours.get(nm, PALETTE.get(nm, "#FFFFFF"))
				var o := {sway = SWAY.get(nm, 0.0) * sway}
				if nm in ["stone", "dirt", "woodBark", "woodBarkDark"]:
					o.merge({ao = .35, ao_h = .5})
				m = Build.mat(c, o)
			mesh.surface_set_material(s, m)
		parts.append({mesh = mesh, xf = xf})
	root.free()
	_models[key] = parts
	return parts


## Put a model in the world: at (x, y, z), turned yaw, scaled s. Returns its node.
static func place(parent: Node3D, path: String, pos: Vector3, yaw := 0.0, s := 1.0, o := {}) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	g.scale = Vector3.ONE * s if not o.has("scale3") else o.scale3
	for part in model(path, o.get("colours", {}), o.get("sway", 1.0), o.get("tint", "#FFFFFF")):
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		mi.transform = part.xf
		if not o.get("shadow", true):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi)
	if o.get("nohit", false):
		Build.nohit(g)
	parent.add_child(g)
	return g


static func kenney(parent: Node3D, name: String, x: float, z: float, s := 1.0, o := {}) -> Node3D:
	return place(parent, KENNEY + name + ".glb", Vector3(x, o.get("y", 0.0), z), o.get("yaw", Build.rnd() * TAU), s, o)


static func kaykit(parent: Node3D, name: String, pos: Vector3, yaw := 0.0, s := 1.0, o := {}) -> Node3D:
	return place(parent, KAYKIT + name + ".gltf.glb", pos, yaw, s, o)


## The height a model stands, in its own units.
static func height(path: String) -> float:
	var box := AABB()
	var first := true
	for part in model(path):
		var b: AABB = part.xf * part.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.end.y


## A model (or any mesh) as a PackedScene, the form Terrain3D's instancer takes.
static func packed(path_or_mesh, colours := {}, sway := 1.0) -> PackedScene:
	var root := Node3D.new()
	var parts: Array = [{mesh = path_or_mesh, xf = Transform3D.IDENTITY}] if path_or_mesh is Mesh else model(path_or_mesh, colours, sway)
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		mi.transform = part.xf
		root.add_child(mi)
		mi.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


static var _imp := {}


## A Quaternius tree or bush with two levels of detail for Terrain3D's instancer: the real
## model (LOD0) and its baked picture on a camera-facing card (LOD1, also its shadow).
static func with_impostor(name: String, sway := 1.0) -> PackedScene:
	if _imp.is_empty():
		_imp = JSON.parse_string(FileAccess.get_file_as_string(QUAT + "impostors/impostors.json"))
	var root := Node3D.new()
	var parts := model(QUAT + name + ".gltf", {}, sway)
	var lod0 := MeshInstance3D.new()
	lod0.name = "LOD0"
	lod0.mesh = parts[0].mesh
	lod0.transform = parts[0].xf
	root.add_child(lod0)
	lod0.owner = root
	var info: Dictionary = _imp[name]
	var q := QuadMesh.new()
	q.size = Vector2(info.side, info.side)
	q.center_offset = Vector3(info.cx, info.cy + info.side / 2.0, 0)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/impostor.gdshader")
	m.set_shader_parameter("picture", load(QUAT + "impostors/" + name + ".png"))
	q.material = m
	var lod1 := MeshInstance3D.new()
	lod1.name = "LOD1"
	lod1.mesh = q
	root.add_child(lod1)
	lod1.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps
