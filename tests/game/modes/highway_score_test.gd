extends GdUnitTestSuite
## Score attack in a session (acceptance 2: "a score attack combo banks and loses as specified"):
## the player's car rolls past lane cars placed beside it, and the points come from where they
## really were: a near miss at 180 km/h (×1.5), a close miss, the chain banking after 5 quiet
## seconds, and a knock into a car losing what isn't banked.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"


func before() -> void:
	Settings.use_folder("user://tests/highway_score")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session() -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.highway.street"
	s.event = RaceEvent.highway("score", false, 20)
	s.traffic_seed = 3
	add_child(s)
	s.traffic.cap = 0 # every car stays a lane car (the near-miss rows come from the lane sim)
	return s


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## The player on direction 1's lane 1 at main distance `d`, `offset` m towards lane 0, at `v`.
func _place_player(s: TrackSession, d: float, offset: float, v: float) -> void:
	var h := s.track.highway
	var at := s.track.transform_at(d, h.lane_lateral(1, 1) - offset)
	s.players[0].vehicle.reset_to(at, at.basis.z * v)


## How far towards lane 0 the player goes to pass lane car `car` with `gap` m between hulls.
func _offset_for(s: TrackSession, car: int, gap: float) -> float:
	var t: Dictionary = TrafficTypes.list()[int(s.traffic.sim.car(car).type)]
	var half := s.players[0].vehicle.fitted.envelope.size.x / 2.0 + float(t.width_m) / 2.0
	return s.track.highway.lane_m - (half + gap)


## Lane car `car` on direction 1's lane 0 at main distance `d`, at `v`.
func _place_car(s: TrackSession, car: int, d: float, v: float) -> void:
	var h := s.track.highway
	var p := s.track.transform_at(d, h.lane_lateral(1, 0)).origin
	var at := s.traffic.sim.locate(p)
	s.traffic.sim.place(car, int(at.lane), float(at.s), v)


func test_misses_bank_and_a_knock_loses() -> void:
	var s := _session()
	for i in 600:
		if not s.players.is_empty() and s.players[0].vehicle:
			break
		await get_tree().physics_frame
	var p := s.players[0]
	p.driver.set_physics_process(false) # nobody steers: it rolls straight
	var tm := s.traffic
	var score := s.get_node(^"HighwayScore") as HighwayScore
	assert_object(score).is_not_null()
	# Everyone else well out of the way.
	for car in tm.sim.get_count():
		_place_car(s, car, 1200.0 + car * 60.0, 25.0)
	var south := float(s.track.project(Vector3(0, 0, -400)).distance)
	# A near miss: 0.85 m between hulls (a car's width less than a lane over), passed at 180 km/h.
	_place_car(s, 0, south - 230.0, 25.0)
	_place_player(s, south - 260.0, _offset_for(s, 0, 0.8), 50.0)
	await _ticks(300)
	var rules := score.rules_for(p)
	assert_int(rules.combo).is_equal(1)
	assert_int(rules.chain).is_equal(150)
	# A close one (0.35 m) within the combo's window: 200 × 1.5, the combo ×1.25.
	var d := float(p.distance)
	_place_car(s, 1, d + 30.0, 25.0)
	_place_player(s, d, _offset_for(s, 1, 0.3), 50.0)
	await _ticks(300)
	assert_int(rules.combo).is_equal(2)
	assert_int(rules.chain).is_equal(450)
	assert_int(rules.unbanked()).is_equal(563)
	# Five quiet seconds: it banks.
	_place_player(s, float(p.distance), 0.0, 30.0)
	await _ticks(5 * 120 + 30)
	assert_int(rules.banked).is_equal(563)
	assert_int(rules.combo).is_equal(0)
	# Another near miss, then straight into a slow car in its own lane: the chain is lost.
	d = float(p.distance)
	_place_car(s, 2, d + 30.0, 25.0)
	_place_player(s, d, _offset_for(s, 2, 0.8), 50.0)
	await _ticks(300)
	assert_int(rules.combo).is_equal(1)
	d = float(p.distance)
	var h := s.track.highway
	var ahead := s.track.transform_at(d + 40.0, h.lane_lateral(1, 1)).origin
	var at := tm.sim.locate(ahead)
	tm.sim.place(3, int(at.lane), float(at.s), 2.0)
	_place_player(s, d, 0.0, 40.0)
	await _ticks(240)
	# Under 5 s since that near miss: only the knock could have taken it.
	assert_int(rules.unbanked()).is_equal(0)
	assert_int(rules.combo).is_equal(0)
	assert_int(rules.banked).is_equal(563)
	s.queue_free()
	await get_tree().process_frame
