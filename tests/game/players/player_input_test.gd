extends GdUnitTestSuite
## Per-player input (docs/INPUT.md §3, LOC-04, ACC-06): presets and overrides, only the player's
## own devices, shared keyboard sides, devices merged, toggles, edges, menu repeat.

const PAD := 7 # joypad ids no real pad has in tests
const OTHER_PAD := 8

var _profile: PlayerProfile
var _keys := []


func before() -> void:
	Settings.use_folder("user://tests/input_suite")


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	_profile = PlayerProfile.create("t1")


func after_test() -> void:
	for k: int in _keys:
		_key(k, false)
	_keys.clear()
	for id in [PAD, OTHER_PAD]:
		for b in PlayerInput.PAD_BUTTON_COUNT:
			_button(id, b, false)
		for a in PlayerInput.PAD_AXIS_COUNT:
			_axis(id, a, 0.0)


func test_whole_keyboard_uses_arrows_and_wasd() -> void:
	var input := _make_input([_kb("full")])
	_key(KEY_W, true)
	assert_float(input.value("throttle")).is_equal(1.0)
	_key(KEY_W, false)
	_key(KEY_LEFT, true)
	assert_float(input.value("steer_left", "keyboard")).is_equal(1.0)


func test_keyboard_sides_dont_cross() -> void:
	var left := _make_input([_kb("left")])
	var right := _make_input([_kb("right")])
	_key(KEY_W, true)
	_key(KEY_DOWN, true)
	assert_float(left.value("throttle")).is_equal(1.0)
	assert_float(left.value("brake")).is_equal(0.0)
	assert_float(right.value("throttle")).is_equal(0.0)
	assert_float(right.value("brake")).is_equal(1.0)


func test_gamepad_axes_are_shaped_and_only_the_players_pad_counts() -> void:
	var input := _make_input([_pad(PAD)])
	_axis(PAD, JOY_AXIS_TRIGGER_RIGHT, 0.8)
	assert_float(input.value("throttle")).is_equal_approx(VehicleController.shape_axis(0.8, 0.05, 1.0), 0.0001)
	_axis(PAD, JOY_AXIS_LEFT_X, -1.0)
	assert_float(input.value("steer_left", "gamepad")).is_equal_approx(1.0, 0.0001)
	assert_float(input.value("steer_right", "gamepad")).is_equal(0.0)
	_axis(OTHER_PAD, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_button(OTHER_PAD, JOY_BUTTON_A, true)
	assert_float(input.value("brake")).is_equal(0.0)
	assert_float(input.value("handbrake")).is_equal(0.0)


## The right stick looks around (Changes.md): its four ways, past the player's stick deadzone.
func test_right_stick_looks_around() -> void:
	var input := _make_input([_pad(PAD)])
	_axis(PAD, JOY_AXIS_RIGHT_X, 1.0)
	_axis(PAD, JOY_AXIS_RIGHT_Y, -0.5)
	assert_float(input.value("look_right")).is_equal_approx(1.0, 0.0001)
	assert_float(input.value("look_left")).is_equal(0.0)
	assert_float(input.value("look_up")).is_greater(0.3)
	assert_float(input.value("look_down")).is_equal(0.0)
	_axis(PAD, JOY_AXIS_RIGHT_X, float(_profile.data.pad_deadzone) * 0.5)
	assert_float(input.value("look_right")).is_equal(0.0)


func test_two_devices_drive_one_car_largest_wins() -> void:
	var input := _make_input([_kb("full"), _pad(PAD)])
	_axis(PAD, JOY_AXIS_TRIGGER_RIGHT, 0.3)
	assert_float(input.analog("throttle")).is_less(0.5)
	_key(KEY_UP, true)
	assert_float(input.analog("throttle")).is_equal(1.0)


func test_profile_overrides_replace_the_preset() -> void:
	_profile.data.input.bindings = { "kb_full": { "throttle": [{ "key": KEY_I }] } }
	var input := _make_input([_kb("full")])
	_key(KEY_W, true)
	assert_float(input.value("throttle")).is_equal(0.0)
	_key(KEY_I, true)
	assert_float(input.value("throttle")).is_equal(1.0)


func test_one_handed_gamepad_preset() -> void:
	_profile.data.input.presets.gamepad = "pad_right_hand"
	var input := _make_input([_pad(PAD)])
	_axis(PAD, JOY_AXIS_RIGHT_X, 1.0)
	_button(PAD, JOY_BUTTON_RIGHT_SHOULDER, true)
	assert_float(input.value("steer_right")).is_equal_approx(1.0, 0.0001)
	assert_float(input.value("brake")).is_equal(1.0)
	_axis(PAD, JOY_AXIS_LEFT_X, -1.0)
	assert_float(input.value("steer_left")).is_equal(0.0)


func test_edges_once_per_press() -> void:
	var input := _make_input([_kb("full")])
	_key(KEY_E, true)
	input.poll()
	assert_bool(input.just_pressed("shift_up")).is_true()
	input.poll()
	assert_bool(input.just_pressed("shift_up")).is_false()
	_key(KEY_E, false)
	input.poll()
	_key(KEY_E, true)
	input.poll()
	assert_bool(input.just_pressed("shift_up")).is_true()


func test_hold_action_as_toggle() -> void:
	_profile.data.input.toggles = ["handbrake"]
	var input := _make_input([_kb("full")])
	_key(KEY_SPACE, true)
	input.poll()
	assert_bool(input.held("handbrake")).is_true()
	_key(KEY_SPACE, false)
	input.poll()
	assert_bool(input.held("handbrake")).is_true()
	_key(KEY_SPACE, true)
	input.poll()
	assert_bool(input.held("handbrake")).is_false()


func test_menu_repeat_uses_delay_and_rate() -> void:
	_profile.data.input.menu_delay = 0.45
	_profile.data.input.menu_rate = 10.0
	var input := _make_input([_kb("full")])
	_key(KEY_DOWN, true)
	var fired := 0
	for i in 100: # 1 s at 100 fps
		fired += input.poll_menu(0.01).count("menu_down")
	# The press, then repeats at 0.45, 0.55 ... 0.95 s.
	assert_int(fired).is_between(6, 8)
	_key(KEY_DOWN, false)
	assert_array(input.poll_menu(0.01)).is_empty()


func test_held_press_does_not_act_in_a_new_menu() -> void:
	var input := _make_input([_kb("full")])
	_key(KEY_ENTER, true)
	input.settle()
	assert_array(input.poll_menu(0.01)).not_contains(["menu_confirm"])
	_key(KEY_ENTER, false)
	input.poll_menu(0.01)
	_key(KEY_ENTER, true)
	assert_array(input.poll_menu(0.01)).contains(["menu_confirm"])


func _make_input(devices: Array) -> PlayerInput:
	var input := PlayerInput.new()
	input.profile = _profile
	input.devices.assign(devices)
	input.rebuild()
	return input


static func _kb(zone: String) -> Dictionary:
	return { "kind": "keyboard", "key": "kb:" + zone, "name": "Keyboard", "id": -1, "guid": "kb", "zone": zone }


static func _pad(id: int) -> Dictionary:
	return { "kind": "gamepad", "key": "pad:test#%d" % id, "name": "Test pad", "id": id, "guid": "test" }


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	if down and k not in _keys:
		_keys.append(k)


static func _button(id: int, b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = id
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


static func _axis(id: int, a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = id
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## The horn and the lights (D119) are in the presets that have room for them, and no two driving
## actions in a preset share an input (menus may share theirs with driving).
func test_presets_have_the_horn_and_lights_and_no_clashes() -> void:
	for id in ["kb_full", "kb_left", "kb_right", "pad_standard"]:
		var b := Bindings.effective(id)
		assert_array(b.get("horn", [])).override_failure_message(id + ": horn").is_not_empty()
		assert_array(b.get("lights", [])).override_failure_message(id + ": lights").is_not_empty()
	for id in ["kb_full", "kb_left", "kb_right", "pad_standard", "pad_left_hand", "pad_right_hand"]:
		var b := Bindings.effective(id)
		var seen := {}
		for action: String in Bindings.DRIVING:
			for r: Dictionary in b.get(action, []):
				var key := JSON.stringify(r)
				var other: String = seen.get(key, "")
				# Kart actions only share with what kart sessions ignore (D135).
				var allowed: bool = action in Bindings.KART and other in Bindings.KART_SHARES[action]
				assert_bool(other.is_empty() or allowed).override_failure_message("%s: %s and %s share %s" % [id, other, action, key]).is_true()
				if other.is_empty():
					seen[key] = action


## Every preset with buttons to spare has the kart actions (D135).
func test_presets_have_the_kart_actions() -> void:
	for id in ["kb_full", "kb_left", "kb_right", "pad_standard", "pad_left_hand", "pad_right_hand"]:
		var b := Bindings.effective(id)
		for action: String in Bindings.KART:
			assert_array(b.get(action, [])).override_failure_message("%s: %s" % [id, action]).is_not_empty()
	assert_array(Bindings.effective("pad_standard").drift).is_equal([{ "button": JOY_BUTTON_RIGHT_SHOULDER }])
	assert_array(Bindings.effective("kb_full").use_item).is_equal([{ "key": KEY_E }])
	assert_bool("drift" in Bindings.HOLD).is_true()
