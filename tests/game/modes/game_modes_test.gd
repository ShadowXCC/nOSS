extends GdUnitTestSuite
## Modes, their classes, and a default car for every class (docs/PLATFORMS.md §3, §6).


func test_modes_list_their_classes() -> void:
	var modes := GameModes.list()
	assert_array(modes.map(func(m: Dictionary) -> String: return m.id)).contains_exactly(["track", "kart", "highway"])
	for mode in modes:
		var classes := GameModes.classes(mode)
		assert_int(classes.size()).override_failure_message(mode.id).is_equal(mode.classes.size())


func test_every_class_has_a_default_car() -> void:
	for mode in GameModes.list():
		for result in GameModes.classes(mode):
			var path := GameModes.default_car(result.platform)
			var family: String = PackageLoader.read_manifest(path).get("family", "")
			assert_bool(Fitting.compatible(result.platform, family)).override_failure_message(result.platform.id).is_true()


func test_describe() -> void:
	var gt := PlatformLoader.load_official("official.track.gt").platform
	assert_str(GameModes.describe(gt)).is_equal("RWD · 377 kW · 1300 kg")
