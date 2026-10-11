extends GdUnitTestSuite
## Shifters, handbrakes and button boxes (INP-04): one player drives with a wheel, pedals, an
## H-shifter, a handbrake lever and a button box, all separate USB devices (faked here).

const SHIFTER := { "kind": "sim", "key": "sim:shifter", "name": "Test shifter", "id": 201, "guid": "shifter", "preset": "sim_generic", "wheel": false, "buttons": 12, "axes": 0 }
const LEVER := { "kind": "sim", "key": "sim:lever", "name": "Test handbrake", "id": 202, "guid": "lever", "preset": "sim_generic", "wheel": false, "buttons": 0, "axes": 1 }
const BOX := { "kind": "sim", "key": "sim:box", "name": "Test button box", "id": 203, "guid": "box", "preset": "sim_generic", "wheel": false, "buttons": 20, "axes": 0 }
const PEDALS := { "kind": "sim", "key": "sim:pedals", "name": "Test pedals", "id": 204, "guid": "pedals", "preset": "sim_generic", "wheel": false, "buttons": 0, "axes": 3 }


func before() -> void:
	Settings.use_folder("user://tests/sim_suite")


func after() -> void:
	PlayerInput.test_sim = {}
	Devices.test_devices = []
	Players.clear()
	Settings.use_folder("user://")


func _profile() -> PlayerProfile:
	var p := PlayerProfile.create("sim_a")
	p.data.input.bindings = {
		"sim:shifter": { "gear_1": [{ "button": 0 }], "gear_2": [{ "button": 1 }], "gear_3": [{ "button": 2 }], "gear_r": [{ "button": 6 }] },
		"sim:lever": { "handbrake": [{ "axis": 0, "dir": 1, "rest": -1.0 }] },
		"sim:box": { "reset_car": [{ "button": 16 }], "camera_next": [{ "button": 3 }] },
		"sim:pedals": { "clutch": [{ "axis": 2, "dir": 1, "rest": -1.0 }] },
	}
	return p


func _player_input(profile: PlayerProfile) -> PlayerInput:
	var i := PlayerInput.new()
	i.profile = profile
	i.devices = [SHIFTER, LEVER, BOX, PEDALS]
	i.rebuild()
	return i


func test_gates_lever_and_box_read_from_their_own_devices() -> void:
	var i := _player_input(_profile())
	PlayerInput.test_sim = { "b201:1": true, "a202:0": 0.0, "b203:16": true, "a204:2": -1.0 }
	i.poll()
	assert_bool(i.held("gear_2")).is_true()
	assert_bool(i.held("gear_1")).is_false()
	# The lever rests at -1: half way is 0.5.
	assert_float(i.analog("handbrake")).is_equal_approx(0.5, 0.01)
	assert_float(i.analog("clutch")).is_equal_approx(0.0, 0.01)
	assert_bool(i.just_pressed("reset_car")).is_true()
	assert_bool(i.has_binding("gear_r")).is_true()


func test_rebinding_captures_a_lever_with_its_rest_position() -> void:
	var i := _player_input(PlayerProfile.create("sim_b"))
	PlayerInput.test_sim = { "a202:0": -1.0, "a204:0": -1.0, "a204:1": -1.0, "a204:2": -1.0 }
	i.capture_start()
	assert_dict(i.capture_poll()).is_empty()
	PlayerInput.test_sim["a202:0"] = 0.4 # pulled most of the way
	var got := i.capture_poll()
	assert_str(String(got.get("kind", ""))).is_equal("sim")
	assert_dict(got.ref).contains_key_value("axis", 0)
	assert_float(float(got.ref.rest)).is_equal(-1.0)
	assert_int(int(got.ref.dir)).is_equal(1)


func test_hat_buttons_come_after_the_devices_own() -> void:
	# A hat reads as four buttons after the device's own (up, right, down, left).
	var i := PlayerInput.new()
	var profile := PlayerProfile.create("sim_c")
	profile.data.input.bindings = { "sim:box": { "camera_next": [{ "button": 17 }] } } # hat 0 right on a 16-button box
	i.profile = profile
	i.devices = [BOX]
	i.rebuild()
	PlayerInput.test_sim = { "b203:17": true }
	i.poll()
	assert_bool(i.just_pressed("camera_next")).is_true()


func test_h_shifter_engages_gears_with_the_clutch() -> void:
	Players.clear()
	var profile := Settings.primary
	var saved: Dictionary = profile.data.duplicate(true)
	profile.data.input.bindings = _profile().data.input.bindings
	profile.data.assists.auto_gearbox = "off"
	Devices.test_devices = [SHIFTER, LEVER, BOX, PEDALS]
	PlayerInput.test_sim = { "a202:0": -1.0, "a204:2": 1.0 } # clutch pedal down
	var slot := Players.primary_slot()
	for d: Dictionary in [SHIFTER, LEVER, BOX, PEDALS]:
		if d.key not in slot.device_keys:
			slot.device_keys.append(d.key)
	Players.refresh_all()
	var s := TrackSession.new()
	s.platform_id = "official.track.touring" # an H-pattern box
	add_child(s)
	for k in 600:
		await get_tree().process_frame
		if s.players.size() == 1 and s.players[0].vehicle:
			break
	var v := s.players[0].vehicle
	await get_tree().create_timer(0.3).timeout
	assert_bool(s.players[0].controller.assists.auto_clutch).is_false() # there's a clutch pedal
	assert_float(float(v.sim.get_telemetry().clutch)).is_less(0.5) # pedal in
	PlayerInput.test_sim["b201:1"] = true # 2nd
	await get_tree().create_timer(0.4).timeout
	assert_int(v.sim.get_gear()).is_equal(2)
	# Clutch out, 3rd: refused (it grinds), still in 2nd.
	PlayerInput.test_sim["a204:2"] = -1.0
	PlayerInput.test_sim["b201:1"] = false
	PlayerInput.test_sim["b201:2"] = true
	await get_tree().create_timer(0.4).timeout
	assert_int(v.sim.get_gear()).is_equal(2)
	assert_int(int(v.sim.get_telemetry().grinds)).is_greater(0)
	# Clutch in: it goes in.
	PlayerInput.test_sim["a204:2"] = 1.0
	await get_tree().create_timer(0.4).timeout
	assert_int(v.sim.get_gear()).is_equal(3)
	# No gate held: neutral.
	PlayerInput.test_sim["b201:2"] = false
	await get_tree().create_timer(0.4).timeout
	assert_int(v.sim.get_gear()).is_equal(0)
	profile.data = saved
	PlayerInput.test_sim = {}
	s.queue_free()
	await get_tree().process_frame
