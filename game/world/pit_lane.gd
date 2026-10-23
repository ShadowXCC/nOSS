class_name PitLane
extends RefCounted
## A circuit's pit lane (D203): an open strip of road that leaves the main road on one side, runs
## past the boxes behind a pit wall and joins it again. Where it leaves and joins it is attached
## to the road as a highway's ramps are (D107): its inner edge is the road's paved edge (past a
## curb or an apron) and it widens from nothing, so the two meet without a seam. In between it
## follows its own points. Cars in it are on track; laps still count along the main road.
##
## In the file: { side, from_m, to_m, taper_m, points[], width_m, speed_kmh, limit_m, boxes,
## box_m, wall }, from_m and to_m metres along the main road from point 0 (where the lane starts
## to leave it, and where it has joined it again).

const DEFAULTS := { "side": "right", "taper_m": 120.0, "points": [], "width_m": 12.0, "speed_kmh": 60.0,
	"limit_m": 40.0, "boxes": 20, "box_m": 10.0, "wall": true }
## The pit wall starts (and ends) where the lane's inner edge is this far from the road's.
const GORE_M := 1.0
## Where it leaves or joins the road it starts this wide (no zero-width triangles).
const MIN_WIDTH := 0.05
## Boxes stay this far inside the limit lines and clear of the attached ends, m.
const BOX_CLEAR_M := 10.0
## A car counts as in the lane this far past its edges (and within this of its height).
const CONTAINS_MARGIN_M := 1.0
const CONTAINS_Y_M := 3.0

## +1: on the road's left, -1: its right.
var side := -1.0
## Main-road distances from point 0: where the lane starts to leave the road, and where it has
## joined it again.
var entry_m := 0.0
var exit_m := 0.0
var taper_m := 120.0
var width := 12.0
## The speed limit, m/s.
var speed := 60.0 / 3.6
## The limit lines, metres along the lane: from the first on, the limit holds, up to the second.
var limit_in_m := 40.0
var limit_out_m := 0.0
var box_m := 10.0
## Where each box is (a car stops there, facing along the lane), nearest the exit first, and how
## far along the lane, m.
var boxes: Array[Transform3D] = []
var box_at := PackedFloat32Array()
## The boxes didn't fit between the limit lines (the validator says so; they're packed in anyway).
var crowded := false
## A wall between the lane and the road, where they're apart.
var wall := true
## The lane's road: an open strip, its left the driver's left (as the main road's).
var track: TrackData
## Main-road samples the lane is attached to as it leaves and as it joins.
var head_main := PackedInt32Array()
var tail_main := PackedInt32Array()
## Strip samples where the pit wall starts and ends (past the gores).
var gore_head := 0
var gore_tail := 0
## Problems building it ("" if none).
var error := ""
var _main: TrackData
## Per main sample: 1 where its barrier on `side` opens onto the lane (the mouths).
var _gap := PackedByteArray()


## The pit lane `data` (the file's "pit") on `main`. Check `error`.
static func build(main: TrackData, data: Dictionary, ground: Callable) -> PitLane:
	var p := PitLane.new()
	var d: Dictionary = DEFAULTS.duplicate(true)
	d.merge(data, true)
	p._main = main
	p.side = 1.0 if d.side == "left" else -1.0
	p.entry_m = fposmod(float(d.get("from_m", 0.0)), main.length)
	p.exit_m = fposmod(float(d.get("to_m", 0.0)), main.length)
	p.taper_m = float(d.taper_m)
	p.width = float(d.width_m)
	p.speed = float(d.speed_kmh) / 3.6
	p.box_m = float(d.box_m)
	p.wall = bool(d.wall)
	p._gap.resize(main.samples.size())
	p._build(main, d, ground)
	if p.error.is_empty():
		p.limit_in_m = minf(float(d.limit_m), p.track.length / 2.0)
		p.limit_out_m = maxf(p.track.length - float(d.limit_m), p.limit_in_m)
		p._place_boxes(int(d.boxes))
	return p


## True where the main road's barrier and run-off on `on_side` open onto the lane at sample `k`.
func gap(k: int, on_side: float) -> bool:
	return on_side == side and k >= 0 and k < _gap.size() and _gap[k] != 0


## The main road's distance `d` is along the stretch the lane runs beside.
func beside(d: float) -> bool:
	return fposmod(d - entry_m, _main.length) <= fposmod(exit_m - entry_m, _main.length)


## Where `pos` is on the lane: {index, distance, lateral, point} (TrackData.project).
func project(pos: Vector3, hint := -1) -> Dictionary:
	return track.project(pos, hint)


## True if a car at `pos` (along the main road at `main_d`) is in the lane. `proj`: its
## project() there, when the caller has it.
func contains(pos: Vector3, main_d: float, proj := {}) -> bool:
	if track == null or not beside(main_d):
		return false
	var on: Dictionary = proj if not proj.is_empty() else project(pos)
	var i := int(on.index)
	var lat := float(on.lateral)
	var half: float = track.half_l[i] if lat >= 0.0 else track.half_r[i]
	return absf(lat) <= half + CONTAINS_MARGIN_M and absf(pos.y - (on.point as Vector3).y) < CONTAINS_Y_M and half > 1.0


## The limit holds at `d` metres along the lane.
func limited(d: float) -> bool:
	return d >= limit_in_m and d <= limit_out_m


func _build(main: TrackData, d: Dictionary, ground: Callable) -> void:
	if main.samples.size() < 3 or not main.closed:
		error = "No road"
		return
	head_main = _walk(main, entry_m, taper_m)
	tail_main = _walk(main, exit_m - taper_m, taper_m)
	if head_main.size() < 2 or tail_main.size() < 2 or fposmod(exit_m - entry_m, main.length) < 2.0 * taper_m + 2.0 * BOX_CLEAR_M:
		error = "Pit lane too short"
		return
	var pts := PackedVector3Array()
	var fwds := PackedVector3Array()
	var lefts := PackedVector3Array()
	var ups := PackedVector3Array()
	var halves := PackedFloat32Array()
	var on_main := PackedInt32Array() # main sample per strip sample (-1: free)
	var traveled := RampData._travel(main, head_main)
	for n in head_main.size():
		_attached(main, head_main[n], maxf(width * smoothstep(0.0, 1.0, traveled[n] / taper_m), MIN_WIDTH), pts, fwds, lefts, ups, halves)
		on_main.append(head_main[n])
	var tail_pts := PackedVector3Array()
	var tail_fwds := PackedVector3Array()
	var tail_lefts := PackedVector3Array()
	var tail_ups := PackedVector3Array()
	var tail_halves := PackedFloat32Array()
	traveled = RampData._travel(main, tail_main)
	for n in tail_main.size():
		_attached(main, tail_main[n], maxf(width * smoothstep(0.0, 1.0, 1.0 - traveled[n] / taper_m), MIN_WIDTH), tail_pts, tail_fwds, tail_lefts, tail_ups, tail_halves)
	# The free part: from the head's last sample through the lane's points to the tail's first.
	var ctrl := PackedVector3Array([pts[pts.size() - 1]])
	for p: Dictionary in d.get("points", []):
		var a: Array = p.p
		var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
		if p.get("height", "ground") != "set" and ground.is_valid():
			at.y = float(ground.call(at.x, at.z))
		ctrl.append(at)
	ctrl.append(tail_pts[0])
	var free := RampData._sample_open(ctrl, fwds[fwds.size() - 1], tail_fwds[0])
	var head_count := pts.size()
	for i in range(1, free.size() - 1):
		pts.append(free[i])
		fwds.append(Vector3.ZERO)
		lefts.append(Vector3.ZERO)
		ups.append(Vector3.ZERO)
		halves.append(width / 2.0)
		on_main.append(-1)
	var tail_start := pts.size()
	pts.append_array(tail_pts)
	fwds.append_array(tail_fwds)
	lefts.append_array(tail_lefts)
	ups.append_array(tail_ups)
	halves.append_array(tail_halves)
	for k in tail_main:
		on_main.append(k)
	var m := pts.size()
	for i in m:
		if on_main[i] >= 0:
			continue
		var fwd := (pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var left := Vector3.UP.cross(fwd).normalized()
		fwds[i] = fwd
		lefts[i] = left
		ups[i] = fwd.cross(left).normalized()
	track = RampData.open_strip(main, "pit", "Pit lane", width, 2, pts, fwds, lefts, ups, halves, ground)
	for i in m:
		track.lines[i] = TrackFormat.LINES.find("edges")
		track.lanes[i] = 1
	# The gores: where the lane has pulled away from the road, and where it comes back.
	gore_head = m - 1
	for i in range(head_count, m):
		if _clear_of_road(i):
			gore_head = i
			break
	gore_tail = 0
	for i in range(tail_start - 1, -1, -1):
		if _clear_of_road(i):
			gore_tail = i
			break
	if gore_tail < gore_head:
		error = "Pit lane never clears the road"
		return
	# The wall on the strip's side toward the road (its left when the lane is on the right).
	for i in m:
		var inner := TrackFormat.BARRIER_CONCRETE if wall and i >= gore_head and i <= gore_tail else TrackFormat.BARRIER_NONE
		track.barrier_l[i] = inner if side < 0.0 else TrackFormat.BARRIER_NONE
		track.barrier_r[i] = inner if side > 0.0 else TrackFormat.BARRIER_NONE
	# The mouths: the road's barrier opens from where the lane leaves to beside the gore, and
	# from beside the other gore to where it has joined.
	_mark(head_main[0], int(main.project(track.samples[gore_head], head_main[head_main.size() - 1]).index))
	_mark(int(main.project(track.samples[gore_tail], tail_main[0]).index), tail_main[tail_main.size() - 1])


## Main samples from `at_m` on for `length` m, driving.
static func _walk(main: TrackData, at_m: float, length: float) -> PackedInt32Array:
	var n := main.samples.size()
	var k := main.index_at(at_m)
	var out := PackedInt32Array([k])
	var traveled := 0.0
	while traveled < length and out.size() < n:
		var next := (k + 1) % n
		traveled += main.samples[k].distance_to(main.samples[next])
		k = next
		out.append(k)
	return out


## An attached sample at main sample `k`, `w` wide, its inner edge on the road's paved edge,
## tilted as the paving is there (an apron's slope, or the banking).
func _attached(main: TrackData, k: int, w: float, pts: PackedVector3Array, fwds: PackedVector3Array,
		lefts: PackedVector3Array, ups: PackedVector3Array, halves: PackedFloat32Array) -> void:
	var across := main.apron_left(k, side) if main.apron(k, side) > 0.0 else main.lefts[k]
	pts.append(main.paved_edge(k, side) + across * side * (w / 2.0))
	fwds.append(main.tangents[k])
	lefts.append(across)
	ups.append(main.tangents[k].cross(across).normalized())
	halves.append(w / 2.0)


## True if strip sample `i`'s inner edge is GORE_M clear of the road's paved edge.
func _clear_of_road(i: int) -> bool:
	var c := track.samples[i]
	var proj := _main.project(c)
	var k := int(proj.index)
	if absf(c.y - _main.samples[k].y) > TrackData.LIFTED_M:
		return true
	return absf(float(proj.lateral)) - track.half_l[i] - _main.edge_at(float(proj.distance), float(proj.lateral)) >= GORE_M


func _mark(k_from: int, k_to: int) -> void:
	var n := _gap.size()
	var k := k_from
	for step in n:
		_gap[k] = 1
		if k == k_to:
			return
		k = (k + 1) % n


## `count` boxes, box_m apart, between the limit lines and clear of the attached ends, centred
## there; nearest the exit first. Each sits on the outer half of the lane.
func _place_boxes(count: int) -> void:
	var from := maxf(limit_in_m, track.distances[gore_head]) + BOX_CLEAR_M
	var to := minf(limit_out_m, track.distances[gore_tail]) - BOX_CLEAR_M
	var room := maxf(to - from, 0.0)
	crowded = count * box_m > room + 0.01
	var mid := (from + to) / 2.0
	var lateral := side * width / 4.0
	for b in count:
		var d := mid + (count / 2.0 - b - 0.5) * box_m
		box_at.append(d)
		boxes.append(track.transform_at(d, lateral))
