extends GdUnitTestSuite
## Tire tracks (D197): what leaves them, where they lie (under the rear wheels, on the ground),
## never across a jump or a reset, within their budget, moving with the floating origin, and for
## remote cars too.

var _world: Node3D
var _tracks: TireTracks
var _pkg: VehiclePackage


func before_test() -> void:
	_world = Node3D.new()
	add_child(_world)
	_tracks = TireTracks.new()
	_world.add_child(_tracks)


func after_test() -> void:
	_world.free()
	if _pkg:
		_pkg.free_scenes()
		_pkg = null


func test_what_leaves_tracks() -> void:
	var K := TireTracks.Kind
	assert_int(TireTracks.kind(VehicleSim.SURFACE_ASPHALT, 0.0)).is_equal(K.NONE)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_CURB, 0.1)).is_equal(K.NONE)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_ASPHALT, 0.8)).is_equal(K.SNOW_ROAD)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_PAINT, 1.0)).is_equal(K.SNOW_ROAD)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_DIRT, 1.0)).is_equal(K.SNOW)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_GRASS, 0.0)).is_equal(K.GRASS)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_DIRT, 0.0)).is_equal(K.DIRT)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_SAND, 0.0)).is_equal(K.SAND)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_GRAVEL, 0.0)).is_equal(K.GRAVEL)
	# Painted snow is snow whatever the weather, and stays when it melts.
	assert_int(TireTracks.kind(VehicleSim.SURFACE_SNOW, 0.0)).is_equal(K.SNOWFIELD)
	assert_int(TireTracks.kind(VehicleSim.SURFACE_ICE, 1.0)).is_equal(K.SNOWFIELD)
	assert_bool(TireTracks.melts(K.SNOW_ROAD)).is_true()
	assert_bool(TireTracks.melts(K.SNOWFIELD)).is_false()
	assert_bool(TireTracks.melts(K.DIRT)).is_false()


func test_a_car_on_dirt_leaves_tracks_under_its_rear_wheels() -> void:
	_ground(VehicleSim.SURFACE_DIRT)
	var v := _car()
	await _drive(v, 2.5)
	assert_int(_tracks.quad_count()).is_greater(4)
	# Straight along +z on flat ground: every corner lies just above it, beside a rear wheel.
	var rear: Array = []
	for pw: Dictionary in v.fitted.physics_wheels:
		if int(pw.axle) == 2:
			rear.append(v.global_transform * (pw.center as Vector3))
	for p in _corners():
		assert_float(p.y).is_between(TireTracks.LIFT_M - 0.02, TireTracks.LIFT_M + 0.02)
		var beside := false
		for hub: Vector3 in rear:
			beside = beside or absf(p.x - hub.x) < 0.4
		assert_bool(beside).override_failure_message("a corner at x %.2f" % p.x).is_true()


func test_asphalt_leaves_tracks_only_in_snow() -> void:
	_ground(VehicleSim.SURFACE_ASPHALT)
	var v := _car()
	await _drive(v, 1.5)
	assert_int(_tracks.quad_count()).is_equal(0)
	v.set_road(0.0, 1.0)
	await _drive(v, 1.5)
	assert_int(_tracks.quad_count()).is_greater(2)
	for uv2 in _arrays(Mesh.ARRAY_TEX_UV2):
		assert_float((uv2 as Vector2).y).is_equal(1.0) # they go when the snow melts


func test_never_across_a_jump_or_a_reset() -> void:
	_ground(VehicleSim.SURFACE_DIRT)
	var v := _car()
	await _drive(v, 1.5)
	var before := _tracks.quad_count()
	assert_int(before).is_greater(0)
	# Up in the air: nothing laid until it lands.
	v.reset_to(Transform3D(Basis(), v.global_position + Vector3(0.0, 3.0, 12.0)), Vector3(0.0, 0.0, 8.0))
	for i in 20:
		await get_tree().physics_frame
	assert_int(_tracks.quad_count()).is_equal(before)
	await _drive(v, 2.0)
	assert_int(_tracks.quad_count()).is_greater(before)
	for q in _quads():
		assert_float((q[0] as Vector3).distance_to(q[3])).is_less_equal(TireTracks.BREAK_M)


func test_the_oldest_go_first_once_the_budget_is_spent() -> void:
	var cap := _tracks.capacity()
	for i in cap + TireTracks.CHUNK_QUADS / 2:
		var at := Vector3(0.0, 0.0, float(i))
		_tracks._quad(at, at + Vector3.RIGHT * 0.2, at + Vector3(0.2, 0.0, 1.0), at + Vector3.BACK, Vector3.UP, i, i + 1, TireTracks.Kind.DIRT)
	assert_int(_tracks.quad_count()).is_less_equal(cap)
	assert_int(_tracks.quad_count()).is_greater(cap - TireTracks.CHUNK_QUADS)


func test_tracks_move_with_the_floating_origin() -> void:
	_ground(VehicleSim.SURFACE_DIRT)
	var v := _car()
	await _drive(v, 1.5)
	var first: Vector3 = _corners()[0]
	var delta := Vector3(-120.0, 0.0, 40.0)
	_world.get_child(1).position += delta # the ground
	get_tree().call_group(&"origin_shift", &"origin_shifted", delta) # the car, the tracks
	assert_vector(_corners()[0]).is_equal_approx(first + delta, Vector3.ONE * 0.001)
	await _drive(v, 1.5)
	for q in _quads():
		assert_float((q[0] as Vector3).distance_to(q[3])).is_less_equal(TireTracks.BREAK_M)


func test_a_remote_car_leaves_tracks_too() -> void:
	_ground(VehicleSim.SURFACE_GRASS)
	var v := _car()
	v.set_remote(true)
	var at := Vector3(0.0, 0.0, -20.0)
	for i in 240:
		at += Vector3(0.0, 0.0, 10.0) / Engine.physics_ticks_per_second
		v.move_remote(Transform3D(Basis(), at), Vector3(0.0, 0.0, 10.0), Vector3.ZERO)
		await get_tree().physics_frame
	assert_int(_tracks.quad_count()).is_greater(4)


## A flat 200 m square of `surface` with its top at y = 0.
func _ground(surface: int) -> void:
	var body := StaticBody3D.new()
	body.set_meta(&"noss_surface", surface)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	cs.shape = box
	cs.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(cs)
	_world.add_child(body)


## A car at -z, facing +z, its handbrake on.
func _car() -> Vehicle:
	_pkg = PackageLoader.load_package("res://content/cars/noss_box")
	var v := Vehicle.create(PlatformLoader.load_official("official.endless.sport"), _pkg)
	_world.add_child(v)
	v.reset_to(Transform3D(Basis(), Vector3(0.0, 0.6, -20.0)))
	return v


func _drive(v: Vehicle, seconds: float) -> void:
	v.throttle = 0.6
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame


## Every laid quad's corners in world space: [l0, r0, r1, l1].
func _quads() -> Array:
	var out: Array = []
	for mi: MeshInstance3D in _chunks():
		var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for q in verts.size() / 4:
			out.append([verts[4 * q] + mi.position, verts[4 * q + 1] + mi.position, verts[4 * q + 2] + mi.position, verts[4 * q + 3] + mi.position])
	return out


func _corners() -> Array:
	var out: Array = []
	for q: Array in _quads():
		out.append_array(q)
	return out


func _arrays(kind: int) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in _chunks():
		out.append_array(Array((mi.mesh as ArrayMesh).surface_get_arrays(0)[kind]))
	return out


## The chunks with tracks in them (not the tails, redrawn every frame).
func _chunks() -> Array:
	return _tracks.get_children().filter(func(n: Node) -> bool:
		return n is MeshInstance3D and n.name != "Tails" and (n.mesh as ArrayMesh).get_surface_count() > 0)
