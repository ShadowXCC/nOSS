extends GdUnitTestSuite
## Remote cars (D84): the state codec, present-time extrapolation and its smoothing, the server
## clock, and a kinematic remote car among physical ones.


func before() -> void:
	Settings.use_folder("user://tests/net_remote")


func after() -> void:
	Settings.use_folder("user://")


func _state(t: float, pos: Vector3, vel := Vector3.ZERO, yaw := 0.0, ang := Vector3.ZERO) -> CarState:
	var s := CarState.new()
	s.id = 7
	s.time = t
	s.xform = Transform3D(Basis(Vector3.UP, yaw), pos)
	s.velocity = vel
	s.angular = ang
	return s


func test_states_round_trip() -> void:
	var s := _state(1234.5678, Vector3(-1520.123, 3.456, 987.001), Vector3(55.5, -0.25, 3.0), 1.1, Vector3(0.1, 0.8, -0.05))
	s.xform.basis = Basis(Vector3(0.3, 0.9, 0.1).normalized(), 2.4)
	s.steer = -0.31
	s.lift = PackedFloat32Array([0.05, -0.02, 0.0, 0.11])
	s.throttle = 0.6
	s.brake = 0.2
	s.gear = 4
	s.rpm = 6512
	s.flags = CarState.FLAG_BRAKE | CarState.FLAG_TELEPORT
	var bytes := PackedByteArray()
	bytes.resize(CarState.SIZE)
	s.encode(bytes, 0)
	var back := CarState.decode(bytes, 0, 1234.0)
	assert_int(back.id).is_equal(7)
	assert_float(back.time).is_equal_approx(1234.568, 0.0011)
	assert_float(back.xform.origin.distance_to(s.xform.origin)).is_less(0.002)
	var dq := back.xform.basis.get_rotation_quaternion().angle_to(s.xform.basis.get_rotation_quaternion())
	assert_float(rad_to_deg(dq)).is_less(0.3)
	assert_float(back.velocity.distance_to(s.velocity)).is_less(0.05)
	assert_float(back.angular.distance_to(s.angular)).is_less(0.002)
	assert_float(back.steer).is_equal_approx(-0.31, 0.01)
	assert_float(back.lift[3]).is_equal_approx(0.11, 0.006)
	assert_float(back.throttle).is_equal_approx(0.6, 0.005)
	assert_int(back.gear).is_equal(4)
	assert_float(back.rpm).is_equal(6512.0)
	assert_int(back.flags).is_equal(CarState.FLAG_BRAKE | CarState.FLAG_TELEPORT)


func test_time_wraps_and_bad_numbers() -> void:
	# The 32-bit milliseconds wrap every 49.7 days; the decoder picks the time nearest now.
	var s := _state(4294967.0 + 2.0, Vector3.ZERO) # just past a wrap
	var bytes := PackedByteArray()
	bytes.resize(CarState.SIZE)
	s.encode(bytes, 0)
	assert_float(CarState.decode(bytes, 0, 4294966.5).time).is_equal_approx(4294969.0, 0.002)
	bytes.encode_half(21, INF)
	assert_object(CarState.decode(bytes, 0, 0.0)).is_null()


func test_states_pack_into_packets() -> void:
	var states: Array[CarState] = []
	for i in 30:
		states.append(_state(10.0 + i, Vector3(i, 0, 0)))
	var packets := NetSession.pack(states)
	assert_int(packets.size()).is_equal(2)
	assert_int(packets[0].size()).is_less(1100)
	var back := NetSession.unpack(packets[1], 30.0)
	assert_int(back.size()).is_equal(6)
	assert_float(back[5].xform.origin.x).is_equal_approx(29.0, 0.001)
	assert_array(NetSession.unpack(packets[0].slice(0, 50), 0.0)).is_empty()


func test_rotation_packing_everywhere() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var q := Quaternion(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var back := CarState.unpack_rotation(CarState.pack_rotation(q))
		assert_float(rad_to_deg(back.angle_to(q))).is_less(0.3)


func test_extrapolates_to_now() -> void:
	var b := MotionBuffer.new()
	b.push(_state(0.0, Vector3.ZERO, Vector3(0, 0, 50)), 0.0)
	b.push(_state(0.1, Vector3(0, 0, 5), Vector3(0, 0, 50)), 0.1)
	# 120 ms after the newest state: 6 m further on.
	var p := b.pose(0.22, 0.0)
	assert_float(p.xform.origin.z).is_equal_approx(11.0, 0.05)
	# Turning at 0.5 rad/s: the heading follows.
	var t := MotionBuffer.new()
	t.push(_state(0.0, Vector3.ZERO, Vector3(0, 0, 20), 0.0, Vector3(0, 0.5, 0)), 0.0)
	var yaw: float = (t.pose(0.2, 0.0).xform as Transform3D).basis.get_euler().y
	assert_float(yaw).is_equal_approx(0.1, 0.002)
	# Never more than half a second ahead.
	var far := b.pose(5.0, 0.0)
	assert_float(far.xform.origin.z).is_equal_approx(5.0 + 50.0 * MotionBuffer.MAX_EXTRAPOLATE_S, 0.1)


func test_braking_is_predicted() -> void:
	var b := MotionBuffer.new()
	b.push(_state(0.0, Vector3.ZERO, Vector3(0, 0, 50)), 0.0)
	b.push(_state(0.1, Vector3(0, 0, 4.9), Vector3(0, 0, 48)), 0.1) # -20 m/s²
	var p := b.pose(0.2, 0.0)
	# 4.9 + 48 * 0.1 - 0.5 * 20 * 0.01
	assert_float(p.xform.origin.z).is_equal_approx(9.6, 0.02)
	assert_float(p.velocity.z).is_equal_approx(46.0, 0.05)


func test_corrections_fade_and_placed_cars_snap() -> void:
	var b := MotionBuffer.new()
	b.push(_state(0.0, Vector3.ZERO, Vector3(0, 0, 10)), 0.0)
	var shown: Vector3 = b.pose(0.1, 1.0 / 60.0).xform.origin
	# The owner swerved: the next state is 1 m to the side of the prediction.
	b.push(_state(0.1, Vector3(1, 0, 1), Vector3(0, 0, 10)), 0.1)
	var next: Vector3 = b.pose(0.1, 1.0 / 60.0).xform.origin
	assert_float(next.distance_to(shown)).is_less(0.15) # no jump
	for i in 60:
		next = b.pose(0.1 + i / 60.0, 1.0 / 60.0).xform.origin
	assert_float(next.x).is_equal_approx(1.0, 0.02) # faded out in a second
	# Placed elsewhere (a reset): straight there.
	var placed := _state(0.2, Vector3(100, 0, 0))
	placed.flags = CarState.FLAG_TELEPORT
	b.push(placed, 0.2)
	assert_float(b.pose(0.2, 1.0 / 60.0).xform.origin.x).is_equal_approx(100.0, 0.01)
	# Old states are dropped.
	assert_bool(b.push(_state(0.15, Vector3.ZERO), 0.2)).is_false()


func test_interpolation_mode() -> void:
	var b := MotionBuffer.new()
	b.delay = 0.1
	b.push(_state(0.0, Vector3.ZERO, Vector3(0, 0, 10)), 0.0)
	b.push(_state(0.1, Vector3(0, 0, 1), Vector3(0, 0, 10)), 0.1)
	assert_float(b.pose(0.15, 0.0).xform.origin.z).is_equal_approx(0.5, 0.01)


func test_clock_follows_the_server() -> void:
	var c := ClockSync.new()
	var server_ahead := 1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 12:
		var ping := c.ping_due()
		if ping.is_empty():
			c._next_ping = 0.0
			ping = c.ping_due()
		# Fake trips: 40 ms of path each way plus up to 60 ms of queueing on the way back.
		var sent := ping.decode_double(1)
		var pong := ClockSync.pong(ping, sent + 0.04 + server_ahead)
		c.on_pong(pong, sent + 0.08 + (rng.randf() * 0.06 if i > 0 else 0.0))
	assert_bool(c.synced).is_true()
	assert_float(c.offset).is_equal_approx(server_ahead, 0.02)


func test_kinematic_remote_car() -> void:
	var platform := PlatformLoader.load_official("official.track.gt")
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var world := Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	var remote := Vehicle.create(platform, pkg)
	world.add_child(remote)
	remote.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 0, 10)))
	remote.set_remote(true)
	var car := Vehicle.create(platform, PackageLoader.load_package("res://content/cars/noss_box"))
	world.add_child(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	await get_tree().physics_frame
	# Drive the remote car backwards into the parked one at 5 m/s: the parked one gets pushed.
	var z := 10.0
	for i in 240:
		z -= 5.0 / 120.0
		remote.move_remote(Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), Vector3(0, 0, -5), Vector3.ZERO)
		await get_tree().physics_frame
	assert_float(car.global_position.z).is_less(-0.5)
	assert_float(remote.speed()).is_equal_approx(-5.0, 0.01)
	# Its sim never ran: no wheel spin of its own.
	assert_float(remote.sim.get_speed()).is_equal(0.0)
	world.queue_free()
	await get_tree().process_frame


func test_knocks_with_remote_cars_are_shared() -> void:
	var platform := PlatformLoader.load_official("official.track.gt")
	var world := Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	var remote := Vehicle.create(platform, PackageLoader.load_package("res://content/cars/noss_box"))
	world.add_child(remote)
	remote.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 0, 12)))
	remote.set_remote(true)
	var car := Vehicle.create(platform, PackageLoader.load_package("res://content/cars/noss_box"))
	world.add_child(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	await get_tree().physics_frame
	# The car rolls into the parked remote car at 6 m/s.
	car.linear_velocity = Vector3(0, 0, 6)
	var seen: Array = []
	for i in 180:
		remote.move_remote(Transform3D(Basis.IDENTITY, Vector3(0, 0, 12)), Vector3.ZERO, Vector3.ZERO)
		await get_tree().physics_frame
		if not car.remote_contacts.is_empty():
			seen = car.remote_contacts.duplicate()
			break
	assert_array(seen).is_not_empty()
	assert_object(seen[0][0]).is_same(remote)
	# Equal masses: the other car's share is half the knock, pointing forward for it.
	assert_float((seen[0][1] as Vector3).z).is_less(0.0)
	# A relayed knock moves a car.
	var before := car.linear_velocity
	car.apply_remote_impulse(Vector3(0, 0, -car.mass * 2.0), car.global_position)
	await get_tree().physics_frame
	assert_float(car.linear_velocity.z - before.z).is_less(-1.0)
	world.queue_free()
	await get_tree().process_frame
