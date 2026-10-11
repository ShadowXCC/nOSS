extends GdUnitTestSuite
## Track events online (D85): events from servers are checked, the race state survives the wire,
## a client follows the server's grid and results, and the results menu fits each role.


func before() -> void:
	Settings.use_folder("user://tests/net_race")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func test_events_from_servers_are_checked() -> void:
	var e := RaceEvent.from_dict({ "kind": "race", "start": "sideways", "grid": "x", "track_limits": "none", "ai_cars": "?",
		"practice_min": 9999, "race_min": -5, "race_laps": 500 })
	assert_str(e.kind).is_equal("race")
	assert_str(e.start).is_equal("standing")
	assert_str(e.grid).is_equal("qualifying")
	assert_str(e.track_limits).is_equal("lenient")
	assert_str(e.ai_cars).is_equal("garage")
	assert_int(e.practice_min).is_equal(120)
	assert_int(e.race_min).is_equal(0)
	assert_int(e.race_laps).is_equal(99)
	assert_str(RaceEvent.from_dict({ "kind": "drift" }).kind).is_equal("free")


## A race session with AI cars that have network ids (no network needed).
func _session() -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	var e := RaceEvent.new()
	e.kind = "race"
	e.ai_count = 3
	e.ai_cars = "builtin"
	s.event = e
	add_child(s)
	return s


func test_race_state_round_trip() -> void:
	var s := _session()
	for i in 600:
		await get_tree().process_frame
		if s.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			break
	var id := 10
	for r in s.racers:
		r.net_id = id
		id += 1
	s.net = NetSession.new()
	var nr := NetRace.new()
	nr.session = s
	nr.race = s.race
	nr.net = s.net
	for r in s.racers:
		s.net.racers[r.net_id] = r
	var a: Racer = s.racers[1]
	a.penalty_s = 5.0
	a.warnings = 1
	a.flag = "blue"
	a.held = true
	a.timer.best_lap = 71.25
	var bytes := nr.pack_state()
	assert_int(bytes.size()).is_equal(NetRace.HEADER + s.racers.size() * NetRace.CAR_SIZE)
	# Changed here, then the state comes back: it's as it was.
	a.penalty_s = 0.0
	a.flag = ""
	a.held = false
	a.timer.best_lap = -1.0
	s.race.mirror = true
	nr._on_raw(bytes)
	assert_float(a.penalty_s).is_equal(5.0)
	assert_int(a.warnings).is_equal(1)
	assert_str(a.flag).is_equal("blue")
	assert_bool(a.held).is_true()
	assert_float(a.timer.best_lap).is_equal_approx(71.25, 0.001)
	assert_int(s.race.position_of(a)).is_greater(0)
	# Junk is ignored.
	nr._on_raw(bytes.slice(0, 20))
	s.net.free()
	nr.free()
	s.queue_free()
	await get_tree().process_frame


func test_a_client_follows_the_servers_grid_and_results() -> void:
	var s := _session()
	for i in 600:
		await get_tree().process_frame
		if s.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			break
	var ids := []
	for i in s.racers.size():
		s.racers[i].net_id = 50 + i
		ids.append(50 + i)
	ids.reverse()
	s.race.mirror = true
	s.race.begin_mirror("race", 0, ids)
	await _frames(2)
	# The last car is on pole now, and everyone waits for the lights.
	var pole: Racer = s.racers[-1]
	var pole_spot := s.grid_transform(0, RaceControl.GRID_FRONT_M, RaceControl.GRID_ROW_M).origin
	assert_float(pole.vehicle.ground_reference().origin.distance_to(pole_spot)).is_less(1.0)
	assert_bool(s.racers.all(func(r: Racer) -> bool: return r.held)).is_true()
	assert_array(s.race.grid_ids).is_equal(ids)
	# The lights go out at the server's time, here.
	s.race.clock_source = func() -> float: return 100.0
	s.race.phase = RaceControl.Phase.COUNTDOWN
	s.race.go_at = 99.0
	await _frames(1)
	assert_int(s.race.phase).is_equal(RaceControl.Phase.RUNNING)
	assert_bool(s.racers.all(func(r: Racer) -> bool: return not r.held)).is_true()
	# Results from the server.
	var got := []
	s.race.session_ended.connect(func(kind: String, rows: Array) -> void: got.append([kind, rows]))
	var rows := []
	for i in s.racers.size():
		rows.append({ "racer": s.racers[i], "position": i + 1, "name": s.racers[i].display_name, "number": i + 5, "car": "Box",
			"time": 100.0 + i, "best": 49.0, "laps": 2, "penalty": 0.0, "dnf": false, "gap": "", "assists": "AI" })
	s.race.mirror_results("race", rows)
	assert_int(got.size()).is_equal(1)
	assert_int(s.race.phase).is_equal(RaceControl.Phase.DONE)
	s.close_results()
	s.queue_free()
	await get_tree().process_frame


func test_results_menu_by_role() -> void:
	var r: Racer = auto_free(Racer.new())
	r.display_name = "Ann"
	r.is_human = true
	var row := { "racer": r, "position": 1, "name": "Ann", "number": 1, "car": "Box", "time": 90.0, "best": 44.0,
		"laps": 2, "penalty": 0.0, "dnf": false, "gap": "", "assists": "ABS TCS" }
	for mode: String in ["local", "host", "client"]:
		var menu: ResultsMenu = auto_free(ResultsMenu.new())
		menu.mode = mode
		menu.results = [row]
		menu.has_next = true
		menu.next_name = "Race"
		add_child(menu)
		await _frames(1)
		var names := menu.find_children("*", "Button", true, false).map(func(b: Button) -> String: return String(b.accessibility_name))
		match mode:
			"local":
				assert_array(names).contains(["Continue: Race", "Restart", "Title"])
			"host":
				assert_array(names).contains(["Continue: Race", "Restart", "Lobby", "Leave"])
			"client":
				assert_array(names).contains(["Leave"])
				assert_bool(names.has("Restart")).is_false()
		assert_str(menu.row_text(0)).contains("assists: ABS TCS")
		menu.queue_free()
