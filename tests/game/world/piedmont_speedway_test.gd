extends GdUnitTestSuite
## Piedmont Speedway (D206): the built-in 1.5-mile quad-oval on the real Charlotte layout comes
## again the same from its generator (made with the editor's commands), passes the checks, runs
## counter-clockwise, is banked 24° in the turns and 5° on the frontstretch, has its pit road and
## boxes and a grid on the flat, is a floodlit night, says where its layout and ground come from,
## and lists as a circuit.

const DIR := "res://content/tracks/piedmont_speedway"
const MakePiedmont := preload("res://tools/make_piedmont_speedway.gd")


func test_the_generator_makes_the_committed_track() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/manifest.json"))
	var d: TrackDraft = MakePiedmont.build()
	assert_str(d.track().layout_hash).override_failure_message("piedmont_speedway changed: run tools/make_piedmont_speedway.tscn").is_equal(String(manifest.layout))
	assert_array(TrackValidator.errors(TrackValidator.check(d))).is_empty()


func test_it_is_a_banked_quad_oval() -> void:
	var pkg := TrackLoader.load_package(DIR)
	assert_bool(pkg.ok()).override_failure_message(pkg.error).is_true()
	assert_object(pkg.terrain).is_not_null()
	var t := pkg.track
	assert_str(t.type).is_equal("circuit")
	assert_bool(t.builtin).is_true()
	assert_float(t.length).is_between(2400.0, 2450.0)
	# 1.5 miles, measured 15 ft out from the inner edge.
	assert_float(MakePiedmont.measured_m(t)).is_equal_approx(2414.0, 10.0)
	# Counter-clockwise: it turns left.
	var turning := 0.0
	for k in t.curvature:
		turning += k
	assert_float(turning).is_greater(0.0)
	var steepest := 0.0
	for b in t.bank:
		steepest = maxf(steepest, absf(rad_to_deg(b)))
		assert_float(rad_to_deg(b)).is_less_equal(0.0) # always up to the outside
	assert_float(steepest).is_equal_approx(24.0, 0.5)
	assert_float(absf(rad_to_deg(t.bank[t.index_at(t.start_m)]))).is_equal_approx(5.0, 0.5)
	# Its inner edge stands on the ground: no bridge anywhere.
	assert_int(Array(t.lifted).count(1)).is_equal(0)
	assert_float(t.apron(t.index_at(t.start_m), 1.0)).is_greater(8.0)
	assert_int(int(t.barrier_r[0])).is_equal(TrackFormat.BARRIER_SAFER)


func test_it_has_pit_road_and_a_grid_on_the_flat() -> void:
	var t := TrackLoader.load_package(DIR).track
	assert_str(t.pit_error).is_empty()
	assert_float(t.pit.side).is_equal(1.0) # inside the frontstretch
	assert_int(t.pit.boxes.size()).is_greater_equal(16)
	assert_bool(t.pit.crowded).is_false()
	assert_int(int(t.grid.slots)).is_equal(20)
	var g := t.grid
	for slot in int(g.slots):
		var d := t.start_m - float(g.front_m) - (slot / 2) * float(g.row_m) - (slot % 2) * float(g.row_m) * float(g.stagger)
		assert_float(absf(rad_to_deg(t.bank[t.index_at(d)]))).is_less_equal(TrackValidator.GRID_BANK_DEG)


func test_it_is_a_floodlit_night_with_its_sources() -> void:
	var pkg := TrackLoader.load_package(DIR)
	var env: Dictionary = pkg.track.raw.environment
	assert_str(String(env.time)).is_equal("night")
	assert_bool(bool(env.floodlit)).is_true()
	var towers: Array = pkg.track.raw.props.items.filter(func(i: Dictionary) -> bool: return i.prop == "light_tower")
	assert_int(towers.size()).is_greater_equal(30)
	var attributions := " ".join(PackedStringArray(pkg.manifest.attributions))
	assert_str(attributions).contains("OpenStreetMap")
	assert_str(attributions).contains("U.S. Geological Survey")


func test_it_lists_as_a_circuit() -> void:
	var circuits := TrackLibrary.list(false, false, "circuit")
	var oval: Array = circuits.filter(func(e: Dictionary) -> bool: return e.id == "piedmont_speedway")
	assert_int(oval.size()).is_equal(1)
	assert_str(TrackLibrary.label(oval[0])).is_equal("Piedmont Speedway · 2.4 km")
