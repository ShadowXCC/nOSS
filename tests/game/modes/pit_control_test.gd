extends GdUnitTestSuite
## Pit stops (D210): the request cycles and locks in the lane; the lane's limiter holds a car to
## its speed; a car stopped in its box is held for its service (fuel to the request, new tires),
## then told "Go"; every local player has their own panel and request; an AI car short of fuel
## takes the lane, stops in its box and comes out.

const OVAL := "res://content/tracks/piedmont_speedway"


func before() -> void:
	Settings.use_folder("user://tests/pit_control")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(ai_players := 0, ai := 0) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = OVAL
	s.platform_id = "official.track.stock_car"
	s.event = RaceEvent.free_drive()
	s.event.fuel_x = 1
	s.event.tyre_x = 1
	s.ai_players = ai_players
	s.ai_racers = ai
	add_child(s)
	return s


func _wait(s: TrackSession, count: int) -> void:
	for i in 900:
		var ready := s.racers.filter(func(r: Racer) -> bool: return r.vehicle != null)
		if ready.size() >= count and s.pits and s.wear:
			return
		await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_the_request_cycles_and_the_service_takes_its_time() -> void:
	var s := _session()
	await _wait(s, 1)
	var p := s.players[0]
	var pits := s.pits
	assert_str(PitControl.request_text(pits.stop_of(p).request)).is_equal("Full · 4 tires")
	pits.cycle(p, "fuel")
	pits.cycle(p, "tires")
	assert_str(PitControl.request_text(pits.stop_of(p).request)).is_equal("Finish · 2 tires")
	var w := s.wear.of(p)
	w.fuel_l = 20.0
	# Full: 48 L at 6 L/s is 8 s, under four tires' 11 s; plus the stop.
	var full := { "fuel": "full", "tires": 4, "repair": false }
	assert_float(pits.service_time(p, full)).is_equal_approx(PitControl.TIRES_4_S + PitControl.STOP_S, 0.001)
	var fuel_only := { "fuel": "full", "tires": 0, "repair": false }
	assert_float(pits.service_time(p, fuel_only)).is_equal_approx(48.0 / PitControl.FUEL_RATE + PitControl.STOP_S, 0.001)
	assert_float(pits.service_time(p, { "fuel": "none", "tires": 0, "repair": false })).is_equal(0.0)
	assert_float(pits.litres(p, { "fuel": "half", "tires": 0 })).is_equal(34.0)
	s.queue_free()
	await get_tree().process_frame


func test_a_car_stopped_in_its_box_is_serviced_then_sent() -> void:
	var s := _session()
	await _wait(s, 1)
	var p := s.players[0]
	var pits := s.pits
	var pit := s.track.pit
	var w := s.wear.of(p)
	w.fuel_l = 30.0
	w.scrub(PackedFloat32Array([30e6, 30e6, 30e6, 30e6]))
	pits.set_request(p, "fuel", "none")
	pits.set_request(p, "tires", 2)
	# In its box, at rest.
	p.vehicle.reset_to(pit.boxes[int(pits.stop_of(p).box)])
	await _ticks(10)
	assert_bool(p.in_pit).is_true()
	assert_str(String(pits.stop_of(p).state)).is_equal("service")
	assert_bool(p.pit_hold).is_true()
	# Locked in the lane: the request can't change now.
	pits.cycle(p, "tires")
	assert_int(int(pits.stop_of(p).request.tires)).is_equal(2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(pits.panel_text(p)).starts_with("Service")
	assert_str((p.hud.get_node("PitPanel") as PitPanel).text()).starts_with("Service")
	await _ticks(roundi((PitControl.TIRES_2_S + PitControl.STOP_S) * Engine.physics_ticks_per_second) + 30)
	assert_str(String(pits.stop_of(p).state)).is_equal("leaving")
	assert_bool(p.pit_hold).is_false()
	assert_str(pits.panel_text(p)).is_equal("Go")
	assert_int(int(pits.stop_of(p).stops)).is_equal(1)
	assert_float(w.fuel_l).is_equal_approx(30.0, 0.5) # no fuel asked for
	assert_float(w.tread()).is_equal_approx(0.5, 0.01) # two of four tires new
	s.queue_free()
	await get_tree().process_frame


func test_the_limiter_holds_the_lanes_speed() -> void:
	var s := _session()
	await _wait(s, 1)
	var p := s.players[0]
	var pit := s.track.pit
	# Rolling in at twice the limit, past the limit line.
	var at := pit.track.transform_at((pit.limit_in_m + pit.limit_out_m) / 2.0 - 60.0)
	p.vehicle.reset_to(at, at.basis.z * pit.speed * 2.0)
	await _ticks(5)
	assert_float(p.pit_limit).is_equal_approx(pit.speed, 0.001)
	await _ticks(360)
	assert_float(p.vehicle.speed()).is_less_equal(pit.speed + 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(p.hud.limit()).is_equal_approx(pit.speed, 0.001) # the limit sign shows it
	s.queue_free()
	await get_tree().process_frame


func test_every_player_has_their_own_panel_and_request() -> void:
	var s := _session(1)
	await _wait(s, 2)
	await _ticks(4)
	await get_tree().process_frame
	var p1 := s.players[0]
	var p2 := s.players[1]
	assert_object(p1.hud.get_node_or_null("PitPanel")).is_not_null()
	assert_object(p2.hud.get_node_or_null("PitPanel")).is_not_null()
	s.pits.cycle(p1, "fuel")
	assert_str(String(s.pits.stop_of(p1).request.fuel)).is_equal("finish")
	assert_str(String(s.pits.stop_of(p2).request.fuel)).is_equal("full")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str((p1.hud.get_node("PitPanel") as PitPanel).text()).is_equal("Pit: Finish · 4 tires")
	assert_str((p2.hud.get_node("PitPanel") as PitPanel).text()).is_equal("Pit: Full · 4 tires")
	s.queue_free()
	await get_tree().process_frame


func test_an_ai_car_short_of_fuel_pits_and_comes_out() -> void:
	var s := _session(0, 1)
	await _wait(s, 2)
	var ai: Racer = s.racers.filter(func(r: Racer) -> bool: return r.driver is RacingAI)[0]
	var pit := s.track.pit
	var w := s.wear.of(ai)
	w.fuel_l = 3.0
	ai.pit_plan = true
	s.pits.stop_of(ai).request.fuel = "full"
	# Rolling up to the entry at a decent pace.
	var at := s.track.transform_at(pit.entry_m - 380.0, -4.0)
	ai.vehicle.reset_to(at, at.basis.z * 50.0)
	var served := false
	for i in 120 * 70:
		await get_tree().physics_frame
		if int(s.pits.stop_of(ai).stops) > 0 and not ai.in_pit:
			served = true
			break
	assert_bool(served).override_failure_message("state %s, in pit %s, at %.0f m" % [s.pits.stop_of(ai).state, ai.in_pit, ai.pit_distance]).is_true()
	assert_float(w.fuel_l).is_greater(60.0)
	assert_bool(ai.pit_plan).is_false()
	s.queue_free()
	await get_tree().process_frame
