extends GdUnitTestSuite
## Grinding along a wall (a bridge's parapet, D218): a car-sized box pressed into it at speed slides
## the length of it with no knock (nothing along the wall catches it) and doesn't spin. Straight,
## nose in a little, and on bends either way; in one piece and in pieces built apart, as the
## endless road's chunks are.
##
## The box stands in for a car: its yaw is damped as tyres would hold it, and a force keeps it
## going and pressed in. Walls built of overlapping boxes (before D218) lost 8 to 15 m/s in one
## tick here, every few joins.

const SAMPLE_M := 2.0
const LENGTH_M := 100.0
const HEIGHT := 1.0 # the parapet's
const THICK := 0.5
const SPEED := 28.0
const CAR := Vector3(1.9, 1.3, 4.5)
## The most speed one tick may take off it: a grind scrubs, a knock takes metres per second.
const KNOCK_DV := 1.5


func test_a_straight_wall_is_smooth() -> void:
	await _check(0.0, 1, 0.0)
	await _check(0.0, 1, 3.0)


func test_a_wall_on_the_outside_of_a_bend_is_smooth() -> void:
	await _check(-1.0 / 150.0, 1, 3.0)


func test_a_wall_on_the_inside_of_a_bend_is_smooth() -> void:
	await _check(1.0 / 150.0, 1, 3.0)


func test_walls_built_apart_meet_smoothly() -> void:
	await _check(0.0, 3, 0.0)
	await _check(-1.0 / 150.0, 3, 3.0)


func _check(curvature: float, pieces: int, nose_deg: float) -> void:
	var r := await _grind(curvature, pieces, nose_deg)
	var what := "(curvature %.4f, %d pieces, nose in %.0f°)" % [curvature, pieces, nose_deg]
	assert_float(r.worst_dv).override_failure_message("knocked %.1f m/s in a tick %s" % [r.worst_dv, what]).is_greater(-KNOCK_DV)
	assert_int(r.snags).override_failure_message("pushed back along the wall %d times %s" % [r.snags, what]).is_equal(0)
	assert_float(r.yaw_rate).override_failure_message("turned at %.2f rad/s %s" % [r.yaw_rate, what]).is_less(1.0)
	if curvature <= 0.0: # on the inside of a bend it leaves the wall
		assert_float(r.touching).override_failure_message("touched for %.0f%% of it %s" % [r.touching * 100.0, what]).is_greater(0.8)


## The path: from the origin heading +z, bending toward +x for curvature > 0, a point every
## SAMPLE_M. The car drives on its -x side.
static func _path(curvature: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var p := Vector3.ZERO
	var heading := 0.0
	for i in int(LENGTH_M / SAMPLE_M) + 1:
		out.append(p)
		p += Vector3(sin(heading), 0.0, cos(heading)) * SAMPLE_M
		heading += curvature * SAMPLE_M
	return out


func _grind(curvature: float, pieces: int, nose_deg: float) -> Dictionary:
	var path := _path(curvature)
	var root := Node3D.new()
	add_child(root)
	var n := path.size() - 1
	for k in pieces: # sharing their end points, as road pieces do
		var b := MeshBatch.new()
		b.wall(path.slice(n * k / pieces, n * (k + 1) / pieces + 1), HEIGHT, THICK, 0.0, 4.0, k > 0, k < pieces - 1)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = b.shape()
		body.add_child(cs)
		root.add_child(body)
	var at := 4
	var t := (path[at + 1] - path[at]).normalized()
	var side := Vector3.UP.cross(t) # toward the wall
	var car := RigidBody3D.new()
	car.mass = 1400.0
	car.gravity_scale = 0.0
	car.axis_lock_linear_y = true
	car.axis_lock_angular_x = true
	car.axis_lock_angular_z = true
	car.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	car.angular_damp = 8.0
	car.contact_monitor = true
	car.max_contacts_reported = 8
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	(box.shape as BoxShape3D).size = CAR
	car.add_child(box)
	root.add_child(car)
	var yaw := atan2(t.x, t.z) + deg_to_rad(nose_deg) # toward the wall
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), path[at] - side * (THICK / 2.0 + CAR.x / 2.0 + 0.3) + Vector3.UP * (CAR.y / 2.0 + 0.15))
	car.linear_velocity = t * SPEED + side * 1.0
	var start := car.global_position
	var last_v := car.linear_velocity
	var r := { "snags": 0, "worst_dv": 0.0, "yaw_rate": 0.0, "touching": 0.0 }
	var ticks := 0
	var touching := 0
	for tick in int(LENGTH_M / SPEED * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		var pos := car.global_position
		var k := _nearest(path, pos)
		if k >= path.size() - 4:
			break
		var tk := (path[k + 1] - path[k]).normalized()
		car.apply_central_force(tk * car.mass * 6.0 + Vector3.UP.cross(tk) * car.mass * 5.0)
		var dv := (car.linear_velocity - last_v).dot(tk)
		last_v = car.linear_velocity
		if pos.distance_to(start) < 15.0: # coming to it, settling against it
			continue
		ticks += 1
		var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
		touching += 1 if state.get_contact_count() > 0 else 0
		for i in state.get_contact_count():
			if absf(state.get_contact_local_normal(i).dot(tk)) > 0.5:
				r.snags += 1
		r.worst_dv = minf(r.worst_dv, dv)
		r.yaw_rate = maxf(r.yaw_rate, absf(car.angular_velocity.y))
	r.touching = float(touching) / maxf(ticks, 1)
	root.free()
	return r


static func _nearest(path: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var d := INF
	for i in path.size():
		var di := Vector2(path[i].x - p.x, path[i].z - p.z).length_squared()
		if di < d:
			d = di
			best = i
	return best
