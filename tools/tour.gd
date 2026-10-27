extends Node
## A walk round the island (and under the hill) for pictures and frame rates, with the minds off:
##   godot --path . -- --autoplay --autoplay-script=res://tools/tour.gd --offline --shots=<dir> [--only=a,b] [--hold=4]
##   [--no-vsync: uncapped, to see the headroom]
## At each stop: the light stands there at that hour, the camera looks the given way, the view settles, a
## screenshot is saved (from the game's own viewport) and the frame rate over --hold seconds is printed as
## "TOUR <stop> fps=<n> min=<n>". Exits when done.

var game: Game
var args: Array = []
var shots := ""
var hold := 4.0
var only := []

## [name, place, x, z, hour, camera az (radians round the light), camera pol (from straight up)]
const STOPS := [
	["village_morning", "isle", 0.0, 22.0, 9.5, 0.4, 1.12],
	["village_from_south", "isle", 2.0, 34.0, 11.0, 0.0, 1.05],
	["home_front", "isle", -6.0, 18.0, 10.0, 0.7, 1.12],
	["odo_hut", "isle", -17.5, 18.5, 10.5, 2.4, 1.12],
	["tam_cottage", "isle", 15.0, 24.0, 15.0, -1.2, 1.12],
	["nell_hut", "isle", 6.5, 37.0, 14.0, -0.6, 1.12],
	["home_inside", "isle", -8.0, 13.0, 12.0, 0.55, 0.85],
	["odo_inside", "isle", -21.0, 15.0, 12.0, 1.2, 0.85],
	["village_dusk", "isle", 2.0, 24.0, 18.6, 0.3, 1.12],
	["village_night", "isle", 1.0, 23.0, 22.5, 0.6, 1.12],
	["home_inside_night", "isle", -8.0, 13.0, 22.5, 0.55, 0.85],
	["path_to_hill", "isle", 1.0, 0.0, 13.0, 0.0, 1.12],
	["hill_door", "isle", 0.0, -20.0, 13.0, 0.0, 1.12],
	["beach", "isle", 0.0, 48.0, 16.0, 3.1, 1.15],
	["cave_entry", "cave", 0.0, 2.5, 12.0, 0.0, 1.0],
	["cave_left", "cave", -4.0, 0.0, 12.0, 0.0, 1.0],
	["cave_plates", "cave", 0.0, -3.5, 12.0, 0.0, 1.0],
]


func _ready() -> void:
	for a in args:
		if a.begins_with("--shots="):
			shots = a.substr(8)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
		if a.begins_with("--hold="):
			hold = float(a.substr(7))
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		if a == "--no-vsync":
			# How fast it could go (the headroom), not capped at the screen's rate
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	game.clock.stopped = true
	var worst := 999
	for s in STOPS:
		if only.size() and not only.has(s[0]):
			continue
		if game.level.id != s[1]:
			# Mo and Bo come too
			for p in [game.mo, game.bo]:
				p.place_id = s[1]
			game.travel(s[1], {})
			await get_tree().create_timer(1.5).timeout
		game.controls = false
		game.clock.set_hour(s[4])
		var at := Vector3(s[2], 0, s[3])
		game.wisp_g = at
		game.heading = Vector3(-sin(s[5]), 0, -cos(s[5]))
		game.az = s[5]
		game.az_goal = s[5]
		game.pol = s[6]
		# Mo and Bo come along, a little aside
		for p in game.here():
			p.position = game.level.collide(at + Vector3(1.2 if p == game.mo else -1.2, 0, 1.0), .34, false)
		await get_tree().create_timer(1.5).timeout
		var frames := 0
		var slowest := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < hold * 1e6:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			slowest = maxf(slowest, (now - last) / 1e6)
			last = now
			frames += 1
		var fps := roundi(frames / hold)
		worst = mini(worst, fps)
		print("TOUR %s fps=%d min=%d" % [s[0], fps, roundi(1.0 / maxf(slowest, 1e-3))])
		if shots != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(shots).path_join(s[0] + ".png"))
	print("TOUR done worst=%d" % worst)
	get_tree().quit(0)
