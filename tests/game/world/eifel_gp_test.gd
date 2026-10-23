extends GdUnitTestSuite
## The Eifel GP (D200): the built-in circuit on the real Nürburgring GP layout comes again the
## same from its generator (made with the editor's commands), passes the checks, keeps to the
## real line, climbs about as much as the real one, has its real pit lane, says where its layout
## and ground come from, and lists as a circuit without a Kart badge.

const DIR := "res://content/tracks/eifel_gp"
const MakeEifelGp := preload("res://tools/make_eifel_gp.gd")


func test_the_generator_makes_the_committed_track() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/manifest.json"))
	var d: TrackDraft = MakeEifelGp.build()
	assert_str(d.track().layout_hash).override_failure_message("eifel_gp changed: run tools/make_eifel_gp.tscn").is_equal(String(manifest.layout))
	assert_array(TrackValidator.errors(TrackValidator.check(d))).is_empty()


func test_it_is_the_real_layout_with_its_hills() -> void:
	var pkg := TrackLoader.load_package(DIR)
	assert_bool(pkg.ok()).override_failure_message(pkg.error).is_true()
	assert_object(pkg.terrain).is_not_null()
	var t := pkg.track
	assert_str(t.type).is_equal("circuit")
	assert_bool(t.builtin).is_true()
	# The real lap is 5.148 km; the map's line, smoothed, comes a little short.
	assert_float(t.length).is_between(5050.0, 5200.0)
	assert_float(MakeEifelGp.off_line(t)).is_less(1.5)
	var low := INF
	var high := -INF
	for p in t.samples:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	assert_float(high - low).is_between(45.0, 65.0)
	assert_int(int(t.grid.slots)).is_equal(20)
	# The real pit lane (D203), on the right, a box for each grid slot, 80 km/h.
	assert_str(t.pit_error).is_empty()
	assert_float(t.pit.side).is_equal(-1.0)
	assert_int(t.pit.boxes.size()).is_equal(20)
	assert_bool(t.pit.crowded).is_false()
	assert_float(t.pit.speed * 3.6).is_equal_approx(80.0, 0.01)
	assert_float(t.pit.track.length).is_between(800.0, 1200.0)
	var attributions := " ".join(PackedStringArray(pkg.manifest.attributions))
	assert_str(attributions).contains("OpenStreetMap")
	assert_str(attributions).contains("EU-DEM")


func test_it_lists_as_a_circuit() -> void:
	var circuits := TrackLibrary.list(false, false, "circuit")
	var gp: Array = circuits.filter(func(e: Dictionary) -> bool: return e.id == "eifel_gp")
	assert_int(gp.size()).is_equal(1)
	assert_str(TrackLibrary.label(gp[0])).is_equal("Eifel GP · 5.1 km")
	var highways := TrackLibrary.list(false, false, "highway").map(func(e: Dictionary) -> String: return e.id)
	assert_array(highways).not_contains(["eifel_gp"])
