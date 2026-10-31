extends GdUnitTestSuite
## Garage cars loaded before the drive (D246): a batch loads a list a few at a time, saying how far
## it's got; loaded cars stay for the next batch (none loads again) until let go, or until their
## file changes; out of memory, the rest are left out; leaving mid-batch doesn't hang. Online, the
## start waits for the cars it holds for, and those are kept for the session (pinned). Headless,
## loads are data only.

const DIR := "user://tests/garage_preload/"
const SOURCE := "res://content/cars/noss_box"
const HIGHWAY := "res://tests/fixtures/tracks/highway_ring_small.json"


func before() -> void:
	Settings.use_folder("user://tests/garage_preload")


func after() -> void:
	Settings.use_folder("user://")


func after_test() -> void:
	GaragePreload.clear()


## `n` copies of a built-in car, each a package of its own (a folder in the test's user://).
func _cars(n: int) -> Array[Dictionary]:
	var listed: Dictionary = PackageLoader.read_manifest(SOURCE).files
	var out: Array[Dictionary] = []
	for i in n:
		var dir := DIR + "box_%d" % i
		for file: String in listed.keys() + ["manifest.json"]:
			DirAccess.make_dir_recursive_absolute(dir.path_join(file).get_base_dir())
			DirAccess.copy_absolute(SOURCE.path_join(file), dir.path_join(file))
		out.append({ "path": dir, "platform": {} })
	return out


## Runs a batch of `items` to its end: [loaded, left out, [progress done counts]].
func _run(batch: GaragePreload, items: Array[Dictionary]) -> Array:
	var out := [-1, -1, []]
	batch.items = items
	batch.finished.connect(func(loaded: int, left_out: int) -> void:
		out[0] = loaded
		out[1] = left_out)
	batch.progressed.connect(func(done: int, of: int) -> void:
		assert_int(of).is_equal(items.size())
		(out[2] as Array).append(done))
	add_child(batch)
	for i in 600:
		if out[0] >= 0:
			break
		await get_tree().process_frame
	return out


func test_a_batch_loads_its_cars_and_the_next_loads_none() -> void:
	var items := _cars(5)
	assert_int(GaragePreload.missing(items)).is_equal(5)
	var batch: GaragePreload = auto_free(GaragePreload.new())
	var out: Array = await _run(batch, items)
	assert_array(out.slice(0, 2)).is_equal([5, 0])
	assert_array(out[2]).is_equal([1, 2, 3, 4, 5])
	assert_bool(batch.memory_full).is_false()
	assert_int(GaragePreload.missing(items)).is_equal(0)
	for it in items:
		var e := GaragePreload.get_car(String(it.path))
		assert_bool((e.pkg as VehiclePackage).ok()).is_true()
		assert_str((e.pkg as VehiclePackage).path).is_equal(String(it.path))
	# The next drive's: every car's in already, so it's done at once and loads nothing.
	var again: GaragePreload = auto_free(GaragePreload.new())
	var done := [-1]
	again.items = items
	again.finished.connect(func(loaded: int, _left: int) -> void: done[0] = loaded)
	add_child(again)
	assert_int(done[0]).is_equal(5)
	assert_bool(PackageLoader._running.is_empty()).is_true()


func test_cars_go_when_let_go_or_changed() -> void:
	var items := _cars(3)
	await _run(auto_free(GaragePreload.new()), items)
	# A model in one, to see it freed.
	var lod := Node3D.new()
	(GaragePreload.get_car(String(items[0].path)).pkg as VehiclePackage).lods.append(lod)
	GaragePreload.keep_only([String(items[1].path), String(items[2].path)])
	assert_bool(is_instance_valid(lod)).is_false()
	assert_bool(GaragePreload.get_car(String(items[0].path)).is_empty()).is_true()
	assert_int(GaragePreload.missing(items)).is_equal(1)
	# Its file changed since it was loaded: it isn't loaded any more, and the next batch loads it again.
	GaragePreload._cache[String(items[1].path)].stamp = 1
	assert_bool(GaragePreload.get_car(String(items[1].path)).is_empty()).is_true()
	var out: Array = await _run(auto_free(GaragePreload.new()), items)
	assert_array(out.slice(0, 2)).is_equal([3, 0])
	assert_int(int(GaragePreload.get_car(String(items[1].path)).stamp)).is_equal(GaragePreload.stamp_of(String(items[1].path)))
	GaragePreload.clear()
	assert_int(GaragePreload.missing(items)).is_equal(3)
	assert_bool(GaragePreload._cache.is_empty()).is_true()


## Out of memory, once those in flight are in: the rest are left out, and said so.
func test_out_of_memory_the_rest_are_left_out() -> void:
	var items := _cars(6)
	var starts := [0]
	var batch: GaragePreload = auto_free(GaragePreload.new())
	batch.room = func(in_flight: int) -> bool:
		assert_int(in_flight).is_less(GaragePreload.MOST_PAUSED)
		starts[0] += 1
		return starts[0] <= 2
	var out: Array = await _run(batch, items)
	assert_array(out.slice(0, 2)).is_equal([2, 4])
	assert_bool(batch.memory_full).is_true()
	assert_int(batch.left.size()).is_equal(4)
	for i in 2:
		assert_bool(GaragePreload.get_car(String(items[i].path)).is_empty()).is_false()
	for i in range(2, 6):
		assert_bool(batch.left.has(String(items[i].path))).is_true()
	assert_int((out[2] as Array).back()).is_equal(6)


## Leaving with loads in flight (quitting on the loading screen) waits for them and keeps none.
func test_leaving_mid_batch_doesnt_hang() -> void:
	var items := _cars(4)
	var batch := GaragePreload.new()
	batch.items = items
	add_child(batch)
	assert_bool(batch.busy()).is_true()
	remove_child(batch)
	batch.free()
	assert_bool(PackageLoader._running.is_empty()).is_true()
	for i in 5:
		await get_tree().process_frame
	assert_int(GaragePreload.missing(items)).is_equal(4)


## Online (D246): while the start waits, the cars it holds for that are here load, and are kept for
## the session; it counts those in (or given up) of those it waits for. Once the start's gone, the
## hold ends.
func test_the_start_waits_for_garage_cars_online() -> void:
	var items := _cars(3)
	var m := GarageModels.new()
	m.cars = {
		0: { "car": "a", "path": String(items[0].path), "fits": [], "paint": {} },
		1: { "car": "b", "path": String(items[1].path), "fits": [], "paint": {} },
		2: { "car": "c", "path": "", "fits": [], "paint": {} }, # still on its way
	}
	var holding := [true]
	m.hold_for = func() -> Array: return [0, 1, 2] if holding[0] else []
	add_child(m)
	assert_that(m.sync()).is_equal(Vector2i(0, 0))
	for i in 300:
		if m.pinned.size() == 2:
			break
		await get_tree().process_frame
	assert_that(m.sync()).is_equal(Vector2i(2, 3))
	# The third's files come in: it loads too.
	m.cars[2].path = String(items[2].path)
	for i in 300:
		if m.pinned.size() == 3:
			break
		await get_tree().process_frame
	assert_that(m.sync()).is_equal(Vector2i(3, 3))
	# Kept: never wanted, never let go.
	m.want(0, 0.0, 10.0, 10.0)
	assert_bool(m.wanted.has(0)).is_false()
	m.sweep(GarageModels.UNLOAD_S * 3.0, {})
	assert_int(m.pkgs.size()).is_equal(3)
	for g: int in m.pkgs:
		assert_str((m.pkgs[g] as VehiclePackage).path).is_equal(String(m.cars[g].path))
	# The start's gone: the hold ends.
	holding[0] = false
	for i in 60:
		if not m.hold_for.is_valid():
			break
		await get_tree().process_frame
	assert_bool(m.hold_for.is_valid()).is_false()
	assert_that(m.sync()).is_equal(Vector2i(0, 0))
	m.free()


## Offline the session's traffic has only the cars loaded before the drive (D246), and none without
## garage traffic or with the traffic off.
func test_a_drive_has_only_the_cars_loaded_before_it() -> void:
	var s := TrackSession.new()
	s.track_package = TrackLoader.load_package(HIGHWAY, {}, { "terrain": false })
	s.event = RaceEvent.highway("cruise", false, 150)
	var pool := s.garage_pool_here()
	var built_in := Array(pool).filter(func(d: Dictionary) -> bool: return String(d.path).begins_with("res://"))
	assert_int(built_in.size()).is_greater(0)
	assert_bool(s.garage_pool_here() == pool).is_true() # worked out once
	assert_int(s._garage_for_drive().size()).is_equal(pool.size())
	s.garage_preloaded = true
	assert_int(s._garage_for_drive().size()).is_equal(0)
	var one := String(built_in[0].path)
	GaragePreload._cache[one] = { "pkg": VehiclePackage.new(), "far": null, "stamp": GaragePreload.stamp_of(one) }
	var drive := s._garage_for_drive()
	assert_int(drive.size()).is_equal(1)
	assert_str(String(drive[0].path)).is_equal(one)
	# Far views: fitted to the platform of the first type each car fits.
	var items := GaragePreload.items_of(drive)
	assert_str(String(items[0].platform.get("id", ""))).is_equal(String(EndlessTraffic.weighted_types()[int(drive[0].fits[0])].platform))
	for off: Array in [["garage", false], ["traffic", 0]]:
		var o := TrackSession.new()
		o.track_package = s.track_package
		o.event = RaceEvent.highway("cruise", false, 0 if off[0] == "traffic" else 150)
		o.event.garage_traffic = off[0] != "garage"
		assert_int(o.garage_pool_here().size()).override_failure_message(str(off)).is_equal(0)
		_free_session(o)
	var endless := TrackSession.new()
	endless.event = RaceEvent.endless(31337, 2)
	endless.event.endless_traffic = "off"
	assert_int(endless.garage_pool_here().size()).is_equal(0)
	endless.event.endless_traffic = "heavy"
	endless._garage_pool = null
	assert_int(endless.garage_pool_here().size()).is_equal(pool.size())
	_free_session(endless)
	_free_session(s)


## A session that never started, and the nodes it made to add then.
func _free_session(s: TrackSession) -> void:
	for p: Dictionary in s.get_property_list():
		var v: Variant = s.get(String(p.name))
		if v is Node and is_instance_valid(v) and v != s and (v as Node).get_parent() == null:
			(v as Node).free()
	s.free()
