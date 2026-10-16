extends GdUnitTestSuite
## Built kart pieces and arenas (D137, D138): each piece carries its surface and tag; a pad sits
## under a centimetre proud, a jump's foot and a loop's ends meet the road with no step, and a
## wall-ride starts at the road's edge; an arena's floor is everywhere inside its wall, the wall
## goes all the way round, and its spawns stand on the floor. A server builds the collision alone.

const KART := "res://tests/fixtures/tracks/kart_small.json"
const ARENA := "res://tests/fixtures/tracks/arena_small.json"


func _build(path: String, visual := true) -> Array:
	var t := TrackData.load_file(path)
	var root := TrackBuilder.build(t, null, { "visual": visual })
	add_child(root)
	await get_tree().physics_frame
	return [t, root]


## Straight down through `p` (world): {position, collider} or {}.
func _down(p: Vector3, up := Vector3.UP) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + up * 4.0, p - up * 4.0)
	return get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)


func _tag(hit: Dictionary) -> int:
	return int((hit.collider as Node).get_meta(&"noss_tag", 0)) if not hit.is_empty() else -1


func test_every_piece_is_built_with_its_tag() -> void:
	var built: Array = await _build(KART)
	var root: Node3D = built[1]
	var tags := { "Stunt_pad_1/PadBody": VehicleSim.TAG_BOOST, "Stunt_loop_1_pad/PadBody": VehicleSim.TAG_BOOST, "Stunt_jump_1/RampBody": VehicleSim.TAG_JUMP,
		"Stunt_wall_1/WallBody": VehicleSim.TAG_STICK, "Stunt_loop_1/LoopBody": VehicleSim.TAG_STICK }
	for path: String in tags:
		var body := root.get_node_or_null("Stunts/" + path)
		assert_object(body).override_failure_message(path).is_not_null()
		assert_int(int(body.get_meta(&"noss_tag", 0))).override_failure_message(path).is_equal(tags[path])
	assert_object(root.get_node_or_null("Stunts/Stunt_row_1")).is_null() # boxes are the session's
	root.queue_free()


func test_pieces_meet_the_road_without_a_step() -> void:
	var built: Array = await _build(KART)
	var t: TrackData = built[0]
	var root: Node3D = built[1]
	var pieces := {}
	for p in t.kart.pieces:
		pieces[p.id] = p
	# The pad: under a centimetre over the road beside it.
	var pad := t.transform_at(float(pieces.pad_1.at_m))
	var on_pad := _down(pad.origin, pad.basis.y)
	var beside := _down(pad.origin + pad.basis.x * 3.0, pad.basis.y)
	assert_int(_tag(on_pad)).is_equal(VehicleSim.TAG_BOOST)
	assert_float(on_pad.position.y - beside.position.y).is_between(0.0, 0.01)
	# The jump: its foot on the road, its lip at its height.
	var jump: Dictionary = pieces.jump_1
	var foot := t.transform_at(float(jump.at_m) - float(jump.length_m) / 2.0 + 0.1)
	var road_y := float(t.point_at(float(jump.at_m) - float(jump.length_m) / 2.0 + 0.1).y)
	var on_foot := _down(foot.origin + foot.basis.y * 0.5, foot.basis.y)
	assert_int(_tag(on_foot)).is_equal(VehicleSim.TAG_JUMP)
	assert_float(on_foot.position.y - road_y).is_less(0.01)
	var lip := t.transform_at(float(jump.at_m) + float(jump.length_m) / 2.0 - 0.05)
	assert_float(_down(lip.origin + lip.basis.y * 3.0, lip.basis.y).position.y - lip.origin.y).is_equal_approx(float(jump.height_m), 0.05)
	# The loop: its ribbon starts on the road in the entry lane.
	var loop: Dictionary = pieces.loop_1
	var lanes := t.kart.loop_lanes(loop)
	var entry := t.transform_at(float(loop.at_m) + 0.1, lanes.x)
	var on_loop := _down(entry.origin + entry.basis.y * 0.3, entry.basis.y)
	assert_int(_tag(on_loop)).is_equal(VehicleSim.TAG_STICK)
	assert_float(on_loop.position.y - entry.origin.y).is_less(0.01)
	# The wall-ride: just past the road's edge, at the road's height.
	var wall: Dictionary = pieces.wall_1
	var d := float(wall.at_m) + 45.0
	var i := t.index_at(d)
	var edge := t.transform_at(d, t.half_l[i] + 0.1) # on the left
	var on_wall := _down(edge.origin + edge.basis.y * 0.3, edge.basis.y)
	assert_int(_tag(on_wall)).is_equal(VehicleSim.TAG_STICK)
	assert_float(absf(on_wall.position.y - edge.origin.y)).is_less(0.02)
	root.queue_free()


func test_an_arena_is_a_floor_inside_a_wall() -> void:
	var built: Array = await _build(ARENA)
	var t: TrackData = built[0]
	var root: Node3D = built[1]
	var a := t.arena
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hits := 0
	while hits < 40:
		var p := Vector3(rng.randf_range(-50, 50), 0, rng.randf_range(-40, 40))
		if not a.inside(p, 0.5):
			continue
		hits += 1
		var hit := _down(p + Vector3.UP * 0.5)
		assert_int(int((hit.collider as Node).get_meta(&"noss_surface", -1))).is_in([VehicleSim.SURFACE_ASPHALT, VehicleSim.SURFACE_PAINT, VehicleSim.SURFACE_CONCRETE])
	var space := get_tree().root.get_world_3d().direct_space_state
	var pieces: Array[RID] = []
	for body: StaticBody3D in root.get_node("Stunts").find_children("*", "StaticBody3D", true, false):
		pieces.append(body.get_rid())
	for k in 36:
		var dir := Vector3(cos(TAU * k / 36.0), 0, sin(TAU * k / 36.0))
		var from := Vector3(a.centre.x, a.floor_y + 0.6, a.centre.y)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 0xFFFFFFFF, pieces)
		var hit := space.intersect_ray(q)
		assert_bool(not hit.is_empty() and (hit.collider as Node).name == "ArenaWallBody").override_failure_message("open at %d°" % (k * 10)).is_true()
	for s in a.spawns:
		var hit := _down(s.origin + Vector3.UP * 0.5)
		assert_str(String((hit.collider as Node).name)).is_equal("ArenaFloorBody")
	assert_object(root.get_node_or_null("Gantry")).is_null()
	root.queue_free()


func test_a_server_builds_the_collision_alone() -> void:
	var built: Array = await _build(KART, false)
	var root: Node3D = built[1]
	assert_int(root.get_node("Stunts").find_children("*", "MeshInstance3D", true, false).size()).is_equal(0)
	assert_int(root.get_node("Stunts").find_children("*", "StaticBody3D", true, false).size()).is_greater(4)
	root.queue_free()
