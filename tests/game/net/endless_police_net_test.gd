extends GdUnitTestSuite
## Endless police online (D195): each game runs its own units, with ids that name the game (its
## first player's car id), clear of every other range; the server takes a unit's states only from
## its own game and never checks them like a player's car; a game's strips, closures and the
## patrols it turned into units reach every other game, checked on the way.


func before() -> void:
	Settings.use_folder("user://tests/endless_police_net")


func after() -> void:
	Players.clear()
	Net.leave()
	Settings.use_folder("user://")


func test_police_ids_name_their_game_and_meet_nothing_else() -> void:
	var seen := {}
	for base in range(1, NetProtocol.FIRST_AI_ID):
		for k in NetProtocol.POLICE_PER_GAME:
			var id := NetProtocol.endless_police_id(base, k)
			assert_bool(NetProtocol.is_endless_police(id)).is_true()
			assert_int(NetProtocol.police_base(id)).is_equal(base)
			assert_bool(seen.has(id)).is_false()
			seen[id] = true
			assert_int(id).is_less(65536) # CarState ids are 16 bits
			assert_int(id).is_greater_equal(NetProtocol.FIRST_TRAFFIC_ID + EndlessTraffic.TRAFFIC_IDS) # above every traffic id
	# Nothing else is taken for it.
	for id: int in [1, 150, NetProtocol.FIRST_AI_ID, NetProtocol.FIRST_POLICE_ID, NetProtocol.FIRST_TRAFFIC_ID,
			EndlessTraffic.car_id_of(EndlessTraffic.slot_of(Vector2i(3, 999999))), NetProtocol.FIRST_TRAFFIC_ID + EndlessTraffic.TRAFFIC_IDS - 1]:
		assert_bool(NetProtocol.is_endless_police(id)).is_false()
	assert_int(EndlessPoliceRoad.CHASE_UNITS + PoliceControl.AHEAD_UNITS).is_less_equal(NetProtocol.POLICE_PER_GAME)


## A hosted endless session (not run): the host's player, and a guest's game on peer 2.
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
	var s := TrackSession.new()
	s.event = RaceEvent.endless(4242, 1)
	var ns := NetSession.new()
	ns.session = s
	return [ns, s]


func test_a_units_states_come_only_from_its_game() -> void:
	var h := _host()
	var ns: NetSession = h[0]
	var host_id: int = Net.server.players_of(1)[0].id
	var guests := NetProtocol.endless_police_id(9, 2)
	var hosts := NetProtocol.endless_police_id(host_id, 0)
	assert_int(ns._peer_of(guests)).is_equal(2)
	assert_int(ns._peer_of(hosts)).is_equal(1)
	assert_bool(ns._owned_by(guests, 2)).is_true()
	assert_bool(ns._owned_by(hosts, 2)).is_false() # the guest can't speak for the host's police
	assert_bool(ns._owned_by(NetProtocol.endless_police_id(77, 0), 2)).is_false() # nobody's
	ns.free()
	(h[1] as TrackSession).free()
	Net.leave()


func test_police_events_are_checked_on_the_way() -> void:
	var ok := EndlessNet._checked_police({
		"strips": [[5200.0, -3.5, 0.0], [NAN, 0.0, 1.0], [10.0, 0.0, 99.0], "junk"],
		"closures": [[3, 5000.0, 5060.0, 0, -1], [4, 5000.0, 9000.0, 0, 2], [5, 1.0, 2.0, 7, -1]],
		"opened": [3, "x"],
	})
	assert_int((ok.strips as Array).size()).is_equal(1)
	assert_int((ok.closures as Array).size()).is_equal(1)
	assert_array(ok.opened).is_equal([3])
	assert_bool(EndlessNet._checked_police("nope").is_empty()).is_true()


## Two games' police meet: game A's strip and roadblock reach game B's road and traffic, and open
## again when A opens them.
func test_another_games_strips_and_roadblocks_come_through() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(4242, 1)
	s.event.endless_traffic = "normal"
	s.event.police = true
	s.autodrive = true
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle and s.police and s.police._placed:
			break
		await get_tree().physics_frame
	var en := EndlessNet.new()
	en.session = s
	en.traffic = s.endless_traffic
	var d := s.players[0].distance
	en._apply_police(9, { "strips": [[d + 300.0, -3.5, 0.0]], "closures": [[4, d + 500.0, d + 560.0, 0, -1]] })
	assert_int(s.police.strips.size()).is_equal(1)
	var strip: SpikeStrip = s.police.strips[0]
	assert_object(strip.for_racer).is_null()
	assert_bool(s.players[0] in strip.watch).is_true()
	assert_int(s.endless_traffic.closures.size()).is_equal(1)
	assert_float(s.endless_traffic.closed_ahead(0, d + 480.0, 40.0)).is_equal_approx(20.0, 0.01)
	en._apply_police(9, { "opened": [4] })
	assert_int(s.endless_traffic.closures.size()).is_equal(0)
	# This game's own go out with its next report.
	en.police_event("strips", [d + 300.0, -3.5, 0.0])
	assert_int((en._police.strips as Array).size()).is_equal(1)
	en.free()
	s.queue_free()
	await get_tree().process_frame


## A patrol turned into a unit is used up on every game (its slot is reported gone).
func test_a_converted_patrol_is_gone_everywhere() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(4242, 1)
	s.event.endless_traffic = "off"
	s.event.speed_traps = true
	s.event.police = true
	s.autodrive = true
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle:
			break
		await get_tree().physics_frame
	var en := EndlessNet.new()
	en.session = s
	s.endless_traffic.net = en
	s.endless_traffic.retire(Vector2i(EndlessTraffic.PARKED, 42))
	assert_bool(en._gone.has(EndlessTraffic.slot_of(Vector2i(EndlessTraffic.PARKED, 42)))).is_true()
	s.endless_traffic.net = null
	en.free()
	s.queue_free()
	await get_tree().process_frame
