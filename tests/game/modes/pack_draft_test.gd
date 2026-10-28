extends GdUnitTestSuite
## Pack drafting (D228): in a pack a line of cars goes faster the longer it is, a car alongside at
## the rear quarter takes air off a car's side, and a straight push from behind doesn't turn the
## car pushed.

const OVAL := "res://content/tracks/piedmont_speedway"


func before() -> void:
	Settings.use_folder("user://tests/pack_draft")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_lines_are_cars_tucked_in_one_behind_the_next() -> void:
	var a: Racer = auto_free(Racer.new())
	var b: Racer = auto_free(Racer.new())
	var c: Racer = auto_free(Racer.new())
	var d: Racer = auto_free(Racer.new())
	var e: Racer = auto_free(Racer.new())
	var gone: Racer = auto_free(Racer.new())
	var tows := { a: [0.0, null], b: [0.8, a], c: [0.6, b], d: [0.1, c], e: [0.9, gone] }
	var sizes := Slipstream.line_sizes(tows, 0.25)
	assert_int(sizes[a]).is_equal(3)
	assert_int(sizes[b]).is_equal(3)
	assert_int(sizes[c]).is_equal(3)
	assert_int(sizes[d]).is_equal(1) # too far back to be in it
	assert_int(sizes[e]).is_equal(1) # behind a car that isn't drafting


## A session on the oval with `ai` AI cars, drafting on (pack racing from the track's rules), the
## AI's drivers off so the cars stay where they're put.
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


func _cars(s: TrackSession, count: int) -> Array:
	for i in 900:
		var ready := s.racers.filter(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null)
		if ready.size() >= count and s.draft:
			for r: Racer in ready:
				if r != s.players[0]:
					r.driver.process_mode = Node.PROCESS_MODE_DISABLED
			return ready
		await get_tree().physics_frame
	return []


## Puts each car at [along, across] from the backstretch's start, rolling at `speed`.
func _place(s: TrackSession, cars: Array, spots: Array, speed := 30.0) -> void:
	var back := s.track.start_m + s.track.length / 2.0
	for k in cars.size():
		var at := s.track.transform_at(back + float(spots[k][0]), float(spots[k][1]))
		(cars[k] as Racer).vehicle.reset_to(at, at.basis.z * speed)
	for i in 6:
		await get_tree().physics_frame


func test_a_longer_line_goes_faster_and_a_car_alongside_slows_one() -> void:
	var s := _session(3)
	var cars: Array = await _cars(s, 4)
	assert_bool(s.draft.pack).is_true()
	# Two lines: three cars nose to tail, and one on its own beside them further up.
	await _place(s, cars, [[0.0, 0.0], [-8.0, 0.0], [-16.0, 0.0], [60.0, 4.0]])
	var line_back := (cars[2] as Racer).vehicle.sim.get_drag_scale()
	assert_int(int(s.draft.lines[cars[0]])).is_equal(3)
	assert_int(int(s.draft.lines[cars[3]])).is_equal(1)
	# The leader of a line of three is pushed along more than the lead cut alone gives.
	assert_float((cars[0] as Racer).vehicle.sim.get_drag_scale()).is_less(1.0 - float(s.draft.tuning.line_cut) + 0.001)
	# A pair: the car behind gets less than the last of three.
	await _place(s, cars, [[0.0, 0.0], [-8.0, 0.0], [-80.0, 4.0], [60.0, 4.0]])
	assert_float((cars[1] as Racer).vehicle.sim.get_drag_scale()).is_greater(line_back)
	# Side by side, the other car's nose at this one's rear quarter: more drag for this one only.
	await _place(s, cars, [[0.0, 0.0], [-3.5, 2.3], [-80.0, 4.0], [60.0, 4.0]])
	assert_float(Slipstream.side(cars[0], s.racers, 1.0, 20.0)).is_greater(0.5)
	assert_float(Slipstream.side(cars[1], s.racers, 1.0, 20.0)).is_equal(0.0)
	assert_float((cars[0] as Racer).vehicle.sim.get_drag_scale()).is_greater(1.0)
	s.queue_free()
	await get_tree().physics_frame


## The most the front car turns (|yaw rate|, rad/s) after the one behind runs into it, `offset` m
## to one side, closing at `closing` m/s, with bump drafting on or off.
func _bump(s: TrackSession, cars: Array, offset: float, closing: float, on: bool) -> float:
	var front: Racer = cars[1]
	var back: Racer = cars[2]
	front.vehicle.bump_draft = on
	back.vehicle.bump_draft = on
	var d := s.track.start_m + s.track.length / 2.0
	var a := s.track.transform_at(d)
	var b := s.track.transform_at(d - 5.2, offset)
	front.vehicle.reset_to(a, a.basis.z * 30.0)
	back.vehicle.reset_to(b, b.basis.z * (30.0 + closing))
	(cars[0] as Racer).vehicle.reset_to(s.track.transform_at(d + 300.0, 4.0)) # out of the way
	var most := 0.0
	for i in 90:
		await get_tree().physics_frame
		most = maxf(most, absf(front.vehicle.angular_velocity.dot(front.vehicle.global_basis.y)))
	return most


func test_a_straight_push_doesnt_turn_the_car_in_front() -> void:
	var s := _session(2)
	var cars: Array = await _cars(s, 3)
	assert_bool(cars[1].vehicle.bump_draft).is_true() # on in a pack
	var gentle_on: float = await _bump(s, cars, 0.4, 2.5, true)
	var gentle_off: float = await _bump(s, cars, 0.4, 2.5, false)
	assert_float(gentle_on).override_failure_message("on %.3f, off %.3f rad/s" % [gentle_on, gentle_off]).is_less(gentle_off * 0.5)
	# A hard hit turns it as ever.
	var hard_on: float = await _bump(s, cars, 0.4, 9.0, true)
	var hard_off: float = await _bump(s, cars, 0.4, 9.0, false)
	assert_float(hard_on).override_failure_message("on %.3f, off %.3f rad/s" % [hard_on, hard_off]).is_equal_approx(hard_off, hard_off * 0.15)
	s.queue_free()
	await get_tree().physics_frame
