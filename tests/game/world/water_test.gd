extends GdUnitTestSuite
## Water in track files (D224): a lake's outline and level are read and hashed with the layout
## (older tracks hash as before), it builds as a surface over a catch volume, the editor keeps it,
## and a car that goes in is sent back to the road.

const DIR := "user://tests/water"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


## The oval template with a lake in its infield (an L, so it isn't convex), its surface just over
## the flat ground (-0.03) so a car on the grass there is in it.
static func _with_lake() -> TrackDraft:
	var d := TrackTemplates.make("oval")
	d.layout.water = [{ "name": "Pond", "y": 0.2, "points": [[-60, -30], [60, -30], [60, 0], [0, 0], [0, 30], [-60, 30]] }]
	d._track = null
	return d


func test_a_lake_is_read_and_counts_in_the_layout() -> void:
	var plain := TrackTemplates.make("oval")
	var d := _with_lake()
	var t := d.track()
	assert_int(t.water.size()).is_equal(1)
	assert_str(String(t.water[0].name)).is_equal("Pond")
	assert_float(float(t.water[0].y)).is_equal(0.2)
	assert_int((t.water[0].outline as PackedVector2Array).size()).is_equal(6)
	assert_bool(t.water_at(-30.0, 15.0).is_empty()).is_false()
	assert_bool(t.water_at(30.0, 15.0).is_empty()).is_true() # the L's missing corner
	assert_str(t.layout_hash).is_not_equal(plain.track().layout_hash)
	plain.layout.water = []
	plain._track = null
	assert_str(plain.track().layout_hash).is_equal(TrackTemplates.make("oval").track().layout_hash)


func test_a_lake_builds_a_surface_over_a_catch_volume() -> void:
	var t := _with_lake().track()
	var root := TrackBuilder.build(t)
	var lake := root.get_node("Lake0") as MeshInstance3D
	var box := lake.mesh.get_aabb()
	assert_float(box.position.y).is_equal_approx(0.2, 0.001)
	assert_float(box.size.x).is_equal_approx(120.0, 0.01)
	assert_float(box.size.z).is_equal_approx(60.0, 0.01)
	var faces := lake.mesh.get_faces()
	assert_int(faces.size()).is_equal(4 * 3) # six corners, four triangles
	for k in range(0, faces.size(), 3): # each faces up (Godot's fronts are clockwise)
		assert_float((faces[k + 1] - faces[k]).cross(faces[k + 2] - faces[k]).y).is_less(0.0)
	var area := root.get_node("Water0") as Area3D
	assert_bool(area.has_meta(&"noss_water")).is_true()
	assert_int(area.collision_mask & Vehicle.LAYER_VEHICLES).is_not_equal(0)
	assert_int(area.get_child_count()).is_equal(4)
	root.free()
	# A dedicated server has the catch volume and no surface.
	var bare := TrackBuilder.build(t, null, { "visual": false })
	assert_object(bare.get_node_or_null("Lake0")).is_null()
	assert_object(bare.get_node_or_null("Water0")).is_not_null()
	bare.free()


func test_the_editor_keeps_a_lake() -> void:
	var d := _with_lake()
	d.flip_direction()
	assert_array(d.layout.water).is_equal(_with_lake().layout.water)
	var round_trip := TrackData.from_dict(JSON.parse_string(JSON.stringify(d.layout)))
	assert_int(round_trip.water.size()).is_equal(1)


func test_the_checks_keep_water_off_the_road() -> void:
	var d := _with_lake()
	var texts := func(of: TrackDraft) -> Array: return TrackValidator.check(of).map(func(p: Dictionary) -> String: return p.level + ": " + p.text)
	assert_array(texts.call(d).filter(func(x: String) -> bool: return "ater" in x)).is_empty()
	# Out over the top straight (the oval's road crosses x = 0 at z = ±110).
	d.layout.water[0].points = [[-60, -30], [60, -30], [60, 0], [0, 0], [0, 130], [-60, 130]]
	d._track = null
	assert_array(texts.call(d)).contains(["error: Water on the road"])
	d = _with_lake()
	d.add_prop({ "prop": "billboard", "p": [-30.0, 0.0, 15.0], "yaw_deg": 0.0, "scale": 1.0 })
	assert_array(texts.call(d)).contains(["warning: Prop in the water"])


func test_a_car_in_the_lake_is_back_on_the_road() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/lake.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(_with_lake().layout))
	f.close()
	Players.clear()
	var s := TrackSession.new()
	s.track_path = path
	s.platform_id = "official.track.gt"
	s.event = RaceEvent.free_drive()
	add_child(s)
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle:
			break
		await get_tree().physics_frame
	var r: Racer = s.players[0]
	for i in 60:
		await get_tree().physics_frame
	r.vehicle.reset_to(Transform3D(Basis(), Vector3(-30.0, 1.5, 15.0)))
	var back := false
	for i in 240:
		await get_tree().physics_frame
		var p := r.vehicle.global_position
		if s.track.water_at(p.x, p.z).is_empty() and absf(r.lateral) < s.track.width:
			back = true
			break
	assert_bool(back).override_failure_message("still in the lake at %s" % r.vehicle.global_position).is_true()
	s.queue_free()
	await get_tree().physics_frame
