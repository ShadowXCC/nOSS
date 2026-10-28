extends GdUnitTestSuite
## The yellow line (D227): a car with all four wheels on the apron is below it; coming back up past
## a car it had just ahead is a place gained there, unless that car was in trouble. The track
## suggests it, with track limits on.

const OVAL := "res://content/tracks/piedmont_speedway"


func before() -> void:
	Settings.use_folder("user://tests/yellow_line")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_the_track_suggests_it_with_track_limits_on() -> void:
	var t := TrackLoader.load_package(OVAL).track
	var raw: Dictionary = t.raw.duplicate(true)
	raw.rules = { "yellow_line": true }
	var lined := TrackData.from_dict(raw)
	var e := RaceEvent.new()
	e.kind = "race"
	assert_bool(e.resolved(t).yellow_line).is_false()
	assert_bool(e.resolved(lined).yellow_line).is_true()
	e.track_limits = "off"
	assert_bool(e.resolved(lined).yellow_line).is_false()


func test_a_pass_on_the_apron_is_below_the_line() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = OVAL
	s.platform_id = "official.track.stock_car"
	s.event = RaceEvent.free_drive()
	s.event.fuel_x = 0
	s.event.tyre_x = 0
	s.ai_racers = 1
	s.ai_builtin_cars = true
	add_child(s)
	for i in 900:
		if s.racers.filter(func(r: Racer) -> bool: return r.vehicle != null).size() >= 2:
			break
		await get_tree().physics_frame
	s.event.yellow_line = true
	var me: Racer = s.players[0]
	var other: Racer = s.racers.filter(func(r: Racer) -> bool: return r != me)[0]
	other.driver.process_mode = Node.PROCESS_MODE_DISABLED # it stays where it's put
	var passes := []
	me.below_line.connect(func(n: int) -> void: passes.append(n))
	var t := s.track
	var back := t.start_m + t.length / 2.0 # the backstretch: the apron inside, pit road far away
	var apron := t.half_width(back, 1.0) + 3.0
	var put := func(r: Racer, d: float, lat: float, frames := 4) -> void:
		r.vehicle.reset_to(t.transform_at(d, lat))
		for i in frames:
			await get_tree().physics_frame
		r.vehicle.knocked_at = -INF # set down, not knocked
	var up_frames := ceili(Racer.YELLOW_UP_S * Engine.physics_ticks_per_second) + 4
	# Down on the apron behind the other car, along past it, and back up: one place. (A car is
	# free below the line for a while out of the pit lane, where free drive starts: long since.)
	await put.call(other, back + 20.0, 0.0)
	me._pit_left_at = -INF
	await put.call(me, back, apron)
	assert_bool(me.below).is_true()
	await put.call(me, back + 40.0, apron)
	assert_array(passes).is_empty()
	await put.call(me, back + 40.0, 0.0)
	assert_array(passes).is_empty() # not back up for long enough yet
	await put.call(me, back + 40.0, 0.0, up_frames)
	assert_bool(me.below).is_false()
	assert_array(passes).is_equal([1])
	# The same round a car that was just knocked: dodging it is no pass.
	await put.call(other, back + 80.0, 0.0)
	await put.call(me, back + 60.0, apron)
	await put.call(me, back + 100.0, apron)
	other.vehicle.knocked_at = Time.get_ticks_msec() / 1000.0
	await put.call(me, back + 100.0, 0.0, up_frames)
	assert_array(passes).is_equal([1])
	s.queue_free()
	await get_tree().physics_frame
