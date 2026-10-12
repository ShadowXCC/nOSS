extends GdUnitTestSuite
## Track validation (EDT-07): the built-in track and the templates pass; each check finds the
## problem it's for, and says where. The AI line bends through pins and goes faster round a
## banked corner.

const DIR := "user://tests/track_validator"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Settings.use_folder("user://")


func _texts(d: TrackDraft, level := "") -> Array:
	return TrackValidator.check(d).filter(func(p: Dictionary) -> bool: return level == "" or p.level == level).map(func(p: Dictionary) -> String: return p.text)


func _has(found: Array, start: String) -> bool:
	return found.any(func(text: String) -> bool: return text.begins_with(start))


func test_the_proving_ground_and_templates_pass() -> void:
	var pg := TrackDraft.from_package(TrackLoader.load_package("res://content/tracks/proving_ground"))
	assert_array(_texts(pg, "error")).is_empty()
	for id in ["oval", "circuit", "figure8"]:
		assert_array(_texts(TrackTemplates.make(id), "error")).override_failure_message(id + ": " + str(_texts(TrackTemplates.make(id)))).is_empty()


func test_too_short_and_no_start() -> void:
	assert_array(_texts(TrackTemplates.make("empty"))).contains(["Track too short"])
	var d := TrackTemplates.make("oval")
	d.layout.race.erase("start_m")
	d._track = null
	assert_array(_texts(d, "error")).contains(["No start line"])


func test_crossing_without_a_bridge_overlaps() -> void:
	var d := TrackTemplates.make("figure8")
	d.copy_to_all("height", "ground")
	var errors := _texts(d, "error")
	assert_bool(_has(errors, "Road overlaps at")).override_failure_message(str(errors)).is_true()
	# Where: the crossing at the origin.
	var found: Array = TrackValidator.check(d).filter(func(p: Dictionary) -> bool: return String(p.text).begins_with("Road overlaps"))
	assert_float(Vector2((found[0].point as Vector3).x, (found[0].point as Vector3).z).length()).is_less(40.0)


func test_road_wider_than_its_corners_is_too_tight() -> void:
	var d := TrackTemplates.make("oval")
	d.copy_to_all("width_l", 60.0)
	d.copy_to_all("width_r", 60.0)
	assert_bool(_has(_texts(d, "error"), "Too tight at")).is_true()


func test_a_step_is_a_gap_and_a_climb_too_steep() -> void:
	var d := TrackTemplates.make("oval")
	# A point 2 m past point 0, 10 m up: a wall.
	var p0: Array = d.points()[0].p
	d.add_point(1, Vector3(p0[0] - 0.5, 10.0, p0[2] + 2.0), { "height": "set" })
	d.set_attr(PackedInt32Array([0]), "height", "set")
	assert_bool(_has(_texts(d, "error"), "Gap at")).is_true()
	var hill := TrackTemplates.make("oval")
	var p3: Array = hill.points()[3].p
	hill.move_point(3, Vector3(p3[0], 20.0, p3[2]))
	hill.set_attr(PackedInt32Array([3]), "height", "set")
	var found := _texts(hill)
	assert_bool(_has(found, "Too steep at")).override_failure_message(str(found)).is_true()
	assert_bool(_has(_texts(hill, "error"), "Gap at")).is_false()


func test_grid_checks() -> void:
	var d := TrackTemplates.make("oval")
	d.set_race("grid/slots", 1)
	assert_array(_texts(d, "error")).contains(["Grid too small"])
	d.set_race("grid/slots", 8)
	assert_array(_texts(d, "warning")).contains(["Grid too small"])
	d.set_race("grid/slots", 40)
	d.set_race("grid/row_m", 30.0)
	assert_array(_texts(d, "error")).contains(["Grid too long"])
	d.set_race("grid/row_m", 13.0)
	d.copy_to_all("bank_deg", 10.0)
	assert_array(_texts(d, "error")).contains(["Grid off the road"])


func test_sectors_out_of_order() -> void:
	var d := TrackTemplates.make("oval")
	var start := float(d.layout.race.start_m)
	d.set_race("sectors_m", [start + 500.0, start + 450.0])
	assert_array(_texts(d, "error")).contains(["Sector 2 out of order"])
	d.set_race("sectors_m", [start + 50.0])
	assert_array(_texts(d, "error")).contains(["Sector 1 out of order"])


func test_road_off_the_terrain() -> void:
	var d := TrackTemplates.make("oval")
	d.set_terrain(TerrainData.create(Vector2(-128, -128), Vector2i(1, 1)))
	assert_bool(_has(_texts(d, "error"), "Road leaves the terrain at")).is_true()


func test_props_on_the_road() -> void:
	var d := TrackTemplates.make("oval")
	var t := d.track()
	var at := t.samples[200]
	# A tent by the left edge leaves room to pass.
	d.add_prop({ "prop": "tent", "p": TrackDraft._vec(at + t.lefts[200] * 5.0), "yaw_deg": 0.0, "scale": 1.0, "ground": true })
	assert_array(_texts(d, "warning")).contains(["Prop on the road"])
	assert_bool(_has(_texts(d, "error"), "Road blocked")).is_false()
	# A grandstand across the road blocks it.
	var yaw := rad_to_deg(atan2(t.lefts[200].x, t.lefts[200].z))
	d.add_prop({ "prop": "grandstand", "p": TrackDraft._vec(t.samples[300]), "yaw_deg": yaw, "scale": 1.0, "ground": true, "size": [13.0, 9.9, 40.0] })
	assert_bool(_has(_texts(d, "error"), "Road blocked at")).is_true()
	# Flat trees don't stop a car; pines do.
	var e := TrackTemplates.make("oval")
	for prop in ["tree_billboard", "tree_pine"]:
		e.set_scatter_live(prop, [at.x, at.z, 0.0, 1.0])
		e.scatter_stroke(prop, [], [at.x, at.z, 0.0, 1.0])
		if prop == "tree_billboard":
			assert_array(_texts(e)).not_contains(["Prop on the road"])
	assert_array(_texts(e)).contains(["Prop on the road"])


func test_a_road_too_narrow_for_the_ai() -> void:
	var d := TrackTemplates.make("oval")
	d.copy_to_all("width_l", 1.0)
	d.copy_to_all("width_r", 1.0)
	assert_bool(_has(_texts(d, "error"), "AI line error at")).is_true()


func test_personal_use_is_a_note() -> void:
	var d := TrackTemplates.make("oval")
	d.set_info("license", "personal-use-only")
	var found := TrackValidator.check(d)
	assert_array(found.filter(func(p: Dictionary) -> bool: return p.level == "info").map(func(p: Dictionary) -> String: return p.text)).contains(["Personal-use tracks stay offline"])
	assert_array(TrackValidator.errors(found)).is_empty()


func test_pins_move_the_line_and_stay_on_the_road() -> void:
	var d := TrackTemplates.make("circuit")
	var free := RacingLine.solve(d.track())
	var at := 900.0
	var want := free.offset_at(at) + (3.0 if free.offset_at(at) < 0.0 else -3.0)
	d.set_race("ai/pins", [{ "at_m": at, "offset_m": want }])
	var pinned := RacingLine.solve(d.track())
	assert_float(pinned.offset_at(at)).is_equal_approx(want, 0.05)
	# Nearby, the line bends toward the pin; far away it's as before.
	assert_float(absf(pinned.offset_at(at + 20.0) - free.offset_at(at + 20.0))).is_greater(0.5)
	assert_float(absf(pinned.offset_at(at + 1200.0) - free.offset_at(at + 1200.0))).is_less(0.3)
	# A pin past the edge is held at the corridor.
	d.set_race("ai/pins", [{ "at_m": at, "offset_m": 40.0 }])
	var clamped := RacingLine.solve(d.track())
	assert_float(clamped.offset_at(at)).is_equal_approx(clamped.corridor(at).x, 0.05)
	assert_array(_texts(d, "error")).is_empty()
	# Pins aren't the layout: records stay.
	assert_str(d.track().layout_hash).is_equal(TrackTemplates.make("circuit").track().layout_hash)


func test_banking_into_a_corner_is_faster() -> void:
	var d := TrackTemplates.make("oval")
	var gt := PlatformLoader.load_official(TrackValidator.REFERENCE_PLATFORM).platform
	var flat_line := RacingLine.solve(d.track())
	assert_bool(flat_line.flat).is_true()
	# The oval turns one way all along: bank so the outside edge is the higher one.
	var turns_left := flat_line.curvature[0] > 0.0
	d.copy_to_all("bank_deg", -12.0 if turns_left else 12.0)
	var banked_line := RacingLine.solve(d.track())
	assert_bool(banked_line.flat).is_false()
	assert_float(banked_line.bank_in[0]).is_greater(0.0)
	var flat_v := _slowest(flat_line.speed_profile(gt))
	var banked_v := _slowest(banked_line.speed_profile(gt))
	assert_float(banked_v).is_greater(flat_v * 1.05)
	assert_float(banked_line.lap_time(banked_line.speed_profile(gt))).is_less(flat_line.lap_time(flat_line.speed_profile(gt)))


func test_a_crest_slows_the_car() -> void:
	var d := TrackTemplates.make("oval")
	var gt := PlatformLoader.load_official(TrackValidator.REFERENCE_PLATFORM).platform
	var before := RacingLine.solve(d.track())
	# A hump on the first straight.
	var p: Array = d.points()[3].p
	d.move_point(3, Vector3(p[0], 6.0, p[2]))
	d.set_attr(PackedInt32Array([3]), "height", "set")
	var after := RacingLine.solve(d.track())
	assert_bool(after.flat).is_false()
	var top := after.track.index_at(after.track.distances[after.track.seg_first[3]])
	assert_float(after.crest[top]).is_greater(0.0)
	assert_float(after.lap_time(after.speed_profile(gt))).is_greater(before.lap_time(before.speed_profile(gt)))


func _slowest(v: PackedFloat32Array) -> float:
	var m := INF
	for s in v:
		m = minf(m, s)
	return m
