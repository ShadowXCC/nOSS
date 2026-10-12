extends GdUnitTestSuite
## Terrain at runtime (D90): collision matches the heights across chunks, the drawn chunks'
## bounds hold their heights, files round-trip, and refitting keeps the shaped ground.


func _hilly(chunks := Vector2i(2, 2)) -> TerrainData:
	var t := TerrainData.create(Vector2(-256, -256), chunks)
	t.field.brush(4, Vector2.ZERO, 600.0, 12.0, 0.0, 0.0, 0.01, 5) # noise
	t.field.paint(3, Vector2(40, -30), 25.0, 1.0, 0.3)
	t.conform(null)
	return t


func test_collision_follows_the_heights_across_chunks() -> void:
	var t := _hilly()
	var col := TerrainCollision.build(t)
	add_child(col)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := col.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var worst := 0.0
	for i in 200:
		var x := rng.randf_range(-250.0, 250.0)
		var z := rng.randf_range(-250.0, 250.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -200, z)))
		assert_bool(hit.is_empty()).is_false()
		worst = maxf(worst, absf(float(hit.position.y) - t.height_at(x, z)))
	assert_float(worst).is_less(0.05)
	col.queue_free()


func test_chunks_share_edges_and_bounds_hold_the_heights() -> void:
	var t := _hilly()
	var a := t.field.chunk_collision(0, 0, TerrainData.CHUNK)
	var b := t.field.chunk_collision(1, 0, TerrainData.CHUNK)
	var side := TerrainData.CHUNK + 1
	for z in side:
		assert_float(a[z * side + TerrainData.CHUNK]).is_equal(b[z * side])
	var view := TerrainView.build(t)
	add_child(view)
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 1)]:
		var range := t.field.chunk_range(c.x, c.y, TerrainData.CHUNK)
		var mi := view.get_node("Chunk_%d_%d_x1" % [c.x, c.y]) as MeshInstance3D
		assert_float(mi.custom_aabb.position.y).is_less_equal(range.x)
		assert_float(mi.custom_aabb.end.y).is_greater_equal(range.y)
	assert_int(view.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D).size()).is_equal(4 * 4 + 1)
	view.queue_free()


func test_files_round_trip() -> void:
	var t := _hilly(Vector2i(1, 2))
	var files := t.to_files()
	assert_array(files.keys()).contains_exactly_in_any_order(["terrain/meta.json", "terrain/height.png", "terrain/splat_0.png", "terrain/splat_1.png"])
	var back: Dictionary = TerrainData.from_files(files)
	assert_str(String(back.get("error", ""))).is_empty()
	var u: TerrainData = back.terrain
	assert_vector(u.origin()).is_equal(t.origin())
	assert_float(u.base_at(12.3, 45.6)).is_equal_approx(t.base_at(12.3, 45.6), 0.006)
	assert_bool(u.field.get_splat_rgba(0) == t.field.get_splat_rgba(0)).is_true()
	# A heightmap of the wrong size is refused.
	var bad := files.duplicate()
	bad["terrain/height.png"] = TerrainData.create(Vector2.ZERO, Vector2i(1, 1)).to_files()["terrain/height.png"]
	assert_str(String(TerrainData.from_files(bad).get("error", ""))).is_equal("Heightmap size doesn't match")


func test_refitting_keeps_the_shaped_ground() -> void:
	var t := _hilly(Vector2i(1, 1))
	var bigger := t.fit_to(Rect2(-300, -300, 700, 500), 100.0)
	assert_int(bigger.chunks().x).is_greater_equal(4)
	for p: Vector2 in [Vector2(-100, -100), Vector2(0, 0), Vector2(-20, -200)]:
		assert_float(bigger.base_at(p.x, p.y)).is_equal_approx(t.base_at(p.x, p.y), 0.01)
	assert_bool(bigger.area().encloses(Rect2(-300, -300, 700, 500))).is_true()


func test_surfaces_follow_the_paint() -> void:
	var t := _hilly()
	var map := t.surface_map()
	assert_int(map.surface_at(40.0, -30.0)).is_equal(VehicleSim.SURFACE_GRAVEL) # layer 3
	assert_int(map.surface_at(-200.0, 200.0)).is_equal(VehicleSim.SURFACE_GRASS)
