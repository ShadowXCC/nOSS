extends Node
## Writes content/tracks/piedmont_road_course/: Piedmont Road Course (D211), the infield road
## course at Piedmont Speedway (the Charlotte "Roval") under a name of its own, made with the track
## editor's own commands (TrackDraft).
##
## It runs the oval counter-clockwise as Piedmont Speedway does, its banked sections exactly the
## oval's (the same control points: banking, apron, SAFER wall), but leaves the frontstretch for
## the infield before turn 1 and comes back up onto the banking in turn 1. Chicanes on the
## backstretch and at the end of turn 4. The infield is flat, 13 m wide, with curbs and grass
## run-off. The ground is the oval's (the same venue). Pit road is the oval's, its exit through the
## infield. The oval's banking the course leaves and the straights its chicanes cut off are scenery
## roads (D212). From tools/data/piedmont.json (OpenStreetMap, ODbL; USGS ground): the infield is routed
## through the map's road course ways from LEAVE_NODE to JOIN_NODE, the chicanes are its ways.
##   tools/godot.sh --headless res://tools/make_piedmont_road_course.tscn [-- --out=<folder>]

const G := preload("res://tools/track_gen_util.gd")
const Oval := preload("res://tools/make_piedmont_speedway.gd")
const OUT := "res://content/tracks/piedmont_road_course"
const DATA := "res://tools/data/piedmont.json"
const CREATED := "2026-10-23"
const SOURCE := "OpenStreetMap ways 402168711, 116107372, 402168714, 402168718, 116107359, 585912895, 676112675, 918050113, 923003592 and the oval's, USGS NED 1/3 arc-second"
## Where the course leaves the oval's frontstretch and joins it again (OSM nodes on way 402168711).
const LEAVE_NODE := 9668619993
const JOIN_NODE := 4066108101
const OVAL_WAY := 402168711
const CHICANES := [676112675, 918050113]
const PIT_EXIT_WAY := 923003592
## The node where the pit lane turns off for the infield (on the oval's pit lane).
const PIT_TURN_NODE := 8568158711
const INFIELD_HALF_M := 6.5
const INFIELD_RUNOFF_M := 12.0
## The map's infield lines: resampled and smoothed (Gaussian sigma), m.
const RESAMPLE_M := 3.0
const SMOOTH_M := 4.0
## Control points: RADIUS_SHARE of the tightest radius just ahead apart, within these (m).
const SPACING_MIN_M := 6.0
const SPACING_MAX_M := 30.0
const RADIUS_SHARE := 0.3
## Oval control points this close to where the course leaves or joins it (m along) are left out,
## and the infield's first and last JOIN_SKIP_M: the spline joins them.
const OVAL_GAP_M := 25.0
const JOIN_SKIP_M := 30.0
## Near where it joins and leaves the oval the course runs low on the banking, MERGE_LOW_M in from
## its centre (its edges still the oval's), easing to the middle over MERGE_M: it climbs the
## banking gently instead of meeting its middle, 3.6 m up.
const MERGE_M := 160.0
const MERGE_LOW_M := 7.5
const PIT_TAPER_M := 100.0
## Infield stretches within CLOSE_M of another part of the course (the way out and the way back run
## side by side): narrowed on that side to leave CLOSE_GAP_M between, a concrete wall between.
const CLOSE_M := 30.0
const CLOSE_GAP_M := 3.0
const NARROWEST_HALF_M := 4.5

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
		out, t.length / 1000.0, d.points().size(), corners(t), t.pit.track.length if t.pit else 0.0, t.pit.boxes.size() if t.pit else 0,
		d.layout.props.items.size(), t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


## Piedmont Road Course as a draft (the same every time).
static func build() -> TrackDraft:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var oval := Oval.build()
	var ot := oval.track()
	var d := course(oval, data)
	var t := d.track()
	# The race: the oval's start line, three sectors, twenty cars, rolling from further back.
	var start_p := ot.point_at(ot.start_m)
	var start := snappedf(float(t.project(start_p).distance), 0.1)
	d.set_race("start_m", start)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])
	d.set_race("grid/slots", Oval.GRID_SLOTS)
	d.set_race("rolling_back_m", Oval.GRID_ROLL_M)
	_pits(d, d.track(), data)
	# The rest of the venue (D212): the oval's banking the course leaves, and its straights the
	# chicanes cut off.
	for road: Dictionary in _unused_oval(oval, d):
		d.add_road(road)
	d.set_env("time", "night")
	d.set_env("floodlit", true)
	for rule: Array in [["start", "rolling"], ["draft", true], ["fuel_x", 5], ["tyre_x", 5]]:
		d.set_rule(rule[0], rule[1])
	_props(d, oval)
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


## The course's road on `oval`'s ground: no race, pit road or scenery yet. Meta "parts": its
## chicanes' and the infield's points, [{kind, from, to (indices, inclusive), oval_m (a chicane's
## start on the oval)}]; "oval": where on the oval it leaves and joins it and the chicanes start
## and end, m.
static func course(oval: TrackDraft, data: Dictionary) -> TrackDraft:
	var ot := oval.track()
	var d := TrackDraft.blank("Piedmont Road Course")
	d.id = "piedmont_road_course"
	d.info.author = "nOSS contributors"
	d.info.license = Oval.LICENSE
	d.info.attributions = Oval.ATTRIBUTIONS.duplicate()
	d.terrain = oval.terrain # the same venue, the same ground
	var nodes := _nodes(data)
	var leave_m := float(G.project(oval, ot, nodes[LEAVE_NODE]).distance)
	var join_m := float(G.project(oval, ot, nodes[JOIN_NODE]).distance)
	# The chicanes: where on the oval each starts and ends, and their own points.
	var chicanes := []
	for id: int in CHICANES:
		var line := _way_line(data, id)
		chicanes.append({ "from": float(G.project(oval, ot, line[0]).distance), "to": float(G.project(oval, ot, line[line.size() - 1]).distance),
			"line": line })
	# Round from where the course comes back onto the oval to where it leaves it: the oval's own
	# points (copied whole: banking, heights, apron, wall), a chicane's in place of the oval's where
	# it has one; then the infield back to the start.
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
		if m < OVAL_GAP_M or m > span - OVAL_GAP_M:
			continue
		var chicane := _chicane_at(chicanes, fposmod(join_m + m, ot.length), ot.length)
		if not chicane.is_empty():
			if not placed.has(chicane.from):
				placed[chicane.from] = true
				var first := points.size()
				points.append_array(_chicane_points(chicane.line))
				parts.append({ "kind": "chicane", "from": first, "to": points.size() - 1, "oval_m": chicane.from })
			continue
		var low := MERGE_LOW_M * maxf(1.0 - smoothstep(0.0, MERGE_M, m), 1.0 - smoothstep(0.0, MERGE_M, span - m))
		points.append(_oval_point(oval, i, low))
	var infield := points.size()
	points.append_array(_infield_points(_route(data), JOIN_SKIP_M))
	parts.append({ "kind": "infield", "from": infield, "to": points.size() - 1 })
	d.layout.road.points = points
	d.layout.road.defaults.merge({ "width_l": INFIELD_HALF_M, "width_r": INFIELD_HALF_M, "height": "ground",
		"runoff_l_m": INFIELD_RUNOFF_M, "runoff_r_m": INFIELD_RUNOFF_M }, true)
	d._track = null
	_side_by_side(d)
	d._track = null
	d.set_meta(&"parts", parts)
	d.set_meta(&"oval", { "leave_m": leave_m, "join_m": join_m, "chicanes": chicanes.map(func(c: Dictionary) -> Array: return [c.from, c.to]) })
	return d


## Piedmont Speedway's scenery roads (D212): this course's infield and chicanes, each with the
## course's two points either side of it on the banking (fitted away: the road comes off the
## oval as the course does).
static func infield_roads(oval: TrackDraft) -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var d := course(oval, data)
	var ot := oval.track()
	var points: Array = d.points()
	var n := points.size()
	var out := []
	for part: Dictionary in d.get_meta(&"parts"):
		var road_points := []
		for i in range(int(part.from) - 2, int(part.to) + 3):
			var p: Dictionary = (points[posmod(i, n)] as Dictionary).duplicate(true)
			road_points.append(_scenery_end(p) if i < int(part.from) or i > int(part.to) else p)
		var name := "Road course infield"
		if part.kind == "chicane":
			name = "Backstretch chicane" if _on_backstretch(ot, float(part.oval_m)) else "Turn 4 chicane"
		out.append({ "name": name, "defaults": (d.layout.road.defaults as Dictionary).duplicate(true), "points": road_points })
	return out


## An oval point of the course's as the end of a scenery road on the oval: where it is, its
## banking and widths; no apron, curbs or walls (the oval has its own).
static func _scenery_end(p: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["p", "height", "bank_deg", "width_l", "width_r"]:
		if p.has(key):
			out[key] = p[key]
	out.merge({ "apron_l_m": 0.0, "apron_r_m": 0.0, "curb_l": "off", "curb_r": "off", "barrier_l": "none", "barrier_r": "none" }, true)
	return out


## True if oval distance `m` is on the backstretch: round the middle of the lap from the line.
static func _on_backstretch(ot: TrackData, m: float) -> bool:
	var along := fposmod(m - ot.start_m, ot.length) / ot.length
	return along > 0.3 and along < 0.7


## The oval this course leaves (D212): its banking from where the course leaves the frontstretch
## to where it comes back in turn 1, and the straights its chicanes cut off, as scenery roads:
## the oval's own points (banking, apron, wall), UNUSED_EXTRA_M on into the course each end
## (fitted away).
const UNUSED_EXTRA_M := 60.0


static func _unused_oval(oval: TrackDraft, d: TrackDraft) -> Array:
	var ot := oval.track()
	var at: Dictionary = d.get_meta(&"oval")
	var spans := [[float(at.leave_m) - OVAL_GAP_M, float(at.join_m) + OVAL_GAP_M, "Oval turn 1"]]
	for c: Array in at.chicanes:
		spans.append([float(c[0]) - OVAL_GAP_M, float(c[1]) + OVAL_GAP_M, "Oval backstretch" if _on_backstretch(ot, float(c[0])) else "Oval turn 4"])
	var out := []
	var oval_points: Array = oval.points()
	for span: Array in spans:
		var from := float(span[0]) - UNUSED_EXTRA_M
		var length := fposmod(float(span[1]) + UNUSED_EXTRA_M - from, ot.length)
		var picked := []
		for i in oval_points.size():
			var m := fposmod(ot.distances[ot.seg_first[i]] - from, ot.length)
			if m <= length:
				picked.append([m, i])
		picked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		out.append({ "name": span[2], "defaults": (oval.layout.road.defaults as Dictionary).duplicate(true),
			"points": picked.map(func(e: Array) -> Dictionary: return (oval_points[e[1]] as Dictionary).duplicate(true)) })
	return out


## Infield points with another part of the course close beside them: that side narrowed so the
## two keep CLOSE_GAP_M apart, a short concrete run-off and a wall (on the right-hand one's side).
static func _side_by_side(d: TrackDraft) -> void:
	var t := d.track()
	var n := t.samples.size()
	for i in d.points().size():
		var p: Dictionary = d.points()[i]
		if p.has("bank_deg"):
			continue # the oval's own
		var k := t.seg_first[i]
		var here := t.samples[k]
		var near := INF
		var side := 0.0
		for j in t.samples_near(here, CLOSE_M):
			var along := absf(t.distances[j] - t.distances[k])
			if minf(along, t.length - along) < 100.0:
				continue
			var gap := Vector2(t.samples[j].x - here.x, t.samples[j].z - here.z).length()
			if gap < near:
				near = gap
				side = signf((t.samples[j] - here).dot(t.lefts[k]))
		if near >= CLOSE_M:
			continue
		var s := "l" if side > 0.0 else "r"
		var half := clampf((near - CLOSE_GAP_M) / 2.0, NARROWEST_HALF_M, INFIELD_HALF_M)
		p["width_" + s] = snappedf(half, 0.1)
		p["runoff_" + s] = "concrete"
		p["runoff_%s_m" % s] = 0.5
		p["barrier_" + s] = "concrete" if s == "r" else "none"


## Every node of the map's ways: id -> (x, z).
static func _nodes(data: Dictionary) -> Dictionary:
	var out := {}
	for w: Dictionary in data.raceways:
		for k in (w.nodes as Array).size():
			out[int(w.nodes[k])] = Vector2(w.points[k][0], w.points[k][1])
	return out


static func _way_line(data: Dictionary, id: int) -> PackedVector2Array:
	for w: Dictionary in data.raceways:
		if int(w.id) == id:
			var out := PackedVector2Array()
			for p: Array in w.points:
				out.append(Vector2(p[0], p[1]))
			return out
	return PackedVector2Array()


## The infield, from LEAVE_NODE to JOIN_NODE: the shortest way through the map's road course
## (one-way ways driven their way), not along the oval.
static func _route(data: Dictionary) -> PackedVector2Array:
	var nodes := _nodes(data)
	var links := {} # node -> [[node, metres]]
	for w: Dictionary in data.raceways:
		var name := String(w.name)
		if int(w.id) == OVAL_WAY or not (name.contains("Roval") or name.begins_with("Charlotte Motor Speedway")):
			continue
		var ns: Array = w.nodes
		for k in ns.size() - 1:
			var a := int(ns[k])
			var b := int(ns[k + 1])
			var len := (nodes[a] as Vector2).distance_to(nodes[b])
			if not links.has(a):
				links[a] = []
			links[a].append([b, len])
			if String(w.oneway) != "yes":
				if not links.has(b):
					links[b] = []
				links[b].append([a, len])
	var dist := { LEAVE_NODE: 0.0 }
	var prev := {}
	var open := [LEAVE_NODE]
	while not open.is_empty():
		var best := 0
		for k in open.size():
			if float(dist[open[k]]) < float(dist[open[best]]):
				best = k
		var n: int = open[best]
		open.remove_at(best)
		if n == JOIN_NODE:
			break
		for link: Array in links.get(n, []):
			var m: int = link[0]
			var c := float(dist[n]) + float(link[1])
			if c < float(dist.get(m, INF)):
				if not dist.has(m):
					open.append(m)
				dist[m] = c
				prev[m] = n
	var path := PackedVector2Array([nodes[JOIN_NODE]])
	var n: int = JOIN_NODE
	while n != LEAVE_NODE:
		n = prev[n]
		path.append(nodes[n])
	path.reverse()
	return path


## An open line's control points: resampled, smoothed, picked closer in the corners, its first
## and last `skip` m left out (where it joins the oval).
static func _infield_points(line: PackedVector2Array, skip: float) -> Array:
	var even := _resample_open(line, RESAMPLE_M)
	var smooth := _gauss_open(even, SMOOTH_M, RESAMPLE_M)
	var n := smooth.size()
	var out := []
	var i := int(skip / RESAMPLE_M)
	var last := n - 1 - int(skip / RESAMPLE_M)
	while i <= last:
		out.append({ "p": [snappedf(smooth[i].x, 0.01), 0.0, snappedf(smooth[i].y, 0.01)] })
		var r := INF
		for o in int(SPACING_MAX_M / RESAMPLE_M):
			var k := mini(i + o, n - 2)
			r = minf(r, G.radius(smooth[maxi(k - 2, 0)], smooth[k], smooth[mini(k + 2, n - 1)]))
		i += maxi(1, roundi(clampf(r * RADIUS_SHARE, SPACING_MIN_M, SPACING_MAX_M) / RESAMPLE_M))
	return out


## A chicane's points (its ends left out: the spline comes off the oval to them).
static func _chicane_points(line: PackedVector2Array) -> Array:
	var out := _infield_points(line, 18.0)
	for p: Dictionary in out:
		p.width_l = INFIELD_HALF_M
		p.width_r = INFIELD_HALF_M
	return out


## The chicane round oval distance `m`, with a little room either side, or {}.
static func _chicane_at(chicanes: Array, m: float, length: float) -> Dictionary:
	for c: Dictionary in chicanes:
		if fposmod(m - (float(c.from) - OVAL_GAP_M), length) <= fposmod(float(c.to) + OVAL_GAP_M - (float(c.from) - OVAL_GAP_M), length):
			return c
	return {}


## Oval control point `i` as this course's: its own attributes and the oval's defaults it took,
## moved `low` m down the banking (on the oval's surface, its edges where the oval's are).
static func _oval_point(oval: TrackDraft, i: int, low := 0.0) -> Dictionary:
	var p: Dictionary = (oval.points()[i] as Dictionary).duplicate(true)
	var defaults: Dictionary = oval.layout.road.defaults
	for key: String in ["width_l", "width_r", "height", "curb_l", "curb_r", "apron_l_m", "apron_l_deg", "runoff_l", "runoff_l_m",
			"barrier_l", "runoff_r", "runoff_r_m", "barrier_r"]:
		if not p.has(key) and defaults.has(key):
			p[key] = defaults[key]
	if low > 0.01:
		var ot := oval.track()
		var at := ot.transform_at(ot.distances[ot.seg_first[i]], low).origin
		p.p = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
		p.width_l = snappedf(float(p.width_l) - low, 0.01)
		p.width_r = snappedf(float(p.width_r) + low, 0.01)
	return p


static func _resample_open(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([line[0]])
	var carry := 0.0
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var seg := a.distance_to(b)
		var s := step - carry
		while s <= seg:
			out.append(a.lerp(b, s / seg))
			s += step
		carry = seg - (s - step)
	out.append(line[line.size() - 1])
	return out


static func _gauss_open(line: PackedVector2Array, sigma: float, step: float) -> PackedVector2Array:
	var n := line.size()
	var reach := ceili(3.0 * sigma / step)
	var out := PackedVector2Array()
	for i in n:
		var sum := Vector2.ZERO
		var wsum := 0.0
		for o in range(-reach, reach + 1):
			var k := clampi(i + o, 0, n - 1)
			var w := exp(-0.5 * pow(o * step / sigma, 2.0))
			sum += line[k] * w
			wsum += w
		out.append(sum / wsum)
	return out


## Pit road: the oval's, turning off through the infield to join this course there (its exit way).
static func _pits(d: TrackDraft, t: TrackData, data: Dictionary) -> void:
	var nodes := _nodes(data)
	var lane := PackedVector2Array()
	var turn: Vector2 = nodes[PIT_TURN_NODE]
	for p: Array in data.pit_lane:
		lane.append(Vector2(p[0], p[1]))
		if lane[lane.size() - 1].distance_to(turn) < 0.5:
			break
	var exit_line := _way_line(data, PIT_EXIT_WAY)
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
	var free := Vector2(from + Oval.PIT_TAPER_M + 15.0, to - PIT_TAPER_M - 15.0)
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


## The oval's scenery outside its wall (light towers, grandstands, trees); none in the infield,
## which the course has for its own.
static func _props(d: TrackDraft, oval: TrackDraft) -> void:
	for item: Dictionary in oval.layout.props.items:
		if item.prop in ["light_tower", "grandstand", "crowd"]:
			d.add_prop(item)
	for g: Dictionary in oval.layout.props.scatter:
		d.set_scatter_live(String(g.prop), g.xf)


## Corners: bends tighter than CORNER_R_M one way (pieces under CORNER_JOIN_M apart are one),
## turning CORNER_DEG or more in all; a chicane's two or three turns each count.
const CORNER_R_M := 200.0
const CORNER_JOIN_M := 30.0
const CORNER_DEG := 25.0


static func corners(t: TrackData) -> int:
	var n := t.samples.size()
	# Start where the road runs straight, so no bend is cut in two.
	var first := 0
	for i in n:
		if absf(t.curvature[i]) < 1.0 / CORNER_R_M:
			first = i
			break
	var count := 0
	var turn := 0.0 # this bend's turning so far, rad (signed)
	var gap := INF # m since the bend last turned
	for s in n + 1:
		var i := (first + s) % n
		var k := t.curvature[i]
		var step := t.samples[i].distance_to(t.samples[(i + 1) % n])
		if absf(k) >= 1.0 / CORNER_R_M and (turn == 0.0 or signf(k) == signf(turn) and gap < CORNER_JOIN_M):
			turn += k * step
			gap = 0.0
			continue
		gap += step
		if turn != 0.0 and (gap >= CORNER_JOIN_M or (absf(k) >= 1.0 / CORNER_R_M and signf(k) != signf(turn))):
			if absf(rad_to_deg(turn)) >= CORNER_DEG:
				count += 1
			turn = k * step if absf(k) >= 1.0 / CORNER_R_M else 0.0
			gap = 0.0 if turn != 0.0 else INF
	return count
