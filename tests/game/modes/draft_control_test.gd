extends GdUnitTestSuite
## Drafting in Track sessions (D208): with the event's drafting on, a car tucked in behind another
## meets less drag (Slipstream.tow), the car in front a little less too (the lead cut); with it off
## nothing changes; the AI keeps the speed a tow gives it.

const TRACK := "res://content/tracks/proving_ground"


func before() -> void:
	Settings.use_folder("user://tests/draft_control")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(draft: String) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = TRACK
	s.platform_id = "official.track.stock_car"
	s.event = RaceEvent.free_drive()
	s.event.draft = draft
	s.ai_racers = 1
	add_child(s)
	return s


## The player and the AI car, the AI's driver off.
func _cars(s: TrackSession) -> Array:
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle:
			var others := s.racers.filter(func(r: Racer) -> bool: return r != s.players[0] and r.vehicle != null and r.driver != null)
			if not others.is_empty():
				others[0].driver.process_mode = Node.PROCESS_MODE_DISABLED
				return [s.players[0], others[0]]
		await get_tree().physics_frame
	return []


## `behind` m behind `ahead` on the start straight, both rolling at 30 m/s.
func _line_up(s: TrackSession, ahead: Racer, behind: Racer, gap: float) -> void:
	var front := s.track.transform_at(s.track.start_m + 300.0)
	ahead.vehicle.reset_to(front, front.basis.z * 30.0)
	var back := s.track.transform_at(s.track.start_m + 300.0 - gap)
	behind.vehicle.reset_to(back, back.basis.z * 30.0)
	for i in 6:
		await get_tree().physics_frame


func test_a_car_behind_drafts_and_pushes_the_one_in_front() -> void:
	var s := _session("on")
	var cars: Array = await _cars(s)
	var p: Racer = cars[0]
	var ai: Racer = cars[1]
	assert_object(s.draft).is_not_null()
	await _line_up(s, ai, p, 6.0)
	assert_float(Slipstream.tow(p, s.racers, 40.0, 1.2, 20.0)).is_between(0.8, 0.9)
	assert_float(Slipstream.tow(ai, s.racers, 40.0, 1.2, 20.0)).is_equal(0.0)
	var behind := p.vehicle.sim.get_drag_scale()
	var front := ai.vehicle.sim.get_drag_scale()
	assert_float(behind).is_between(0.7, 0.8)
	assert_float(front).is_between(0.95, 0.999) # the lead cut
	# Out of the slipstream (beside it): no draft.
	var beside := s.track.transform_at(s.track.start_m + 294.0, 4.0)
	p.vehicle.reset_to(beside, beside.basis.z * 30.0)
	for i in 6:
		await get_tree().physics_frame
	assert_float(p.vehicle.sim.get_drag_scale()).is_equal(1.0)
	s.queue_free()
	await get_tree().process_frame


func test_with_drafting_off_nothing_changes() -> void:
	var s := _session("off")
	var cars: Array = await _cars(s)
	assert_object(s.draft).is_null()
	await _line_up(s, cars[1], cars[0], 6.0)
	assert_float((cars[0] as Racer).vehicle.sim.get_drag_scale()).is_equal(1.0)
	s.queue_free()
	await get_tree().process_frame


func test_the_ai_keeps_a_tows_speed() -> void:
	var s := _session("on")
	var cars: Array = await _cars(s)
	var ai: Racer = cars[1]
	var driver := ai.driver as RacingAI
	assert_bool(driver._ceiling.is_empty()).is_false()
	var plain := (driver._line as RacingLine).speed_profile(ai.vehicle.base_platform, 1.0)
	var ceiling := (driver._line as RacingLine).ceiling(ai.vehicle.base_platform, 1.0)
	var above := 0
	for i in plain.size():
		assert_float(ceiling[i]).is_greater_equal(plain[i] - 0.001)
		above += 1 if ceiling[i] > plain[i] + 1.0 else 0
	assert_int(above).is_greater(0) # on the straights power holds it back, not the corners
	s.queue_free()
	await get_tree().process_frame
