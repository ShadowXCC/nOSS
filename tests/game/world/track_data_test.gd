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


## A track from points ([x, y, z]) and per-point overrides.
static func _v1(points: Array, defaults := {}, race := {}) -> Dictionary:
	var d := TrackFormat.blank("test", "Test")
	d.road.points = points.map(func(p: Variant) -> Dictionary: return p if p is Dictionary else { "p": p })
	d.road.defaults.merge(defaults, true)
	d.race.merge(race, true)
	return d


func test_widths_differ_per_side_and_blend() -> void:
	var square := [{ "p": [0, 0, 0], "width_l": 4.0, "width_r": 9.0 }, [400, 0, 0], [400, 0, 400], [0, 0, 400]]
	var t := TrackData.from_dict(_v1(square, { "height": "set" }))
	assert_float(t.half_l[0]).is_equal_approx(4.0, 0.001)
	assert_float(t.half_r[0]).is_equal_approx(9.0, 0.001)
	var mid := t.segment_samples(0)
	var k := (mid.x + mid.y) / 2
	assert_float(t.half_l[k]).is_between(4.0, 6.0) # blending back to the default 6
	assert_float(t.half_width(0.0, 1.0)).is_equal_approx(4.0, 0.001)
	assert_float(t.half_width(0.0, -1.0)).is_equal_approx(9.0, 0.001)
	assert_float(t.edge_at(t.distances[k], -1.0)).is_greater_equal(t.half_r[k])


func test_banking_tilts_the_road() -> void:
	var oval := [[0, 0, 0], { "p": [300, 0, 0], "bank_deg": 10.0 }, { "p": [300, 0, 200], "bank_deg": 10.0 }, [0, 0, 200]]
	var t := TrackData.from_dict(_v1(oval, { "height": "set" }))
	var seg := t.segment_samples(1)
	var k := (seg.x + seg.y) / 2
	assert_float(rad_to_deg(t.bank[k])).is_equal_approx(10.0, 0.01)
	assert_float(t.ups[k].y).is_less(0.999)
	assert_float(t.lefts[k].y).is_equal_approx(sin(deg_to_rad(10.0)), 0.01) # left edge up
	var xf := t.transform_at(t.distances[k], 3.0)
	assert_float((xf.origin - t.samples[k]).dot(t.ups[k])).is_equal_approx(0.0, 0.01) # on the surface
	assert_float(xf.basis.x.cross(xf.basis.y).dot(xf.basis.z)).is_greater(0.99)


func test_a_bridge_keeps_its_branch() -> void:
	# A figure 8: along x through the origin on the ground, then along z over it 8 m up.
	var eight := [[-300, 0, 0], [0, 0, 0], [300, 0, 0], [300, 4, 300], [0, 8, 300], [0, 8, 0], [0, 8, -300], [-300, 4, -300]]
	var t := TrackData.from_dict(_v1(eight, { "height": "set" }))
	var crossing := Vector3.ZERO
	var low := t.project(crossing + Vector3.UP * 0.5)
	var high := t.project(crossing + Vector3.UP * 8.5)
	assert_float(t.point_at(low.distance).y).is_less(3.0)
	assert_float(t.point_at(high.distance).y).is_greater(5.0)
	# Walking from a hint on the bridge stays on the bridge.
	var walked := t.project(crossing + Vector3(1, 8.5, 1), high.index)
	assert_float(t.point_at(walked.distance).y).is_greater(5.0)


func test_heights_follow_the_ground_or_the_points() -> void:
	var hill := func(x: float, z: float) -> float: return 20.0 * exp(-((x - 200.0) ** 2 + z ** 2) / 20000.0)
	var square := [[0, 0, 0], [400, 0, 0], { "p": [400, 3, 400], "height": "set" }, { "p": [0, 3, 400], "height": "set" }]
	var t := TrackData.from_dict(_v1(square), hill)
	var top := t.project(Vector3(200, 0, 0))
	assert_float(t.point_at(top.distance).y).is_between(14.0, 20.5) # over the hill, smoothed
	var set_seg := t.segment_samples(2)
	var k := (set_seg.x + set_seg.y) / 2
	assert_float(t.samples[k].y).is_equal_approx(3.0, 0.05)
	# The grade stays under 15 % everywhere.
	for i in t.samples.size():
		var j := (i + 1) % t.samples.size()
		var run := Vector2(t.samples[j].x - t.samples[i].x, t.samples[j].z - t.samples[i].z).length()
		assert_float(absf(t.samples[j].y - t.samples[i].y)).is_less_equal(run * 0.15 + 0.01)


func test_v0_upgrades_to_a_valid_v1() -> void:
	var v0: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tracks/proving_ground_v0.json"))
	var v1 := TrackFormat.upgrade_v0(v0)
	assert_str(TrackFormat.validate(v1)).is_empty()
	assert_float(float(v1.road.defaults.width_l)).is_equal(6.0)
	assert_array(v1.road.points[5].p).is_equal([480.0, 0.0, 25.0]) # [x, z] became [x, y, z]
	assert_str(TrackFormat.layout_hash(v1)).is_equal(TrackFormat.layout_hash(TrackFormat.upgrade_v0(v0)))
	# Pins don't change the layout; a moved point does.
	var pinned := v1.duplicate(true)
	pinned.race.ai.pins = [{ "at_m": 500.0, "offset_m": 2.0 }]
	assert_str(TrackFormat.layout_hash(pinned)).is_equal(TrackFormat.layout_hash(v1))
	var moved := v1.duplicate(true)
	moved.road.points[3].p[0] = 310.0
	assert_str(TrackFormat.layout_hash(moved)).is_not_equal(TrackFormat.layout_hash(v1))


func test_record_keys() -> void:
	assert_str(_track.record_key()).is_equal("proving_ground")
	var t := TrackData.from_dict(_v1([[0, 0, 0], [300, 0, 0], [300, 0, 300], [0, 0, 300]], { "height": "set" }))
	assert_str(t.record_key()).starts_with("test-")
	assert_int(t.record_key().length()).is_equal(5 + 12)
