extends GdUnitTestSuite
## Scenery roads (D212): an open road is made as the main road is (banking, widths, its ends at
## its first and last points); one running off the main road's paving stops at its edge without
## overlapping it; one crossing it comes in two pieces; they build with collision, shape the
## ground, count in the layout hash, pass the schema and come and go in the editor with undo.

const Fixtures := preload("res://tests/game/world/road_builder_test.gd")


## A scenery road on the banked oval fixture: from its level apron (4 m past the inner edge, on the
## top straight) into the infield.
func _with_infield_road() -> Dictionary:
	var d := Fixtures.oval_track()
	d.roads = [{ "name": "Infield", "defaults": { "width_l": 4.0, "width_r": 4.0, "height": "ground", "curb_l": "off", "curb_r": "off",
		"runoff_l_m": 0.0, "runoff_r_m": 0.0 },
		"points": [{ "p": [-80.0, 0.0, 137.0] }, { "p": [-40.0, 0.0, 118.0] }, { "p": [-10.0, 0.0, 80.0] }, { "p": [0.0, 0.0, 40.0] }] }]
	return d


func _terrain() -> TerrainData:
	return TerrainData.around(Rect2(-400, -200, 800, 400), 100.0)


func test_an_open_road_is_made_as_the_road_is() -> void:
	var main := TrackData.from_dict(Fixtures.loop_track(3000.0))
	var road := { "defaults": { "width_l": 5.0, "width_r": 3.0, "height": "set" },
		"points": [{ "p": [0.0, 0.0, 0.0] }, { "p": [100.0, 2.0, 0.0], "bank_deg": 10.0 }, { "p": [200.0, 0.0, 30.0] }] }
	var t := TrackData.open_road(main, road, Callable())
	assert_bool(t.closed).is_false()
	assert_vector(t.samples[0]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_vector(t.samples[t.samples.size() - 1]).is_equal_approx(Vector3(200.0, 0.0, 30.0), Vector3.ONE * 0.001)
	assert_float(t.length).is_between(200.0, 215.0)
	assert_float(t.distances[t.distances.size() - 1]).is_equal_approx(t.length, 0.001)
	var mid := t.index_at(t.project(Vector3(100.0, 2.0, 0.0)).distance)
	assert_float(rad_to_deg(t.bank[mid])).is_equal_approx(10.0, 0.5)
	assert_float(t.half_l[mid]).is_equal(5.0)
	assert_float(t.half_r[mid]).is_equal(3.0)


func test_a_road_off_the_paving_stops_at_its_edge() -> void:
	var terrain := _terrain()
	var t := TrackData.from_dict(_with_infield_road(), terrain.ground_height())
	assert_int(t.scenery.size()).is_equal(1)
	var piece := t.scenery[0]
	assert_str(piece.display_name).is_equal("Infield")
	# Its first samples (both edges on the apron) are cut; no edge it keeps is on the oval's paving.
	var first_edges := [piece.samples[0] + piece.lefts[0] * piece.half_l[0], piece.samples[0] - piece.lefts[0] * piece.half_r[0]]
	assert_float(piece.samples[0].distance_to(Vector3(-80.0, 0.0, 137.0))).is_greater(2.0)
	for i in piece.samples.size():
		for side: float in [1.0, -1.0]:
			var e := piece.samples[i] + piece.lefts[i] * side * (piece.half_l[i] if side > 0.0 else piece.half_r[i])
			var proj := t.project(e)
			assert_float(absf(float(proj.lateral))).override_failure_message("sample %d edge %s at %.2f" % [i, side, float(proj.lateral)]) \
				.is_greater_equal(t.edge_at(float(proj.distance), float(proj.lateral)) - 0.05)
	# Where it leaves the apron its edge is on the apron's (18 m in from the centre), level with it.
	var nearest := INF
	for e: Vector3 in first_edges:
		var proj := t.project(e)
		nearest = minf(nearest, absf(absf(float(proj.lateral)) - 18.0))
		assert_float(e.y).is_equal_approx(0.0, 0.1)
	assert_float(nearest).is_less(0.3)
	# It ends at its last point.
	assert_vector(piece.samples[piece.samples.size() - 1]).is_equal_approx(Vector3(0.0, 0.0, 40.0), Vector3(0.01, 0.1, 0.01))


func test_a_road_across_the_track_comes_in_two_pieces() -> void:
	var d := Fixtures.oval_track(6.0, 0.0, 0.0) # flat, no apron
	d.roads = [{ "defaults": { "width_l": 3.0, "width_r": 3.0, "height": "ground", "curb_l": "off", "curb_r": "off" },
		"points": [{ "p": [10.0, 0.0, 100.0] }, { "p": [10.0, 0.0, 150.0] }, { "p": [10.0, 0.0, 195.0] }] }]
	var t := TrackData.from_dict(d, _terrain().ground_height())
	assert_int(t.scenery.size()).is_equal(2)
	var before := t.scenery[0]
	var after := t.scenery[1]
	assert_float(before.samples[before.samples.size() - 1].z).is_between(140.0, 145.0) # stops at the inner edge (144)
	assert_float(after.samples[0].z).is_between(155.0, 160.0) # and starts again past the outer one (156)
	assert_str(before.display_name).is_equal("Road 1")


func test_scenery_roads_build_shape_the_ground_and_count_in_the_hash() -> void:
	var terrain := _terrain()
	var d := _with_infield_road()
	var t := TrackData.from_dict(d, terrain.ground_height())
	var root := Node3D.new()
	add_child(root)
	RoadBuilder.new(t, terrain).build_all(root)
	var scenery := root.get_node_or_null(^"Scenery/Piece_0")
	assert_object(scenery).is_not_null()
	assert_object(scenery.get_node_or_null(^"Road")).is_not_null()
	assert_int(scenery.find_children("*", "CollisionShape3D", true, false).size()).is_greater(0)
	root.free()
	# The ground: its samples after the road's (and the closing copy).
	var rows := TerrainData.road_samples(t).size() / 9
	assert_int(rows).is_equal(t.samples.size() + 1 + t.scenery[0].samples.size())
	assert_int(TerrainData.road_aprons(t).size()).is_equal(rows * 6)
	# The hash and the schema.
	var plain := Fixtures.oval_track()
	assert_str(TrackFormat.layout_hash(d)).is_not_equal(TrackFormat.layout_hash(plain))
	assert_str(TrackFormat.validate(JSON.parse_string(JSON.stringify(d)))).is_empty()
	var bad := _with_infield_road()
	bad.roads[0].points = [{ "p": [0.0, 0.0, 0.0] }]
	assert_str(TrackFormat.validate(JSON.parse_string(JSON.stringify(bad)))).is_not_empty()


func test_the_editor_adds_and_removes_them_with_undo() -> void:
	var d := TrackDraft.blank("Scenery")
	d.layout.road = Fixtures.oval_track().road
	d.layout.race.start_m = 100.0
	d._track = null
	var road: Dictionary = _with_infield_road().roads[0]
	d.add_road(road)
	assert_int((d.layout.roads as Array).size()).is_equal(1)
	assert_int(d.track().scenery.size()).is_equal(1)
	d.history.undo_last()
	assert_bool(d.layout.has("roads")).is_false()
	assert_int(d.track().scenery.size()).is_equal(0)
	d.history.redo_next()
	assert_int(d.track().scenery.size()).is_equal(1)
	d.remove_road(0)
	assert_bool(d.layout.has("roads")).is_false()
	assert_int(d.track().scenery.size()).is_equal(0)
