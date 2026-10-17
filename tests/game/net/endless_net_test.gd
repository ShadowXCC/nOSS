extends GdUnitTestSuite
## Endless roads online (D159): car positions go out as world millimetres wrapped to 32 bits, so
## games whose origins moved apart (each round its own players) still agree where a car is; a
## server passes states on as they came; the server rules who drives each traffic car (first to
## ask, then the next still asking), keeps slots used up, takes a game's word only for its own
## players, and checks the road chunks games made against its own; a joiner starts just behind
## the leader; Join takes a game's players anywhere along the road; and every game gets one sky,
## which an admin can change mid-session.


func before() -> void:
	Settings.use_folder("user://tests/endless_net")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _state(at: Vector3) -> CarState:
	var s := CarState.new()
	s.id = 7
	s.time = 12.5
	s.xform = Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)), at)
	s.velocity = Vector3(20.0, 0.0, -3.0)
	return s


func test_positions_go_out_as_world_millimetres() -> void:
	# Two games far out along a road (well past 2147 km, the 32-bit millimetre range), each with
	# its own origin (multiples of 1500 m), both near the same world point.
	var world := [3000123.456, 5.25, -4000007.5]
	var a := [3000000000, -4000500000] # mm
	var b := [3001500000, -3999000000]
	var s := _state(Vector3(world[0] - a[0] / 1000.0, world[1], world[2] - a[1] / 1000.0))
	var bytes := PackedByteArray()
	bytes.resize(CarState.SIZE)
	s.encode(bytes, 0, a[0], a[1])
	var got := CarState.decode(bytes, 0, 12.5, b[0], b[1])
	assert_float(got.xform.origin.x).is_equal_approx(world[0] - b[0] / 1000.0, 0.002)
	assert_float(got.xform.origin.y).is_equal_approx(5.25, 0.001)
	assert_float(got.xform.origin.z).is_equal_approx(world[2] - b[1] / 1000.0, 0.002)
	# A track event (no origin) writes millimetres as before.
	var t := _state(Vector3(12.345, 1.0, -7.0))
	t.encode(bytes, 0)
	assert_int(bytes.decode_s32(6)).is_equal(12345)
	assert_int(bytes.decode_s32(14)).is_equal(-7000)
	assert_int(CarState.wrap32(0x80000000)).is_equal(-0x80000000)
	assert_int(CarState.wrap32(-0x80000001)).is_equal(0x7FFFFFFF)


func test_a_server_passes_states_on_as_they_came() -> void:
	var bytes := PackedByteArray()
	bytes.resize(CarState.SIZE)
	_state(Vector3(120.0, 2.0, -40.0)).encode(bytes, 0, 1500000, 0)
	var s := CarState.decode(bytes, 0, 12.5)
	s.xform.origin += Vector3(-1500.0, 0.0, 0.0) # the server's origin moved since
	var again := PackedByteArray()
	again.resize(CarState.SIZE)
	s.encode(again, 0, 3000000, 0)
	assert_array(Array(again)).is_equal(Array(bytes))


func test_slots_have_network_ids() -> void:
	for key: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -3), Vector2i(1, -3), Vector2i(1, 123456)]:
		var slot := EndlessTraffic.slot_of(key)
		assert_object(EndlessTraffic.key_of(slot)).is_equal(key)
		var id := EndlessTraffic.car_id_of(slot)
		assert_int(id).is_between(NetProtocol.FIRST_TRAFFIC_ID, 65535)
	assert_int(EndlessTraffic.car_id_of(EndlessTraffic.slot_of(Vector2i(0, 5)))).is_not_equal(EndlessTraffic.car_id_of(EndlessTraffic.slot_of(Vector2i(1, 5))))


## A hosted server with one player of its own (peer 1) and a joined game's player (peer 2, faked).
func _host() -> Array:
	var cfg := ServerConfig.defaults()
	cfg.port = 47900 + randi() % 90
	cfg.upnp = false
	cfg.lan = false
	assert_int(Net.host(cfg, [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	var guest := NetPlayer.new()
	guest.id = 9
	guest.peer = 2
	guest.name = "Guest"
	Net.server.players[9] = guest
	var info := NetServer.PeerInfo.new()
	info.players = PackedInt32Array([9])
	Net.server.peers[2] = info
	var host_id: int = Net.server.players_of(1)[0].id
	var s := TrackSession.new()
	s.event = RaceEvent.endless(4242, 1)
	s.endless_world = EndlessWorld.new()
	s.endless_world.gen = EndlessGen.make(4242, 1)
	var en := EndlessNet.new()
	en.session = s
	return [en, host_id, s]


## A session never added to the tree, with the nodes it made for itself.
func _free_session(s: TrackSession) -> void:
	for n: Node in [s.views, s.field, s.race, s.endless_world]:
		if n:
			n.free()
	s.free()


func _report(want := [], drop := [], gone := [], at := {}, sums := {}) -> Dictionary:
	return { "want": PackedInt64Array(want), "drop": PackedInt64Array(drop), "gone": PackedInt64Array(gone), "at": at, "sums": sums }


func test_the_server_rules_who_drives_each_car() -> void:
	var h := _host()
	var en: EndlessNet = h[0]
	var host_id: int = h[1]
	# The guest asks first: it drives the car; the host asks too and waits its turn.
	en._on_report(2, _report([11]))
	en._on_report(1, _report([11]))
	assert_int(int(en.owners[11])).is_equal(9)
	assert_int(en.owner_of_car(EndlessTraffic.car_id_of(11))).is_equal(9)
	assert_bool(EndlessTraffic.car_id_of(11) in en.owned_cars()).is_true()
	# The guest lets it go: the host takes it over.
	en._on_report(2, _report([], [11]))
	assert_int(int(en.owners[11])).is_equal(host_id)
	assert_int(en.handovers).is_equal(1)
	# Nobody near any more: nobody drives it.
	en._on_report(1, _report([], [11]))
	assert_bool(en.owners.has(11)).is_false()
	assert_int(en.owner_of_car(EndlessTraffic.car_id_of(11))).is_equal(-1)
	# A slot used up is kept once.
	en._on_report(2, _report([], [], [21, 21]))
	en._on_report(1, _report([], [], [21]))
	assert_int(en._gone_order.size()).is_equal(1)
	# A game's word on where players are counts for its own players only.
	en._on_report(2, _report([], [], [], { 9: [5200.0, 22.0], host_id: [99999.0, 1.0] }))
	assert_float(en.distance_of(9)).is_equal_approx(5200.0, 0.01)
	assert_bool(en.at.has(host_id)).is_false()
	# Road chunks: the same as the server's pass; another doesn't.
	var c := en.session.endless_world.gen.chunk(3)
	en._on_report(2, _report([], [], [], {}, { 3: int(c.checksum), 4: 12345 }))
	assert_int(en.checked).is_equal(2)
	assert_int(en.mismatches).is_equal(1)
	# Junk is turned away.
	en._on_report(2, { "want": [1, 2], "drop": "x", "gone": null })
	assert_bool(en.owners.has(1)).is_false()
	Net.leave()
	en.free()
	_free_session(h[2])


func test_one_sky_and_one_road_for_everyone() -> void:
	var cfg := ServerConfig.defaults()
	cfg.port = 47900 + randi() % 90
	cfg.upnp = false
	cfg.lan = false
	var e := RaceEvent.endless(4242, 2)
	e.weather = "changing"
	cfg.rotation = [{ "track": "anything", "class": "official.endless.cruiser", "event": e.to_dict() }]
	Game.hold_events = true # no scene changes
	assert_int(Net.host(cfg, [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	Net.host_logic.start_session()
	var d := Net.host_logic.session_dict()
	assert_str(String(d.track)).is_equal(ServerConfig.ENDLESS)
	assert_str(Game.session_track(String(d.track))).is_equal(ServerConfig.ENDLESS)
	assert_str(String(d.track_name)).is_equal("Endless " + EndlessCode.encode(4242, 2))
	assert_str(String(d.environment.weather)).is_equal("changing")
	assert_int(int(d.environment.seed)).is_greater(0)
	assert_bool(d.endless.has("t0")).is_true()
	# This game's own copy of the session has them too.
	assert_str(String(Net.session.environment.weather)).is_equal("changing")
	assert_float(float(Net.session.endless.t0)).is_equal(float(d.endless.t0))
	# An admin changes the weather: every game hears, and joiners get it.
	var heard := []
	Net.env_changed.connect(func(env: Dictionary) -> void: heard.append(env))
	Net.host_logic.admin(1, "weather", "Rain")
	Net.host_logic.admin(1, "time", "teatime") # not a time: nothing changes
	assert_int(heard.size()).is_equal(1)
	assert_str(String(heard[0].weather)).is_equal("rain")
	assert_int(int(heard[0].seed)).is_equal(int(d.environment.seed))
	assert_str(String(Net.host_logic.session_dict().environment.weather)).is_equal("rain")
	Net.leave()
	Game.hold_events = false


func test_a_joiner_starts_behind_the_leader() -> void:
	var s := TrackSession.new()
	s.event = RaceEvent.endless(4242, 1)
	assert_float(s._endless_start()).is_equal(EndlessControl.START_M)
	s.online = { "endless": { "t0": 0.0, "at": { 3: [52000.0, 10.0, 25.0], 4: [8000.0, 10.0, 25.0], 5: ["junk"] } } }
	assert_float(s._endless_start()).is_equal(52000.0 - EndlessControl.JOIN_BEHIND_M)
	s.dedicated = true # the server stays at the start
	assert_float(s._endless_start()).is_equal(EndlessControl.START_M)
	# In single file behind the leader (this game's players one behind another).
	assert_int(s._endless_file_index(3, 4)).is_equal(0)
	_free_session(s)


func test_players_start_apart_at_the_start() -> void:
	# Every game's first player is its own player 0: the roster keeps them apart (one game's car
	# landed on the other's in a LAN test).
	var s := TrackSession.new()
	s.event = RaceEvent.endless(4242, 1)
	s.online = { "endless": { "t0": 0.0, "at": {} } }
	assert_int(s._endless_file_index(7, 0)).is_equal(0)
	assert_int(s._endless_file_index(9, 1)).is_equal(1)
	assert_int(s._endless_file_index(12, 2)).is_equal(2)
	_free_session(s)


func test_join_takes_players_far_along_the_road() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(4242, 1)
	s.event.endless_traffic = "off"
	s.autodrive = true
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle:
			break
		await get_tree().physics_frame
	var p := s.players[0]
	s.endless.move_to(60000.0, 20.0)
	for i in 30:
		await get_tree().physics_frame
	# The origin went with them: the car is near the scene's centre, on the road 60 km along.
	assert_float(Vector2(s.origin.x, s.origin.z).length()).is_greater(20000.0)
	assert_float(Vector2(p.vehicle.global_position.x, p.vehicle.global_position.z).length()).is_less(FloatingOrigin.SHIFT_AT_M + 500.0)
	assert_float(p.distance).is_between(60000.0, 60060.0)
	assert_float(absf(p.lateral)).is_less(4.0)
	assert_bool(s.endless_world.built_at(p.distance)).is_true()
	# Where the road is in the world here is where the generator says it is.
	var c := s.endless_world.gen.chunk(floori(p.distance / (TrackData.SAMPLE_M * NossRoadGen.chunk_samples())))
	var w := s.origin.to_world(s.track.point_at(float(c.first) * TrackData.SAMPLE_M))
	assert_float(w[0]).is_equal_approx(float(c.x[0]), 0.01)
	assert_float(w[2]).is_equal_approx(float(c.z[0]), 0.01)
	s.queue_free()
	await get_tree().process_frame
