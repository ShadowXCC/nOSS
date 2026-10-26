extends GdUnitTestSuite
## New events online (UI overhaul P10, protocol 14; docs/NETWORKING.md §15): a time trial's
## minutes go with time trials and servers take them; a timed time trial ends with its results; the
## live board (TimeTrialNet) is fastest first and survives the wire; a highway run is a session kind
## of its own; servers take a kart cup's races.


func before() -> void:
	Settings.use_folder("user://tests/online_events")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_protocol_14() -> void:
	assert_int(NetProtocol.VERSION).is_equal(14)
	# Kinds are appended, never reordered: a run is the ninth.
	assert_int(NetRace.KINDS.find("run")).is_equal(8)
	assert_int(NetRace.KINDS.find("drag")).is_equal(7)


func test_time_trial_minutes_go_with_time_trials() -> void:
	var tt := RaceEvent.time_trial()
	tt.tt_min = 15
	assert_int(int(tt.to_dict().tt_min)).is_equal(15)
	assert_int(RaceEvent.from_dict(tt.to_dict()).tt_min).is_equal(15)
	assert_bool(RaceEvent.free_drive().to_dict().has("tt_min")).is_false()
	assert_int(RaceEvent.from_dict({ "kind": "time_trial", "tt_min": 999 }).tt_min).is_equal(RaceEvent.TT_MAX)
	assert_int(RaceEvent.from_dict({ "kind": "time_trial", "tt_min": -3 }).tt_min).is_equal(0)


func test_a_run_is_its_own_session() -> void:
	assert_array(Array(RaceEvent.highway("run").sessions())).contains_exactly(["run"])
	assert_array(Array(RaceEvent.highway("score").sessions())).contains_exactly(["free"])
	assert_array(Array(RaceEvent.highway("loop").sessions())).contains_exactly(["free"])


## A server's config (a file, or what a listen server keeps in settings.cfg) takes time trials and
## a cup's races, numbers as JSON gives them.
func test_server_configs_take_time_trials_and_cups() -> void:
	var tt := RaceEvent.time_trial()
	tt.tt_min = 10
	var d: Dictionary = JSON.parse_string(JSON.stringify({ "schema": ServerConfig.SCHEMA, "rotation": [
		{ "track": "proving_ground", "class": "official.track.gt", "event": tt.to_dict(), "name": "Regular time trial" },
		{ "track": "marble_mile", "class": EventFlow.KART, "event": { "kind": "race", "race_laps": 3 }, "name": "Spark Cup, race 2 of 4",
			"cup": { "id": "spark_cup", "name": "Spark Cup", "race": 1, "races": 4 } },
	] }))
	var errors := PackedStringArray()
	var cfg := ServerConfig.from_dict(d, errors)
	assert_array(Array(errors)).is_empty()
	assert_str(cfg.event(0).kind).is_equal("time_trial")
	assert_int(cfg.event(0).tt_min).is_equal(10)
	assert_dict(cfg.cup_of(0)).is_empty()
	assert_dict(cfg.cup_of(1)).is_equal({ "id": "spark_cup", "name": "Spark Cup", "race": 1, "races": 4 })
	assert_dict(cfg.cup_of(5)).is_empty()
	# A cup item without its race number isn't one.
	d.rotation[1].cup.erase("race")
	assert_array(Array(JsonSchema.validate(d, JsonSchema.load_schema("server")))).is_not_empty()


## Hosting a cup: its races one after another, each marked as the cup's, the later ones on a
## reversed grid; a time trial online has minutes (local: none).
func test_the_event_pages_make_the_playlist() -> void:
	var flow := EventFlow.racing("kart", false, "host")
	flow.recall()
	flow.cup = "res://data/cups/spark_cup.cup.json"
	flow.fit()
	var items := flow.rotation_items()
	assert_int(items.size()).is_equal(4)
	assert_str(String(items[0].track)).is_equal(TrackLibrary.resolve("proving_ground"))
	assert_int(int(RaceEvent.from_dict(items[1].event).race_laps)).is_equal(3)
	assert_str(RaceEvent.from_dict(items[0].event).grid).is_equal("random")
	assert_str(RaceEvent.from_dict(items[3].event).grid).is_equal("reverse")
	assert_dict(items[3].cup).is_equal({ "id": "spark_cup", "name": "Spark Cup", "race": 3, "races": 4 })
	assert_int(flow.server_config().rotation.size()).is_equal(4)
	var race := EventFlow.racing("kart", false, "host")
	race.recall()
	race.cup = ""
	assert_int(race.rotation_items().size()).is_equal(1)
	assert_bool(race.rotation_items()[0].has("cup")).is_false()
	var tt := EventFlow.racing("regular", true, "host")
	tt.recall()
	assert_str(tt.event.kind).is_equal("time_trial")
	assert_int(tt.event.tt_min).is_equal(EventFlow.TT_DEFAULT)
	var local := EventFlow.racing("regular", true)
	local.recall()
	assert_int(local.event.tt_min).is_equal(0)
	# Highway's modes stay as picked when hosting.
	var highway := EventFlow.make("highway", "", false, "host")
	highway.recall()
	highway.event.sub = "score"
	highway.fit()
	assert_str(highway.event.sub).is_equal("score")


## A timed time trial ends when its minutes are up (a car that never started a lap is in at
## once), with its results: best laps, as practice's.
func test_a_timed_time_trial_ends_with_its_results() -> void:
	Players.clear()
	var s := TrackSession.new()
	var e := RaceEvent.time_trial()
	e.tt_min = 1
	s.event = e
	add_child(s)
	for i in 600:
		await get_tree().physics_frame
		if not s.players.is_empty() and s.players[0].vehicle:
			break
	assert_str(s.race.kind).is_equal("time_trial")
	assert_bool(s.race.timed()).is_true()
	s.race.clock = 0.0
	assert_str(s.race.session_text(s.players[0])).is_equal("Time trial  1:00")
	var ended := []
	s.race.session_ended.connect(func(kind: String, rows: Array) -> void: ended.append([kind, rows.size()]))
	s.race.clock = 60.0
	for i in 5:
		await get_tree().physics_frame
	assert_array(ended).contains_exactly([["time_trial", 1]])
	s.queue_free()
	await get_tree().process_frame


## The live board: each driver's best lap, fastest first, drivers without a lap left out; a place
## by car id; the board's id and laps survive the wire.
func test_the_live_board() -> void:
	var made: Array[Racer] = []
	for d: Array in [[1, "Ana", 71.5, 4], [2, "Bo", 70.25, 3], [3, "Cy", -1.0, 1], [301, "Police", 50.0, 9]]:
		var r := Racer.new()
		r.net_id = d[0]
		r.display_name = d[1]
		r.timer.best_lap = d[2]
		r.timer.lap = d[3]
		made.append(r)
	var tn := TimeTrialNet.new()
	var board := TimeTrialNet.board_of(made)
	assert_array(board.map(func(e: Dictionary) -> String: return e.name)).contains_exactly(["Bo", "Ana"])
	assert_int(int(board[0].laps)).is_equal(2)
	tn.entries = board
	assert_int(tn.place_of(1)).is_equal(2)
	assert_int(tn.place_of(3)).is_equal(0)
	var got := []
	var take := func(name: String, entries: Array) -> void: got.append([name, entries])
	Net.board_received.connect(take)
	Net._handle(NetProtocol.Msg.BOARD, { "board": TimeTrialNet.BOARD, "entries": board })
	Net.board_received.disconnect(take)
	assert_str(String(got[0][0])).is_equal("live")
	assert_int(int(got[0][1][0].id)).is_equal(2)
	assert_float(float(got[0][1][0].time)).is_equal_approx(70.25, 0.001)
	assert_int(int(got[0][1][1].laps)).is_equal(3)
	for r in made:
		r.free()
	tn.free()
