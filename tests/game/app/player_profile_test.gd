extends GdUnitTestSuite
## Player profiles (ACC-01, docs/ACCESSIBILITY.md §1): defaults, the v1 -> v2 migration, several
## profiles side by side.

const DIR := "user://tests/profile_suite"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_defaults_fill_missing_keys_and_drop_wrong_types() -> void:
	var p := PlayerProfile.create("x", { "name": "Ana", "camera_shake": "loud", "nonsense": 1, "assists": { "abs": false } })
	assert_str(p.display_name()).is_equal("Ana")
	assert_float(p.data.camera_shake).is_equal(0.5)
	assert_bool(p.data.has("nonsense")).is_false()
	assert_bool(p.data.assists.abs).is_false()
	assert_bool(p.data.assists.tcs).is_true()
	assert_str(p.data.input.presets.keyboard).is_equal("kb_full")


func test_v1_profile_migrates_keyboard_overrides() -> void:
	# The shape M1/M2 saved (player1.json).
	var v1 := {
		"assists": { "abs": true, "auto_gearbox": true, "steer_aid": true, "tcs": true },
		"bindings": { "throttle": [73.0], "brake": [75.0] },
		"camera": "hood", "camera_shake": 0.5, "head_movement": 0.5, "horizon_lock": false,
		"last_car": "user://garage/race_2.noss", "last_platform": "official.track.formula",
		"name": "Player 1", "pad_deadzone": 0.08, "pad_linearity": 1.6, "speed_fov": true, "wheel": {},
	}
	var p := PlayerProfile.create("player1", v1)
	assert_int(p.data.version).is_equal(PlayerProfile.VERSION)
	assert_str(p.data.assists.steer_aid).is_equal("auto")
	assert_bool(p.data.has("bindings")).is_false()
	assert_array(p.data.input.bindings.kb_full.throttle).is_equal([{ "key": KEY_I }])
	assert_str(p.data.camera).is_equal("hood")
	assert_str(p.data.last_platform).is_equal("official.track.formula")
	var map := Bindings.effective("kb_full", p.data.input.bindings.kb_full)
	assert_array(map.throttle).is_equal([{ "key": KEY_I }])
	assert_array(map.brake).is_equal([{ "key": KEY_K }])


func test_profiles_save_and_load_separately() -> void:
	var a := Settings.new_profile()
	var b := Settings.new_profile()
	assert_str(a.id).is_not_equal(b.id)
	a.set_value("hud_scale", 1.5)
	b.set_value("hud_scale", 0.75)
	assert_float(PlayerProfile.load_id(a.id).data.hud_scale).is_equal(1.5)
	assert_float(PlayerProfile.load_id(b.id).data.hud_scale).is_equal(0.75)
	assert_bool(Array(Settings.profile_ids()).has(b.id)).is_true()
	Settings.delete_profile(b.id)
	assert_bool(Array(Settings.profile_ids()).has(b.id)).is_false()
