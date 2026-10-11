class_name TrackData
extends RefCounted
## A track's centreline and race setup (pre-.nosstrack format, noss.track/0). Points are
## [x, z] or [x, z, y] control points of a closed centripetal Catmull-Rom spline.

const SAMPLE_M := 2.0
const GRID_M := 40.0
## Curbs line both edges through corners tighter than this radius (and a little either side).
const CURB_CURVATURE := 1.0 / 140.0
const CURB_WIDTH := 1.1

var id := ""
var display_name := ""
var style := StyleProfile.DEFAULT
var width := 12.0
var raw := {}
## Centreline samples every ~2 m, with their along-track distance from the first point.
var samples := PackedVector3Array()
var distances := PackedFloat32Array()
var tangents := PackedVector3Array()
## Car-left unit vectors (up x forward).
var lefts := PackedVector3Array()
## Signed curvature, 1/m, + = turning left.
var curvature := PackedFloat32Array()
## 1 where the sample has curbs on both edges (TrackBuilder draws them, track limits allow them).
var curbs := PackedByteArray()
var length := 0.0
var start_m := 0.0
## Sector end distances, measured from the start line.
var sectors_m := PackedFloat32Array()
var checkpoint_spacing := 100.0
var _grid := {}


static func load_file(path: String) -> TrackData:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema") != "noss.track/0":
		push_error("Not a track file: " + path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> TrackData:
	var t := TrackData.new()
	t.raw = data
	t.id = data.get("id", "")
	t.display_name = data.get("name", t.id)
	t.style = data.get("style", StyleProfile.DEFAULT)
	t.width = float(data.get("width_m", 12.0))
	t.checkpoint_spacing = float(data.get("checkpoint_spacing_m", 100.0))
	var points := PackedVector3Array()
	for p: Array in data.points:
		points.append(Vector3(p[0], p[2] if p.size() > 2 else 0.0, p[1]))
	t._sample(points)
	t.start_m = fposmod(float(data.get("start_m", 0.0)), t.length)
	for s: float in data.get("sectors_m", []):
		t.sectors_m.append(fposmod(s - t.start_m, t.length))
	return t


## Along-track distance from the start line, wrapped to [0, length).
func from_start(distance: float) -> float:
	return fposmod(distance - start_m, length)


func index_at(distance: float) -> int:
	var d := fposmod(distance, length)
	var i := distances.bsearch(d, true) - 1
	return clampi(i, 0, samples.size() - 1)


func point_at(distance: float) -> Vector3:
	var i := index_at(distance)
	var j := (i + 1) % samples.size()
	var span := (distances[j] if j > 0 else length) - distances[i]
	return samples[i].lerp(samples[j], clampf((fposmod(distance, length) - distances[i]) / maxf(span, 0.001), 0.0, 1.0))


## Car placement at `distance`: origin on the ground, +Z along the track, +X to its left.
func transform_at(distance: float, lateral := 0.0) -> Transform3D:
	var i := index_at(distance)
	var fwd := tangents[i]
	var left := lefts[i]
	return Transform3D(Basis(left, Vector3.UP, fwd), point_at(distance) + left * lateral)


## Nearest point on the centreline. With `hint` (a sample index, e.g. last tick's) it walks
## from there to the nearest sample, which takes a step or two for a moving car.
## Returns {index, distance, lateral (+ = left), point}.
func project(pos: Vector3, hint := -1) -> Dictionary:
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


## True if any centreline sample is within `radius` (XZ) of `pos`. Uses a coarse grid.
func is_near_centreline(pos: Vector3, radius: float) -> bool:
	if _grid.is_empty():
		for i in samples.size():
			var key := _cell(samples[i])
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(i)
	var reach := int(ceil(radius / GRID_M))
	var center := _cell(pos)
	var r2 := radius * radius
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for i: int in _grid.get(center + Vector2i(dx, dz), []):
				if Vector2(samples[i].x - pos.x, samples[i].z - pos.z).length_squared() < r2:
					return true
	return false


func _d2(i: int, pos: Vector3) -> float:
	return Vector2(samples[i].x - pos.x, samples[i].z - pos.z).length_squared()


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID_M), floori(p.z / GRID_M))


func _sample(points: PackedVector3Array) -> void:
	var n := points.size()
	for i in n:
		var p0 := points[(i - 1 + n) % n]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		var p3 := points[(i + 2) % n]
		var steps := maxi(2, int(p1.distance_to(p2) / SAMPLE_M))
		for s in steps:
			samples.append(_catmull_rom(p0, p1, p2, p3, float(s) / steps))
	var m := samples.size()
	var total := 0.0
	for i in m:
		distances.append(total)
		total += samples[i].distance_to(samples[(i + 1) % m])
	length = total
	for i in m:
		var fwd := (samples[(i + 1) % m] - samples[(i - 1 + m) % m]).normalized()
		tangents.append(fwd)
		lefts.append(Vector3.UP.cross(fwd).normalized())
	for i in m:
		var a := tangents[(i - 1 + m) % m]
		var b := tangents[(i + 1) % m]
		var ds := samples[(i - 1 + m) % m].distance_to(samples[(i + 1) % m])
		curvature.append(asin(clampf(a.cross(b).y, -1.0, 1.0)) / maxf(ds, 0.01))
	_find_curbs()


## Curbs through corners: smoothed curvature over ±6 samples above CURB_CURVATURE, extended
## 5 samples either side.
func _find_curbs() -> void:
	var n := samples.size()
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for i in n:
		var sum := 0.0
		for k in range(-6, 7):
			sum += curvature[posmod(i + k, n)]
		smooth[i] = sum / 13.0
	curbs.resize(n)
	for i in n:
		var on := 0
		for k in range(-5, 6):
			if absf(smooth[posmod(i + k, n)]) > CURB_CURVATURE:
				on = 1
				break
		curbs[i] = on


## Extra width at `distance` that still counts as track: the curb, where there is one.
func curb_at(distance: float) -> float:
	return CURB_WIDTH if curbs[index_at(distance)] else 0.0


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
