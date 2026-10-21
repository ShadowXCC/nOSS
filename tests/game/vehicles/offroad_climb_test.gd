extends GdUnitTestSuite
## Off the endless road (D188): its ground drives like a dirt road, so a car that runs off it can
## climb back up the banks. Track grass keeps its penalty.

const RUN_S := 12.0


## A plain slope of `deg` degrees rising along +z from the origin, of `surface`, with flat ground
## before it; the car starts on the flat, 6 m short, facing up it, at full throttle. How high it
## got in RUN_S, and how fast it was still climbing.
func _climb(platform_id: String, deg: float, surface: int) -> Vector2:
	var world := Node3D.new()
	add_child(world)
	var flat := StaticBody3D.new()
	flat.set_meta(&"noss_surface", surface)
	var flat_shape := CollisionShape3D.new()
	var flat_box := BoxShape3D.new()
	flat_box.size = Vector3(40.0, 1.0, 40.0)
	flat_shape.shape = flat_box
	flat_shape.position = Vector3(0.0, -0.5, -20.0)
	flat.add_child(flat_shape)
	world.add_child(flat)
	var slope := StaticBody3D.new()
	slope.set_meta(&"noss_surface", surface)
	var slope_shape := CollisionShape3D.new()
	var slope_box := BoxShape3D.new()
	slope_box.size = Vector3(40.0, 1.0, 120.0)
	slope_shape.shape = slope_box
	var a := deg_to_rad(deg)
	# The box's top face starts at the origin and rises at `deg`.
	slope_shape.transform = Transform3D(Basis(Vector3.RIGHT, -a), Vector3(0.0, 60.0 * sin(a) - 0.5 * cos(a), 60.0 * cos(a) + 0.5 * sin(a)))
	slope.add_child(slope_shape)
	world.add_child(slope)
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var v := Vehicle.create(PlatformLoader.load_official(platform_id), pkg)
	world.add_child(v)
	v.reset_to(Transform3D(Basis(), Vector3(0.0, 0.6, -6.0))) # a car faces +z
	for i in 30:
		await get_tree().physics_frame
	v.throttle = 1.0
	for i in int(RUN_S * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	var end := v.global_position.y
	var rate := v.linear_velocity.y
	world.queue_free()
	pkg.free_scenes()
	return Vector2(end, rate)


## Climbing still, well up the slope (or stuck, or sliding back).
func _climbs(result: Vector2) -> bool:
	return result.x > 8.0 and result.y > 0.3


func test_the_cruiser_climbs_a_dirt_bank() -> void:
	# Measured: still climbing at 1.4 m/s on 18 degrees, stuck on 20.
	var r: Vector2 = await _climb("official.endless.cruiser", 16.0, VehicleSim.SURFACE_DIRT)
	assert_bool(_climbs(r)).override_failure_message("got to %.1f m, climbing at %.2f m/s" % [r.x, r.y]).is_true()


func test_the_sport_climbs_a_steeper_dirt_bank() -> void:
	# Measured: 2.6 m/s on 21 degrees, stuck on 24.
	var r: Vector2 = await _climb("official.endless.sport", 20.0, VehicleSim.SURFACE_DIRT)
	assert_bool(_climbs(r)).override_failure_message("got to %.1f m, climbing at %.2f m/s" % [r.x, r.y]).is_true()


func test_grass_still_holds_the_cruiser_back() -> void:
	var r: Vector2 = await _climb("official.endless.cruiser", 16.0, VehicleSim.SURFACE_GRASS)
	assert_bool(_climbs(r)).override_failure_message("got to %.1f m, climbing at %.2f m/s" % [r.x, r.y]).is_false()


## An endless tile's ground reads as dirt (rock as concrete) where it isn't the road.
func test_endless_ground_reads_dirt() -> void:
	var origin: FloatingOrigin = auto_free(FloatingOrigin.new())
	add_child(origin)
	var w: EndlessWorld = auto_free(EndlessWorld.new())
	w.gen = EndlessGen.make(5, EndlessGen.biome_ids().find("forest"))
	w.origin = origin
	w.visual = false
	add_child(w)
	w._update_road(PackedFloat64Array([1000.0]))
	var key := Vector2i(floori((w.road.point_at(1000.0).x + origin.x) / EndlessWorld.TILE), floori((w.road.point_at(1000.0).z + origin.z) / EndlessWorld.TILE))
	var job := w._tile_job(key)
	job.input.collide = true
	w._run(job)
	var map: NossSurfaceMap = job.result.map
	var corner: Vector2 = job.input.corner
	var seen := {}
	for z in range(0, EndlessWorld.TILE, 16):
		for x in range(0, EndlessWorld.TILE, 16):
			seen[map.surface_at(corner.x + x, corner.y + z)] = true
	assert_bool(seen.has(VehicleSim.SURFACE_DIRT)).is_true()
	assert_bool(seen.has(VehicleSim.SURFACE_GRASS)).is_false()
