extends GdUnitTestSuite
## Ways round an arena (D138, D144): every point of a path is on the floor clear of the wall; a
## crate in the way is gone round, a ramp (a tagged piece) is driven over; outside the outline
## is no way at all.

const ARENA := "res://tests/fixtures/tracks/arena_small.json"

var arena: ArenaLayout
var bodies: Array[Node] = []


func before_test() -> void:
	arena = TrackData.load_file(ARENA).arena


func after_test() -> void:
	for b in bodies:
		b.queue_free()
	bodies.clear()
	await get_tree().physics_frame


## A 4 m crate standing on the floor at `at` (x, z), tagged like a stunt piece if `tag`.
func _crate(at: Vector2, tag := 0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Vehicle.LAYER_WORLD
	if tag:
		body.set_meta(&"noss_tag", tag)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(at.x, arena.floor_y + 1.0, at.y)
	add_child(body)
	bodies.append(body)


func _nav() -> ArenaNav:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nav := ArenaNav.new()
	nav.build(arena, get_tree().root.get_world_3d().direct_space_state)
	return nav


func _passes(path: PackedVector3Array, at: Vector2, half: float) -> bool:
	for i in path.size() - 1:
		for k in 5:
			var p := path[i].lerp(path[i + 1], k / 5.0)
			if absf(p.x - at.x) < half and absf(p.z - at.y) < half:
				return true
	return false


func test_a_path_stays_on_the_floor() -> void:
	var nav := await _nav()
	var from := Vector3(-35, 0, -20)
	var to := Vector3(35, 0, 20)
	var path := nav.path(from, to)
	assert_int(path.size()).is_greater(10)
	for p in path:
		assert_bool(arena.inside(p, ArenaNav.WALL_MARGIN_M * 0.5)).override_failure_message("%s near the wall" % p).is_true()
	assert_vector(path[path.size() - 1]).is_equal_approx(Vector3(35, arena.floor_y, 20), Vector3.ONE * 0.01)
	# Outside the outline: no cell to stand on.
	assert_bool(nav.open(nav.cell_of(Vector3(200, 0, 0)))).is_false()


func test_a_crate_is_gone_round_and_a_ramp_driven_over() -> void:
	_crate(Vector2(0, 0))
	_crate(Vector2(20, 0), VehicleSim.TAG_JUMP)
	var nav := await _nav()
	assert_bool(nav.open(nav.cell_of(Vector3(0, 0, 0)))).is_false()
	assert_bool(nav.open(nav.cell_of(Vector3(20, 0, 0)))).is_true()
	var path := nav.path(Vector3(-20, 0, 0), Vector3(10, 0, 0))
	assert_int(path.size()).is_greater(5)
	assert_bool(_passes(path, Vector2(0, 0), 2.0)).is_false()
	var over := nav.path(Vector3(12, 0, 0), Vector3(28, 0, 0))
	assert_bool(_passes(over, Vector2(20, 0), 1.0)).is_true()
