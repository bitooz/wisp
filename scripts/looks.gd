class_name Looks
extends RefCounted
## How Mo or Bo looks, from how they are: their body (tired, cold, scared, bored), their mood, and how they feel
## about whoever they're with. What comes out drives the body (pal.gd: a pose layer over the rig's clips, the
## eyelids, a little face) and is what anyone looking at them sees, in their own pictures too (the model is
## never told it in words).
##
##   slump    0..1  tired or low: the back rounds, the head drops, a slower walk
##   hunch    0..1  cold or scared: shoulders up, arms drawn in
##   shiver   0..1  cold: a fast small tremble
##   bounce   0..1  happy and lively: a spring in the step
##   walk     pace, as a share of their usual (tired and hunched slower, bouncy quicker)
##   lids     0 open .. 1 shut (droopy when tired, narrowed when cross)
##   brows    neutral, happy, sad, worried, cross, scared
##   mouth    smile, grin, flat, frown, o (scared or surprised)
##   glance   how often they look about (scared), per second
##   away     look away from whoever they're with (a grudge, or something to hide)
##
## Pure arithmetic: tools/looks_test.gd runs it.

## A face for someone they feel this strongly about (fondness), as a share
const WARMS := .5


## The look of them now. body: Body; heart: Heart; with: who they're with ("wisp", "mo", "bo" or "");
## nervous: they've just said something that wasn't so (0..1, fading).
static func of(body, heart, with := "", nervous := 0.0) -> Dictionary:
	var v: float = heart.v if heart else 0.0
	var a: float = heart.a if heart else .4
	var tired: float = body.tired if body else 0.0
	var cold: float = body.cold if body else 0.0
	var fear: float = body.fear if body else 0.0
	var bored: float = body.bored if body else 0.0
	var e := {}
	e.slump = clampf(maxf(0.0, tired - .4) * 1.6 + maxf(0.0, -v - .1) * .7 + maxf(0.0, bored - .6) * .5, 0.0, 1.0)
	e.hunch = clampf(maxf(0.0, cold - .25) * 1.4 + maxf(0.0, fear - .2) * 1.1, 0.0, 1.0)
	e.shiver = smoothstep(.45, .8, cold)
	e.bounce = clampf(maxf(0.0, v - .25) * 2.0 * smoothstep(.3, .7, a), 0.0, 1.0) * maxf(0.0, 1.0 - 1.5 * e.slump)
	e.walk = clampf(1.0 - .35 * e.slump - .15 * e.hunch + .2 * e.bounce, .55, 1.25)
	e.glance = lerpf(.25, 1.0, smoothstep(.4, .9, fear)) if fear > .4 else 0.0
	# How they feel about whoever they're with shows: warmer for a friend, guarded for a grudge
	var fond := 0.0
	var sore := false
	if heart and with != "" and heart.rel.has(with):
		fond = heart.rel[with].fond
		sore = heart.rel[with].grudges.any(func(g): return float(g.s) > .35)
	var warmth := v + (fond * .25 if with != "" else 0.0) - (.3 if sore else 0.0)
	# The face
	if fear > .55:
		e.brows = "scared"
		e.mouth = "o"
	elif warmth > .5:
		e.brows = "happy"
		e.mouth = "grin"
	elif warmth > .15:
		e.brows = "neutral"
		e.mouth = "smile"
	elif warmth < -.4 and a > .55 or sore:
		e.brows = "cross"
		e.mouth = "frown"
	elif warmth < -.15:
		e.brows = "sad"
		e.mouth = "frown"
	elif fear > .3 or cold > .55:
		e.brows = "worried"
		e.mouth = "flat"
	else:
		e.brows = "neutral"
		e.mouth = "flat"
	e.lids = clampf(maxf(0.0, tired - .5) * 1.4 + (.25 if e.brows == "cross" else 0.0), 0.0, .6) if fear < .55 else 0.0
	# Something to hide (a fib just told), or a grudge: eyes off the one they're with
	e.away = nervous > .2 or sore
	if nervous > .2:
		e.glance = maxf(e.glance, .8)
		e.brows = "worried" if e.brows == "neutral" else e.brows
	return e
