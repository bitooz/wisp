class_name Clock
extends RefCounted
## The time of day, everywhere at once (it goes on under the hill too). A whole day takes DAY_MINUTES real
## minutes: the sun comes up about six, goes down about six, and the night between is dark. What it looks like
## is the island's (island.gd); what it does to Mo and Bo is their bodies' (body.gd).
##
## Tests and trying things: --hour=21.5 starts at that hour, --day-minutes=4 makes days go faster.

const DAY_MINUTES := 24.0
const START_HOUR := 8.0

## Hours since the first midnight (so days count up)
var t := START_HOUR
## Game hours per real second
var rate := 24.0 / (DAY_MINUTES * 60.0)
## Held still (tests)
var stopped := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			t = float(a.substr(7))
		elif a.begins_with("--day-minutes="):
			rate = 24.0 / (maxf(.05, float(a.substr(14))) * 60.0)


func step(dt: float) -> void:
	if not stopped:
		t += dt * rate


## Hours a real time span is, now.
func hours(dt: float) -> float:
	return 0.0 if stopped else dt * rate


func set_hour(h: float) -> void:
	t = floorf(t / 24.0) * 24.0 + fposmod(h, 24.0)


func hour() -> float:
	return fposmod(t, 24.0)


func day() -> int:
	return int(floorf(t / 24.0)) + 1


## How high the sun is: 1 at noon, 0 at six in the morning and evening, -1 at midnight.
func sun_height() -> float:
	return sin((hour() - 6.0) / 12.0 * PI)


## How much it's day: 0 at night, 1 from mid-morning to late afternoon.
func daylight() -> float:
	return smoothstep(-.12, .3, sun_height())


## The low, warm light round sunrise and sunset.
func twilight() -> float:
	return 1.0 - smoothstep(.06, .4, absf(sun_height() + .04))


## How much it's night: 1 from about half past seven in the evening to half past four in the morning.
func night() -> float:
	return smoothstep(-.02, -.3, sun_height())


## Morning or evening (for which way the light's going).
func evening() -> bool:
	return hour() >= 12.0


## The time of day as you'd know it without a watch.
func sense() -> String:
	var h := hour()
	if h < 4.5 or h >= 22.0:
		return "it's the middle of the night"
	if h < 6.0:
		return "it's nearly morning: the sky's getting paler"
	if h < 8.0:
		return "it's early morning"
	if h < 11.5:
		return "it's morning"
	if h < 13.5:
		return "it's the middle of the day"
	if h < 16.5:
		return "it's afternoon"
	if h < 18.5:
		return "it's late afternoon, getting on for evening"
	if h < 20.0:
		return "the sun's going down"
	return "it's night"
