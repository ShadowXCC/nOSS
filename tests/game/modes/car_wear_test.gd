extends GdUnitTestSuite
## Fuel and tires (D209): fuel burns with the engine's work and runs dry, tires wear with sliding
## and grip less, a lap's fuel gives laps left, service refills and fits tires; in a session the
## cars this game drives use fuel and wear tires, a dry car only coasts, and the HUD says so.

const TRACK := "res://content/tracks/proving_ground"


func before() -> void:
	Settings.use_folder("user://tests/car_wear")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _stock() -> Dictionary:
	return PlatformLoader.load_official("official.track.stock_car").platform


func test_fuel_burns_and_laps_are_counted() -> void:
	var w := CarWear.make(_stock(), 4, 1, 0)
	assert_float(w.fuel_l).is_equal(68.0)
	assert_bool(w.uses_fuel()).is_true()
	assert_bool(w.wears_tires()).is_false()
	# 0.32 L a kWh: 3.6 MJ burns 0.32 L.
	w.lap_started(1)
	w.burn(3.6e6)
	assert_float(w.fuel_l).is_equal_approx(67.68, 0.001)
	assert_float(w.laps_left()).is_equal(INF) # no lap measured yet
	w.lap_started(2)
	assert_float(w.lap_fuel).is_equal_approx(0.32, 0.001)
	assert_float(w.laps_left()).is_equal_approx(67.68 / 0.32, 0.01)
	# Five times the use burns five times the fuel; it runs dry once.
	var x5 := CarWear.make(_stock(), 4, 5, 0)
	x5.burn(3.6e6)
	assert_float(x5.fuel_l).is_equal_approx(66.4, 0.001)
	assert_bool(x5.burn(1e9)).is_true()
	assert_float(x5.fuel_l).is_equal(0.0)
	assert_bool(x5.burn(1e6)).is_false() # already dry
	# Service: to the top at most, and a lap with a refill in it isn't a measure.
	x5.lap_started(1)
	x5.service(30.0, 0)
	x5.burn(3.6e6)
	x5.lap_started(2)
	assert_float(x5.fuel_l).is_equal_approx(28.4, 0.001)
	assert_float(x5.lap_fuel).is_equal(0.0)
	x5.service(500.0, 0)
	assert_float(x5.fuel_l).is_equal(68.0)


func test_tires_wear_and_grip_less() -> void:
	var w := CarWear.make(_stock(), 4, 0, 2)
	assert_bool(w.wears_tires()).is_true()
	assert_bool(w.uses_fuel()).is_false()
	assert_float(w.laps_left()).is_equal(INF)
	# 60 MJ a tire at 1x: 15 MJ at 2x is half of it.
	w.scrub(PackedFloat32Array([15e6, 3e6, 0.0, 30e6]))
	assert_float(w.wear[0]).is_equal_approx(0.5, 0.001)
	assert_float(w.wear[3]).is_equal(1.0)
	assert_float(w.grip_of(3)).is_equal_approx(0.85, 0.001)
	assert_float(w.grip_of(2)).is_equal(1.0)
	assert_float(w.tire_grip()).is_equal_approx(0.85, 0.001)
	assert_float(w.tread()).is_equal(0.0)
	# Two tires: the two most worn.
	w.service(0.0, 2)
	assert_float(w.wear[3]).is_equal(0.0)
	assert_float(w.wear[0]).is_equal(0.0)
	assert_float(w.wear[1]).is_greater(0.0)
	w.service(0.0, 4)
	assert_float(w.tread()).is_equal(1.0)
	# A class without its own figures takes the defaults.
	var gt := CarWear.make(PlatformLoader.load_official("official.track.gt").platform, 4, 1, 1)
	assert_float(gt.tank_l).is_equal(CarWear.DEFAULT_FUEL.tank_l)
	assert_float(gt.worn_grip).is_equal(CarWear.DEFAULT_TIRES.worn_grip)


func _session(fuel_x: int, tyre_x: int) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = TRACK
	s.platform_id = "official.track.stock_car"
	s.event = RaceEvent.free_drive()
	s.event.fuel_x = fuel_x
	s.event.tyre_x = tyre_x
	s.autodrive = true
	add_child(s)
	return s


func test_a_session_uses_fuel_and_tires_and_the_hud_shows_them() -> void:
	var s := _session(10, 10)
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle and s.wear and s.wear.cars.has(s.players[0]):
			break
		await get_tree().physics_frame
	assert_object(s.wear).is_not_null()
	var p := s.players[0]
	var w := s.wear.of(p)
	for i in 600: # five seconds of driving
		await get_tree().physics_frame
	assert_float(w.fuel_l).is_less(68.0)
	assert_float(w.tread()).is_less(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := p.hud as Hud
	assert_str(hud._wear.text).contains("Fuel")
	assert_str(hud._wear.text).contains("Tires")
	assert_bool(hud._wear.visible).is_true()
	# Dry: no power, only coasting.
	w.fuel_l = 0.0
	for i in 120:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(hud._wear.text).contains("Out of fuel")
	var v := p.vehicle.sim.get_speed()
	for i in 240:
		await get_tree().physics_frame
	assert_float(p.vehicle.sim.get_speed()).is_less(v + 0.5) # never faster again
	s.queue_free()
	await get_tree().process_frame


func test_without_fuel_or_wear_nothing_changes() -> void:
	var s := _session(0, 0)
	for i in 120:
		await get_tree().physics_frame
	assert_object(s.wear).is_null()
	s.queue_free()
	await get_tree().process_frame
