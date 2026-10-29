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
	Settings.reset_keys(["traffic_off"]) # every car in traffic


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
	# Garage traffic (D191, D233): set 0 and the next of the host's cars that may be shared (up to
	# 12 a set), with the types they drive as.
	var garage: Dictionary = d.endless.garage
	assert_int(int(garage.k)).is_equal(0)
	var first: PackedInt32Array = garage.sets[0]
	assert_int(first.size()).is_equal(mini(Net.host_logic._host_hand.size(), EndlessGarage.ONLINE_MOST))
	assert_int(first.size()).is_greater(0)
	assert_bool(garage.sets.has(1)).is_true()
	var type_ids := EndlessTraffic.weighted_types().map(func(t: Dictionary) -> String: return String(t.id))
	for i: int in first:
		assert_bool(ContentStore.valid_hash(String(garage.cars[i].car))).is_true()
		assert_bool((garage.cars[i].fits as PackedStringArray).is_empty()).is_false()
		for id: String in garage.cars[i].fits:
			assert_bool(id in type_ids).is_true()
	# This game's own copy of the session has them too.
	assert_str(String(Net.session.environment.weather)).is_equal("changing")
	assert_float(float(Net.session.endless.t0)).is_equal(float(d.endless.t0))
	assert_object(Net.endless_garage).is_not_null()
	assert_array(Array(Net.endless_garage.sets[0])).is_equal(Array(first))
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
	# With the setting off, none.
	e.garage_traffic = false
	cfg.rotation = [{ "track": "anything", "class": "official.endless.cruiser", "event": e.to_dict() }]
	assert_int(Net.host(cfg, [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	Net.host_logic.start_session()
	assert_bool((Net.host_logic.session_dict().endless.garage as Dictionary).is_empty()).is_true()
	assert_object(Net.endless_garage).is_null()
	Net.leave()
	# With it on but every car switched out of traffic in the Garage (D222), none either.
	e.garage_traffic = true
	cfg.rotation = [{ "track": "anything", "class": "official.endless.cruiser", "event": e.to_dict() }]
	var ids := PackedStringArray()
	for path in PackageLoader.list_available():
		ids.append(String(PackageLoader.read_manifest(path).get("id", "")))
	GarageFiles.set_in_traffic(ids, false)
	assert_int(Net.host(cfg, [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	Net.host_logic.start_session()
	var none: Dictionary = Net.host_logic.session_dict().endless.garage
	assert_int((none.sets[0] as PackedInt32Array).size()).is_equal(0)
	Net.leave()
	Settings.reset_keys(["traffic_off"])
	Game.hold_events = false


func _garage_host(from := "host") -> NetHost:
	var cfg := ServerConfig.defaults()
	cfg.port = 47900 + randi() % 90
	cfg.upnp = false
	cfg.lan = false
	var e := RaceEvent.endless(4242, 2)
	e.endless_traffic = "heavy"
	e.garage_from = from
	cfg.rotation = [{ "track": "anything", "class": "official.endless.cruiser", "event": e.to_dict() }]
	Game.hold_events = true
	assert_int(Net.host(cfg, [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	Net.host_logic.start_session()
	return Net.host_logic


static func _hashes(from: int, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in n:
		out.append("sha256:%064x" % (from + i))
	return out


## Everyone (D233): the host's cars and each guest's take turns in a set, no car twice; a guest's
## count once the server has seen for itself that they fit; one that's gone is out of the next set.
func test_everyone_takes_turns_in_the_sets() -> void:
	var host := _garage_host("everyone")
	# Three of the host's own (made up), and a guest (peer 7) offering the built-in cars.
	host._host_hand = _hashes(100, 3)
	for h in host._host_hand:
		host._car_fits[h] = PackedStringArray(["saloon"])
	var built_in := {}
	for path in PackageLoader.list_available():
		if path.begins_with("res://content/cars/"):
			built_in[ContentIndex.package_hash(path)] = path
	for h: String in built_in:
		host._car_fits.erase(h) # as if only the guest had them
	var offer := [{ "car": "junk", "bytes": 1 }, { "car": _hashes(900, 1)[0], "bytes": 1 << 40 }]
	for h: String in built_in:
		offer.append({ "car": h, "bytes": 1000 })
		offer.append({ "car": h, "bytes": 1000 })
	host.handle(7, NetProtocol.Msg.TRAFFIC_CARS, { "cars": offer })
	assert_array(Array(host._offered[7])).contains_exactly_in_any_order(built_in.keys())
	# Looked at here (they're built in, so their data is): those that fit.
	var fit := Array(host._guest_hand(7))
	assert_int(fit.size()).is_greater(0)
	for h: String in fit:
		assert_array(Array(EndlessTraffic.fits_ids(built_in[h]))).is_equal(Array(host._car_fits[h]))
	# The guest connected: turns from the second hand (set 5: 5 % 2), the host's and the guest's in
	# turn, each car once.
	var info := NetServer.PeerInfo.new()
	info.connected = true
	host.server.peers[7] = info
	var dealt := Array(host._deal(5))
	host.server.peers.erase(7)
	var cars := dealt.map(func(i: int) -> String: return String(host.endless_garage.cars[i].car))
	assert_array(cars).contains_exactly_in_any_order(Array(host._host_hand) + fit)
	var sorted := dealt.duplicate()
	sorted.sort()
	assert_array(dealt).is_equal(sorted)
	# The guest gone: only the host's.
	var after := Array(host._deal(6)).map(func(i: int) -> String: return String(host.endless_garage.cars[i].car))
	assert_array(after).contains_exactly_in_any_order(Array(host._host_hand))
	# In Host, a guest's offer counts for nothing.
	Net.leave()
	host = _garage_host("host")
	host._host_hand = _hashes(100, 3)
	for h in host._host_hand:
		host._car_fits[h] = PackedStringArray(["saloon"])
	host.handle(7, NetProtocol.Msg.TRAFFIC_CARS, { "cars": offer })
	host.server.peers[7] = info
	var hosts := Array(host._deal(2)).map(func(i: int) -> String: return String(host.endless_garage.cars[i].car))
	host.server.peers.erase(7)
	assert_array(hosts).contains_exactly_in_any_order(Array(host._host_hand))
	Net.leave()
	Game.hold_events = false


## A swap (D233) reaches this game's own copy as every client's (the message through the local
## sink), and a late joiner's state with the swaps after it draws every slot from the same set.
func test_a_swap_reaches_every_game_and_a_late_joiner_alike() -> void:
	var host := _garage_host()
	var sink := host.local_sink
	var sent := []
	host.local_sink = func(type: int, d: Dictionary) -> void:
		if type == NetProtocol.Msg.ENDLESS_GARAGE:
			sent.append(bytes_to_var(var_to_bytes(d)))
		sink.call(type, d)
	var heard := []
	var count := func() -> void: heard.append(true)
	Net.endless_garage_changed.connect(count)
	host.endless_swap({ 0: PackedInt64Array([10, 40]) })
	host.endless_swap({ 0: PackedInt64Array([30, 90]), 1: PackedInt64Array([-5, 5]) })
	var late := EndlessGarage.from_dict(bytes_to_var(var_to_bytes(host.session_dict().endless.garage)))
	assert_int(late.set_of(0, 35)).is_equal(0) # pinned both times
	assert_int(late.set_of(0, 60)).is_equal(1) # pinned the second time
	assert_int(late.set_of(0, 120)).is_equal(2)
	host.endless_swap({ 1: PackedInt64Array([0, 3]) })
	assert_bool(late.apply(sent[-1])).is_true()
	assert_int(heard.size()).is_equal(3)
	assert_int(host.endless_garage.k).is_equal(3)
	for g: EndlessGarage in [Net.endless_garage, late]:
		assert_int(g.k).is_equal(3)
		for lane in 2:
			for j in range(-20, 200):
				assert_int(g.set_of(lane, j)).is_equal(host.endless_garage.set_of(lane, j))
	assert_int(host.endless_garage.set_of(0, 35)).is_equal(3) # not pinned the third time
	assert_int(host.endless_garage.set_of(1, 2)).is_equal(1)
	assert_int(host.endless_garage.set_of(1, 4)).is_equal(3)
	Net.endless_garage_changed.disconnect(count)
	Net.leave()
	Game.hold_events = false


## The slots a swap pins (D233) hold every car the traffic's schedule has within PIN_M of a player,
## and the biome a swap goes by is the one EndlessControl names there.
func test_a_swap_pins_every_car_near_a_player() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(31337, 2)
	s.event.endless_traffic = "heavy"
	s.event.lanes = 4
	s.autodrive = true
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle:
			break
		await get_tree().physics_frame
	var t: EndlessTraffic = s.endless_traffic
	t.clock = func() -> float: return 0.0 # the server's pins go by the traffic's clock (0 here)
	var en := EndlessNet.new()
	en.session = s
	var d := float(s.players[0].distance) + 400.0
	en.at = { 1: [d, 0.0, 0.0] }
	var pins := en.pinned()
	assert_int(pins.size()).is_equal(4)
	var near := 0
	for c: Dictionary in t.scheduled():
		if int(c.lane) == EndlessTraffic.PARKED or absf(float(c.s) - d) > EndlessGarage.PIN_M - 20.0:
			continue
		near += 1
		var p: PackedInt64Array = pins[int(c.lane)]
		var inside := false
		for i in range(0, p.size(), 2):
			inside = inside or (c.key.y >= p[i] and c.key.y <= p[i + 1])
		assert_bool(inside).override_failure_message("lane %d slot %d at %.0f m" % [c.lane, c.key.y, float(c.s) - d]).is_true()
	assert_int(near).is_greater(20)
	var road := s.endless_world.road
	var i := road.index_of(d)
	assert_int(en._biome_at(d)).is_equal(int(road.biome2[i]) if road.blend[i] >= 0.5 else int(road.biome[i]))
	en.free()
	s.queue_free()
	await get_tree().process_frame


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
