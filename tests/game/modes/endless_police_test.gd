extends GdUnitTestSuite
## The police on the endless road (D194): a camera's snap gives heat and a unit comes up behind in
## the players' way's lane, right or left; busted is pulled over, held, then on your way; players
## on one screen each have their own heat; a trap's parked patrol joins the chase where it was;
## patrols turn up in the traffic; traffic moves over for a siren; roadblocks close the right lanes
## for two lanes and four; spike strips only from heat 3.


func before() -> void:
	Settings.use_folder("user://tests/endless_police")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _session(side := "right", lanes := 2, traffic := "off", traps := false, players := 1) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(4242, 1)
	s.event.endless_traffic = traffic
	s.event.drive_side = side
	s.event.lanes = lanes
	s.event.speed_traps = traps
	s.event.police = true
	s.autodrive = true
	s.ai_players = players - 1
	add_child(s)
	for i in 900:
		var ready := s.players.size() >= players and s.police != null and s.police._placed
		for p in s.players:
			ready = ready and p.vehicle != null
		if ready:
			break
		await get_tree().physics_frame
	return s


func test_a_camera_snap_brings_a_unit_up_the_players_lane() -> void:
	for side: String in ["right", "left"]:
		var s := await _session(side)
		var pc := s.police
		assert_object(pc).is_not_null()
		assert_bool(pc.road is EndlessPoliceRoad).is_true()
		var p := s.players[0]
		var limit := pc.road.limit_mps(p)
		# Under the limit: nothing. Well over: heat, and a unit.
		pc.camera_snap(p, { "kind": "camera" }, limit + 1.0)
		assert_int(pc.heat_of(p).points).is_equal(0)
		pc.camera_snap(p, { "kind": "camera" }, limit + 30.0 / 3.6)
		assert_int(pc.heat_of(p).points).is_equal(Heat.POINTS.camera)
		await _ticks(4)
		var chasing := pc.units.filter(func(u: PoliceRacer) -> bool: return u.ai.target == p)
		assert_int(chasing.size()).is_equal(1)
		var u: PoliceRacer = chasing[0]
		assert_bool(u.ai is EndlessPoliceAI).is_true()
		var proj := s.track.project(u.vehicle.global_position)
		assert_float(p.distance - float(proj.distance)).is_between(PoliceControl.SEND_BEHIND_M - 30.0, PoliceControl.SEND_BEHIND_M + 30.0)
		assert_float(signf(float(proj.lateral))).is_equal(-1.0 if side == "right" else 1.0)
		assert_float(u.vehicle.global_basis.z.dot(s.track.tangents[int(proj.index)])).is_greater(0.9)
		# It closes in, siren on.
		var gap := u.vehicle.global_position.distance_to(p.vehicle.global_position)
		await _ticks(120 * 6)
		assert_bool(u.vehicle.siren).is_true()
		assert_float(u.vehicle.global_position.distance_to(p.vehicle.global_position)).is_less(gap - 50.0)
		s.queue_free()
		await get_tree().process_frame


func test_busted_is_pulled_over_then_on_your_way() -> void:
	var s := await _session()
	var pc := s.police
	var p := s.players[0]
	p.driver.set_physics_process(false)
	var h := pc.heat_of(p)
	h.points = 6
	var at := s.endless.lane_transform(p.distance)
	p.vehicle.reset_to(at)
	p.vehicle.throttle = 0.0
	p.vehicle.handbrake = 1.0 # stopped (on a hill, maybe)
	var u := pc.units[pc.units.size() - 1]
	u.deploy(Transform3D(at.basis, at.origin - at.basis.z * 4.6), Vector3.ZERO)
	u.ai.mode = PoliceAI.Mode.PARKED
	await _ticks(int(120 * (Heat.BUST_S + 0.5)))
	assert_int(pc.busts).is_equal(1)
	assert_int(h.level()).is_equal(0)
	assert_bool(p.held).is_true()
	assert_int(int((pc.road as EndlessPoliceRoad).busts[p])).is_equal(1)
	assert_str(pc.road.bust_text(p)).is_equal("Busted (1). Pulled over")
	# On the shoulder.
	var lat := float(s.track.project(p.vehicle.global_position).lateral)
	assert_float(absf(lat)).is_greater(s.endless_lanes.lane_w(s.track, p.distance) * 0.75)
	await _ticks(int(120 * (EndlessPoliceRoad.PULLED_OVER_S + 0.5)))
	assert_bool(p.held).is_false()
	s.queue_free()
	await get_tree().process_frame


func test_each_player_on_a_screen_has_their_own_heat() -> void:
	var s := await _session("right", 2, "off", false, 2)
	var pc := s.police
	var a := s.players[0]
	var b := s.players[1]
	assert_bool(a in pc.players() and b in pc.players()).is_true()
	pc.heat_of(a).points = 15 # level 3
	await _ticks(6)
	assert_int(pc.heat_of(a).level()).is_equal(3)
	assert_int(pc.heat_of(b).level()).is_equal(0)
	assert_int(pc.units.filter(func(u: PoliceRacer) -> bool: return u.ai.target == a).size()).is_equal(3)
	assert_int(pc.units.filter(func(u: PoliceRacer) -> bool: return u.ai.target == b).size()).is_equal(0)
	assert_int(pc.units.size()).is_equal(EndlessPoliceRoad.CHASE_UNITS)
	assert_object(a.hud.get_node_or_null(^"HeatPanel")).is_not_null()
	s.queue_free()
	await get_tree().process_frame


func test_a_traps_parked_patrol_joins_the_chase_where_it_was() -> void:
	var s := await _session("right", 2, "off", true)
	var pc := s.police
	var w := s.endless_world
	var trap := {}
	for k in range(EndlessTraps.FIRST_CHUNK, 3000):
		trap = EndlessTraps.plan(4242, k, w.gen.chunk(k), s.endless_lanes)
		if not trap.is_empty() and trap.kind == "patrol":
			break
	assert_bool(trap.is_empty()).is_false()
	var p := s.players[0]
	p.driver.set_physics_process(false)
	s.endless.move_to(float(trap.at_m) - 80.0)
	await _ticks(120)
	var spot: Transform3D = s.endless_traffic.pose(EndlessTraffic.PARKED, float(trap.at_m))
	assert_int(pc.road.patrols(p.vehicle.global_position, 250.0).size()).is_greater(0)
	pc.heat_of(p).points = 1
	await _ticks(4)
	var chasing := pc.units.filter(func(u: PoliceRacer) -> bool: return u.ai.target == p)
	assert_int(chasing.size()).is_equal(1)
	assert_int(pc.patrols_converted).is_equal(1)
	assert_float(chasing[0].vehicle.global_position.distance_to(spot.origin)).is_less(3.0)
	var key := Vector2i(EndlessTraffic.PARKED, int(trap.id))
	assert_bool(s.endless_traffic.gone.has(key)).is_true()
	assert_bool(s.endless_traffic.cars.has(key)).is_false()
	s.queue_free()
	await get_tree().process_frame


## Patrols in the traffic: about PATROL_SHARE of the car types, nothing else in the schedule
## changed; none without police.
func test_patrols_come_among_the_cars() -> void:
	var plain := EndlessTraffic.new()
	var with := EndlessTraffic.new()
	for t in [plain, with]:
		t.seed = 4242
		t.density = "heavy"
		for type: Dictionary in TrafficTypes.list():
			if int(type.weight) > 0:
				t._types.append(type)
				t._weights += int(type.weight)
		for type: Dictionary in TrafficTypes.list():
			if type.get("patrol", false):
				t._patrol_type = t._types.size()
				t._types.append(type)
		for i in t._types.size():
			if String(t._types[i].platform) == "official.traffic.car":
				t._car_types[i] = true
	with.patrols = true
	var patrols := 0
	var cars := 0
	for j in range(0, 6000):
		var a := plain.slot(EndlessTraffic.UP, j)
		var b := with.slot(EndlessTraffic.UP, j)
		assert_float(float(a.tau)).is_equal(float(b.tau))
		assert_bool(a.present == b.present).is_true()
		if plain._car_types.has(int(a.type)):
			cars += 1
		if b.get("patrol", false):
			patrols += 1
			assert_int(int(b.type)).is_equal(with._patrol_type)
			assert_bool(plain._car_types.has(int(a.type))).is_true()
		else:
			assert_int(int(b.type)).is_equal(int(a.type))
		assert_bool(a.get("patrol", false)).is_false()
	assert_float(float(patrols) / cars).is_equal_approx(EndlessTraffic.PATROL_SHARE, 0.008)
	plain.free()
	with.free()


func test_traffic_moves_over_for_a_siren() -> void:
	var s := await _session("right", 2, "heavy")
	var t: EndlessTraffic = s.endless_traffic
	var p := s.players[0]
	# A physics car in the players' way's lane.
	var car: EndlessTrafficCar = null
	for i in 120:
		for key: Vector2i in t.cars:
			if key.x == EndlessTraffic.UP and not (t.cars[key] as EndlessTrafficCar).remote:
				car = t.cars[key]
		if car:
			break
		await _ticks(30)
	assert_object(car).is_not_null()
	var u := s.police.units[0]
	var behind := s.track.transform_at(car.s - 40.0, s.endless_lanes.lateral(s.track, EndlessLanes.UP, car.s - 40.0))
	u.deploy(behind, behind.basis.z * car.vehicle.speed())
	u.ai.target = p
	u.ai.mode = PoliceAI.Mode.PURSUE
	var lane_lat := s.endless_lanes.lateral(s.track, EndlessLanes.UP, car.s)
	await _ticks(120 * 3)
	assert_bool(t.siren_behind(car.vehicle)).is_true()
	var lat := float(s.track.project(car.vehicle.global_position).lateral)
	assert_float(absf(lat)).is_greater(absf(lane_lat) + 0.6) # towards the shoulder
	assert_float(car.vehicle.speed()).is_less(t.lane_speed(EndlessTraffic.UP, car.s) * 0.8)
	s.queue_free()
	await get_tree().process_frame


func test_roadblocks_close_the_lanes_of_the_players_way() -> void:
	for lanes in [2, 4]:
		var s := await _session("right", lanes, "heavy")
		var pc := s.police
		var p := s.players[0]
		pc.heat_of(p).points = Heat.LEVELS[3] # level 4
		await _ticks(6)
		assert_bool(pc._blocks.has(p)).is_true()
		var b: Dictionary = pc._blocks[p]
		var t: EndlessTraffic = s.endless_traffic
		var c: Dictionary = t.closures[int(b.closures[0])]
		assert_array(c.lanes).is_equal([EndlessLanes.id(0, EndlessLanes.UP)] if lanes == 2 else [EndlessLanes.id(0, EndlessLanes.UP), EndlessLanes.id(1, EndlessLanes.UP)])
		assert_int((b.units as Array).size()).is_equal(1 if lanes == 2 else 2)
		# Nothing scheduled drives into it.
		for car: Dictionary in t.scheduled():
			if car.lane in c.lanes:
				assert_bool(float(car.s) > float(c.from) - EndlessTraffic.CLOSED_BEFORE_M and float(car.s) < float(c.to)).is_false()
		s.queue_free()
		await get_tree().process_frame


func test_spike_strips_only_from_heat_three() -> void:
	var s := await _session()
	var pc := s.police
	var p := s.players[0]
	pc.set_physics_process(false)
	p.driver.set_physics_process(false)
	var h := pc.heat_of(p)
	h.points = Heat.LEVELS[1]
	for i in 10:
		pc._clock += 10.0
		pc._spikes()
	assert_int(pc.spikes_laid).is_equal(0)
	h.points = Heat.LEVELS[2]
	pc._spikes()
	var laid := false
	for i in 40:
		pc._clock += PoliceTuning.at(3).spikes_s
		pc._spikes()
		if pc.spikes_laid > 0:
			laid = true
			break
		# Along the road a bit, to find a straight.
		s.endless.move_to(p.distance + 300.0)
		await _ticks(2)
	assert_bool(laid).is_true()
	var strip: SpikeStrip = pc.strips[0]
	var span := Vector2(strip.lat_from, strip.lat_to)
	assert_float(span.x).is_less(0.0) # driving on the right: across the right of the road
	assert_float(span.y).is_equal(0.0)
	s.queue_free()
	await get_tree().process_frame
