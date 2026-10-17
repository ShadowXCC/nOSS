extends GdUnitTestSuite
## Modes, their classes, and a default car for every class (docs/PLATFORMS.md §3, §6).


func test_modes_list_their_classes() -> void:
	var modes := GameModes.list()
	assert_array(modes.map(func(m: Dictionary) -> String: return m.id)).contains_exactly(["track", "kart", "highway", "endless"])
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
	assert_str(GameModes.describe(PlatformLoader.load_official("official.endless.cruiser").platform)).is_equal("RWD · 151 kW · 1400 kg")
	assert_str(GameModes.describe(PlatformLoader.load_official("official.endless.sport").platform)).is_equal("RWD · 260 kW · 1350 kg")


## Endless (M9, PLATFORMS.md §6): calm classes with assists on, autodrive allowed, nothing to tune,
## and no racing line (there's no line on a road made as you go).
func test_the_endless_mode() -> void:
	var mode := GameModes.mode_for("official.endless.cruiser")
	assert_str(String(mode.id)).is_equal("endless")
	assert_array(mode.tuning.allow).is_empty()
	assert_array(mode.assists.allowed).contains(["autodrive", "steer_aid"])
	assert_array(mode.assists.allowed).not_contains(["racing_line"])
	assert_array(mode.assists.defaults).contains(["abs", "tcs", "stability", "auto_gearbox"])
	var cruiser := PlatformLoader.load_official("official.endless.cruiser").platform
	assert_bool(Fitting.compatible(cruiser, "truck")).is_true()
	assert_bool(Fitting.compatible(PlatformLoader.load_official("official.endless.sport").platform, "truck")).is_false()


func test_the_kart_mode_fills_its_arcade_numbers() -> void:
	var kart := GameModes.mode_for("official.kart.medium")
	var arcade := GameModes.arcade(kart)
	assert_float(arcade.grip).is_equal(1.25)
	assert_array(arcade.drift.tiers_s).is_equal([0.6, 1.2, 2.0])
	assert_float(arcade.tow.s).is_equal(1.5)
	# A block that only sets some keys keeps the rest.
	var partial := kart.duplicate(true)
	partial.arcade = { "drift": { "hop": 0.0 } }
	var merged := GameModes.arcade(partial)
	assert_float(merged.drift.hop).is_equal(0.0)
	assert_float(merged.drift.min_speed).is_equal(8.0)
	assert_float(merged.grip).is_equal(1.25)
	assert_dict(GameModes.arcade(GameModes.mode_for("official.track.gt"))).is_empty()
	# The mode file's arcade block passes its schema, and a bad one doesn't.
	var schema := JsonSchema.load_schema("mode")
	partial.arcade = { "drift": { "tiers_s": [0.6, 1.2] } }
	assert_array(JsonSchema.validate(partial, schema)).is_not_empty()


func test_the_layer_drives_a_vehicle_sim() -> void:
	var platform := PlatformLoader.load_official("official.kart.medium").platform
	var sim := VehicleSim.new()
	var wheels := []
	for i in 4:
		wheels.append({ "center": Vector3(0.55 if i % 2 == 0 else -0.55, 0.14, 0.6 if i < 2 else -0.6), "radius": 0.14,
			"axle": 1 if i < 2 else 2, "side": "L" if i % 2 == 0 else "R" })
	assert_bool(sim.configure(platform, { "ground_y": 0.0, "wheels": wheels })).is_true()
	assert_bool(sim.has_layer()).is_false()
	assert_dict(sim.get_kart_state()).is_empty()
	sim.set_layer(GameModes.arcade(GameModes.mode_for("official.kart.medium")))
	assert_bool(sim.has_layer()).is_true()
	sim.kart_effect(VehicleSim.KART_BOOST, 1.0)
	assert_float(float(sim.get_kart_state().boost)).is_equal(1.0)
	assert_int(sim.get_kart_flags() & VehicleSim.KART_FLAG_BOOST).is_equal(VehicleSim.KART_FLAG_BOOST)
	assert_float(sim.get_geared_top() * 3.6).is_equal_approx(100.0, 1.0)
	# Hotswap keeps the layer and its state.
	assert_bool(sim.configure(platform, { "ground_y": 0.0, "wheels": wheels })).is_true()
	assert_bool(sim.has_layer()).is_true()
	assert_float(float(sim.get_kart_state().boost)).is_equal(1.0)
	sim.set_layer({})
	assert_bool(sim.has_layer()).is_false()


func test_kart_classes_default_to_the_noss_kart() -> void:
	var pkg := PackageLoader.load_package("res://content/cars/noss_kart")
	for id in ["official.kart.light", "official.kart.medium", "official.kart.heavy"]:
		var platform := PlatformLoader.load_official(id).platform
		assert_str(GameModes.default_car(platform)).override_failure_message(id).is_equal("res://content/cars/noss_kart")
		var fitted := Fitting.fit(platform, pkg.fit)
		assert_array(fitted.notes).override_failure_message("%s: %s" % [id, fitted.notes]).is_empty()
		assert_float(fitted.scale).is_equal(1.0)
	assert_str(pkg.sound.base).is_equal("two_stroke")
	pkg.free_scenes()
	var formula := PlatformLoader.load_official("official.track.formula").platform
	assert_str(GameModes.default_car(formula)).is_equal("res://content/cars/noss_open")
