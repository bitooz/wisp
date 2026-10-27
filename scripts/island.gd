extends Level
## The island: home, and big enough to explore. A village with a house, a pond, a
## campfire and a lantern on a stump; a dirt path winding north to a stone door in the
## big hill, whose rune hums; hills, woods, a beach and the sea all round. Far off the
## north-east shore the next island sleeps; an old brazier on that shore lights a bridge of light to it,
## if someone brings it fire from under the hill.
##
## Days come and go (clock.gd): the sun crosses the sky, evening goes gold, and the night is dark but for the
## moon, the campfire (lit in the evening), the house's window and whatever light you carry. There's food (apples
## fall under the big tree, the larder at home) and a bed indoors; both are back each morning.
##
## The ground is a Terrain3D terrain (addons/terrain_3d, MIT) generated here from a
## height function: four CC0 ground layers painted by height, slope and the path, and
## grass, flowers, bushes, trees and rocks scattered through its instancer.

const SHORE := 58.0
const VILLAGE := Vector2(0, 18)
const SPAWN := Vector3(0, 0, 28)
const ARCH := Vector3(0, 0, -28)
const DOOR_FRONT := Vector2(0, -24)
const POND := Vector3(-11, 0, 22)
const POND_R := 4.2
const HOUSE := Vector2(-8, 13)
const MUSH := Vector2(-3.5, 10.5)
const CAMPFIRE := Vector2(5, 21)
const STUMP := Vector2(8.5, 19)
const BIG_TREE := Vector2(9.5, 10.5)
const PATH := [Vector2(0, 27), Vector2(-1.5, 16), Vector2(2.5, 6), Vector2(-2, -6), Vector2(1.5, -16), Vector2(0, -24)]
const FAR_AT := Vector3(62, 4.0, -80)
const FAR_SCALE := 3.0
const HAZE_DAY := Color("#D6EAF8")
const HAZE_DUSK := Color("#5E4F8A")
const HAZE_NIGHT := Color("#070A18")
## Where the apples fall round the big tree (offsets), and how filling one is
const APPLES := [Vector2(1.5, .7), Vector2(-1.1, 1.3), Vector2(.4, -1.6), Vector2(1.7, -.9)]
const APPLE_FOOD := .3
## Meals in the larder at home, each day
const LARDER := 6
## The campfire burns from evening to morning
const FIRE_FROM := 17.5
const FIRE_TO := 7.5
const MAP := 256

# Day and dusk, as linear colours (three.js lerps them in linear space)
var DAY := {sky = Color("#E8F4FF").srgb_to_linear(), gnd = Color("#A8936F").srgb_to_linear(), sun = Color("#FFF1DC").srgb_to_linear()}
var DUSK := {sky = Color("#9C97D6").srgb_to_linear(), gnd = Color("#6E5A6A").srgb_to_linear(), sun = Color("#FFA77E").srgb_to_linear()}
var NIGHT := {sky = Color("#2A3560").srgb_to_linear(), gnd = Color("#151520").srgb_to_linear(), moon = Color("#9DB2FF").srgb_to_linear()}

@onready var sun: DirectionalLight3D = $Sun

var terrain: Terrain3D
var noise := FastNoiseLite.new()
var heights := PackedFloat32Array()
var water_y := 2.0
var arch: Node3D
var far: Node3D
var far_mats := []
var far_gem_m: ShaderMaterial
var big_tree: Node3D
var house: Node3D
var mush: Node3D
var pond: Node3D
var campfire: Node3D
var lantern: Node3D
var fire: Dictionary
var fire_light: OmniLight3D
var fire_sound: AudioStreamPlayer3D
var lantern_light: OmniLight3D
## The homes you can walk into (houses.gd): "house" (Mo and Bo's) and each islander's, by id
var homes := {}
## The one you're in now (or null), for the camera
var home_in: Houses.House
var rune_glow: MeshInstance3D
var clouds: Node3D
var bridge := []
var brazier: Node3D
var brazier_fire: Dictionary
var brazier_light: OmniLight3D
var lighting := false
var BA := Vector3()
var BB := Vector3()

var village := Village.new()
var pollen: CPUParticles3D
var fireflies: CPUParticles3D
var cloud_shadows := []
## How evening (twilight) and night it is now, from the clock
var dusk_t := 0.0
var night_t := 0.0
var larder := LARDER
var apples := []
var bridge_built := false


func _init() -> void:
	id = "isle"
	outdoors = true
	cam_dist = 7.5
	follow = true
	speed = 4.2
	fov = 55.0
	names.merge({house = "house", tree = "big tree", campfire = "campfire", mushroom = "mushroom", pond = "pond", lantern = "lantern", far = "island", apple = "apple"})
	said = {house = "our house", tree = "the big tree", campfire = "the campfire", mushroom = "a giant mushroom", pond = "the pond", lantern = "a lantern"}
	labels = {door = "the glowing door", far = "the next island", tree = "the big tree", house = "our house", campfire = "the campfire",
		mushroom = "the giant mushroom", pond = "the pond", lantern = "the lantern", brazier = "the old brazier"}
	noise.seed = 7
	noise.frequency = .035


# ---------- The shape of the land ----------

static func ss(a: float, b: float, x: float) -> float:
	var t: float = clamp((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func shore_radius(a: float) -> float:
	return SHORE * (1.0 + .07 * sin(3.0 * a + .5) + .05 * sin(5.0 * a + 2.0) + .03 * sin(9.0 * a))


static func bump(x: float, z: float, cx: float, cz: float, sigma: float) -> float:
	return exp(-((x - cx) * (x - cx) + (z - cz) * (z - cz)) / (2.0 * sigma * sigma))


static func path_distance(p: Vector2) -> float:
	var best := 1e9
	for i in PATH.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, PATH[i], PATH[i + 1])
		best = min(best, p.distance_to(q))
	return best


## The village's own trails: from each home's door out to the main path (and Nell's down to the beach).
static var _trails := []


static func trails() -> Array:
	if _trails.is_empty():
		var homes_at := {house = [HOUSE, .55]}
		for w in Folk.IDS:
			homes_at[w] = [Folk.HOME[w].at, Folk.HOME[w].yaw]
		for k in homes_at:
			var S: Dictionary = Houses.SPECS[k]
			var at: Vector2 = homes_at[k][0]
			var yaw: float = homes_at[k][1]
			var turn := func(x: float, z: float) -> Vector2: return at + Vector2(x * cos(yaw) + z * sin(yaw), -x * sin(yaw) + z * cos(yaw))
			var door: Vector2 = turn.call(float(S.door_x), S.d / 2 + .6)
			var out: Vector2 = turn.call(float(S.door_x), S.d / 2 + 2.8)
			var best := Vector2()
			var bd := 1e9
			for i in PATH.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(out, PATH[i], PATH[i + 1])
				if q.distance_to(out) < bd:
					bd = q.distance_to(out)
					best = q
			# A bend halfway, so it isn't ruled straight
			var mid := (out + best) / 2 + (best - out).orthogonal().normalized() * minf(1.5, bd * .15)
			_trails.append_array([[door, out], [out, mid], [mid, best]])
		var nell_out: Vector2 = _trails[3 * Folk.IDS.find("nell") + 3][1]
		_trails.append_array([[nell_out, Vector2(6.0, 46.0)], [Vector2(6.0, 46.0), Vector2(4.5, 50.5)]])
		# Round the campfire, and over to the woodpile and the big tree
		_trails.append_array([[Vector2(-1.0, 19.5), Vector2(3.0, 21.5)], [Vector2(1.0, 13.0), Vector2(7.5, 11.5)]])
	return _trails


## How far from the nearest path or trail.
static func trail_distance(p: Vector2) -> float:
	var best := path_distance(p)
	if p.distance_squared_to(Vector2(0, 25)) > 1600.0:
		return best
	for t in trails():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, t[0], t[1])))
	return best


## How far out from the middle, as a share of the way to the shore (1 = waterline).
static func reach(x: float, z: float) -> float:
	return Vector2(x, z).length() / shore_radius(atan2(z, x))


## Each home sits on its own levelled patch: [x, z, the height there]
var _pads := []


func height_at(x: float, z: float) -> float:
	if _pads.is_empty():
		for q in [HOUSE] + Folk.IDS.map(func(w): return Folk.HOME[w].at):
			_pads.append([q.x, q.y, _land(q.x, q.y)])
	var h := _land(x, z)
	for pd in _pads:
		h = lerp(h, float(pd[2]), ss(5.5, 3.6, Vector2(x - pd[0], z - pd[1]).length()))
	return h


func _land(x: float, z: float) -> float:
	var k := reach(x, z)
	var h := 2.4 * ss(1.06, .84, k) - 5.0 * ss(1.0, 1.35, k)
	var inland := ss(1.0, .8, k)
	h += inland * (15.0 * bump(x, z, 0, -46, 13) + 9.0 * bump(x, z, -34, -8, 11) + 7.0 * bump(x, z, 36, -20, 9)
		+ 4.0 * bump(x, z, -24, 34, 7) + 3.0 * bump(x, z, 30, 26, 8))
	h += inland * noise.get_noise_2d(x, z) * 1.4
	var p := Vector2(x, z)
	h = lerp(h, 2.4, ss(16.0, 9.0, p.distance_to(VILLAGE)))
	h = lerp(h, 2.6, ss(6.5, 3.0, p.distance_to(DOOR_FRONT)))
	h -= 1.2 * ss(POND_R + 1.2, POND_R - 1.5, p.distance_to(Vector2(POND.x, POND.z)))
	return h


## The ground's height where you stand (from the terrain itself; a house's floor inside it).
func ground(x: float, z: float) -> float:
	for k in homes:
		var H: Houses.House = homes[k]
		if absf(x - H.node.position.x) < 4.5 and absf(z - H.node.position.z) < 4.5 and H.on_floor(Vector3(x, 0, z)):
			return H.floor_y()
	if terrain:
		var y := terrain.data.get_height(Vector3(x, 0, z))
		if not is_nan(y):
			return y
	return height_at(x, z)


func _terrain() -> void:
	# Heights and painting, one pixel per metre
	heights.resize(MAP * MAP)
	var hi := Image.create_empty(MAP, MAP, false, Image.FORMAT_RF)
	var ci := Image.create_empty(MAP, MAP, false, Image.FORMAT_RF)
	for j in MAP:
		for i in MAP:
			var h := height_at(i - MAP / 2.0, j - MAP / 2.0)
			heights[j * MAP + i] = h
			hi.set_pixel(i, j, Color(h, 0, 0))
	var patch := FastNoiseLite.new()
	patch.seed = 21
	patch.frequency = .08
	for j in MAP:
		for i in MAP:
			var x := i - MAP / 2.0
			var z := j - MAP / 2.0
			var h := heights[j * MAP + i]
			var hx := heights[j * MAP + mini(i + 1, MAP - 1)] - heights[j * MAP + maxi(i - 1, 0)]
			var hz := heights[mini(j + 1, MAP - 1) * MAP + i] - heights[maxi(j - 1, 0) * MAP + i]
			var slope := Vector2(hx, hz).length() * .5
			# 0 grass, 1 dirt, 2 rock, 3 sand
			var w := [0.0, 0.0, 0.0, 0.0]
			var p2 := Vector2(x, z)
			w[1] = max(max(ss(1.9, .9, path_distance(p2)), ss(1.25, .55, trail_distance(p2)) * .9), ss(.6, .85, patch.get_noise_2d(x, z) * .5 + .5) * .7)
			w[2] = max(ss(.55, .9, slope), ss(8.5, 11.5, h))
			w[3] = ss(1.7, .9, h)
			w[0] = max(0.0, 1.0 - max(w[1], max(w[2], w[3])))
			var order := [0, 1, 2, 3]
			order.sort_custom(func(a, b): return w[a] > w[b])
			var base: int = order[0]
			var over: int = order[1]
			var blend := int(255.0 * w[over] / max(w[base] + w[over], 1e-4))
			ci.set_pixel(i, j, Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(over) | Terrain3DUtil.enc_blend(blend)), 0, 0))

	terrain = Terrain3D.new()
	terrain.name = "Terrain"
	terrain.set_meta("keep", true)
	Build.nohit(terrain)
	terrain.mesh_size = int(game.quality.t3d_mesh)
	# The island is kept while they're under the hill: keep the ground's textures to rebuild it on the way back
	terrain.free_editor_textures = false
	terrain.mesh_lods = 6
	# The ground's own shadow pass is costly on phones; trees, rocks and Mo and Bo still cast
	terrain.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_ON if game.quality.get("terrain_shadows", true) else RenderingServer.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)
	# 128 m regions, so the 256 m map centred on the island fills four of them
	terrain.data.change_region_size(128)
	terrain.set_camera(game.camera)
	terrain.material.world_background = Terrain3DMaterial.NONE
	# Terrain3D's standard shader runs at 5 fps on a Galaxy A16; ours is its lightweight one
	terrain.material.shader_override = load("res://shaders/terrain_mobile.gdshader" if game.quality.terrain == "mobile" else "res://shaders/terrain.gdshader")
	terrain.material.shader_override_enabled = true
	var assets := Terrain3DAssets.new()
	# Tints pull the photo textures toward the mock's brighter, softer palette
	var layers := [["grass", Color(1.3, 1.45, 1.05), .18], ["dirt", Color(1.15, 1.02, .9), .22], ["rock", Color(1.15, 1.12, 1.2), .12], ["sand", Color(1.05, 1.0, .92), .2]]
	for i in layers.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = layers[i][0]
		ta.albedo_texture = load("res://assets/terrain/%s_albedo_height.png" % layers[i][0])
		ta.normal_texture = load("res://assets/terrain/%s_normal_rough.png" % layers[i][0])
		ta.albedo_color = layers[i][1]
		ta.uv_scale = layers[i][2]
		assets.set_texture(i, ta)
	terrain.assets = assets
	terrain.data.import_images([hi, ci, null], Vector3(-MAP / 2.0, 0, -MAP / 2.0), 0.0, 1.0)


# ---------- What grows on it ----------

var _mesh_ids := {}


func _mesh_asset(key: String, scene: PackedScene, reach_m: float, shadows: bool) -> int:
	var ma := Terrain3DMeshAsset.new()
	ma.name = key
	ma.scene_file = scene
	ma.lod0_range = reach_m
	ma.fade_margin = 0.0
	ma.cast_shadows = 1 if shadows else 0
	var id_ := terrain.assets.get_mesh_count()
	terrain.assets.set_mesh_asset(id_, ma)
	_mesh_ids[key] = id_
	return id_


## A tree or bush with its impostor as LOD1: the real one up to near, the card beyond, to far.
## The card is also its shadow, which is much cheaper than the real tree's.
func _lod_asset(key: String, scene: PackedScene, near: float, far: float) -> int:
	var ma := Terrain3DMeshAsset.new()
	ma.name = key
	ma.scene_file = scene
	ma.lod0_range = near
	ma.lod1_range = far
	ma.fade_margin = 0.0
	ma.cast_shadows = 1
	ma.shadow_impostor = 1
	var id_ := terrain.assets.get_mesh_count()
	terrain.assets.set_mesh_asset(id_, ma)
	_mesh_ids[key] = id_
	return id_


func _vegetation() -> void:
	var q: Dictionary = game.quality
	var veg: float = q.veg
	var near: float = q.get("tree_near", 45.0)
	var Q := Props.QUAT
	var kinds := {
		grass = _mesh_asset("grass", Props.packed(Grass.clump(int(28 * clamp(veg, .6, 1.0)), .5)), q.grass_range, false),
		tuft = _mesh_asset("tuft", Props.packed(Q + "Grass_Wispy_Short.gltf"), q.grass_range, false),
		clover = _mesh_asset("clover", Props.packed(Q + "Clover_1.gltf"), 30.0, false),
		fern = _mesh_asset("fern", Props.packed(Q + "Fern_1.gltf"), 40.0, false),
		plant = _mesh_asset("plant", Props.packed(Q + "Plant_1.gltf"), 35.0, false),
		flowers_a = _mesh_asset("flowers_a", Props.packed(Q + "Flower_3_Group.gltf"), 40.0, false),
		flowers_b = _mesh_asset("flowers_b", Props.packed(Q + "Flower_4_Group.gltf"), 40.0, false),
		mushroom = _mesh_asset("mushroom", Props.packed(Q + "Mushroom_Common.gltf"), 30.0, false),
		pebble = _mesh_asset("pebble", Props.packed(Q + "Pebble_Round_1.gltf"), 30.0, false),
		bush = _lod_asset("bush", Props.with_impostor("Bush_Common_Flowers"), near * .6, 90.0),
		bush_flowers = _lod_asset("bush_flowers", Props.with_impostor("Bush_Common_Flowers"), near * .6, 90.0),
		tree_1 = _lod_asset("tree_1", Props.with_impostor("CommonTree_1"), near, 220.0),
		tree_2 = _lod_asset("tree_2", Props.with_impostor("CommonTree_2"), near, 220.0),
		tree_3 = _lod_asset("tree_3", Props.with_impostor("CommonTree_3"), near, 220.0),
		tree_5 = _lod_asset("tree_5", Props.with_impostor("CommonTree_5"), near, 220.0),
		pine_1 = _lod_asset("pine_1", Props.with_impostor("Pine_1"), near, 220.0),
		pine_2 = _lod_asset("pine_2", Props.with_impostor("Pine_2"), near, 220.0),
		pine_3 = _lod_asset("pine_3", Props.with_impostor("Pine_3"), near, 220.0),
		pine_5 = _lod_asset("pine_5", Props.with_impostor("Pine_5"), near, 220.0),
		rock = _mesh_asset("rock", Props.packed(Q + "Rock_Medium_1.gltf", {}, 0.0), 150.0, true),
		rock_b = _mesh_asset("rock_b", Props.packed(Q + "Rock_Medium_3.gltf", {}, 0.0), 150.0, true),
		stone = _mesh_asset("stone", Props.packed(Q + "Rock_Medium_2.gltf", {}, 0.0), 80.0, false),
		reeds = _mesh_asset("reeds", Props.packed(Props.KENNEY + "plant_flatTall.glb", {}, 1.0), 50.0, false),
	}
	var xf := {}
	for k in kinds:
		xf[k] = [] as Array[Transform3D]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var forest := FastNoiseLite.new()
	forest.seed = 9
	forest.frequency = .045
	var keep_clear := [[Folk.HOME.nell.at, 4.2], [Folk.HOME.tam.at, 4.2], [Folk.HOME.odo.at, 4.2], [Folk.SPOTS.tam.chore, 2.0], [Folk.SPOTS.odo.hobby, 1.5], [HOUSE, 5.0], [MUSH, 2.0], [CAMPFIRE, 2.5], [STUMP, 1.5], [BIG_TREE, 2.5], [Vector2(POND.x, POND.z), POND_R + .3], [DOOR_FRONT, 5.0], [Vector2(ARCH.x, ARCH.z), 4.0]]
	keep_clear.append_array(village.clear)
	keep_clear.append([Vector2(block.global_position.x, block.global_position.z), 1.2])
	var trunks := []
	var put := func(kind: String, p: Vector3, s: float) -> void:
		xf[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	var step := 1.0 / sqrt(veg)
	var x := -70.0
	while x < 70.0:
		var z := -70.0
		while z < 70.0:
			var px := x + rng.randf() * step
			var pz := z + rng.randf() * step
			z += step
			var k := reach(px, pz)
			if k > .99:
				continue
			var p2 := Vector2(px, pz)
			if keep_clear.any(func(c): return p2.distance_to(c[0]) < c[1]):
				continue
			var h := ground(px, pz)
			var on_path := trail_distance(p2) < 1.5
			var pos := Vector3(px, h, pz)
			var n := terrain.data.get_normal(pos)
			var steep := n.y < .82
			var r := rng.randf()
			if h < 1.4:
				# Beach: stones and the odd rock
				if r < .02:
					put.call("stone", pos - Vector3(0, .15, 0), .25 + rng.randf() * .35)
				elif r < .05:
					put.call("pebble", pos, .8 + rng.randf() * .8)
				continue
			if steep or h > 9.0:
				if r < .045:
					put.call(["rock", "rock_b"][rng.randi() % 2], pos - Vector3(0, .4, 0), .6 + rng.randf() * 1.0)
				elif r < .1 and h < 13.0:
					put.call(["pine_1", "pine_2", "pine_3", "pine_5"][rng.randi() % 4], pos, .55 + rng.randf() * .25)
					trunks.append([px, pz, .45])
				elif r < .16:
					put.call("fern", pos, .5 + rng.randf() * .4)
				continue
			if on_path:
				if r < .03:
					put.call("pebble", pos - Vector3(0, .03, 0), .7 + rng.randf() * .8)
				continue
			var woods := forest.get_noise_2d(px, pz)
			if woods > .28 and r < .06 and p2.distance_to(VILLAGE) > 14.0 and path_distance(p2) > 4.0:
				var kind: String = ["tree_1", "tree_2", "tree_3", "tree_5", "pine_1", "pine_3"][rng.randi() % 6] if h < 5.0 else ["pine_1", "pine_2", "pine_3", "pine_5"][rng.randi() % 4]
				put.call(kind, pos, .55 + rng.randf() * .3)
				trunks.append([px, pz, .5])
				continue
			if woods > .2 and r < .06:
				# The woods' floor: ferns, mushrooms, clover
				put.call(["fern", "fern", "mushroom", "clover", "plant"][rng.randi() % 5], pos, .5 + rng.randf() * .4)
				continue
			if r < .02:
				put.call("bush" if rng.randf() < .6 else "bush_flowers", pos, .55 + rng.randf() * .5)
				continue
			if r < .02 + .04 * (1.0 if woods < 0 else .4):
				put.call(["flowers_a", "flowers_b", "clover", "plant"][rng.randi() % 4], pos, .35 + rng.randf() * .25)
				continue
			if r < .09:
				put.call("tuft", pos, .45 + rng.randf() * .35)
				continue
			if woods < .45 or rng.randf() < .4:
				put.call("grass", pos, .8 + rng.randf() * .6)
		x += step
	# Reeds round the pond
	for i in 22:
		var a := rng.randf() * TAU
		var rr := POND_R + rng.randf() * .8
		var px := POND.x + cos(a) * rr
		var pz := POND.z + sin(a) * rr
		put.call("reeds", Vector3(px, ground(px, pz), pz), 2.0 + rng.randf())
	for k in kinds:
		if xf[k].size():
			terrain.instancer.add_transforms(kinds[k], xf[k])
	obstacles.append_array(trunks)
	print("WISP_WORLD instances ", xf.keys().map(func(k): return "%s=%d" % [k, xf[k].size()]))


# ---------- The village, the door, the far island ----------

## A home (houses.gd) on its levelled patch, its door facing yaw.
func _home(id_: String, at2: Vector2, yaw: float, tag: String) -> Node3D:
	var y := ground(at2.x, at2.y)
	var H := Houses.build(id_, Vector3(at2.x, y, at2.y), yaw, tag)
	add_child(H.node)
	homes[id_] = H
	return H.node


## Which home a shelter tag is ("house", "hut_tam"), or null.
func home_of(t: String) -> Houses.House:
	if t == "house":
		return homes.get("house")
	if t.begins_with("hut_"):
		return homes.get(t.substr(4))
	return null


## Where someone indoors is (pal.gd): in bed when asleep, else at the table. {at, yaw, lift}, or empty.
func inside_spot(where: String, p: Pal) -> Dictionary:
	var H := home_of(where)
	if H == null:
		return {}
	var S: Dictionary
	if p.closed and H.spots.bed.size():
		S = H.spots.bed[(1 if p.id == "bo" else 0) % H.spots.bed.size()]
	else:
		var i := 0
		for o in game.people():
			if o == p:
				break
			if o.inside == where and not o.closed:
				i += 1
		S = H.spots.seat[i % H.spots.seat.size()]
	return {at = H.node.to_global(S.at), yaw = H.node.rotation.y + S.yaw, lift = S.lift}


## Keep a point out of things, and out of the homes' walls (you can go in by the door).
func collide(p: Vector3, r: float, is_wisp: bool) -> Vector3:
	p = super.collide(p, r, is_wisp)
	for k in homes:
		p = homes[k].push(p, r, is_wisp)
	return p


## The camera doesn't pull in for the walls of the house you're in (they're cut away).
func cam_exclude() -> Array:
	if home_in == null:
		return []
	var out := []
	for c in home_in.node.get_children():
		if c is StaticBody3D:
			out.append(c.get_rid())
	return out


## The homes: who's in, the door, the light; and the roof off the one you're in.
var _was_in := {}


func _homes_tick(dt: float, t: float) -> void:
	var eve := maxf(dusk_t, night_t)
	var h: float = game.clock.hour()
	var w: Vector3 = game.wisp_g
	var now := Time.get_ticks_msec() / 1000.0
	var in_now: Houses.House = null
	var people: Array = game.here_all()
	for k in homes:
		var H: Houses.House = homes[k]
		var tag: String = "house" if k == "house" else "hut_" + k
		var someone := false
		for p in people:
			var was: String = _was_in.get(p, "")
			if p.inside != was:
				# In or out by the door: it swings, and you hear it
				if p.inside == tag or was == tag:
					H.door_until = now + 1.6
					if H.door_at().distance_to(w) < 22.0:
						game.sfx.play("doorOpen_1", H.door_at(.2), -12.0, randf_range(.9, 1.1))
			if p.inside == tag:
				someone = true
		var near := H.node.global_position.distance_to(w)
		if H.door_at(.3).distance_to(w) < 2.0:
			H.door_until = maxf(H.door_until, now + .4)
		var inside := H.contains(w, .05)
		if inside:
			in_now = H
		# The hearth's lit in the evening and the early morning, when someone's home
		var fire: bool = (h >= 17.0 or h < 8.5) and (someone or h < 23.0 and h >= 6.0 or k == "house")
		Houses.tick(H, dt, now, eve, fire, near, inside, someone)
		if H.crackle == null:
			H.crackle = game.sfx.loop_at("fire", H.node, -10.0, 9.0)
			H.crackle.position = H.hearth.g.position + Vector3(0, .4, 0)
		var crackle := fire and near < 12.0
		if H.crackle.playing != crackle:
			H.crackle.playing = crackle
	for p in people:
		_was_in[p] = p.inside
	if in_now != home_in:
		if home_in:
			home_in.cutaway(false, Vector3())
		home_in = in_now
		game.sfx.play("doorOpen_1", w, -10.0)
	if home_in:
		home_in.cutaway(true, game.camera.global_position)
	cam_dist = lerpf(cam_dist, 5.2 if home_in else 7.5, 1.0 - exp(-dt * 3.0))

func _ready() -> void:
	Build.reseed(11)
	_terrain()
	water_y = ground(POND.x + POND_R + 1.5, POND.z) - .35
	var mat := func(c: String) -> ShaderMaterial: return Build.mat(c)
	var at := func(p: Vector2) -> Vector3: return Vector3(p.x, ground(p.x, p.y), p.y)

	pond = Build.group(self, "pond")
	pond.position = Vector3(POND.x, water_y, POND.z)
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	water.set_shader_parameter("radius", POND_R + .4)
	Build.noshadow(Build.mesh(Build.disc(POND_R + .4, 48), water, 0, 0, 0, pond)).rotation.x = -PI / 2
	var shore := Build.group(self)
	for i in 22:
		var a := i / 22.0 * TAU + Build.rnd() * .15
		var px := POND.x + cos(a) * (POND_R + .5)
		var pz := POND.z + sin(a) * (POND_R + .5)
		Props.kenney(shore, "stone_small" + "ABCD"[i % 4], px, pz, 2.0 + Build.rnd() * 1.2, {y = ground(px, pz) - .05})
	for q in [[1.2, -.8, 3.2], [-1.6, .9, 2.6], [.4, 2.0, 2.2], [-.5, -2.2, 2.4]]:
		Props.kenney(shore, "lily_large" if q[2] > 2.5 else "lily_small", POND.x + q[0], POND.z + q[1], q[2], {y = water_y + .02, shadow = false, nohit = true, sway = 0.0})

	big_tree = Props.place(self, Props.QUAT + "CommonTree_2.gltf", Vector3(BIG_TREE.x, ground(BIG_TREE.x, BIG_TREE.y), BIG_TREE.y), .4, .95)
	Build.tag(big_tree, "tree")

	house = _home("house", HOUSE, .55, "house")

	mush = Build.group(null, "mushroom")
	Build.mesh(Build.cyl(.16, .21, .55, 10), mat.call("#F6EEE2"), 0, .27, 0, mush)
	Build.mesh(Build.sphere(.52, 18, 9, PI / 2), mat.call("#E9524B"), 0, .5, 0, mush).scale.y = .78
	for i in 6:
		var a := i / 6.0 * TAU
		var r := .3 if i % 2 else .2
		Build.mesh(Build.sphere(.065, 8, 6), mat.call("#FFF8EE"), cos(a) * r, .5 + sqrt(.27 - r * r) * .78 + .01, sin(a) * r, mush)
	mush.position = at.call(MUSH)
	mush.scale = Vector3.ONE * 1.7
	add_child(mush)

	campfire = Build.group(null, "campfire")
	for i in 8:
		var a := i / 8.0 * TAU
		Build.rot(Build.mesh(Build.dodeca(.12), mat.call("#A9A39A"), cos(a) * .42, .07, sin(a) * .42, campfire), Build.rnd() * 3, Build.rnd() * 3, 0)
	for i in 3:
		var l := Build.mesh(Build.cyl(.065, .075, .72, 7), mat.call("#8A5A3F"), 0, .14, 0, campfire)
		l.rotation = Vector3(0, i / 3.0 * TAU, PI / 2 - .35)
		l.position = Vector3(cos(i / 3.0 * TAU) * .05, .16, sin(i / 3.0 * TAU) * .05)
	fire = Build.flames(campfire, [["#FF7A2F", .2, .62], ["#FFB547", .14, .48], ["#FFE491", .08, .32]])
	fire.g.position.y = .18
	Build.nohit(fire.g)
	fire_light = Build.omni("#FF8A3C", 0, 9, 1.5)
	fire_light.position = Vector3(0, .7, 0)
	campfire.add_child(fire_light)
	fire_sound = game.sfx.loop_at("fire", campfire, -6.0, 18.0)
	fire_sound.position.y = .4
	campfire.position = at.call(CAMPFIRE)
	campfire.scale = Vector3.ONE * 1.4
	add_child(campfire)
	# Logs to sit on round the fire
	Props.kenney(self, "log_large", CAMPFIRE.x + 2.0, CAMPFIRE.y + .6, 1.8, {yaw = 1.3, y = ground(CAMPFIRE.x + 2.0, CAMPFIRE.y + .6)})
	Props.kenney(self, "log_large", CAMPFIRE.x - 1.2, CAMPFIRE.y - 1.7, 1.8, {yaw = 2.5, y = ground(CAMPFIRE.x - 1.2, CAMPFIRE.y - 1.7)})

	var stump_y := ground(STUMP.x, STUMP.y)
	Build.mesh(Build.cyl(.24, .28, .36, 9), mat.call("#A87452"), STUMP.x, stump_y + .18, STUMP.y, self).scale = Vector3.ONE * 1.5
	lantern = Build.group(null, "lantern")
	Build.mesh(Build.cyl(.11, .12, .05, 10), mat.call("#3B3B42"), 0, .025, 0, lantern)
	Build.noshadow(Build.mesh(Build.cyl(.095, .095, .2, 10), Build.smooth("#FFF1C2", {emissive = "#FFC45C", ei = .6, roughness = .4, opacity = .95}), 0, .15, 0, lantern))
	Build.mesh(Build.cone(.13, .1, 10), mat.call("#3B3B42"), 0, .3, 0, lantern)
	Build.mesh(Build.torus(.06, .012, 6, 14), mat.call("#3B3B42"), 0, .38, 0, lantern)
	lantern_light = Build.omni("#FFC867", .4, 4.5, 1.6)
	lantern_light.position.y = .16
	lantern.add_child(lantern_light)
	lantern.scale = Vector3.ONE * 2.1
	lantern.position = Vector3(STUMP.x, stump_y + .54, STUMP.y)
	add_child(lantern)

	# The way in: a stone door in the foot of the big hill, its rune humming
	arch = Build.group(null, "door")
	var arch_stone: ShaderMaterial = mat.call("#C9C2B6")
	var hill: ShaderMaterial = mat.call("#A9A296")
	for q in [[-1.25, -.1, .32], [1.2, -.05, .26], [-.9, .25, .18], [1.5, -.4, .4], [-1.7, -.5, .45]]:
		Build.rot(Build.mesh(Build.dodeca(q[2]), hill, q[0], q[2] * .5, q[1], arch), Build.rnd() * 3, Build.rnd() * 3, 0)
	Build.mesh(Build.box(.36, 1.6, .42), arch_stone, -.6, .8, 0, arch)
	Build.mesh(Build.box(.36, 1.6, .42), arch_stone, .6, .8, 0, arch)
	Build.mesh(Build.box(1.66, .34, .5), arch_stone, 0, 1.76, 0, arch)
	# The dark way in, running back into the hill
	Build.noshadow(Build.mesh(Build.box(.86, 1.6, 2.4), Build.basic("#16141D"), 0, .8, -1.25, arch))
	var rune := Build.mesh(Build.torus(.12, .028, 8, 24), Build.basic("#9FE8FF"), 0, 1.76, .26, arch)
	Build.nohit(rune)
	rune_glow = Build.glow("#8FE3FF", 2.6)
	rune_glow.position = rune.position
	arch.add_child(rune_glow)
	arch.position = Vector3(ARCH.x, ground(ARCH.x, ARCH.z + .4) - .1, ARCH.z)
	arch.scale = Vector3.ONE * 1.6
	add_child(arch)

	# The sea all round, with foam on the shore
	var sea := PlaneMesh.new()
	sea.size = Vector2(1600, 1600)
	var sea_m := ShaderMaterial.new()
	sea_m.shader = load("res://shaders/sea.gdshader")
	sea_m.set_shader_parameter("shore", SHORE)
	var sea_mi := Build.noshadow(Build.mesh(sea, sea_m, 0, 0, 0, self))
	Build.nohit(sea_mi)
	sea_mi.set_meta("keep", true)
	sea_mi.visible = game.quality.get("sea", true)

	clouds = Build.group(self)
	Build.nohit(clouds)
	clouds.set_meta("keep", true)
	var cloud_m := Build.mat("#FFFFFF", {roughness = 1.0})
	for i in 9:
		var g := Build.group(clouds)
		var a := i / 9.0 * TAU + Build.rnd()
		var r := 120 + Build.rnd() * 60
		for k in 4:
			Build.noshadow(Build.mesh(Build.ico(.55 + Build.rnd() * .45, 1), cloud_m, k * .7 - 1, Build.rnd() * .3, Build.rnd() * .4, g))
		g.position = Vector3(cos(a) * r, 18 + Build.rnd() * 22, sin(a) * r)
		g.scale = Vector3.ONE * (8 + Build.rnd() * 5)
		g.look_at(Vector3(0, g.position.y, 0), Vector3.UP, true)

	# The next island, asleep until you bring back an ember
	far = Build.group(null, "far")
	var by_colour := {}
	var fmat := func(c: String) -> ShaderMaterial:
		if by_colour.has(c):
			return by_colour[c]
		var m := Build.mat("#8C8B96", {unique = true})
		m.set_meta("c", Color(c).srgb_to_linear())
		far_mats.append(m)
		by_colour[c] = m
		return m
	Build.floating(far, [fmat.call("#A8D97F"), fmat.call("#D9AE84"), fmat.call("#BE967A")])
	for q in [[-2.2, -.8, 1.3], [1.9, 1.4, 1.1], [-.4, 2.6, .9], [2.6, -2, 1.4], [-3.2, 1.6, 1]]:
		Build.pine(far, q[0], q[1], q[2], fmat)
	Build.tree(far, .6, -1.6, 1.5, "#F2A0C0", "#F7BCD3", "", fmat)
	far_gem_m = Build.mat("#5E5C66", {emissive = "#FFB547", ei = 0.0, roughness = .3, unique = true})
	Build.mesh(Build.octa(.55), far_gem_m, -.6, 1.1, .6, far)
	far.scale = Vector3.ONE * FAR_SCALE
	far.position = FAR_AT
	add_child(far)

	# The bridge: from the north-east beach out to the far island, hidden until the ember
	var dir := Vector2(FAR_AT.x, FAR_AT.z).normalized()
	var foot := dir * shore_radius(atan2(dir.y, dir.x)) * .93
	BA = Vector3(foot.x, ground(foot.x, foot.y) + .1, foot.y)
	var near_edge := Vector2(FAR_AT.x, FAR_AT.z) - dir * 5.0 * FAR_SCALE
	BB = Vector3(near_edge.x, FAR_AT.y - .1, near_edge.y)
	var tile_m := Build.mat("#EDE3CD", {emissive = "#FFC873", ei = .8, roughness = .8})
	var d := BB - BA
	var yaw := atan2(d.x, d.z)
	var n := int(d.length() / .85)
	for i in n:
		var k := (i + .5) / n
		var t := Build.mesh(Build.box(1.5, .2, .78), tile_m, 0, 0, 0, self)
		t.position = BA.lerp(BB, k)
		t.position.y -= sin(k * PI) * 1.2
		t.rotation.y = yaw + (Build.rnd() - .5) * .12
		Build.noshadow(t)
		t.visible = false
		t.set_meta("body", true)
		bridge.append(t)

	# The old brazier at the bridge's foot: cold, until someone brings it fire
	brazier = Build.group(null, "brazier")
	var bm := Build.mat("#8E8A86")
	Build.mesh(Build.cyl(.32, .42, .9, 9), bm, 0, .45, 0, brazier)
	Build.mesh(Build.cyl(.55, .34, .3, 12), bm, 0, 1.05, 0, brazier)
	Build.mesh(Build.cyl(.46, .46, .06, 12), Build.mat("#2A2522"), 0, 1.18, 0, brazier)
	brazier_fire = Build.flames(brazier, [["#FF7A2F", .26, .7], ["#FFB547", .18, .52], ["#FFE491", .1, .34]])
	brazier_fire.g.position.y = 1.2
	brazier_fire.g.visible = false
	Build.nohit(brazier_fire.g)
	brazier_light = Build.omni("#FFA347", 0, 9, 1.4)
	brazier_light.position.y = 1.6
	brazier.add_child(brazier_light)
	var bdir := Vector2(BA.x, BA.z).normalized()
	var bat := Vector2(BA.x, BA.z) - bdir * 2.2 + Vector2(-bdir.y, bdir.x) * 1.6
	brazier.position = Vector3(bat.x, ground(bat.x, bat.y), bat.y)
	add_child(brazier)

	sun.look_at_from_position(Vector3(6, 11, 6), Vector3.ZERO)
	sun.directional_shadow_max_distance = game.quality.get("shadow_dist", 55.0)
	sun.shadow_enabled = game.quality.get("sun_shadows", true)
	things = [{t = "door", node = arch}, {t = "far", node = far}, {t = "tree", node = big_tree, hi = .55}, {t = "house", node = house},
		{t = "campfire", node = campfire}, {t = "mushroom", node = mush}, {t = "pond", node = pond},
		{t = "lantern", node = lantern, live = true, carry = true, light = 4.5, hold_scale = .7, hold_y = -.2},
		{t = "brazier", node = brazier}]
	# Windfalls under the big tree
	for i in APPLES.size():
		_apple(i)
	# Their own things: Bo's woodpile and model boat, Mo's shell jar, and shells on the beach
	_life_things()
	# The island's other people: their homes, and what they've lost
	_folk_things()
	# What makes the village lived in round them
	village.build(self)
	# Places they know by name (they live here), seen or not
	var at_shore := func(a: float, k: float) -> Vector3:
		var r := shore_radius(a) * k
		return Vector3(cos(a) * r, 0, sin(a) * r)
	var ne := atan2(BA.z, BA.x)
	places = {"the village": Vector3(VILLAGE.x, 0, VILLAGE.y), "the pond": Vector3(POND.x, 0, POND.z + POND_R + 1.5),
		"the hill with the glowing door": Vector3(DOOR_FRONT.x + 1.5, 0, DOOR_FRONT.y + 4.0),
		"the north-east shore": at_shore.call(ne, .8), "the beach in the south": at_shore.call(PI / 2, .85),
		"the west hills": Vector3(-30, 0, -8), "the east hills": Vector3(31, 0, -18)}
	for w in Folk.IDS:
		places[Folk.HOME[w].what] = homes[w].door_at(1.6)
	# The village's own landmarks (where their chores are, and the evenings)
	places["the campfire"] = Vector3(CAMPFIRE.x, 0, CAMPFIRE.y + 2.4)
	places["the woodpile"] = woodpile.position + Vector3(1.2, 0, .6)
	places["the big tree"] = Vector3(BIG_TREE.x - 1.5, 0, BIG_TREE.y + 2.0)
	places["the house in the village"] = homes.house.door_at(1.6)
	place_words = {trestle = "the house in the village", boat = "the house in the village", larder = "the house in the village", village = "the village",
		fire = "the campfire", firepit = "the campfire", logs = "the woodpile", wood = "the woodpile", apples = "the big tree",
		apple = "the big tree", tree = "the big tree", door = "the hill with the glowing door", hill = "the hill with the glowing door",
		brazier = "the north-east shore", shore = "the north-east shore", beach = "the beach in the south", sea = "the beach in the south",
		shells = "the beach in the south", hives = "Tam's cottage", bees = "Tam's cottage", wheel = "Odo's hut", clay = "the pond"}
	# Where you'd look on getting there
	place_looks = {"the hill with the glowing door": ARCH, "the north-east shore": brazier.position,
		"the campfire": campfire.position, "the woodpile": woodpile.position, "the big tree": big_tree.position}
	# [x, z, radius, low]: round things to go around. You float over the low ones. (Added to what's there:
	# the woodpile, the boat and the jar are in already.)
	# (The homes keep you out of their walls themselves: collide())
	obstacles.append_array([[BIG_TREE.x, BIG_TREE.y, .8], [MUSH.x, MUSH.y, .7, 1], [CAMPFIRE.x, CAMPFIRE.y, .8, 1],
		[STUMP.x, STUMP.y, .5, 1], [POND.x, POND.z, POND_R, 1], [ARCH.x - 1.1, ARCH.z, .5], [ARCH.x + 1.1, ARCH.z, .5],
		[brazier.position.x, brazier.position.z, .5]])
	if game.quality.get("vegetation", true):
		_vegetation()
	solidify()
	settle()
	Houses.bake(village.root, Build.mat("#FFFFFF", {vcol = true}))
	Houses.bake(thing("well").node, Build.mat("#FFFFFF", {vcol = true, ao = .3, ao_h = .8}))
	Build.merge_static(self)
	for g in [mush, campfire, lantern, arch, far, clouds, big_tree, brazier]:
		Build.merge_static(g)
	for k in homes:
		Houses.finish(homes[k])
	_atmosphere()


func enter(opts: Dictionary) -> void:
	if visits > 0 and terrain:
		# Back from under the hill: Terrain3D builds its ground anew on entering the tree
		terrain.set_camera(game.camera)
		terrain.assets.update_texture_list()
		terrain.material.update()
	game.set_fog(true, HAZE_DAY, 45.0, 260.0, .7)
	game.set_pal_glow(0.0)
	game.hud.cave = false
	_daylight(0.0, true)
	if opts.get("back", false):
		# Back from under the hill, just out of the door
		game.stage = "end" if bridge_built else "home"
		game.wisp_g = Vector3(DOOR_FRONT.x, 0, DOOR_FRONT.y + 1.0)
		game.heading = Vector3(0, 0, 1)
		game.az = PI
		game.pol = 1.12
		game.az_goal = null
		var a: Vector2 = game.slot(game.mo)
		var b: Vector2 = game.slot(game.bo)
		game.place_party(game.wisp_g, game.heading, a, b)
	else:
		game.stage = stage_saved if stage_saved != "" else "island"
		game.az = 0.0
		game.pol = 1.12
		game.az_goal = null
		game.place_party(SPAWN, Vector3(0, 0, -1), Vector2(SPAWN.x - .8, SPAWN.z + .9), Vector2(SPAWN.x + .8, SPAWN.z + .9))


## Stay on the island: you can go down to the beach, not into the sea.
## Mo and Bo can wade into the shallows (ankle deep), but no further.
const WADE := 1.045


func bounds(p: Vector3, _r: float, is_wisp: bool) -> Vector3:
	var k := reach(p.x, p.z)
	var R := .985 if is_wisp else WADE
	if k > R:
		p.x *= R / k
		p.z *= R / k
	return p


func say_of(t: String) -> String:
	match t:
		"door":
			return "the glowing door in the hill"
		"far":
			return "the next island, joined to ours by a bridge of light" if bridge_built else "the next island, far over the sea"
		"brazier":
			return "the old stone brazier on the shore, burning" if bridge_built else "an old stone brazier on the shore, cold and empty"
		"lantern":
			return "a lantern (it glows)"
	return said.get(t, "")


func surface(x: float, z: float) -> String:
	if _home_at(Vector3(x, 0, z)) != null:
		return "wood"
	return "dirt" if trail_distance(Vector2(x, z)) < 1.6 else "grass"


## The home whose floor this is, or null.
func _home_at(at: Vector3) -> Houses.House:
	for k in homes:
		if homes[k].contains(at):
			return homes[k]
	return null


func underfoot(at: Vector3) -> String:
	if in_water(at):
		return ""
	if _home_at(at) != null:
		return "wooden floorboards underfoot"
	if ground(at.x, at.z) < 1.4:
		return "soft sand underfoot"
	if path_distance(Vector2(at.x, at.z)) < 1.8:
		return "packed earth underfoot"
	return "grass underfoot"


func in_water(at: Vector3) -> bool:
	return ground(at.x, at.z) < -.03


func touch_at(at: Vector3, r: float) -> String:
	if reach(at.x, at.z) > WADE - .01:
		return "the water gets deeper: too deep to go on"
	for k in homes:
		if homes[k].push(at, r, false).distance_to(at) > .01:
			return "you bumped into something hard"
	return super.touch_at(at, r)


## The fire crackling, the brazier once it's lit, and the sea on the nearest shore.
func sounds_around(p: Pal) -> Array:
	var out := []
	if fire.g.visible:
		out.append([campfire.global_position + Vector3(0, .5, 0), "a fire crackling", 14.0])
	if bridge_built:
		out.append([brazier.global_position + Vector3(0, 1, 0), "a big fire roaring", 25.0])
	var a := atan2(p.position.z, p.position.x)
	var r := shore_radius(a) * 1.02
	out.append([Vector3(cos(a) * r, .3, sin(a) * r), "waves washing on the shore", 22.0])
	return out


## What going through a way sounds like to those nearby.
func way_sound(t: String) -> String:
	return "a heavy door creaking" if t == "door" else super.way_sound(t)


# ---------- For Mo's and Bo's minds ----------

func place_of(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	var k := reach(p.x, p.z)
	var H := _home_at(p)
	if H != null:
		return "inside our house" if H.id == "house" else "inside " + Folk.HOME[H.id].what
	if q.distance_to(DOOR_FRONT) < 9.0:
		return "on the hill, by the glowing door"
	if brazier and q.distance_to(Vector2(brazier.position.x, brazier.position.z)) < 9.0:
		return "on the north-east shore, by the old brazier"
	if q.distance_to(Vector2(POND.x, POND.z)) < POND_R + 3.0:
		return "by the pond, near our house"
	if q.distance_to(VILLAGE) < 13.0:
		return "near our house, in the village"
	if k > .86:
		return "down on the beach, by the sea"
	if path_distance(q) < 2.5:
		return "on the dirt path between the village and the hill"
	if height_at(p.x, p.z) > 7.0:
		return "up on a hill"
	return "out in the meadows and woods of the island"


func region() -> String:
	return "on the island"


func scenery(p: Vector3) -> Array:
	var out := []
	var k := reach(p.x, p.z)
	if k > .7:
		out.append("the sea, %d m away" % roundi((1.0 - k) * shore_radius(atan2(p.z, p.x))))
	if path_distance(Vector2(p.x, p.z)) < 1.8:
		out.append("the dirt path under your feet")
	if dusk_t > .5 or night_t > .5:
		out.append(game.clock.sense())
	return out


func walkable(p: Vector3) -> bool:
	if reach(p.x, p.z) > .9:
		return false
	if Vector2(p.x - POND.x, p.z - POND.z).length() < POND_R + .6:
		return false
	return super.walkable(p)


func use_reach(t: String) -> float:
	if use_reach_life(t) > 0:
		return use_reach_life(t)
	if t == "door":
		return 1.2
	if t == "brazier":
		return 1.0
	if t == "lantern":
		return .7
	return -1.0


func way(t: String) -> Dictionary:
	if t == "door":
		return {to = "cave", opts = {}}
	return {}


func through_by_use(t: String) -> bool:
	return t == "door"


func way_hint(t: String) -> String:
	if t == "door":
		return "pushed it: it swung open, humming, and dark steps lead down under the hill. I could go into it"
	return super.way_hint(t)


func use(p: Pal, t: String) -> String:
	match t:
		"brazier":
			if bridge_built:
				return "warmed my hands at the fire"
			if p.held and p.held.t == "ember":
				var T: Dictionary = p.let_go()
				T.node.reparent(brazier, false)
				T.node.position = Vector3(0, 1.25, 0)
				T.node.scale = T.get("ground_scale", Vector3.ONE)
				await _light_bridge()
				game.minds.news_seen(brazier.global_position + Vector3(0, 1, 0), p.id, "%s lit the old brazier on the north-east shore, and a bridge of light grew out over the sea" % p.pal_name, .6, "news", "", [game.minds.of(p)])
				return "put %s in it: it caught fire with a roar, and something bright grew out over the sea" % T.get("what", "it")
			if p.held and p.held.get("light", 0.0) > 0:
				p._gesture("point")
				return "held %s to it; nothing caught" % p.held.get("what", "it")
			p._gesture("point")
			return "looked in: a cold stone bowl, old ash and scorch marks"
		"far":
			p._gesture("point")
			return "it's too far over the water to reach"
		"mushroom":
			p.bounce()
			game.hearing.make(mush.global_position, id, "a springy boing", 10.0, p)
			# Seen by anyone: that's funny
			for o in game.people():
				var om: Mind = game.minds.of(o)
				if o != p and o.place_id == id and not om.body.asleep and om._sees(p):
					om.heart.shared(p.id, "the time %s went boing off the giant mushroom" % p.pal_name, om.mem.life_h, true)
					game.minds.of(p).heart.shared(o.id, "the time you went boing off the giant mushroom", game.minds.of(p).mem.life_h, true)
			# Something to tell the others about
			game.minds.news_seen(mush.global_position + Vector3(0, .8, 0), p.id, "%s went boing off the giant mushroom" % p.pal_name, .2, "news", "", [game.minds.of(p)])
			return "bounced on it: springy!"
		"pond":
			p.crouch = 1
			game.get_tree().create_timer(.4).timeout.connect(func(): p.crouch = 0)
			game.minds.of(p).body.wet_hands = 1.0
			game.hearing.make(pond.global_position, id, "a splash of water", 12.0, p)
			return "splashed my hand in the water; it's cold, and now my hand's wet"
		"campfire":
			if _log_in(p):
				var L: Dictionary = p.let_go()
				L.node.queue_free()
				if fire.g.visible:
					game.hearing.make(campfire.global_position, id, "a fire flaring up and crackling", 12.0, p)
					return "put %s on the fire: it flared up, crackling" % L.get("what", "the log")
				wood = mini(WOOD_MOST, wood + 1)
				_show_wood()
				return "laid %s by the fire pit, ready for tonight's fire" % L.get("what", "the log")
			if fire.g.visible:
				return "warmed my hands at the fire"
			p._gesture("point")
			return "poked the cold ashes; nobody's lit it yet"
		"house":
			if p.held and String(p.held.t).begins_with("apple"):
				# Mo's chore: windfalls for the larder
				var T: Dictionary = p.let_go()
				T.node.queue_free()
				larder += 1
				return "went in and put %s in the larder" % T.get("what", "the apple")
			return "went in for a moment: our house, warm and familiar, nothing new. Came back out"
		"woodpile":
			if _log_in(p):
				var L: Dictionary = p.let_go()
				L.node.queue_free()
				wood = mini(WOOD_MOST, wood + 1)
				_show_wood()
				game.hearing.make(woodpile.global_position, id, "a log thunking onto a pile", 8.0, p)
				return "put %s on the woodpile" % L.get("what", "the log")
			var axe_held: bool = p.held != null and not p.held.is_empty() and p.held.t == "axe"
			if not axe_held and thing("axe").is_empty():
				p._gesture("point")
				return "went to chop wood, but the axe isn't in the chopping block; someone's got it, or left it somewhere"
			var mind: Mind = game.minds.of(p)
			if not mind.try_skill("chopping", .05):
				game.hearing.make(woodpile.global_position, id, "a dull thunk", 10.0, p)
				return "swung the axe, but it glanced off the log: no wood chopped this time"
			# The better at it, the more each go gets done
			wood = mini(WOOD_MOST, wood + (2 if mind.skills.level.chopping >= .75 else 1))
			_show_wood()
			# A split log or two left by the block, to carry
			_set_logs(LOOSE_LOGS)
			game.hearing.make(woodpile.global_position, id, "the thock of an axe on wood", 15.0, p)
			game.sfx.play("impactSoft_heavy_00%d" % (randi() % 3), block.global_position + Vector3(0, .5, 0), -4.0, randf_range(.8, 1.0))
			return "chopped some wood with the axe%s and stacked it on the pile" % ("" if axe_held else " from the chopping block") + (": it's a good big pile now" if wood >= 10 else "")
		"boat":
			if p == game.bo:
				var bm: Mind = game.minds.of(p)
				if not bm.try_skill("building", .1):
					return "tried to fit the next piece of my boat, but it wouldn't sit right; had to take it off again"
				var before := Life.boat_words(boat_k)
				boat_k = minf(1.0, boat_k + (.15 if bm.skills.level.building >= .75 else .1))
				_show_boat()
				var after := Life.boat_words(boat_k)
				return "worked on my model boat" + (": " + after if after != before else "")
			return "had a look at Bo's model boat: " + Life.boat_words(boat_k)
		"well":
			p.crouch = 1
			game.get_tree().create_timer(.6).timeout.connect(func(): p.crouch = 0)
			game.hearing.make(Vector3(Village.WELL.x, ground(Village.WELL.x, Village.WELL.y) + .8, Village.WELL.y), id, "a bucket splashing down a well, and the creak of a crank", 12.0, p)
			game.minds.of(p).body.wet_hands = 1.0
			return "wound the bucket up from the well and had a drink: the water's cold and clear"
		"jar":
			if p.held and String(p.held.t).begins_with("shell") and p == game.mo:
				var T: Dictionary = p.let_go()
				T.node.queue_free()
				jar_n += 1
				_show_jar()
				return "put the shell in my jar; %s" % jar_words()
			return ("looked at my shell jar: " if p == game.mo else "looked at Mo's shell jar: ") + jar_words()
	return await super.use(p, t)


## The ember in the brazier: the bridge to the next island.
func _light_bridge() -> void:
	lighting = true
	brazier_fire.g.visible = true
	Build.set_light(brazier_light, 9.0)
	game.sfx.play("maximize_006", brazier.global_position, -2.0)
	for t in bridge:
		t.visible = true
		t.scale = Vector3.ONE * .01
		game.tween(.42, func(k): t.scale = Vector3.ONE * max(.01, game.back_out(k)))
		await game.wait(.05)
	var wake := func(k):
		for m in far_mats:
			Build.set_color(m, Color("#8C8B96").srgb_to_linear().lerp(m.get_meta("c"), k).linear_to_srgb())
		Build.set_color(far_gem_m, Color("#FFB547"))
		Build.set_glow(far_gem_m, 1.6 * k)
	await game.tween(1.5, wake)
	bridge_built = true
	game.hearing.make(brazier.global_position, id, "a roar of fire and a deep, bright hum", 90.0)
	game.minds.changed()
	game.stage = "end"


func near_arch() -> bool:
	return Vector2(game.wisp_g.x - ARCH.x, game.wisp_g.z - ARCH.z).length() < 7.0


func tick(dt: float, t: float) -> void:
	_daylight(dt, false)
	_homes_tick(dt, t)
	clouds.rotation.y += dt * .012
	_weather(dt, t)
	Build.glow_opacity(rune_glow, .55 + sin(t * 2.4) * .3)
	if bridge_built:
		Build.flicker(brazier_fire, t, dt)
	if game.embers > 0 and not bridge_built and not lighting and brazier.position.distance_to(game.wisp_g) < 2.5:
		# The light itself carries the ember to the brazier
		lighting = true
		_light_bridge()
	Build.flicker(fire, t, dt)
	if fire_sound.playing != fire.g.visible:
		fire_sound.playing = fire.g.visible
	if fire.g.visible:
		Build.set_light(fire_light, 10 + sin(t * 17) * 1.4 + sin(t * 7.3) * 1.1)


# ---------- Day and night ----------

## The sky, the sun (the moon at night), the haze and the island's own lights, from the time of day.
func _daylight(dt: float, snap: bool) -> void:
	var c: Clock = game.clock
	var day := c.daylight()
	dusk_t = c.twilight()
	night_t = c.night()
	var eve := maxf(dusk_t, night_t)
	game.set_hemi(DAY.sky.lerp(DUSK.sky, dusk_t).lerp(NIGHT.sky, night_t), DAY.gnd.lerp(DUSK.gnd, dusk_t).lerp(NIGHT.gnd, night_t),
		lerpf(lerpf(1.15, .62, dusk_t), .05, night_t))
	# The sun goes over from east to west; at night the moon, dim and blue, from the other side
	var a := (c.hour() - 6.0) / 12.0 * PI
	var up := c.sun_height() > -.05
	if not up:
		a += PI
	sun.look_at_from_position(Vector3(cos(a) * 12.0, maxf(1.5, absf(sin(a)) * 11.0), 6.0), Vector3.ZERO)
	if up:
		Build.set_light(sun, 2.4 * smoothstep(-.05, .25, c.sun_height()) * lerpf(1.0, .55, dusk_t))
		sun.light_color = DAY.sun.lerp(DUSK.sun, dusk_t).linear_to_srgb()
	else:
		Build.set_light(sun, .12 * night_t)
		sun.light_color = NIGHT.moon.linear_to_srgb()
	game.hud.dusk_goal = dusk_t * (1.0 - night_t * .5)
	game.hud.night = night_t
	if snap:
		game.hud.dusk = game.hud.dusk_goal
	# Night closes in: the haze darkens and comes nearer
	game.set_fog_colour(HAZE_DAY.lerp(HAZE_DUSK, dusk_t).lerp(HAZE_NIGHT, night_t))
	game.set_fog_depth(lerpf(45.0, 10.0, night_t), lerpf(260.0, 55.0, night_t))
	Build.set_light(lantern_light, lerpf(.4, 2.4, eve))
	Build.set_glow(village.lamp_m, smoothstep(.25, .7, eve) * 2.2)
	for g in village.lamp_glows:
		g.visible = eve > .3
		Build.glow_opacity(g, smoothstep(.3, .8, eve) * .8)
	village.bees.emitting = c.daylight() > .5
	Build.set_light(game.wisp_light, lerpf(.4, 4.0, eve))
	game.wisp_light.omni_range = 6.0
	var burning := fire_burning()
	if burning != fire.g.visible:
		fire.g.visible = burning
		Build.set_light(fire_light, 0.0)
	if home_in:
		game.sfx.ambience("indoors", -9.0)
	else:
		game.sfx.ambience("island_dusk" if eve > .5 else "island_day", -7.0)


## The campfire burns from evening to morning, if there's wood for it: lighting it takes a log from the pile.
func fire_burning() -> bool:
	var h: float = game.clock.hour()
	if not (h >= FIRE_FROM or h < FIRE_TO):
		return false
	var evening: int = game.clock.day() - (1 if h < FIRE_TO else 0)
	if fire_evening == evening:
		return true
	if fire_tried == evening:
		return false
	fire_tried = evening
	if wood > 0:
		wood -= 1
		fire_evening = evening
		_show_wood()
		return true
	return false


## A windfall apple under the big tree.
func _apple(i: int) -> Dictionary:
	var g := Build.group(null, "apple_%d" % i)
	Build.mesh(Build.sphere(.12, 12, 9), Build.smooth("#D63A2C", {roughness = .45}), 0, .12, 0, g)
	Build.rot(Build.mesh(Build.box(.07, .015, .04), Build.mat("#4E8A3A"), .04, .25, 0, g), 0, 0, .5)
	var o: Vector2 = BIG_TREE + APPLES[i]
	g.position = Vector3(o.x, ground(o.x, o.y), o.y)
	add_child(g)
	var T := {t = "apple_%d" % i, node = g, carry = true, food = APPLE_FOOD, hold_y = -.1}
	things.append(T)
	labels[T.t] = "an apple"
	names[T.t] = "apple"
	return T


## Morning: new windfalls and shells, and the larder's full again.
func new_day() -> void:
	larder = LARDER
	_axe_in_block()
	_set_logs(LOOSE_LOGS)
	_set_shells(SHELLS.size())
	for i in APPLES.size():
		var t := "apple_%d" % i
		if not thing(t).is_empty() or game.people().any(func(p): return p.held and p.held.t == t):
			continue
		var T := _apple(i)
		T.box = Level.box_of(T.node)
		grab_volume(T)


func ambient_light() -> float:
	var c: Clock = game.clock
	return maxf(c.daylight(), .03 + .22 * c.twilight() * (1.0 - c.night()))


func chill() -> float:
	return .7 * (1.0 - game.clock.daylight())


func light_spots() -> Array:
	var out := super.light_spots()
	if fire.g.visible:
		out.append([campfire.global_position, 7.0])
	if bridge_built:
		out.append([brazier.global_position, 8.0])
	if maxf(dusk_t, night_t) > .3:
		# Light from the windows and the open door, and the room's own inside
		for k in homes:
			out.append([homes[k].door_at(.8), 3.0])
			out.append([homes[k].node.global_position, maxf(homes[k].w, homes[k].d) * .6])
	return out


func warmth_at(at: Vector3) -> float:
	var w := 0.0
	if fire.g.visible:
		w = maxf(w, smoothstep(4.5, 1.6, Vector2(at.x - campfire.position.x, at.z - campfire.position.z).length()))
	if bridge_built:
		w = maxf(w, smoothstep(4.0, 1.4, Vector2(at.x - brazier.position.x, at.z - brazier.position.z).length()))
	return w


## The house is home: a bed for the night, a larder, a door to go in by.
func shelter(t: String) -> Dictionary:
	if t.begins_with("hut_") and huts.has(t.substr(4)):
		var w := t.substr(4)
		return {door = collide(homes[w].door_at(.75), .34, false), what = Folk.HOME[w].what, who = w}
	if t != "house":
		return {}
	return {door = collide(homes.house.door_at(.75), .34, false), what = "our house"}


func eat_at(p: Pal, t: String) -> Dictionary:
	if t.begins_with("hut_"):
		# At home, there's always something; and a neighbour who's in will give you a bite
		var w := t.substr(4)
		if p.id == w:
			return {food = .55, said = "had a meal at home"}
		var o: Mind = game.minds.by_id(w)
		if o != null and o.pal.place_id == id and not o.body.asleep and o.pal.position.distance_to(shelter(t).door) < 8.0:
			o.remember("did", "gave %s something to eat" % p.pal_name)
			game.minds.of(p).heart.helped(w)
			return {food = .45, said = "knocked at %s and %s gave me %s" % [Folk.HOME[w].what, o.pal.pal_name, Folk.TREAT[w]]}
		return {food = 0.0, said = "knocked at %s for something to eat, but nobody's home" % Folk.HOME[w].what}
	if t != "house":
		return {}
	if larder <= 0:
		return {food = 0.0, said = "went in to find something to eat, but the larder's bare: we've eaten it all today"}
	larder -= 1
	return {food = .55, said = "went in and had bread and cheese from the larder at home" + ("; that's the last of it" if larder == 0 else "")}


# ---------- Their own things ----------

const WOOD_MOST := 12
const SHELLS := [Vector2(-2.0, 53.2), Vector2(1.5, 52.6), Vector2(4.0, 53.5)]
var wood := 6
var boat_k := 0.0
var jar_n := 0
var fire_evening := -1
var fire_tried := -1
var woodpile: Node3D
var block: Node3D
## Split logs lying about, to carry (to the pile or the fire): by the chopping block, and ready by the fire pit
const LOOSE_LOGS := 4
var boat: Node3D
var jar: Node3D
var _logs: Node3D
var _boat_parts: Array = []
var _jar_shells: Node3D


func _life_things() -> void:
	var at := func(p: Vector3) -> Vector3: return Vector3(p.x, ground(p.x, p.z), p.z)
	# Bo's woodpile, by the campfire: a rack, and as many logs as there are
	woodpile = Build.group(null, "woodpile")
	var rack: ShaderMaterial = Build.mat("#7A5236", {ao = .3})
	Build.mesh(Build.box(1.6, .1, .8), rack, 0, .05, 0, woodpile)
	for q in [[-.78, -.38, 1.55], [.78, -.38, 1.55], [-.78, .38, 1.15], [.78, .38, 1.15]]:
		Build.mesh(Build.box(.09, q[2], .09), rack, q[0], q[2] / 2, q[1], woodpile)
	# A lean-to roof over it
	var lean := Build.mesh(Build.box(1.9, .07, 1.2), Build.mat("#8E6A48"), 0, 1.38, 0, woodpile)
	lean.rotation.x = .33
	_logs = Build.nohit(Build.group(woodpile)) as Node3D
	woodpile.position = at.call(Vector3(CAMPFIRE.x - 2.8, 0, CAMPFIRE.y + 1.6))
	woodpile.rotation.y = .3
	add_child(woodpile)
	# The chopping block (part of the woodpile: pointing at either is the woodpile), the axe in it, and a couple
	# of split logs lying by
	block = Build.group(woodpile)
	Build.mesh(Build.cyl(.27, .3, .42, 10), Build.mat("#9C6B4E", {ao = .3, ao_h = .4}), 0, .21, 0, block)
	Build.mesh(Build.cyl(.25, .25, .02, 10), Build.mat("#E8C9A0"), 0, .425, 0, block)
	var bw := woodpile.position + Vector3(1.5, 0, 1.0)
	block.position = woodpile.to_local(Vector3(bw.x, ground(bw.x, bw.z), bw.z))
	_axe_in_block()
	# Bo's model boat, on a trestle by the house
	boat = Build.group(null, "boat")
	var trestle: ShaderMaterial = Build.mat("#8A6A4A")
	Build.mesh(Build.box(.9, .45, .3), trestle, 0, .22, 0, boat)
	var bp := Build.nohit(Build.group(boat)) as Node3D
	var wood_m: ShaderMaterial = Build.mat("#B98A5A")
	_boat_parts = [Build.mesh(Build.box(1.1, .08, .1), wood_m, 0, .5, 0, bp),
		Build.mesh(Build.box(1.0, .22, .34), wood_m, 0, .6, 0, bp),
		Build.mesh(Build.cyl(.025, .025, .8, 6), Build.mat("#6E4B2E"), 0, 1.1, 0, bp),
		Build.mesh(Build.box(.04, .5, .4), Build.mat("#F2EDE2"), .02, 1.15, .02, bp),
		Build.mesh(Build.box(1.02, .06, .36), Build.mat("#3E7FCB"), 0, .62, 0, bp)]
	boat.position = at.call(house.to_global(Vector3(1.75, 0, homes.house.d / 2 + 1.5)))
	boat.rotation.y = house.rotation.y
	add_child(boat)
	# Mo's shell jar, on the step by the door
	jar = Build.group(null, "jar")
	Build.noshadow(Build.mesh(Build.cyl(.16, .16, .36, 14), Build.smooth("#DDEFF2", {opacity = .45, roughness = .2}), 0, .18, 0, jar))
	_jar_shells = Build.nohit(Build.group(jar)) as Node3D
	jar.position = at.call(house.to_global(Vector3(float(Houses.SPECS.house.door_x) + 1.0, 0, homes.house.d / 2 + .3)))
	add_child(jar)
	things.append_array([{t = "woodpile", node = woodpile}, {t = "boat", node = boat}, {t = "jar", node = jar}])
	labels.merge({woodpile = "the woodpile", boat = "Bo's model boat", jar = "Mo's shell jar"})
	names.merge({woodpile = "woodpile", boat = "boat", jar = "jar"})
	obstacles.append_array([[woodpile.position.x, woodpile.position.z, .9], [block.global_position.x, block.global_position.z, .3, 1], [boat.position.x, boat.position.z, .55, 1], [jar.position.x, jar.position.z, .25, 1]])
	_set_logs(LOOSE_LOGS)
	_set_shells(SHELLS.size())
	_show_wood()
	_show_boat()
	_show_jar()


## The axe, stuck in the chopping block (where it's kept: put back each morning if it was left lying about).
func _axe_in_block() -> void:
	if game.people().any(func(p): return p.held and p.held.t == "axe"):
		return
	var A := thing("axe")
	if not A.is_empty():
		# Left lying about: back in the block
		A.node.reparent(self, false)
		A.node.position = block.global_position + Vector3(.05, .38, 0)
		A.node.rotation = Vector3(0, .8, -.35)
		if A.has("box"):
			A.box = Level.box_of(A.node)
		return
	var g := Build.group(null, "axe")
	var handle := Build.mesh(Build.cyl(.022, .028, .75, 6), Build.mat("#B98A5A"), 0, .33, 0, g)
	Build.mesh(Build.box(.05, .1, .2), Build.mat("#8C8F99", {roughness = .35, metal = .4}), 0, .34, .08, handle)
	g.position = block.global_position + Vector3(.05, .38, 0)
	g.rotation = Vector3(0, .8, -.35)
	add_child(g)
	var T := {t = "axe", node = g, carry = true, hold_y = -.25, rest_y = .05}
	things.append(T)
	labels.axe = "the axe"
	names.axe = "axe"
	said.axe = "an axe, in the chopping block"
	if is_inside_tree() and things[0].has("box"):
		T.box = Level.box_of(g)
		grab_volume(T)


## Split logs by the block: as many as there should be (some may be carried off).
func _set_logs(n: int) -> void:
	var have := things.filter(func(T): return String(T.t).begins_with("log_")).size()
	for i in 6:
		if have >= n:
			return
		var t := "log_%d" % i
		if not thing(t).is_empty() or game.people().any(func(p): return p.held and p.held.t == t):
			continue
		var g := Build.group(null, t)
		var l := Build.mesh(Build.cyl(.1, .11, .5, 7), Build.mat("#8A5A3F"), 0, .1, 0, g)
		l.rotation.z = PI / 2
		Build.mesh(Build.cyl(.09, .09, .01, 7), Build.mat("#E8C9A0"), 0, .255, 0, l)
		var q: Vector3
		if i in [2, 3]:
			# Two by the fire pit, ready for tonight
			var a := -.4 + (i - 2) * .5
			q = campfire.position + Vector3(cos(a), 0, sin(a)) * 1.25
		else:
			var bp := block.global_position
			q = bp + Vector3(-.2 + (i % 2) * .35, 0, -.55 - (i % 2) * .2 - (.4 if i > 3 else 0.0))
		g.position = Vector3(q.x, ground(q.x, q.z), q.z)
		g.rotation.y = i * .7
		add_child(g)
		var T := {t = t, node = g, carry = true, hold_y = -.15}
		things.append(T)
		labels[t] = "a log"
		names[t] = "log"
		said[t] = "a split log"
		if is_inside_tree() and things[0].has("box"):
			T.box = Level.box_of(g)
			grab_volume(T)
		have += 1


## Holding a split log?
static func _log_in(p: Pal) -> bool:
	return p.held != null and not p.held.is_empty() and String(p.held.t).begins_with("log_")


# ---------- The island's other people ----------

## Each one's home: Folk.id -> the hut
var huts := {}
## What they've lost (until it's found): Nell's float, Tam's smoker; and what's been found (kept, and saved)
var lost := {}
var found: Array = []


## Their homes (a hut each, like ours but smaller), and what Nell and Tam have lost, where it is.
func _folk_things() -> void:
	for w in Folk.IDS:
		var H: Dictionary = Folk.HOME[w]
		var hut := _home(w, H.at, H.yaw, "hut_" + w)
		huts[w] = hut
		things.append({t = "hut_" + w, node = hut})
		labels["hut_" + w] = H.what
		names["hut_" + w] = "hut"
		said["hut_" + w] = H.what
	# Tam's hives, by her cottage; Odo's wheel, by his
	for i in 3:
		var hv := Build.group(self)
		Build.mesh(Build.box(.5, .55, .45), Build.mat(["#F2D27A", "#E8C060", "#F5DC92"][i]), 0, .28, 0, hv)
		Build.mesh(Build.box(.58, .06, .52), Build.mat("#8A6A4A"), 0, .58, 0, hv)
		var q: Vector2 = Folk.SPOTS.tam.chore + Vector2(i * .9 - .9, 1.2)
		hv.position = Vector3(q.x, ground(q.x, q.y), q.y)
	var wheel := Build.group(self)
	Build.mesh(Build.cyl(.3, .3, .08, 14), Build.mat("#8A6A4A"), 0, .55, 0, wheel)
	Build.mesh(Build.cyl(.12, .16, .5, 8), Build.mat("#6E5A4A"), 0, .25, 0, wheel)
	Build.mesh(Build.cyl(.12, .1, .2, 10), Build.mat("#B5704C"), 0, .69, 0, wheel)
	var wq: Vector2 = Folk.SPOTS.odo.hobby + Vector2(.6, .6)
	wheel.position = Vector3(wq.x, ground(wq.x, wq.y), wq.y)
	# Nell's float, washed up along the north-east shore; Tam's smoker, put down by the pond
	# (a few metres along the sand from where "the north-east shore" brings you: there to be found by looking)
	var ne := atan2(BA.z, BA.x) + .1
	var r := shore_radius(ne) * .9
	_lost("float", Vector3(cos(ne) * r, 0, sin(ne) * r), func(g):
		Build.noshadow(Build.mesh(Build.sphere(.2, 14, 10), Build.smooth("#5FB38A", {opacity = .85, roughness = .15}), 0, .2, 0, g))
		Build.mesh(Build.torus(.2, .018, 6, 16), Build.mat("#C9B48A"), 0, .2, 0, g).rotation.x = PI / 2, "a green glass float")
	_lost("smoker", Vector3(POND.x - 4.6, 0, POND.z - 4.4), func(g):
		Build.mesh(Build.cyl(.1, .1, .26, 10), Build.mat("#9A9AA2"), 0, .13, 0, g)
		Build.mesh(Build.cone(.1, .12, 10), Build.mat("#7E7E86"), 0, .32, 0, g)
		Build.mesh(Build.box(.06, .14, .14), Build.mat("#7A5236"), -.13, .14, 0, g), "a bee smoker")


func _lost(t: String, at: Vector3, make: Callable, label: String) -> void:
	var g := Build.group(null, t)
	make.call(g)
	g.position = Vector3(at.x, ground(at.x, at.z), at.z)
	add_child(g)
	var T := {t = t, node = g, carry = true, hold_y = -.15}
	things.append(T)
	lost[t] = T
	labels[t] = label
	names[t] = t
	if is_inside_tree() and things[0].has("box"):
		T.box = Level.box_of(g)
		grab_volume(T)


func use_reach_life(t: String) -> float:
	return {woodpile = 1.3, boat = 1.0, jar = .7, well = 1.2}.get(t, -1.0)


func _show_wood() -> void:
	if _logs == null:
		return
	for c in _logs.get_children():
		c.queue_free()
	var m: ShaderMaterial = Build.mat("#8A5A3F")
	var grain: ShaderMaterial = Build.mat("#E8C9A0")
	for i in wood:
		var row := i / 4
		var l := Build.mesh(Build.cyl(.11, .12, .66, 7), m, -.5 + (i % 4) * .3 + (row % 2) * .12, .2 + row * .2, 0, _logs)
		l.rotation.x = PI / 2
		# The cut ends, pale, so it reads as a woodpile from anywhere
		for e in [-1.0, 1.0]:
			Build.mesh(Build.cyl(.1, .1, .01, 7), grain, 0, e * .333, 0, l)
	# The whole stack as two meshes (wood and cut ends), not three a log
	for l in _logs.get_children():
		if not l.is_queued_for_deletion():
			for c in l.get_children():
				c.reparent(_logs)
	Build.merge_static(_logs)
	_logs.set_meta("logs", wood)


func _show_boat() -> void:
	for i in _boat_parts.size():
		_boat_parts[i].visible = boat_k >= [0.0, .25, .5, .75, 1.0][i]


func _show_jar() -> void:
	if _jar_shells == null:
		return
	for c in _jar_shells.get_children():
		c.queue_free()
	var cols := ["#F7D9C4", "#F2B8A8", "#FFF1DE", "#E9C9F0"]
	for i in mini(jar_n, 16):
		var a := i * 2.4
		Build.mesh(Build.sphere(.035, 6, 4), Build.mat(cols[i % 4]), cos(a) * .08, .04 + i * .018, sin(a) * .08, _jar_shells)


func jar_words() -> String:
	if jar_n == 0:
		return "it's empty"
	if jar_n < 4:
		return "only a few shells in it"
	if jar_n < 10:
		return "quite a few shells in it now"
	if jar_n < 16:
		return "lots of shells in it"
	return "so many shells it's nearly full"


## Shells on the beach: as many as there should be.
func _set_shells(n: int) -> void:
	for i in SHELLS.size():
		var t := "shell_%d" % i
		var T := thing(t)
		var held := game.people().any(func(p): return p.held and p.held.t == t)
		if i < n and T.is_empty() and not held:
			var g := Build.group(null, t)
			Build.mesh(Build.cone(.09, .14, 8), Build.smooth(["#F7D9C4", "#F2B8A8", "#FFF1DE"][i], {roughness = .5}), 0, .05, 0, g).rotation.z = PI / 2
			g.position = Vector3(SHELLS[i].x, ground(SHELLS[i].x, SHELLS[i].y) + .03, SHELLS[i].y)
			add_child(g)
			var S := {t = t, node = g, carry = true, hold_y = -.1}
			things.append(S)
			labels[t] = "a shell"
			names[t] = "shell"
			if is_inside_tree() and not things.is_empty() and things[0].has("box"):
				S.box = Level.box_of(g)
				grab_volume(S)
		elif i >= n and not T.is_empty():
			things.erase(T)
			T.node.queue_free()


## The apples under the tree: as many as there should be.
func _set_apples(n: int) -> void:
	for i in APPLES.size():
		var t := "apple_%d" % i
		var T := thing(t)
		var held := game.people().any(func(p): return p.held and p.held.t == t)
		if i < n and T.is_empty() and not held:
			var A := _apple(i)
			A.box = Level.box_of(A.node)
			grab_volume(A)
		elif i >= n and not T.is_empty():
			things.erase(T)
			T.node.queue_free()


## The island's own counters (Life.fresh_world() has the same keys), and setting them (on coming back).
func life_state() -> Dictionary:
	return {wood = wood, boat = boat_k, jar = jar_n, larder = larder, found = found,
		apples = things.filter(func(T): return String(T.t).begins_with("apple")).size(),
		beach_shells = things.filter(func(T): return String(T.t).begins_with("shell")).size()}


func set_life_state(d: Dictionary) -> void:
	wood = int(d.get("wood", wood))
	boat_k = float(d.get("boat", boat_k))
	jar_n = int(d.get("jar", jar_n))
	# What's been found and given back stays gone from where it was lost
	found = d.get("found", found)
	for t in found:
		if lost.has(t) and not thing(t).is_empty():
			things.erase(lost[t])
			lost[t].node.queue_free()
	larder = int(d.get("larder", larder))
	_set_apples(int(d.get("apples", APPLES.size())))
	_set_shells(int(d.get("beach_shells", SHELLS.size())))
	# If it's evening now, the fire's already been lit (the time away took the log)
	var h: float = game.clock.hour()
	if h >= FIRE_FROM or h < FIRE_TO:
		var evening: int = game.clock.day() - (1 if h < FIRE_TO else 0)
		fire_tried = evening
		fire_evening = evening if d.get("fire", true) else -1
	_show_wood()
	_show_boat()
	_show_jar()


## Where each of them is at a time of their day.
func life_spot(who: String, doing: String) -> Vector3:
	if Folk.has(who):
		var f: Vector3
		match doing:
			"chore", "hobby", "own":
				var q: Vector2 = Folk.SPOTS[who][doing]
				f = Vector3(q.x, 0, q.y)
			"campfire":
				var a: float = Folk.FIRE_SEAT[who]
				f = campfire.position + Vector3(cos(a), 0, sin(a)) * 2.4
			_:
				f = shelter("hut_" + who).door
		return Vector3(f.x, ground(f.x, f.z), f.z)
	var spots := {
		mo = {chore = Vector3(BIG_TREE.x - 1.5, 0, BIG_TREE.y + 2.0), hobby = Vector3(0.5, 0, 52.0), own = Vector3(-1.0, 0, 4.0)},
		bo = {chore = woodpile.position + Vector3(1.2, 0, .6), hobby = boat.position + (boat.position - house.position).normalized() * .9, own = Vector3(6.0, 0, 6.0)},
	}
	var s: Dictionary = spots[who]
	var at: Vector3
	match doing:
		"chore", "hobby", "own":
			at = s[doing]
		"campfire":
			at = campfire.position + Vector3(-1.8 if who == "mo" else 1.8, 0, 1.2)
		_:
			at = homes.house.node.to_global(Vector3(float(Houses.SPECS.house.door_x) + (.6 if who == "mo" else -.6), 0, homes.house.d / 2 + 1.2))
	return Vector3(at.x, ground(at.x, at.z), at.z)


## The HUD's boxes (what the chosen one sees) only for what some light reaches.
func lit(_t: String, c: Vector3) -> bool:
	return light_at(c) > .1


# ---------- Weather: what makes the island feel alive ----------

func _atmosphere() -> void:
	# Pollen drifting in the sun; fireflies come out at dusk
	# They drift round wherever you are
	pollen = Build.motes(int(70 * game.quality.fx), Vector3(12, 2.5, 12), "#FFF4C4", .09, 9.0)
	add_child(pollen)
	fireflies = Build.motes(int(50 * game.quality.fx), Vector3(12, 1.5, 12), "#E4FF8C", .24, 5.0)
	fireflies.emitting = false
	add_child(fireflies)
	# Cloud shadows sliding over the lawn
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(.5, .5)
	soft.fill_to = Vector2(1, .5)
	soft.width = 128
	soft.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, .34))
	g.set_color(1, Color(0, 0, 0, 0))
	soft.gradient = g
	for i in 3:
		var d := Decal.new()
		d.texture_albedo = soft
		d.size = Vector3(44, 40, 34)
		d.position = Vector3(-80 + i * 60, 6, -30 + i * 28)
		d.cull_mask = 1
		add_child(d)
		cloud_shadows.append(d)


func _weather(dt: float, _t: float) -> void:
	for d in cloud_shadows:
		d.position.x += dt * 2.2
		if d.position.x > 90:
			d.position.x = -90
		d.modulate.a = lerp(1.0, .25, dusk_t) * (1.0 - night_t)
	var w := game.wisp.global_position
	pollen.position = Vector3(w.x, w.y + 1.0, w.z)
	fireflies.position = Vector3(w.x, w.y + .3, w.z)
	pollen.emitting = game.clock.daylight() > .6
	fireflies.emitting = dusk_t > .5 or night_t > .3
