class_name Folk
extends RefCounted
## The other people on the island, besides Mo and Bo: who they are, where they live, their day, and what each
## of them wants. Each one has the same mind as Mo and Bo (mind.gd: sight, body, memory, mood, plans, a life
## that goes on while the game's closed, private thoughts, skills, body language) and the same kind of body:
## Mo's or Bo's rigged model, grown up (taller, broader) and in other colours (pal.gd, shaders/pal.gdshader).
##
##   Nell, the old fisher: a hut above the south beach. Out fishing at dawn, mending nets in the afternoon,
##     always first with the news. She's lost her lucky float (it washed off in a storm).
##   Tam, the beekeeper: a cottage east of the village, by her hives. Warm and a worrier. She's put her bee
##     smoker down somewhere by the pond and can't find it.
##   Odo, the potter: a hut west of the pond, by his clay. Shy, with a dry joke now and then. He'd love a
##     shell from the beach to press its pattern into his new pot.
##
## A want is something they'd like done; told to someone who'd help, it becomes their quest (a thing in their
## plan, minds.gd), and it's done when the thing is put in the wanter's hands (Mind give). Pure data.

const IDS := ["nell", "tam", "odo"]
## Everyone with a mind of their own, and how they're named
const NAMES := {wisp = "Wisp", mo = "Mo", bo = "Bo", nell = "Nell", tam = "Tam", odo = "Odo"}
const HIS := {mo = "her", bo = "his", nell = "her", tam = "her", odo = "his"}

## Their bodies: which model, how much bigger (x and z, then y), what colours (hue turned, colour taken out,
## lighter or darker: only the strongly coloured parts, so skin stays skin), the glow colour, the render
## layer (each their own), and how fast they talk
const BODY := {
	nell = {model = "mo", scale = Vector3(1.32, 1.42, 1.32), hue = 0.0, desat = .9, tone = 1.2, brow = "#8C8C8C", color = "#B8C4CC", layer = 4, rate = .95},
	tam = {model = "mo", scale = Vector3(1.55, 1.48, 1.55), hue = .62, desat = 0.0, tone = 1.05, brow = "#7A5A1E", color = "#E8C547", layer = 5, rate = 1.0},
	odo = {model = "bo", scale = Vector3(1.32, 1.36, 1.32), hue = 2.4, desat = .2, tone = .85, brow = "#1E2422", color = "#4FB3A5", layer = 6, rate = .92},
}

## Where they live (a hut: x, z, which way its door faces), and what it's called
const HOME := {
	nell = {at = Vector2(9.0, 41.0), yaw = 2.9, what = "Nell's hut", walls = "#E9DCC6", roof = "#5C7C8A"},
	tam = {at = Vector2(19.0, 22.0), yaw = -1.5, what = "Tam's cottage", walls = "#F3E3B8", roof = "#C9893A"},
	odo = {at = Vector2(-21.0, 15.0), yaw = 1.2, what = "Odo's hut", walls = "#D9C2A8", roof = "#7A5A86"},
}

## What they give a hungry neighbour at the door
const TREAT := {nell = "a bit of smoked fish", tam = "bread and honey", odo = "a bowl of soup"}

## Their day, as Life.ROUND has Mo's and Bo's
const ROUND := {
	nell = [[0.0, "sleep"], [5.5, "breakfast"], [6.0, "chore"], [10.5, "own"], [12.0, "lunch"], [13.0, "hobby"],
		[16.5, "free"], [18.0, "supper"], [19.0, "campfire"], [21.0, "sleep"]],
	tam = [[0.0, "sleep"], [7.0, "breakfast"], [7.5, "chore"], [10.5, "own"], [12.5, "lunch"], [13.5, "hobby"],
		[17.0, "free"], [18.0, "supper"], [19.5, "campfire"], [22.0, "sleep"]],
	odo = [[0.0, "sleep"], [8.0, "breakfast"], [8.5, "chore"], [11.0, "own"], [13.0, "lunch"], [14.0, "hobby"],
		[17.5, "free"], [19.0, "supper"], [20.0, "campfire"], [23.0, "sleep"]],
}
const CHORE := {nell = "go fishing off the south beach", tam = "tend the bees", odo = "dig clay by the pond"}
const HOBBY := {nell = "mend my nets", tam = "work in my garden", odo = "throw pots at my wheel"}
const CHORE_ING := {nell = "fishing off the south beach", tam = "tending the bees", odo = "digging clay by the pond"}
const HOBBY_ING := {nell = "mending nets", tam = "working in the garden", odo = "throwing pots"}
## What each chore and hobby leaves in their memory (a good day, a poor one)
const DID := {
	nell = {chore = ["went fishing off the south beach and caught a good few fish", "went fishing off the south beach; hardly a bite all morning"],
		hobby = ["mended a long tear in my net", "sat mending my nets"]},
	tam = {chore = ["tended the bees; they were calm and busy", "tended the bees; they were cross today and one stung me"],
		hobby = ["weeded the garden and picked beans", "pottered about in the garden"]},
	odo = {chore = ["dug a good bucket of clay by the pond", "dug clay by the pond, but it was full of grit"],
		hobby = ["threw a new pot at the wheel; it came out well", "threw a pot at the wheel, but it slumped"]},
}
## Where they are at each part of their day (offsets from home for chore, hobby and own, or a place)
const SPOTS := {
	nell = {chore = Vector2(4.0, 50.0), hobby = Vector2(10.6, 39.2), own = Vector2(2.0, 30.0)},
	tam = {chore = Vector2(22.5, 18.5), hobby = Vector2(17.0, 25.5), own = Vector2(12.0, 17.0)},
	odo = {chore = Vector2(-15.8, 19.0), hobby = Vector2(-19.4, 11.7), own = Vector2(-6.0, 26.0)},
}
## Round the campfire in the evening (an angle round it), so they don't all stand in one spot
const FIRE_SEAT := {mo = -2.2, bo = 2.2, nell = 3.4, tam = -3.4, odo = 0.6}

## What they knew before the game began (their memory seeds): who they are, what they want, and what they've
## seen of the others
const SEEDS := {
	nell = [["note", "I'm Nell. I've fished off this island my whole life, and I knew Mo and Bo's grandma well."],
		["note", "I want my lucky float back: the old green glass one. The storm took it; it'll have washed up somewhere along the north-east shore."],
		["saw", "Mo: curly red hair, a red hoodie, always running"],
		["saw", "Bo: a beanie with a red bobble, goggles, a blue vest"],
		["saw", "Tam, the beekeeper, in her yellow top; Odo the potter, quiet, with clay on his hands"],
		["saw", "Wisp, a kid with a glowing lantern who's turned up on the island: curly brown hair, a green jacket"]],
	tam = [["note", "I'm Tam. I keep the bees in the cottage east of the village, and I worry about everyone."],
		["note", "I want my bee smoker back. I put it down somewhere by the pond and now I can't find it anywhere."],
		["saw", "Mo and Bo, the two kids from the house in the village"],
		["saw", "Nell, the old fisher from the hut above the beach; Odo the potter, who lives past the pond"],
		["saw", "Wisp, a kid with a glowing lantern who's turned up on the island"]],
	odo = [["note", "I'm Odo. I make pots in my hut west of the pond. I'm not one for talking much."],
		["note", "I'd love a shell from the beach, a nice ridged one, to press its pattern into my new pot."],
		["saw", "Mo and Bo, the kids from the house in the village; Mo's always about"],
		["saw", "Nell the fisher, who knows everything that goes on; Tam the beekeeper, with her bees"],
		["saw", "Wisp, a kid with a glowing lantern who's turned up on the island"]],
}

## What each of them wants: what would do it (a thing whose tag starts with this, put in their hands), in their
## words (as a story others pass on), and as a thing to do for whoever takes it up
const WANTS := {
	nell = {item = "float", text = "Nell has lost her lucky float, an old green glass one; the storm washed it off, and it's somewhere along the north-east shore",
		todo = "find Nell's lucky float on the north-east shore and give it to her", done = "found Nell's lucky float and gave it back to her",
		goal = "get my lucky float back", thanks = "found my lucky float and gave it back to me"},
	tam = {item = "smoker", text = "Tam has lost her bee smoker; she put it down somewhere by the pond and can't find it",
		todo = "find Tam's bee smoker by the pond and give it to her", done = "found Tam's bee smoker and gave it back to her",
		goal = "get my bee smoker back", thanks = "found my bee smoker and gave it back to me"},
	odo = {item = "shell", text = "Odo would love a shell from the beach, to press its pattern into his new pot",
		todo = "bring Odo a shell from the beach for his pot", done = "brought Odo a shell from the beach for his pot",
		goal = "get a shell for my pot", thanks = "brought me a shell from the beach for my pot"},
}

## How they feel about each other at the start: [trust, fond]. Mo and Bo's feelings toward them too.
const BONDS := {
	mo = {nell = [.6, .7], tam = [.6, .5], odo = [.4, .3]},
	bo = {nell = [.5, .4], tam = [.6, .4], odo = [.6, .55]},
	nell = {wisp = [.1, .2], mo = [.6, .7], bo = [.5, .6], tam = [.5, .45], odo = [.4, .25]},
	tam = {wisp = [.2, .3], mo = [.55, .6], bo = [.55, .5], nell = [.5, .5], odo = [.45, .4]},
	odo = {wisp = [0.0, .05], mo = [.35, .3], bo = [.6, .55], nell = [.35, .2], tam = [.5, .45]},
}
## How they usually are: mood (v, a), and how they take teasing
const TEMPER := {nell = [.15, .5, .3], tam = [.2, .45, .2], odo = [0.0, .25, -.2]}
## What they're good at to start with
const SKILLS := {
	nell = {chopping = .4, building = .5, mechanisms = .35, wayfinding = .85, night_eyes = .6},
	tam = {chopping = .3, building = .35, mechanisms = .4, wayfinding = .6, night_eyes = .35},
	odo = {chopping = .45, building = .6, mechanisms = .55, wayfinding = .5, night_eyes = .4},
}


static func has(who: String) -> bool:
	return IDS.has(who)


## Everyone with feelings and a memory (not Wisp: that's you).
static func everyone() -> Array:
	return ["mo", "bo"] + IDS


## Who someone has feelings about: everyone else, and Wisp.
static func others(who: String) -> Array:
	return (["wisp"] + everyone()).filter(func(o): return o != who)


## Whose want this thing would do (a thing's tag), or "".
static func wanted_by(tag: String) -> String:
	for w in WANTS:
		if tag.begins_with(WANTS[w].item):
			return w
	return ""
