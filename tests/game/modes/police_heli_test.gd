extends GdUnitTestSuite
## The police helicopter (D251): only over a player at heat 5; it searches while they get away and
## flies off when they're evaded or busted; its searchlight shines only while lights are on; its
## strobe keeps to the flash rules; none on a dedicated server; a remote car flagged at heat 5
## gets one (CarState.FLAG_HELI, which round-trips); the HUD's sound arrows show it.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"


func before() -> void:
	Settings.use_folder("user://tests/police_heli")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
	var p := s.players[0]
	p.driver.set_physics_process(false)
	p.vehicle.throttle = 0.0
	s.police_heli.set_process(false) # updated by hand: its own look every LOOK_S would undo what a test sets
	return s


func test_only_over_a_player_at_heat_five_searching_and_leaving() -> void:
	var s := await _session()
	var hc := s.police_heli
	assert_object(hc).is_not_null()
	var p := s.players[0]
	var h := s.police.heat_of(p)
	h.points = Heat.LEVELS[3] # heat 4: none
	await _ticks(2)
	hc.update()
	assert_bool(hc.helis.is_empty()).is_true()
	h.points = Heat.LEVELS[4] # heat 5: one, coming in from ahead
	await _ticks(2)
	hc.update()
	assert_int(hc.helis.size()).is_equal(1)
	var heli: PoliceHeli = hc.helis[p]
	assert_object(heli.target).is_equal(p)
	assert_int(heli.state).is_equal(PoliceHeli.State.ARRIVE)
	assert_float(heli.global_position.y - p.vehicle.global_position.y).is_greater(PoliceHeli.HEIGHT_M)
	# It gets to its spot over the car and tracks it.
	for i in 60 * 20:
		await get_tree().process_frame
		if heli.state != PoliceHeli.State.ARRIVE:
			break
	assert_int(heli.state).is_equal(PoliceHeli.State.TRACK)
	var settle := heli._t + 4.0
	while heli._t < settle:
		await get_tree().process_frame
	# Ahead of the car, high up and to one side, where a chase camera sees it.
	var rel := heli.global_position - p.vehicle.global_position
	assert_float(rel.length()).is_less(85.0)
	assert_float(rel.dot(p.vehicle.global_basis.z)).is_greater(PoliceHeli.AHEAD_M * 0.6)
	# Getting away: it searches.
	heli.searching = true
	await _frames(2)
	assert_int(heli.state).is_equal(PoliceHeli.State.SEARCH)
	heli.searching = false
	await _frames(2)
	assert_int(heli.state).is_equal(PoliceHeli.State.TRACK)
	# Evaded (the heat's gone): it flies off, and is gone in time.
	h._clear()
	await _ticks(2)
	hc.update()
	assert_bool(hc.helis.is_empty()).is_true()
	assert_int(heli.state).is_equal(PoliceHeli.State.LEAVE)
	assert_bool(heli in hc.all()).is_true()
	var y := heli.global_position.y
	while heli._leave_t < 3.0:
		await get_tree().process_frame
	assert_float(heli.global_position.y).is_greater(y + 5.0)
	heli._leave_t = PoliceHeli.LEAVE_S
	await _frames(3)
	assert_bool(is_instance_valid(heli)).is_false()
	s.queue_free()
	await get_tree().process_frame


func test_searching_follows_the_evade_clock() -> void:
	var s := await _session()
	var p := s.players[0]
	s.police.set_physics_process(false) # its clock by hand
	var h := s.police.heat_of(p)
	h.points = Heat.LEVELS[4]
	assert_str(str(s.heat_state(p))).is_equal(str(Vector2i(5, 0)))
	h._hidden = 1.0
	assert_str(str(s.heat_state(p))).is_equal(str(Vector2i(5, 1)))
	s.police_heli.update()
	assert_bool((s.police_heli.helis[p] as PoliceHeli).searching).is_true()
	# Online, a highway client knows its players' heat from the server's news.
	s.police.heat.erase(p)
	s._on_highway_event({ "id": p.net_id, "kind": "heat", "level": 5, "evading": 0.0, "text": "" })
	assert_str(str(s.heat_state(p))).is_equal(str(Vector2i(5, 0)))
	s.queue_free()
	await get_tree().process_frame


func test_the_searchlight_shines_only_with_lights_on() -> void:
	var s := await _session()
	var p := s.players[0]
	s.police.heat_of(p).points = Heat.LEVELS[4]
	await _ticks(2)
	s.police_heli.update()
	var heli: PoliceHeli = s.police_heli.helis[p]
	s.env.set_process(false)
	s.env.set_physics_process(false)
	s.env.lights_on = false
	await _frames(3)
	assert_bool(heli.beam.visible).is_false()
	assert_bool(heli.spot.visible).is_false()
	s.env.lights_on = true
	await _frames(3)
	assert_bool(heli.beam.visible).is_true()
	assert_bool(heli.spot.visible).is_true()
	assert_bool(heli.spot.shadow_enabled).is_false()
	# Past the few nearest, only the beam.
	heli.real_light = false
	await _frames(2)
	assert_bool(heli.spot.visible).is_false()
	assert_bool(heli.beam.visible).is_true()
	s.queue_free()
	await get_tree().process_frame


func test_the_strobe_keeps_to_the_flash_rules() -> void:
	assert_int(Flash.most_per_second(func(t: float) -> float: return PoliceHeli.strobe_pattern(t, true))).is_equal(0)
	assert_int(Flash.most_per_second(func(t: float) -> float: return PoliceHeli.strobe_pattern(t, false))).is_between(1, 3)
	var heli := PoliceHeli.new()
	add_child(heli)
	assert_int(heli.strobe.layers).is_equal(1 << (Flash.LAYER_NORMAL - 1))
	assert_int(heli.calm_strobe.layers).is_equal(1 << (Flash.LAYER_CALM - 1))
	assert_object(heli.sound.stream).is_not_null()
	assert_float(heli.sound.stream.get_length()).is_equal_approx(PoliceHeli.SOUND_S, 0.01)
	heli.free()


func test_none_on_a_dedicated_server() -> void:
	var s := TrackSession.new()
	s.dedicated = true
	s._add_police_heli()
	assert_object(s.police_heli).is_null()
	s.free()


func test_a_remote_car_flagged_at_heat_five_gets_one() -> void:
	var st := CarState.new()
	st.id = 7
	st.flags = CarState.FLAG_HELI | CarState.FLAG_SEARCH | CarState.FLAG_BRAKE
	var bytes := PackedByteArray()
	bytes.resize(CarState.SIZE)
	st.encode(bytes, 0)
	assert_int(CarState.decode(bytes, 0).flags).is_equal(st.flags)
	var s := await _session()
	var r := NetRacer.new()
	r.net_id = 7
	r.is_human = true
	r.display_name = "Remote"
	r.spawn_at = s.track.transform_at(200.0, s.track.highway.lane_lateral(1, 1))
	s._add_racer(r)
	r.default_car = PoliceRacer.CAR
	r.load_net_car()
	for i in 600:
		if r.vehicle:
			break
		await get_tree().physics_frame
	assert_object(r.vehicle).is_not_null()
	r.vehicle.remote_state = st
	assert_str(str(s.heat_state(r))).is_equal(str(Vector2i(5, 1)))
	s.police_heli.update()
	assert_bool(s.police_heli.helis.has(r)).is_true()
	assert_bool((s.police_heli.helis[r] as PoliceHeli).searching).is_true()
	st.flags = 0
	s.police_heli.update()
	assert_bool(s.police_heli.helis.has(r)).is_false()
	s.queue_free()
	await get_tree().process_frame


func test_the_hud_arrows_show_it_out_of_view() -> void:
	var s := await _session()
	var p := s.players[0]
	s.police.heat_of(p).points = Heat.LEVELS[4]
	await _ticks(2)
	s.police_heli.update()
	var heli: PoliceHeli = s.police_heli.helis[p]
	heli.set_process(false)
	var cam := p.hud.camera
	heli.global_position = cam.global_position + cam.global_basis.z * 120.0 + Vector3.UP * 40.0 # behind the view
	p.hud._show_arrows = true
	p.hud._update_arrows()
	assert_int(p.hud._arrows.rotors.size()).is_equal(1)
	heli.global_position = cam.global_position - cam.global_basis.z * 100.0 # in front: in view
	p.hud._update_arrows()
	assert_int(p.hud._arrows.rotors.size()).is_equal(0)
	heli.global_position = cam.global_position + cam.global_basis.z * 400.0 # behind, too far
	p.hud._update_arrows()
	assert_int(p.hud._arrows.rotors.size()).is_equal(0)
	s.queue_free()
	await get_tree().process_frame
