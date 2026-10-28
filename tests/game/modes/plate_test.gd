extends GdUnitTestSuite
## Restrictor plates (D226): with a plate on, every car in a Track session has the Track mode's
## share of its power, through a setup change, and the AI plans its speeds with it.

const OVAL := "res://content/tracks/piedmont_speedway"


func before() -> void:
	Settings.use_folder("user://tests/plate")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(plate: String) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = OVAL
	s.platform_id = "official.track.stock_car"
	s.event = RaceEvent.free_drive()
	s.event.plate = plate
	s.event.fuel_x = 0
	s.event.tyre_x = 0
	s.ai_racers = 1
	s.ai_builtin_cars = true
	add_child(s)
	return s


func _cars(s: TrackSession) -> Array:
	for i in 900:
		var ready := s.racers.filter(func(r: Racer) -> bool: return r.vehicle != null)
		if ready.size() >= 2:
			return ready
		await get_tree().physics_frame
	return []


func test_a_plate_cuts_every_cars_power() -> void:
	var s := _session("medium")
	var cars: Array = await _cars(s)
	assert_int(cars.size()).is_equal(2)
	var share := RaceEvent.plate_share("medium", s.mode)
	assert_float(s.plate_share).is_equal(share)
	assert_float(share).is_less(1.0)
	for r: Racer in cars:
		assert_float(r.vehicle.power_cap).is_equal(share)
	# A setup change builds the car's model again; the plate stays on.
	var car: Vehicle = (cars[0] as Racer).vehicle
	car.apply_setup(null)
	assert_float(car.power_cap).is_equal(share)
	# The AI plans with the power it has: its lap is slower than an unplated car's.
	var ai: Racer = cars.filter(func(r: Racer) -> bool: return r.driver is RacingAI and r != s.players[0])[0]
	var driver := ai.driver as RacingAI
	var line := RacingLine.for_track(s.track)
	var grip := driver._base_grip()
	assert_float(line.lap_time(driver._profile)).is_greater(line.lap_time(line.speed_profile(ai.vehicle.base_platform, grip)) + 0.1)
	s.queue_free()
	await get_tree().physics_frame


func test_no_plate_leaves_the_power_alone() -> void:
	var s := _session("off")
	var cars: Array = await _cars(s)
	assert_float(s.plate_share).is_equal(1.0)
	for r: Racer in cars:
		assert_float(r.vehicle.power_cap).is_equal(1.0)
	s.queue_free()
	await get_tree().physics_frame
