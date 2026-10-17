extends GdUnitTestSuite
## The floating origin (D155): it moves in steps of 1500 m once the focus is 2 km out, everything
## in the group moves back by as much, and a car keeps its speed and isn't reset.

class Mover extends Node3D:
	var moved := Vector3.ZERO
	func origin_shifted(delta: Vector3) -> void:
		moved += delta
		position += delta


func test_it_moves_in_steps_once_the_focus_is_far_enough() -> void:
	var o: FloatingOrigin = auto_free(FloatingOrigin.new())
	add_child(o)
	var m: Mover = auto_free(Mover.new())
	m.add_to_group(&"origin_shift")
	add_child(m)
	m.position = Vector3(2100.0, 5.0, -300.0)
	assert_bool(o.check(Vector3(1900.0, 0.0, 0.0))).is_false()
	assert_bool(o.check(m.position)).is_true()
	assert_float(o.x).is_equal(1500.0)
	assert_float(o.z).is_equal(0.0)
	assert_bool(m.moved.is_equal_approx(Vector3(-1500.0, 0.0, 0.0))).is_true()
	assert_bool(m.position.is_equal_approx(Vector3(600.0, 5.0, -300.0))).is_true() # heights never move
	# World and scene: a point keeps its world place.
	var w := o.to_world(m.position)
	assert_float(w[0]).is_equal(2100.0)
	assert_bool(o.to_scene(w[0], w[1], w[2]).is_equal_approx(m.position)).is_true()
	# Far out on both axes.
	o.check(Vector3(-4400.0, 0.0, 3100.0))
	assert_float(o.x).is_equal(1500.0 - 4500.0)
	assert_float(o.z).is_equal(3000.0)
	assert_int(o.shifts).is_equal(2)


func test_a_car_keeps_its_speed_and_isnt_reset() -> void:
	var v: Vehicle = auto_free(Vehicle.new())
	add_child(v)
	v.global_position = Vector3(1800.0, 2.0, 500.0)
	v.linear_velocity = Vector3(30.0, 0.0, -4.0)
	v.angular_velocity = Vector3(0.0, 0.3, 0.0)
	var resets := v.reset_count
	v.origin_shifted(Vector3(-1500.0, 0.0, 0.0))
	assert_bool(v.global_position.is_equal_approx(Vector3(300.0, 2.0, 500.0))).is_true()
	assert_bool(v.linear_velocity.is_equal_approx(Vector3(30.0, 0.0, -4.0))).is_true()
	assert_bool(v.angular_velocity.is_equal_approx(Vector3(0.0, 0.3, 0.0))).is_true()
	assert_int(v.reset_count).is_equal(resets) # not a placement: online it isn't a teleport


func test_remote_states_move_with_the_world() -> void:
	var b := MotionBuffer.new()
	var s := CarState.new()
	s.time = 1000
	s.xform = Transform3D(Basis(), Vector3(1600.0, 1.0, 0.0))
	b.push(s, 1.0)
	b.shift(Vector3(-1500.0, 0.0, 0.0))
	assert_bool(b.latest().xform.origin.is_equal_approx(Vector3(100.0, 1.0, 0.0))).is_true()


## World textures repeat every 2, 3, 4, 5, 6 m (planar UVs), 4 m (terrain layers) and 250 m
## (colour variation): a 1500 m step is a whole number of each, so nothing jumps.
func test_the_step_keeps_world_textures_in_place() -> void:
	for period in [2.0, 3.0, 4.0, 5.0, 6.0, 250.0]:
		assert_float(fmod(FloatingOrigin.SNAP_M, period)).is_equal(0.0)
	for m: ShaderMaterial in [WorldMaterials.surface(VehicleSim.SURFACE_ASPHALT), WorldMaterials.surface(VehicleSim.SURFACE_CONCRETE),
			WorldMaterials.surface(VehicleSim.SURFACE_GRASS), WorldMaterials.surface(VehicleSim.SURFACE_GRAVEL)]:
		var scale: Vector2 = m.get_shader_parameter("uv_scale")
		assert_float(fmod(FloatingOrigin.SNAP_M * scale.x, 1.0)).is_equal_approx(0.0, 1e-4)
