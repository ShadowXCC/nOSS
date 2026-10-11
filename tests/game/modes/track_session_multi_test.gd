extends GdUnitTestSuite
## Free drive with several local players (LOC-01…LOC-03): separate cars, views, HUDs and lap
## timers; drop-out re-flows the views; pause belongs to the player who paused.


func before() -> void:
	Settings.use_folder("user://tests/session_suite")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_four_players_drive_apart_and_one_drops_out() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.autodrive = true
	s.ai_players = 3
	add_child(s)
	await _wait_for_cars(s)
	assert_int(s.players.size()).is_equal(4)
	assert_int(s.views.views().size()).is_equal(4)
	# Each on their own grid spot, with their own timer and HUD in their own view.
	for i in 4:
		for j in range(i + 1, 4):
			var gap := s.players[i].vehicle.global_position.distance_to(s.players[j].vehicle.global_position)
			assert_float(gap).is_greater(3.0)
			assert_object(s.players[i].timer).is_not_same(s.players[j].timer)
		assert_object(s.players[i].hud.get_viewport()).is_same(s.players[i].view.viewport)
		assert_object(s.players[i].cameras.camera.get_viewport()).is_same(s.players[i].view.viewport)
		assert_bool(s.players[i].cameras.camera.current).is_true()
	# P3 leaves: three views, numbered P1-P3.
	Players.leave(Players.slots[2])
	await get_tree().process_frame
	assert_int(s.players.size()).is_equal(3)
	assert_int(s.views.views().size()).is_equal(3)
	assert_array(Players.slots.map(func(p: PlayerSlot) -> String: return p.tag())).is_equal(["P1", "P2", "P3"])
	s.queue_free()
	await get_tree().process_frame


func test_pause_menu_belongs_to_who_paused() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.autodrive = true
	s.ai_players = 1
	add_child(s)
	await _wait_for_cars(s)
	var p2 := s.players[1]
	s._open_pause(p2)
	var paused := get_tree().paused
	var target := p2.slot.menu_target
	var menu_in_view := p2.overlay != null and p2.overlay.get_viewport() == p2.view.viewport
	s._resume()
	assert_bool(paused).is_true()
	assert_object(target).is_same(p2.view.viewport)
	assert_bool(menu_in_view).is_true()
	assert_object(s.players[0].slot.menu_target).is_null()
	assert_bool(get_tree().paused).is_false()
	assert_object(p2.slot.menu_target).is_null()
	s.queue_free()
	await get_tree().process_frame


func test_a_free_pad_drops_in_mid_drive() -> void:
	Players.clear()
	var pad := { "kind": "gamepad", "key": "pad:test#9", "name": "Test pad", "id": 9, "guid": "test9", "preset": "pad_standard" }
	Devices.test_devices = [pad]
	var s := TrackSession.new()
	s.autodrive = true
	add_child(s)
	await _wait_for_cars(s)
	assert_bool(Players.joining).is_true()
	var slot := Players.join(pad)
	await _wait_for_cars(s)
	Devices.test_devices = []
	assert_int(s.players.size()).is_equal(2)
	assert_object(s.views.view(slot)).is_not_null()
	assert_object(s.players[1].vehicle).is_not_null()
	assert_float(s.players[1].vehicle.global_position.distance_to(s.players[0].vehicle.global_position)).is_greater(3.0)
	s.queue_free()
	await get_tree().process_frame


func test_auto_resolution_steps_down_on_slow_frames() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.autodrive = true
	s.ai_players = 1
	add_child(s)
	await _wait_for_cars(s)
	var auto := Settings.auto_resolution
	Settings.auto_resolution = true
	for i in 40: # 2 s of 20 fps
		s.views._process(0.05)
	var scale := s.views.render_scale
	var vp_scale := s.views.views()[1].viewport.scaling_3d_scale
	Settings.auto_resolution = auto
	assert_float(scale).is_less(1.0)
	assert_float(scale).is_greater_equal(ViewManager.MIN_RENDER_SCALE)
	assert_float(vp_scale).is_less(1.0)
	s.queue_free()
	await get_tree().process_frame


func _wait_for_cars(s: TrackSession) -> void:
	for i in 600:
		await get_tree().process_frame
		if not s.players.is_empty() and s.players.all(func(p: SessionPlayer) -> bool: return p.vehicle != null):
			return
