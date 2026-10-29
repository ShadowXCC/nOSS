extends GdUnitTestSuite
## Endless sessions (docs/GAMEMODES.md §4, D157): players start in single file in the right-hand
## lane; the HUD shows speed until hidden (no laps ever); a reset puts the car back in its lane; the
## autodrive keeps its lane and gets going; road codes round-trip; and players on one PC drifting
## too far apart are brought together by the event's rule.


func before() -> void:
	Settings.use_folder("user://tests/endless_session")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(players := 1, spread := "bring", lanes := 2, side := "right") -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(4242, 1)
	s.event.spread = spread
	s.event.lanes = lanes
	s.event.drive_side = side
	s.event.endless_traffic = "off"
	s.autodrive = true
	s.ai_players = players - 1
	add_child(s)
	return s


func _wait_for_cars(s: TrackSession, n := 1) -> void:
	for i in 900:
		var ready := s.players.size() >= n
		for p in s.players:
			ready = ready and p.vehicle != null
		if ready:
			return
		await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_players_start_in_the_right_hand_lane() -> void:
	var s := _session(2)
	await _wait_for_cars(s, 2)
	assert_object(s.endless).is_not_null()
	assert_bool(s.track is RoadWindow).is_true()
	assert_object(s.origin).is_not_null()
	for i in s.players.size():
		var p := s.players[i]
		assert_bool(p.laps).is_false()
		assert_bool(p.limits).is_false()
		var proj := s.track.project(p.vehicle.global_position)
		var lane := s.track.half_width(float(proj.distance), 1.0) - RoadWindow.SHOULDER_M
		assert_float(float(proj.lateral)).is_equal_approx(-lane / 2.0, 0.5)
		assert_float(float(proj.distance)).is_equal_approx(EndlessControl.START_M - EndlessControl.SPACING_M * i, 1.5)
		assert_float(p.vehicle.global_basis.z.dot(s.track.tangents[int(proj.index)])).is_greater(0.98)
	s.queue_free()
	await get_tree().process_frame


## Two lanes or four, on the right or the left: players start in the lane traffic keeps to (the
## edge one), and the autodrive keeps to it (D190).
func test_players_start_and_drive_in_the_keep_lane_of_each_layout() -> void:
	for layout: Array in [[2, "right", -0.5], [2, "left", 0.5], [4, "right", -1.5], [4, "left", 1.5]]:
		var s := _session(1, "bring", layout[0], layout[1])
		await _wait_for_cars(s)
		var p := s.players[0]
		var proj := s.track.project(p.vehicle.global_position)
		var lane_w: float = (s.track.half_width(float(proj.distance), 1.0) - RoadWindow.SHOULDER_M) / (int(layout[0]) / 2)
		assert_float(float(proj.lateral)).override_failure_message("%s: starts at %.2f" % [layout, float(proj.lateral)]).is_equal_approx(float(layout[2]) * lane_w, 0.5)
		await _ticks(720) # 6 s
		assert_float(p.lateral).override_failure_message("%s: drives at %.2f" % [layout, p.lateral]).is_equal_approx(float(layout[2]) * lane_w, 1.2)
		s.queue_free()
		await get_tree().process_frame


func test_the_hud_shows_speed_until_hidden() -> void:
	var s := _session()
	await _wait_for_cars(s)
	var p := s.players[0]
	assert_bool(p.hud.shows("speed")).is_true()
	assert_bool(p.hud.shows("timing")).is_false() # no laps here
	var items: Array = s.endless.pause_items(p)
	var texts := items.map(func(i: Array) -> String: return String(i[0]))
	assert_bool(texts.any(func(t: String) -> bool: return t.begins_with("Road code: FOREST-"))).is_true()
	assert_bool(texts.has("Hide HUD")).is_true()
	(items[texts.find("Hide HUD")][1] as Callable).call()
	assert_bool(p.hud.shows("speed")).is_false()
	assert_bool(p.hud.shows("timing")).is_false()
	texts = s.endless.pause_items(p).map(func(i: Array) -> String: return String(i[0]))
	assert_bool(texts.has("Show HUD")).is_true()
	s.queue_free()
	await get_tree().process_frame


func test_autodrive_keeps_its_lane_and_a_reset_puts_it_back() -> void:
	var s := _session()
	await _wait_for_cars(s)
	var p := s.players[0]
	var from := p.distance
	await _ticks(1200) # 10 s
	assert_float(p.distance - from).is_greater(80.0)
	assert_float(p.speed).is_greater(10.0)
	var lane := s.track.half_width(p.distance, 1.0) - RoadWindow.SHOULDER_M
	assert_float(p.lateral).is_equal_approx(-lane / 2.0, 1.2)
	# Off into the trees, then a reset: back in the lane at its last good spot.
	p.last_valid = p.distance - 30.0
	p.vehicle.reset_to(Transform3D(Basis(), p.vehicle.global_position + p.vehicle.global_basis.x * 25.0))
	p.reset_car()
	await _ticks(2)
	var proj := s.track.project(p.vehicle.global_position)
	assert_float(float(proj.lateral)).is_equal_approx(-lane / 2.0, 0.6)
	assert_bool(p.ghosted).is_true()
	s.queue_free()
	await get_tree().process_frame


func test_road_codes() -> void:
	for seed_value in [0, 1, 7, 123456, 0x7FFFFFFF]:
		for biome in NossRoadGen.biome_ids().size():
			var code := EndlessCode.encode(seed_value, biome)
			assert_dict(EndlessCode.decode(code)).is_equal({ "seed": seed_value, "biome": biome })
			assert_dict(EndlessCode.decode(" " + code.to_lower() + " ")).is_equal({ "seed": seed_value, "biome": biome })
	assert_str(EndlessCode.encode(7, 1)).is_equal("FOREST-0000007")
	# Haunted (D221) is appended: the others keep their codes. Its roads change the protocol.
	assert_str(EndlessCode.encode(1, EndlessBiomes.index_of("haunted"))).is_equal("HAUNTED-0000001")
	assert_int(EndlessBiomes.index_of("haunted")).is_equal(7)
	assert_int(NetProtocol.VERSION).is_equal(16) # 16: garage traffic's sets (D232)
	assert_dict(EndlessCode.decode("FOREST-OOOOOO7")).is_equal({ "seed": 7, "biome": 1 }) # O for 0
	for bad in ["", "forest", "MOON-0000001", "FOREST-", "FOREST-UUUU", "FOREST-ZZZZZZZZ"]:
		assert_dict(EndlessCode.decode(bad)).is_empty()


func test_players_far_apart_come_together() -> void:
	for rule in ["bring", "hold"]:
		var s := _session(2, rule)
		await _wait_for_cars(s, 2)
		var lead := s.players[0]
		var last := s.players[1]
		# Put the leader 3.2 km on (the road there has to exist: let the window catch up).
		var to := EndlessControl.START_M + 3200.0
		for i in 60:
			if s.track.end_m() > to + 50.0:
				break
			await _ticks(5)
		lead.vehicle.reset_to(s.endless.lane_transform(to))
		lead.distance = to
		await _ticks(160)
		var apart := absf(lead.distance - last.distance)
		assert_float(apart).override_failure_message(rule).is_less(EndlessControl.SPREAD_WARN_M)
		if rule == "bring":
			assert_float(last.distance).is_greater(to - 300.0) # the one behind came up
		else:
			assert_float(lead.distance).is_less(to - 2000.0) # the leader went back
		s.queue_free()
		await get_tree().process_frame


## A Haunted start (D221) is night from the first frame, at noon: the sky follows the biome
## under P1 (EnvDirector.biomes_here).
func test_a_haunted_start_is_night_at_once() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(1, EndlessBiomes.index_of("haunted"))
	s.event.time = "noon"
	s.event.weather = "clear"
	s.event.endless_traffic = "off"
	s.autodrive = true
	add_child(s)
	assert_float(s.env.night).is_greater(0.8)
	assert_str(String((s.env.biomes[1] as Dictionary).get("id", ""))).is_equal("haunted")
	assert_float(float(s.env.snapshot.fog)).is_greater_equal(0.45)
	s.queue_free()
	await get_tree().process_frame
