extends GdUnitTestSuite
## Pack racing (D213): with drafting on a track that suggests it, the AI runs in grooves (lanes a
## car and some room apart, the middle one a line solved with room for the others); a car in the
## draft makes a run into a free groove and passes; two cars side by side hold their grooves
## without touching. Below MISTAKE_SKILL the AI makes mistakes (D229), one being a block made
## late, onto a car already alongside.

const OVAL := "res://content/tracks/piedmont_speedway"


func before() -> void:
	Settings.use_folder("user://tests/pack_racing")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_the_grooves_are_parallel_lanes_on_the_road() -> void:
	var t := TrackLoader.load_package(OVAL).track
	var line := RacingLine.for_track(t)
	var grooves := line.grooves()
	assert_int(grooves.size()).is_equal(RacingLine.GROOVES_EACH_SIDE * 2 + 1)
	assert_object(line.grooves()[0]).is_same(grooves[0]) # made once
	for i in range(0, t.samples.size(), 7):
		for g in grooves.size() - 1:
			var a: RacingLine = grooves[g]
			var b: RacingLine = grooves[g + 1]
			assert_float(b.offsets[i] - a.offsets[i]).is_equal_approx(RacingLine.GROOVE_M, 0.001)
		var c := RacingLine.limits(t, i)
		assert_float((grooves[grooves.size() - 1] as RacingLine).offsets[i]).is_less_equal(c.x + 0.01)
		assert_float((grooves[0] as RacingLine).offsets[i]).is_greater_equal(c.y - 0.01)
	# Each has its own speeds; the middle one is nearly as quick as the line (with less room).
	var p := PlatformLoader.load_official("official.track.stock_car").platform
	var middle: RacingLine = grooves[RacingLine.GROOVES_EACH_SIDE]
	assert_float(middle.lap_time(middle.speed_profile(p, 0.9))).is_less(line.lap_time(line.speed_profile(p, 0.9)) * 1.04)


## A session on the oval with `ai` AI cars and drafting on (pack racing from the track's rules);
## the player's car waits in a pit box.
func _session(ai: int) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = OVAL
	s.platform_id = "official.track.stock_car"
	s.event = RaceEvent.free_drive()
	s.event.draft = "on"
	s.event.fuel_x = 0
	s.event.tyre_x = 0
	s.ai_racers = ai
	s.ai_builtin_cars = true
	add_child(s)
	return s


func _wait(s: TrackSession, count: int) -> void:
	for i in 900:
		var ready := s.racers.filter(func(r: Racer) -> bool: return r.vehicle != null)
		if ready.size() >= count and s.draft:
			break
		await get_tree().physics_frame
	var p := s.players[0]
	p.vehicle.reset_to(s.track.pit.boxes[0])
	p.pit_hold = true


func _ais(s: TrackSession) -> Array:
	return s.racers.filter(func(r: Racer) -> bool: return r.driver is RacingAI and r.driver != s.players[0].driver)


## Puts `r` at `d` along the road in groove `g`, at `speed`.
func _place(s: TrackSession, r: Racer, d: float, g: int, speed: float) -> void:
	var ai := r.driver as RacingAI
	var lane: RacingLine = RacingLine.for_track(s.track).grooves()[g]
	var at := s.track.transform_at(d, lane.offset_at(d))
	r.vehicle.reset_to(at, at.basis.z * speed)
	await get_tree().physics_frame
	ai.resync(g)


func _progress(r: Racer) -> float:
	return r.timer.lap * r.track.length + r.track.from_start(r.distance)


func test_a_car_in_the_draft_makes_a_run_and_passes() -> void:
	var s := _session(2)
	await _wait(s, 3)
	var cars := _ais(s)
	var lead: Racer = cars[0]
	var follower: Racer = cars[1]
	assert_bool((lead.driver as RacingAI).pack).is_true()
	(lead.driver as RacingAI).skill = 0.0 # slower, and never blocks
	(follower.driver as RacingAI).skill = 100.0
	var middle := RacingLine.GROOVES_EACH_SIDE
	var start := s.track.start_m + 100.0
	await _place(s, lead, start + 18.0, middle, 70.0)
	await _place(s, follower, start, middle, 70.0)
	var ran := false
	var passed := false
	var touched := false
	for i in 120 * 45:
		await get_tree().physics_frame
		ran = ran or (follower.driver as RacingAI).intent == "run"
		touched = touched or (follower.vehicle.last_hit == lead.vehicle and follower.vehicle.car_impulse > 500.0)
		if _progress(follower) > _progress(lead) + RacingAI.CAR_LENGTH + 2.0:
			passed = true
			break
	assert_bool(ran).is_true()
	assert_bool(passed).override_failure_message("lead %.0f, follower %.0f" % [_progress(lead), _progress(follower)]).is_true()
	assert_bool(touched).is_false()
	s.queue_free()
	await get_tree().process_frame


func test_two_cars_side_by_side_hold_their_grooves() -> void:
	var s := _session(2)
	await _wait(s, 3)
	var cars := _ais(s)
	var a: Racer = cars[0]
	var b: Racer = cars[1]
	for r: Racer in cars:
		(r.driver as RacingAI).skill = 80.0
	var middle := RacingLine.GROOVES_EACH_SIDE
	var start := s.track.start_m + 100.0
	await _place(s, a, start, middle, 65.0)
	await _place(s, b, start, middle + 1, 65.0)
	var touched := false
	var closest := INF
	for i in 120 * 15:
		await get_tree().physics_frame
		touched = touched or (a.vehicle.last_hit == b.vehicle and a.vehicle.car_impulse > 500.0)
		if absf(s.field.gap(a, b)) < RacingAI.CAR_LENGTH:
			closest = minf(closest, absf(a.lateral - b.lateral))
	assert_bool(touched).is_false()
	assert_float(closest).is_greater(RacingAI.CAR_WIDTH + 0.3)
	s.queue_free()
	await get_tree().process_frame


## Mistakes (D229): none from MISTAKE_SKILL up, more the lower the skill.
func test_only_the_less_skilled_make_mistakes() -> void:
	var s := _session(1)
	await _wait(s, 2)
	var ai := _ais(s)[0].driver as RacingAI
	ai.skill = 95.0
	assert_float(ai._blunder()).is_equal(0.0)
	ai.skill = RacingAI.MISTAKE_SKILL * 100.0
	assert_float(ai._blunder()).is_equal(0.0)
	ai.skill = 60.0
	var some := ai._blunder()
	ai.skill = 20.0
	assert_float(ai._blunder()).is_greater(some)
	assert_float(some).is_greater(0.0)
	s.queue_free()
	await get_tree().physics_frame


## A run it didn't see coming: once the car's alongside, it moves over on it anyway; a car that saw
## it coming would have blocked early or let it go, and doesn't move over on a car alongside.
func test_a_late_block_moves_over_on_a_car_alongside() -> void:
	var s := _session(2)
	await _wait(s, 3)
	var cars := _ais(s)
	var me: Racer = cars[0]
	var them: Racer = cars[1]
	var mine := me.driver as RacingAI
	var middle := RacingLine.GROOVES_EACH_SIDE
	var d := s.track.start_m + s.track.length / 2.0
	for late in [false, true]:
		mine._block_wait = 0.0
		mine._run = null
		await _place(s, me, d, middle, 40.0)
		await _place(s, them, d - 2.0, middle + 1, 44.0) # its nose 2.6 m past our tail
		mine._late_block = them if late else null
		var moved := false
		for i in 12:
			await get_tree().physics_frame
			moved = moved or mine._groove == middle + 1 # into its groove (side by side says so after)
		assert_bool(moved).override_failure_message("late %s" % late).is_equal(late)
	s.queue_free()
	await get_tree().physics_frame

