extends GdUnitTestSuite
## Platform files load, validate and merge family defaults (PLT-02).


func test_track_gt_loads() -> void:
	var result := PlatformLoader.load_official("official.track.gt")
	assert_array(result.errors).is_empty()
	assert_str(result.platform.name).is_equal("GT")
	assert_str(result.hash).starts_with("sha256:")
	assert_float(result.platform.mass.kg).is_equal(1300.0)


func test_every_official_platform_is_valid() -> void:
	var paths := PlatformLoader.list_official()
	assert_array(paths).is_not_empty()
	for path in paths:
		var result := PlatformLoader.load_file(path)
		assert_array(result.errors).override_failure_message(path + ": " + str(result.errors)).is_empty()


func test_unknown_platform_fails() -> void:
	assert_bool(PlatformLoader.load_official("official.track.nope").ok()).is_false()
	assert_bool(PlatformLoader.load_official("bob.track.gt").ok()).is_false()


func test_official_id_reserved_outside_data() -> void:
	var data := _gt()
	assert_array(PlatformLoader.validate(data, true)).is_empty()
	assert_array(PlatformLoader.validate(data, false)).contains(["official.* is reserved"])
	data.id = "bob.gt"
	assert_array(PlatformLoader.validate(data, false)).is_empty()


func test_semantic_checks() -> void:
	var data := _gt()
	data.geometry.wheelbase_m.ref = 3.5
	data.engine.idle_rpm = 9000
	data.layout.drive = "fwd"
	var errors := PlatformLoader.validate(data, true)
	assert_int(errors.size()).is_equal(3)


func test_layout_rules() -> void:
	var data := _gt()
	data.family = "open"
	data.layout.axles[0].wheels = 1
	data.layout.axles[1].wheels = 1
	assert_array(PlatformLoader.validate(data, true)).contains(["layout: open needs 2 axles and at least 3 wheels"])
	data.layout.axles[1].wheels = 2
	assert_array(PlatformLoader.validate(data, true)).is_empty()
	data = _gt()
	data.differential.center = { "type": "viscous", "front_share": 0.4 }
	assert_array(PlatformLoader.validate(data, true)).contains(["differential.center needs two driven axles"])


func test_merged_rules() -> void:
	var data := PlatformLoader.with_defaults(_gt())
	assert_array(PlatformLoader.validate_merged(data)).is_empty()
	data.suspension.type = "rigid"
	assert_array(PlatformLoader.validate_merged(data)).has_size(2)
	data = _gt()
	data.erase("aero")
	data.family = "moto" # no defaults file
	assert_array(PlatformLoader.validate_merged(PlatformLoader.with_defaults(data))).contains(["aero.cd_a: missing (no default)"])


func test_missing_blocks_use_family_defaults() -> void:
	var data := _gt()
	data.erase("differential")
	data.erase("aero")
	var merged := PlatformLoader.with_defaults(data)
	assert_str(merged.differential.type).is_equal("open")
	assert_float(merged.aero.cd_a).is_greater(0.0)
	# The platform's own values win.
	assert_str(merged.gearbox.type).is_equal("sequential")


func _gt() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/platforms/track/gt.platform.json"))


## The Stock Car (D204): heavy, about 500 kW, low downforce and lots of drag, a tank of fuel and
## tires that wear.
func test_the_stock_car_loads() -> void:
	var result := PlatformLoader.load_official("official.track.stock_car")
	assert_array(result.errors).is_empty()
	var p := result.platform
	assert_float(float(p.mass.kg)).is_equal(1550.0)
	assert_float(GameModes.peak_power_kw(p)).is_between(480.0, 520.0)
	assert_float(float(p.aero.cd_a)).is_equal(1.0)
	assert_bool(bool(p.aero.slipstream)).is_true()
	assert_float(float(p.fuel.tank_l)).is_equal(68.0)
	assert_bool(bool(p.tires.wear)).is_true()
	assert_float(float(p.tires.worn_grip)).is_less(1.0)
	assert_array(GameModes.mode_for("official.track.stock_car").classes).contains(["official.track.stock_car"])
