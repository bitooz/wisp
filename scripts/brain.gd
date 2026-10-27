class_name Brain
extends Node
## The line to Mo's and Bo's minds: the Worker in worker/ (the model and Fish Audio, keys kept there), or the
## mind server in mindserver/ on a Mac (the player's own Claude or Codex login), which speaks the same protocol.
## think() sends one of them what they perceive, remember and just heard, and streams back what they heard,
## say and do, with their voice in the same stream. Where it goes, and with what key: res://brain.json (the
## Worker; kept out of git), over which user://brain.json (this device's settings, set_server()) and then
## --brain=<url> --brain-key=<key> go. "minds" picks what each one thinks with on the mind server
## ({"mo": "claude", "bo": "codex"}; --minds=mo:claude,bo:codex); the Worker ignores it. Without an address,
## or offline, Mo and Bo keep to their written lines.

var host := ""
var port := 443
var tls := true
var key := ""
var on := false
## What each one thinks with, by who they are ("claude", "codex" or "worker"), sent with each call
var minds := {}
## Connections kept open between thoughts, so the next one skips the handshake
var idle: Array[HTTPClient] = []

const SETTINGS := "user://brain.json"


func _ready() -> void:
	var o := {}
	for path in ["res://brain.json", SETTINGS]:
		if FileAccess.file_exists(path):
			var x = JSON.parse_string(FileAccess.get_file_as_string(path))
			if x is Dictionary:
				o.merge(x, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--brain="):
			o.url = a.substr(8)
		elif a.begins_with("--brain-key="):
			o.key = a.substr(12)
		elif a.begins_with("--minds="):
			var m := {}
			for pair in a.substr(8).split(",", false):
				m[pair.get_slice(":", 0)] = pair.get_slice(":", 1)
			o.minds = m
	minds = o.get("minds", {}) if o.get("minds") is Dictionary else {}
	_point(String(o.get("url", "")), String(o.get("key", "")))


func _point(url: String, k: String) -> void:
	idle.clear()
	on = false
	if url == "" or k == "":
		return
	tls = not url.begins_with("http://")
	var rest := url.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	host = rest.get_slice(":", 0)
	port = int(rest.get_slice(":", 1)) if rest.contains(":") else (443 if tls else 80)
	key = k
	on = true


## Point this device at a mind server (or back at the Worker, with url ""), and keep it in user://brain.json.
func set_server(url: String, k: String, who_thinks_with := {}) -> void:
	var o := {url = url, key = k, minds = who_thinks_with}
	if url == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
		_ready()
		return
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	f.store_string(JSON.stringify(o))
	f.close()
	minds = who_thinks_with
	_point(url, k)


func _connect(h: HTTPClient) -> Error:
	return h.connect_to_host(host, port, TLSOptions.client() if tls else null)


## The body with what this one thinks with, if it's set.
func _with_mind(body: Dictionary) -> Dictionary:
	var who := String(body.get("who", ""))
	if minds.has(who) and not body.has("engine"):
		body = body.duplicate()
		body.engine = minds[who]
	return body


## One thought on its way: what was heard, the line, the voice, then the whole reply.
class Thought:
	extends RefCounted
	signal heard(text: String)
	signal said(text: String)
	## The whole reply (the action, the note to remember), while the voice may still be coming
	signal decided(r: Dictionary)
	## The stream is over (r.type is "error" if it failed)
	signal finished(r: Dictionary)
	## What was heard wasn't for them: noise or a filler ("ignored"), or said to the other one ("redirect")
	signal stopped(kind: String, heard: String)
	var body := {}
	var result := {}
	var over := false
	var cancelled := false
	## Where the voice goes (the speaker's Voice); null for none
	var voice: Voice = null
	var sent_at := 0
	var first_audio_ms := -1
	var say_ms := -1
	var audio_bytes := 0
	var events := 0
	## The voice that came before anyone was ready to hear it
	var pending := PackedByteArray()
	var audio_over := false
	var voice_line := -1

	## Send the voice to a speaker: what came already, then the rest as it comes.
	func attach(v: Voice) -> void:
		voice = v
		voice_line = v.line_id
		if pending.size():
			v.feed(pending)
			pending = PackedByteArray()
		if audio_over:
			v.finish()


## Send a thought on its way. Returns at once; listen on the Thought's signals.
func think(body: Dictionary, voice: Voice = null) -> Thought:
	var th := make()
	if voice:
		th.attach(voice)
	go(th, body)
	return th


## A night's reflection (minds.gd): what they remember of the day in, a few beliefs out ({beliefs: [{text,
## importance, from}], cost}), or {error}. Text only, not streamed.
func reflect(body: Dictionary) -> Dictionary:
	return await _post("/reflect", body)


## The morning's plan for the day (minds.gd): how they are today in, {day: [{text, why}], step, cost} out, or
## {error}. One small text-only call.
func plan(body: Dictionary) -> Dictionary:
	return await _post("/plan", body)


func _post(path: String, body: Dictionary) -> Dictionary:
	if not on:
		return {error = "offline"}
	var req := HTTPRequest.new()
	req.timeout = 40.0
	add_child(req)
	var base := "%s://%s:%d" % ["https" if tls else "http", host, port]
	var err := req.request(base + path, ["content-type: application/json", "x-wisp-key: " + key], HTTPClient.METHOD_POST, JSON.stringify(_with_mind(body)))
	if err != OK:
		req.queue_free()
		return {error = "request %d" % err}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return {error = "http %d/%d" % [res[0], res[1]]}
	var o = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return o if o is Dictionary else {error = "bad reply"}


## A thought to send later (when what goes with it is ready): connect to it, then go().
func make() -> Thought:
	return Thought.new()


func go(th: Thought, body: Dictionary) -> void:
	th.body = body
	th.sent_at = Time.get_ticks_msec()
	if th.cancelled or body.is_empty():
		_fail.call_deferred(th, "cancelled")
		return
	_run(th)


## Open a connection ahead of time (when the talk button goes down), so sending is quicker.
func warm() -> void:
	if not on or idle.size() > 0:
		return
	var h := HTTPClient.new()
	if _connect(h) == OK:
		idle.append(h)


func _client() -> HTTPClient:
	while idle.size() > 0:
		var h: HTTPClient = idle.pop_back()
		h.poll()
		var s := h.get_status()
		if s in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
			return h
		h.close()
	var n := HTTPClient.new()
	_connect(n)
	return n


func _fail(th: Thought, why: String) -> void:
	if th.over:
		return
	th.over = true
	th.result = {type = "error", error = why}
	if th.voice and th.voice.line_id == th.voice_line:
		th.voice.finish()
	th.finished.emit(th.result)


func _run(th: Thought) -> void:
	if not on:
		_fail.call_deferred(th, "offline")
		return
	var h := _client()
	var tree := get_tree()
	var t0 := Time.get_ticks_msec()
	while h.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		h.poll()
		await tree.process_frame
		if Time.get_ticks_msec() - t0 > 8000 or th.cancelled:
			h.close()
			_fail(th, "cancelled" if th.cancelled else "no connection")
			return
	if h.get_status() != HTTPClient.STATUS_CONNECTED:
		h.close()
		_fail(th, "no connection (%d)" % h.get_status())
		return
	var payload := JSON.stringify(_with_mind(th.body))
	var headers := ["content-type: application/json", "x-wisp-key: " + key]
	if h.request(HTTPClient.METHOD_POST, "/think", headers, payload) != OK:
		h.close()
		_fail(th, "request failed")
		return
	while h.get_status() == HTTPClient.STATUS_REQUESTING:
		h.poll()
		await tree.process_frame
	if not h.has_response():
		h.close()
		_fail(th, "no response (%d)" % h.get_status())
		return
	if h.get_response_code() != 200:
		var err := PackedByteArray()
		while h.get_status() == HTTPClient.STATUS_BODY:
			h.poll()
			err.append_array(h.read_response_body_chunk())
			await tree.process_frame
		h.close()
		_fail(th, "worker %d: %s" % [h.get_response_code(), err.get_string_from_utf8().left(200)])
		return
	var buf := PackedByteArray()
	while h.get_status() == HTTPClient.STATUS_BODY:
		h.poll()
		var chunk := h.read_response_body_chunk()
		if chunk.size() == 0:
			await tree.process_frame
			if th.cancelled:
				h.close()
				_fail(th, "cancelled")
				return
			continue
		buf.append_array(chunk)
		var nl := buf.find(10)
		while nl >= 0:
			_event(th, buf.slice(0, nl).get_string_from_utf8())
			buf = buf.slice(nl + 1)
			nl = buf.find(10)
	if buf.size() > 0:
		_event(th, buf.get_string_from_utf8())
	# A connection that read its whole answer can carry the next one
	if h.get_status() == HTTPClient.STATUS_CONNECTED and idle.size() < 2:
		idle.append(h)
	else:
		h.close()
	th.audio_over = true
	if th.voice and th.voice.line_id == th.voice_line:
		th.voice.finish()
	if not th.over:
		if th.result.is_empty():
			_fail(th, "the answer stopped short")
		else:
			th.over = true
			th.finished.emit(th.result)


func _event(th: Thought, line: String) -> void:
	if line.strip_edges() == "" or th.over:
		return
	var m = JSON.parse_string(line)
	if not (m is Dictionary):
		return
	th.events += 1
	match m.get("type", ""):
		"heard":
			th.heard.emit(String(m.heard))
		"say":
			th.say_ms = Time.get_ticks_msec() - th.sent_at
			th.said.emit(String(m.say))
		"audio":
			var pcm := Marshalls.base64_to_raw(m.pcm)
			th.audio_bytes += pcm.size()
			if th.first_audio_ms < 0:
				th.first_audio_ms = Time.get_ticks_msec() - th.sent_at
			if th.cancelled:
				pass
			elif th.voice:
				if th.voice.line_id == th.voice_line:
					th.voice.feed(pcm)
			else:
				th.pending.append_array(pcm)
		"done":
			th.result = m
			th.decided.emit(m)
		"audio_end":
			th.result["audio"] = m
			th.audio_over = true
			if th.voice and th.voice.line_id == th.voice_line:
				th.voice.finish()
		"ignored", "redirect":
			th.result = m
			th.stopped.emit(String(m.type), String(m.get("heard", "")))
		"error":
			_fail(th, String(m.get("error", "error")))


## A written line in one of their voices, streamed from the Worker into the speaker as it comes. Returns
## the whole line's PCM (to keep), or nothing if it failed or was cut off.
func speak(who: String, text: String, voice: Voice) -> PackedByteArray:
	var all := PackedByteArray()
	if not on:
		return all
	var mine := voice.line_id
	var h := _client()
	var tree := get_tree()
	var t0 := Time.get_ticks_msec()
	while h.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		h.poll()
		await tree.process_frame
		if Time.get_ticks_msec() - t0 > 8000:
			break
	if h.get_status() != HTTPClient.STATUS_CONNECTED or voice.line_id != mine:
		h.close()
		if voice.line_id == mine:
			voice.finish()
		return PackedByteArray()
	var q := "/speak?v=%s&t=%s" % [who, text.uri_encode()]
	if h.request(HTTPClient.METHOD_GET, q, ["x-wisp-key: " + key]) != OK:
		h.close()
		voice.finish()
		return PackedByteArray()
	while h.get_status() == HTTPClient.STATUS_REQUESTING:
		h.poll()
		await tree.process_frame
	var ok := h.has_response() and h.get_response_code() == 200
	var odd := PackedByteArray()
	while h.get_status() == HTTPClient.STATUS_BODY:
		h.poll()
		var chunk := h.read_response_body_chunk()
		if chunk.size() == 0:
			await tree.process_frame
			if voice.line_id != mine:
				# Cut off by another line
				h.close()
				return PackedByteArray()
			continue
		if not ok:
			continue
		odd.append_array(chunk)
		var even := odd.size() & ~1
		if even > 0:
			var piece := odd.slice(0, even)
			odd = odd.slice(even)
			all.append_array(piece)
			voice.feed(piece)
	if h.get_status() == HTTPClient.STATUS_CONNECTED and idle.size() < 2:
		idle.append(h)
	else:
		h.close()
	if voice.line_id == mine:
		voice.finish()
	return all if ok else PackedByteArray()
