extends GdUnitTestSuite
## Garage cars in highway traffic online (D239): the server deals one set (up to 12, the host's or
## everyone's in turn) for the whole session, shuffled by the session's traffic seed, and sends it
## in SESSION's `highway`; every game picks the same car for each traffic car from it, and a car
## whose files aren't here yet drives as a stock car in its paint.


func before() -> void:
	Settings.use_folder("user://tests/highway_garage_net")
	Settings.reset_keys(["traffic_off"]) # every car in traffic


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _host(e: RaceEvent) -> NetHost:
	var cfg := ServerConfig.defaults()
	cfg.port = 47900 + randi() % 90
	cfg.upnp = false
	cfg.lan = false
	cfg.rotation = [{ "track": "lumen_ring", "class": "official.highway.street", "event": e.to_dict() }]
	Game.hold_events = true # no scene changes
	assert_int(Net.host(cfg, [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	Net.host_logic.start_session()
	return Net.host_logic


static func _hashes(from: int, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in n:
		out.append("sha256:%064x" % (from + i))
	return out


func test_hosting_a_highway_sends_one_set() -> void:
	var host := _host(RaceEvent.highway("cruise", false, 650))
	var d := host.session_dict()
	assert_int(int(d.highway.count)).is_equal(650)
	assert_int(int(Net.session.highway.count)).is_equal(650) # not clamped on the way (D238)
	var garage: Dictionary = d.highway.garage
	assert_int(int(garage.k)).is_equal(0)
	assert_bool(garage.sets.has(1)).is_false() # one set, never swapped
	var first: PackedInt32Array = garage.sets[0]
	assert_int(first.size()).is_greater(0)
	assert_int(first.size()).is_equal(mini(host._host_hand.size(), EndlessGarage.ONLINE_MOST))
	var type_ids := EndlessTraffic.weighted_types().map(func(t: Dictionary) -> String: return String(t.id))
	for i: int in first:
		assert_bool(ContentStore.valid_hash(String(garage.cars[i].car))).is_true()
		for id: String in garage.cars[i].fits:
			assert_bool(id in type_ids).is_true()
	# Shuffled by the session's traffic seed (a highway event has no road seed).
	assert_int(host._garage_seed()).is_equal(int(host._highway.seed))
	# This game's own copy has it.
	assert_object(Net.endless_garage).is_not_null()
	assert_array(Array(Net.endless_garage.sets[0])).is_equal(Array(first))
	Net.leave()
	# Off, or no traffic: none.
	var off := RaceEvent.highway("cruise", false, 250)
	off.garage_traffic = false
	host = _host(off)
	assert_bool((host.session_dict().highway.garage as Dictionary).is_empty()).is_true()
	assert_object(Net.endless_garage).is_null()
	Net.leave()
	host = _host(RaceEvent.highway("cruise", false, 0))
	assert_bool((host.session_dict().highway.garage as Dictionary).is_empty()).is_true()
	Net.leave()
	Game.hold_events = false


func test_a_guests_cars_are_shuffled_by_the_traffic_seed() -> void:
	var e := RaceEvent.highway("cruise", false, 250)
	e.garage_from = "everyone"
	var host := _host(e)
	var offered := _hashes(500, 30)
	host._offered[7] = offered
	for h in offered:
		host._car_fits[h] = PackedStringArray(["saloon"])
	host._highway.seed = 11
	var a := host._guest_hand(7)
	host._highway.seed = 12
	var b := host._guest_hand(7)
	assert_array(Array(a)).contains_exactly_in_any_order(Array(offered))
	assert_array(Array(b)).contains_exactly_in_any_order(Array(offered))
	assert_bool(a == b).is_false()
	# Everyone: the host's and the guest's in turn, each car once, 12 at most.
	host._host_hand = _hashes(100, 3)
	for h in host._host_hand:
		host._car_fits[h] = PackedStringArray(["hatch"])
	var info := NetServer.PeerInfo.new()
	info.connected = true
	host.server.peers[7] = info
	var dealt := Array(host._deal(0)).map(func(i: int) -> String: return String(host.endless_garage.cars[i].car))
	host.server.peers.erase(7)
	assert_int(dealt.size()).is_equal(EndlessGarage.ONLINE_MOST)
	for h in host._host_hand:
		assert_bool(h in dealt).is_true()
	var once := {}
	for h: String in dealt:
		once[h] = true
	assert_int(once.size()).is_equal(dealt.size())
	Net.leave()
	Game.hold_events = false


func test_every_game_picks_the_same_from_the_set() -> void:
	var pkg := TrackLoader.load_package("res://content/tracks/lumen_ring", {}, { "terrain": false })
	var sets := EndlessGarage.new()
	for i in 12:
		sets.cars[i] = { "car": "sha256:%064x" % (i + 1), "fits": PackedStringArray(["hatch", "saloon", "suv"] if i % 3 else ["van"]) }
	sets.sets[0] = PackedInt32Array(range(12))
	var games: Array[TrafficManager] = []
	for i in 2:
		var tm := TrafficManager.new()
		assert_bool(tm.setup(pkg.track, 99, 650)).is_true()
		tm.use_garage(EndlessGarage.from_dict(sets.to_dict()))
		games.append(tm)
	assert_str(games[0].picks_check()).is_equal(games[1].picks_check())
	var picked := 0
	var vans := 0
	for car in 650:
		var g := games[0].garage_of(car)
		assert_int(g).is_equal(games[1].garage_of(car))
		if g < 0:
			continue
		picked += 1
		var type := int(games[0].sim.car(car).type)
		assert_bool(type in games[0].models.cars[g].fits).is_true()
		vans += int(TrafficTypes.list()[type].id == "van")
		# Its files aren't here: a stock car in its stock paint.
		assert_bool(games[0].models.has_paint(g)).is_false()
		var colors := TrafficTypes.colors(type)
		assert_object(games[0]._color_of(car)).is_equal(colors[int(games[0].sim.car(car).color) % colors.size()])
	assert_int(picked).is_greater(300)
	assert_int(vans).is_greater(0)
	for tm in games:
		tm.free()
