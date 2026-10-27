class_name Sfx
extends Node
## Sound: one-shots in the world (footsteps, hits) or on the screen (buttons), and an
## ambient bed that crossfades between places and times of day.
## Kenney's CC0 packs for footsteps, hits and clicks; our own synthesised loops for
## wind and sea, crickets at dusk, and the dungeon (assets/audio/wisp, see tools/synth_audio.py).

const KENNEY := "res://assets/audio/kenney/"
const OURS := "res://assets/audio/wisp/"

var world: Node3D
var _streams := {}
var _amb: Array[AudioStreamPlayer] = []
var _amb_now := ""
var _amb_vol := 0.0
## Until when a sound of the game's own is ringing out (not footsteps): the mic ignores it (ears.gd)
var loud_until := 0.0
## Everything here plays on its own bus, "World", which the sound button mutes; voices (voice.gd) don't use it,
## so they're always heard
const BUS := "World"
const SETTINGS := "user://settings.cfg"
var muted := false


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, BUS)
		AudioServer.set_bus_send(b, "Master")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		set_muted(bool(cfg.get_value("sound", "background_off", false)), false)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80
		p.bus = BUS
		add_child(p)
		_amb.append(p)


## The background (ambience and sound effects) off or on; remembered for next time.
func set_muted(on: bool, keep := true) -> void:
	muted = on
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS), on)
	if keep:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("sound", "background_off", on)
		cfg.save(SETTINGS)


func stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := (OURS + name + ".wav") if ResourceLoader.exists(OURS + name + ".wav") else (KENNEY + name + ".ogg")
		_streams[name] = load(path)
	return _streams[name]


## A sound somewhere in the world (heard from the camera), or on the screen if at is null.
func play(name: String, at = null, volume_db := 0.0, pitch := 1.0) -> void:
	var s := stream(name)
	if s and not name.begins_with("footstep") and not muted:
		loud_until = maxf(loud_until, Time.get_ticks_msec() / 1000.0 + s.get_length() / maxf(pitch, .1) + .3)
	if s == null:
		return
	if at is Vector3 and world:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.unit_size = 6.0
		p.max_distance = 45.0
		p.bus = BUS
		world.add_child(p)
		p.global_position = at
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.bus = BUS
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


## A sound that keeps going where it is (a fire): a looping player under parent, started and stopped by setting
## its `playing`. Heard only within reach metres.
func loop_at(name: String, parent: Node3D, volume_db := 0.0, reach := 16.0) -> AudioStreamPlayer3D:
	var s := stream(name)
	if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = 3.0
	p.max_distance = reach
	p.bus = BUS
	parent.add_child(p)
	return p


## One of a numbered set (footstep_grass_000..004), picked at random, a little detuned.
func play_any(prefix: String, count: int, at = null, volume_db := 0.0, pitch := 1.0) -> void:
	play("%s_%03d" % [prefix, randi() % count], at, volume_db, pitch * randf_range(.92, 1.08))


## The ambient bed: crossfades to a new loop over a couple of seconds.
func ambience(name: String, volume_db := -8.0) -> void:
	_amb_vol = volume_db
	if name == _amb_now:
		return
	_amb_now = name
	var p := _amb[0]
	_amb.reverse()
	var s := stream(name)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.volume_db = -60
	p.play()


func _process(dt: float) -> void:
	# The new loop rises, the old one falls
	var k: float = min(1.0, dt * 1.2)
	if _amb[1].playing:
		_amb[1].volume_db = lerp(_amb[1].volume_db, _amb_vol, k)
	if _amb[0].playing:
		_amb[0].volume_db = lerp(_amb[0].volume_db, -60.0, k)
		if _amb[0].volume_db < -55:
			_amb[0].stop()
