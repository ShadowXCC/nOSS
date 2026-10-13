class_name RampData
extends RefCounted
## One highway ramp (D107): an open strip of road from a carriageway or a portal to a carriageway
## or a portal. Where it's attached to the road (the taper as it leaves, or as it merges) it reuses
## the road's own samples: its inner edge is exactly the road's outer edge and it widens from
## nothing, so the two meet without a seam or an overlap. In between it follows its own points
## (centripetal Catmull-Rom, its ends lined up with the road or the portal).

## A ramp's shoulders, inside and out, m.
const SHOULDER_M := 0.6
## Its inner barrier starts (or ends) where it's this far from the road.
const GORE_M := 2.5
## Its barriers stand this far outside its edges.
const RUNOFF_M := 0.5

var id := ""
var name := ""
## "exit" (road to portal), "entry" (portal to road), "link" (road to road: a crossover).
var kind := "exit"
var lanes := 1
var lane_m := 3.6
var taper_m := 200.0
## Speed limit, m/s.
var speed := 70.0 / 3.6
## Traffic uses it.
var traffic := true
## Its ends as in the file: {dir, at_m} or {portal}.
var from := {}
var to := {}
## Width edge to edge, m.
var width := 0.0
## The ramp's road: an open strip (samples in driving order; left is the driver's left).
var track: TrackData
## Main-road samples the start and the end are attached to, in driving order ([] if a portal).
var head_main := PackedInt32Array()
var tail_main := PackedInt32Array()
## Ramp samples where its own inner barrier starts and ends (past the gore).
var gore_head := 0
var gore_tail := 0
## The traffic lane through it, in driving order: from the road's outer lane (or the portal) to
## the road's outer lane (or the portal).
var lane_path := PackedVector3Array()
## Problems building it ("" if none).
var error := ""


## Builds ramp `r` (a full ramp dictionary, TrackFormat.RAMP_DEFAULTS merged) on `layout`'s road.
static func build(layout: HighwayLayout, r: Dictionary, ground: Callable) -> RampData:
	var ramp := RampData.new()
	ramp.id = String(r.id)
	ramp.name = String(r.get("name", ""))
	ramp.kind = String(r.kind)
	ramp.lanes = int(r.lanes)
	ramp.lane_m = float(r.lane_m)
	ramp.taper_m = float(r.taper_m)
	ramp.speed = float(r.speed_kmh) / 3.6
	ramp.traffic = bool(r.traffic)
	ramp.from = r.from
	ramp.to = r.to
	ramp.width = ramp.lanes * ramp.lane_m + 2.0 * SHOULDER_M
	ramp._build(layout, r, ground)
	return ramp


func _build(layout: HighwayLayout, r: Dictionary, ground: Callable) -> void:
	var main := layout.main
	var w := width
	# Head: attached samples (their centres, frames and widths) or a portal.
	var pts := PackedVector3Array()
	var fwds := PackedVector3Array()
	var lefts := PackedVector3Array()
	var ups := PackedVector3Array()
	var halves := PackedFloat32Array()
	var on_main := PackedInt32Array() # main sample per strip sample (-1: free)
	var lane_lat := PackedFloat32Array() # the lane's offset from the main road's centreline (attached part)
	var start_tangent := Vector3.ZERO
	var start_point := Vector3.ZERO
	if from.has("portal"):
		var portal: Dictionary = layout.portals.get(from.portal, {})
		if portal.is_empty():
			error = "No portal " + String(from.portal)
			return
		start_point = portal.p
		start_tangent = portal.forward
	else:
		head_main = layout.walk(int(from.dir), float(from.at_m), taper_m)
		if head_main.size() < 2:
			error = "Ramp too short"
			return
		var traveled := _travel(main, head_main)
		for n in head_main.size():
			var k := head_main[n]
			var u := smoothstep(0.0, 1.0, traveled[n] / taper_m)
			_attached(layout, int(from.dir), k, w * u, pts, fwds, lefts, ups, halves)
			on_main.append(k)
			lane_lat.append(lerpf(layout.lane_lateral(int(from.dir), 0), _centre_lateral(layout, int(from.dir), k), u))
		start_point = pts[pts.size() - 1]
		start_tangent = fwds[fwds.size() - 1]
	# Tail: attached samples (kept aside) or a portal.
	var tail_pts := PackedVector3Array()
	var tail_fwds := PackedVector3Array()
	var tail_lefts := PackedVector3Array()
	var tail_ups := PackedVector3Array()
	var tail_halves := PackedFloat32Array()
	var tail_lat := PackedFloat32Array()
	var end_tangent := Vector3.ZERO
	var end_point := Vector3.ZERO
	if to.has("portal"):
		var portal: Dictionary = layout.portals.get(to.portal, {})
		if portal.is_empty():
			error = "No portal " + String(to.portal)
			return
		end_point = portal.p
		end_tangent = -portal.forward
	else:
		var dir := int(to.dir)
		tail_main = layout.walk(dir, float(to.at_m) - dir * taper_m, taper_m)
		if tail_main.size() < 2:
			error = "Ramp too short"
			return
		var traveled := _travel(main, tail_main)
		for n in tail_main.size():
			var k := tail_main[n]
			var u := smoothstep(0.0, 1.0, 1.0 - traveled[n] / taper_m)
			_attached(layout, dir, k, w * u, tail_pts, tail_fwds, tail_lefts, tail_ups, tail_halves)
			tail_lat.append(lerpf(layout.lane_lateral(dir, 0), _centre_lateral(layout, dir, k), u))
		end_point = tail_pts[0]
		end_tangent = tail_fwds[0]
	# The free part: start, its own points, end, sampled every ~2 m.
	var ctrl := PackedVector3Array([start_point])
	for p: Dictionary in r.get("points", []):
		var a: Array = p.p
		var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
		if p.get("height", "ground") != "set":
			at.y = float(ground.call(at.x, at.z))
		ctrl.append(at)
	ctrl.append(end_point)
	var free := _sample_open(ctrl, start_tangent, end_tangent)
	# Join: attached head (its last sample is the free part's first point), free, attached tail.
	var head_count := pts.size()
	var first_free := 1 if head_count > 0 else 0
	var last_free := free.size() - (2 if not tail_pts.is_empty() else 1)
	for i in range(first_free, last_free + 1):
		pts.append(free[i])
		fwds.append(Vector3.ZERO)
		lefts.append(Vector3.ZERO)
		ups.append(Vector3.ZERO)
		halves.append(w / 2.0)
		on_main.append(-1)
	var tail_start := pts.size()
	pts.append_array(tail_pts)
	fwds.append_array(tail_fwds)
	lefts.append_array(tail_lefts)
	ups.append_array(tail_ups)
	halves.append_array(tail_halves)
	for k in tail_main:
		on_main.append(k)
	if pts.size() < 3:
		error = "Ramp too short"
		return
	# Frames of the free samples from their neighbours.
	var m := pts.size()
	for i in m:
		if on_main[i] >= 0:
			continue
		var fwd := (pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var left := Vector3.UP.cross(fwd).normalized()
		fwds[i] = fwd
		lefts[i] = left
		ups[i] = fwd.cross(left).normalized()
	track = _strip(layout, pts, fwds, lefts, ups, halves, ground)
	# The gores: where the ramp has pulled away from the road (or not yet come back).
	gore_head = 0
	if head_count > 0:
		gore_head = m - 1
		for i in range(head_count, m):
			if _clear_of_road(layout, i):
				gore_head = i
				break
	gore_tail = m - 1
	if not tail_pts.is_empty():
		gore_tail = 0
		for i in range(tail_start - 1, -1, -1):
			if _clear_of_road(layout, i):
				gore_tail = i
				break
	for i in m:
		var inner := TrackFormat.BARRIER_CONCRETE if i >= gore_head and i <= gore_tail else TrackFormat.BARRIER_NONE
		track.barrier_l[i] = inner
		track.barrier_r[i] = TrackFormat.BARRIER_CONCRETE
	# Mouths on the road: from the attach point to beside the gore.
	if head_count > 0:
		var gore_k := int(main.project(track.samples[gore_head], head_main[head_count - 1]).index)
		layout.mark_gap(int(from.dir), head_main[0], gore_k)
	if not tail_pts.is_empty():
		var gore_k := int(main.project(track.samples[gore_tail], tail_main[0]).index)
		layout.mark_gap(int(to.dir), gore_k, tail_main[tail_main.size() - 1])
	# The traffic lane: from the road's outer lane across the taper, along the ramp (its right
	# lane), back to the road's outer lane.
	var right := -(width / 2.0 - SHOULDER_M - lane_m / 2.0)
	for i in m:
		if i < head_count:
			lane_path.append(main.samples[on_main[i]] + main.lefts[on_main[i]] * lane_lat[i])
		elif i >= tail_start:
			lane_path.append(main.samples[on_main[i]] + main.lefts[on_main[i]] * tail_lat[i - tail_start])
		else:
			lane_path.append(track.samples[i] + track.lefts[i] * right)


## The ramp's centre at main sample `k` once fully out: just beyond the road's outer edge.
func _centre_lateral(layout: HighwayLayout, dir: int, k: int) -> float:
	var edge: float = layout.main.half_r[k] if dir > 0 else layout.main.half_l[k]
	return -dir * (edge + width / 2.0)


## An attached sample at main sample `k`: the strip `w` wide just outside the road's edge on
## direction `dir`'s side, its inner edge on the road's edge.
func _attached(layout: HighwayLayout, dir: int, k: int, w: float, pts: PackedVector3Array, fwds: PackedVector3Array,
		lefts: PackedVector3Array, ups: PackedVector3Array, halves: PackedFloat32Array) -> void:
	var main := layout.main
	var edge: float = main.half_r[k] if dir > 0 else main.half_l[k]
	pts.append(main.samples[k] + main.lefts[k] * (-dir * (edge + w / 2.0)))
	fwds.append(main.tangents[k] * dir)
	lefts.append(main.lefts[k] * dir)
	ups.append(main.ups[k])
	halves.append(w / 2.0)


## Distance driven along main samples `ks` from the first, per sample.
static func _travel(main: TrackData, ks: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for n in range(1, ks.size()):
		out.append(out[n - 1] + main.samples[ks[n - 1]].distance_to(main.samples[ks[n]]))
	return out


## True if strip sample `i`'s inner edge is GORE_M clear of the road (or above or below it).
func _clear_of_road(layout: HighwayLayout, i: int) -> bool:
	var main := layout.main
	var c := track.samples[i]
	var proj := main.project(c)
	var k := int(proj.index)
	if absf(c.y - main.samples[k].y) > TrackData.LIFTED_M:
		return true
	var edge: float = main.half_l[k] if float(proj.lateral) >= 0.0 else main.half_r[k]
	return absf(float(proj.lateral)) - track.half_l[i] - edge >= GORE_M


## Open centripetal Catmull-Rom through `ctrl`, its ends leaving along `t0` and arriving along
## `t1`, every ~2 m. Includes both end points.
static func _sample_open(ctrl: PackedVector3Array, t0: Vector3, t1: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	if n < 2:
		return ctrl
	var first := ctrl[0] - t0.normalized() * maxf(ctrl[0].distance_to(ctrl[1]), 1.0)
	var last := ctrl[n - 1] + t1.normalized() * maxf(ctrl[n - 1].distance_to(ctrl[n - 2]), 1.0)
	for i in n - 1:
		var p0 := ctrl[i - 1] if i > 0 else first
		var p3 := ctrl[i + 2] if i + 2 < n else last
		var steps := maxi(2, int(ctrl[i].distance_to(ctrl[i + 1]) / TrackData.SAMPLE_M))
		for s in steps:
			out.append(TrackData._catmull_rom(p0, ctrl[i], ctrl[i + 1], p3, float(s) / steps))
	out.append(ctrl[n - 1])
	return out


## The ramp's road as an open TrackData the road builder can build.
func _strip(layout: HighwayLayout, pts: PackedVector3Array, fwds: PackedVector3Array, lefts: PackedVector3Array,
		ups: PackedVector3Array, halves: PackedFloat32Array, ground: Callable) -> TrackData:
	var t := TrackData.new()
	var main := layout.main
	t.id = main.id + ":" + id
	t.display_name = name
	t.raw = main.raw
	t.type = "highway"
	t.closed = false
	t.kind = "road"
	t.width = width
	t.samples = pts
	t.tangents = fwds
	t.lefts = lefts
	t.ups = ups
	var m := pts.size()
	var total := 0.0
	for i in m:
		t.distances.append(total)
		if i + 1 < m:
			total += pts[i].distance_to(pts[i + 1])
	t.length = total
	for array: String in ["half_l", "half_r", "bank", "runoff_l_m", "runoff_r_m", "curvature"]:
		var a := PackedFloat32Array()
		a.resize(m)
		t.set(array, a)
	for array: String in ["surface", "runoff_l", "runoff_r", "barrier_l", "barrier_r", "lanes", "lines", "lifted", "curb_l", "curb_r", "curbs"]:
		var a := PackedByteArray()
		a.resize(m)
		t.set(array, a)
	var concrete := TrackFormat.surface_id("concrete")
	var lowest := INF
	for i in m:
		t.half_l[i] = halves[i]
		t.half_r[i] = halves[i]
		t.runoff_l_m[i] = RUNOFF_M
		t.runoff_r_m[i] = RUNOFF_M
		t.surface[i] = VehicleSim.SURFACE_ASPHALT
		t.runoff_l[i] = concrete
		t.runoff_r[i] = concrete
		t.lanes[i] = lanes
		t.lifted[i] = 1 if pts[i].y - float(ground.call(pts[i].x, pts[i].z)) > TrackData.LIFTED_M else 0
		lowest = minf(lowest, pts[i].y)
		var a := fwds[maxi(i - 1, 0)]
		var b := fwds[mini(i + 1, m - 1)]
		var ds := pts[maxi(i - 1, 0)].distance_to(pts[mini(i + 1, m - 1)])
		t.curvature[i] = asin(clampf(a.cross(b).y, -1.0, 1.0)) / maxf(ds, 0.01)
	t.kill_y = lowest - 30.0
	t.sample_seg.resize(m)
	t.seg_first = PackedInt32Array([0])
	return t
