extends GdUnitTestSuite
## Kart sessions (D129-D132): every car gets the kart layer and no track limits; a kart that
## falls off, or is reset, is towed back to the road and put down rolling; slipstream behind a
## car; walls bounce karts back; a kart on its roof rights itself.

const TRACK := "res://content/tracks/proving_ground"


func before() -> void:
	Settings.use_folder("user://tests/kart_session")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(ai := 0) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = TRACK
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.free_drive()
	s.ai_racers = ai
	add_child(s)
	return s


func _wait_for_car(s: TrackSession) -> void:
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle:
			return
		await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_a_kart_session_drives_with_the_layer() -> void:
	var s := _session()
	await _wait_for_car(s)
	var p := s.players[0]
	assert_object(s.kart).is_not_null()
	assert_bool(p.vehicle.sim.has_layer()).is_true()
	assert_float(float(p.vehicle.arcade.grip)).is_equal(1.25)
	assert_bool(p.limits).is_false()
	s.queue_free()
	await get_tree().process_frame


func test_other_classes_drive_without_it() -> void:
	Players.clear()
	var gt := TrackSession.new()
	gt.track_path = TRACK
	gt.platform_id = "official.track.gt"
	gt.event = RaceEvent.free_drive()
	add_child(gt)
	await _wait_for_car(gt)
	assert_object(gt.kart).is_null()
	assert_bool(gt.players[0].vehicle.sim.has_layer()).is_false()
	gt.queue_free()
	await get_tree().process_frame


func test_a_kart_that_falls_off_is_towed_back_rolling() -> void:
	var s := _session()
	await _wait_for_car(s)
	var p := s.players[0]
	await _ticks(30)
	var spot := p.last_valid
	# Well under the road where it is.
	var under := p.vehicle.global_transform
	under.origin.y -= 9.0
	p.vehicle.reset_to(under)
	await _ticks(2)
	assert_bool(p.towed).is_true()
	assert_bool(s.kart.towing(p)).is_true()
	assert_int(p.vehicle.kart_flags() & CarState.KART_TOWED).is_not_equal(0)
	await _ticks(int(1.6 * 120))
	assert_bool(p.towed).is_false()
	var proj := s.track.project(p.vehicle.global_position)
	assert_float(absf(float(proj.lateral))).is_less(1.0)
	assert_float(absf(float(proj.distance) - spot)).is_less(5.0)
	assert_float(p.vehicle.speed()).is_greater(p.vehicle.sim.get_geared_top() * 0.4)
	assert_bool(p.ghosted).is_true()
	await _ticks(int(1.2 * 120))
	assert_bool(p.ghosted).is_false()
	# A manual reset tows too.
	p.reset_car()
	assert_bool(p.towed).is_true()
	s.queue_free()
	await get_tree().process_frame


func test_slipstream_behind_a_car_cuts_the_drag() -> void:
	var s := _session(1)
	await _wait_for_car(s)
	var p := s.players[0]
	var ai: Racer
	for i in 600:
		var others := s.racers.filter(func(r: Racer) -> bool: return r != p and r.vehicle != null and r.driver != null)
		if not others.is_empty():
			ai = others[0]
			break
		await get_tree().physics_frame
	ai.driver.process_mode = Node.PROCESS_MODE_DISABLED
	var at := s.track.transform_at(s.track.start_m + 300.0)
	ai.vehicle.reset_to(at, at.basis.z * 20.0)
	var behind := s.track.transform_at(s.track.start_m + 290.0)
	p.vehicle.reset_to(behind, behind.basis.z * 20.0)
	await _ticks(6)
	assert_float(float(p.vehicle.sim.get_kart_state().drag)).is_less(0.95)
	assert_float(float(ai.vehicle.sim.get_kart_state().drag)).is_equal(1.0)
	s.queue_free()
	await get_tree().process_frame


## A world of its own: flat ground, a wall across the road at z = 40.
func _yard() -> Node3D:
	var world := Node3D.new()
	add_child(world)
	for spec in [[Vector3(200, 1, 400), Vector3(0, -0.5, 100)], [Vector3(30, 1.2, 1), Vector3(0, 0.6, 40.5)]]:
		var body := StaticBody3D.new()
		body.collision_layer = Vehicle.LAYER_WORLD
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[0]
		cs.shape = box
		cs.position = spec[1]
		body.add_child(cs)
		world.add_child(body)
	return world


func _kart(world: Node3D) -> Vehicle:
	var v := Vehicle.create(PlatformLoader.load_official("official.kart.medium"), PackageLoader.load_package("res://content/cars/noss_kart"))
	v.set_arcade(GameModes.arcade(GameModes.mode_for("official.kart.medium")))
	world.add_child(v)
	return v


func test_walls_bounce_a_kart_back() -> void:
	var world := _yard()
	var v := _kart(world)
	v.reset_to(Transform3D(Basis(), Vector3(0, 0, 20)), Vector3(0, 0, 15))
	var back := 0.0
	for i in 240:
		await get_tree().physics_frame
		back = maxf(back, -v.linear_velocity.z)
	assert_float(back).is_greater(15.0 * 0.5)
	world.queue_free()
	await get_tree().process_frame


func test_a_kart_on_its_roof_rights_itself() -> void:
	var world := _yard()
	var v := _kart(world)
	v.reset_to(Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3(0, 1.5, 0)))
	await _ticks(int(2.6 * 120))
	assert_float(v.global_basis.y.y).is_greater(0.9)
	world.queue_free()
	await get_tree().process_frame
