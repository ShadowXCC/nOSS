extends GdUnitTestSuite
## Police v1 (D115, MODE-04) in a session: a unit parked at each speed trap; speeding past one
## gives heat and brings units after you, sirens on; slow with a unit on you for 3 s is busted
## (the unbanked score goes, back to the shoulder); out of sight and far long enough, evaded.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"


func before() -> void:
	Settings.use_folder("user://tests/police")


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
	s.event = RaceEvent.highway("score", true, 0)
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle and s.police and s.police._placed:
			break
		await get_tree().physics_frame
	return s


func test_a_trap_sees_speeding_and_units_give_chase() -> void:
	var s := await _session()
	var pc := s.police
	assert_object(pc).is_not_null()
	var traps: Array = s.track.highway.traps
	assert_int(pc.units.size()).is_equal(traps.size() + PoliceControl.CHASE_UNITS)
	# The trap units sit at their traps; the rest wait out of play.
	var trap_unit := pc.units[0]
	assert_bool(trap_unit.waiting).is_false()
	assert_float(trap_unit.vehicle.global_position.distance_to(pc._trap_spot(traps[0]).origin)).is_less(3.0)
	assert_bool(pc.units[traps.size()].waiting).is_true()
	# The player flies past trap 0 (direction 1) at 60 m/s: seen speeding.
	var p := s.players[0]
	p.driver.set_physics_process(false)
	var trap: Dictionary = traps[0]
	var start := s.track.transform_at(float(trap.at_m) - 150.0, s.track.highway.lane_lateral(1, 1))
	p.vehicle.reset_to(start, start.basis.z * 60.0)
	p.vehicle.throttle = 1.0
	await _ticks(120 * 4)
	var h := pc.heat_of(p)
	assert_int(h.level()).is_greater(0)
	var chasing := pc.units.filter(func(u: PoliceRacer) -> bool: return u.ai.target == p)
	assert_int(chasing.size()).is_equal(h.level())
	assert_bool(chasing.all(func(u: PoliceRacer) -> bool: return u.vehicle.siren and u.vehicle.light_bar)).is_true()
	assert_int(pc.pursuits).is_equal(1)
	assert_object(p.hud.get_node_or_null(^"HeatPanel")).is_not_null()
	s.queue_free()
	await get_tree().process_frame


func test_busted_when_slow_with_a_unit_alongside() -> void:
	var s := await _session()
	var pc := s.police
	var p := s.players[0]
	p.driver.set_physics_process(false)
	var h := pc.heat_of(p)
	h.points = 6
	var score := s.get_node(^"HighwayScore") as HighwayScore
	score.rules_for(p).chain = 500
	score.rules_for(p).combo = 2
	score.rules_for(p).last_event = INF # not banking
	# The player stopped; a unit stopped right behind, touching.
	var at := s.track.transform_at(300.0, s.track.highway.lane_lateral(1, 1))
	p.vehicle.reset_to(at)
	var u := pc.units[pc.units.size() - 1]
	u.deploy(Transform3D(at.basis, at.origin - at.basis.z * 4.6), Vector3.ZERO)
	u.ai.mode = PoliceAI.Mode.PARKED
	await _ticks(120 * 4)
	assert_int(pc.busts).is_equal(1)
	assert_int(h.level()).is_equal(0)
	assert_int(score.rules_for(p).unbanked()).is_equal(0)
	s.queue_free()
	await get_tree().process_frame


func test_evaded_out_of_sight_and_far() -> void:
	var s := await _session()
	var pc := s.police
	var p := s.players[0]
	p.driver.set_physics_process(false)
	var h := pc.heat_of(p)
	h.points = 1 # level 1: 12 s
	# Far from every unit (the trap units too): on the far side of the ring from them, at rest.
	var far := s.track.transform_at(fposmod(float(s.track.highway.traps[0].at_m) + s.track.length / 2.0, s.track.length) + 300.0,
		s.track.highway.lane_lateral(1, 1))
	p.vehicle.reset_to(far)
	# Every chase unit parked out of sight beyond EVADE_M (but near enough not to stand down, so
	# none is free to send in): the police have lost them.
	var d := float(s.track.project(far.origin).distance)
	var k := 0
	for u in pc.units:
		if pc._trap_units.has(u):
			continue
		var spot := s.track.transform_at(d - 360.0 - k * 15.0, s.track.highway.lane_lateral(1, k % 3))
		u.deploy(spot, Vector3.ZERO)
		u.ai.target = null
		u.ai.mode = PoliceAI.Mode.PARKED
		k += 1
	await _ticks(120 * 14)
	assert_int(pc.evades).is_equal(1)
	assert_int(h.level()).is_equal(0)
	s.queue_free()
	await get_tree().process_frame


func test_units_close_in_and_heat_four_brings_a_roadblock() -> void:
	var s := await _session()
	var pc := s.police
	var p := s.players[0]
	var h := pc.heat_of(p)
	h.points = 30 # level 4
	await _ticks(10)
	# The ones sent in from the pool (a trap unit nearby may join too).
	var chasing := pc.units.filter(func(u: PoliceRacer) -> bool: return u.ai.target == p and not pc._trap_units.has(u))
	assert_int(chasing.size()).is_greater(0)
	var u: PoliceRacer = chasing[0]
	var gap := u.vehicle.global_position.distance_to(p.vehicle.global_position)
	assert_float(gap).is_greater(PoliceControl.SEND_BEHIND_M - 50.0) # sent in out of sight
	# A roadblock ahead: every lane but the outer one closed, two units parked across.
	assert_bool(pc._blocks.has(p)).is_true()
	var b: Dictionary = pc._blocks[p]
	assert_int((b.closures as Array).size()).is_equal(s.track.highway.lanes - 1) # all but the outer lane
	assert_int((b.units as Array).size()).is_equal(2)
	assert_int(pc.roadblocks).is_equal(1)
	# The chasing unit closes in on the autodriven player.
	await _ticks(120 * 8)
	assert_float(u.vehicle.global_position.distance_to(p.vehicle.global_position)).is_less(gap - 100.0)
	s.queue_free()
	await get_tree().process_frame
