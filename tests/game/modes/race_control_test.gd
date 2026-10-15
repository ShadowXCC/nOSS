extends GdUnitTestSuite
## Race control (MODE-02): standings, the finish and results, the grid from qualifying, track
## limit rulings and flags, driven with racers placed by hand (no cars).

const TRACK := "res://content/tracks/proving_ground/track.json"

var _session: TrackSession
var _race: RaceControl


func before_test() -> void:
	_session = auto_free(TrackSession.new())
	_session.track = TrackData.load_file(TRACK)
	_session.field.track = _session.track
	_session.field.racers = _session.racers
	_session.race.free() # the session's own; this test brings one it drives by hand
	_race = auto_free(RaceControl.new())
	_race.session = _session
	_race.event = RaceEvent.new()
	_race.event.kind = "race"
	_race.event.race_laps = 3
	_session.race = _race


func after_test() -> void:
	# Members a session would add to the tree in _ready.
	_session.views.free()
	_session.field.free()


func _racer(n: int) -> Racer:
	var r: Racer = auto_free(Racer.new())
	r.session = _session
	r.track = _session.track
	r.number = n
	r.display_name = "R%d" % n
	r.setup()
	_session.racers.append(r)
	_race.watch(r)
	return r


## Puts `r` on lap `lap` (timer laps: 1 = first lap after the first crossing) at `from_line` m.
func _at(r: Racer, lap: int, from_line: float) -> void:
	r.timer.lap = lap
	r.distance = fposmod(_session.track.start_m + from_line, _session.track.length)


func test_race_standings_follow_laps_then_position() -> void:
	var a := _racer(1)
	var b := _racer(2)
	var c := _racer(3)
	_race.kind = "race"
	_at(a, 2, 100.0)
	_at(b, 2, 900.0)
	_at(c, 3, 10.0)
	assert_array(_race.standings()).is_equal([c, b, a])
	assert_int(_race.position_of(b)).is_equal(2)


func test_finish_order_counts_penalties_and_lapped_cars() -> void:
	var a := _racer(1)
	var b := _racer(2)
	var c := _racer(3)
	_race.begin("race")
	_race.phase = RaceControl.Phase.RUNNING
	for r: Racer in [a, b]:
		_at(r, 3, 2000.0)
		_race._laps[r] = 3
	_at(c, 2, 2000.0) # a lap down
	_race._laps[c] = 2
	# a crosses for the 3rd time: 3 laps done, the race is won.
	_race.clock = 200.0
	_at(a, 4, 5.0)
	_race._check_finish()
	assert_bool(a.finished).is_true()
	assert_int(_race.phase).is_equal(RaceControl.Phase.CHECKERED)
	# b takes the flag 1 s later but has a 2 s penalty; c is a lap down and finishes next.
	b.penalty_s = 2.0
	_race.clock = 201.0
	_at(b, 4, 5.0)
	_race._check_finish()
	_race.clock = 201.5
	_at(c, 3, 5.0)
	_race._check_finish()
	assert_int(_race.phase).is_equal(RaceControl.Phase.DONE)
	var rows := _race.results
	assert_array(rows.map(func(row: Dictionary) -> Racer: return row.racer)).is_equal([a, b, c])
	assert_str(rows[1].gap).is_equal("+3.000")
	assert_str(rows[2].gap).is_equal("+1 lap")


func test_session_ends_after_the_grace_time() -> void:
	var a := _racer(1)
	var b := _racer(2)
	_race.begin("race")
	_race.phase = RaceControl.Phase.RUNNING
	_at(a, 3, 2000.0)
	_at(b, 3, 1000.0) # a lap down: 2 laps done
	_race._laps[a] = 3
	_race._laps[b] = 3
	_race.clock = 100.0
	_at(a, 4, 2.0)
	_race._check_finish()
	_race.clock = 100.0 + RaceControl.FINISH_GRACE_S + 1.0
	_race._check_finish()
	assert_int(_race.phase).is_equal(RaceControl.Phase.DONE)
	assert_str(_race.results[1].gap).is_equal("+1 lap")


func test_grid_comes_from_qualifying_or_its_reverse() -> void:
	var a := _racer(1)
	var b := _racer(2)
	var c := _racer(3)
	_race.qualifying_order = [b, c, a]
	_race.kind = "race"
	_race.event.grid = "qualifying"
	assert_array(_race._grid_order()).is_equal([b, c, a])
	_race.event.grid = "reverse"
	assert_array(_race._grid_order()).is_equal([a, c, b])


func test_qualifying_ranks_by_best_lap() -> void:
	var a := _racer(1)
	var b := _racer(2)
	var c := _racer(3)
	_race.kind = "qualifying"
	a.timer.best_lap = 70.5
	b.timer.best_lap = 69.9
	c.timer.best_lap = -1.0
	assert_array(_race.standings()).is_equal([b, a, c])


func test_track_limits_warn_then_penalise_cuts_that_gain() -> void:
	var a := _racer(1)
	_race.begin("race")
	_race.phase = RaceControl.Phase.RUNNING
	_race.event.track_limits = "lenient"
	a.cut_track.emit(false) # running wide gains nothing
	assert_int(a.warnings).is_equal(0)
	a.cut_track.emit(true)
	assert_int(a.warnings).is_equal(1)
	assert_float(a.penalty_s).is_equal(0.0)
	a.cut_track.emit(true)
	assert_float(a.penalty_s).is_equal(2.0)
	_race.event.track_limits = "strict"
	a.cut_track.emit(false)
	assert_float(a.penalty_s).is_equal(7.0)


func test_track_limits_invalidate_practice_laps() -> void:
	var a := _racer(1)
	_race.event.practice_min = 10
	_race.begin("practice")
	a.timer.lap = 2
	a.timer.valid = true
	a.cut_track.emit(false)
	assert_bool(a.timer.valid).is_false()


func test_yellow_for_a_stopped_car_ahead_blue_for_a_car_a_lap_up() -> void:
	var me := _racer(1)
	var stopped := _racer(2)
	var leader := _racer(3)
	_race.kind = "race"
	_race.phase = RaceControl.Phase.RUNNING
	_race.clock = 100.0
	_at(me, 2, 500.0)
	me.speed = 50.0
	_at(stopped, 2, 650.0)
	stopped.speed = 0.0
	_at(leader, 3, 450.0) # a lap up, 50 m behind
	leader.speed = 55.0
	_race._update_flags()
	assert_str(me.flag).is_equal("yellow")
	stopped.speed = 40.0
	_race._update_flags()
	assert_str(me.flag).is_equal("blue")


func test_live_delta_compares_with_the_best_lap() -> void:
	var t := LapTimer.new()
	t.setup(1000.0, PackedFloat32Array([300.0, 600.0]), 100.0)
	var dt := 1.0 / 120.0
	var pos := 990.0
	t.update(pos, dt, 0.0)
	# Lap 1 at 40 m/s: 25 s.
	while t.lap < 2:
		pos = fposmod(pos + 40.0 * dt, 1000.0)
		t.update(pos, dt, 40.0)
	assert_float(t.best_lap).is_between(24.95, 25.05)
	# Lap 2 at 50 m/s: half way round it's 2.5 s up.
	while pos < 500.0:
		pos += 50.0 * dt
		t.update(pos, dt, 50.0)
	assert_float(t.live_delta()).is_between(-2.6, -2.4)


func _step(seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		_race._physics_process(0.05)


## Online, an event's first session holds every car until each game has the session's cars, at
## least SYNC_MIN_S and at most LOADING_MAX_S, then three lights (Changes.md, D127).
func test_online_start_waits_for_every_games_cars() -> void:
	_session.online = { "track": "t" } # online, as far as the race control can tell
	var a := _racer(1)
	a.vehicle = auto_free(Vehicle.new())
	var state := [Vector2i(1, 2)]
	_race.sync_state = func() -> Vector2i: return state[0]
	_race.event.kind = "free"
	_race.begin("free")
	assert_int(_race.phase).is_equal(RaceControl.Phase.LOADING)
	assert_bool(a.held).is_true()
	_step(10.0)
	assert_int(_race.phase).is_equal(RaceControl.Phase.LOADING)
	assert_str(_race.sync_text()).is_equal("Syncing 1/2")
	state[0] = Vector2i(2, 2)
	_step(0.05)
	assert_int(_race.phase).is_equal(RaceControl.Phase.COUNTDOWN)
	assert_int(_race.light_count).is_equal(RaceControl.SHORT_LIGHTS)
	var lit := []
	while _race.phase == RaceControl.Phase.COUNTDOWN and lit.size() < 200:
		if _race.lights > 0 and (lit.is_empty() or lit[-1] != _race.lights):
			lit.append(_race.lights)
		_step(0.05)
	assert_array(lit).is_equal([1, 2, 3])
	assert_int(_race.phase).is_equal(RaceControl.Phase.RUNNING)
	assert_bool(a.held).is_false()
	assert_str(_race.sync_text()).is_empty()
	# Everything's here at once: still SYNC_MIN_S on the grid.
	_race.begin("free")
	_step(RaceControl.SYNC_MIN_S - 0.5)
	assert_int(_race.phase).is_equal(RaceControl.Phase.LOADING)
	_step(0.6)
	assert_int(_race.phase).is_equal(RaceControl.Phase.COUNTDOWN)
	# A game that never gets there holds nobody past LOADING_MAX_S.
	state[0] = Vector2i(0, 1)
	_race.begin("free")
	_step(RaceControl.LOADING_MAX_S - 0.5)
	assert_int(_race.phase).is_equal(RaceControl.Phase.LOADING)
	_step(0.6)
	assert_int(_race.phase).is_equal(RaceControl.Phase.COUNTDOWN)


## Offline, free drive starts at once (no hold, no lights).
func test_offline_free_drive_goes_at_once() -> void:
	var a := _racer(1)
	a.vehicle = auto_free(Vehicle.new())
	_race.event.kind = "free"
	_race.begin("free")
	assert_int(_race.phase).is_equal(RaceControl.Phase.RUNNING)
	assert_bool(a.held).is_false()


## A race online waits the same way, then forms its grid and counts down five lights.
func test_online_race_waits_then_five_lights() -> void:
	_session.online = { "track": "t" }
	_race.sync_state = func() -> Vector2i: return Vector2i(1, 1)
	_race.begin("race")
	_step(RaceControl.SYNC_MIN_S - 0.5)
	assert_int(_race.phase).is_equal(RaceControl.Phase.LOADING)
	_step(2.0)
	assert_int(_race.phase).is_equal(RaceControl.Phase.COUNTDOWN)
	assert_int(_race.light_count).is_equal(RaceControl.LIGHTS)
	_step(RaceControl.LIGHTS * RaceControl.LIGHT_S + 1.5)
	assert_int(_race.phase).is_equal(RaceControl.Phase.RUNNING)


## The start's tones (Changes.md): a beep for each light and the go tone when they go out, five
## and one for a standing start, three and one for an online start, the go tone at a rolling
## start's green, and nothing for offline free drive.
func test_start_tones_follow_the_lights() -> void:
	var tones: StartTones = auto_free(StartTones.new())
	tones.race = _race
	add_child(tones)
	var run := func(seconds: float) -> void:
		for i in roundi(seconds / 0.05):
			_race._physics_process(0.05)
			tones._process(0.05)
	_race.begin("race")
	run.call(10.0)
	assert_int(_race.phase).is_equal(RaceControl.Phase.RUNNING)
	assert_array([tones.beeps, tones.gos]).is_equal([5, 1])
	_race.event.kind = "free"
	_race.begin("free")
	run.call(5.0)
	assert_array([tones.beeps, tones.gos]).is_equal([5, 1])
	_session.online = { "track": "t" }
	_race.begin("free")
	run.call(10.0)
	assert_array([tones.beeps, tones.gos]).is_equal([8, 2])
	# A rolling start's green.
	_race.phase = RaceControl.Phase.FORMATION
	tones._process(0.05)
	_race._go()
	tones._process(0.05)
	assert_int(tones.gos).is_equal(3)
	var beep := StartTones.stream("beep")
	assert_int(beep.data.size()).is_equal(int(EngineSound.RATE * StartTones.BEEP_S) * 2)
	assert_int(beep.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
