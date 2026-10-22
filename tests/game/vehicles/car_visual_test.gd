extends GdUnitTestSuite
## The visual rig: paint slots, wheel poses, steering wheel (docs/ARCHITECTURE.md §4).

var _visual: CarVisual


func before_test() -> void:
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var platform := PlatformLoader.load_official("official.track.gt").platform
	_visual = auto_free(CarVisual.create(pkg, Fitting.fit(platform, pkg.fit)))


func test_paint_slots_use_paint_shader() -> void:
	var shell := _visual.find_child("shell", true, false) as MeshInstance3D
	var m := shell.get_surface_override_material(0) as ShaderMaterial
	assert_object(m).is_not_null()
	assert_object(m.shader).is_equal(CarVisual.PAINT_SHADER)
	_visual.set_paint("primary", Color.RED, "matte")
	assert_object(m.get_shader_parameter("paint_color")).is_equal(Color.RED)
	assert_float(m.get_shader_parameter("roughness")).is_equal(0.75)


func test_wheel_pose_moves_hub_and_spins_wheel() -> void:
	var hub := _visual.find_child("hub_LF", true, false) as Node3D
	var wheel := _visual.find_child("wheel_LF", true, false) as Node3D
	var rest := hub.position
	_visual.set_wheel(0, 0.3, 1.0, 0.05)
	assert_vector(hub.position).is_equal_approx(rest + Vector3(0, 0.05, 0), Vector3.ONE * 0.0001)
	# +steer turns the wheel's forward (+Z) toward the car's left (+X).
	assert_float((hub.basis * Vector3.FORWARD * -1.0).x).is_greater(0.2)
	assert_float(wheel.basis.get_euler().x).is_equal_approx(1.0, 0.0001)


## Ride height lowers the wheels on the body.
func test_ride_height_drops_the_hubs() -> void:
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	pkg.fit = pkg.fit.duplicate(true)
	pkg.fit.body_lift_m = 0.05
	var platform := PlatformLoader.load_official("official.track.gt").platform
	var lifted: CarVisual = auto_free(CarVisual.create(pkg, Fitting.fit(platform, pkg.fit)))
	var level := _visual.find_child("hub_LF", true, false) as Node3D
	var hub := lifted.find_child("hub_LF", true, false) as Node3D
	assert_vector(hub.position).is_equal_approx(level.position - Vector3(0, 0.05, 0), Vector3.ONE * 0.0001)


func test_steering_wheel_rotates_about_its_center() -> void:
	var sw := _visual.find_child("steering_wheel", true, false) as Node3D
	var rest := sw.transform
	_visual.set_steering_angle(PI / 2.0)
	assert_bool(sw.transform.is_equal_approx(rest)).is_false()
	assert_vector(sw.transform.origin).is_equal_approx(rest.origin, Vector3.ONE * 0.05)


func test_brake_lights_toggle() -> void:
	_visual.set_brake_lights(true)
	assert_float(_visual._brake_materials[0].emission_energy_multiplier).is_equal(CarVisual.BRAKE_ON_ENERGY)
	_visual.set_brake_lights(false)
	assert_float(_visual._brake_materials[0].emission_energy_multiplier).is_equal(CarVisual.BRAKE_OFF_ENERGY)


func test_pca_finds_disc_normal() -> void:
	var points := PackedVector3Array()
	var normal := Vector3(0.1, 0.4, -0.9).normalized()
	var u := normal.cross(Vector3.UP).normalized()
	var v := normal.cross(u)
	for i in 64:
		var a := TAU * i / 64.0
		points.append((u * cos(a) + v * sin(a)) * 0.18 + normal * 0.005 * sin(a * 7.0))
	var axis := Pca.smallest_axis(points)
	assert_float(absf(axis.dot(normal))).is_greater(0.999)
