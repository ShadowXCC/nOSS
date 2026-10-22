extends GdUnitTestSuite
## Name tags over the other players' cars (D199): every local player's HUD has them, bots get
## none; a tag points at its car at any HUD size, goes with the car out of play and with the HUD
## element, and reads in the player's units.


func before() -> void:
	Settings.use_folder("user://tests/nameplates_suite")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://") # the machine's own units again


func test_tags_name_other_players_only() -> void:
	var s := await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	var bot: Racer = s.racers.filter(func(r: Racer) -> bool: return r is AiRacer)[0]
	# The bot beside P2, both in front of P1's camera.
	bot.vehicle.reset_to(Transform3D(p2.vehicle.global_basis, p2.vehicle.global_position + p2.vehicle.global_basis.x * 6.0))
	_look_at(p1, p2)
	var plates := p1.hud.get_node(^"Nameplates") as Nameplates
	assert_object(p2.hud.get_node_or_null(^"Nameplates")).is_not_null()
	Settings.units = "metric" # the machine running the tests may not be
	var cam := p1.cameras.camera
	assert_bool(cam.is_position_behind(bot.vehicle.global_position)).is_false()
	assert_bool(p1.view.viewport.get_visible_rect().has_point(cam.unproject_position(Nameplates.anchor(bot.vehicle)))).is_true()
	var tags := plates.entries()
	assert_int(tags.size()).is_equal(1)
	assert_object(tags[0].racer).is_same(p2)
	assert_str(String(tags[0].text)).starts_with(p2.display_name).ends_with(" m")
	Settings.units = "imperial"
	assert_str(String(plates.entries()[0].text)).ends_with(" ft")
	Settings.units = "metric"
	s.queue_free()
	await get_tree().process_frame


func test_tag_points_at_the_car_at_any_hud_size() -> void:
	var s := await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	_look_at(p1, p2)
	var plates := p1.hud.get_node(^"Nameplates") as Nameplates
	for hud_scale: float in [1.0, 1.5]:
		p1.slot.profile.data.hud_scale = hud_scale
		p1.view.apply_profile()
		assert_float(p1.view.hud_root.scale.x).is_equal_approx(hud_scale, 0.001)
		var tags := plates.entries()
		assert_int(tags.size()).is_equal(1)
		# The tip, back in the view's pixels, is where the camera sees the point over the roof.
		var tip: Vector2 = plates.get_global_transform_with_canvas() * (tags[0].tip as Vector2)
		var want := p1.cameras.camera.unproject_position(Nameplates.anchor(p2.vehicle))
		assert_float(tip.distance_to(want)).is_less(0.5)
	p1.slot.profile.data.hud_scale = 1.0
	p1.view.apply_profile()
	s.queue_free()
	await get_tree().process_frame


func test_no_tag_out_of_play_or_hidden() -> void:
	var s := await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	_look_at(p1, p2)
	var plates := p1.hud.get_node(^"Nameplates") as Nameplates
	assert_int(plates.entries().size()).is_equal(1)
	for flag: String in ["parked", "out", "waiting"]:
		p2.set(flag, true)
		assert_int(plates.entries().size()).is_equal(0)
		p2.set(flag, false)
	# Left the session: the car stays, hidden.
	p2.vehicle.visible = false
	assert_int(plates.entries().size()).is_equal(0)
	p2.vehicle.visible = true
	# The player's HUD element, and the Off preset.
	var profile := p1.slot.profile
	profile.data.hud_hidden = ["nametags"]
	p1.hud.apply_profile(profile)
	assert_int(plates.entries().size()).is_equal(0)
	profile.data.hud_hidden = []
	profile.data.hud_preset = "off"
	p1.hud.apply_profile(profile)
	assert_int(plates.entries().size()).is_equal(0)
	profile.data.hud_preset = "minimal"
	p1.hud.apply_profile(profile)
	assert_int(plates.entries().size()).is_equal(1)
	profile.data.hud_preset = "full"
	p1.hud.apply_profile(profile)
	s.queue_free()
	await get_tree().process_frame


## Free drive: two players on one screen and a bot, all held still.
func _session() -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.autodrive = true
	s.ai_players = 1
	s.ai_racers = 1
	add_child(s)
	await _wait_for_cars(s)
	for r in s.racers:
		r.driver.set_physics_process(false)
		r.vehicle.handbrake = 1.0
	await get_tree().process_frame
	return s


## `p`'s camera held 12 m behind and over `target`'s car, looking at it.
func _look_at(p: SessionPlayer, target: Racer) -> void:
	p.cameras.process_mode = Node.PROCESS_MODE_DISABLED
	var v := target.vehicle
	p.cameras.camera.look_at_from_position(v.global_position - v.global_basis.z * 12.0 + Vector3.UP * 4.0, v.global_position)


func _wait_for_cars(s: TrackSession) -> void:
	for i in 600:
		await get_tree().process_frame
		if not s.racers.is_empty() and s.racers.all(func(p: Racer) -> bool: return p.vehicle != null):
			return
