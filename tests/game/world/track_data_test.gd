extends GdUnitTestSuite
## Track centreline sampling and projection.

var _track: TrackData


func before() -> void:
	_track = TrackData.load_file("res://content/tracks/proving_ground/track.json")


func test_proving_ground_is_about_2_5_km() -> void:
	assert_float(_track.length).is_between(2300.0, 2700.0)
	assert_int(_track.sectors_m.size()).is_equal(2)


func test_projection_round_trips() -> void:
	for d in [10.0, 700.0, 1500.0, 2400.0]:
		var p := _track.point_at(d) + _track.lefts[_track.index_at(d)] * 3.0
		var proj := _track.project(p)
		assert_float(proj.distance).is_equal_approx(d, 1.5)
		assert_float(proj.lateral).is_equal_approx(3.0, 0.3)


func test_transform_faces_along_track() -> void:
	var xf := _track.transform_at(100.0)
	assert_float(xf.basis.z.dot(_track.tangents[_track.index_at(100.0)])).is_greater(0.99)
	assert_vector(xf.basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	assert_float(xf.basis.x.cross(xf.basis.y).dot(xf.basis.z)).is_greater(0.99) # right-handed


func test_near_centreline_grid() -> void:
	assert_bool(_track.is_near_centreline(_track.point_at(500.0), 1.0)).is_true()
	assert_bool(_track.is_near_centreline(Vector3(100, 0, 200), 30.0)).is_false() # skidpad
