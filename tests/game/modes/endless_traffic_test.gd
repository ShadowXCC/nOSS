extends GdUnitTestSuite
## Endless traffic (D158): a schedule from the seed and the clock, the same on every game; cars in a
## lane never meet; up cars go up the road and oncoming ones down it; near a player they become
## physics cars and go back; one knocked out of its slot leaves it empty.


func before() -> void:
	Settings.use_folder("user://tests/endless_traffic")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(density := "normal", lanes := 2, side := "right") -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(31337, 2)
	s.event.endless_traffic = density
	s.event.lanes = lanes
	s.event.drive_side = side
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


## A schedule on its own (no session): the slots and their draws.
func _bare(density: String) -> EndlessTraffic:
	var t: EndlessTraffic = auto_free(EndlessTraffic.new())
	t.seed = 4242
	t.density = density
	for type: Dictionary in TrafficTypes.list():
		if int(type.weight) > 0:
			t._types.append(type)
			t._weights += int(type.weight)
	return t


func test_heavy_traffic_is_a_car_every_8_seconds_a_lane() -> void:
	for pair: Array in [["light", 48.0], ["normal", 20.0], ["heavy", 8.0]]:
		var t := _bare(pair[0])
		var n := 2000
		var span := float(t.slot(EndlessTraffic.UP, n).tau) - float(t.slot(EndlessTraffic.UP, 0).tau)
		assert_float(span / n).is_equal_approx(pair[1], pair[1] * 0.05)
	assert_bool("heavy" in RaceEvent.CHOICES.endless_traffic).is_true()
	assert_bool(EndlessMenu.TRAFFIC.any(func(c: Array) -> bool: return c[0] == "heavy")).is_true()


func test_the_nearest_cars_turn_physical_first() -> void:
	var s := _session("heavy")
	await _wait_for_car(s)
	var t: EndlessTraffic = s.endless_traffic
	var p := s.players[0]
	var near: Array = t.near_scheduled(PackedVector3Array([p.vehicle.global_position]))
	# From far along the road: everything within reach, in order.
	var far: Array = t.near_scheduled(PackedVector3Array([s.endless.lane_transform(p.distance + 200.0).origin, p.vehicle.global_position]))
	for list: Array in [near, far]:
		for i in range(1, list.size()):
			assert_float(float(list[i][0])).is_greater_equal(float(list[i - 1][0]))
		for n: Array in list:
			assert_float(float(n[0])).is_less(EndlessTraffic.PROMOTE_M)
	assert_int(far.size()).is_greater_equal(near.size())
	s.queue_free()
	await get_tree().process_frame


## Two lanes each way's slots are drawn as they always were (D158): the same tau, presence, type and
## colour from the same three draws.
func test_two_lane_slots_are_as_they_always_were() -> void:
	var t := _bare("normal")
	for lane in [EndlessTraffic.UP, EndlessTraffic.DOWN]:
		for j in range(-20, 300):
			var rng := RandomNumberGenerator.new()
			rng.seed = (t.seed * 1000003 + lane * 7919 + j) & 0x7FFFFFFFFFFFFFFF
			var tau := t.headway() * (float(j) + EndlessTraffic.SPREAD * rng.randf())
			var present := rng.randf() >= EndlessTraffic.EMPTY_SHARE
			var pick := rng.randi_range(0, t._weights - 1)
			var type := 0
			for i in t._types.size():
				pick -= int(t._types[i].weight)
				if pick < 0:
					type = i
					break
			var colors := TrafficTypes.colors(TrafficTypes.index_of(String(t._types[type].id)))
			var sl := t.slot(lane, j)
			assert_float(float(sl.tau)).is_equal(tau)
			assert_bool(sl.present).is_equal(present)
			assert_int(int(sl.type)).is_equal(type)
			assert_bool(sl.color == colors[rng.randi_range(0, colors.size() - 1)]).is_true()


func test_slots_and_ids_round_trip() -> void:
	var ids := {}
	for lane in 5: # four lanes and a trap's parked patrol
		for j: int in [-70000, -9, -1, 0, 1, 2, 7, 12345]:
			var key := Vector2i(lane, j)
			var slot := EndlessTraffic.slot_of(key)
			assert_bool(EndlessTraffic.key_of(slot) == key).is_true()
			var id := EndlessTraffic.car_id_of(slot)
			assert_int(id).is_between(NetProtocol.FIRST_TRAFFIC_ID, NetProtocol.FIRST_TRAFFIC_ID + EndlessTraffic.TRAFFIC_IDS - 1)
			if absi(j) < 1000:
				assert_bool(ids.has(id)).is_false()
				ids[id] = true


## Four lanes (D190): every lane has its cars, the same on every game; a lane's cars never meet;
## the passing lanes run faster and have no trucks or buses.
func test_four_lanes_run_their_own_schedules() -> void:
	var s := _session("heavy", 4, "left")
	await _wait_for_car(s)
	var t: EndlessTraffic = s.endless_traffic
	var other := EndlessTraffic.new()
	other.session = s
	other.world = s.endless_world
	other.lanes = t.lanes
	other.seed = t.seed
	other.density = t.density
	other.clock = t.now
	other._types = t._types
	other._weights = t._weights
	var a := t.scheduled()
	var b := other.scheduled()
	var by_key := {}
	for c: Dictionary in b:
		by_key[c.key] = c
	for c: Dictionary in a:
		assert_bool(by_key.has(c.key)).is_true()
		assert_float(float(c.s)).is_equal_approx(float(by_key[c.key].s), 0.001)
	var big := [TrafficTypes.index_of("truck"), TrafficTypes.index_of("bus")]
	for lane in 4:
		var mine: Array = b.filter(func(c: Dictionary) -> bool: return c.lane == lane)
		assert_int(mine.size()).override_failure_message("lane %d is empty" % lane).is_greater(2)
		var spots: Array = mine.map(func(c: Dictionary) -> float: return float(c.s))
		spots.sort()
		for i in range(1, spots.size()):
			assert_float(spots[i] - spots[i - 1]).is_greater(25.0)
		if EndlessLanes.pos_of(lane) == 0:
			for c: Dictionary in mine:
				assert_bool(TrafficTypes.index_of(String(t._types[int(c.type)].id)) in big).is_false()
	# The passing lane is quicker than the keep lane, everywhere.
	for d in [s.players[0].distance, s.players[0].distance + 500.0]:
		assert_float(t.lane_speed(0, d) / t.lane_speed(2, d)).is_equal_approx(EndlessLanes.PASS_FACTOR / EndlessLanes.KEEP_FACTOR, 0.001)
	# Driven on the left: the players' way keeps left of the centre line.
	var up_keep := t.pose(EndlessLanes.id(1, EndlessTraffic.UP), s.players[0].distance)
	assert_float(float(s.track.project(up_keep.origin).lateral)).is_greater(0.0)
	other.free()
	s.queue_free()
	await get_tree().process_frame
