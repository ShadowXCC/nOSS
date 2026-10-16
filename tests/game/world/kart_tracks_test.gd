extends GdUnitTestSuite
## The kart tracks (D147): each one rebuilt from its commands is the one committed (its layout
## hash) and checks with no errors; the circuits are tagged kart and list with a "Kart" badge,
## the arenas list as arenas; the Spark Cup's tracks are all there.

const MakeKartTracks := preload("res://tools/make_kart_tracks.gd")


func test_each_rebuild_is_the_committed_track() -> void:
	for id: String in MakeKartTracks.IDS:
		var d: TrackDraft = MakeKartTracks.build(id)
		var errors := TrackValidator.errors(TrackValidator.check(d))
		assert_array(errors).override_failure_message("%s: %s" % [id, errors]).is_empty()
		var path := "res://content/tracks/%s" % id
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("manifest.json")))
		assert_str(d.track().layout_hash).override_failure_message(id + " changed: run tools/make_kart_tracks.tscn").is_equal(String(manifest.layout))
		assert_array(manifest.tags).contains(["kart"])


func test_they_list_by_type() -> void:
	var arenas := TrackLibrary.list(false, false, "arena").map(func(e: Dictionary) -> String: return e.id)
	assert_array(arenas).contains_exactly_in_any_order(["crate_yard", "dust_bowl"])
	var circuits := TrackLibrary.list(false, false, "circuit")
	var gearworks: Dictionary = circuits.filter(func(e: Dictionary) -> bool: return e.id == "gearworks")[0]
	assert_str(TrackLibrary.label(gearworks)).is_equal("Gearworks · 1.5 km · Kart")
	var pg: Dictionary = circuits.filter(func(e: Dictionary) -> bool: return e.id == "proving_ground")[0]
	assert_str(TrackLibrary.label(pg)).not_contains("Kart")
	var yard := TrackLibrary.entry("res://content/tracks/crate_yard")
	assert_str(TrackLibrary.label(yard)).is_equal("Crate Yard")


func test_the_spark_cups_tracks_are_there() -> void:
	var cup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cups/spark_cup.cup.json"))
	assert_int((cup.races as Array).size()).is_equal(4)
	for race: Dictionary in cup.races:
		assert_str(TrackLibrary.resolve(String(race.track))).override_failure_message(String(race.track)).is_not_empty()
