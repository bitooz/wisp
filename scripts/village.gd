class_name Village
extends RefCounted
## What makes the village lived in, round the homes (houses.gd): a well, lamps along the path that glow at
## night, Tam's fenced garden and hives with bees about them, Odo's kiln and clay pit, Nell's drying rack, her
## boat drawn up on the south beach and a jetty out into the sea, a washing line behind Mo and Bo's house,
## flowers along the walls, and barrels and crates where people would keep things.
##
## Scenery, solid to bump into and to see, but not things to name: except the well, which they can use.

const WELL := Vector2(-3.6, 17.4)
const LAMPS := [Vector2(1.9, 24.6), Vector2(-3.3, 13.2), Vector2(4.0, 8.4), Vector2(12.6, 20.2), Vector2(-12.5, 15.6)]
const GARDEN := Vector2(17.4, 27.6)
const JETTY_FROM := Vector2(2.6, 50.8)

## Lamp glass (glows at night) and the bees' motes, for the island to light and show
var lamp_m: ShaderMaterial
var lamp_glows := []
var bees: CPUParticles3D
## Circles to keep the woods and grass off: [Vector2, r]
var clear := []
## Everything here but the well hangs off this, to be baked into one mesh (Houses.bake)
var root: Node3D


func build(isle: Level) -> void:
	root = Build.group(isle)
	var at := func(x: float, z: float, up := 0.0) -> Vector3: return Vector3(x, isle.ground(x, z) + up, z)
	var wood := Build.mat("#7A5236", {ao = .3})
	var dark_wood := Build.mat("#5A3E2B")
	var stone := Build.mat("#A39C92", {ao = .3, ao_h = .6})
	var iron := Build.mat("#55555E", {roughness = .5})

	# The well: a stone ring, a little roof on two posts, a crank and a bucket
	var well := Build.group(null, "well")
	Build.mesh(Build.cyl(.78, .86, .75, 14), stone, 0, .37, 0, well)
	Build.mesh(Build.cyl(.62, .62, .06, 14), Build.basic("#1E2A33"), 0, .7, 0, well)
	Build.mesh(Build.torus(.8, .07, 6, 18), Build.mat("#B5ADA2"), 0, .76, 0, well).rotation.x = PI / 2
	for s in [-1.0, 1.0]:
		Build.mesh(Build.box(.12, 1.7, .12), wood, s * .72, 1.4, 0, well)
	Build.rot(Build.mesh(Build.cyl(.05, .05, 1.5, 8), dark_wood, 0, 1.75, 0, well), 0, 0, PI / 2)
	Build.mesh(Build.box(.04, .3, .04), iron, .8, 1.62, .0, well)
	for s in [-1.0, 1.0]:
		var r := Build.mesh(Build.box(1.9, .07, .75), Build.mat("#B5563C"), 0, 2.33, s * .3, well)
		r.rotation.x = s * .55
	var bucket := Build.mesh(Build.cyl(.14, .11, .22, 10), Build.mat("#8A6A4A"), .2, 1.2, .1, well)
	Build.mesh(Build.torus(.14, .012, 5, 12), iron, 0, .1, 0, bucket).rotation.x = PI / 2
	well.position = at.call(WELL.x, WELL.y)
	well.rotation.y = .4
	isle.add_child(well)
	isle.things.append({t = "well", node = well})
	isle.labels["well"] = "the well"
	isle.names["well"] = "well"
	isle.said["well"] = "the village well"
	isle.obstacles.append([WELL.x, WELL.y, .9])
	clear.append([WELL, 1.8])

	# Lamps along the path: posts with a lantern on an arm, lit at dusk
	lamp_m = Build.mat("#FFE6A3", {emissive = "#FFC45C", ei = .0, roughness = .4, unique = true})
	for q in LAMPS:
		var g := Build.group(root)
		Build.mesh(Build.box(.14, 2.3, .14), dark_wood, 0, 1.15, 0, g)
		Build.mesh(Build.box(.5, .08, .08), dark_wood, .22, 2.18, 0, g)
		Build.mesh(Build.box(.26, .04, .26), iron, .42, 2.03, 0, g)
		Build.mesh(Build.box(.24, .04, .24), iron, .42, 1.73, 0, g)
		Build.noshadow(Build.mesh(Build.box(.2, .26, .2), lamp_m, .42, 1.88, 0, g))
		Build.mesh(Build.cone(.19, .16, 4), iron, .42, 2.13, 0, g).rotation.y = PI / 4
		var gl := Build.glow("#FFC867", 1.6)
		gl.position = Vector3(.42, 1.88, 0)
		g.add_child(gl)
		lamp_glows.append(gl)
		g.position = at.call(q.x, q.y)
		g.rotation.y = atan2(-q.x, -(q.y - 18.0)) + PI / 2
		isle.obstacles.append([q.x, q.y, .18])
		clear.append([q, .8])

	# Tam's garden: rows of beans and cabbages behind a little fence
	var gd := Build.group(root)
	var soil := Build.mat("#6E4E36", {ao = .2})
	for i in 3:
		var z := -1.0 + i * 1.0
		Build.mesh(Build.box(3.0, .18, .55), soil, 0, .06, z, gd)
		for j in 6:
			var x := -1.25 + j * .5
			if i == 1:
				# Beans up their poles
				Build.mesh(Build.cyl(.015, .02, 1.1, 5), wood, x, .6, z, gd)
				Build.mesh(Build.ico(.13 + (j % 2) * .03, 0), Build.mat("#6FAF4F", {sway = .3}), x, .75 + (j % 3) * .12, z, gd)
			else:
				Build.mesh(Build.ico(.16 + (j % 3) * .03, 1), Build.mat("#8CC46A" if j % 2 else "#A6D47E"), x, .22, z, gd).scale.y = .7
	var fence := Build.mat("#C9B48A", {ao = .3, ao_h = .5})
	var gw := 3.8
	var gh := 3.4
	for side in [[Vector2(-gw / 2, -gh / 2), Vector2(gw / 2, -gh / 2)], [Vector2(gw / 2, -gh / 2), Vector2(gw / 2, gh / 2)],
			[Vector2(gw / 2, gh / 2), Vector2(-gw / 2, gh / 2)], [Vector2(-gw / 2, gh / 2), Vector2(-gw / 2, .5)], [Vector2(-gw / 2, -.5), Vector2(-gw / 2, -gh / 2)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var n := maxi(1, int(a.distance_to(b) / .45))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			Build.mesh(Build.box(.07, .62, .07), fence, p.x, .31, p.y, gd)
		for y in [.22, .48]:
			var r := Build.mesh(Build.box(a.distance_to(b), .05, .04), fence, (a.x + b.x) / 2, y, (a.y + b.y) / 2, gd)
			r.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	gd.position = at.call(GARDEN.x, GARDEN.y)
	isle.obstacles.append([GARDEN.x, GARDEN.y, 1.9, 1])
	clear.append([GARDEN, 2.8])

	# Bees about Tam's hives
	var hives: Vector2 = Folk.SPOTS.tam.chore + Vector2(0, 1.2)
	bees = Build.motes(14, Vector3(1.4, .5, .8), "#FFD45C", .06, 3.0)
	bees.initial_velocity_min = .4
	bees.initial_velocity_max = .9
	bees.position = at.call(hives.x, hives.y, .8)
	root.add_child(bees)

	# Odo's kiln, a stack of pots, and his clay pit by the pond
	var kq: Vector2 = Folk.SPOTS.odo.hobby + Vector2(-1.8, -1.2)
	var kiln := Build.group(root)
	var clay := Build.mat("#B5704C", {ao = .35, ao_h = .7})
	Build.mesh(Build.sphere(.85, 14, 8, PI / 2), clay, 0, 0, 0, kiln).scale.y = 1.1
	Build.mesh(Build.box(.5, .5, .3), Build.mat("#2A2420"), 0, .25, .72, kiln)
	Build.mesh(Build.cyl(.14, .18, .5, 8), clay, .2, 1.05, -.2, kiln)
	for i in 5:
		var a := i * 1.3
		Build.mesh(Build.cyl(.1 + (i % 2) * .04, .13, .3 + (i % 3) * .08, 9), Build.mat(["#C98A5E", "#8E5A3C", "#D9A06E"][i % 3]), 1.2 + cos(a) * .3, .17, .3 + sin(a) * .3, kiln)
	kiln.position = at.call(kq.x, kq.y)
	kiln.rotation.y = Folk.HOME.odo.yaw
	isle.obstacles.append([kq.x, kq.y, .95])
	clear.append([kq, 2.2])
	var pit: Vector2 = Folk.SPOTS.odo.chore + Vector2(.9, .4)
	var pg := Build.group(root)
	Build.noshadow(Build.mesh(Build.disc(1.0, 14), Build.mat("#7A5A44"), 0, .03, 0, pg)).rotation.x = -PI / 2
	Build.mesh(Build.cyl(.16, .13, .28, 10), Build.mat("#8A6A4A"), .9, .14, .5, pg)
	var spade := Build.mesh(Build.box(.04, 1.0, .04), wood, -.7, .5, -.3, pg)
	spade.rotation.z = .3
	Build.mesh(Build.box(.2, .26, .03), iron, 0, -.55, 0, spade)
	pg.position = at.call(pit.x, pit.y)
	clear.append([pit, 1.4])

	# Nell's drying rack (fish and a net), her boat up on the sand, and a jetty out into the sea
	var nr: Vector2 = Folk.HOME.nell.at + Vector2(3.6, -1.6)
	var rack := Build.group(root)
	for s in [-1.0, 1.0]:
		Build.mesh(Build.box(.12, 1.8, .12), dark_wood, s * 1.1, .9, 0, rack)
	Build.mesh(Build.box(2.4, .08, .08), dark_wood, 0, 1.72, 0, rack)
	for i in 5:
		var f := Build.mesh(Build.sphere(.1, 8, 6), Build.mat("#8FA6B0", {roughness = .4}), -.8 + i * .4, 1.42, 0, rack)
		f.scale = Vector3(.6, 2.2, .35)
	var cord := Build.mat("#C9B48A")
	for i in 7:
		Build.mesh(Build.box(.015, .9, .015), cord, -1.0 + i * .33, 1.25, .1, rack)
	rack.position = at.call(nr.x, nr.y)
	rack.rotation.y = Folk.HOME.nell.yaw + .4
	isle.obstacles.append([nr.x, nr.y, 1.1, 1])
	clear.append([nr, 1.6])
	var bq := JETTY_FROM + Vector2(3.4, -1.0)
	var boat := Build.group(root)
	var hull := Build.mat("#E8E1D4", {ao = .25, ao_h = .4})
	var stripe := Build.mat("#C8553D")
	for s in [-1.0, 1.0]:
		var side := Build.mesh(Build.box(2.6, .4, .08), hull, 0, .28, s * .5, boat)
		side.rotation.x = s * -.35
		Build.mesh(Build.box(2.5, .07, .05), stripe, 0, .46, s * .58, boat)
	Build.mesh(Build.box(2.4, .08, .8), Build.mat("#B98A5A"), 0, .1, 0, boat)
	Build.mesh(Build.box(.12, .42, 1.0), hull, -1.3, .26, 0, boat)
	Build.mesh(Build.box(.3, .06, .9), Build.mat("#B98A5A"), .2, .32, 0, boat)
	for s in [-1.0, 1.0]:
		var oar := Build.mesh(Build.box(2.0, .04, .06), Build.mat("#B98A5A"), .1, .4, s * .2, boat)
		oar.rotation.y = s * .15
	boat.position = at.call(bq.x, bq.y)
	boat.rotation = Vector3(0, .6, .06)
	isle.obstacles.append([bq.x, bq.y, 1.2, 1])
	# The jetty starts where the sand runs down to the water
	var jdir := Vector2(.12, 1).normalized()
	var jfrom := JETTY_FROM
	for i in 40:
		if isle.ground(jfrom.x, jfrom.y) < .75:
			break
		jfrom += jdir * .25
	var jetty := Build.group(root)
	var plank := Build.mat("#A57E58", {ao = .25})
	var top := isle.ground(jfrom.x, jfrom.y) + .3
	for i in 27:
		var p := jfrom + jdir * (i * .42)
		Build.mesh(Build.box(1.5, .07, .38), plank if i % 3 else Build.mat("#94704E"), p.x, top, p.y, jetty).rotation.y = atan2(jdir.x, jdir.y) + (Build.rnd() - .5) * .04
		if i % 4 == 0:
			for s in [-1.0, 1.0]:
				var post: Vector2 = jfrom + jdir * (i * .42) + jdir.orthogonal() * s * .7
				Build.mesh(Build.cyl(.08, .09, 2.6, 7), dark_wood, post.x, top - 1.1, post.y, jetty)
	clear.append([JETTY_FROM, 1.5])

	# A washing line behind Mo and Bo's house
	var hy: float = .55
	var turn := func(x: float, z: float) -> Vector2: return Vector2(-8, 13) + Vector2(x * cos(hy) + z * sin(hy), -x * sin(hy) + z * cos(hy))
	var la: Vector2 = turn.call(-2.2, -3.6)
	var lb: Vector2 = turn.call(2.4, -3.6)
	var line := Build.group(root)
	var ya := isle.ground(la.x, la.y)
	for q in [la, lb]:
		Build.mesh(Build.box(.1, 1.9, .1), dark_wood, q.x, isle.ground(q.x, q.y) + .95, q.y, line)
	var cl := Build.mesh(Build.box(la.distance_to(lb), .015, .015), cord, (la.x + lb.x) / 2, ya + 1.8, (la.y + lb.y) / 2, line)
	cl.rotation.y = -atan2(lb.y - la.y, lb.x - la.x)
	var cols := ["#E57A5A", "#FFFFFF", "#5AA9FF", "#F2D27A", "#9BC27A"]
	for i in 5:
		var k := (i + .7) / 5.6
		var q := la.lerp(lb, k)
		var c := Build.mesh(Build.box(.42 + (i % 2) * .12, .5 - (i % 3) * .08, .02), Build.mat(cols[i], {flat = false}), q.x, ya + 1.55 - (i % 3) * .04, q.y, line)
		c.rotation.y = cl.rotation.y
	isle.obstacles.append([la.x, la.y, .12])
	isle.obstacles.append([lb.x, lb.y, .12])
	clear.append([(la + lb) / 2, 2.6])

	# Barrels and crates where people keep things; flowers along the walls
	# (Flush against the walls, inside the room everyone keeps from a house anyway: nothing more to walk round)
	var beside := func(id: String, lx: float, lz: float) -> Vector3:
		var hat: Vector2 = Vector2(-8, 13) if id == "house" else Folk.HOME[id].at
		var yaw: float = .55 if id == "house" else Folk.HOME[id].yaw
		var q := hat + Vector2(lx * cos(yaw) + lz * sin(yaw), -lx * sin(yaw) + lz * cos(yaw))
		return at.call(q.x, q.y)
	var stash := [["barrel_large", "house", 3.6, -.9, .7], ["box_small", "house", 3.45, .05, .8], ["crates_stacked", "house", 3.65, -1.85, .6],
		["barrel_small", "nell", 2.8, -.9, .8], ["crates_stacked", "nell", 3.0, .3, .7], ["barrel_small", "tam", 2.85, -1.0, .75],
		["barrel_small", "odo", -2.8, -.6, .75]]
	for s in stash:
		Props.kaykit(root, s[0], beside.call(s[1], s[2], s[3]), Build.rnd() * TAU, s[4], {})
	for i in 7:
		var q: Vector2 = turn.call(-2.6 + i * .8 + (1.2 if i > 1 else 0.0), 2.75)
		if i == 2:
			continue
		Props.place(root, Props.QUAT + ["Flower_3_Group.gltf", "Flower_4_Group.gltf"][i % 2], at.call(q.x, q.y), Build.rnd() * TAU, .5, {shadow = false, nohit = true})
