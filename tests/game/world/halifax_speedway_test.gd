extends GdUnitTestSuite
## Halifax Speedway (D230): the built-in 2.5-mile superspeedway on the real Daytona layout comes
## again the same from its generator (made with the editor's commands), passes the checks, runs
## counter-clockwise, is banked 31° in the turns, 18° along the tri-oval and 3° down the
## backstretch, has its pit road and a rolling grid on the tri-oval, Lake Lloyd in its infield, a
## floodlit night, the superspeedway's rules, says where it comes from and lists as an oval.

const DIR := "res://content/tracks/halifax_speedway"
const MakeHalifax := preload("res://tools/make_halifax_speedway.gd")


func test_the_generator_makes_the_committed_track() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/manifest.json"))
	var d: TrackDraft = MakeHalifax.build()
	assert_str(d.track().layout_hash).override_failure_message("halifax_speedway changed: run tools/make_halifax_speedway.tscn").is_equal(String(manifest.layout))
	assert_array(TrackValidator.errors(TrackValidator.check(d))).is_empty()


func test_it_is_a_banked_tri_oval_of_two_and_a_half_miles() -> void:
	var t := TrackLoader.load_package(DIR).track
	assert_float(MakeHalifax.measured_m(t)).is_equal_approx(MakeHalifax.MILES_M, 15.0)
	var turning := 0.0
	for k in t.curvature:
		turning += k
	assert_float(turning).is_greater(0.0) # counter-clockwise
	var steepest := 0.0
	var gentlest := 90.0
	for b in t.bank:
		steepest = maxf(steepest, absf(rad_to_deg(b)))
		gentlest = minf(gentlest, absf(rad_to_deg(b)))
		assert_float(rad_to_deg(b)).is_less_equal(0.0) # always up to the outside
	assert_float(steepest).is_equal_approx(31.0, 0.5)
	assert_float(gentlest).is_equal_approx(3.0, 0.5) # the backstretch
	assert_float(absf(rad_to_deg(t.bank[t.index_at(t.start_m)]))).is_equal_approx(18.0, 0.5) # the tri-oval
	# Its inner edge stands on the ground: no bridge anywhere.
	assert_int(Array(t.lifted).count(1)).is_equal(0)
	assert_float(t.apron(t.index_at(t.start_m), 1.0)).is_greater(9.0) # the yellow line's apron
	assert_int(int(t.barrier_r[0])).is_equal(TrackFormat.BARRIER_SAFER)


func test_it_has_pit_road_and_a_grid_on_the_tri_oval() -> void:
	var t := TrackLoader.load_package(DIR).track
	assert_str(t.pit_error).is_empty()
	assert_float(t.pit.side).is_equal(1.0) # inside the frontstretch
	assert_int(t.pit.boxes.size()).is_greater_equal(16)
	assert_float(t.pit.speed).is_equal_approx(88.5 / 3.6, 0.01) # 55 mph
	assert_int(int(t.grid.slots)).is_equal(20)
	var g := t.grid
	for slot in int(g.slots):
		var d := t.start_m - float(g.front_m) - (slot / 2) * float(g.row_m) - (slot % 2) * float(g.row_m) * float(g.stagger)
		var bank := absf(rad_to_deg(t.bank[t.index_at(d)]))
		assert_float(bank).is_greater(10.0) # on the banked tri-oval
		assert_float(bank).is_less_equal(TrackValidator.GRID_BANK_DEG)


func test_lake_lloyd_is_in_the_infield() -> void:
	var t := TrackLoader.load_package(DIR).track
	assert_int(t.water.size()).is_equal(1)
	var lake: Dictionary = t.water[0]
	assert_str(String(lake.name)).is_equal("Lake Lloyd")
	var line := PackedVector2Array()
	for p in t.samples:
		line.append(Vector2(p.x, p.z))
	for p: Vector2 in lake.outline:
		assert_bool(Geometry2D.is_point_in_polygon(p, line)).is_true()
	# Its surface is below the infield, its bed further down.
	var pkg := TrackLoader.load_package(DIR)
	var c := (lake.outline as PackedVector2Array)[0].lerp((lake.outline as PackedVector2Array)[(lake.outline as PackedVector2Array).size() / 2], 0.5)
	assert_float(pkg.terrain.height_at(c.x, c.y)).is_less(float(lake.y) - 1.0)


func test_it_is_a_floodlit_night_with_its_rules_and_sources() -> void:
	var pkg := TrackLoader.load_package(DIR)
	var env: Dictionary = pkg.track.raw.environment
	assert_str(String(env.time)).is_equal("night")
	assert_bool(bool(env.floodlit)).is_true()
	var rules := RaceEvent.track_rules(pkg.track)
	assert_str(String(rules.start)).is_equal("rolling")
	assert_bool(bool(rules.draft)).is_true()
	assert_int(int(rules.fuel_x)).is_equal(5)
	assert_int(int(rules.tyre_x)).is_equal(2)
	assert_bool(bool(rules.pack)).is_true()
	assert_str(String(rules.plate)).is_equal("medium")
	assert_bool(bool(rules.yellow_line)).is_true()
	var items: Array = pkg.track.raw.props.items
	assert_int(items.filter(func(i: Dictionary) -> bool: return i.prop == "light_tower").size()).is_greater_equal(50)
	assert_int(items.filter(func(i: Dictionary) -> bool: return i.prop == "stadium_stand").size()).is_greater_equal(5) # 200 m each, along the tri-oval
	var scatter := (pkg.track.raw.props.scatter as Array).map(func(s: Dictionary) -> String: return s.prop)
	assert_array(scatter).contains(["camper", "palm", "cypress"])
	var attributions := " ".join(PackedStringArray(pkg.manifest.attributions))
	assert_str(attributions).contains("OpenStreetMap")
	assert_str(attributions).contains("U.S. Geological Survey")


func test_it_lists_as_an_oval_circuit() -> void:
	var circuits := TrackLibrary.list(false, false, "circuit")
	var oval: Array = circuits.filter(func(e: Dictionary) -> bool: return e.id == "halifax_speedway")
	assert_int(oval.size()).is_equal(1)
	assert_str(TrackLibrary.label(oval[0])).is_equal("Halifax Speedway · 4.1 km")
	var pkg := TrackLoader.load_package(DIR)
	assert_array(pkg.manifest.tags).contains(["oval"])
