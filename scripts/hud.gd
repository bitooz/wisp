class_name Hud
extends Control
## The phone's heads-up display, drawn by hand to match the mock: Mo and Bo up top,
## the embers, what the chosen one sees in the corner, the speech bubble, the stick
## under the left thumb, and the phrases and talk button under the right.
## It also sorts every finger: the stick, a button, or a drag to look around.

signal chip(i: int)
signal mic
signal pal(id: String)
signal restart
## The sound button: background sound (not their voices) off or on
signal sound
signal tap(pos: Vector2)
signal look(d: Vector2)
signal steer(v: Vector2)
signal dash
signal interact

const PW := 176.0
const PH := 112.0
const BASE0 := Vector2(104, 292)
const INK := Color("#1B1B1F")
const PALS := [["mo", "Mo", "#FF7A52"], ["bo", "Bo", "#5AA9FF"]]

var f400: FontVariation
var f600: FontVariation
var f650: FontVariation
var f700: FontVariation

var ui: Control
var vig: ColorRect
var fade_rect: ColorRect
var sky: TextureRect
var pip_tex: TextureRect
var pip_over: Control

var cave := false
var dusk_goal := 0.0
var dusk := 0.0
## How much it's night (the island sets it from the clock)
var night := 0.0
var active_id := "mo"
var embers := 0
var ember_pop := [9.0, 9.0, 9.0]
var chips_list: Array = []
var chips_busy := false
var chip_sig := ""
var chip_t := 0.0
var chip_alpha := 1.0
var listening := false
## Mo and Bo can hear anything you say (their minds are on), so the talk button works even with no phrases
var talk_any := false
## The mic is always listening unless you mute it with this button
var mic_muted := false
var mic_busy := false
var mic_alpha := 1.0
var bubble_words := PackedStringArray()
var bubble_lit := 0
var bubble_on := false
var bubble_alpha := 0.0
var bubble_anchor := Vector2(-999, -999)
var bubble_lean := -1
var bubble_rect := Rect2()
## Background sound is off (the sound button shows it crossed out)
var sound_off := false
var you_text := ""
var you_on := false
var you_typing := false
var you_alpha := 0.0
var vig_on := false
var vig_a := 0.0
var fade_on := false
var fade_a := 0.0
var pip_name := "Mo"
var boxes := {}
var stick_hint := true
var stick_id := -1
var stick_base := BASE0
var stick_knob := Vector2.ZERO
var time := 0.0

var touches := {}
var buttons: Array = []
var pressed_btn := ""
var interact_label := ""
var dash_ready := 1.0
const STICK_R := 46.0
var pad_l := 30.0
var pad_r := 30.0


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var base: FontFile = load("res://fonts/Nunito.ttf")
	# Nunito runs lighter than SF Rounded, so each weight is nudged up to look the same
	f400 = _weight(base, 600)
	f600 = _weight(base, 760)
	f650 = _weight(base, 820)
	f700 = _weight(base, 880)

	var back := CanvasLayer.new()
	back.layer = -1
	add_child(back)
	# The backdrop and the world's picture, composited in one full-screen pass
	sky = TextureRect.new()
	sky.set_anchors_preset(PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.material = _shader_mat("res://shaders/backdrop.gdshader")
	sky.mouse_filter = MOUSE_FILTER_IGNORE
	back.add_child(sky)

	vig = ColorRect.new()
	vig.set_anchors_preset(PRESET_FULL_RECT)
	vig.material = _shader_mat("res://shaders/vignette.gdshader")
	vig.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vig)

	ui = Control.new()
	ui.set_anchors_preset(PRESET_FULL_RECT)
	ui.mouse_filter = MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	add_child(ui)

	# The corner view: one shader rounds it and puts a little sky behind; boxes on top
	pip_tex = TextureRect.new()
	pip_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pip_tex.stretch_mode = TextureRect.STRETCH_SCALE
	pip_tex.size = Vector2(PW, PH)
	pip_tex.mouse_filter = MOUSE_FILTER_IGNORE
	pip_tex.material = _shader_mat("res://shaders/pip_backdrop.gdshader")
	add_child(pip_tex)
	pip_over = Control.new()
	pip_over.size = Vector2(PW, PH)
	pip_over.mouse_filter = MOUSE_FILTER_IGNORE
	pip_over.draw.connect(_draw_pip)
	pip_tex.add_child(pip_over)

	fade_rect = ColorRect.new()
	fade_rect.set_anchors_preset(PRESET_FULL_RECT)
	fade_rect.color = Color("#050507", 0)
	fade_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(fade_rect)


func _weight(base: FontFile, w: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {"wght": w}
	return f


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


## The sky's colours as the corner view shows them (also behind what Mo and Bo see, game.look()).
func sky_top() -> Color:
	return Color("#09090E") if cave else Color("#A8D6FF").lerp(Color("#3A3570"), _ease(dusk)).lerp(Color("#050816"), night)


func sky_bottom() -> Color:
	return Color("#09090E") if cave else Color("#EAF5FF").lerp(Color("#C98A83"), _ease(dusk)).lerp(Color("#1A2142"), night)


# ---------- What the game tells the HUD ----------

func set_chips(list: Array, busy: bool) -> void:
	chips_busy = busy
	mic_busy = false
	if busy:
		return
	var sig := "|".join(list.map(func(c): return c.q))
	if sig == chip_sig:
		return
	chip_sig = sig
	chips_list = list
	chip_t = 0.0


func reset_chips() -> void:
	chip_sig = "~"


func show_bubble(words: PackedStringArray, lit: int) -> void:
	bubble_words = words
	bubble_lit = lit
	bubble_on = true


func pop_ember(n: int) -> void:
	embers = n
	if n > 0:
		ember_pop[n - 1] = 0.0


func set_box(key: String, label: String, on: bool, rect: Rect2, hot: bool) -> void:
	if not boxes.has(key):
		if not on:
			return
		boxes[key] = {a = 0.0}
	var b: Dictionary = boxes[key]
	b.label = label
	b.on = on
	b.hot = hot
	if on:
		b.rect = rect
		b.up = rect.end.y > PH - 18


func clear_boxes() -> void:
	boxes.clear()


# ---------- Every frame ----------

func _process(dt: float) -> void:
	time += dt
	chip_t += dt
	for i in 3:
		ember_pop[i] += dt
	var s := get_viewport_rect().size
	_insets(s)
	dusk = move_toward(dusk, dusk_goal, dt / 2.2)
	(sky.material as ShaderMaterial).set_shader_parameter("dusk", _ease(dusk))
	(sky.material as ShaderMaterial).set_shader_parameter("night", night)
	(sky.material as ShaderMaterial).set_shader_parameter("cave", 1.0 if cave else 0.0)
	bubble_alpha = move_toward(bubble_alpha, 1.0 if bubble_on else 0.0, dt / .2)
	you_alpha = move_toward(you_alpha, 1.0 if you_on else 0.0, dt / .25)
	chip_alpha = move_toward(chip_alpha, 0.0 if chips_busy else 1.0, dt / .2)
	mic_alpha = move_toward(mic_alpha, .35 if (mic_busy and not listening) else 1.0, dt / .25)
	vig_a = move_toward(vig_a, 1.0 if vig_on else 0.0, dt / 1.0)
	(vig.material as ShaderMaterial).set_shader_parameter("amount", vig_a)
	vig.visible = vig_a > 0
	fade_a = move_toward(fade_a, 1.0 if fade_on else 0.0, dt / .45)
	fade_rect.color.a = _ease(fade_a)
	fade_rect.visible = fade_a > 0
	for k in boxes.keys():
		var b: Dictionary = boxes[k]
		b.a = move_toward(b.a, 1.0 if b.on else 0.0, dt / .18)
		if not b.on and b.a <= 0:
			boxes.erase(k)
	pip_tex.position = Vector2(s.x - pad_r - PW, 18)
	var top := sky_top()
	var bottom := sky_bottom()
	(pip_tex.material as ShaderMaterial).set_shader_parameter("top", top)
	(pip_tex.material as ShaderMaterial).set_shader_parameter("bottom", bottom)
	ui.queue_redraw()
	pip_over.queue_redraw()


# Keep clear of a camera cut-out on either side.
func _insets(s: Vector2) -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0 or OS.get_name() != "Android":
		return
	var safe := DisplayServer.get_display_safe_area()
	var k := s.x / win.x
	pad_l = max(30.0, safe.position.x * k + 12)
	pad_r = max(30.0, (win.x - safe.end.x) * k + 12)


func _ease(k: float) -> float:
	return k * k * (3 - 2 * k)


func hud_bg() -> Color:
	return Color(30 / 255.0, 30 / 255.0, 38 / 255.0, .62) if cave else Color(1, 1, 1, .62)


func hud_on() -> Color:
	return Color(78 / 255.0, 78 / 255.0, 92 / 255.0, .92) if cave else Color.WHITE


func hud_ink() -> Color:
	return Color("#EEEEF3") if cave else INK


# ---------- Drawing ----------

func _box(bg: Color, r: float, shadow := Color(0, 0, 0, 0), shadow_size := 0, shadow_y := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(r))
	sb.anti_aliasing = true
	sb.corner_detail = 10
	if shadow.a > 0:
		sb.shadow_color = shadow
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2(0, shadow_y)
	return sb


func _text(c: CanvasItem, font: Font, size: int, pos: Vector2, h: float, text: String, col: Color) -> void:
	var y := pos.y + (h - font.get_height(size)) / 2 + font.get_ascent(size)
	c.draw_string(font, Vector2(pos.x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _tw(font: Font, size: int, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _draw_ui() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_ui_all()
	var g: Node = get_parent().get_parent()
	if "prof" in g:
		g.prof.hud += Time.get_ticks_usec() - t0


func _draw_ui_all() -> void:
	var s := get_viewport_rect().size
	buttons = []
	_draw_banner(s)
	_draw_stick(s)
	_draw_bubble(s)
	_draw_pals()
	_draw_embers(s)
	_draw_pip_frame(s)
	_draw_you(s)
	_draw_chips(s)
	_draw_mic(s)
	_draw_actions(s)


## A line across the top for a few seconds ("Two days later", on coming back).
var banner := ""
var banner_t := -1.0


func show_banner(text: String) -> void:
	banner = text
	banner_t = time


func _draw_banner(s: Vector2) -> void:
	var age := time - banner_t
	if banner == "" or banner_t < 0 or age > 5.0:
		return
	var a := clampf(minf(age / .4, (5.0 - age) / .8), 0.0, 1.0)
	var w := _tw(f650, 26, banner)
	_text(ui, f650, 26, Vector2((s.x - w) / 2.0, 86), 30, banner, Color(hud_ink(), a) if cave else Color(1, 1, 1, a))


func _draw_stick(_s: Vector2) -> void:
	var c := stick_base
	var ring := Color(1, 1, 1, .3 if cave else .55)
	ui.draw_circle(c, 52, Color(1, 1, 1, .06 if cave else .12), true, -1, true)
	ui.draw_arc(c, 51.25, 0, TAU, 64, ring, 1.5, true)
	var k := stick_knob
	if stick_hint and stick_id < 0:
		var ph := fmod(time, 1.8) / 1.8
		var e := ph / .45 if ph < .45 else 1 - (ph - .45) / .55
		k = Vector2(0, -16 * _ease(clamp(e, 0, 1)))
	var kc := c + k
	ui.draw_circle(kc + Vector2(0, 5), 19, Color(0, 0, 0, .1), true, -1, true)
	ui.draw_circle(kc + Vector2(0, 4), 21, Color(0, 0, 0, .08), true, -1, true)
	ui.draw_circle(kc, 22, Color(1, 1, 1, .55 if cave else .78), true, -1, true)


func _wrap(font: Font, size: int, words: PackedStringArray, max_w: float) -> Array:
	var lines := []
	var cur := []
	var w := 0.0
	var space := _tw(font, size, " ")
	for i in words.size():
		var ww := _tw(font, size, words[i])
		if cur.size() and w + space + ww > max_w:
			lines.append({ids = cur, w = w})
			cur = []
			w = 0.0
		w += (space if cur.size() else 0.0) + ww
		cur.append(i)
	if cur.size():
		lines.append({ids = cur, w = w})
	return lines


func _draw_bubble(s: Vector2) -> void:
	if bubble_alpha <= 0 or bubble_words.is_empty() or bubble_anchor.x < -500:
		return
	var a := bubble_alpha
	var lines := _wrap(f400, 15, bubble_words, 240 - 26)
	var tw := 0.0
	for l in lines:
		tw = max(tw, l.w)
	var bw := ceilf(tw) + 26
	var bh := lines.size() * 19.0 + 16
	var x := bubble_anchor.x
	var y := bubble_anchor.y
	var left: float = clamp(x - bw + 34 if bubble_lean < 0 else x - 34, 24, s.x - bw - 24)
	var top: float = clamp(y - bh - 6, 62, s.y - bh - 96)
	bubble_rect = Rect2(left, top, bw, bh)
	var tx: float = clamp(x - left, 18, bw - 18)
	ui.draw_style_box(_box(Color(1, 1, 1, a), 17, Color(0, 0, 0, .16 * a), 8, 8), bubble_rect)
	var tip := Vector2(left + tx, top + bh - 1)
	var d := 8.5
	ui.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -d), tip + Vector2(d, 0), tip + Vector2(0, d), tip + Vector2(-d, 0)]), Color(1, 1, 1, a))
	var space := _tw(f400, 15, " ")
	var ly := top + 8
	for l in lines:
		var lx := left + 13
		for i in l.ids:
			var col := INK if i < bubble_lit else Color(INK, .25)
			col.a *= a
			_text(ui, f400, 15, Vector2(lx, ly), 19, bubble_words[i], col)
			lx += _tw(f400, 15, bubble_words[i]) + space
		ly += 19


func _draw_pals() -> void:
	var x := pad_l
	for p in PALS:
		var on: bool = p[0] == active_id
		var w := 4 + 26 + 6 + _tw(f650, 14, p[1]) + 12
		var r := Rect2(x, 18, w, 34)
		var bg := hud_on() if on else hud_bg()
		ui.draw_style_box(_box(bg, 17, Color(0, 0, 0, .12) if on else Color(0, 0, 0, 0), 6, 4), r)
		var fc := Vector2(x + 4 + 13, 18 + 17)
		ui.draw_circle(fc, 13, Color(p[2]), true, -1, true)
		for ex in [-4.5, 4.5]:
			var e := fc + Vector2(ex, -.5)
			ui.draw_circle(e, 4, Color.WHITE, true, -1, true)
			ui.draw_circle(e + Vector2(.4, .96), 2.1, INK, true, -1, true)
		_text(ui, f650, 14, Vector2(x + 36, 18), 34, p[1], hud_ink())
		buttons.append({id = "pal:" + p[0], rect = r})
		x += w + 6
	# Start over
	var rc := Vector2(x + 17, 35)
	ui.draw_circle(rc, 17, hud_bg(), true, -1, true)
	var k := 16.0 / 24.0
	var o := rc - Vector2(8, 8)
	var col := Color(hud_ink(), .8)
	ui.draw_arc(o + Vector2(12, 12) * k, 8 * k, PI, -2.33, 24, col, 1.6, true)
	ui.draw_polyline(PackedVector2Array([o + Vector2(4, 4) * k, o + Vector2(4, 8.5) * k, o + Vector2(8.5, 8.5) * k]), col, 1.6, true)
	buttons.append({id = "reset", rect = Rect2(rc - Vector2(19, 19), Vector2(38, 38))})
	# Background sound off or on (their voices always stay): a speaker, with waves or a cross
	var sc := rc + Vector2(44, 0)
	ui.draw_circle(sc, 17, hud_bg(), true, -1, true)
	var sp := PackedVector2Array([sc + Vector2(-8, -3), sc + Vector2(-4, -3), sc + Vector2(1, -8), sc + Vector2(1, 8), sc + Vector2(-4, 3), sc + Vector2(-8, 3)])
	ui.draw_colored_polygon(sp, col)
	if sound_off:
		ui.draw_line(sc + Vector2(4, -4), sc + Vector2(10, 4), col, 1.8, true)
		ui.draw_line(sc + Vector2(10, -4), sc + Vector2(4, 4), col, 1.8, true)
	else:
		ui.draw_arc(sc + Vector2(1, 0), 5.0, -.9, .9, 10, col, 1.6, true)
		ui.draw_arc(sc + Vector2(1, 0), 9.0, -.85, .85, 12, col, 1.6, true)
	buttons.append({id = "sound", rect = Rect2(sc - Vector2(19, 19), Vector2(38, 38))})


func _draw_embers(s: Vector2) -> void:
	for i in 3:
		var c := Vector2(s.x / 2 - 38 + 6 + i * 32, 34)
		var sc := 1.0
		var t: float = ember_pop[i]
		if t < .7:
			var k := t / .7
			sc = lerp(.4, 1.6, _back(k / .6)) if k < .6 else lerp(1.6, 1.0, _ease((k - .6) / .4))
		var d := 6 * sqrt(2.0) * sc
		var pts := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
		if i < embers:
			for g in 4:
				ui.draw_circle(c, d + 2 + g * 3, Color(1, .65, .24, .14 - g * .03), true, -1, true)
			ui.draw_colored_polygon(pts, Color("#FFB547"))
		else:
			pts.append(pts[0])
			ui.draw_polyline(pts, Color(hud_ink(), .42), 1.5, true)


func _back(k: float) -> float:
	k = clamp(k, 0, 1)
	return 1 + 2.2 * pow(k - 1, 3) + 1.2 * pow(k - 1, 2)


func _draw_pip_frame(s: Vector2) -> void:
	var r := Rect2(s.x - pad_r - PW, 18, PW, PH)
	var ring := Color(1, 1, 1, .75) if cave else Color.WHITE
	ui.draw_style_box(_box(ring, 20, Color(0, 0, 0, .22), 10, 8), r.grow(2))


func _draw_you(s: Vector2) -> void:
	if you_alpha <= 0 or you_text == "":
		return
	var a := you_alpha
	var lines := _wrap(f400, 15, you_text.split(" ", false), 380 - 28)
	var tw := 0.0
	for l in lines:
		tw = max(tw, l.w)
	var caret := 4.0 if you_typing else 0.0
	var w := ceilf(tw) + 28 + caret
	var h := lines.size() * 19.0 + 16
	var right := s.x - pad_r - 78
	var r := Rect2(right - w, s.y - 88 - h + 4 * (1 - a), w, h)
	var sb := _box(Color(hud_bg(), hud_bg().a * a), 17)
	sb.corner_radius_bottom_right = 6
	ui.draw_style_box(sb, r)
	var words := you_text.split(" ", false)
	var space := _tw(f400, 15, " ")
	var ly := r.position.y + 8
	var lx := 0.0
	for l in lines:
		lx = r.position.x + 14
		for i in l.ids:
			_text(ui, f400, 15, Vector2(lx, ly), 19, words[i], Color(hud_ink(), a))
			lx += _tw(f400, 15, words[i]) + space
		ly += 19
	if you_typing and fmod(time, .8) < .4:
		ui.draw_rect(Rect2(lx - space + 2, ly - 19 + 2, 2, 15), Color(hud_ink(), a))


func _draw_chips(s: Vector2) -> void:
	var right := s.x - pad_r - 78
	var widths := []
	var total := 0.0
	for c in chips_list:
		var w := _tw(f600, 14, c.q) + 30
		widths.append(w)
		total += w
	total += max(0, chips_list.size() - 1) * 8
	var x := right - total
	for i in chips_list.size():
		var k: float = clamp((chip_t - i * .05) / .3, 0, 1)
		var e := 1 - pow(1 - k, 4)
		var a := e * chip_alpha
		var r := Rect2(x, s.y - 35 - 38 + 6 * (1 - e), widths[i], 38)
		var id := "chip:%d" % i
		if pressed_btn == id:
			r = r.grow(-r.size.y * .02)
		if a > 0:
			ui.draw_style_box(_box(Color(hud_bg(), hud_bg().a * a), 19), r)
			_text(ui, f600, 14, r.position + Vector2(15, 0), r.size.y, chips_list[i].q, Color(hud_ink(), a))
		if not chips_busy:
			buttons.append({id = id, rect = r})
		x += widths[i] + 8


func _draw_mic(s: Vector2) -> void:
	var c := Vector2(s.x - pad_r - 31, s.y - 24 - 31)
	var r := 31.0
	if pressed_btn == "mic":
		r *= .93
	var bg := Color("#F3F1EC") if cave else INK
	var ink := Color("#16161A") if cave else Color.WHITE
	if listening:
		bg = Color("#FF6B4A")
		var ph := fmod(time, 1.0)
		ui.draw_arc(c, (r + 8) * lerp(.9, 1.25, ph), 0, TAU, 64, Color("#FF6B4A", .8 * (1 - ph)), 2, true)
	var a := 1.0 if listening else mic_alpha
	if mic_muted:
		a = .55
	ui.draw_circle(c + Vector2(0, 6), r - 4, Color(0, 0, 0, .14 * a), true, -1, true)
	ui.draw_circle(c, r, Color(bg, a), true, -1, true)
	if listening:
		var delays := [0.0, .2, .35, .1, .28]
		for i in 5:
			var ph := fmod(time + delays[i], .92) / .46
			var k := ph if ph < 1 else 2 - ph
			var h: float = lerp(5.0, 20.0, _ease(k))
			ui.draw_rect(Rect2(c.x - 11.5 + i * 6.5 - 1.75, c.y - h / 2, 3.5, h), Color.WHITE)
	else:
		var o := c - Vector2(12, 12)
		var col := Color(ink, a)
		# The microphone: a capsule, a cradle and a stem
		ui.draw_arc(o + Vector2(12, 6), 3, PI, TAU, 12, col, 2, true)
		ui.draw_arc(o + Vector2(12, 11), 3, 0, PI, 12, col, 2, true)
		ui.draw_line(o + Vector2(9, 6), o + Vector2(9, 11), col, 2, true)
		ui.draw_line(o + Vector2(15, 6), o + Vector2(15, 11), col, 2, true)
		ui.draw_arc(o + Vector2(12, 11), 6.5, 0, PI, 20, col, 2, true)
		ui.draw_line(o + Vector2(12, 17.5), o + Vector2(12, 21), col, 2, true)
		if mic_muted:
			ui.draw_line(o + Vector2(3, 3), o + Vector2(21, 21), Color("#FF6B4A", a), 2.5, true)
	if not mic_busy or listening:
		buttons.append({id = "mic", rect = Rect2(c - Vector2(34, 34), Vector2(68, 68))})


## Dash (a burst of light) and interact (go in, boop): round buttons above the talk button.
func _draw_actions(s: Vector2) -> void:
	var ink := hud_ink()
	# Dash
	var c := Vector2(s.x - pad_r - 31, s.y - 24 - 62 - 40)
	var r := 26.0 * (.92 if pressed_btn == "dash" else 1.0)
	ui.draw_circle(c, r, hud_bg(), true, -1, true)
	var ready := dash_ready >= 1.0
	if not ready:
		ui.draw_arc(c, r - 2, -PI / 2, -PI / 2 + TAU * dash_ready, 32, Color("#FFD84D", .9), 3, true)
	var col := Color(ink, 1.0 if ready else .45)
	# A little bolt
	ui.draw_colored_polygon(PackedVector2Array([c + Vector2(2, -11), c + Vector2(-7, 2), c + Vector2(-1, 2), c + Vector2(-3, 11), c + Vector2(7, -3), c + Vector2(1, -3)]), col)
	buttons.append({id = "dash", rect = Rect2(c - Vector2(30, 30), Vector2(60, 60))})
	# Interact, when there's something at hand
	var ci := Vector2(c.x - 66, c.y)
	var on := interact_label != ""
	var ri := 26.0 * (.92 if pressed_btn == "interact" else 1.0)
	ui.draw_circle(ci, ri, hud_on() if on else Color(hud_bg(), hud_bg().a * .5), true, -1, true)
	var hcol := Color(ink, 1.0 if on else .3)
	# A hand: palm and fingers
	ui.draw_circle(ci + Vector2(0, 4), 7, hcol, true, -1, true)
	for k in 4:
		ui.draw_line(ci + Vector2(-5 + k * 3.4, 1), ci + Vector2(-5.5 + k * 3.6, -9 + absf(k - 1.5) * 1.6), hcol, 2.6, true)
	if on:
		var w := _tw(f600, 13, interact_label) + 22
		var lr := Rect2(ci.x - ri - 8 - w, ci.y - 14, w, 28)
		ui.draw_style_box(_box(hud_on(), 14), lr)
		_text(ui, f600, 13, lr.position + Vector2(11, 0), 28, interact_label, ink)
		buttons.append({id = "interact", rect = Rect2(ci - Vector2(30, 30), Vector2(60, 60)).merge(lr)})


func _draw_pip() -> void:
	for b in boxes.values():
		if b.a <= 0 or not b.has("rect"):
			continue
		var r: Rect2 = b.rect
		var k := Color("#FFD84D") if b.hot else Color.WHITE
		k.a = b.a
		var sh := Color(0, 0, 0, .35 * b.a)
		for pass_i in 2:
			var col := sh if pass_i == 0 else k
			var o := Vector2(.6, .6) if pass_i == 0 else Vector2.ZERO
			for corner in 4:
				var cx := r.position.x if corner % 2 == 0 else r.end.x
				var cy := r.position.y if corner < 2 else r.end.y
				var sx := 1.0 if corner % 2 == 0 else -1.0
				var sy := 1.0 if corner < 2 else -1.0
				var p := Vector2(cx, cy) + o
				pip_over.draw_rect(Rect2(p.x + min(0, sx * 8), p.y + min(0, sy * 2), 8, 2), col)
				pip_over.draw_rect(Rect2(p.x + min(0, sx * 2), p.y + min(0, sy * 8), 2, 8), col)
		var lw := _tw(f700, 10, b.label) + 10
		var ly: float = r.position.y - 3 - 15 if b.up else r.end.y + 3
		var lr := Rect2(r.position.x, ly, lw, 15)
		var lbg := Color("#FFD84D", b.a) if b.hot else Color(20 / 255.0, 20 / 255.0, 24 / 255.0, .62 * b.a)
		pip_over.draw_style_box(_box(lbg, 5), lr)
		_text(pip_over, f700, 10, lr.position + Vector2(5, 0), 15, b.label, Color(INK, b.a) if b.hot else Color(1, 1, 1, b.a))
	# Whose eyes these are
	var w := 6 + 6 + 4 + _tw(f650, 12, pip_name) + 8
	var r := Rect2(7, 7, w, 21)
	pip_over.draw_style_box(_box(Color(20 / 255.0, 20 / 255.0, 24 / 255.0, .5), 10.5), r)
	var pulse := .35 + .65 * (.5 + .5 * cos(time / 1.6 * TAU))
	pip_over.draw_circle(Vector2(7 + 6 + 3, 7 + 10.5), 3, Color("#FF5A4E", pulse), true, -1, true)
	_text(pip_over, f650, 12, Vector2(7 + 16, 7), 21, pip_name, Color.WHITE)


# ---------- Fingers ----------

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index, e.position)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		_drag(e.index, e.position)
		get_viewport().set_input_as_handled()


func _press(i: int, p: Vector2) -> void:
	for b in buttons:
		if b.rect.has_point(p):
			touches[i] = {kind = "btn", id = b.id, rect = b.rect}
			pressed_btn = b.id
			return
	var s := get_viewport_rect().size
	if stick_id < 0 and Rect2(0, 70, 330 + pad_l - 30, s.y - 70).has_point(p):
		touches[i] = {kind = "stick"}
		stick_id = i
		stick_base = p
		stick_knob = Vector2.ZERO
		steer.emit(Vector2.ZERO)
		return
	touches[i] = {kind = "world", start = p, last = p, moved = false}


func _drag(i: int, p: Vector2) -> void:
	if not touches.has(i):
		return
	var t: Dictionary = touches[i]
	if t.kind == "stick":
		var d := p - stick_base
		# Past the rim, the base follows your thumb, so you never lose the stick
		if d.length() > STICK_R:
			stick_base += d.normalized() * (d.length() - STICK_R)
			d = d.normalized() * STICK_R
		stick_knob = d
		steer.emit(d / STICK_R)
	elif t.kind == "world":
		if not t.moved and p.distance_to(t.start) < 5:
			return
		t.moved = true
		look.emit(p - t.last)
		t.last = p


func _release(i: int, p: Vector2) -> void:
	if not touches.has(i):
		return
	var t: Dictionary = touches[i]
	touches.erase(i)
	if t.kind == "btn":
		pressed_btn = ""
		if t.rect.grow(8).has_point(p):
			_fire(t.id)
	elif t.kind == "stick":
		stick_id = -1
		stick_base = BASE0 + Vector2(pad_l - 30, 0)
		stick_knob = Vector2.ZERO
		steer.emit(Vector2.ZERO)
	elif t.kind == "world" and not t.moved:
		tap.emit(p)


func _fire(id: String) -> void:
	if id.begins_with("chip:"):
		chip.emit(int(id.substr(5)))
	elif id == "mic":
		mic.emit()
	elif id.begins_with("pal:"):
		pal.emit(id.substr(4))
	elif id == "reset":
		restart.emit()
	elif id == "sound":
		sound.emit()
	elif id == "dash":
		dash.emit()
	elif id == "interact":
		interact.emit()


## Where a button is right now, for the autoplay test.
func button_rect(id: String) -> Rect2:
	for b in buttons:
		if b.id == id:
			return b.rect
	return Rect2()
