extends GdUnitTestSuite
## Mounting models on a platform (docs/PLATFORMS.md §4.1, §4.3).

var _platform: Dictionary


func before() -> void:
	_platform = PlatformLoader.load_official("official.track.gt").platform


func test_in_range_model_is_unchanged() -> void:
	var r := Fitting.fit(_platform, _fit(2.55, 1.57))
	assert_float(r.scale).is_equal(1.0)
	assert_float(r.wheelbase).is_equal_approx(2.55, 0.001)
	assert_float(r.track).is_equal_approx(1.57, 0.001)
	assert_array(r.notes).is_empty()
	assert_vector(r.wheels[0].center).is_equal_approx(Vector3(0.785, 0.30, 1.275), Vector3.ONE * 0.001)


func test_long_model_is_scaled_down() -> void:
	var r := Fitting.fit(_platform, _fit(3.54, 2.0))
	assert_float(r.scale).is_equal_approx(2.95 / 3.54, 0.0001)
	assert_float(r.wheelbase).is_equal_approx(2.95, 0.001)
	assert_array(r.notes).contains(["Scaled to 83%"])
	assert_float(r.wheels[0].radius).is_equal_approx(0.3 * r.scale, 0.0001)


## A car on a kart class comes down to a kart's size (D150); a kart-sized model stays as it is.
func test_a_car_on_a_kart_class_is_kart_sized() -> void:
	var kart := PlatformLoader.load_official("official.kart.medium").platform
	var r := Fitting.fit(kart, _fit(2.6, 1.57))
	var cap := float(kart.fit.wheelbase_max_m)
	assert_float(r.scale).is_equal_approx(cap / 2.6, 0.0001)
	assert_float(r.wheelbase).is_equal_approx(cap, 0.001)
	assert_bool(Array(r.notes).any(func(n: String) -> bool: return n.begins_with("Kart size ("))).is_true()
	var small := Fitting.fit(kart, _fit(1.25, 1.15))
	assert_float(small.scale).is_equal(1.0)
	assert_bool(Array(small.notes).any(func(n: String) -> bool: return n.begins_with("Kart size"))).is_false()
	# The nOSS Kart itself fits as it is.
	var pkg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/cars/noss_kart/fit.json"))
	assert_float(Fitting.fit(kart, pkg).scale).is_equal(1.0)


func test_narrow_track_moves_wheels_out() -> void:
	var r := Fitting.fit(_platform, _fit(2.6, 1.37))
	assert_float(r.track).is_equal_approx(1.45, 0.0001)
	assert_array(r.notes).contains(["Wheels moved 4 cm out"])
	var lf: Dictionary = r.wheels.filter(func(w: Dictionary) -> bool: return w.id == "LF")[0]
	var rf: Dictionary = r.wheels.filter(func(w: Dictionary) -> bool: return w.id == "RF")[0]
	assert_float(lf.center.x - rf.center.x).is_equal_approx(1.45, 0.0001)


func test_envelope_is_clamped_to_platform_box() -> void:
	var data := _fit(2.6, 1.6)
	data.envelope = { "min": [-1.5, -0.15, -3.0], "max": [1.5, 2.0, 3.0] }
	var r := Fitting.fit(_platform, data)
	assert_vector(r.envelope.size).is_equal_approx(Vector3(2.05, 1.45, 4.9), Vector3.ONE * 0.0001)
	assert_float(r.envelope.position.y).is_equal_approx(-0.15, 0.0001)


func test_model_transform_applies() -> void:
	var data := _fit(2.6, 1.6)
	data.model_transform = { "scale": 0.01, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] }
	for w: Dictionary in data.wheels:
		w.center = [w.center[0] * 100.0, w.center[1] * 100.0, w.center[2] * 100.0]
		w.radius *= 100.0
	var r := Fitting.fit(_platform, data)
	assert_float(r.wheelbase).is_equal_approx(2.6, 0.001)
	assert_float(r.wheels[0].radius).is_equal_approx(0.3, 0.0001)


func test_compatible_follows_accepts_families() -> void:
	assert_bool(Fitting.compatible(_platform, "car")).is_true()
	assert_bool(Fitting.compatible(_platform, "truck")).is_false()
	var kart := _platform.duplicate(true)
	kart.accepts_families = ["car", "open", "truck"]
	assert_bool(Fitting.compatible(kart, "truck")).is_true()
	kart.erase("accepts_families")
	assert_bool(Fitting.compatible(kart, "car")).is_true() # defaults to its own family


func test_physics_wheels_follow_the_platform_layout() -> void:
	var r := Fitting.fit(_platform, _fit(2.6, 1.6))
	assert_int(r.physics_wheels.size()).is_equal(4)
	assert_array(r.wheel_map).has_size(4)
	for i in 4:
		assert_int(r.wheel_map[i].size()).is_equal(1)
		var pw: Dictionary = r.physics_wheels[r.wheel_map[i][0]]
		assert_vector(pw.center).is_equal_approx(r.wheels[i].center, Vector3.ONE * 0.0001)


func test_three_wheeler_gets_four_physics_wheels() -> void:
	var data := _fit(2.6, 1.6)
	data.wheels = data.wheels.filter(func(w: Dictionary) -> bool: return w.id != "RF")
	data.wheels[0].id = "C1"
	data.wheels[0].side = "C"
	data.wheels[0].center[0] = 0.0
	var r := Fitting.fit(_platform, data)
	assert_int(r.physics_wheels.size()).is_equal(4)
	# The centre wheel shows both front physics wheels, which take the rear's track.
	assert_int(r.wheel_map[0].size()).is_equal(2)
	var front: Array = r.physics_wheels.filter(func(w: Dictionary) -> bool: return w.axle == 1)
	assert_float(front[0].center.x - front[1].center.x).is_equal_approx(1.6, 0.0001)


func test_middle_axle_is_visual_only() -> void:
	var data := _fit(2.6, 1.6)
	for side in ["L", "R"]:
		var x := 0.8 if side == "L" else -0.8
		data.wheels.append({ "id": side + "2", "axle": 2, "side": side, "center": [x, 0.3, -0.5], "radius": 0.3, "width": 0.22 })
	for w: Dictionary in data.wheels:
		if w.id in ["LR", "RR"]:
			w.axle = 3
	var r := Fitting.fit(_platform, data)
	assert_int(r.physics_wheels.size()).is_equal(4)
	assert_float(r.physics_wheels[2].center.z).is_equal_approx(-1.3, 0.0001) # rear = the last axle
	assert_int(r.wheel_map[4].size()).is_equal(1) # the middle wheels follow the rear ones


func test_strict_fitting_uses_the_reference() -> void:
	var r := Fitting.fit(_platform, _fit(2.35, 1.5), "strict")
	var front: Dictionary = r.physics_wheels[0]
	var rear: Dictionary = r.physics_wheels[2]
	assert_float(front.center.z - rear.center.z).is_equal_approx(2.6, 0.0001)
	assert_float(front.center.x - r.physics_wheels[1].center.x).is_equal_approx(1.6, 0.0001)
	assert_float(front.radius).is_equal_approx(0.33, 0.0001)
	assert_float(front.visual_radius).is_equal_approx(0.3, 0.0001)
	assert_float(front.center.y - front.radius).is_equal_approx(r.ground_y, 0.0001)
	assert_vector(r.envelope.size).is_equal_approx(Vector3(1.875, 1.225, 4.35), Vector3.ONE * 0.0001)


func test_hood_and_bumper_cameras() -> void:
	var r := Fitting.fit(_platform, _fit(2.6, 1.6))
	assert_float(r.bumper.z).is_greater(r.model_bounds.end.z)
	assert_float(r.bumper.y).is_equal_approx(0.42, 0.001)
	assert_float(r.hood.z).is_between(r.eye_point.z, r.model_bounds.end.z)
	var data := _fit(2.6, 1.6)
	data.cameras = { "hood": [0.0, 1.1, 0.8], "bumper": null }
	assert_vector(Fitting.fit(_platform, data).hood).is_equal_approx(Vector3(0, 1.1, 0.8), Vector3.ONE * 0.0001)


func test_ground_comes_from_the_wheels() -> void:
	var data := _fit(2.6, 1.6)
	data.ground_y = -0.05
	var r := Fitting.fit(_platform, data)
	assert_float(r.ground_y).is_equal_approx(0.0, 0.0001)
	assert_array(r.notes).contains(["Ground moved 5 cm"])


## The ground is where the driven wheels touch down, as the sim works it out: a wheel up on
## the roof (an import took a turret ring for one) doesn't lift it.
func test_ground_is_where_the_driven_wheels_touch() -> void:
	var r := Fitting.fit(_platform, _with_roof_wheel(_fit(2.6, 1.6)))
	assert_float(r.ground_y).is_equal_approx(0.0, 0.0001)
	var contact := 0.0
	for pw: Dictionary in r.physics_wheels:
		contact += pw.center.y - pw.radius
	assert_float(r.ground_y).is_equal_approx(contact / r.physics_wheels.size(), 0.0001)


## A car with a wheel on its roof stays on the ground when it's placed (it used to be thrown up:
## its real wheels started under the road).
func test_a_car_with_a_roof_wheel_stays_down() -> void:
	var world := Node3D.new()
	add_child(world)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor.add_child(shape)
	world.add_child(floor)
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	pkg.fit = _with_roof_wheel(pkg.fit.duplicate(true))
	var v := Vehicle.create(PlatformLoader.load_official("official.track.gt"), pkg)
	world.add_child(v)
	v.reset_to(Transform3D.IDENTITY)
	var start := v.global_position.y
	var highest := start
	var rising := 0.0
	for i in 60:
		await get_tree().physics_frame
		highest = maxf(highest, v.global_position.y)
		rising = maxf(rising, v.linear_velocity.y)
	world.queue_free()
	pkg.free_scenes()
	assert_float(highest - start).override_failure_message("rose %.2f m" % (highest - start)).is_less(0.1)
	assert_float(rising).is_less(0.5)


## `data` with its rear wheels on axle 3 and a wheel on the roof on axle 2.
static func _with_roof_wheel(data: Dictionary) -> Dictionary:
	for w: Dictionary in data.wheels:
		if int(w.axle) == 2:
			w.axle = 3
	data.wheels.append({ "id": "C2", "axle": 2, "side": "C", "center": [0.0, 2.0, 0.0], "radius": 0.3, "width": 0.2 })
	return data


func _fit(wheelbase: float, track: float) -> Dictionary:
	var wheels := []
	for id in ["LF", "RF", "LR", "RR"]:
		var x := track / 2.0 * (1.0 if id[0] == "L" else -1.0)
		var z := wheelbase / 2.0 if id[1] == "F" else -wheelbase / 2.0
		wheels.append({ "id": id, "axle": 1 if id[1] == "F" else 2, "side": id[0], "center": [x, 0.30, z], "radius": 0.3, "width": 0.22 })
	return {
		"schema": "noss.fit/1",
		"model_transform": { "scale": 1.0, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] },
		"ground_y": 0.0, "wheel_mode": "model", "wheels": wheels,
		"envelope": { "min": [-0.9, 0.0, -2.2], "max": [0.9, 1.3, 2.2] },
	}
