extends GdUnitTestSuite
## Spike strips (D192): a wheel over one goes flat, one through the half lane left open doesn't;
## a reset puts the tyres back, and they come back up on their own after a while; strips come
## from heat level 3 and are taken up once the player is well past.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"


func before() -> void:
	Settings.use_folder("user://tests/spike_strip")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _session() -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.highway.super"
	s.event = RaceEvent.highway("cruise", true, 0)
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle and s.police and s.police._placed:
			break
		await get_tree().physics_frame
	return s


## The player rolls at 20 m/s down lateral `lat`, over where a strip lies 60 m on.
func _drive_over(s: TrackSession, lat: float) -> int:
	var p := s.players[0]
	var pc := s.police
	p.driver.set_physics_process(false)
	p.vehicle.repair()
	var h := s.track.highway
	var d := 300.0
	var strip := pc.lay_spikes(p, d + 60.0)
	var at := s.track.transform_at(d, lat)
	p.vehicle.reset_to(at, at.basis.z * 20.0)
	p.vehicle.throttle = 0.3
	await _ticks(int(120 * 4.5))
	pc.strips.erase(strip)
	strip.queue_free()
	return p.vehicle.flats


func test_over_the_strip_flat_through_the_gap_not() -> void:
	var s := await _session()
	var h := s.track.highway
	var span := s.police.road.strip_span(1, 360.0)
	# Its middle lane: over the strip.
	assert_int(await _drive_over(s, h.lane_lateral(1, 1))).is_not_equal(0)
	# The half lane left open at the outer edge.
	var gap := -(h.inner + (h.lanes - 0.25) * h.lane_m)
	assert_float(gap).is_less(span.x)
	assert_int(await _drive_over(s, gap)).is_equal(0)
	s.queue_free()
	await get_tree().process_frame


func test_a_reset_mends_the_tyres_and_they_mend_themselves_in_time() -> void:
	var s := await _session()
	var p := s.players[0]
	p.driver.set_physics_process(false)
	p.vehicle.flatten(0b0101)
	assert_int(p.vehicle.sim.get_flats()).is_equal(0b0101)
	p.reset_car()
	assert_int(p.vehicle.flats).is_equal(0)
	assert_int(p.vehicle.sim.get_flats()).is_equal(0)
	# Left alone, back up after their time.
	assert_float(SpikeStrip.FLAT_S).is_equal(30.0)
	p.vehicle.flatten(0b0011, 0.5)
	await _ticks(30)
	assert_int(p.vehicle.flats).is_equal(0b0011)
	await _ticks(60)
	assert_int(p.vehicle.flats).is_equal(0)
	s.queue_free()
	await get_tree().process_frame


func test_strips_come_with_heat_three_and_go_once_passed() -> void:
	var s := await _session()
	var pc := s.police
	var p := s.players[0]
	p.driver.set_physics_process(false)
	pc.set_physics_process(false) # its clock and its strips by hand
	# At the start of the ring's first straight, going along it.
	var at := s.track.transform_at(0.0, s.track.highway.lane_lateral(1, 1))
	p.vehicle.reset_to(at)
	p.distance = 0.0
	var h := pc.heat_of(p)
	h.points = Heat.LEVELS[1] # level 2: none, however long
	for i in 10:
		pc._clock += 10.0
		pc._spikes()
	assert_int(pc.spikes_laid).is_equal(0)
	h.points = Heat.LEVELS[2] # level 3: the first half its time on, the next its time after
	pc._spikes()
	assert_int(pc.spikes_laid).is_equal(0)
	pc._clock += PoliceTuning.at(3).spikes_s * 0.5 + 0.1
	pc._spikes()
	assert_int(pc.spikes_laid).is_equal(1)
	pc._clock += 1.0
	pc._spikes()
	assert_int(pc.spikes_laid).is_equal(1)
	var strip: SpikeStrip = pc.strips[0]
	assert_float(pc.road.delta_m(strip.at_m, p.distance)).is_between(PoliceControl.SPIKES_FROM_M, PoliceControl.SPIKES_TO_M)
	assert_bool(pc.road.straight_clear(strip.at_m - 40.0, 1, 80.0)).is_true()
	# Taken up once they're past.
	p.distance = strip.at_m + SpikeStrip.PAST_M + 30.0
	pc._spikes()
	assert_bool(strip in pc.strips).is_false()
	s.queue_free()
	await get_tree().process_frame
