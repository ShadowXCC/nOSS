extends GdUnitTestSuite
## Car setups (PLT-04): what may be tuned, clamping and snapping, gear order, save and load.

const TRACK_ID := "proving_ground"

var _gt: Dictionary
var _track_mode: Dictionary


func before() -> void:
	Settings.use_folder("user://tests/setup_suite")
	_gt = PlatformLoader.load_official("official.track.gt").platform
	_track_mode = GameModes.mode_for("official.track.gt")


func after() -> void:
	DirAccess.remove_absolute(Setup.path_for("official.track.gt", TRACK_ID))
	Settings.use_folder("user://")


func test_modes_narrow_what_can_be_tuned() -> void:
	assert_int(Setup.allowed_for(_gt, _track_mode).size()).is_equal(_gt.tunable.size())
	var street := PlatformLoader.load_official("official.highway.street").platform
	var highway := GameModes.mode_for("official.highway.street")
	assert_array(Setup.allowed_for(street, highway).keys()).contains_exactly_in_any_order(["gearbox.final_drive", "brakes.bias_front"])
	var kart := PlatformLoader.load_official("official.kart.medium").platform
	assert_dict(Setup.allowed_for(kart, GameModes.mode_for("official.kart.medium"))).is_empty()


func test_values_are_clamped_and_snapped() -> void:
	var s := Setup.create(_gt, _track_mode)
	s.set_value("brakes.bias_front", 0.99)
	assert_float(s.get_value("brakes.bias_front")).is_equal_approx(0.70, 0.0001)
	s.set_value("gearbox.final_drive", 3.512)
	assert_float(s.get_value("gearbox.final_drive")).is_equal_approx(3.50, 0.0001)
	# Back to the default: no longer a change.
	s.set_value("gearbox.final_drive", float(_gt.gearbox.final_drive))
	assert_bool(s.values.has("gearbox.final_drive")).is_false()
	# Not tunable here: ignored.
	s.set_value("mass.kg", 900.0)
	assert_bool(s.values.has("mass.kg")).is_false()


func test_gears_stay_in_order() -> void:
	var s := Setup.create(_gt, _track_mode)
	s.set_gear("gearbox.ratios", 1, 3.5) # 2nd longer than 1st? kept below it
	var ratios: Array = s.get_value("gearbox.ratios")
	assert_float(ratios[1]).is_less(float(ratios[0]))
	s.set_gear("gearbox.ratios", 2, 0.5) # below the range and below 4th: kept above 4th
	ratios = s.get_value("gearbox.ratios")
	assert_float(ratios[2]).is_greater(float(ratios[3]))


func test_apply_changes_only_the_tuned_values() -> void:
	var s := Setup.create(_gt, _track_mode)
	s.set_value("brakes.bias_front", 0.66)
	s.set_gear("gearbox.ratios", 5, 0.95)
	var p := s.apply(_gt)
	assert_float(p.brakes.bias_front).is_equal_approx(0.66, 0.0001)
	assert_float(p.gearbox.ratios[5]).is_equal_approx(0.95, 0.0001)
	assert_float(p.mass.kg).is_equal(float(_gt.mass.kg))
	# The platform itself is untouched.
	assert_float(_gt.brakes.bias_front).is_not_equal(0.66)


func test_save_and_load_round_trip() -> void:
	var s := Setup.create(_gt, _track_mode)
	s.set_value("suspension.front.freq_hz", 3.1)
	s.set_value("aero.cl_a_rear", -0.75)
	s.set_gear("gearbox.ratios", 0, 3.3)
	assert_int(s.save(TRACK_ID)).is_equal(OK)
	var back := Setup.load_for(_gt, _track_mode, TRACK_ID)
	assert_dict(back.values).is_equal(s.values)
	# Reset and save: the file goes.
	back.reset()
	back.save(TRACK_ID)
	assert_bool(FileAccess.file_exists(Setup.path_for("official.track.gt", TRACK_ID))).is_false()


func test_a_vehicle_drives_with_the_setup() -> void:
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var v: Vehicle = auto_free(Vehicle.create(PlatformLoader.load_official("official.track.gt"), pkg))
	var s := Setup.create(v.base_platform, _track_mode)
	s.set_value("brakes.bias_front", 0.68)
	v.apply_setup(s)
	assert_float(v.platform.brakes.bias_front).is_equal_approx(0.68, 0.0001)
	assert_str(v.sim.get_error()).is_empty()
	v.apply_setup(null)
	assert_float(v.platform.brakes.bias_front).is_equal(float(_gt.brakes.bias_front))


func test_a_tampered_file_is_kept_inside_the_ranges() -> void:
	var s := Setup.create(_gt, _track_mode)
	s.load_dict({ "schema": Setup.SCHEMA, "platform": "official.track.gt", "values": {
		"brakes.bias_front": 2.0, "mass.kg": 500, "gearbox.ratios": [9, 9, 9, 9, 9, 9], "aero.cl_a_rear": "lots" } })
	assert_float(s.get_value("brakes.bias_front")).is_equal_approx(0.70, 0.0001)
	assert_bool(s.values.has("mass.kg")).is_false()
	assert_bool(s.values.has("aero.cl_a_rear")).is_false()
	var ratios: Array = s.get_value("gearbox.ratios")
	for i in ratios.size() - 1:
		assert_float(ratios[i]).is_greater(float(ratios[i + 1]))
	for r: float in ratios:
		assert_float(r).is_less_equal(3.6)
	# Another platform's setup isn't taken.
	var other := Setup.create(_gt, _track_mode)
	other.load_dict({ "schema": Setup.SCHEMA, "platform": "official.track.formula", "values": { "brakes.bias_front": 0.6 } })
	assert_bool(other.is_default()).is_true()
