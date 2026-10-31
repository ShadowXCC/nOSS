extends GdUnitTestSuite
## Garage cars in highway traffic (D239): each car's pick is fixed for the session from the seed,
## only into a type the car fits, about GARAGE_SHARE of those; patrols never. Drawing them never
## touches the lane sim. In a drive a garage car turns physical as itself once its model is here;
## whole models load near a player only, the nearest MOST_WHOLE at most, and go a while after.
## Models load a few at a time, nearest first, and a physics car that started as the stock car
## becomes its garage car out of sight (D241). Loaded before the drive (D246), they're kept, each
## physics car is its garage car from the start, and a car of each kind is made before it.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"
const LUMEN := "res://content/tracks/lumen_ring"


func before() -> void:
	Settings.use_folder("user://tests/highway_garage")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	GaragePreload.clear() # the other tests stream theirs


## The built-in cars that fit the traffic (the tests never load this PC's garage).
func _pool(seed_value := 4242) -> Array[Dictionary]:
	var built_in := PackedStringArray(Array(PackageLoader.list_available()).filter(func(p: String) -> bool: return p.begins_with("res://")))
	return EndlessTraffic.garage_pool(built_in, seed_value)


func _manager(track: TrackData, count: int, patrols := false) -> TrafficManager:
	var tm := TrafficManager.new()
	assert_bool(tm.setup(track, 7, count, patrols)).is_true()
	return tm


func test_views_only_change_what_is_drawn() -> void:
	var pkg := TrackLoader.load_package(FIXTURE, {}, { "terrain": false })
	var a := TrafficTypes.sim(pkg.track, 3, 120)
	var b := TrafficTypes.sim(pkg.track, 3, 120)
	a.step_to(400)
	b.step_to(400)
	var types := TrafficTypes.list().size()
	var views := PackedInt32Array()
	var colors := PackedColorArray()
	views.resize(120)
	views.fill(-1)
	colors.resize(120)
	colors.fill(Color(0, 0, 0, 0))
	views[5] = types + 2
	colors[5] = Color(0.25, 0.5, 0.75)
	b.set_views(views, colors)
	var cars := PackedVector3Array()
	var plain := a.buffers(0.0, cars, 1e6, false)
	var drawn := b.buffers(0.0, cars, 1e6, false)
	assert_int(drawn.size()).is_equal(types + 3)
	var active := int(a.car(5).flags) & TrafficManager.ACTIVE != 0 and int(a.car(5).flags) & TrafficManager.SHADOW == 0
	if active:
		assert_int(int(drawn[types + 2][1])).is_equal(1)
		var buf: PackedFloat32Array = drawn[types + 2][0]
		assert_float(buf[12]).is_equal_approx(0.25, 0.001)
		assert_float(buf[14]).is_equal_approx(0.75, 0.001)
		var type := int(a.car(5).type)
		assert_int(int(drawn[type][1])).is_equal(int(plain[type][1]) - 1)
	# The lane sim never sees it.
	a.step_to(1200)
	b.step_to(1200)
	assert_int(b.checksum()).is_equal(a.checksum())
	assert_bool(b.full_state() == a.full_state()).is_true()
	# setup() forgets them.
	b = TrafficTypes.sim(pkg.track, 3, 120)
	assert_int(b.buffers(0.0, cars, 1e6, false).size()).is_equal(types)


func test_picks_hold_for_the_seed_and_fit_their_type() -> void:
	var pkg := TrackLoader.load_package(LUMEN, {}, { "terrain": false })
	var pool := _pool()
	assert_int(pool.size()).is_greater(0)
	var tm := _manager(pkg.track, 650, true)
	var again := _manager(pkg.track, 650, true)
	var stock := _manager(pkg.track, 650, true)
	tm.set_garage(pool.duplicate(true))
	again.set_garage(pool.duplicate(true))
	var types := TrafficTypes.list()
	var car_types := ["hatch", "saloon", "suv"].map(func(id: String) -> int: return TrafficTypes.index_of(id))
	var fitting := 0
	var picked := 0
	for i in 650:
		var g := tm.garage_of(i)
		assert_int(g).is_equal(again.garage_of(i))
		assert_int(stock.garage_of(i)).is_equal(-1)
		var type := int(tm.sim.car(i).type)
		if types[type].get("patrol", false):
			assert_int(g).is_equal(-1)
			continue
		if type in car_types:
			fitting += 1
		if g >= 0:
			picked += 1
			assert_bool(type in tm.models.cars[g].fits).override_failure_message("car %d: type %d" % [i, type]).is_true()
			# Drawn in its own paint from the start (its paint is read up front offline).
			assert_float(tm._color_now[i].a).is_equal(1.0)
			assert_bool(tm._color_now[i].is_equal_approx(tm._color_of(i))).is_true()
	assert_float(float(picked) / fitting).override_failure_message("%d of %d" % [picked, fitting]).is_equal_approx(GarageModels.GARAGE_SHARE, 0.06)
	assert_str(tm.picks_check()).is_equal(again.picks_check())
	assert_str(tm.picks_check()).is_not_equal(stock.picks_check())
	# Another seed, other picks.
	var other := TrafficManager.new()
	assert_bool(other.setup(pkg.track, 8, 650, true)).is_true()
	other.set_garage(pool.duplicate(true))
	assert_str(other.picks_check()).is_not_equal(tm.picks_check())
	# No cars to pick from: none.
	var empty: Array[Dictionary] = []
	stock.set_garage(empty)
	for i in 650:
		assert_int(stock.garage_of(i)).is_equal(-1)
	# The traffic itself is the same with garage cars or without.
	tm.sim.step_to(2000)
	stock.sim.step_to(2000)
	assert_int(tm.sim.checksum()).is_equal(stock.sim.checksum())
	for t: TrafficManager in [tm, again, stock, other]:
		t.free()
	# Events are on by default (the Highway page has it On), editor test drives too.
	assert_bool(RaceEvent.highway().garage_traffic).is_true()


func _session() -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.highway.street"
	s.event = RaceEvent.highway("cruise", false, 150)
	s.event.garage_traffic = false # the test's own pool below, not this PC's garage
	s.traffic_seed = 3
	s.autodrive = true
	add_child(s)
	return s


func _wait_for_car(s: TrackSession) -> void:
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle:
			return
		await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_a_garage_car_drives_as_itself_and_models_come_and_go() -> void:
	var s := _session()
	await _wait_for_car(s)
	var tm := s.traffic
	assert_bool(tm.models.cars.is_empty()).is_true()
	tm.set_garage(_pool())
	var seen := false
	for i in 120:
		for car: int in tm.cars:
			var tc: TrafficCar = tm.cars[car]
			if tc.garage >= 0:
				assert_int(tc.garage).is_equal(tm.garage_of(car))
				assert_str(tc.vehicle.package.path).is_equal(String(tm.models.cars[tc.garage].path))
				# Garage cars in traffic wear their own paint, never a livery (a built-in's stock one either).
				if tc.vehicle.visual:
					assert_dict(tc.vehicle.visual.livery).is_empty()
				seen = true
		if seen:
			break
		await _ticks(30)
	assert_bool(seen).is_true()
	# Only cars wanted near a player load whole.
	for g: int in tm.models.pkgs:
		assert_bool(tm.models.wanted_near.has(g)).is_true()
	assert_int(tm.models.pkgs.size()).is_less_equal(TrafficManager.MOST_WHOLE + tm.cars.size())
	# The nearest one at most: the rest go, a sweep at a time (never one a physics car is).
	tm.models.most_whole = 1
	for i in 40:
		await _ticks(int(TrafficManager.STREAM_S * 120.0))
		var driven := {}
		for car: int in tm.cars:
			driven[(tm.cars[car] as TrafficCar).garage] = true
		if tm.models.pkgs.keys().filter(func(g: int) -> bool: return not driven.has(g)).size() <= 1:
			break
	var driven := {}
	for car: int in tm.cars:
		driven[(tm.cars[car] as TrafficCar).garage] = true
	assert_int(tm.models.pkgs.keys().filter(func(g: int) -> bool: return not driven.has(g)).size()).is_less_equal(1)
	# Nobody near for UNLOAD_S: every whole model goes but those driven, and the pool's cars on them.
	s.players[0].driver.set_physics_process(false)
	s.players[0].vehicle.reset_to(s.highway.shoulder_spot(1, fposmod(s.players[0].distance + s.track.length / 2.0, s.track.length)))
	await _ticks(int((TrafficManager.FORCE_BACK_S + 1.0) * 120.0))
	driven.clear()
	for car: int in tm.cars:
		driven[(tm.cars[car] as TrafficCar).garage] = true
	tm.models.sweep(tm._clock + GarageModels.UNLOAD_S + 1.0, driven)
	for g: int in tm.models.pkgs:
		assert_bool(driven.has(g)).is_true()
	for key: Vector2i in tm._pool:
		assert_bool(key.y < 0 or tm.models.pkgs.has(key.y)).override_failure_message("pool %s" % key).is_true()
	s.queue_free()
	await get_tree().process_frame


## Loads go a few at a time (D241): never more than MOST_LOADING_WHOLE in flight, the nearest
## first, and everything wanted is in within a few sweeps. (Far views go the same way; headless
## never loads them.) The registry is one built-in car many times: each entry loads on its own.
func test_models_load_a_few_at_a_time_nearest_first() -> void:
	var one := _pool()[0]
	var pool: Array[Dictionary] = []
	for i in 7:
		pool.append(one.duplicate())
	for most: int in [-1, pool.size()]:
		PackageLoader.clear_shared()
		var m := GarageModels.new()
		m.draws = false # data only, as headless
		m.most_whole = most
		add_child(m)
		m.set_pool(pool)
		var sweeps := 0
		while m.pkgs.size() < pool.size() and sweeps < 40:
			for g: int in m.cars:
				m.want(g, sweeps * 0.5, 10.0 * (pool.size() - g)) # the last is the nearest
			m.sweep(sweeps * 0.5, {})
			var flight := m.loading.keys()
			assert_int(flight.size()).override_failure_message("sweep %d: %s" % [sweeps, flight]).is_less_equal(GarageModels.MOST_LOADING_WHOLE)
			if sweeps == 0:
				assert_bool(m.loading.has(Vector2i(pool.size() - 1, 0)) and m.loading.has(Vector2i(pool.size() - 2, 0))).override_failure_message(str(flight)).is_true()
			for k: Vector2i in flight:
				for g: int in m.cars:
					if g > k.x: # nearer: started already
						assert_bool(m.pkgs.has(g) or m.loading.has(Vector2i(g, 0))).override_failure_message("%d before %d" % [k.x, g]).is_true()
			await _ticks(10)
			sweeps += 1
		assert_int(m.pkgs.size()).is_equal(pool.size())
		assert_int(sweeps).override_failure_message("%d sweeps" % sweeps).is_less_equal(pool.size())
		m.free()


## A physics car that started as the stock car (its model wasn't here yet) becomes its garage car
## once that's loaded, out of every player's sight only (D241); its stock body goes to the pool.
func test_stock_physics_cars_become_garage_cars_out_of_view() -> void:
	var s := _session()
	await _wait_for_car(s)
	var tm := s.traffic
	for i in 60:
		if tm.cars.size() >= 8:
			break
		await _ticks(30)
	var rig := s.players[0].cameras
	var above := func(look: Vector3, fov: float) -> void:
		var at := s.players[0].vehicle.global_position + Vector3.UP * 400.0
		rig.watch(Transform3D(Basis.looking_at(look, Vector3.FORWARD), at), fov)
	# The camera high above, looking down on every car near the player.
	above.call(Vector3.DOWN, 120.0)
	await _ticks(2)
	tm.set_garage(_pool())
	var stock := {} # car -> its stock body, for cars that pick a garage car
	for car: int in tm.cars:
		if tm.garage_of(car) >= 0:
			stock[car] = (tm.cars[car] as TrafficCar).vehicle
	assert_int(stock.size()).is_greater(0)
	var ready := func() -> Array:
		return stock.keys().filter(func(car: int) -> bool: return tm.cars.has(car) and tm.models.pkgs.has(tm.garage_of(car)))
	# Their models load, but they're seen: still stock (two sweeps after the first is in).
	var seen_loaded := 0
	for i in 12:
		await _ticks(int(TrafficManager.STREAM_S * 120.0))
		above.call(Vector3.DOWN, 120.0)
		for car: int in stock:
			if tm.cars.has(car):
				assert_int((tm.cars[car] as TrafficCar).garage).override_failure_message("car %d swapped in view" % car).is_equal(-1)
		if not ready.call().is_empty():
			seen_loaded += 1
			if seen_loaded > 2:
				break
	assert_int(seen_loaded).is_greater(2)
	# Looking up at the sky: they become their garage cars, where they were.
	var swapped := 0
	for i in 10:
		above.call(Vector3.UP, 60.0)
		await _ticks(int(TrafficManager.STREAM_S * 120.0))
		var waiting: Array = ready.call()
		for car: int in waiting.duplicate():
			var tc: TrafficCar = tm.cars[car]
			if tc.garage < 0:
				continue
			waiting.erase(car)
			var old: Vehicle = stock[car]
			assert_int(tc.garage).is_equal(tm.garage_of(car))
			assert_str(tc.vehicle.package.path).is_equal(String(tm.models.cars[tc.garage].path))
			assert_bool(tc.vehicle != old and old.traffic_id != car).is_true()
			assert_bool((tm._pool[Vector2i(int(tm.sim.car(car).type), -1)] as Array).has(old) or old.traffic_id >= 0).is_true()
			swapped += 1
			stock.erase(car)
		if waiting.is_empty() and swapped > 0:
			break
	assert_int(swapped).is_greater(0)
	rig.unwatch()
	s.queue_free()
	await get_tree().process_frame


## Loaded before the drive (D246), as Game does behind the loading screen: every car's pinned (kept,
## never wanted), each physics car is its garage car from the start (never a stand-in), one car of
## each kind is made before the first frame and parked out of the way, and the drawn traffic isn't
## interpolated.
func test_cars_loaded_before_the_drive_drive_as_themselves_from_the_start() -> void:
	var pool := _pool()
	var batch: GaragePreload = auto_free(GaragePreload.new())
	batch.items = GaragePreload.items_of(pool)
	var done := [false]
	batch.finished.connect(func(_loaded: int, _left: int) -> void: done[0] = true)
	add_child(batch)
	for i in 300:
		if done[0]:
			break
		await get_tree().process_frame
	assert_bool(done[0]).is_true()
	Players.clear()
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.highway.street"
	s.event = RaceEvent.highway("cruise", false, 150)
	s.traffic_seed = 3
	s.autodrive = true
	s.garage_preloaded = true
	s._garage_pool = pool # the test's, not this PC's garage
	add_child(s)
	await _wait_for_car(s)
	var tm := s.traffic
	assert_int(tm.models.cars.size()).is_equal(pool.size())
	for g: int in tm.models.cars:
		assert_bool(tm.models.pinned.has(g) and tm.models.pkgs.has(g)).override_failure_message("car %d" % g).is_true()
	# A car of each kind made: parked (out of the way, not among the cars) or driving.
	var kinds := {}
	for i in tm.sim.get_count():
		kinds[Vector2i(int(tm.sim.car(i).type), tm.garage_of(i))] = true
	for kind: Vector2i in kinds:
		var parked: Array = tm._pool.get(kind, [])
		for v: Vehicle in parked:
			assert_bool(v.is_in_group(&"vehicles") or v.process_mode != Node.PROCESS_MODE_DISABLED or not v.freeze).is_false()
		var driving := tm.cars.keys().filter(func(car: int) -> bool:
			return Vector2i(int(tm.sim.car(car).type), (tm.cars[car] as TrafficCar).garage) == kind).size()
		assert_int(parked.size() + driving).override_failure_message("kind %s" % kind).is_greater(0)
	for view: MultiMeshInstance3D in tm._views:
		assert_int(view.physics_interpolation_mode).is_equal(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	# Physics cars: their garage cars from the start.
	var seen := 0
	for i in 40:
		for car: int in tm.cars:
			var tc: TrafficCar = tm.cars[car]
			assert_int(tc.garage).override_failure_message("car %d" % car).is_equal(tm.garage_of(car))
			if tc.garage >= 0:
				assert_str(tc.vehicle.package.path).is_equal(String(tm.models.cars[tc.garage].path))
				seen += 1
		if seen > 20:
			break
		await _ticks(30)
	assert_int(seen).is_greater(0)
	# Nothing loads in the drive, and nothing goes.
	assert_bool(tm.models.loading.is_empty()).is_true()
	tm.models.sweep(tm._clock + GarageModels.UNLOAD_S * 3.0, {})
	assert_int(tm.models.pkgs.size()).is_equal(pool.size())
	s.queue_free()
	await get_tree().process_frame
