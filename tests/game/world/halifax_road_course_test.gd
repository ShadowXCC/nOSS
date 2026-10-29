extends GdUnitTestSuite
## Halifax Road Course (D231): the built-in sports-car course through Halifax Speedway's infield
## comes again the same from its generator and passes the checks; it runs counter-clockwise, about
## 5.8 km with its 12 corners; its banked sections are the oval's own; it has pit road, Lake Lloyd,
## a floodlit night and its rules; the oval it leaves is scenery (D212), and the speedway shows its
## infield and chicane.

const DIR := "res://content/tracks/halifax_road_course"
const OVAL := "res://content/tracks/halifax_speedway"
const MakeRoadCourse := preload("res://tools/make_halifax_road_course.gd")
const Corners := preload("res://tools/make_piedmont_road_course.gd")


func test_the_generator_makes_the_committed_track() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/manifest.json"))
	var d: TrackDraft = MakeRoadCourse.build()
	assert_str(d.track().layout_hash).override_failure_message("halifax_road_course changed: run tools/make_halifax_road_course.tscn").is_equal(String(manifest.layout))
	assert_array(TrackValidator.errors(TrackValidator.check(d))).is_empty()


func test_it_is_the_road_course_round_the_infield() -> void:
	var pkg := TrackLoader.load_package(DIR)
	assert_bool(pkg.ok()).override_failure_message(pkg.error).is_true()
	var t := pkg.track
	# The real lap is 3.56 miles (5.73 km); its oval sections run on the oval's centre, a little out.
	assert_float(t.length).is_between(5700.0, 5850.0)
	var turning := 0.0
	for k in t.curvature:
		turning += k
	assert_float(turning).is_greater(0.0) # counter-clockwise
	assert_int(Corners.corners(t)).is_equal(12)
	var steepest := 0.0
	for b in t.bank:
		steepest = maxf(steepest, absf(rad_to_deg(b)))
	assert_float(steepest).is_equal_approx(31.0, 0.5)
	# Its banked sections are the oval's own control points.
	var oval: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OVAL + "/track.json"))
	var oval_points := {}
	for p: Dictionary in oval.road.points:
		oval_points[str(p.p)] = p
	var shared := 0
	for p: Dictionary in t.raw.road.points:
		if oval_points.has(str(p.p)):
			shared += 1
			assert_float(float(p.bank_deg)).is_equal(float(oval_points[str(p.p)].bank_deg))
	assert_int(shared).is_greater(40)
	# The infield is flat.
	assert_int(t.raw.road.points.filter(func(p: Dictionary) -> bool: return not p.has("bank_deg")).size()).is_greater(50)


func test_it_has_pit_road_the_lake_lights_and_its_rules() -> void:
	var pkg := TrackLoader.load_package(DIR)
	var t := pkg.track
	assert_str(t.pit_error).is_empty()
	assert_int(t.pit.boxes.size()).is_greater_equal(16)
	assert_bool(t.pit.crowded).is_false()
	assert_int(t.water.size()).is_equal(1)
	assert_str(String(t.raw.environment.time)).is_equal("night")
	assert_bool(bool(t.raw.environment.floodlit)).is_true()
	var rules := RaceEvent.track_rules(t)
	assert_str(String(rules.start)).is_equal("rolling")
	assert_bool(bool(rules.draft)).is_true()
	assert_int(int(rules.fuel_x)).is_equal(5)
	assert_int(int(rules.tyre_x)).is_equal(2)
	assert_bool(bool(rules.pack)).is_false()
	assert_str(String(rules.plate)).is_equal("off")
	assert_bool(bool(rules.yellow_line)).is_false()
	var attributions := " ".join(PackedStringArray(pkg.manifest.attributions))
	assert_str(attributions).contains("OpenStreetMap")
	var circuits := TrackLibrary.list(false, false, "circuit").map(func(e: Dictionary) -> String: return e.id)
	assert_array(circuits).contains(["halifax_road_course"])


func test_each_track_shows_the_others_roads() -> void:
	var t := TrackLoader.load_package(DIR).track
	var names := (t.raw.roads as Array).map(func(r: Dictionary) -> String: return r.name)
	assert_array(names).contains_exactly_in_any_order(["Oval turn 1", "Oval backstretch"])
	for piece in t.scenery:
		# The oval's own: its SAFER wall all along; never on the course.
		assert_int(Array(piece.barrier_r).count(TrackFormat.BARRIER_SAFER)).is_equal(piece.samples.size())
		for i in range(0, piece.samples.size(), 5):
			var proj := t.project(piece.samples[i])
			assert_float(absf(float(proj.lateral))).is_greater(t.edge_at(float(proj.distance), float(proj.lateral)) - 0.05)
	var oval := TrackLoader.load_package(OVAL).track
	var oval_names := (oval.raw.roads as Array).map(func(r: Dictionary) -> String: return r.name)
	assert_array(oval_names).contains_exactly_in_any_order(["Road course infield", "Le Mans chicane"])
	var longest := 0.0
	for piece in oval.scenery:
		longest = maxf(longest, piece.length)
	assert_float(longest).is_greater(1500.0)
