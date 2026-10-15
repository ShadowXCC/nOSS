extends GdUnitTestSuite
## Kart pieces in play (D131-D133, D137), on the kart fixture in Jolt: a kart takes the loop and
## comes down in the exit lane, its place in the race held where the loop stands; it rides the
## wall round a corner; a boost pad takes it past its top speed; a trick off the jump boosts.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"

var s: TrackSession
var p: SessionPlayer


func before() -> void:
	Settings.use_folder("user://tests/kart_stunts")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	s = TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.free_drive()
	add_child(s)
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle and s.players[0].driver:
			break
		await get_tree().physics_frame
	p = s.players[0]
	p.driver.process_mode = Node.PROCESS_MODE_DISABLED # the test drives


func after_test() -> void:
	s.queue_free()
	await get_tree().process_frame


func _piece(id: String) -> Dictionary:
	return s.track.kart.pieces.filter(func(x: Dictionary) -> bool: return x.id == id)[0]


## Steers at `target` (pure pursuit in the kart's own frame) and holds `speed`.
func _drive_at(target: Vector3, speed: float) -> void:
	var v := p.vehicle
	var local := v.global_transform.affine_inverse() * target
	v.steer = clampf(-2.0 * atan2(local.x, maxf(local.z, 0.5)), -1.0, 1.0) # +x is the kart's left
	v.throttle = clampf((speed - v.speed()) * 0.5, 0.0, 1.0)
	v.brake = 0.0


func test_the_loop_round_and_out_in_the_exit_lane() -> void:
	var loop := _piece("loop_1")
	var lanes := s.track.kart.loop_lanes(loop)
	var at := float(loop.at_m)
	var start := s.track.transform_at(at - 50.0, lanes.x)
	p.vehicle.reset_to(start, start.basis.z * 22.0)
	var top := false
	var held := true
	for i in 120 * 8:
		await get_tree().physics_frame
		var com := p.com()
		var prog := s.track.kart.loop_progress(com)
		if not prog.is_empty():
			var t := float(prog.t)
			top = top or (t > 0.45 and t < 0.55)
			if t > 0.1 and t < 0.9: # (the race field looked a tick ago)
				held = held and absf(p.distance - at) < 0.5
			_drive_at(s.track.kart.loop_point(loop, minf(t + 0.04, 1.0)), 22.0)
		else:
			var d := p.distance
			var lane := lanes.y if top else lanes.x
			_drive_at(s.track.transform_at(d + 8.0, lane).origin, 22.0)
		if top and prog.is_empty() and p.distance > at + 40.0:
			break
	assert_bool(top).override_failure_message("never got to the top").is_true()
	assert_bool(held).override_failure_message("its distance moved round the loop").is_true()
	assert_bool(p.towed).is_false()
	assert_float(p.distance).is_greater(at + 30.0)
	assert_float(absf(p.lateral - lanes.y)).is_less(1.5)
	assert_float(p.vehicle.global_basis.y.y).is_greater(0.95)
	assert_float(p.vehicle.speed()).is_greater(15.0)


func test_the_wall_ride_round_the_corner() -> void:
	var wall := _piece("wall_1")
	var d0 := float(wall.at_m) + 20.0
	var face := func(d: float, up: float) -> Transform3D:
		var f := s.track.transform_at(d)
		var i := s.track.index_at(d)
		var out := s.track.half_r[i] + 0.02 + KartLayout.WALL_CURVE_M
		# On the wall's upright face, which looks at the road (the road's left): the kart's up.
		var b := Basis(-f.basis.y, f.basis.x, f.basis.z)
		return Transform3D(b, f.origin - f.basis.x * out + f.basis.y * up)
	var place: Transform3D = face.call(d0, 4.0) # on its upright part (it curves up to 3 m)
	p.vehicle.reset_to(place, place.basis.z * 18.0)
	var rode := 0.0
	for i in 120 * 4:
		await get_tree().physics_frame
		var v := p.vehicle
		var on_wall := int(v.sim.get_kart_state().grounded) >= 2 and v.global_basis.y.dot(s.track.transform_at(p.distance).basis.x) > 0.7
		if not on_wall:
			break
		rode = p.distance - d0
		_drive_at((face.call(p.distance + 8.0, 4.0) as Transform3D).origin, 18.0)
		if rode > 55.0:
			break
	assert_float(rode).is_greater(50.0)


func test_a_boost_pad_and_a_trick() -> void:
	var pad := _piece("pad_1")
	var top := p.vehicle.sim.get_geared_top()
	var start := s.track.transform_at(float(pad.at_m) - 30.0)
	p.vehicle.reset_to(start, start.basis.z * top * 0.95)
	var fastest := 0.0
	for i in 120 * 2:
		await get_tree().physics_frame
		_drive_at(s.track.transform_at(p.distance + 8.0).origin, 40.0)
		fastest = maxf(fastest, p.vehicle.speed())
	assert_int(int(p.vehicle.sim.get_kart_state().boosts)).is_greater_equal(1)
	assert_float(fastest).is_greater(top * 1.05)
	# The jump: in the air off it, the drift button does a trick; landing upright boosts.
	var jump := _piece("jump_1")
	start = s.track.transform_at(float(jump.at_m) - 30.0)
	p.vehicle.reset_to(start, start.basis.z * 20.0)
	var boosts := int(p.vehicle.sim.get_kart_state().boosts)
	var tricked := false
	for i in 120 * 3:
		await get_tree().physics_frame
		_drive_at(s.track.transform_at(p.distance + 8.0).origin, 20.0)
		var airborne := p.vehicle.kart_flags() & VehicleSim.KART_FLAG_AIRBORNE != 0
		p.vehicle.drift = airborne and not tricked and float(p.vehicle.sim.get_kart_state().air_time) > 0.05
		tricked = tricked or bool(p.vehicle.sim.get_kart_state().trick)
	assert_bool(tricked).is_true()
	assert_int(int(p.vehicle.sim.get_kart_state().tricks)).is_equal(1)
	assert_int(int(p.vehicle.sim.get_kart_state().boosts)).is_greater(boosts)
