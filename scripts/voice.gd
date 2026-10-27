class_name Voice
extends AudioStreamPlayer3D
## Mo's or Bo's voice: their lines arrive from the Worker as 16-bit mono PCM, a piece at a time, and play as
## they come. Written lines they've said before come from the recordings in assets/voice instead.

const RATE := 24000

var pb: AudioStreamGeneratorPlayback
var queue := PackedVector2Array()
var frames := 0
var ended := true
var started_at := -1.0
## How much the generator holds when empty, to tell how much of what was pushed has been heard
var cap := 0
## Which line is playing: a new one makes the old one's stream stop
var line_id := 0
## Tests: what's played also goes into the mic, as a phone's speaker would leak into it (ears.gd must not
## take it for you)
var echo: Ears = null
## What's been pushed this line, and how much of it has reached the speaker (for the echo)
var played_log := PackedVector2Array()
var leaked := 0


func _init() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 4.0
	stream = g
	unit_size = 7.0
	max_db = 4.0
	attenuation_model = ATTENUATION_INVERSE_DISTANCE
	panning_strength = .6


## A new line: anything still playing stops.
func begin() -> void:
	if stream is not AudioStreamGenerator:
		var g := AudioStreamGenerator.new()
		g.mix_rate = RATE
		g.buffer_length = 4.0
		stream = g
	stop()
	line_id += 1
	play()
	pb = get_stream_playback()
	cap = pb.get_frames_available()
	played_log = PackedVector2Array()
	leaked = 0
	queue.clear()
	frames = 0
	ended = false
	started_at = -1.0


## A recorded line, all at once.
func play_clip(clip: AudioStream) -> void:
	line_id += 1
	pb = null
	queue.clear()
	stream = clip
	play()
	frames = int(clip.get_length() * RATE)
	ended = true
	started_at = Time.get_ticks_msec() / 1000.0


func feed(pcm: PackedByteArray) -> void:
	var n := pcm.size() / 2
	var at := queue.size()
	queue.resize(at + n)
	for i in n:
		var v := pcm.decode_s16(i * 2) / 32768.0
		queue[at + i] = Vector2(v, v)
	_pump()


func finish() -> void:
	ended = true


func hush() -> void:
	line_id += 1
	queue.clear()
	ended = true
	frames = 0
	started_at = -1.0
	stop()


func _process(_dt: float) -> void:
	_pump()
	# The echo leaks what actually reaches the speaker, when it does
	if echo and pb and played_log.size() > 0:
		var played := clampi(frames - (cap - pb.get_frames_available()), 0, played_log.size())
		if played > leaked:
			echo.leak(played_log.slice(leaked, played), RATE)
			leaked = played


func _pump() -> void:
	if pb == null or queue.is_empty():
		return
	var n := mini(pb.get_frames_available(), queue.size())
	if n <= 0:
		return
	var out := queue.slice(0, n)
	pb.push_buffer(out)
	if echo:
		played_log.append_array(out)
	queue = queue.slice(n)
	frames += n
	if started_at < 0:
		started_at = Time.get_ticks_msec() / 1000.0


func sounding() -> bool:
	return started_at >= 0


## Seconds of the line heard so far (the generator's gaps, when the network fell behind, don't count).
func heard_s() -> float:
	if started_at < 0:
		return 0.0
	if pb == null:
		return Time.get_ticks_msec() / 1000.0 - started_at
	return float(frames - (cap - pb.get_frames_available())) / RATE


## The line's length so far.
func length_s() -> float:
	return float(frames) / RATE


func done() -> bool:
	if not ended or not queue.is_empty():
		return false
	if started_at < 0:
		return true
	if pb == null:
		return heard_s() >= length_s() + .05
	return pb.get_frames_available() >= cap - 64
