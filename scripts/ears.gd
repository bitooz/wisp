class_name Ears
extends Node
## The phone's microphone, always listening (unless muted): a voice detector picks out each thing you say and
## hands it over as a 16 kHz mono WAV.
##
## The game's own voices come out of the same phone, and Godot's Android mic has no echo cancelling (it uses
## the device's default recording preset), so while Mo or Bo is talking, and a moment after, the mic is
## ignored (deaf() says when). The detector's threshold follows the room's noise, so steady sound (wind, the
## sea, the hum of the dungeon) isn't taken for talk. Desktop builds leave the input off (the project setting
## audio/driver/enable_input is on for Android only); tests feed WAVs through feed() instead.

signal heard(wav: PackedByteArray, t_end: int)
signal speaking(on: bool)

const RATE := 16000
## The detector works in 20 ms windows
const WIN := 320
## Speech starts when most of the last 300 ms is louder than the noise by this much
const START_K := 3.0
const STOP_K := 2.0
## The quietest that counts as a voice (RMS), whatever the noise
const MIN_RMS := .004
const START_WINS := 15
const START_NEED := 11
## This long quiet ends what you're saying
const STOP_WINS := 35
const MAX_S := 12.0
## How long after their voices stop before listening again (the room, and the phone's own delay)
const TAIL := .7

var player: AudioStreamPlayer
var cap: AudioEffectCapture
var bus := -1
var muted := false
## True while their voices play: set by minds.gd
var deaf: Callable = func(): return false
var on := false
var live := false

var step := 1.0
var pos := 0.0
var win := PackedFloat32Array()
var pre: Array = []
var utt := PackedFloat32Array()
var in_speech := false
var loud_hist: Array = []
var quiet_n := 0
var voiced_n := 0
var floor_rms := .003
var deaf_until := 0.0
var level := 0.0
## Fed by tests in place of the mic: 16 kHz samples, taken at the pace of real time
var test_queue := PackedFloat32Array()
var test_pos := 0.0
var stats := {utterances = 0, gated_s = 0.0, false_starts = 0}


func _ready() -> void:
	AudioServer.add_bus()
	bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "Mic")
	cap = AudioEffectCapture.new()
	cap.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, cap)
	# Heard by the capture, not by you: the bus's volume comes after its effects
	AudioServer.set_bus_volume_db(bus, -80.0)
	player = AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = "Mic"
	add_child(player)
	step = AudioServer.get_mix_rate() / RATE
	if OS.get_name() == "Android":
		get_tree().on_request_permissions_result.connect(func(_p, _g): _try_start())
	_try_start()


func can_hear() -> bool:
	return ProjectSettings.get_setting_with_override("audio/driver/enable_input")


## Start the mic if it's allowed (Android asks once).
func _try_start() -> void:
	if on or not can_hear():
		return
	if OS.get_name() == "Android" and not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		OS.request_permission("android.permission.RECORD_AUDIO")
		return
	cap.clear_buffer()
	player.play()
	on = true
	print("WISP_EARS mic on (%d Hz in)" % AudioServer.get_mix_rate())


## Something to hear as if through the mic (tests): a 16-bit mono WAV at 16 kHz.
func feed(wav_bytes: PackedByteArray) -> void:
	var data := wav_bytes.slice(44)
	var n := data.size() / 2
	var at := test_queue.size()
	test_queue.resize(at + n)
	for i in n:
		test_queue[at + i] = data.decode_s16(i * 2) / 32768.0


## What the speaker plays, leaking back in (tests of the echo): a little quieter, at 16 kHz.
func leak(frames: PackedVector2Array, rate: int) -> void:
	var k := float(rate) / RATE
	var at := test_queue.size()
	var n := int(frames.size() / k)
	test_queue.resize(at + n)
	for i in n:
		test_queue[at + i] = frames[int(i * k)].x * .6


func feed_silence(sec: float) -> void:
	var at := test_queue.size()
	test_queue.resize(at + int(sec * RATE))
	for i in range(at, test_queue.size()):
		test_queue[i] = randf_range(-.0015, .0015)


func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if deaf.call():
		deaf_until = now + TAIL
	var gated := muted or now < deaf_until
	if on:
		var k := cap.get_frames_available()
		if k > 0:
			# Every step-th frame (44.1 kHz down to 16 kHz): speech has little above 8 kHz, and the phone
			# can't spare a loop over every frame
			var buf := cap.get_buffer(k)
			var i := pos
			while i < k:
				var f: Vector2 = buf[int(i)]
				_sample((f.x + f.y) * .5, gated)
				i += step
			pos = i - k
	if not on and test_queue.size() == 0:
		# No mic (a desktop test): the room is quiet, so what was being heard ends as it should
		feed_silence(dt)
	if test_queue.size() > 0:
		test_pos += dt * RATE
		var n := mini(int(test_pos), test_queue.size())
		test_pos -= n
		for i in n:
			_sample(test_queue[i], gated)
		test_queue = test_queue.slice(n)
	if gated:
		stats.gated_s += dt


func _sample(v: float, gated: bool) -> void:
	win.append(v)
	if win.size() < WIN:
		return
	var w := win
	win = PackedFloat32Array()
	if gated:
		# Their voices are playing: none of it is you. Anything half-heard is dropped.
		if in_speech:
			in_speech = false
			utt = PackedFloat32Array()
			speaking.emit(false)
		pre.clear()
		loud_hist.clear()
		return
	var e := 0.0
	for x in w:
		e += x * x
	var rms := sqrt(e / WIN)
	level = lerpf(level, rms, .3)
	var loud := rms > maxf(floor_rms * START_K, MIN_RMS)
	if not in_speech:
		# The room's noise: follows quiet quickly, loud slowly
		floor_rms = lerpf(floor_rms, rms, .25 if rms < floor_rms else .015)
		pre.append(w)
		if pre.size() > START_WINS:
			pre.pop_front()
		loud_hist.append(loud)
		if loud_hist.size() > START_WINS:
			loud_hist.pop_front()
		if loud_hist.count(true) >= START_NEED:
			in_speech = true
			utt = PackedFloat32Array()
			for p in pre:
				utt.append_array(p)
			quiet_n = 0
			voiced_n = loud_hist.count(true)
			speaking.emit(true)
		return
	utt.append_array(w)
	if rms > maxf(floor_rms * STOP_K, MIN_RMS * .7):
		quiet_n = 0
		voiced_n += 1
	else:
		quiet_n += 1
	if quiet_n >= STOP_WINS or utt.size() >= RATE * MAX_S:
		_finish()


func _finish() -> void:
	in_speech = false
	speaking.emit(false)
	pre.clear()
	loud_hist.clear()
	# Keep a quarter second of the quiet at the end
	var keep := utt.size() - maxi(0, quiet_n - 12) * WIN
	var samples := utt.slice(0, keep)
	utt = PackedFloat32Array()
	if voiced_n < 20 or samples.size() < RATE * .5:
		stats.false_starts += 1
		return
	if samples.size() >= RATE * MAX_S - WIN:
		# Twelve seconds without a pause is a sound in the room, not someone talking: it's the noise now
		var e := 0.0
		for x in samples:
			e += x * x
		floor_rms = maxf(floor_rms, sqrt(e / samples.size()) * .9)
		stats.false_starts += 1
		return
	var peak := 0.0
	for x in samples:
		peak = maxf(peak, absf(x))
	var gain := clampf(.8 / maxf(peak, 1e-4), 1.0, 12.0)
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, clampi(int(samples[i] * gain * 32767.0), -32768, 32767))
	stats.utterances += 1
	heard.emit(wav(pcm, RATE), Time.get_ticks_msec())


## Hearing you right now (they wait for you to finish before talking).
func listening() -> bool:
	return in_speech


static func wav(data: PackedByteArray, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952) # RIFF
	h.encode_u32(4, 36 + data.size())
	h.encode_u32(8, 0x45564157) # WAVE
	h.encode_u32(12, 0x20746d66) # fmt
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164) # data
	h.encode_u32(40, data.size())
	h.append_array(data)
	return h
