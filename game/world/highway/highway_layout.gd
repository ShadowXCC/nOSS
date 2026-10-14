class_name HighwayLayout
extends RefCounted
## A highway track's carriageways, ramps, portals, runs, zones and speed traps (D106) on its main
## road: the median's closed centreline. Direction +1 drives along the road on its right (lateral
## < 0, +X being the road's left), -1 the other way on its left. Lanes count from the outside:
## lane 0 is the slow lane by the outer shoulder, the last one runs by the median.

## A car this far outside a road's edge, or this far above or below it, isn't on it.
const OFF_ROAD_M := 1.0
const OFF_HEIGHT_M := 2.5

## The main road (held weakly: the track holds this layout).
var main: TrackData:
	get:
		return _main.get_ref() as TrackData
## TrackFormat.highway_settings(): every key present.
var settings := {}
var lanes := 3
var lane_m := 3.6
## Centreline to the median-side edge of the inner lane (half the median and the inner shoulder).
var inner := 2.0
## Centreline to each outer edge (the default; per sample: main.half_l / half_r).
var half := 15.8
## Speed limit, m/s.
var speed := 110.0 / 3.6
var ramps: Array[RampData] = []
## id -> {id, name, p: Vector3, forward: Vector3 (out of the portal), yaw (rad)}.
var portals := {}
## [{id, name, dir, from_m, to_m}], [{dir, from_m, to_m, speed (m/s), tunnel, name}], [{dir, at_m}].
var runs: Array = []
var zones: Array = []
var traps: Array = []
## Per main sample, 1 where a ramp leaves or joins on that side (no barrier, run-off or edge line).
var gap_l := PackedByteArray()
var gap_r := PackedByteArray()
## Problems building ramps, e.g. "harbour_off: Ramp too short".
var errors := PackedStringArray()
var _ramp_boxes: Array[AABB] = []
var _main: WeakRef


static func build(t: TrackData, h: Dictionary, ground: Callable) -> HighwayLayout:
	var layout := HighwayLayout.new()
	layout._main = weakref(t)
	layout.settings = h
	layout.lanes = int(h.lanes)
	layout.lane_m = float(h.lane_m)
	layout.inner = float(h.median_m) / 2.0 + float(h.shoulder_in_m)
	layout.half = TrackFormat.highway_half(h)
	layout.speed = float(h.speed_kmh) / 3.6
	layout.gap_l.resize(t.samples.size())
	layout.gap_r.resize(t.samples.size())
	for p: Dictionary in h.portals:
		var yaw := deg_to_rad(float(p.get("yaw_deg", 0.0)))
		var a: Array = p.p
		layout.portals[p.id] = { "id": p.id, "name": String(p.get("name", p.id)), "p": Vector3(float(a[0]), float(a[1]), float(a[2])),
			"forward": Vector3(sin(yaw), 0.0, cos(yaw)), "yaw": yaw }
	for r: Dictionary in h.ramps:
		var ramp := RampData.build(layout, r, ground)
		if ramp.error:
			layout.errors.append("%s: %s" % [ramp.id, ramp.error])
			continue
		layout.ramps.append(ramp)
		var box := AABB(ramp.track.samples[0], Vector3.ZERO)
		for p in ramp.track.samples:
			box = box.expand(p)
		layout._ramp_boxes.append(box.grow(ramp.width + OFF_HEIGHT_M))
	for run: Dictionary in h.runs:
		layout.runs.append({ "id": String(run.id), "name": String(run.get("name", run.id)), "dir": int(run.dir),
			"from_m": float(run.from_m), "to_m": float(run.to_m) })
	for z: Dictionary in h.zones:
		layout.zones.append({ "dir": int(z.get("dir", 0)), "from_m": float(z.from_m), "to_m": float(z.to_m),
			"speed": float(z.get("speed_kmh", h.speed_kmh)) / 3.6, "tunnel": bool(z.get("tunnel", false)), "name": String(z.get("name", "")) })
	for trap: Dictionary in h.traps:
		layout.traps.append({ "dir": int(trap.dir), "at_m": float(trap.at_m) })
	return layout


## Lateral offset (from the centreline, + = left) of lane `lane` of direction `dir`'s carriageway.
func lane_lateral(dir: int, lane: int) -> float:
	return -dir * (inner + (lanes - lane - 0.5) * lane_m)


## The carriageway a lateral offset is on: +1 (right of the centreline) or -1.
static func carriageway_at(lateral: float) -> int:
	return 1 if lateral < 0.0 else -1


## The lane at a lateral offset on the main road (clamped to the carriageway's lanes).
func lane_at(lateral: float) -> int:
	return clampi(lanes - 1 - floori((absf(lateral) - inner) / lane_m), 0, lanes - 1)


## Distance driven along direction `dir` to main-road distance `d` from the road's 0.
func along(dir: int, d: float) -> float:
	return fposmod(d, main.length) if dir > 0 else fposmod(-d, main.length)


## True if main sample `k` has a ramp mouth on `side` (+1 left, -1 right).
func gap(k: int, side: float) -> bool:
	return (gap_l if side > 0.0 else gap_r)[k] != 0


## The speed limit on direction `dir` at main-road distance `d`, m/s.
func speed_at(dir: int, d: float) -> float:
	for z: Dictionary in zones:
		if (z.dir == 0 or z.dir == dir) and _within(d, z.from_m, z.to_m):
			return z.speed
	return speed


## True inside a tunnel zone at main-road distance `d`.
func in_tunnel(d: float) -> bool:
	for z: Dictionary in zones:
		if z.tunnel and _within(d, z.from_m, z.to_m):
			return true
	return false


func _within(d: float, from_m: float, to_m: float) -> bool:
	var a := fposmod(d - from_m, main.length)
	return a <= fposmod(to_m - from_m, main.length)


## Main samples from `at_m` driving along `dir` until `length` m have passed (both ends included).
func walk(dir: int, at_m: float, length: float) -> PackedInt32Array:
	var n := main.samples.size()
	var k := main.index_at(at_m)
	var out := PackedInt32Array([k])
	var traveled := 0.0
	while traveled < length and out.size() < n:
		var next := posmod(k + dir, n)
		traveled += main.samples[k].distance_to(main.samples[next])
		k = next
		out.append(k)
	return out


## Marks a ramp mouth on direction `dir`'s outer side from main sample `k_from` to `k_to`, driving.
func mark_gap(dir: int, k_from: int, k_to: int) -> void:
	var n := main.samples.size()
	var k := k_from
	for step in n:
		if dir > 0:
			gap_r[k] = 1
		else:
			gap_l[k] = 1
		if k == k_to:
			return
		k = posmod(k + dir, n)


func ramp(id: String) -> RampData:
	for r in ramps:
		if r.id == id:
			return r
	return null


## Where `pos` is on the highway: {road (-1: the main road, else a ramp's index), index, distance,
## lateral (+ = left of that road), dir (main road: the carriageway; ramp: 0), lane (main road),
## on_road}. `hint` is the last result (keeps the walk short).
func locate(pos: Vector3, hint := {}) -> Dictionary:
	var main_hint: int = hint.get("main", -1)
	var mp := main.project(pos, main_hint)
	var k := int(mp.index)
	var lat := float(mp.lateral)
	var edge: float = main.half_l[k] if lat >= 0.0 else main.half_r[k]
	var dy_main := absf(pos.y - main.samples[k].y)
	var best := { "road": -1, "index": k, "distance": mp.distance, "lateral": lat, "dir": carriageway_at(lat),
		"lane": lane_at(lat), "on_road": absf(lat) <= edge + OFF_ROAD_M and dy_main < OFF_HEIGHT_M, "main": k, "dy": dy_main }
	for i in ramps.size():
		if not _ramp_boxes[i].has_point(pos):
			continue
		var r := ramps[i]
		var rp := r.track.project(pos, int(hint.get("ramp_index", -1)) if int(hint.get("road", -1)) == i else -1)
		var ri := int(rp.index)
		var rlat := float(rp.lateral)
		var dy := absf(pos.y - r.track.samples[ri].y)
		var on := absf(rlat) <= r.track.half_l[ri] + OFF_ROAD_M and dy < OFF_HEIGHT_M and r.track.half_l[ri] > 0.5
		if on and (not best.on_road or dy < float(best.dy) - 0.5):
			best = { "road": i, "index": ri, "distance": rp.distance, "lateral": rlat, "dir": 0, "lane": 0, "on_road": true,
				"main": k, "dy": dy, "ramp_index": ri }
	return best


## True if a road (the main road or a ramp) runs under `p` at least `clear` m below it: a pillar
## standing there would land on it.
func road_below(p: Vector3, clear := 2.0) -> bool:
	var mp := main.project(p)
	var k := int(mp.index)
	var edge: float = main.half_l[k] if float(mp.lateral) >= 0.0 else main.half_r[k]
	if absf(float(mp.lateral)) <= edge + 0.5 and main.samples[k].y < p.y - clear:
		return true
	for i in ramps.size():
		var box := _ramp_boxes[i]
		if p.x < box.position.x or p.x > box.end.x or p.z < box.position.z or p.z > box.end.z:
			continue
		var r := ramps[i].track
		var rp := r.project(p)
		var ri := int(rp.index)
		if absf(float(rp.lateral)) <= r.half_l[ri] + 0.5 and r.samples[ri].y < p.y - clear:
			return true
	return false


## A car's spot in lane `lane` of direction `dir` at main-road distance `d`: on the road, facing
## the way that carriageway drives.
func spawn_spot(dir: int, d: float, lane: int) -> Transform3D:
	var t := main.transform_at(d, lane_lateral(dir, lane))
	if dir < 0:
		t.basis = Basis(-t.basis.x, t.basis.y, -t.basis.z)
	return t


## The lanes traffic drives, for the native lane sim (NossTraffic, D108): each lane's points in
## driving order, and how they connect. Main-road lanes are the road's samples offset sideways
## (vertex k of every lane of a direction is the same sample, so lanes map onto each other by
## vertex), driven backwards for direction -1. Ramps that carry traffic add one lane each.
##   lanes: [{dir, road (-1 or the ramp's index), index, closed, points, speed (m/s), limits (mm/s per vertex)}]
##   adjacent: [outer, inner]*    branches: [lane, vertex, ramp lane]*    merges: [ramp lane, lane, vertex]*
##   attaches: [ramp lane, ramp vertex, lane, lane vertex, count]*  (where a ramp runs beside a lane)
##   portal_in / portal_out: [lane, portal]*  (portal: its index in portal_ids)
func lane_graph() -> Dictionary:
	var n := main.samples.size()
	var out := { "lanes": [], "adjacent": PackedInt32Array(), "branches": PackedInt32Array(), "merges": PackedInt32Array(),
		"attaches": PackedInt32Array(), "portal_in": PackedInt32Array(), "portal_out": PackedInt32Array(), "portal_ids": [] }
	for dir: int in [1, -1]:
		var limits := PackedInt32Array()
		limits.resize(n)
		for v in n:
			limits[v] = roundi(speed_at(dir, main.distances[_vertex_sample(dir, v)]) * 1000.0)
		for lane in lanes:
			var pts := PackedVector3Array()
			pts.resize(n)
			var lat := lane_lateral(dir, lane)
			for v in n:
				var k := _vertex_sample(dir, v)
				pts[v] = main.samples[k] + main.lefts[k] * lat
			out.lanes.append({ "dir": dir, "road": -1, "index": lane, "closed": true, "points": pts, "speed": speed, "limits": limits })
			if lane + 1 < lanes:
				out.adjacent.append_array([main_lane(dir, lane), main_lane(dir, lane + 1)])
	var ids := portals.keys()
	ids.sort()
	out.portal_ids = ids
	for i in ramps.size():
		var r := ramps[i]
		if not r.traffic:
			continue
		var id: int = out.lanes.size()
		out.lanes.append({ "dir": 0, "road": i, "index": 0, "closed": false, "points": r.lane_path, "speed": r.speed })
		if r.from.has("portal"):
			out.portal_out.append_array([id, ids.find(r.from.portal)])
		else:
			out.branches.append_array([main_lane(int(r.from.dir), 0), _sample_vertex(int(r.from.dir), r.head_main[0]), id])
		if r.to.has("portal"):
			out.portal_in.append_array([id, ids.find(r.to.portal)])
		else:
			var dir := int(r.to.dir)
			var into := main_lane(dir, 0)
			out.merges.append_array([id, into, _sample_vertex(dir, r.tail_main[r.tail_main.size() - 1])])
			out.attaches.append_array([id, r.tail_start, into, _sample_vertex(dir, r.tail_main[0]), r.tail_main.size()])
	return out


## The lane graph index of main-road lane `lane` of direction `dir`.
func main_lane(dir: int, lane: int) -> int:
	return (0 if dir > 0 else lanes) + lane


## Main sample of lane vertex `v` on direction `dir` (driven backwards for -1).
func _vertex_sample(dir: int, v: int) -> int:
	return v if dir > 0 else posmod(-v, main.samples.size())


func _sample_vertex(dir: int, k: int) -> int:
	return k if dir > 0 else posmod(-k, main.samples.size())
