extends GdUnitTestSuite
## The traffic set (D117): every type's package loads and fits its platform without scaling, none
## shows in the car pickers; light groups switch; a car placed at speed keeps rolling (D120).

var _ground: StaticBody3D


func before() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 2000)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 900)
	_ground.add_child(shape)
	add_child(_ground)


func test_every_type_loads_and_fits_its_platform() -> void:
	for t: Dictionary in TrafficTypes.list():
		var pkg := PackageLoader.load_package("res://content/traffic/" + String(t.model))
		assert_bool(pkg.ok()).override_failure_message("%s: %s" % [t.id, pkg.error]).is_true()
		var platform := PlatformLoader.load_official(String(t.platform))
		assert_bool(platform.ok()).override_failure_message(String(t.platform)).is_true()
		assert_bool(Fitting.compatible(platform.platform, String(pkg.manifest.family))).override_failure_message(t.id).is_true()
		var fit := Fitting.fit(platform.platform, pkg.fit)
		assert_float(fit.scale).override_failure_message(t.id).is_equal_approx(1.0, 0.001)
		# The lane sim's size for it is the model's.
		assert_float(fit.envelope.size.z).override_failure_message(t.id).is_equal_approx(float(t.length_m), 0.25)
		pkg.free_scenes()


func test_traffic_never_shows_in_the_car_pickers() -> void:
	for path in PackageLoader.list_available():
		assert_str(path).not_contains("content/traffic")


func test_light_groups_switch() -> void:
	var pkg := PackageLoader.load_package("res://content/traffic/saloon")
	var v := Vehicle.create(PlatformLoader.load_official("official.traffic.car"), pkg)
	add_child(v)
	var ind: Array = v.visual._light_materials.get("indicator_L", [])
	assert_int(ind.size()).is_greater(0)
	assert_float((ind[0] as BaseMaterial3D).emission_energy_multiplier).is_equal(0.0)
	v.visual.set_indicators(true, false)
	assert_float((ind[0] as BaseMaterial3D).emission_energy_multiplier).is_greater(1.0)
	assert_float(v.visual.light_level("indicator_R")).is_equal(0.0)
	v.visual.set_light("head", 2.0)
	assert_float(v.visual.light_level("head")).is_equal(2.0)
	v.queue_free()


func test_a_car_placed_at_speed_keeps_rolling() -> void:
	var pkg := PackageLoader.load_package("res://content/traffic/hatch")
	var v := Vehicle.create(PlatformLoader.load_official("official.traffic.car"), pkg)
	add_child(v)
	v.visual_every_frame = true
	v.reset_to(Transform3D(Basis(), Vector3(0, 0, 10)), Vector3(0, 0, 25))
	v.throttle = 0.4
	for i in 60:
		await get_tree().physics_frame
	# Half a second on it's still going about 25 m/s and in a sensible gear; no skid off the line.
	assert_float(v.linear_velocity.z).is_between(22.0, 28.0)
	assert_int(v.sim.get_gear()).is_greater(1)
	assert_float(v.sim.get_rpm()).is_greater(1200.0)
	v.queue_free()


func test_distant_traffic_has_a_merged_mesh_per_type() -> void:
	for i in TrafficTypes.list().size():
		var t: Dictionary = TrafficTypes.list()[i]
		var mesh := TrafficModels.far_mesh(i)
		assert_object(mesh).override_failure_message(t.id).is_not_null()
		assert_int(mesh.get_surface_count()).is_greater(2)
		var size := mesh.get_aabb().size
		assert_float(size.z).override_failure_message(t.id).is_equal_approx(float(t.length_m), 0.3)
		assert_float(size.x).override_failure_message(t.id).is_equal_approx(float(t.width_m), 0.3)
		# Paint takes the instance's colour; tail lights glow on the brake bit.
		var kinds := []
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as ShaderMaterial
			kinds.append(int(m.get_shader_parameter("kind")))
		assert_array(kinds).contains([0, 2])


func test_sirens_and_horns_render() -> void:
	assert_int(NossAudio.render_siren("wail").size()).is_equal(4 * 44100 * 2)
	assert_int(NossAudio.render_siren("yelp").size()).is_greater(44100)
	assert_int(NossAudio.render_horn(420.0, 500.0).size()).is_equal(22050 * 2)


## A garage car's far mesh in the endless traffic (D191): as fitted, wheels on the ground, facing
## +z, its paint on the instance colour; none for a model over the triangle cap.
func test_a_garage_cars_far_mesh_stands_where_its_car_would() -> void:
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var platform := PlatformLoader.load_official("official.traffic.car").platform
	var mesh := TrafficModels.far_mesh_of(pkg, platform)
	assert_object(mesh).is_not_null()
	var box := mesh.get_aabb()
	var fit := Fitting.fit(platform, pkg.fit)
	assert_float(box.position.y).is_equal_approx(fit.model_bounds.position.y - fit.ground_y, 0.05)
	assert_float(box.size.z).is_equal_approx(fit.model_bounds.size.z, 0.3)
	assert_float(box.get_center().x).is_equal_approx(0.0, 0.2)
	var paint := 0
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s) as ShaderMaterial
		if m and m.shader == TrafficModels.SHADER and int(m.get_shader_parameter("kind")) == 0:
			paint += 1
	assert_int(paint).is_equal(1)
	assert_object(TrafficModels.far_mesh_of(pkg, platform, 10)).is_null()
	pkg.free_scenes()
