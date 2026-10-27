class_name Body
extends RefCounted
## Mo's or Bo's body: hunger, tiredness, cold, fear and boredom, each from 0 (none) to 1 (as bad as it gets),
## and how wet their feet and hands are (wet makes you colder, and dries off, faster by a fire).
## They rise and fall with time and with where they are (step()), and come to them only as feelings (feel()):
## never as numbers, never as a list of what's around. What they do about it is theirs.
##
## step() is pure arithmetic on what's around them (a Ctx), so tests can run days of it with fixed steps.

## What's around a body right now, as the world has it (Level.surroundings()).
class Ctx:
	extends RefCounted
	## Light where they are: 0 pitch dark, 1 broad day
	var light := 1.0
	## How cold the air is here: 0 warm, 1 a cold night out in the open
	var chill := 0.0
	## Warmth from a fire nearby, or being indoors: 0 none, 1 right by it
	var warmth := 0.0
	## Someone they know is close by
	var company := true
	## Walking about (tires you more than standing)
	var moving := false
	## Standing in water (wets your feet)
	var in_water := false

## Rises per game hour, awake
const HUNGER_PER_H := .07
const TIRED_PER_H := .045
const TIRED_MOVING_PER_H := .03
## Falls per game hour
const SLEEP_RESTS_PER_H := .09
const REST_RESTS_PER_H := .05
## Sleeping makes you hungry more slowly
const HUNGER_ASLEEP := .4
## How fast cold follows the air (per game hour)
const COLD_FOLLOWS := 1.2
## Drying off (per game hour), and how much colder being wet makes the air feel
const DRIES_PER_H := .8
const WET_CHILL := .3
## How fast fear follows the dark (per real second), and boredom rises standing about (per real second)
const FEAR_FOLLOWS := .12
const BORED_PER_S := 1.0 / 150.0

var hunger := .2
var tired := .1
var cold := 0.0
var fear := 0.0
var bored := 0.0
var wet_feet := 0.0
var wet_hands := 0.0
var in_water := false
var asleep := false
var resting := false
## How each of them takes the dark: Mo hates not seeing, Bo just gets on with it
var dark_fear := .75
## Game hours since they last ate and woke (for "you ate not long ago")
var since_ate := 99.0
var since_woke := 99.0
## What they had last, in their own word
var last_food := ""


func _init(who := "") -> void:
	if who == "bo":
		dark_fear = .6


## hours: game time passed; secs: real time passed (fear and boredom go by what you live through, not the clock).
## idle: standing about with nothing new going on.
func step(hours: float, secs: float, c: Ctx, idle: bool) -> void:
	since_ate += hours
	since_woke += 0.0 if asleep else hours
	hunger = clampf(hunger + hours * HUNGER_PER_H * (HUNGER_ASLEEP if asleep else 1.0), 0, 1)
	if asleep:
		tired -= hours * SLEEP_RESTS_PER_H
	elif resting:
		tired -= hours * REST_RESTS_PER_H
	else:
		tired += hours * (TIRED_PER_H + (TIRED_MOVING_PER_H if c.moving else 0.0))
	tired = clampf(tired, 0, 1)
	# Wet: in the water your feet are soaked; out of it, everything dries, faster by a fire
	in_water = c.in_water
	if in_water:
		wet_feet = 1.0
	else:
		wet_feet = maxf(0, wet_feet - hours * DRIES_PER_H * (1.0 + c.warmth * 2.0))
	wet_hands = maxf(0, wet_hands - hours * DRIES_PER_H * 1.5 * (1.0 + c.warmth * 2.0))
	# Cold follows the air, less of it by a fire or indoors; lying still on the ground at night is colder, and
	# so is being wet
	var wet := maxf(wet_feet, wet_hands * .6)
	var air := clampf(c.chill * (1.0 - c.warmth) + (.2 if (asleep or resting) and c.warmth < .3 else 0.0) - c.warmth * .3
		+ wet * WET_CHILL * (.4 + c.chill), 0, 1)
	cold = move_toward(cold, air, hours * COLD_FOLLOWS)
	# Fear follows the dark (worse alone); asleep, you don't see it
	if not asleep:
		var dark := clampf((.35 - c.light) / .35, 0, 1)
		var want := dark * dark_fear * (1.0 if c.company else 1.3)
		fear = clampf(fear + (want - fear) * (1.0 - exp(-secs * FEAR_FOLLOWS)), 0, 1)
	# Standing about with nothing new gets boring; doing things, or being asleep, doesn't
	if asleep:
		bored = maxf(0, bored - secs * BORED_PER_S)
	elif idle:
		bored = minf(1, bored + secs * BORED_PER_S * (.5 if resting else 1.0))
	else:
		bored = maxf(0, bored - secs * BORED_PER_S * 3.0)


## Something new happened, or they did something: less bored.
func perked(by := .35) -> void:
	bored = maxf(0, bored - by)


## A fright (the shadow lunging).
func scared(by := .5) -> void:
	fear = minf(1, fear + by)


## Eating: how filling it is (a share of a meal).
func eat(food: float, what: String) -> void:
	hunger = maxf(0, hunger - food)
	since_ate = 0
	last_food = what


## Room for anything? (Stuffed full, you can't eat more.)
func can_eat() -> bool:
	return hunger > .12


## Can they fall asleep now? (Only when tired enough, and not starving, freezing or terrified.)
func can_sleep() -> String:
	if tired < .45:
		return "not sleepy"
	if hunger > .85:
		return "too hungry"
	if cold > .8:
		return "too cold"
	if fear > .75:
		return "too scared"
	return ""


## Asleep, does a sound this loud (0 to 1, where they are) wake them? The more tired, the deeper they sleep:
## just asleep after a long day it takes a loud one; near morning, much less.
func woken_by(level: float) -> bool:
	return asleep and level >= .45 + .5 * tired


## Asleep, what wakes them (on its own): "" for nothing yet. Rested, they sleep on till morning (their body knows
## the time of day, even under the hill: daylight is the clock's).
func wakes(daylight: float) -> String:
	if not asleep:
		return ""
	if hunger > .9:
		return "hungry"
	if cold > .85:
		return "cold"
	if tired < .12 and daylight > .3:
		return "rested"
	return ""


## How it all feels, in words: what goes to the model. No numbers, nothing named but their own body.
func feel() -> Array:
	var out := []
	if asleep:
		return out
	var h := _band(hunger, [.35, .6, .85], ["a bit peckish", "hungry: your tummy is rumbling", "really hungry: you feel wobbly and weak"])
	if h == "" and since_ate < 1.0:
		h = "full: you ate not long ago"
	if h != "":
		out.append(h)
	var t := _band(tired, [.45, .7, .88], ["a little tired", "tired: your legs are heavy and you keep yawning", "so sleepy you can hardly keep your eyes open"])
	if t == "" and since_woke < 1.5:
		t = "wide awake and rested: you slept well"
	if t != "":
		out.append(t)
	var c := _band(cold, [.3, .55, .8], ["a bit chilly", "cold: you're shivering", "freezing: your teeth are chattering and your hands are numb"])
	if c != "":
		out.append(c)
	var f := _band(fear, [.3, .55, .8], ["uneasy: you keep glancing about", "scared: your heart's thumping", "terrified: you want to get somewhere safe, now"])
	if f != "":
		out.append(f)
	var b := _band(bored, [.5, .8], ["bored: you want something to do", "really, really bored of standing about"])
	if b != "":
		out.append(b)
	if in_water:
		out.append("standing in water: it's cold round your ankles")
	elif wet_feet > .3:
		out.append("your feet are wet")
	if wet_hands > .3:
		out.append("your hands are wet")
	if resting:
		out.append("resting, lying down" + (": it's nice to be off your feet" if tired > .3 else ""))
	return out


func _band(v: float, at: Array, words: Array) -> String:
	var s := ""
	for i in at.size():
		if v >= at[i]:
			s = words[i]
	return s


func to_dict() -> Dictionary:
	return {hunger = hunger, tired = tired, cold = cold, fear = fear, bored = bored, wet_feet = wet_feet, wet_hands = wet_hands, asleep = asleep}
