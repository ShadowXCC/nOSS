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


func test_bindings_apply_defaults_and_overrides() -> void:
	Bindings.apply({})
	assert_bool(InputMap.has_action("throttle")).is_true()
	assert_array(Bindings.keys_for("throttle")).contains([KEY_W, KEY_UP])
	Bindings.apply({ "throttle": [KEY_I] })
	assert_array(Bindings.keys_for("throttle")).is_equal([KEY_I])
	Bindings.apply(Settings.profile.bindings)


func test_gamepad_buttons_only_listen_to_the_chosen_pad() -> void:
	Bindings.use_gamepad(3)
	var pad_events := InputMap.action_get_events("shift_up").filter(func(e: InputEvent) -> bool: return e is InputEventJoypadButton)
	assert_int(pad_events[0].device).is_equal(3)
	Bindings.use_gamepad(-1)
