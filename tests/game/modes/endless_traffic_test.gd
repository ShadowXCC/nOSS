extends GdUnitTestSuite
## Endless traffic (D158): a schedule from the seed and the clock, the same on every game; cars in a
## lane never meet; up cars go up the road and oncoming ones down it; near a player they become
## physics cars and go back; one knocked out of its slot leaves it empty.


func before() -> void:
	Settings.use_folder("user://tests/endless_traffic")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(density := "normal") -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(31337, 2)
	s.event.endless_traffic = density
	s.autodrive = true
	add_child(s)
	return s


func _wait_for_car(s: TrackSession) -> void:
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle:
			return
		await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_the_schedule_is_the_same_everywhere_and_cars_never_meet() -> void:
	var s := _session()
	await _wait_for_car(s)
	var t: EndlessTraffic = s.endless_traffic
	assert_object(t).is_not_null()
	# A second schedule from the same seed on the same road, at the same moment.
	var other := EndlessTraffic.new()
	other.session = s
	other.world = s.endless_world
	other.seed = t.seed
	other.density = t.density
	other.clock = t.now
	other._types = t._types
	other._weights = t._weights
	var a := t.scheduled()
	var b := other.scheduled()
	assert_int(a.size()).is_greater(4)
	# (the first may have some already turned into physics cars: compare where both have them)
	var by_key := {}
	for c: Dictionary in b:
		by_key[c.key] = c
	for c: Dictionary in a:
		assert_bool(by_key.has(c.key)).is_true()
		assert_float(float(c.s)).is_equal_approx(float(by_key[c.key].s), 0.001)
	# In each lane, cars are well apart.
	for lane in [EndlessTraffic.UP, EndlessTraffic.DOWN]:
		var spots: Array = b.filter(func(c: Dictionary) -> bool: return c.lane == lane).map(func(c: Dictionary) -> float: return float(c.s))
		spots.sort()
		for i in range(1, spots.size()):
			assert_float(spots[i] - spots[i - 1]).is_greater(25.0)
	other.free()
	s.queue_free()
	await get_tree().process_frame


func test_up_cars_go_up_the_road_and_oncoming_down() -> void:
	var s := _session()
	await _wait_for_car(s)
	var t: EndlessTraffic = s.endless_traffic
	var before := {}
	for c: Dictionary in t.scheduled():
		before[c.key] = float(c.s)
	await _ticks(240) # 2 s
	var moved := 0
	for c: Dictionary in t.scheduled():
		if before.has(c.key):
			var ds := float(c.s) - float(before[c.key])
			if c.lane == EndlessTraffic.UP:
				assert_float(ds).is_greater(5.0)
			else:
				assert_float(ds).is_less(-5.0)
			moved += 1
	assert_int(moved).is_greater(3)
	s.queue_free()
	await get_tree().process_frame


func test_cars_near_a_player_turn_physical_and_a_knocked_one_leaves_its_slot() -> void:
	var s := _session()
	await _wait_for_car(s)
	var t: EndlessTraffic = s.endless_traffic
	var p := s.players[0]
	# Wait for a car to come near (oncoming ones pass within a minute at this density).
	for i in 120:
		if not t.cars.is_empty():
			break
		await _ticks(30)
	assert_int(t.cars.size()).is_greater(0)
	var key: Vector2i = t.cars.keys()[0]
	var car: EndlessTrafficCar = t.cars[key]
	assert_float(absf(car.s - t.slot_s(key))).is_less(8.0) # where its slot is
	# Knock it hard: it leaves its slot, and the slot stays empty once it's gone.
	car.vehicle.car_impulse = EndlessTrafficCar.KNOCK_NS * 2.0
	await _ticks(2)
	assert_bool(car.left_slot).is_true()
	assert_bool(car.wrecked).is_true()
	# The player goes far away: the car goes.
	p.vehicle.reset_to(s.endless.lane_transform(p.distance + 1200.0))
	await _ticks(60)
	assert_bool(t.cars.has(key)).is_false()
	assert_bool(t.gone.has(key)).is_true()
	for c: Dictionary in t.scheduled():
		assert_bool(c.key == key).is_false()
	s.queue_free()
	await get_tree().process_frame
