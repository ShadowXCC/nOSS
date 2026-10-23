class_name TrackData
extends RefCounted
## A track's road and race setup, sampled for driving (docs/TRACK_EDITOR.md §5): noss.track/1,
## or noss.track/0 upgraded on load (TrackFormat). The road is a closed centripetal Catmull-Rom
## through its control points, sampled every ~2 m. Each sample carries its frame (banked),
## widths to the left and right edge, curbs per side, surface, run-off and barriers.
## Heights follow the ground (smoothed) or the points (set), D93. A scenery road (D212) is an
## open one made the same way (open_road).

const SAMPLE_M := 2.0
const GRID_M := 40.0
## Curbs line both edges through corners tighter than this radius (and a little either side).
const CURB_CURVATURE := 1.0 / 140.0
const CURB_WIDTH := 1.1
## Projection (D94): up to this far above or below the road counts as on it; further, the height
## difference counts PROJECT_Y_WEIGHT times, so a car on a bridge keeps to the bridge.
const PROJECT_FREE_Y := 2.0
const PROJECT_Y_WEIGHT := 3.0
## A road this far above the ground stands on supports (and the ground isn't shaped to it).
const LIFTED_M := 3.0
## Ground-following heights: smoothed along the road (sigma, m) and kept under this grade.
const GROUND_SMOOTH_M := 12.0
const MAX_GRADE := 0.15

var id := ""
var display_name := ""
var style := StyleProfile.DEFAULT
## Nominal width (both default sides); per-sample widths are half_l and half_r.
var width := 12.0
## The track file as noss.track/1.
var raw := {}
## "road": built from the spline; "centreline": a fitted scene (the spline only guides).
var kind := "road"
## "circuit", "highway" or "arena" (TrackFormat.TYPES).
var type := "circuit"
## A loop (every track's main road), or an open strip with two ends (a highway's ramps, D107).
var closed := true
## A highway's carriageways, ramps and runs (D106); null on circuits.
var highway: HighwayLayout
## Kart pieces and item boxes (D136); null unless the track has a kart section, or is an arena.
var kart: KartLayout
## An arena's outline, floor, spawns and box clusters (D138); null on other tracks.
var arena: ArenaLayout
## A circuit's pit lane (D203); null if it has none, or it doesn't build (pit_error says why).
var pit: PitLane
var pit_error := ""
## Scenery roads (D212): the pieces of the track's `roads`, fitted to the road and its pit lane.
var scenery: Array[TrackData] = []
## The ground it was laid on (for rebuilding a highway's ramps without resampling the road).
var _ground := Callable()
## Built in (res://): records are keyed by id alone.
var builtin := false
## Centreline samples every ~2 m, with their along-track distance from the first point.
var samples := PackedVector3Array()
var distances := PackedFloat32Array()
var tangents := PackedVector3Array()
## Car-left unit vectors (up × forward), banked; and the road's up.
var lefts := PackedVector3Array()
var ups := PackedVector3Array()
## Signed curvature, 1/m, + = turning left.
var curvature := PackedFloat32Array()
## Curbs per side (1 = on), and on either side (track limits, the AI's corridor).
var curbs := PackedByteArray()
var curb_l := PackedByteArray()
var curb_r := PackedByteArray()
## Centreline to each edge, m; banking, rad (+ raises the left edge).
var half_l := PackedFloat32Array()
var half_r := PackedFloat32Array()
var bank := PackedFloat32Array()
## An apron past each edge (and its curb), m across it, and its slope, rad (+ raises the left), D202.
var apron_l := PackedFloat32Array()
var apron_r := PackedFloat32Array()
var apron_l_bank := PackedFloat32Array()
var apron_r_bank := PackedFloat32Array()
## Per sample: VehicleSim surface ids of the road and run-offs, run-off widths, barrier types
## (TrackFormat.BARRIERS), lanes, line style (TrackFormat.LINES), and lifted (on supports).
var surface := PackedByteArray()
var runoff_l := PackedByteArray()
var runoff_r := PackedByteArray()
var runoff_l_m := PackedFloat32Array()
var runoff_r_m := PackedFloat32Array()
var barrier_l := PackedByteArray()
var barrier_r := PackedByteArray()
var lanes := PackedByteArray()
var lines := PackedByteArray()
var lifted := PackedByteArray()
## The control segment each sample is on, and each segment's first sample.
var sample_seg := PackedInt32Array()
var seg_first := PackedInt32Array()
var length := 0.0
var start_m := 0.0
## Sector end distances, measured from the start line.
var sectors_m := PackedFloat32Array()
var checkpoint_spacing := 100.0
## Race grid: slots, front_m, row_m, stagger, pole ("left" or "right").
var grid := TrackFormat.GRID.duplicate()
var rolling_back_m := TrackFormat.ROLLING_BACK_M
var gantry := true
## The AI drives carefully on its first lap until this far past the start, m.
var caution_until_m := 1100.0
## The AI line's pins: [{at_m, offset_m}].
var ai_pins: Array = []
var layout_hash := ""
## Below this the car has fallen off the world.
var kill_y := -100.0
var _grid := {}


## A track file: noss.track/1, or /0 (upgraded). Null, with the reason pushed, if it isn't one.
static func load_file(path: String, ground_height := Callable()) -> TrackData:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Not a track file: " + path)
		return null
	if data.get("schema") == TrackFormat.LEGACY:
		data = TrackFormat.upgrade_v0(data)
	elif data.get("schema") == TrackFormat.SCHEMA:
		var err := TrackFormat.validate(data)
		if err:
			push_error("%s: %s" % [path, err])
			return null
	else:
		push_error("Not a track file: " + path)
		return null
	var t := from_dict(data, ground_height)
	t.builtin = path.begins_with("res://")
	return t


## `data` is noss.track/1 (or /0, upgraded). `ground_height(x, z) -> float` gives the ground
## for points that follow it; without it the ground is flat at 0.
static func from_dict(data: Dictionary, ground_height := Callable()) -> TrackData:
	if data.get("schema") == TrackFormat.LEGACY:
		data = TrackFormat.upgrade_v0(data)
	var t := TrackData.new()
	t.raw = data
	t.id = String(data.get("id", ""))
	t.display_name = String(data.get("name", t.id))
	t.style = String(data.get("style", StyleProfile.DEFAULT))
	var road: Dictionary = data.get("road", {})
	t.kind = "centreline" if road.get("mode") == "centreline" else "road"
	var defaults: Dictionary = road.get("defaults", {})
	t.width = float(defaults.get("width_l", TrackFormat.DEFAULTS.width_l)) + float(defaults.get("width_r", TrackFormat.DEFAULTS.width_r))
	t.layout_hash = TrackFormat.layout_hash(data)
	t.type = String(data.get("type", "circuit"))
	# A highway on flat ground still knows the ground (at 0), so its viaducts stand on supports.
	var ground := ground_height if ground_height.is_valid() or t.type != "highway" else func(_x: float, _z: float) -> float: return 0.0
	t._ground = ground
	if (road.get("points", []) as Array).size() >= 3: # fewer make no loop
		t._sample(road, ground)
	t._read_race(data.get("race", {}))
	if t.type == "highway" and t.samples.size() >= 3:
		t.highway = HighwayLayout.build(t, TrackFormat.highway_settings(data), ground)
	t._read_kart(data)
	t._read_pit(data)
	t._read_roads(data)
	return t


## The same road with `data`'s race setup (start, sectors, grid, AI) and a highway's ramps,
## portals, zones and runs: no resampling. The road's arrays are shared, so neither copy may
## change them.
func with_race(data: Dictionary) -> TrackData:
	var t := TrackData.new()
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			t.set(prop.name, get(prop.name))
	t.raw = data
	t.layout_hash = TrackFormat.layout_hash(data)
	t._read_race(data.get("race", {}))
	if highway:
		t.highway = HighwayLayout.build(t, TrackFormat.highway_settings(data), _ground)
	t._read_kart(data)
	t._read_pit(data)
	t._read_roads(data)
	return t


## An open road made as the main road is from `road` ({points, defaults}), beside `main`: a
## scenery road's (D212).
static func open_road(main: TrackData, road: Dictionary, ground: Callable) -> TrackData:
	var t := TrackData.new()
	t.raw = main.raw
	t.id = main.id
	t.type = main.type
	t.closed = false
	t._ground = ground
	if (road.get("points", []) as Array).size() >= 2:
		t._sample(road, ground)
	return t


func _read_roads(data: Dictionary) -> void:
	scenery = []
	if not data.get("roads") is Array or kind != "road" or samples.size() < 3:
		return
	var ground := _ground if _ground.is_valid() else func(_x: float, _z: float) -> float: return 0.0
	var others: Array[TrackData] = []
	if pit:
		others.append(pit.track)
	scenery = SceneryRoad.build_all(self, data.roads, others, ground)


func _read_pit(data: Dictionary) -> void:
	pit = null
	pit_error = ""
	if not data.get("pit") is Dictionary or type != "circuit" or kind != "road" or samples.size() < 3:
		return
	var ground := _ground if _ground.is_valid() else func(_x: float, _z: float) -> float: return 0.0
	var built := PitLane.build(self, data.pit, ground)
	if built.error:
		pit_error = built.error
	else:
		pit = built


func _read_kart(data: Dictionary) -> void:
	arena = null
	kart = null
	if samples.size() < 3:
		return
	if type == "arena":
		arena = ArenaLayout.build(self, data.get("arena", {}))
	if data.has("kart") or arena:
		kart = KartLayout.build(self, data.get("kart", {}))


func _read_race(race: Dictionary) -> void:
	checkpoint_spacing = float(race.get("checkpoint_spacing_m", 100.0))
	var g: Dictionary = race.get("grid", {})
	grid = TrackFormat.GRID.duplicate()
	for key: String in TrackFormat.GRID:
		grid[key] = g.get(key, TrackFormat.GRID[key])
	rolling_back_m = float(race.get("rolling_back_m", TrackFormat.ROLLING_BACK_M))
	gantry = bool(race.get("gantry", true))
	var ai: Dictionary = race.get("ai", {})
	ai_pins = ai.get("pins", []).duplicate(true)
	sectors_m = PackedFloat32Array()
	if samples.size() < 2:
		return
	start_m = fposmod(float(race.get("start_m", 0.0)), length)
	for s: float in race.get("sectors_m", []):
		sectors_m.append(fposmod(s - start_m, length))
	var caution := float(ai.get("caution_until_m", TrackFormat.CAUTION_AUTO))
	caution_until_m = caution if caution >= 0.0 else minf(1100.0, 0.45 * length)


## The key lap records (ghosts, leaderboards) are kept under: built-in tracks by id; others by id
## and layout, so an edited layout starts fresh (D97).
func record_key() -> String:
	if builtin:
		return id
	return "%s-%s" % [id, layout_hash.trim_prefix("sha256:").left(12)]


## Along-track distance from the start line, wrapped to [0, length).
func from_start(distance: float) -> float:
	return fposmod(distance - start_m, length)


func index_at(distance: float) -> int:
	var d := fposmod(distance, length) if closed else clampf(distance, 0.0, length)
	var i := distances.bsearch(d, true) - 1
	return clampi(i, 0, samples.size() - 1)


func point_at(distance: float) -> Vector3:
	var i := index_at(distance)
	if not closed:
		var k := mini(i + 1, samples.size() - 1)
		var along := clampf(distance, 0.0, length) - distances[i]
		return samples[i].lerp(samples[k], clampf(along / maxf(distances[k] - distances[i], 0.001), 0.0, 1.0))
	var j := (i + 1) % samples.size()
	var span := (distances[j] if j > 0 else length) - distances[i]
	return samples[i].lerp(samples[j], clampf((fposmod(distance, length) - distances[i]) / maxf(span, 0.001), 0.0, 1.0))


## Car placement at `distance`: origin on the road, +Z along the track, +X to its left, +Y the
## road's up (banked).
func transform_at(distance: float, lateral := 0.0) -> Transform3D:
	var i := index_at(distance)
	var fwd := tangents[i]
	var left := lefts[i]
	return Transform3D(Basis(left, ups[i], fwd), point_at(distance) + left * lateral)


## Grid slot `i` (0: pole): two staggered columns behind the start line, each half way to the
## narrower edge, the pole on the grid's pole side.
func grid_slot(i: int) -> Transform3D:
	var d := start_m - float(grid.front_m) - (i / 2) * float(grid.row_m) - (i % 2) * float(grid.row_m) * float(grid.stagger)
	var column := 1.0 if i % 2 == 0 else -1.0
	if grid.pole == "right":
		column = -column
	return transform_at(d, 0.5 * minf(half_width(d, 1.0), half_width(d, -1.0)) * column)


## Centreline to the road's edge on `side` (+1 left, -1 right) at `distance`, m.
func half_width(distance: float, side: float) -> float:
	var i := index_at(distance)
	return half_l[i] if side >= 0.0 else half_r[i]


## How far from the centreline still counts as track on `side`: the road, its curb and apron.
func edge_at(distance: float, side: float) -> float:
	var i := index_at(distance)
	if side >= 0.0:
		return half_l[i] + (CURB_WIDTH if curb_l[i] else 0.0) + apron(i, 1.0)
	return half_r[i] + (CURB_WIDTH if curb_r[i] else 0.0) + apron(i, -1.0)


## The apron's width on `side` at sample `i`, m (0: none; roads built without one, like a
## highway's ramps, have none).
func apron(i: int, side: float) -> float:
	var a := apron_l if side > 0.0 else apron_r
	return a[i] if i < a.size() else 0.0


## The outer edge of the paving on `side` (+1 left, -1 right) at sample `i`: past the curb and
## the apron.
func paved_edge(i: int, side: float) -> Vector3:
	var curb := CURB_WIDTH if (curb_l[i] if side > 0.0 else curb_r[i]) else 0.0
	return cross_point(i, side, curb + apron(i, side))


## The point `out` m past the road's edge on `side` at sample `i`, across the cross-section: on
## along the road's banking over its curb, then at the apron's own slope, and on at that slope past
## it (run-off, barriers). Without an apron, straight on along the banking.
func cross_point(i: int, side: float, out: float) -> Vector3:
	var half: float = half_l[i] if side > 0.0 else half_r[i]
	var curb := CURB_WIDTH if (curb_l[i] if side > 0.0 else curb_r[i]) else 0.0
	if apron(i, side) <= 0.0 or out <= curb:
		return samples[i] + lefts[i] * side * (half + out)
	return samples[i] + lefts[i] * side * (half + curb) + apron_left(i, side) * side * (out - curb)


## The apron's left on `side` at sample `i`: the level left tilted by the apron's slope.
func apron_left(i: int, side: float) -> Vector3:
	var level := Vector3.UP.cross(tangents[i]).normalized()
	var up := tangents[i].cross(level)
	var a: float = apron_l_bank[i] if side > 0.0 else apron_r_bank[i]
	return level * cos(a) + up * sin(a)


## The sector (0-based) `distance` is in.
func sector_of(distance: float) -> int:
	var d := from_start(distance)
	for k in sectors_m.size():
		if d < sectors_m[k]:
			return k
	return sectors_m.size()


## Samples of control segment `seg`: [first, end) (end may wrap past the last sample).
func segment_samples(seg: int) -> Vector2i:
	var n := seg_first.size()
	if not closed:
		var first := seg_first[clampi(seg, 0, n - 1)]
		return Vector2i(first, seg_first[seg + 1] if seg + 1 < n else samples.size() - 1)
	var a := seg_first[posmod(seg, n)]
	var b := seg_first[posmod(seg + 1, n)]
	return Vector2i(a, b if b > a else b + samples.size())


## Nearest point on the centreline. With `hint` (a sample index, e.g. last tick's) it walks
## from there to the nearest sample, which takes a step or two for a moving car. Height counts
## past PROJECT_FREE_Y, so bridges and the roads under them stay apart.
## Returns {index, distance, lateral (+ = left), point}. An open strip clamps to its ends.
func project(pos: Vector3, hint := -1) -> Dictionary:
	if not closed:
		return _project_open(pos, hint)
	var n := samples.size()
	var best := -1
	var best_d2 := INF
	if hint >= 0:
		best = posmod(hint, n)
		best_d2 = _d2(best, pos)
		for step in 200:
			var fwd := (best + 1) % n
			var back := (best - 1 + n) % n
			var d_fwd := _d2(fwd, pos)
			var d_back := _d2(back, pos)
			if d_fwd < best_d2 and d_fwd <= d_back:
				best = fwd
				best_d2 = d_fwd
			elif d_back < best_d2:
				best = back
				best_d2 = d_back
			else:
				break
		if best_d2 > 2500.0:
			return project(pos) # lost track of the hint; search everything
	else:
		for i in n:
			var d2 := _d2(i, pos)
			if d2 < best_d2:
				best_d2 = d2
				best = i
	# Refine on the neighbouring segment.
	var j := (best + 1) % n
	var seg := samples[j] - samples[best]
	var t := clampf((pos - samples[best]).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	var on := samples[best] + seg * t
	var dist := fposmod(distances[best] + seg.length() * t, length)
	return { "index": best, "distance": dist, "lateral": (pos - on).dot(lefts[best]), "point": on }


func _project_open(pos: Vector3, hint: int) -> Dictionary:
	var n := samples.size()
	var best := -1
	var best_d2 := INF
	if hint >= 0 and hint < n:
		best = hint
		best_d2 = _d2(best, pos)
		for step in 200:
			var d_fwd := _d2(best + 1, pos) if best + 1 < n else INF
			var d_back := _d2(best - 1, pos) if best > 0 else INF
			if d_fwd < best_d2 and d_fwd <= d_back:
				best += 1
				best_d2 = d_fwd
			elif d_back < best_d2:
				best -= 1
				best_d2 = d_back
			else:
				break
		if best_d2 > 2500.0:
			return _project_open(pos, -1)
	else:
		for i in n:
			var d2 := _d2(i, pos)
			if d2 < best_d2:
				best_d2 = d2
				best = i
	# Refine on the segment either side (no wrap; the ends clamp).
	var a := best if best < n - 1 else best - 1
	if best > 0 and best < n - 1:
		var back := samples[best] - samples[best - 1]
		if (pos - samples[best]).dot(back) < 0.0:
			a = best - 1
	var seg := samples[a + 1] - samples[a]
	var t := clampf((pos - samples[a]).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	var on := samples[a] + seg * t
	var k := a if t < 0.5 else a + 1
	return { "index": k, "distance": distances[a] + seg.length() * t, "lateral": (pos - on).dot(lefts[a]), "point": on }


## True if any centreline sample is within `radius` (XZ) of `pos`. Uses a coarse grid.
func is_near_centreline(pos: Vector3, radius: float) -> bool:
	index_cells()
	var reach := int(ceil(radius / GRID_M))
	var center := _cell(pos)
	var r2 := radius * radius
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for i: int in _grid.get(center + Vector2i(dx, dz), []):
				if Vector2(samples[i].x - pos.x, samples[i].z - pos.z).length_squared() < r2:
					return true
	return false


## Builds the coarse grid is_near_centreline() uses (before handing the track to a worker).
func index_cells() -> void:
	if not _grid.is_empty():
		return
	for i in samples.size():
		var key := _cell(samples[i])
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


## Samples within `radius` (XZ) of `pos`.
func samples_near(pos: Vector3, radius: float) -> PackedInt32Array:
	index_cells()
	var out := PackedInt32Array()
	var reach := int(ceil(radius / GRID_M))
	var center := _cell(pos)
	var r2 := radius * radius
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for i: int in _grid.get(center + Vector2i(dx, dz), []):
				if Vector2(samples[i].x - pos.x, samples[i].z - pos.z).length_squared() < r2:
					out.append(i)
	return out


func _d2(i: int, pos: Vector3) -> float:
	var s := samples[i]
	var dy := maxf(absf(s.y - pos.y) - PROJECT_FREE_Y, 0.0) * PROJECT_Y_WEIGHT
	return Vector2(s.x - pos.x, s.z - pos.z).length_squared() + dy * dy


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID_M), floori(p.z / GRID_M))


func _sample(road: Dictionary, ground_height: Callable) -> void:
	var points_data: Array = road.points
	var n := points_data.size()
	var ground := func(x: float, z: float) -> float: return float(ground_height.call(x, z)) if ground_height.is_valid() else 0.0
	# Control points: set heights as given, ground ones on the ground.
	var points := PackedVector3Array()
	var set_h := PackedFloat32Array()
	for i in n:
		var p: Array = points_data[i].p
		var is_set: bool = TrackFormat.attr(road, i, "height") == "set"
		set_h.append(1.0 if is_set else 0.0)
		points.append(Vector3(p[0], float(p[1]) if is_set else ground.call(float(p[0]), float(p[2])), p[2]))
	# Sample the spline, noting each sample's segment and how far along it. An open road's ends
	# run on straight (a mirrored point beyond each), and its last point ends it.
	var along := PackedFloat32Array()
	for i in (n if closed else n - 1):
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		var p0 := points[(i - 1 + n) % n] if closed or i > 0 else p1 * 2.0 - p2
		var p3 := points[(i + 2) % n] if closed or i + 2 < n else p2 * 2.0 - p1
		var steps := maxi(2, int(p1.distance_to(p2) / SAMPLE_M))
		seg_first.append(samples.size())
		for s in steps:
			samples.append(_catmull_rom(p0, p1, p2, p3, float(s) / steps))
			sample_seg.append(i)
			along.append(float(s) / steps)
	if not closed:
		samples.append(points[n - 1])
		sample_seg.append(n - 2)
		along.append(1.0)
	var m := samples.size()
	# Per-sample attributes: blended across the segment, or the segment's own.
	var seg_attr := []
	for i in n:
		var a := {}
		for key: String in TrackFormat.DEFAULTS:
			a[key] = TrackFormat.attr(road, i, key)
		seg_attr.append(a)
	# (Packed arrays are values: each is resized by name.)
	half_l.resize(m)
	half_r.resize(m)
	bank.resize(m)
	apron_l.resize(m)
	apron_r.resize(m)
	apron_l_bank.resize(m)
	apron_r_bank.resize(m)
	runoff_l_m.resize(m)
	runoff_r_m.resize(m)
	surface.resize(m)
	runoff_l.resize(m)
	runoff_r.resize(m)
	barrier_l.resize(m)
	barrier_r.resize(m)
	lanes.resize(m)
	lines.resize(m)
	lifted.resize(m)
	curb_l.resize(m)
	curb_r.resize(m)
	for k in m:
		var s := sample_seg[k]
		var a: Dictionary = seg_attr[s]
		var b: Dictionary = seg_attr[(s + 1) % n]
		var u := smoothstep(0.0, 1.0, along[k])
		half_l[k] = lerpf(float(a.width_l), float(b.width_l), u)
		half_r[k] = lerpf(float(a.width_r), float(b.width_r), u)
		# Banking follows a smooth curve through the points, as the heights do: blended per segment
		# it would twist the road in steps, rippling the surface off the centreline.
		var bank_prev := float((seg_attr[_wrap(s - 1, n)] as Dictionary).bank_deg)
		var bank_next := float((seg_attr[_wrap(s + 2, n)] as Dictionary).bank_deg)
		bank[k] = deg_to_rad(_curve(bank_prev, float(a.bank_deg), float(b.bank_deg), bank_next, along[k]))
		apron_l[k] = lerpf(float(a.apron_l_m), float(b.apron_l_m), u)
		apron_r[k] = lerpf(float(a.apron_r_m), float(b.apron_r_m), u)
		apron_l_bank[k] = deg_to_rad(lerpf(float(a.apron_l_deg), float(b.apron_l_deg), u))
		apron_r_bank[k] = deg_to_rad(lerpf(float(a.apron_r_deg), float(b.apron_r_deg), u))
		surface[k] = TrackFormat.surface_id(String(a.surface))
		runoff_l[k] = TrackFormat.surface_id(String(a.runoff_l))
		runoff_r[k] = TrackFormat.surface_id(String(a.runoff_r))
		runoff_l_m[k] = float(a.runoff_l_m)
		runoff_r_m[k] = float(a.runoff_r_m)
		barrier_l[k] = TrackFormat.barrier_id(String(a.barrier_l))
		barrier_r[k] = TrackFormat.barrier_id(String(a.barrier_r))
		lanes[k] = clampi(int(a.lanes), 1, 8)
		lines[k] = maxi(TrackFormat.LINES.find(String(a.lines)), 0)
	_heights(set_h, along, ground)
	var total := 0.0
	for i in m:
		distances.append(total)
		if closed or i + 1 < m:
			total += samples[i].distance_to(samples[(i + 1) % m])
	length = total
	for i in m:
		var fwd := (samples[_wrap(i + 1, m)] - samples[_wrap(i - 1, m)]).normalized()
		tangents.append(fwd)
		var left := Vector3.UP.cross(fwd).normalized()
		var up := fwd.cross(left)
		if bank[i] != 0.0: # banked: the left edge rises
			var c := cos(bank[i])
			var s := sin(bank[i])
			var banked := left * c + up * s
			up = fwd.cross(banked)
			left = banked
		lefts.append(left)
		ups.append(up.normalized())
	for i in m:
		var a := tangents[_wrap(i - 1, m)]
		var b := tangents[_wrap(i + 1, m)]
		var ds := samples[_wrap(i - 1, m)].distance_to(samples[_wrap(i + 1, m)])
		curvature.append(asin(clampf(a.cross(b).y, -1.0, 1.0)) / maxf(ds, 0.01))
	_find_curbs(seg_attr)
	var lowest := INF
	for i in m:
		lowest = minf(lowest, samples[i].y)
		# Banked road is measured from its lower edge: one standing on that edge isn't a bridge.
		var low := samples[i]
		if bank[i] != 0.0:
			low += lefts[i] * (half_l[i] if bank[i] < 0.0 else -half_r[i])
		lifted[i] = 1 if ground_height.is_valid() and low.y - float(ground.call(low.x, low.z)) > LIFTED_M else 0
	kill_y = lowest - 30.0


## Sample heights: set points' spline heights, or the ground under the road (averaged across it,
## smoothed along it, its grade limited), blended by smoothstep across mixed segments.
func _heights(set_h: PackedFloat32Array, along: PackedFloat32Array, ground: Callable) -> void:
	var m := samples.size()
	var n := set_h.size()
	var any_ground := false
	for h in set_h:
		any_ground = any_ground or h < 0.5
	if not any_ground:
		return # every height is set: the spline's (v0 tracks)
	var g := PackedFloat32Array()
	g.resize(m)
	for k in m:
		var p := samples[k]
		var fwd := (samples[_wrap(k + 1, m)] - samples[_wrap(k - 1, m)])
		var left := Vector3(-fwd.z, 0.0, fwd.x).normalized()
		g[k] = (float(ground.call(p.x, p.z)) + float(ground.call(p.x + left.x * half_l[k], p.z + left.z * half_l[k]))
			+ float(ground.call(p.x - left.x * half_r[k], p.z - left.z * half_r[k]))) / 3.0
	# Smooth along the road (Gaussian, sigma GROUND_SMOOTH_M), wrapping (an open road's ends hold).
	var reach := int(ceil(GROUND_SMOOTH_M * 1.5 / SAMPLE_M))
	var weights := PackedFloat32Array()
	for o in range(-reach, reach + 1):
		var x := o * SAMPLE_M / GROUND_SMOOTH_M
		weights.append(exp(-0.5 * x * x))
	var smooth := PackedFloat32Array()
	smooth.resize(m)
	for k in m:
		var sum := 0.0
		var wsum := 0.0
		for o in range(-reach, reach + 1):
			var w := weights[o + reach]
			sum += g[_wrap(k + o, m)] * w
			wsum += w
		smooth[k] = sum / wsum
	# Keep the grade under MAX_GRADE: a pass each way, twice round so it closes.
	for pass_i in (2 if closed else 1):
		for k in (m if closed else m - 1):
			var j := (k + 1) % m
			var step := Vector2(samples[j].x - samples[k].x, samples[j].z - samples[k].z).length() * MAX_GRADE
			smooth[j] = clampf(smooth[j], smooth[k] - step, smooth[k] + step)
		for k in range(m - 1, -1 if closed else 0, -1):
			var j := (k - 1 + m) % m
			var step := Vector2(samples[j].x - samples[k].x, samples[j].z - samples[k].z).length() * MAX_GRADE
			smooth[j] = clampf(smooth[j], smooth[k] - step, smooth[k] + step)
	for k in m:
		var s := sample_seg[k]
		var w := lerpf(set_h[s], set_h[(s + 1) % n], smoothstep(0.0, 1.0, along[k]))
		var p := samples[k]
		p.y = lerpf(smooth[k], p.y, w)
		samples[k] = p


## Curbs through corners: smoothed curvature over ±6 samples above CURB_CURVATURE, extended
## 5 samples either side; a segment's "on" or "off" overrides that per side.
func _find_curbs(seg_attr: Array) -> void:
	var n := samples.size()
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for i in n:
		var sum := 0.0
		for k in range(-6, 7):
			sum += curvature[_wrap(i + k, n)]
		smooth[i] = sum / 13.0
	curbs.resize(n)
	for i in n:
		var on := 0
		for k in range(-5, 6):
			if absf(smooth[_wrap(i + k, n)]) > CURB_CURVATURE:
				on = 1
				break
		var a: Dictionary = seg_attr[sample_seg[i]]
		curb_l[i] = on if a.curb_l == "auto" else (1 if a.curb_l == "on" else 0)
		curb_r[i] = on if a.curb_r == "auto" else (1 if a.curb_r == "on" else 0)
		curbs[i] = curb_l[i] | curb_r[i]


## Index `i` of `n` round a closed road, held at an open road's ends.
func _wrap(i: int, n: int) -> int:
	return posmod(i, n) if closed else clampi(i, 0, n - 1)


## Extra width at `distance` that still counts as track: the curb, where there is one.
func curb_at(distance: float) -> float:
	return CURB_WIDTH if curbs[index_at(distance)] else 0.0


## A smooth curve through values (a monotone cubic), `u` (0-1) between `p1` and `p2`: level
## where the values level off or turn back (a smoothstep, as segments blend), steady through a
## steady change, never past its neighbours. Equal middle values give exactly that value.
static func _curve(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	if p1 == p2:
		return p1
	var d0 := p1 - p0
	var d1 := p2 - p1
	var d2 := p3 - p2
	var m1 := 0.0 if d0 * d1 <= 0.0 else signf(d1) * minf(absf(d0 + d1) / 2.0, 3.0 * minf(absf(d0), absf(d1)))
	var m2 := 0.0 if d1 * d2 <= 0.0 else signf(d1) * minf(absf(d1 + d2) / 2.0, 3.0 * minf(absf(d1), absf(d2)))
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * p1 + (u3 - 2.0 * u2 + u) * m1 + (3.0 * u2 - 2.0 * u3) * p2 + (u3 - u2) * m2


## Centripetal Catmull-Rom: no cusps or loops between unevenly spaced points.
static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 1e-4))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 1e-4))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 1e-4))
	var t := lerpf(t1, t2, u)
	var a1 := p0 * (t1 - t) / (t1 - t0) + p1 * (t - t0) / (t1 - t0)
	var a2 := p1 * (t2 - t) / (t2 - t1) + p2 * (t - t1) / (t2 - t1)
	var a3 := p2 * (t3 - t) / (t3 - t2) + p3 * (t - t2) / (t3 - t2)
	var b1 := a1 * (t2 - t) / (t2 - t0) + a2 * (t - t0) / (t2 - t0)
	var b2 := a2 * (t3 - t) / (t3 - t1) + a3 * (t - t1) / (t3 - t1)
	return b1 * (t2 - t) / (t2 - t1) + b2 * (t - t1) / (t2 - t1)
