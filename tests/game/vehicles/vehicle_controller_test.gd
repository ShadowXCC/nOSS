extends GdUnitTestSuite
## Input shaping for gamepads (INP-02) and the action bindings (docs/INPUT.md §1).


func test_axis_deadzone_and_curve() -> void:
	assert_float(VehicleController.shape_axis(0.05, 0.1, 1.0)).is_equal(0.0)
	assert_float(VehicleController.shape_axis(1.0, 0.1, 1.6)).is_equal_approx(1.0, 0.0001)
	assert_float(VehicleController.shape_axis(-1.0, 0.1, 1.6)).is_equal_approx(-1.0, 0.0001)
	assert_float(VehicleController.shape_axis(0.55, 0.1, 1.0)).is_equal_approx(0.5, 0.0001)
	# A curve above 1 softens the middle of the range.
	assert_float(VehicleController.shape_axis(0.55, 0.1, 2.0)).is_equal_approx(0.25, 0.0001)


func test_largest_input_wins() -> void:
	assert_float(VehicleController._largest([0.2, -0.6, 0.4])).is_equal(-0.6)
	assert_float(VehicleController._largest([0.0, 0.0])).is_equal(0.0)


func test_presets_load_with_names_resolved() -> void:
	var kb := Bindings.preset("kb_full")
	assert_array(kb.bindings.throttle).contains([{ "key": KEY_W }, { "key": KEY_UP }])
	var pad := Bindings.preset("pad_standard")
	assert_array(pad.bindings.throttle).is_equal([{ "axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1 }])
	assert_array(pad.bindings.pause).is_equal([{ "button": JOY_BUTTON_START }])
	# Every action can be reached from each full preset, menus included.
	for id in ["kb_full", "kb_left", "kb_right", "pad_standard"]:
		for action: String in Bindings.MENU + ["steer_left", "steer_right", "throttle", "brake", "pause"]:
			assert_bool(Bindings.preset(id).bindings.has(action)).override_failure_message("%s: %s" % [id, action]).is_true()


func test_keyboard_sides_share_no_keys() -> void:
	var left := Bindings.keys_of("kb_left")
	for k: int in Bindings.keys_of("kb_right"):
		assert_bool(k in left).override_failure_message(OS.get_keycode_string(k)).is_false()


func test_overrides_replace_one_action() -> void:
	var map := Bindings.effective("kb_full", { "brake": [{ "key": "K" }] })
	assert_array(map.brake).is_equal([{ "key": KEY_K }])
	assert_array(map.throttle).contains([{ "key": KEY_W }])


func test_ref_labels() -> void:
	assert_str(Bindings.ref_label({ "button": JOY_BUTTON_RIGHT_SHOULDER }, "gamepad")).is_equal("RB")
	assert_str(Bindings.ref_label({ "axis": JOY_AXIS_LEFT_X, "dir": -1 }, "gamepad")).is_equal("Left stick left")
	assert_str(Bindings.ref_label({ "button": 3 }, "sim")).is_equal("Button 4")
