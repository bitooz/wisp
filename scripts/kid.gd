class_name Kid
extends Node3D
## The player's own body: the kid with the lantern (art/player, made from refs3d/player-human.png like
## Mo and Bo, on the same skeleton and clips). Not in the game yet: the light (Wisp) is still "you".
## To use it: add one, move it (position and rotation.y, every frame: its legs keep up with however it
## moves, by gait.gd), and put the light's glow at `lantern`, which follows the lantern as it hangs and
## swings from the kid's hand. talk, look_at_point and gesture() as for the pals.

const MODEL := preload("res://art/player/player.glb")
const SKIN := preload("res://shaders/pal.gdshader")
const LIDS := ["lid.L", "lid.R"]
const ONCE := {jump = 1.0, pick_up = 2.2, wave = 1.0, point = 1.0}

var inner: Node3D
var skel: Skeleton3D
var skin: ShaderMaterial
var gait: Gait
var eye_anim: AnimationPlayer
var looker: Pal.LookAt
var hang: Hang
## Where the light goes: the lantern's flame
var lantern: Marker3D
## Talking (the talk clip while standing)
var talk := false
## Where to look (world), or null for straight ahead
var look_at_point = null
## How tall (m)
var height := 0.0
var _last := Vector3.INF
var _yaw := 0.0
var _blink := 2.0


func _ready() -> void:
	inner = Node3D.new()
	add_child(inner)
	var model: Node3D = MODEL.instantiate()
	inner.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	height = mesh.get_aabb().end.y
	skin = ShaderMaterial.new()
	skin.shader = SKIN
	var src_mat = mesh.mesh.surface_get_material(0)
	if src_mat is BaseMaterial3D:
		skin.set_shader_parameter("albedo_tex", src_mat.albedo_texture)
	skin.set_shader_parameter("glow", 1.0)
	mesh.material_override = skin
	var src: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	gait = Gait.new(model, src, ONCE, func(b): return not LIDS.has(b) and b != "lantern")
	eye_anim = AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var blink: Animation = src.get_animation("blink").duplicate()
	for i in range(blink.get_track_count() - 1, -1, -1):
		if not LIDS.has(str(blink.track_get_path(i)).get_slice(":", 1)):
			blink.remove_track(i)
	lib.add_animation("blink", blink)
	model.add_child(eye_anim)
	eye_anim.root_node = eye_anim.get_path_to(model)
	eye_anim.add_animation_library("", lib)
	eye_anim.play("blink")
	eye_anim.seek(0, true)
	eye_anim.pause()
	src.queue_free()
	looker = Pal.LookAt.new()
	looker.head = skel.find_bone("DEF-head")
	looker.neck = skel.find_bone("DEF-neck")
	skel.add_child(looker)
	hang = Hang.new()
	hang.bone = skel.find_bone("lantern")
	hang.flame_bone = skel.find_bone("flame")
	skel.add_child(hang)
	lantern = Marker3D.new()
	lantern.name = "Lantern"
	add_child(lantern)
	_yaw = global_rotation.y


## A gesture, once (jump, pick_up, wave or point).
func gesture(g: String) -> void:
	gait.play(g, ONCE[g])


func _process(dt: float) -> void:
	step(dt)


## A frame of it (_process calls it; call it yourself after set_process(false) to step it by hand).
func step(dt: float) -> void:
	if dt <= 0:
		return
	var p := global_position
	var v := 0.0
	if _last != Vector3.INF:
		v = Vector2(p.x - _last.x, p.z - _last.z).length() / dt
	_last = p
	var turn := wrapf(global_rotation.y - _yaw, -PI, PI) / dt
	_yaw = global_rotation.y
	if v > .3 and gait.playing() not in ["", "jump"]:
		gait.cancel()
	gait.update(dt, v, talk)
	inner.rotation = gait.tilt(dt, v, turn)
	hang.body_v = (global_basis.inverse() * (p - hang.last_world)) / dt if hang.last_world != Vector3.INF else Vector3.ZERO
	hang.last_world = p
	_blink -= dt
	if _blink < 0:
		eye_anim.play("blink")
		eye_anim.seek(0, true)
		_blink = 2.4 + randf() * 3
	looker.target = skel.to_local(look_at_point) if look_at_point != null else null
	if hang.bone >= 0:
		lantern.global_position = skel.to_global(hang.flame)


## Keeps the lantern hanging from the hand as the arm swings: a pendulum under the handle (its bone,
## "lantern"), pushed about by the handle's movement, settling back to straight down.
class Hang extends SkeletonModifier3D:
	var bone := -1
	## The flame's bone (a child of the lantern's) and where it is, in the skeleton's space
	var flame_bone := -1
	var flame := Vector3.ZERO
	## The body's velocity (its own space) and where it was, for the swing (set by Kid)
	var body_v := Vector3.ZERO
	var last_world := Vector3.INF
	var _swing := Vector2.ZERO
	var _spin := Vector2.ZERO
	var _hand := Vector3.INF
	var _hand_v := Vector3.ZERO

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or bone < 0 or delta <= 0:
			return
		var pose := sk.get_bone_global_pose(bone)
		var rest := sk.get_bone_global_rest(bone)
		var length := sk.get_bone_rest(flame_bone).origin.length() if flame_bone >= 0 else .15
		# How the handle speeds up (its own movement in the skeleton plus the body's): what pushes it
		var v := body_v
		if _hand != Vector3.INF:
			v += (pose.origin - _hand) / delta
		_hand = pose.origin
		var a := (v - _hand_v) / delta
		_hand_v = v
		# A damped pendulum, small angles (x: to the side, y: forward and back)
		_spin += (Vector2(-a.x, -a.z) / length - _swing * 9.8 / length - _spin * 3.0) * delta
		_swing = (_swing + _spin * delta).limit_length(.7)
		# Straight down in the world, as seen in the skeleton, tilted by the swing
		var down := (sk.global_basis.inverse() * Vector3.DOWN).normalized()
		down = (down + Vector3(_swing.x, 0, _swing.y)).normalized()
		var basis := Basis(Quaternion(rest.basis.y.normalized(), down)) * rest.basis
		sk.set_bone_global_pose(bone, Transform3D(basis, pose.origin))
		flame = pose.origin + down * length
