extends Node
## Writes the kart tracks (D147) into content/tracks/, made with the track editor's own commands
## (TrackDraft) so the editor can open and change them:
##   Marble Mile: 1.3 km over rolling grass, tyre walls all round: a fast sweeper, a hairpin, a chicane;
##     automatic item boxes; the plain kart circuit.
##   Gearworks: 1.6 km round a flat concrete yard: boost pads, three rows of boxes, a jump, a
##     wall-ride round the outside of the long corner and the loop on the 14 m back straight;
##     containers and cranes.
##   Skyhop Ridge: 1.8 km on a hillside: three jumps (pads before the big one), a wall-ride round
##     the hairpin, three rows of boxes.
##   Crate Yard: a 100 by 80 m arena with cut corners, crates and tyre stacks, two jumps, two pads.
##   Dust Bowl: a round dirt arena 120 m across, four jumps facing each other round the middle.
##   tools/godot.sh --headless res://tools/make_kart_tracks.tscn [-- --only=<id>] [-- --out=<folder>]

const OUT := "res://content/tracks"
const CREATED := "2026-10-16"
const IDS := ["marble_mile", "gearworks", "skyhop_ridge", "crate_yard", "dust_bowl"]

var opts := { "out": OUT }


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_write.call_deferred()


func _write() -> void:
	var failed := false
	for id: String in IDS:
		if opts.has("only") and opts.only != id:
			continue
		var t0 := Time.get_ticks_msec()
		var d := build(id)
		var found := TrackValidator.check(d)
		for p: Dictionary in found:
			print("  %s %s: %s" % [id, p.level, p.text])
		if not TrackValidator.errors(found).is_empty():
			print("FAIL %s: validation errors" % id)
			failed = true
			continue
		var t := d.track()
		var tags := ["kart", "arena"] if t.type == "arena" else ["kart"]
		var err := TrackWriter.write_folder(String(opts.out).path_join(id),
			d.manifest_info().merged({ "created": CREATED, "tags": tags, "source": "nOSS" }, true), d.files())
		if err:
			print("FAIL %s: %s" % [id, err])
			failed = true
			continue
		var pieces := t.kart.pieces.size() if t.kart else 0
		print("Wrote %s: %s, %.2f km, %d pieces, layout %s, %d ms" % [id, t.type, t.length / 1000.0, pieces, t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(1 if failed else 0)


## Track `id` as a draft (the same every time).
static func build(id: String) -> TrackDraft:
	var d: TrackDraft
	match id:
		"marble_mile":
			d = marble_mile()
		"gearworks":
			d = gearworks()
		"skyhop_ridge":
			d = skyhop_ridge()
		"crate_yard":
			d = crate_yard()
		"dust_bowl":
			d = dust_bowl()
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


# --- circuits ------------------------------------------------------------------------------

static func marble_mile() -> TrackDraft:
	var verts := [Vector2(-250, -110), Vector2(110, -110), Vector2(250, 60), Vector2(90, 20), Vector2(-10, 120), Vector2(-70, 95),
		Vector2(-130, 125), Vector2(-260, 110)]
	var d := _circuit("marble_mile", "Marble Mile", verts, [45, 110, 16, 35, 35, 35, 35, 40], func(x: float, z: float) -> float:
		return 3.5 * sin(x / 85.0) * cos(z / 65.0) + 2.0 * sin((x - z) / 140.0))
	# A kart track's tyre walls all the way round, behind a strip of grass.
	for side in ["l", "r"]:
		d.set_default("barrier_" + side, "tyres")
		d.set_default("runoff_%s_m" % side, 3.0)
	_start(d, Vector2(-80, -110))
	d.set_boxes("auto")
	return d


static func gearworks() -> TrackDraft:
	var verts := [Vector2(-300, -150), Vector2(170, -150), Vector2(250, -30), Vector2(100, 20), Vector2(330, 240), Vector2(-120, 210),
		Vector2(-200, 90), Vector2(-310, 40)].map(func(v: Vector2) -> Vector2: return v * 0.9)
	var d := _circuit("gearworks", "Gearworks", verts, [40, 40, 25, 25, 60, 40, 30, 35], Callable(), "concrete")
	_start(d, Vector2(-160, -135))
	var t := d.track()
	var at := func(p: Vector2) -> float: return snappedf(float(t.project(Vector3(p.x, 0, p.y)).distance), 0.1)
	# The back straight (the long corner to the far end) 14 m wide for the loop.
	var back := PackedInt32Array()
	for i in d.points().size():
		var p: Array = d.points()[i].p
		if float(p[2]) > 150.0 and float(p[0]) > -90.0 and float(p[0]) < 200.0:
			back.append(i)
	d.set_attr(back, "width_l", 7.0)
	d.set_attr(back, "width_r", 7.0)
	t = d.track()
	d.add_stunt("boost_pad", at.call(Vector2(-60, -135)))
	d.add_stunt("item_row", at.call(Vector2(0, -135)))
	d.add_stunt("jump", at.call(Vector2(60, -135)), { "height_m": 1.2, "length_m": 8.0 })
	d.add_stunt("item_row", at.call(Vector2(140, 10)))
	d.add_stunt("wall_ride", at.call(Vector2(255, 120)), { "length_m": 110.0, "side": _outside(t, at.call(Vector2(290, 200))), "height_m": 6.0 })
	d.add_stunt("loop", at.call(Vector2(60, 199)), { "radius_m": 9.0, "width_m": 5.0 })
	d.add_stunt("item_row", at.call(Vector2(-170, 120)))
	d.add_stunt("boost_pad", at.call(Vector2(-275, -20)))
	d.set_boxes("placed")
	# The yard: containers along the straights, two cranes over the infield.
	for spec: Array in [[Vector2(-200, -175), 90.0], [Vector2(-160, -175), 90.0], [Vector2(-120, -175), 90.0], [Vector2(40, -175), 90.0],
			[Vector2(80, -175), 90.0], [Vector2(-50, 230), 90.0], [Vector2(-10, 230), 90.0], [Vector2(30, 230), 90.0], [Vector2(130, 228), 90.0],
			[Vector2(-30, 40), 0.0], [Vector2(-30, 56), 0.0], [Vector2(-60, 40), 0.0]]:
		var v: Vector2 = spec[0]
		d.add_prop({ "prop": "container", "p": [v.x, 0.0, v.y], "yaw_deg": float(spec[1]), "scale": 1.0 })
	for v: Vector2 in [Vector2(-100, 30), Vector2(60, 80)]:
		d.add_prop({ "prop": "crane", "p": [v.x, 0.0, v.y], "yaw_deg": 0.0, "scale": 1.0 })
	return d


static func skyhop_ridge() -> TrackDraft:
	var verts := [Vector2(-300, -136), Vector2(128, -170), Vector2(280, -51), Vector2(221, 68), Vector2(323, 170), Vector2(85, 221),
		Vector2(-51, 102), Vector2(-170, 212), Vector2(-323, 102)]
	var d := _circuit("skyhop_ridge", "Skyhop Ridge", verts, [60, 70, 40, 20, 50, 45, 30, 35, 50], func(x: float, z: float) -> float:
		return 0.03 * (z + 200.0) + 2.0 * sin(x / 70.0) * sin(z / 90.0))
	_start(d, Vector2(-120, -150))
	var t := d.track()
	var at := func(p: Vector2) -> float: return snappedf(float(t.project(Vector3(p.x, 0, p.y)).distance), 0.1)
	# `s` m along the side from corner `i` to the next.
	var leg := func(i: int, s: float) -> Vector2:
		var a: Vector2 = verts[i]
		return a + (verts[(i + 1) % verts.size()] - a).normalized() * s
	# Every jump has a straight to land on: the small one after the first hill's top, the middle
	# one on the far side, the big one (two pads before it) down the last straight.
	d.add_stunt("item_row", at.call(Vector2(-40, -158)))
	d.add_stunt("jump", at.call(leg.call(5, 40.0)), { "height_m": 0.8, "length_m": 6.0 })
	d.add_stunt("wall_ride", at.call(Vector2(275, 110)), { "length_m": 90.0, "side": _outside(t, at.call(Vector2(320, 175))), "height_m": 5.0 })
	d.add_stunt("item_row", at.call(Vector2(200, 205)))
	d.add_stunt("jump", at.call(leg.call(7, 45.0)), { "height_m": 1.2, "length_m": 8.0 })
	d.add_stunt("boost_pad", at.call(leg.call(8, 40.0)))
	d.add_stunt("boost_pad", at.call(leg.call(8, 55.0)))
	d.add_stunt("jump", at.call(leg.call(8, 75.0)), { "height_m": 1.8, "length_m": 10.0 })
	d.add_stunt("item_row", at.call(leg.call(2, 60.0)))
	d.set_boxes("placed")
	return d


## A circuit through `verts` with corners of `radii`: flat ground of `ground_surface` without a
## `hills` function (height at x, z), else terrain shaped by it; grid of 12, three sectors.
static func _circuit(id: String, track_name: String, verts: Array, radii: Array, hills: Callable, ground_surface := "grass") -> TrackDraft:
	var d := TrackDraft.blank(track_name)
	d.id = id
	d.info.author = "nOSS contributors"
	var pts := TrackTemplates.rounded_polygon(verts, radii, 40.0)
	if hills.is_valid():
		var box := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
		for p: Vector3 in pts:
			box = box.expand(Vector2(p.x, p.z))
		d.terrain = TerrainData.around(box, 150.0)
		var size: Vector2i = d.terrain.field.get_size()
		var origin: Vector2 = d.terrain.origin()
		var heights := PackedFloat32Array()
		heights.resize(size.x * size.y)
		for z in size.y:
			for x in size.x:
				heights[z * size.x + x] = snappedf(hills.call(origin.x + x, origin.y + z), TerrainData.HEIGHT_STEP)
		d.terrain.field.set_base(heights)
	else:
		d.terrain = null
		d.layout.erase("ground")
		d.layout.ground = { "flat_y": -0.03, "surface": ground_surface }
	d.layout.road.points = pts.map(func(p: Vector3) -> Dictionary: return { "p": TrackDraft._vec(p) })
	d._track = null
	d.set_race("grid/slots", 12)
	return d


## The start line at the road nearest `p`, the sectors at thirds of a lap from it.
static func _start(d: TrackDraft, p: Vector2) -> void:
	var t := d.track()
	var start := snappedf(float(t.project(Vector3(p.x, 0, p.y)).distance), 0.1)
	d.set_race("start_m", start)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])


## The outside of the corner at `at_m` (where a wall-ride goes).
static func _outside(t: TrackData, at_m: float) -> String:
	return "left" if t.curvature[t.index_at(at_m)] < 0.0 else "right"


# --- arenas --------------------------------------------------------------------------------

static func crate_yard() -> TrackDraft:
	var d := _arena("crate_yard", "Crate Yard", TrackTemplates.rounded_rect(50.0, 40.0, 10.0, 25.0, 45.0), "concrete", "tyres")
	d.add_stunt("jump", Vector3(0, 0, -30), { "yaw_deg": 90.0, "width_m": 5.0, "height_m": 1.0, "length_m": 7.0 })
	d.add_stunt("jump", Vector3(0, 0, 30), { "yaw_deg": -90.0, "width_m": 5.0, "height_m": 1.0, "length_m": 7.0 })
	d.add_stunt("boost_pad", Vector3(-38, 0, 0), { "yaw_deg": 0.0 })
	d.add_stunt("boost_pad", Vector3(38, 0, 0), { "yaw_deg": 180.0 })
	# Crates in twos and threes, tyre stacks at the cut corners.
	for v: Vector2 in [Vector2(-14, -9), Vector2(-12, -9), Vector2(14, 9), Vector2(12, 9), Vector2(12, 11), Vector2(-14, 12), Vector2(14, -12),
			Vector2(-38, -22), Vector2(38, 22), Vector2(-36, 24), Vector2(36, -24)]:
		d.add_prop({ "prop": "crate", "p": [v.x, 0.0, v.y], "yaw_deg": 0.0, "scale": 1.0 })
	for v: Vector2 in [Vector2(-44, -34), Vector2(44, -34), Vector2(-44, 34), Vector2(44, 34)]:
		for k in 3:
			d.add_prop({ "prop": "tyre_stack", "p": [v.x - signf(v.x) * k * 0.8, 0.0, v.y], "yaw_deg": 0.0, "scale": 1.0 })
	return d


static func dust_bowl() -> TrackDraft:
	var pts := []
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(Vector3(snappedf(60.0 * cos(a), 0.01), 0.0, snappedf(60.0 * sin(a), 0.01)))
	var d := _arena("dust_bowl", "Dust Bowl", pts, "dirt", "tyres")
	# Four jumps facing each other round the middle: up toward it from each side.
	for k in 4:
		var a := TAU * k / 4.0
		var at := Vector3(cos(a), 0, sin(a)) * 11.0
		d.add_stunt("jump", at, { "yaw_deg": snappedf(rad_to_deg(atan2(-at.x, -at.z)), 0.1), "width_m": 6.0, "height_m": 1.2, "length_m": 8.0 })
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		d.add_box_cluster(Vector3(snappedf(28.0 * cos(a), 0.1), 0.0, snappedf(28.0 * sin(a), 0.1)))
	d.add_box_cluster(Vector3(0, 0, -45))
	return d


static func _arena(id: String, track_name: String, outline: Array, floor_surface: String, wall: String) -> TrackDraft:
	var d := TrackDraft.blank(track_name)
	d.id = id
	d.info.author = "nOSS contributors"
	d.terrain = null
	d.layout.erase("ground")
	d.layout.ground = { "flat_y": -0.03, "surface": "grass" }
	d.set_type("arena")
	d.layout.road.points = outline.map(func(p: Vector3) -> Dictionary: return { "p": TrackDraft._vec(p) })
	d._track = null
	d.set_arena("floor", floor_surface)
	d.set_arena("wall", wall)
	return d
