extends Node
## Writes content/tracks/halifax_road_course/: Halifax Road Course (D231), the sports-car road
## course through Halifax Speedway's infield (the Daytona road course) under a name of its own,
## made with the track editor's own commands (TrackDraft).
##
## It runs the oval counter-clockwise as Halifax Speedway does, its banked sections exactly the
## oval's (the same control points: banking, apron, SAFER wall), but leaves the banking in turn 1
## for the infield (the International Horseshoe, the Dogleg, the West Horseshoe) and comes back up
## onto it in turn 2; down the backstretch the Le Mans chicane. Its infield is flat, with curbs and
## grass run-off, as Piedmont Road Course's is (the infield helpers are that generator's). The
## ground and Lake Lloyd are the oval's (the same venue). Pit road is the oval's, its exit through
## the infield. The oval's turn 1 and the backstretch its chicane cuts off are scenery roads
## (D212). From tools/data/halifax.json (OpenStreetMap, ODbL; USGS ground): the infield is the
## map's ROUTE_WAYS, the chicane its way.
##   tools/godot.sh --headless res://tools/make_halifax_road_course.tscn [-- --out=<folder>]

const G := preload("res://tools/track_gen_util.gd")
const Oval := preload("res://tools/make_halifax_speedway.gd")
## Piedmont Road Course's generator: its infield, chicane and merging helpers, and their tuning.
const RC := preload("res://tools/make_piedmont_road_course.gd")
const OUT := "res://content/tracks/halifax_road_course"
const DATA := "res://tools/data/halifax.json"
const CREATED := "2026-10-28"
const SOURCE := "OpenStreetMap ways 352696267, 352104911, 352104914, 1315971773, 352070313, 352104912, 352070310, 352070308, 198466856, 198465570 and the oval's, USGS NED 1/3 arc-second"
## Where the course leaves the oval in turn 1 and joins it again in turn 2 (OSM nodes), the
## infield between them (the map's ways in driving order), and the backstretch's Le Mans chicane.
const LEAVE_NODE := 101134860
const JOIN_NODE := 101134774
const ROUTE_WAYS := [352696267, 352104911, 352104914, 1315971773, 352070313, 352104912, 352070310, 352070308]
const CHICANES := [198466856]
## Pit road: the oval's to PIT_TURN_NODE, then the road course's pit lane into the infield.
const PIT_TURN_NODE := 2085914724
const PIT_EXIT_WAY := 198465570

var opts := { "out": OUT }


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_write.call_deferred()


func _write() -> void:
	var t0 := Time.get_ticks_msec()
	var d := build()
	var t := d.track()
	var found := TrackValidator.check(d)
	for p: Dictionary in found:
		print("  %s: %s%s" % [p.level, p.text, " (%.0f, %.0f)" % [p.point.x, p.point.z] if p.point is Vector3 else ""])
	if not TrackValidator.errors(found).is_empty():
		print("FAIL: validation errors")
		get_tree().quit(1)
		return
	var out := String(opts.out)
	var err := TrackWriter.write_folder(out, d.manifest_info().merged({ "created": CREATED, "tags": ["real-world"], "source": SOURCE }, true), d.files())
	if err:
		print("FAIL: " + err)
		get_tree().quit(1)
		return
	print("Wrote %s: %.3f km, %d points, %d corners, pit road %.0f m with %d boxes, %d props, layout %s, %d ms" % [
		out, t.length / 1000.0, d.points().size(), RC.corners(t), t.pit.track.length if t.pit else 0.0, t.pit.boxes.size() if t.pit else 0,
		d.layout.props.items.size(), t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


## Halifax Road Course as a draft (the same every time).
static func build() -> TrackDraft:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var oval := Oval.build()
	var ot := oval.track()
	var d := course(oval, data)
	var t := d.track()
	# The race: the oval's start line, three sectors, twenty cars, rolling from further back.
	var start := snappedf(float(t.project(ot.point_at(ot.start_m)).distance), 0.1)
	d.set_race("start_m", start)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])
	d.set_race("grid/slots", Oval.GRID_SLOTS)
	d.set_race("rolling_back_m", Oval.GRID_ROLL_M)
	_pits(d, d.track(), data)
	# The rest of the venue (D212): the oval's banking the course leaves and the backstretch its
	# chicane cuts off; and its lake.
	for road: Dictionary in RC._unused_oval(oval, d):
		d.add_road(road)
	d.layout.water = (oval.layout.water as Array).duplicate(true)
	d._track = null
	d.set_env("time", "night")
	d.set_env("floodlit", true)
	for rule: Array in [["start", "rolling"], ["draft", true], ["fuel_x", 5], ["tyre_x", 2]]:
		d.set_rule(rule[0], rule[1])
	_props(d, oval)
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


## The course's road on `oval`'s ground: no race, pit road or scenery yet. Meta "parts" and
## "oval" as Piedmont Road Course's (RC.course).
static func course(oval: TrackDraft, data: Dictionary) -> TrackDraft:
	var ot := oval.track()
	var d := TrackDraft.blank("Halifax Road Course")
	d.id = "halifax_road_course"
	d.info.author = "nOSS contributors"
	d.info.license = Oval.LICENSE
	d.info.attributions = Oval.ATTRIBUTIONS.duplicate()
	d.terrain = oval.terrain # the same venue, the same ground
	var nodes := RC._nodes(data)
	var leave_m := float(G.project(oval, ot, nodes[LEAVE_NODE]).distance)
	var join_m := float(G.project(oval, ot, nodes[JOIN_NODE]).distance)
	var chicanes := []
	for id: int in CHICANES:
		var line := RC._way_line(data, id)
		chicanes.append({ "from": float(G.project(oval, ot, line[0]).distance), "to": float(G.project(oval, ot, line[line.size() - 1]).distance),
			"line": line })
	# Round from where the course comes back onto the oval to where it leaves it: the oval's own
	# points, the chicane's in place of the oval's where it has one; then the infield.
	var points := []
	var oval_points: Array = oval.points()
	var span := fposmod(leave_m - join_m, ot.length)
	var order := range(oval_points.size())
	var at_m := func(i: int) -> float: return fposmod(ot.distances[ot.seg_first[i]] - join_m, ot.length)
	order.sort_custom(func(a: int, b: int) -> bool: return at_m.call(a) < at_m.call(b))
	var placed := {}
	var parts := []
	for i: int in order:
		var m: float = at_m.call(i)
		if m < RC.OVAL_GAP_M or m > span - RC.OVAL_GAP_M:
			continue
		var chicane := RC._chicane_at(chicanes, fposmod(join_m + m, ot.length), ot.length)
		if not chicane.is_empty():
			if not placed.has(chicane.from):
				placed[chicane.from] = true
				var first := points.size()
				points.append_array(RC._chicane_points(chicane.line))
				parts.append({ "kind": "chicane", "from": first, "to": points.size() - 1, "oval_m": chicane.from })
			continue
		var low := RC.MERGE_LOW_M * maxf(1.0 - smoothstep(0.0, RC.MERGE_M, m), 1.0 - smoothstep(0.0, RC.MERGE_M, span - m))
		points.append(RC._oval_point(oval, i, low))
	var infield := points.size()
	points.append_array(RC._infield_points(_route(data), RC.JOIN_SKIP_M))
	parts.append({ "kind": "infield", "from": infield, "to": points.size() - 1 })
	d.layout.road.points = points
	d.layout.road.defaults.merge({ "width_l": RC.INFIELD_HALF_M, "width_r": RC.INFIELD_HALF_M, "height": "ground",
		"runoff_l_m": RC.INFIELD_RUNOFF_M, "runoff_r_m": RC.INFIELD_RUNOFF_M }, true)
	d._track = null
	RC._side_by_side(d)
	d._track = null
	d.set_meta(&"parts", parts)
	d.set_meta(&"oval", { "leave_m": leave_m, "join_m": join_m, "chicanes": chicanes.map(func(c: Dictionary) -> Array: return [c.from, c.to]) })
	return d


## Halifax Speedway's scenery roads (D212): this course's infield and chicane, each with the
## course's two points either side of it on the banking (fitted away).
static func infield_roads(oval: TrackDraft) -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var d := course(oval, data)
	var points: Array = d.points()
	var n := points.size()
	var out := []
	for part: Dictionary in d.get_meta(&"parts"):
		var road_points := []
		for i in range(int(part.from) - 2, int(part.to) + 3):
			var p: Dictionary = (points[posmod(i, n)] as Dictionary).duplicate(true)
			road_points.append(RC._scenery_end(p) if i < int(part.from) or i > int(part.to) else p)
		out.append({ "name": "Le Mans chicane" if part.kind == "chicane" else "Road course infield",
			"defaults": (d.layout.road.defaults as Dictionary).duplicate(true), "points": road_points })
	return out


## The infield, from LEAVE_NODE to JOIN_NODE along ROUTE_WAYS (the full sports-car course: the
## map also has shorter ways through it).
static func _route(data: Dictionary) -> PackedVector2Array:
	var path := PackedVector2Array()
	for id: int in ROUTE_WAYS:
		var line := RC._way_line(data, id)
		if not path.is_empty():
			if path[path.size() - 1].distance_to(line[0]) > 1.0:
				push_error("Halifax Road Course: way %d doesn't join the one before" % id)
			line = line.slice(1)
		path.append_array(line)
	return path


## Pit road: the oval's, turning off through the infield to join this course there (its exit way).
static func _pits(d: TrackDraft, t: TrackData, data: Dictionary) -> void:
	var nodes := RC._nodes(data)
	var lane := PackedVector2Array()
	var turn: Vector2 = nodes[PIT_TURN_NODE]
	for p: Array in data.pit_lane:
		lane.append(Vector2(p[0], p[1]))
		if lane[lane.size() - 1].distance_to(turn) < 0.5:
			break
	var exit_line := RC._way_line(data, PIT_EXIT_WAY)
	for k in range(1, exit_line.size()):
		lane.append(exit_line[k])
	var along := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	for p in lane:
		var proj := G.project(d, t, p)
		along.append(float(proj.distance))
		var k := t.index_at(float(proj.distance))
		lateral.append(maxf(float(proj.lateral), t.half_l[k] + t.apron(k, 1.0) + Oval.PIT_CLEAR_M + Oval.PIT_HALF_M))
	var from := snappedf(along[0], 0.1)
	var to := snappedf(along[along.size() - 1], 0.1)
	var points := []
	var free := Vector2(from + Oval.PIT_TAPER_M + 15.0, to - RC.PIT_TAPER_M - 15.0)
	for j in along.size():
		if G.within(t, along[j], free):
			var at := t.transform_at(along[j], lateral[j]).origin
			points.append({ "p": [snappedf(at.x, 0.01), 0.0, snappedf(at.z, 0.01)] })
	d.add_pit(from, to, "left")
	d.set_pit("taper_m", Oval.PIT_TAPER_M)
	d.set_pit("width_m", Oval.PIT_HALF_M * 2.0)
	d.set_pit("speed_kmh", Oval.PIT_SPEED_KMH)
	d.set_pit("boxes", Oval.GRID_SLOTS)
	d.set_pit("box_m", Oval.PIT_BOX_M)
	d.set_pit("points", points)


## The oval's scenery: outside its wall (light towers, stadium stands, trees) and in the infield
## what keeps clear of this course's roads (they're the oval's scenery roads: tents, campers,
## billboards).
static func _props(d: TrackDraft, oval: TrackDraft) -> void:
	for item: Dictionary in oval.layout.props.items:
		if item.prop in ["light_tower", "stadium_stand", "crowd", "tent", "billboard"]:
			d.add_prop(item)
	for g: Dictionary in oval.layout.props.scatter:
		d.set_scatter_live(String(g.prop), g.xf)
