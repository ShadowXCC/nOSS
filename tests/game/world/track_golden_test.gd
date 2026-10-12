class_name TrackGoldenTest
extends GdUnitTestSuite
## The Proving Ground stays exactly as it drove before the track editor (M6): centreline,
## curbs, the AI's line and lap time, the race grid and the built pieces' bounds, recorded from
## the noss.track/0 code (v0.5.x). The v0 file is kept as a fixture; the built-in track must
## give the same.

const V0 := "res://tests/fixtures/tracks/proving_ground_v0.json"
const BUILT_IN := "res://content/tracks/proving_ground"

const SAMPLES := 1238
const LENGTH := 2519.1613
const CURVATURE_SQ := 0.102550616
const CURBS := 514
const SECTORS := [730.0, 1540.0]
## sha256 of the line's offsets in whole millimetres (int32 little-endian).
const OFFSETS_SHA := "fc1956c5305b75ae3405c376d2cb89776c7b4606a0b7a5661616266bf381c05a"
const GT_LAP_S := 66.2835
## Race grid spots 0-11 (pole 12 m behind the line, rows 13 m, columns ±width/4): origin, forward.
const GRID := [
	[Vector3(-162.055, 0.0, -4.043), Vector3(0.9997, 0.0, 0.0257)],
	[Vector3(-168.708, 0.0, 1.787), Vector3(0.9997, 0.0, 0.0261)],
	[Vector3(-175.049, 0.0, -4.38), Vector3(0.9997, 0.0, 0.026)],
	[Vector3(-181.703, 0.0, 1.449), Vector3(0.9997, 0.0, 0.0258)],
	[Vector3(-188.048, 0.0, -4.716), Vector3(0.9997, 0.0, 0.0252)],
	[Vector3(-194.694, 0.0, 1.122), Vector3(0.9997, 0.0, 0.0242)],
	[Vector3(-201.051, 0.0, -5.031), Vector3(0.9997, 0.0, 0.0228)],
	[Vector3(-207.681, 0.0, 0.824), Vector3(0.9998, 0.0, 0.0209)],
	[Vector3(-214.06, 0.0, -5.307), Vector3(0.9998, 0.0, 0.0187)],
	[Vector3(-220.663, 0.0, 0.575), Vector3(0.9999, 0.0, 0.0159)],
	[Vector3(-227.077, 0.0, -5.522), Vector3(0.9999, 0.0, 0.0127)],
	[Vector3(-233.641, 0.0, 0.401), Vector3(1.0, 0.0, 0.0089)],
]
## Drivable and solid pieces: mesh AABB position and size.
const PIECES := {
	"Road": [Vector3(-396.604, 0.0, -8.899), Vector3(902.605, 0.0, 455.38)],
	"Curbs": [Vector3(-380.239, -0.03, -7.867), Vector3(887.3391, 0.075, 455.269)],
	"Barriers": [Vector3(-541.104, 0.0, -153.399), Vector3(1191.605, 1.6, 744.38)],
	"Skidpad": [Vector3(28.0, 0.0, 128.0), Vector3(144.0, 0.0, 144.0)],
	"Gantry": [Vector3(-150.637, 0.0, -9.249), Vector3(1.003, 7.9, 17.007)],
	"Grandstand": [Vector3(-25.142, 0.0, -32.0), Vector3(110.0, 7.8, 12.0)],
	"PitBuilding": [Vector3(-60.142, 0.0, 26.0), Vector3(120.0, 9.0, 12.0)],
}


func _check_track(t: TrackData) -> void:
	assert_int(t.samples.size()).is_equal(SAMPLES)
	assert_float(t.length).is_equal_approx(LENGTH, 0.001)
	var k2 := 0.0
	for c in t.curvature:
		k2 += c * c
	assert_float(k2).is_equal_approx(CURVATURE_SQ, 1e-7)
	var curbs := 0
	for c in t.curbs:
		curbs += c
	assert_int(curbs).is_equal(CURBS)
	assert_float(t.start_m).is_equal_approx(150.0, 1e-4)
	assert_array(Array(t.sectors_m)).is_equal(SECTORS)


func _check_line(t: TrackData) -> void:
	var line := RacingLine.for_track(t)
	var mm := PackedInt32Array()
	for o in line.offsets:
		mm.append(roundi(o * 1000.0))
	assert_str(PlatformLoader.sha256_hex(mm.to_byte_array())).is_equal(OFFSETS_SHA)
	var gt := PlatformLoader.load_official("official.track.gt").platform
	assert_float(line.lap_time(line.speed_profile(gt, 1.0))).is_equal_approx(GT_LAP_S, 0.001)


func _check_grid(spot: Callable) -> void:
	for i in GRID.size():
		var x: Transform3D = spot.call(i)
		assert_vector(x.origin).is_equal_approx(GRID[i][0], Vector3.ONE * 0.0015)
		assert_vector(x.basis.z).is_equal_approx(GRID[i][1], Vector3.ONE * 0.00015)


## Pieces built as several nodes now: the site wall is "Perimeter" (it was in "Barriers").
const MERGED := { "Barriers": ["Barriers", "Perimeter"] }


func _check_pieces(t: TrackData) -> void:
	var root := TrackBuilder.build(t)
	for piece: String in PIECES:
		var a := AABB()
		var names: Array = MERGED.get(piece, [piece])
		for k in names.size():
			var mi := root.get_node(String(names[k])) as MeshInstance3D
			a = mi.mesh.get_aabb() if k == 0 else a.merge(mi.mesh.get_aabb())
		assert_vector(a.position).override_failure_message(piece).is_equal_approx(PIECES[piece][0], Vector3.ONE * 0.002)
		assert_vector(a.size).override_failure_message(piece).is_equal_approx(PIECES[piece][1], Vector3.ONE * 0.002)
	root.free()


func test_the_v0_proving_ground() -> void:
	var t := TrackData.load_file(V0)
	_check_track(t)
	_check_line(t)
	_check_grid(func(i: int) -> Transform3D:
		return t.transform_at(t.start_m - 12.0 - (i / 2) * 13.0 - (i % 2) * 6.5, t.width / 4.0 * (1.0 if i % 2 == 0 else -1.0)))
	_check_pieces(t)


func test_the_built_in_proving_ground() -> void:
	var t := TrackLoader.load_package(BUILT_IN).track
	_check_track(t)
	_check_line(t)
	_check_pieces(t)
