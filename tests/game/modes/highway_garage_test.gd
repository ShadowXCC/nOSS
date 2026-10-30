extends GdUnitTestSuite
## Garage cars in highway traffic (D239): each car's pick is fixed for the session from the seed,
## only into a type the car fits, about GARAGE_SHARE of those; patrols never. Drawing them never
## touches the lane sim. In a drive a garage car turns physical as itself once its model is here;
## whole models load near a player only, the nearest MOST_WHOLE at most, and go a while after.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"
const LUMEN := "res://content/tracks/lumen_ring"


func before() -> void:
	Settings.use_folder("user://tests/highway_garage")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


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
