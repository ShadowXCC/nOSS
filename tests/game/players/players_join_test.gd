extends GdUnitTestSuite
## Local player slots (LOC-01, LOC-04, docs/INPUT.md §3): press-to-join, claiming, the shared
## keyboard sides, adding devices, remembered profiles.

const PAD := 7
const PAD2 := 8


func before() -> void:
	Settings.use_folder("user://tests/join_suite")


func after() -> void:
	Devices.test_devices = []
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	Players.joining = false
	Devices.test_devices = [_pad(PAD), _pad(PAD2)]


func test_press_on_a_free_pad_joins() -> void:
	Players.joining = true
	_button(PAD, JOY_BUTTON_A, true)
	Players._process(0.016)
	_button(PAD, JOY_BUTTON_A, false)
	assert_int(Players.count()).is_equal(1)
	assert_str(Players.slots[0].device_keys[0]).is_equal(_pad(PAD).key)
	# Its pad is taken now; the other one isn't.
	var free := Players.free_devices().map(func(d: Dictionary) -> String: return d.key)
	assert_bool(_pad(PAD).key in free).is_false()
	assert_bool(_pad(PAD2).key in free).is_true()


func test_back_buttons_dont_join() -> void:
	Players.joining = true
	_button(PAD, JOY_BUTTON_B, true)
	Players._process(0.016)
	_button(PAD, JOY_BUTTON_B, false)
	assert_int(Players.count()).is_equal(0)


func test_keyboard_sides() -> void:
	var kb: Dictionary = Players.free_devices()[0]
	assert_str(kb.key).is_equal("kb:full")
	var p1 := Players.join(kb)
	assert_bool(Players.free_devices().any(func(d: Dictionary) -> bool: return d.kind == "keyboard")).is_false()
	assert_bool(Players.set_keyboard_zone(p1, "left")).is_true()
	var free: Array = Players.free_devices().filter(func(d: Dictionary) -> bool: return d.kind == "keyboard")
	assert_str(free[0].key).is_equal("kb:right")
	var p2 := Players.join(free[0])
	assert_str(p2.keyboard_zone()).is_equal("right")
	# The whole keyboard can't be taken back while P2 has a side.
	assert_bool(Players.set_keyboard_zone(p1, "full")).is_false()
	assert_bool(Players.set_keyboard_zone(p1, "right")).is_false()


func test_add_device_and_two_players_own_profiles() -> void:
	var p1 := Players.join(_pad(PAD))
	Players.adding = p1
	_button(PAD2, JOY_BUTTON_X, true)
	Players._process(0.016)
	_button(PAD2, JOY_BUTTON_X, false)
	assert_int(p1.device_keys.size()).is_equal(2)
	Players.leave(p1)
	var a := Players.join(_pad(PAD))
	var b := Players.join(_pad(PAD2))
	assert_object(a.profile).is_not_same(b.profile)
	assert_str(a.tag()).is_equal("P1")
	assert_str(b.tag()).is_equal("P2")


func test_remembered_profile_follows_the_device() -> void:
	Players.join(_pad(PAD))
	var b := Players.join(_pad(PAD2))
	b.profile.set_value("name", "Bea")
	Players.remember_all()
	var bea_id := b.profile.id
	Players.clear()
	var again := Players.join(_pad(PAD2))
	assert_str(again.profile.id).is_equal(bea_id)


func test_max_four() -> void:
	Devices.test_devices = [_pad(1), _pad(2), _pad(3), _pad(4), _pad(5)]
	for i in range(1, 6):
		Players.join(_pad(i))
	assert_int(Players.count()).is_equal(4)


static func _pad(id: int) -> Dictionary:
	return { "kind": "gamepad", "key": "pad:test#%d" % id, "name": "Test pad %d" % id, "id": id, "guid": "test%d" % id, "preset": "pad_standard" }


static func _button(id: int, b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = id
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
