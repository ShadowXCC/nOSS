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


## Pressed actions straight from a dictionary, no devices.
class FakeInput extends PlayerInput:
	var pressed := {}

	func _source(action: String) -> float:
		return 1.0 if pressed.get(action, false) else 0.0


## Kart controls (D135): the drift button drifts, the handbrake and the shifts do nothing, and the
## item button asks for the item, thrown back while that's held.
func test_kart_controls() -> void:
	var v: Vehicle = auto_free(Vehicle.new())
	v.arcade = GameModes.arcade(GameModes.mode_for("official.kart.medium"))
	var input := FakeInput.new()
	input.profile = PlayerProfile.create("kart_test")
	var c: VehicleController = auto_free(VehicleController.new())
	c.vehicle = v
	c.input = input
	var asked: Array = []
	c.item_requested.connect(func(back: bool) -> void: asked.append(back))
	input.pressed = { "drift": true, "handbrake": true, "throttle": true }
	input.poll()
	c._physics_process(1.0 / 120.0)
	assert_bool(v.drift).is_true()
	assert_float(v.handbrake).is_equal(0.0)
	assert_float(v.throttle).is_equal(1.0)
	input.pressed = { "use_item": true }
	input.poll()
	c._physics_process(1.0 / 120.0)
	assert_bool(v.drift).is_false()
	assert_array(asked).is_equal([false])
	input.pressed = { "use_item": true, "throw_back": true }
	input.poll()
	c._physics_process(1.0 / 120.0) # still held: not again
	input.pressed = { "throw_back": true }
	input.poll()
	c._physics_process(1.0 / 120.0)
	input.pressed = { "use_item": true, "throw_back": true }
	input.poll()
	c._physics_process(1.0 / 120.0)
	assert_array(asked).is_equal([false, true])
	# Not a kart: the handbrake is the handbrake, and nothing asks for items.
	v.arcade = {}
	input.pressed = { "drift": true, "handbrake": true, "use_item": true }
	input.poll()
	c._physics_process(1.0 / 120.0)
	assert_float(v.handbrake).is_equal(1.0)
	assert_array(asked).is_equal([false, true])
## Sumo's drift setting off (D181): the drift button does nothing and the handbrake is left alone,
## so the car brakes as any other does. On a keyboard both are the same key (Space).
func test_kart_controls_with_the_drift_turned_off() -> void:
	var v: Vehicle = auto_free(Vehicle.new())
	v.arcade = GameModes.arcade(GameModes.mode_for("official.sumo.standard"))
	v.drift_allowed = false
	var input := FakeInput.new()
	input.profile = PlayerProfile.create("sumo_drift_test")
	var c: VehicleController = auto_free(VehicleController.new())
	c.vehicle = v
	c.input = input
	input.pressed = { "drift": true, "handbrake": true, "throttle": true }
	input.poll()
	c._physics_process(1.0 / 120.0)
	assert_bool(v.drift).override_failure_message("the drift button still drifted").is_false()
	assert_float(v.handbrake).override_failure_message("the handbrake was suppressed").is_equal(1.0)
	assert_float(v.throttle).is_equal(1.0)
	# With it allowed, the kart rule stands: the drift button drifts and the handbrake is ignored.
	v.drift_allowed = true
	c._physics_process(1.0 / 120.0)
	assert_bool(v.drift).is_true()
	assert_float(v.handbrake).is_equal(0.0)
