class_name RoadWindow
extends TrackData
## The stretch of the endless road that exists now (D154): an open strip made of NossRoadGen's
## chunks, added ahead and dropped behind as players drive. Its arrays are in scene coordinates
## (the floating origin's), with `distances` from its own first sample; every distance its API
## takes or gives (project, index_at, point_at, transform_at) is the road's absolute distance,
## 2 m per generator sample from the road's start, as a 64-bit float. So a racer's distance never
## jumps when the window moves; only sample indices do (trimmed() says by how many).

signal trimmed(samples: int)

## Lanes are this far in from the centreline, each side.
const SHOULDER_M := 0.6
## The arrays that hold a value per sample (appended and trimmed together).
const PER_SAMPLE := ["samples", "tangents", "lefts", "ups", "curvature", "curbs", "curb_l", "curb_r", "half_l", "half_r",
	"bank", "surface", "runoff_l", "runoff_r", "runoff_l_m", "runoff_r_m", "barrier_l", "barrier_r", "lanes", "lines", "lifted",
	"sample_seg"]

## The absolute distance of sample 0, m; and its index in the generator's samples.
var offset_m := 0.0
var first_index := 0
## The chunk numbers in the window, oldest first.
var chunks := PackedInt32Array()
## Per sample: the biome (NossRoadGen order), the next one and its weight; traffic's speed in each
## lane (m/s; up: toward higher distances) and the time to here at that speed (s, 64-bit).
var biome := PackedByteArray()
var biome2 := PackedByteArray()
var blend := PackedFloat32Array()
var speed_up := PackedFloat32Array()
var speed_down := PackedFloat32Array()
var time_up := PackedFloat64Array()
var time_down := PackedFloat64Array()
## Natural ground at the centre (m, world height).
var ground := PackedFloat32Array()
const EXTRA := ["biome", "biome2", "blend", "speed_up", "speed_down", "time_up", "time_down", "ground"]


func _init() -> void:
	closed = false
	type = "endless"
	kind = "road"
	id = "endless"
	display_name = "Endless"
	kill_y = -INF
	start_m = 0.0
	length = 0.0


## A chunk from NossRoadGen.chunk() as an open strip of its own (CHUNK + 1 samples), in the scene
## of an origin at world (ox, oz). Its distances run from 0; `index` is its chunk number.
static func chunk_track(chunk: Dictionary, ox: float, oz: float, index: int) -> RoadWindow:
	var t := RoadWindow.new()
	var x: PackedFloat64Array = chunk.x
	var y: PackedFloat64Array = chunk.y
	var z: PackedFloat64Array = chunk.z
	var heading: PackedFloat64Array = chunk.heading
	var grade: PackedFloat32Array = chunk.grade
	var bank_deg: PackedFloat32Array = chunk.bank
	var lane: PackedFloat32Array = chunk.lane
	var lifted_b: PackedByteArray = chunk.lifted
	var bl: PackedByteArray = chunk.barrier_l
	var br: PackedByteArray = chunk.barrier_r
	var n := x.size()
	for name: String in PER_SAMPLE:
		var a: Variant = t.get(name)
		a.resize(n)
		t.set(name, a)
	t.distances.resize(n)
	var armco := TrackFormat.barrier_id("armco")
	var all_lines := TrackFormat.LINES.find("all")
	for i in n:
		t.samples[i] = Vector3(x[i] - ox, y[i], z[i] - oz)
		t.distances[i] = SAMPLE_M * i
		var fwd := Vector3(sin(heading[i]), grade[i], cos(heading[i])).normalized()
		t.tangents[i] = fwd
		var left := Vector3.UP.cross(fwd).normalized()
		var up := fwd.cross(left)
		# The generator banks into a bend with the left edge lower; here + raises the left edge.
		var b := -deg_to_rad(bank_deg[i])
		t.bank[i] = b
		if b != 0.0:
			var banked := left * cos(b) + up * sin(b)
			up = fwd.cross(banked)
			left = banked
		t.lefts[i] = left
		t.ups[i] = up.normalized()
		var half := lane[i] + SHOULDER_M
		t.half_l[i] = half
		t.half_r[i] = half
		t.surface[i] = VehicleSim.SURFACE_ASPHALT
		t.runoff_l[i] = VehicleSim.SURFACE_GRASS
		t.runoff_r[i] = VehicleSim.SURFACE_GRASS
		t.barrier_l[i] = armco if bl[i] else TrackFormat.BARRIER_NONE
		t.barrier_r[i] = armco if br[i] else TrackFormat.BARRIER_NONE
		t.lanes[i] = 2
		t.lines[i] = all_lines
		t.lifted[i] = lifted_b[i]
		t.sample_seg[i] = index
	t.curvature = chunk.curvature
	t.biome = chunk.biome
	t.biome2 = chunk.biome2
	t.blend = chunk.blend
	t.speed_up = chunk.speed_up
	t.speed_down = chunk.speed_down
	t.time_up = chunk.time_up
	t.time_down = chunk.time_down
	t.ground = chunk.ground
	t.seg_first = PackedInt32Array([0])
	t.length = SAMPLE_M * (n - 1)
	t.first_index = int(chunk.first)
	t.offset_m = SAMPLE_M * t.first_index
	t.chunks = PackedInt32Array([index])
	t.width = 2.0 * (lane[0] + SHOULDER_M)
	return t


## The absolute distance of the window's last sample.
func end_m() -> float:
	return offset_m + length


func is_empty() -> bool:
	return samples.is_empty()


## Adds a chunk (chunk_track) at the far end; it must start where the window ends.
func append(c: RoadWindow) -> void:
	if is_empty():
		for name: String in PER_SAMPLE + EXTRA:
			set(name, c.get(name).duplicate())
		offset_m = c.offset_m
		first_index = c.first_index
		width = c.width
	else:
		assert(c.first_index == first_index + samples.size() - 1, "chunks out of order")
		for name: String in PER_SAMPLE + EXTRA:
			var a: Variant = get(name)
			a.append_array(c.get(name).slice(1)) # its first sample is the window's last
			set(name, a)
	chunks.append(c.chunks[0])
	_reindex()


## Drops `count` samples from the near end (keeping at least two). Racers' sample hints go down by
## the same: see trimmed.
func trim_front(count: int) -> void:
	count = clampi(count, 0, samples.size() - 2)
	if count <= 0:
		return
	for name: String in PER_SAMPLE + EXTRA:
		var a: Variant = get(name)
		set(name, a.slice(count))
	first_index += count
	offset_m = SAMPLE_M * first_index
	while chunks.size() > 1 and (chunks[1] * NossRoadGen.chunk_samples()) <= first_index:
		chunks.remove_at(0)
	_reindex()
	trimmed.emit(count)


## The world moved (floating origin): every sample moves by `delta`.
func shift(delta: Vector3) -> void:
	for i in samples.size():
		samples[i] += delta
	_grid.clear()


func _reindex() -> void:
	var n := samples.size()
	distances.resize(n)
	for i in n:
		distances[i] = SAMPLE_M * i
	length = SAMPLE_M * maxi(n - 1, 0)
	seg_first = PackedInt32Array([0])
	_grid.clear()


# --- the API in absolute distances --------------------------------------------------------------


func from_start(distance: float) -> float:
	return distance


func index_at(distance: float) -> int:
	return clampi(floori((distance - offset_m) / SAMPLE_M), 0, maxi(samples.size() - 1, 0))


func point_at(distance: float) -> Vector3:
	if samples.is_empty():
		return Vector3.ZERO
	var local := clampf(distance - offset_m, 0.0, length)
	var i := mini(floori(local / SAMPLE_M), samples.size() - 1)
	var k := mini(i + 1, samples.size() - 1)
	return samples[i].lerp(samples[k], clampf((local - SAMPLE_M * i) / SAMPLE_M, 0.0, 1.0))


func project(pos: Vector3, hint := -1) -> Dictionary:
	if samples.size() < 2:
		return { "index": 0, "distance": offset_m, "lateral": 0.0, "point": pos }
	var r := _project_open(pos, hint)
	r.distance = float(r.distance) + offset_m
	return r


## The sample index of an absolute distance, or -1 outside the window.
func index_of(distance: float) -> int:
	var i := floori((distance - offset_m) / SAMPLE_M)
	return i if i >= 0 and i < samples.size() else -1
