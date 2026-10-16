extends GdUnitTestSuite
## Cups (D145): points 15, 12, 10... by place, ties to the most wins, then the better last race;
## the next grid is the standings reversed; the AI field keeps its cars, paint and skill from race
## to race; a cup saves, loads and is checked; a missing track is found.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"


func before() -> void:
	Settings.use_folder("user://tests/cup_run")
	CupRun.user_dir = "user://tests/cup_run/cups/"


func after() -> void:
	Players.clear()
	CupRun.user_dir = "user://cups/"
	Settings.use_folder("user://")


func _cup() -> Dictionary:
	return CupRun.load_file("res://data/cups/spark_cup.cup.json")


## A racer for the table: an AI by name.
func _ai(n: String) -> AiRacer:
	var a := AiRacer.new()
	a.display_name = n
	return a


func _rows(order: Array) -> Array:
	var rows := []
	for i in order.size():
		rows.append({ "racer": order[i], "position": i + 1, "dnf": false })
	return rows


func test_points_and_ties() -> void:
	var run := CupRun.start(_cup(), "official.kart.medium", RaceEvent.new())
	var a := _ai("Vega")
	var b := _ai("Rook")
	var c := _ai("Juno")
	run.add_results(_rows([a, b, c])) # 15 12 10
	run.add_results(_rows([b, a, c])) # 27 27 20: one win each, Rook won the last
	var table := run.standings()
	assert_array(table.map(func(t: Dictionary) -> String: return t.name)).is_equal(["Rook", "Vega", "Juno"])
	assert_int(int(table[0].points)).is_equal(27)
	assert_int(int(table[2].points)).is_equal(20)
	run.add_results(_rows([c, b, a])) # Rook 39, Vega 37, Juno 35
	assert_str(String(run.standings()[0].name)).is_equal("Rook")
	# The next grid: the standings reversed, the leader at the back.
	assert_array(run.grid_keys()).is_equal(["ai:Juno", "ai:Vega", "ai:Rook"])
	assert_int(run.index).is_equal(3)
	assert_bool(run.done()).is_false()
	run.add_results(_rows([a, b, c]))
	assert_bool(run.done()).is_true()
	for x in [a, b, c]:
		x.free()


func test_the_field_stays_the_same_and_the_grid_follows_the_standings() -> void:
	Players.clear()
	var run := CupRun.start(_cup(), "official.kart.medium", RaceEvent.new())
	var s := _session(run)
	add_child(s)
	await _loaded(s, 4)
	run.keep_roster(s)
	assert_int(run.roster.size()).is_equal(3)
	var first := {}
	for r in s.racers:
		if r is AiRacer:
			first[r.display_name] = [r.vehicle.package.path, (r as AiRacer).skill]
	# Standings with the first AI on top: it starts last next time.
	var order: Array = s.racers.duplicate()
	var top := CupRun.key_of(order[0])
	run.add_results(_rows(order))
	s.queue_free()
	await get_tree().process_frame
	var s2 := _session(run)
	add_child(s2)
	await _loaded(s2, 4)
	for r in s2.racers:
		if r is AiRacer:
			assert_str(r.vehicle.package.path).is_equal(first[r.display_name][0])
			assert_float((r as AiRacer).skill).is_equal(first[r.display_name][1])
	var grid := s2.race._grid_order().map(func(r: Racer) -> String: return CupRun.key_of(r))
	assert_array(grid).is_equal(run.grid_keys())
	assert_str(String(grid[grid.size() - 1])).is_equal(top)
	s2.queue_free()
	await get_tree().process_frame


func _session(run: CupRun) -> TrackSession:
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = run.platform_id
	var e := RaceEvent.new()
	e.kind = "race"
	e.practice_min = 0
	e.qualifying_min = 0
	e.race_laps = 1
	e.ai_count = 3
	e.ai_cars = "builtin"
	e.grid = "random" if run.index == 0 else "reverse"
	s.event = e
	s.cup = run
	return s


func _loaded(s: TrackSession, n: int) -> void:
	for i in 900:
		if s.racers.size() == n and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			return
		await get_tree().physics_frame


func test_a_cup_saves_loads_and_is_checked() -> void:
	var c := { "schema": CupRun.SCHEMA, "id": "", "name": "My Cup!", "races": [
		{ "track": "gearworks", "laps": 3 }, { "track": "marble_mile", "laps": 2 }, { "track": "skyhop_ridge", "laps": 1 }, { "track": "proving_ground", "laps": 2 }] }
	assert_str(CupRun.save(c)).is_empty()
	assert_str(String(c.id)).is_equal("my_cup")
	var back := CupRun.load_file(CupRun.user_dir + "my_cup.cup.json")
	assert_str(String(back.name)).is_equal("My Cup!")
	assert_bool(CupRun.list().any(func(e: Dictionary) -> bool: return e.id == "my_cup" and not e.builtin)).is_true()
	assert_bool(CupRun.list().any(func(e: Dictionary) -> bool: return e.id == "spark_cup" and e.builtin)).is_true()
	# A second one by the same name gets its own file.
	var again := c.duplicate(true)
	again.id = ""
	assert_str(CupRun.save(again)).is_empty()
	assert_str(String(again.id)).is_equal("my_cup_2")
	# Three races, or none named: not saved.
	var short := c.duplicate(true)
	short.races.pop_back()
	assert_str(CupRun.save(short)).is_equal("Needs four races")
	var unnamed := c.duplicate(true)
	unnamed.name = " "
	assert_str(CupRun.check(unnamed)).is_equal("No name")
	# A track that isn't here.
	assert_int(CupRun.missing_track(c)).is_equal(-1)
	c.races[2].track = "nowhere"
	assert_int(CupRun.missing_track(c)).is_equal(2)
	CupRun.delete("my_cup")
	CupRun.delete("my_cup_2")
	assert_bool(FileAccess.file_exists(CupRun.user_dir + "my_cup.cup.json")).is_false()


func test_the_standings_screen_reads_the_table() -> void:
	var run := CupRun.start(_cup(), "official.kart.medium", RaceEvent.new())
	var a := _ai("Vega")
	var b := _ai("Rook")
	run.add_results(_rows([a, b]))
	var menu := CupStandingsMenu.new()
	menu.run = run
	add_child(menu)
	await get_tree().process_frame
	assert_str(menu.row_text(0)).is_equal("1, Vega, 15 points, 1 win, last race P1")
	var next := menu.find_children("*", "Button", true, false).filter(func(x: Button) -> bool: return x.text.begins_with("Next race: "))
	assert_int(next.size()).is_equal(1)
	assert_str((next[0] as Button).text).is_equal("Next race: Marble Mile")
	menu.queue_free()
	a.free()
	b.free()
