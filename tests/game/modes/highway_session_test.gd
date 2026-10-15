extends GdUnitTestSuite
## Highway sessions (docs/GAMEMODES.md §3, D110, D113): players start on the shoulder facing the
## traffic's way; lane cars near them become physics cars where the lane sim had them and go back
## when nobody is near; wrecks stay until towed; the cap holds, with stand-in boxes beyond it; a
## car going against the traffic is told so; a portal leads out of the next entry; turning round.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"


func before() -> void:
	Settings.use_folder("user://tests/highway_session")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(direction := 1, traffic := 150) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.highway.street"
	s.event = RaceEvent.highway("cruise", false, traffic)
	s.event.direction = direction
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


func test_players_start_on_the_shoulder_facing_the_traffic() -> void:
	for dir in [1, -1]:
		var s := _session(dir)
		await _wait_for_car(s)
		var p := s.players[0]
		assert_object(s.highway).is_not_null()
		assert_object(s.traffic).is_not_null()
		assert_bool(p.limits).is_false()
		assert_int(p.direction).is_equal(dir)
		var t := s.track
		var proj := t.project(p.vehicle.global_position)
		# On the outer shoulder of its carriageway, facing along it.
		var lat := float(proj.lateral)
		assert_float(-dir * lat).is_between(s.track.highway.inner + 3 * 3.6, s.track.highway.half)
		assert_float(p.vehicle.global_basis.z.dot(t.tangents[int(proj.index)] * dir)).is_greater(0.98)
		s.queue_free()
		await get_tree().process_frame


func test_traffic_becomes_physical_near_a_player_and_goes_back() -> void:
	var s := _session()
	await _wait_for_car(s)
	await _ticks(360)
	var tm := s.traffic
	assert_int(tm.cars.size()).is_greater(0)
	# Each physics car is where the lane sim has its shadow (a car length or so: the shadow drives
	# on by itself).
	for car: int in tm.cars:
		var tc: TrafficCar = tm.cars[car]
		var info := tm.sim.car(car)
		assert_int(int(info.flags) & TrafficManager.SHADOW).is_not_equal(0)
		assert_float(absf(float(info.s) - tc.s)).override_failure_message("car %d" % car).is_less(TrafficCar.RESHADOW_M + 2.0)
		assert_bool(tm.promoters().size() > 0).is_true()
	# The player goes to the far side of the ring: every physics car near it now goes back.
	var p := s.players[0]
	var far := fposmod(p.distance + s.track.length / 2.0, s.track.length)
	p.vehicle.reset_to(s.highway.shoulder_spot(1, far))
	var before := tm.demotions
	await _ticks(int((TrafficManager.FORCE_BACK_S + 1.0) * 120.0))
	assert_int(tm.demotions).is_greater(before)
	for car: int in tm.cars:
		var tc: TrafficCar = tm.cars[car]
		assert_float(tc.vehicle.global_position.distance_to(p.vehicle.global_position)).is_less(TrafficManager.R_OUT + 20.0)
	s.queue_free()
	await get_tree().process_frame


func test_a_wreck_stays_until_towed() -> void:
	var s := _session()
	await _wait_for_car(s)
	await _ticks(360)
	var tm := s.traffic
	assert_int(tm.cars.size()).is_greater(0)
	# The physics car nearest the player.
	var p := s.players[0]
	var car := -1
	for c: int in tm.cars:
		if car < 0 or (tm.cars[c] as TrafficCar).vehicle.global_position.distance_to(p.vehicle.global_position) \
				< (tm.cars[car] as TrafficCar).vehicle.global_position.distance_to(p.vehicle.global_position):
			car = c
	var tc: TrafficCar = tm.cars[car]
	assert_float(tc.vehicle.global_position.distance_to(p.vehicle.global_position)).is_less(TrafficManager.R_IN)
	p.driver.set_physics_process(false) # the player stays put
	tc.wreck()
	await _ticks(40)
	assert_bool(tc.wrecked).is_true()
	assert_int(int(tm.sim.car(car).flags) & 8).is_not_equal(0) # WRECK: its shadow stands still
	# Nobody near: towed (the car goes into the city and comes back later).
	p.vehicle.reset_to(s.highway.shoulder_spot(1, fposmod(p.distance + s.track.length / 2.0, s.track.length)))
	await _ticks(60)
	assert_bool(tm.cars.has(car)).is_false()
	assert_int(int(tm.sim.car(car).flags) & TrafficManager.AWAY).is_not_equal(0)
	assert_int(tm.tows).is_greater(0)
	s.queue_free()
	await get_tree().process_frame


func test_the_cap_holds_and_boxes_stand_in() -> void:
	var s := _session()
	await _wait_for_car(s)
	var tm := s.traffic
	tm.cap = 0
	await _ticks(60)
	assert_int(tm.cars.size()).is_equal(0)
	# A lane car right beside the player: a solid box where the lane sim has it.
	var p := s.players[0]
	var at := tm.sim.locate(p.vehicle.global_position)
	var lane := s.track.highway.main_lane(1, 0)
	tm.sim.place(0, lane, float(tm.sim.locate(p.vehicle.global_position + p.vehicle.global_basis.x * 3.0).get("s", at.get("s", 0.0))) + 15.0, 0.0)
	await _ticks(2)
	var boxes := tm.get_children().filter(func(n: Node) -> bool: return n is AnimatableBody3D and n.process_mode != Node.PROCESS_MODE_DISABLED)
	assert_int(boxes.size()).is_greater(0)
	assert_int(int((boxes[0] as Node).get_meta(&"noss_traffic"))).is_greater_equal(0)
	s.queue_free()
	await get_tree().process_frame


func test_wrong_way_only_against_the_traffic() -> void:
	var s := _session(1, 0)
	await _wait_for_car(s)
	var p := s.players[0]
	p.driver.set_physics_process(false)
	await _ticks(10)
	assert_bool(p.wrong_way).is_false()
	# Turned round on its own carriageway and driving: wrong way.
	var t := s.highway.shoulder_spot(1, 500.0)
	var back := Transform3D(Basis(-t.basis.x, t.basis.y, -t.basis.z), t.origin)
	p.vehicle.reset_to(back, -t.basis.z * 15.0)
	await _ticks(240)
	assert_bool(p.wrong_way).is_true()
	# The same on the other carriageway is the right way.
	p.vehicle.reset_to(s.highway.shoulder_spot(-1, 500.0), s.highway.shoulder_spot(-1, 500.0).basis.z * 15.0)
	await _ticks(240)
	assert_bool(p.wrong_way).is_false()
	assert_int(p.direction).is_equal(-1)
	s.queue_free()
	await get_tree().process_frame


func test_a_portal_leads_out_of_the_next_entry() -> void:
	var s := _session(1, 0)
	await _wait_for_car(s)
	var p := s.players[0]
	p.driver.set_physics_process(false)
	var exit := s.track.highway.ramp("harbour_off")
	var k := exit.track.samples.size() - 12
	var t := exit.track
	p.vehicle.reset_to(Transform3D(Basis(t.lefts[k], t.ups[k], t.tangents[k]), t.samples[k]), t.tangents[k] * 15.0)
	await _ticks(180)
	var entry := s.track.highway.ramp("harbour_on")
	var at := entry.track.project(p.vehicle.global_position)
	assert_float(float(at.distance)).is_less(entry.track.length)
	assert_float(Vector2(at.point.x, at.point.z).distance_to(Vector2(p.vehicle.global_position.x, p.vehicle.global_position.z))).is_less(4.0)
	s.queue_free()
	await get_tree().process_frame


func test_turning_round() -> void:
	var s := _session(1, 0)
	await _wait_for_car(s)
	var p := s.players[0]
	s.highway.change_direction(p)
	await _ticks(5)
	assert_int(p.direction).is_equal(-1)
	var proj := s.track.project(p.vehicle.global_position)
	assert_float(float(proj.lateral)).is_greater(0.0)
	s.queue_free()
	await get_tree().process_frame


func test_the_lane_driver_holds_its_lane_and_stops_for_a_wreck() -> void:
	var s := _session(1, 40)
	await _wait_for_car(s)
	var p := s.players[0]
	await _ticks(20 * 120)
	# On its lane's line, and moving.
	var d := p.driver as HighwayDriver
	assert_int(d.lane).is_greater_equal(0)
	var off := s.traffic.sim.locate(p.vehicle.global_position + Vector3.UP * 0.5)
	assert_float(absf(float(off.get("lateral", 9.0)))).is_less(0.6)
	assert_float(p.speed).is_greater(10.0)
	# A wreck stands in its lane 150 m on: it stops behind without touching it.
	var tm := s.traffic
	var s_ahead := float(off.s) + 150.0
	tm.sim.place(39, d.lane, s_ahead, 0.0)
	tm._event(TrafficManager.WRECK, 39, d.lane, s_ahead, 0.0)
	var contact := false
	for i in 15 * 120:
		await get_tree().physics_frame
		contact = contact or p.vehicle.car_impulse > 50.0 or p.vehicle.traffic_impulse > 50.0
	assert_bool(contact).is_false()
	assert_float(absf(p.speed)).is_less(1.0)
	s.queue_free()
	await get_tree().process_frame


func test_starts_never_share_a_spot_or_a_ramp_mouth() -> void:
	var pkg := TrackLoader.load_package("res://content/tracks/lumen_ring", {}, { "terrain": false })
	var hc := HighwayControl.new()
	hc.layout = pkg.track.highway
	for dir: int in [1, -1]:
		var spots := []
		for i in 16:
			var at := hc.spawn_for(i, dir).origin
			for other: Vector3 in spots:
				# Along the road START_GAP_M apart (a little less on the inside of a corner).
				assert_float(at.distance_to(other)).override_failure_message("dir %d, %d" % [dir, i]).is_greater(HighwayControl.START_GAP_M * 0.9)
			assert_bool(hc._in_mouth(float(pkg.track.project(at).distance), dir)).is_false()
			spots.append(at)
	hc.free()


func test_a_run_rolls_up_starts_at_the_line_and_finishes() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.highway.street"
	s.event = RaceEvent.highway("run", false, 30)
	s.event.run = "south_sprint"
	s.traffic_seed = 3
	s.autodrive = true
	add_child(s)
	await _wait_for_car(s)
	await _ticks(10)
	var run := s.run
	assert_object(run).is_not_null()
	var p := s.players[0]
	assert_bool(run.state.has(p)).is_true()
	# Lined up before the start, rolling no faster than the pace until the line.
	assert_float(run.progress(p)).is_less(-RunControl.ROLL_M + 30.0)
	var fastest := 0.0
	while float(run.state[p].started) < 0.0 and run.clock < 60.0:
		await get_tree().physics_frame
		fastest = maxf(fastest, p.vehicle.speed())
	assert_float(float(run.state[p].started)).is_greater(0.0)
	assert_float(fastest).is_less(RunControl.PACE_KMH / 3.6 + 3.0)
	var rows := []
	run.done.connect(func(r: Array) -> void: rows.append_array(r))
	while run.phase != RunControl.Phase.DONE and run.clock < 240.0:
		await get_tree().physics_frame
	assert_int(rows.size()).is_equal(1)
	assert_bool(bool(rows[0].dnf)).override_failure_message(str(run.state[p])).is_false()
	assert_float(float(rows[0].time)).is_between(20.0, 120.0)
	var board := Leaderboard.entries(s.track.record_key(), "official.highway.street|run:south_sprint")
	assert_int(board.size()).is_greater(0)
	s.queue_free()
	await get_tree().process_frame
