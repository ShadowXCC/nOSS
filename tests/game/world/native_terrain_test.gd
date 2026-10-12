extends GdUnitTestSuite
## The native terrain (D90, D91): 16-bit heights survive the PNG round trip through Godot's
## deflate, HeightMapShape3D collision matches the heights, and the sim reads painted surfaces.


func _noisy(side := 129) -> NossTerrain:
	var t := NossTerrain.new()
	t.create(side, side, Vector2(-(side - 1) / 2.0, -(side - 1) / 2.0), 1.0, 0.0, 0)
	t.brush(4, Vector2.ZERO, 200.0, 6.0, 0.0, 0.0, 0.03, 7) # noise
	t.conform(Rect2i(0, 0, side, side), PackedFloat32Array(), 12.0, 0.05)
	return t


func test_heights_round_trip_through_png() -> void:
	var t := _noisy()
	var u16 := t.get_base_u16(-100.0, 0.01)
	var png := NossTerrain.png16_encode(u16, 129, 129)
	assert_int(png.size()).is_greater(100)
	var back := NossTerrain.new()
	back.create(129, 129, Vector2(-64, -64), 1.0, 0.0, 0)
	assert_str(back.set_base_png(png, -100.0, 0.01)).is_empty()
	assert_bool(back.get_base_u16(-100.0, 0.01) == u16).is_true()
	assert_float(back.base_at(10.0, -7.0)).is_equal_approx(t.base_at(10.0, -7.0), 0.006)
	# Not a 16-bit grey PNG, or the wrong size: refused.
	var rgba := Image.create(129, 129, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	assert_str(back.set_base_png(rgba, -100.0, 0.01)).is_equal("Heightmap must be 16-bit grey")
	var small := NossTerrain.new()
	small.create(65, 65, Vector2.ZERO, 1.0, 0.0, 0)
	assert_str(small.set_base_png(png, -100.0, 0.01)).is_equal("Heightmap too large")


func test_godots_png_loader_keeps_8_bits() -> void:
	# Why the terrain has its own 16-bit PNG code (D90): Godot reads 16-bit PNGs as 8-bit.
	var png := NossTerrain.png16_encode(_noisy().get_base_u16(-100.0, 0.01), 129, 129)
	var img := Image.new()
	img.load_png_from_buffer(png)
	assert_int(img.get_data().size()).is_less_equal(129 * 129 * 2)
	assert_bool(img.get_format() in [Image.FORMAT_L8, Image.FORMAT_LA8, Image.FORMAT_RGB8, Image.FORMAT_RGBA8]).is_true()


## A chunk's collision: a body with a HeightMapShape3D centred on the chunk.
func _chunk_body(t: NossTerrain, chunk := 128) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var map := HeightMapShape3D.new()
	map.map_width = chunk + 1
	map.map_depth = chunk + 1
	map.map_data = t.chunk_collision(0, 0, chunk)
	shape.shape = map
	body.add_child(shape)
	body.position = Vector3(t.get_origin().x + chunk / 2.0, 0.0, t.get_origin().y + chunk / 2.0)
	return body


func test_collision_matches_the_heights() -> void:
	var t := _noisy(257) # a game chunk: 256 m
	var started := Time.get_ticks_usec()
	var body := _chunk_body(t, 256)
	var built_ms := (Time.get_ticks_usec() - started) / 1000.0
	add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := body.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var worst := 0.0
	for i in 200:
		var x := rng.randf_range(-120.0, 120.0)
		var z := rng.randf_range(-120.0, 120.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 100, z), Vector3(x, -100, z)))
		assert_bool(hit.is_empty()).is_false()
		worst = maxf(worst, absf(float(hit.position.y) - t.height_at(x, z)))
	# Both are triangles over the same samples; they may split the cells the other way.
	assert_float(worst).is_less(0.05) # measured 7 mm
	assert_float(built_ms).is_less(20.0) # measured well under 1 ms
	body.queue_free()


func test_a_wheel_reads_the_painted_surface() -> void:
	var t := NossTerrain.new()
	t.create(129, 129, Vector2(-64, -64), 1.0, 0.0, 0)
	t.paint(1, Vector2.ZERO, 30.0, 1.0, 0.0) # layer 1 under the car
	var body := _chunk_body(t)
	body.set_meta(&"noss_surface", VehicleSim.SURFACE_GRASS)
	body.set_meta(&"noss_surface_map", t.surface_map(PackedByteArray([VehicleSim.SURFACE_GRASS, VehicleSim.SURFACE_DIRT, 0, 0, 0, 0, 0, 0])))
	add_child(body)
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var v := Vehicle.create(PlatformLoader.load_official("official.track.gt"), pkg)
	v.position = Vector3(0, 1.0, 0)
	add_child(v)
	for i in 120: # lands and settles
		await get_tree().physics_frame
	var wheels: Array = v.sim.get_telemetry().wheels
	assert_bool(wheels.any(func(w: Dictionary) -> bool: return w.contact)).is_true()
	for w: Dictionary in wheels:
		if w.contact:
			assert_int(int(w.surface)).is_equal(VehicleSim.SURFACE_DIRT)
	v.queue_free()
	pkg.free_scenes()
	body.queue_free()
