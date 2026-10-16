extends GdUnitTestSuite
## Each kart its own class (D149): a player drives the class their card picked, AI karts pick their
## own (all the session's when asked, as the balance checks want), a cup keeps each AI kart's class,
## and the results say which class each drove. Outside karts, everyone has the session's class.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"

var s: TrackSession


func before() -> void:
	Settings.use_folder("user://tests/kart_classes")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
		await get_tree().process_frame
	Players.clear()


func _session(ai: int, mix := true, platform := "official.kart.medium") -> void:
	s = TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = platform
	s.event = RaceEvent.free_drive()
	s.ai_racers = ai
	s.ai_class_mix = mix
	add_child(s)
	for i in 900:
		if s.racers.size() == ai + 1 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			return
		await get_tree().physics_frame


func test_a_player_drives_the_class_they_picked() -> void:
	Players.clear()
	Players.primary_slot().profile.set_value("kart_class", "official.kart.heavy")
	await _session(0)
	var p: Racer = s.racers[0]
	assert_str(String(p.platform.platform.id)).is_equal("official.kart.heavy")
	assert_float(p.vehicle.mass).is_equal_approx(260.0, 0.5)
	assert_str(s.race._car_text(p)).ends_with("· Heavy")


func test_ai_karts_pick_their_own_or_all_take_the_sessions() -> void:
	Players.clear()
	Players.primary_slot().profile.set_value("kart_class", "")
	Game.dev["seed"] = "4"
	await _session(9)
	var ids := {}
	for r in s.racers.slice(1):
		ids[String(r.platform.platform.id)] = true
	assert_int(ids.size()).is_greater(1) # nine karts, three classes
	s.queue_free()
	await get_tree().process_frame
	Players.clear()
	await _session(5, false, "official.kart.light")
	for r in s.racers.slice(1): # the AI karts (the player keeps their own pick)
		assert_str(String(r.platform.platform.id)).is_equal("official.kart.light")
	Game.dev.erase("seed")


func test_a_cup_keeps_each_ai_karts_class() -> void:
	Players.clear()
	var run := CupRun.start(CupRun.load_file("res://data/cups/spark_cup.cup.json"), "official.kart.medium", RaceEvent.new())
	run.roster = [{ "class": "official.kart.heavy" }, { "class": "official.kart.light" }]
	s = TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.free_drive()
	s.ai_racers = 2
	s.cup = run
	add_child(s)
	for i in 900:
		if s.racers.size() == 3 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			break
		await get_tree().physics_frame
	assert_str(String(s.racers[1].platform.platform.id)).is_equal("official.kart.heavy")
	assert_str(String(s.racers[2].platform.platform.id)).is_equal("official.kart.light")
	run.roster = []
	run.keep_roster(s)
	assert_str(String(run.roster[0]["class"])).is_equal("official.kart.heavy")


func test_outside_karts_everyone_has_the_sessions_class() -> void:
	Players.clear()
	Players.primary_slot().profile.set_value("kart_class", "official.kart.heavy")
	s = TrackSession.new()
	s.platform_id = "official.track.gt"
	s.event = RaceEvent.free_drive()
	s.ai_racers = 1
	add_child(s)
	for i in 900:
		if s.racers.size() == 2 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		assert_str(String(r.platform.platform.id)).is_equal("official.track.gt")
