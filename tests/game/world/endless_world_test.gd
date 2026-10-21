extends GdUnitTestSuite
## The endless world streams (D156): driving 20 km builds road, ground and props ahead and frees
## them behind, so the count of pieces (and nodes and bodies) stays the same whatever the distance;
## the floating origin moves under it without breaking the road.

var _d := 1500.0


func _world(visual: bool) -> Array:
	var origin: FloatingOrigin = auto_free(FloatingOrigin.new())
	add_child(origin)
	var w := EndlessWorld.new()
	w.gen = EndlessGen.make(2024, 1)
	w.origin = origin
	w.visual = visual
	w.focus = func() -> PackedFloat64Array: return PackedFloat64Array([_d])
	w.focus_points = func() -> PackedVector3Array: return PackedVector3Array([w.road.point_at(_d)])
	add_child(w)
	auto_free(w)
	return [w, origin]


## Lets the workers finish and the pieces go in.
func _settle(w: EndlessWorld) -> void:
	for i in 400:
		w._process(0.05)
		if w.counts().jobs == 0:
			return
		OS.delay_msec(5)


func test_driving_on_keeps_the_world_the_same_size() -> void:
	var parts := _world(true)
	var w: EndlessWorld = parts[0]
	var origin: FloatingOrigin = parts[1]
	w.prime(_d)
	assert_bool(w.built_at(_d)).is_true()
	_settle(w)
	var sizes: Array = []
	var nodes: Array = []
	for step in 84: # 20 km
		_d += 240.0
		origin.check(w.road.point_at(_d))
		w._process(0.5)
		_settle(w)
		if step >= 20:
			sizes.append(w.counts())
			nodes.append(w.find_children("*", "", true, false).size())
	# The window always covers behind and ahead of the driver.
	assert_float(w.road.offset_m).is_less_equal(_d - EndlessWorld.BEHIND_M + 240.0)
	assert_float(w.road.end_m()).is_greater_equal(_d + EndlessWorld.AHEAD_M)
	assert_bool(w.built_at(_d)).is_true()
	assert_int(origin.shifts).is_greater(5)
	# Near the origin still: the driver is never far from the scene's centre.
	assert_float(Vector2(w.road.point_at(_d).x, w.road.point_at(_d).z).length()).is_less(FloatingOrigin.SHIFT_AT_M + 300.0)
	var lo: int = nodes.min()
	var hi: int = nodes.max()
	print("endless world: road %s, tiles %s, far %s, nodes %d..%d, built %s" % [
		Array(sizes.map(func(s: Dictionary) -> int: return s.road)).max(), Array(sizes.map(func(s: Dictionary) -> int: return s.tiles)).max(),
		Array(sizes.map(func(s: Dictionary) -> int: return s.far)).max(), lo, hi, w.stats])
	for s: Dictionary in sizes:
		assert_int(s.road).is_less_equal(20)
		assert_int(s.tiles).is_less_equal(90)
		assert_int(s.far).is_less_equal(100)
	# Everything built that isn't in the world now was freed: nothing piles up.
	var now := w.counts()
	assert_int(w.stats.road - w.stats.freed_road).is_equal(now.road)
	assert_int(w.stats.tiles - w.stats.freed_tiles).is_equal(now.tiles)
	assert_int(w.stats.far - w.stats.freed_far).is_equal(now.far)
	# Nodes depend on the biome (a forest has more trees than a farm), but never run away.
	assert_int(hi).is_less(60000)


## The road's collision is where its window says the road is, before and after the world moves.
func test_the_road_is_solid_where_the_window_says() -> void:
	var parts := _world(false)
	var w: EndlessWorld = parts[0]
	var origin: FloatingOrigin = parts[1]
	w.prime(_d)
	_settle(w)
	await get_tree().physics_frame
	var space := w.get_world_3d().direct_space_state
	var hit := _down(space, w.road.point_at(_d))
	assert_bool(hit.is_empty()).is_false()
	assert_float(hit.position.y).is_equal_approx(w.road.point_at(_d).y, 0.15)
	origin.shift_by(1500.0, -1500.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	hit = _down(space, w.road.point_at(_d))
	assert_bool(hit.is_empty()).is_false()
	assert_float(hit.position.y).is_equal_approx(w.road.point_at(_d).y, 0.15)


func _down(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 5.0)
	return space.intersect_ray(q)


## Where the road goes onto a bridge or comes off one, the ground stays under the deck: no ramp
## to be launched off (D187).
func test_no_ground_above_a_bridge_deck() -> void:
	var gen := EndlessGen.make(2024, 1)
	var ends: Array[float] = [] # absolute distances where the road is lifted and its neighbour isn't
	var k := 0
	while ends.size() < 6 and k < 400:
		var c := gen.chunk(k)
		var lifted: PackedByteArray = c.lifted
		for i in range(1, lifted.size()):
			if lifted[i] != lifted[i - 1]:
				ends.append(TrackData.SAMPLE_M * (int(c.first) + (i if lifted[i] else i - 1)))
		k += 1
	assert_int(ends.size()).is_greater(1)
	var parts := _world(false)
	var w: EndlessWorld = parts[0]
	var checked := 0
	for at in ends:
		_d = at
		w.prime(at)
		_settle(w)
		await get_tree().physics_frame
		var space := w.get_world_3d().direct_space_state
		for step in range(-30, 31, 2):
			var i := w.road.index_of(at + step)
			if i < 0 or not w.road.lifted[i]:
				continue
			for lat: float in [-1.75, 0.0, 1.75]:
				var p := w.road.samples[i] + w.road.lefts[i] * lat
				var ground := _ground_at(w, p)
				if is_nan(ground):
					continue
				checked += 1
				# Under the deck, clear of it; where it meets the ground, under the road.
				var inside := w.road.lifted[maxi(i - 1, 0)] and w.road.lifted[mini(i + 1, w.road.samples.size() - 1)]
				assert_float(ground).override_failure_message("ground %.2f m over the deck at %.0f m" % [ground - p.y, at + step]).is_less(p.y - (0.6 if inside else 0.0))
				var hit := _down(space, p + Vector3.UP * 0.5)
				if not hit.is_empty():
					assert_float(hit.position.y).is_less(p.y + 0.1)
	assert_int(checked).is_greater(50)


## The ground's own height under a scene point (NAN off the tiles).
func _ground_at(w: EndlessWorld, p: Vector3) -> float:
	var key := Vector2i(floori((p.x + w.origin.x) / EndlessWorld.TILE), floori((p.z + w.origin.z) / EndlessWorld.TILE))
	if not w._tiles.has(key):
		return NAN
	return (w._tiles[key].terrain as TerrainData).height_at(p.x, p.z)


## Props stand on the ground as the road left it: in a cutting, not up where the hill was (D187).
func test_props_stand_on_the_carved_ground() -> void:
	var origin: FloatingOrigin = auto_free(FloatingOrigin.new())
	add_child(origin)
	var w: EndlessWorld = auto_free(EndlessWorld.new())
	w.gen = EndlessGen.make(77, EndlessGen.biome_ids().find("alpine"))
	w.origin = origin
	w.focus = func() -> PackedFloat64Array: return PackedFloat64Array([_d])
	add_child(w)
	w._update_road(PackedFloat64Array([_d]))
	var points := 0
	var moved := 0
	for key: Vector2i in w._wanted_tiles(PackedVector3Array([w.road.point_at(_d)]), 300.0):
		var job := w._tile_job(key)
		if (job.input.road as PackedFloat32Array).is_empty():
			continue
		w._run(job)
		var t: TerrainData = job.result.terrain
		var corner: Vector2 = job.input.corner
		for id: String in job.result.scatter:
			for xf: Transform3D in job.result.scatter[id].all:
				var cell := Vector2(roundf(xf.origin.x - corner.x), roundf(xf.origin.z - corner.y)).clamp(Vector2.ONE, Vector2.ONE * (EndlessWorld.TILE - 1))
				var at := corner + cell
				assert_float(xf.origin.y).is_equal_approx(t.height_at(at.x, at.y), 0.1) # a cell either way at x.5
				points += 1
				if absf(t.height_at(at.x, at.y) - t.base_at(at.x, at.y)) > 0.5:
					moved += 1
	assert_int(points).is_greater(100)
	assert_int(moved).is_greater(0) # some stand where the road cut or filled the ground


## The far ground faces up (as the near ground does), and sinks under the near ground wherever
## that's built, cuttings and all (D187).
func test_far_ground_faces_up_and_stays_under_the_near_ground() -> void:
	var parts := _world(true)
	var w: EndlessWorld = parts[0]
	w.gen = EndlessGen.make(77, EndlessGen.biome_ids().find("alpine"))
	w.prime(_d)
	w._update_ground()
	_settle(w)
	var t0 := Time.get_ticks_usec()
	var lowered := w._far_dirty.size()
	while not w._far_dirty.is_empty():
		w._lower_far(Time.get_ticks_usec())
	print("far ground: %d tiles lowered in %.1f ms" % [lowered, (Time.get_ticks_usec() - t0) / 1000.0])
	assert_int(w._far.size()).is_greater(0)
	# Which way round a triangle faces up: the near ground's grid.
	var grid: PackedInt32Array = TerrainView._grid(1).surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var gv: PackedVector3Array = TerrainView._grid(1).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var up := signf((gv[grid[1]] - gv[grid[0]]).cross(gv[grid[2]] - gv[grid[0]]).y)
	var under := 0
	for key: Vector2i in w._far:
		var mi: MeshInstance3D = w._far[key]
		var arrays := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, index.size(), 3):
			assert_float(signf((v[index[t + 1]] - v[index[t]]).cross(v[index[t + 2]] - v[index[t]]).y)).is_equal(up)
		# Every far vertex over built ground is below the lowest of it round about.
		for p in v:
			var at := p + mi.position
			for dx: float in [-8.0, 8.0]:
				for dz: float in [-8.0, 8.0]:
					var near := _ground_at(w, at + Vector3(dx, 0.0, dz))
					if not is_nan(near):
						assert_float(at.y).is_less_equal(near - EndlessWorld.FAR_DROP_M + 0.01)
						under += 1
	assert_int(under).is_greater(100)


## Guard rails stand on the road's bed where the ground falls away (a fill), not down on the
## ground the fill was made over.
func test_rails_stand_on_the_fill() -> void:
	var gen := EndlessGen.make(2024, 1)
	var checked := 0
	for k in 60:
		var c := RoadWindow.chunk_track(gen.chunk(k), 0.0, 0.0, k)
		var ground := EndlessGround.of(gen, 0.0, 0.0)
		var rb := RoadBuilder.new(c, ground)
		for i in c.samples.size():
			if c.lifted[i] or c.barrier_l[i] == TrackFormat.BARRIER_NONE:
				continue
			var p := rb._barrier_point(i, 1.0)
			var edge := c.samples[i] + c.lefts[i] * c.half_l[i]
			if ground.height_at(edge.x, edge.z) < edge.y - 2.0:
				assert_float(p.y).is_equal_approx(edge.y - TerrainData.BED_DEPTH_M, 0.01)
				checked += 1
	assert_int(checked).is_greater(10)
