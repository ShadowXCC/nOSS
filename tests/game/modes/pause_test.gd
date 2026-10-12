extends GdUnitTestSuite
## The pause menu closes by every route (ACC-08): Resume and back online too, a real mouse click
## on a paused view, and Esc on the whole keyboard (which is both "back" and "pause").


func before() -> void:
	Settings.use_folder("user://tests/pause_suite")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	get_tree().paused = false # a failed test mustn't stall the rest


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


## `driven`: P1 drives (their devices are read); otherwise the autopilot does.
func _session(ai_players := 0, driven := false) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.autodrive = not driven
	s.ai_players = ai_players
	add_child(s)
	return s


func _wait_for_cars(s: TrackSession) -> void:
	for i in 300:
		await get_tree().process_frame
		if not s.players.is_empty() and s.players.all(func(p: SessionPlayer) -> bool: return p.vehicle != null):
			return


func test_online_pause_menu_closes_on_resume_and_back() -> void:
	var s := _session()
	await _wait_for_cars(s)
	var p := s.players[0]
	# Online nobody holds the pause (D86); the menu's owner closes it.
	s.online = { "test": true }
	s._open_pause(p)
	var menu := p.overlay as PauseMenu
	var paused := get_tree().paused
	menu.resumed.emit()
	var closed_by_resume := p.overlay == null
	s._open_pause(p)
	Players.push_action(p.slot.menu_target, "ui_cancel")
	var closed_by_back := p.overlay == null
	s.online = {}
	assert_bool(paused).is_false()
	assert_bool(closed_by_resume).is_true()
	assert_bool(closed_by_back).is_true()
	assert_object(p.slot.menu_target).is_null()
	s.queue_free()
	await get_tree().process_frame


func test_a_click_reaches_a_paused_view() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	var s := _session()
	await _wait_for_cars(s)
	var p := s.players[0]
	s._open_pause(p)
	await _frames()
	assert_bool(get_tree().paused).is_true()
	var resume: Button = (p.overlay as PauseMenu)._buttons[0]
	# The button's middle, from the view's 2D (laid out for 1080p and stretched) into the window.
	var in_view := resume.get_global_transform_with_canvas() * (resume.size / 2.0)
	var view := p.view
	var at := view.get_global_rect().position + in_view * view.size / Vector2(view.viewport.size_2d_override)
	at = root.get_final_transform() * at
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_tree().root.push_input(e)
		await get_tree().process_frame
	root.size = old_size
	assert_bool(get_tree().paused).is_false()
	assert_object(p.overlay).is_null()
	s.queue_free()
	await get_tree().process_frame


func test_escape_on_the_whole_keyboard_closes_the_pause_menu() -> void:
	var s := _session(0, true)
	await _wait_for_cars(s)
	var p := s.players[0]
	s._open_pause(p)
	await _frames()
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	await _frames()
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _frames()
	assert_bool(get_tree().paused).is_false()
	assert_object(p.overlay).is_null()
	s.queue_free()
	await get_tree().process_frame


func test_a_free_pad_does_not_join_while_paused() -> void:
	var pad := { "kind": "gamepad", "key": "pad:test#9", "name": "Test pad", "id": 9, "guid": "test9", "preset": "pad_standard" }
	Devices.test_devices = [pad]
	var s := _session(0, true)
	await _wait_for_cars(s)
	var p := s.players[0]
	s._open_pause(p)
	await _frames()
	var e := InputEventJoypadButton.new()
	e.device = 9
	e.button_index = JOY_BUTTON_A
	e.pressed = true
	Input.parse_input_event(e)
	await _frames()
	var up := e.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await _frames()
	var count := Players.count()
	s._resume()
	await _frames()
	Devices.test_devices = []
	assert_int(count).is_equal(1)
	assert_int(Players.count()).is_equal(1)
	s.queue_free()
	await get_tree().process_frame
