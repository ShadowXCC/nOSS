class_name RoadBuilderTest
extends GdUnitTestSuite
## The road builder (EDT-01): pieces per segment for the editor, bridges on lifted road, terrain
## tracks, and the build time that keeps editing interactive (B4 gate).


## A closed loop of about `length` metres: an ellipse with a few kinks, flat or over `ground`.
static func loop_track(length := 3000.0, height := "set", extra := {}) -> Dictionary:
	var d := TrackFormat.blank("loop", "Loop")
	var a := length / 5.1 # an ellipse 1 x 0.6 is about 5.1 a round
	var b := a * 0.6
	var points := []
	for k in 16:
		var t := TAU * k / 16.0
		var wobble := 1.0 + 0.12 * sin(t * 3.0)
		points.append({ "p": [a * cos(t) * wobble, 0.0, b * sin(t) * wobble] })
	d.road.points = points
	d.road.defaults.height = height
	d.road.defaults.merge(extra, true)
	d.race.start_m = 100.0
	return d


func _count(root: Node, cls: String) -> int:
	return root.find_children("*", cls, true, false).size()


func test_a_3_km_track_builds_in_time() -> void:
	var t := TrackData.from_dict(loop_track(3000.0))
	assert_float(t.length).is_between(2700.0, 3600.0)
	var started := Time.get_ticks_usec()
	var root := TrackBuilder.build(t)
	var full_ms := (Time.get_ticks_usec() - started) / 1000.0
	assert_object(root.get_node("Road")).is_not_null()
	assert_object(root.get_node("Lines")).is_not_null()
	# One segment, as a drag rebuilds it.
	var road := RoadBuilder.new(t)
	started = Time.get_ticks_usec()
	var seg := road.build_segment(3)
	var seg_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("build: full %.0f ms, one segment %.1f ms" % [full_ms, seg_ms])
	assert_float(full_ms).is_less(400.0)
	assert_float(seg_ms).is_less(16.0)
	seg.free()
	root.free()


func test_segments_rebuild_on_their_own() -> void:
	var t := TrackData.from_dict(loop_track(2000.0))
	var root := TrackBuilder.build(t, null, { "segmented": true })
	var pieces := root.get_node("Road")
	assert_int(pieces.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Seg_")).size()).is_equal(t.seg_first.size())
	var before := pieces.get_node("Seg_5")
	var kept := pieces.get_node("Seg_9")
	RoadBuilder.new(t).rebuild_segments(pieces, PackedInt32Array([4, 5, 6]))
	assert_bool(is_instance_valid(before) and not before.is_queued_for_deletion()).is_false()
	assert_object(pieces.get_node("Seg_9")).is_same(kept)
	assert_object(pieces.get_node("Seg_5")).is_not_null()
	await get_tree().process_frame
	root.free()


func test_surfaces_and_barriers_follow_the_road() -> void:
	var d := loop_track(2000.0)
	d.road.points[2].surface = "concrete"
	d.road.points[6].barrier_l = "armco"
	d.road.points[6].barrier_r = "armco"
	d.road.points[8].runoff_r = "gravel"
	var t := TrackData.from_dict(d)
	var root := TrackBuilder.build(t)
	assert_object(root.get_node_or_null("Road_Concrete")).is_not_null()
	assert_int(int(root.get_node("Road_ConcreteBody").get_meta(&"noss_surface"))).is_equal(VehicleSim.SURFACE_CONCRETE)
	assert_object(root.get_node_or_null("Armco")).is_not_null()
	assert_int(int(root.get_node("Runoff_GravelBody").get_meta(&"noss_surface"))).is_equal(VehicleSim.SURFACE_GRAVEL)
	assert_object(root.get_node_or_null("Perimeter")).is_not_null()
	root.free()


func test_a_bridge_stands_on_pillars() -> void:
	var eight := [[-300, 0, 0], [0, 0, 0], [300, 0, 0], [300, 4, 300], [0, 8, 300], [0, 8, 0], [0, 8, -300], [-300, 4, -300]]
	var d := TrackFormat.blank("eight", "Eight")
	d.road.points = eight.map(func(p: Array) -> Dictionary: return { "p": p })
	d.road.defaults.height = "set"
	d.race.start_m = 50.0
	var terrain := TerrainData.around(Rect2(-400, -400, 800, 800), 100.0)
	var t := TrackData.from_dict(d, terrain.ground_height())
	terrain.conform(t)
	assert_int(Array(t.lifted).count(1)).is_greater(20)
	var root := TrackBuilder.build(t, terrain)
	var bridge := root.get_node("Bridge") as MeshInstance3D
	assert_object(bridge).is_not_null()
	assert_float(bridge.mesh.get_aabb().position.y).is_less(1.0) # pillars reach the ground
	assert_object(root.get_node_or_null("ConcreteWalls")).is_not_null() # parapets
	# The ground under the bridge is left alone; under the low road it's the road's bed.
	assert_float(terrain.height_at(0.0, 0.0)).is_less(0.5)
	root.free()


## A wall is one strip (D218): nothing on it faces along it (no block ends for a car sliding on it
## to catch), only the 2 cm noses where an open one ends; a closed one has none. Its ends narrow,
## and an end that runs on goes on past its last point.
func test_a_wall_is_one_strip_with_narrow_ends() -> void:
	var path := PackedVector3Array()
	for i in 31:
		var a := i * 2.0 / 120.0
		path.append(Vector3(120.0 * (1.0 - cos(a)), 0.0, 120.0 * sin(a))) # a 120 m radius bend
	for run_on: bool in [false, true]:
		var b := MeshBatch.new()
		b.wall(path, 1.0, 0.5, 0.0, 4.0, false, run_on)
		var ends := _faces_along(b.faces(), path)
		assert_int(ends.size()).is_equal(4) # two noses, two triangles each
		for area: float in ends:
			assert_float(area).is_less(MeshBatch.WALL_NOSE * 1.0 / 2.0 + 0.001)
		var end_dir := (path[-1] - path[-2]).normalized()
		var reach := -INF
		for p in b.faces():
			reach = maxf(reach, (p - path[-1]).dot(end_dir))
		assert_float(reach).is_equal_approx((0.5 - MeshBatch.WALL_NOSE) / 2.0 * MeshBatch.RUN_ON_SLOPE if run_on else 0.0, 0.01)
	var ring := PackedVector3Array()
	for i in 41:
		ring.append(Vector3(cos(TAU * i / 40.0), 0.0, sin(TAU * i / 40.0)) * 30.0)
	var loop := MeshBatch.new()
	loop.wall(ring, 1.0, 0.5)
	assert_array(_faces_along(loop.faces(), ring)).is_empty()


## On the endless road a bridge's parapet that reaches a chunk's end runs on into the next chunk.
func test_endless_parapets_run_on_between_chunks() -> void:
	var gen := EndlessGen.make(2024, 1)
	var checked := 0
	for k in 120:
		var c := RoadWindow.chunk_track(gen.chunk(k), 0.0, 0.0, k)
		var last := c.samples.size() - 1
		if not c.lifted[last] or not c.lifted[last - 1]:
			continue
		var rb := RoadBuilder.new(c, EndlessGround.of(gen, 0.0, 0.0))
		rb.visual = false
		rb.joined_ends = true
		var walls: MeshBatch = rb._batches(0, last)["barrier:4"]
		var reach := -INF
		for p in walls.faces():
			reach = maxf(reach, (p - c.samples[last]).dot(c.tangents[last]))
		assert_float(reach).is_greater(4.0)
		checked += 1
		if checked >= 3:
			break
	assert_int(checked).is_greater(0)


## The areas of the triangles in `faces` that face along `path` (the nearest of its segments).
static func _faces_along(faces: PackedVector3Array, path: PackedVector3Array) -> Array:
	var out := []
	for f in range(0, faces.size(), 3):
		var n := (faces[f + 1] - faces[f]).cross(faces[f + 2] - faces[f])
		var centre := (faces[f] + faces[f + 1] + faces[f + 2]) / 3.0
		var best := 0
		for i in path.size() - 1:
			if centre.distance_squared_to(path[i]) < centre.distance_squared_to(path[best]):
				best = i
		var along := (path[best + 1] - path[best]).normalized()
		if n.length() > 0.0 and absf(n.normalized().dot(along)) > 0.5:
			out.append(n.length() / 2.0)
	return out


func test_a_terrain_track_follows_its_ground() -> void:
	var terrain := TerrainData.around(Rect2(-500, -300, 1000, 600), 200.0)
	terrain.field.brush(0, Vector2(590, 0), 200.0, 15.0, 0.8, 0.0, 0.0, 0) # a hill under the right end
	var d := loop_track(3000.0, "ground")
	var t := TrackData.from_dict(d, terrain.ground_height())
	terrain.conform(t)
	var root := TrackBuilder.build(t, terrain)
	assert_object(root.get_node_or_null("TerrainView")).is_not_null()
	assert_object(root.get_node_or_null("TerrainCollision")).is_not_null()
	# The road sits on its bed: 5 cm above the ground under it, all the way round.
	for i in range(0, t.samples.size(), 7):
		var p := t.samples[i]
		assert_float(p.y - terrain.height_at(p.x, p.z)).is_between(0.0, 0.2)
	var top := t.samples[t.project(Vector3(t.samples[0].x, 0, 0)).index]
	assert_float(top.y).is_greater(5.0) # over the hill
	root.free()


## A banked oval turning left (so its inside is the left), standing on its inner edge: a level
## apron inside, a SAFER wall just outside (D202).
static func oval_track(half := 9.0, bank := -24.0, apron := 9.0) -> Dictionary:
	var d := TrackFormat.blank("oval", "Oval")
	var y := half * sin(deg_to_rad(-bank))
	var points := []
	for end in [1.0, -1.0]: # the top straight and right end, then the bottom and left
		for x in [-200.0, -100.0, 0.0, 100.0, 200.0]:
			points.append({ "p": [x * end, y, 150.0 * end] })
		for deg in [30.0, 60.0, 90.0, 120.0, 150.0]:
			var a := deg_to_rad(deg)
			points.append({ "p": [(200.0 + 150.0 * sin(a)) * end, y, 150.0 * cos(a) * end] })
	d.road.points = points
	d.road.defaults.merge({ "height": "set", "width_l": half, "width_r": half, "bank_deg": bank, "curb_l": "off", "curb_r": "off",
		"apron_l_m": apron, "runoff_l_m": 6.0, "runoff_r_m": 0.3, "barrier_l": "none", "barrier_r": "safer" }, true)
	d.race.start_m = 100.0
	return d


func test_an_oval_has_an_apron_and_a_safer_wall() -> void:
	var terrain := TerrainData.around(Rect2(-400, -200, 800, 400), 100.0)
	var t := TrackData.from_dict(oval_track(), terrain.ground_height())
	terrain.conform(t)
	assert_int(Array(t.lifted).count(1)).is_equal(0) # on its inner edge, not a bridge
	var k := t.segment_samples(7).x # the middle of the right-hand turn
	assert_float(t.cross_point(k, 1.0, 0.0).y).is_equal_approx(0.0, 0.05)
	var mid := t.cross_point(k, 1.0, 4.5)
	assert_float(mid.y).is_equal_approx(t.paved_edge(k, 1.0).y, 0.01) # a level apron
	assert_float(t.edge_at(t.distances[k], 1.0)).is_equal_approx(18.0, 0.01) # it counts as track
	# The ground is shaped to the apron (cut deeper for the bend at the edge, so the 1 m grid stays
	# under the road) and to the banking out to the wall.
	var bend := 0.25 * tan(deg_to_rad(24.0))
	assert_float(terrain.height_at(mid.x, mid.z)).is_equal_approx(mid.y - TerrainData.BED_DEPTH_M - bend, 0.02)
	for step in 40: # across the bend, between the grid's samples, never through the road
		var p := t.cross_point(k, 1.0, -1.5 + step * 0.1)
		assert_float(terrain.height_at(p.x, p.z)).is_less(p.y)
	var outer := t.cross_point(k, -1.0, 0.0)
	assert_float(outer.y).is_greater(7.0)
	assert_float(terrain.height_at(outer.x, outer.z)).is_equal_approx(outer.y - TerrainData.BED_DEPTH_M, 0.15)
	# The apron is road: it's in the road's own piece, so it drives and collides like it.
	var pieces := RoadBuilder.new(t, terrain)._batches(0, t.samples.size())
	var edge := t.paved_edge(k, 1.0)
	var found := false
	for v in (pieces["road:%d" % VehicleSim.SURFACE_ASPHALT] as MeshBatch).verts:
		found = found or v.distance_to(edge) < 0.01
	assert_bool(found).is_true()
	var root := TrackBuilder.build(t, terrain)
	var wall := root.get_node("SaferWalls") as MeshInstance3D
	var fence := root.get_node("CatchFences") as MeshInstance3D
	assert_object(root.get_node_or_null("SaferWallsBody")).is_not_null()
	assert_object(root.get_node_or_null("CatchFencesBody")).is_not_null()
	assert_object(root.get_node_or_null("FencePosts")).is_not_null()
	assert_float(fence.mesh.get_aabb().end.y - wall.mesh.get_aabb().end.y).is_equal_approx(RoadBuilder.CATCH_FENCE[0], 0.01)
	# The gantry's inside foot stands on the apron, not in the air or under it.
	var gantry := root.get_node("Gantry") as MeshInstance3D
	assert_float(gantry.mesh.get_aabb().position.y).is_less(0.5)
	root.free()
