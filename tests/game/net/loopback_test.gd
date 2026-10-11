extends GdUnitTestSuite
## A real server and clients over ENet on 127.0.0.1, in one process and polled by hand (D78, D81):
## joining, player ids, the join checks, kicks and bans.

var port := 0
var server: NetServer
var clients: Array[NetClient] = []


func before() -> void:
	Settings.use_folder("user://tests/net_loopback")


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	port = 47900 + randi() % 90
	clients.clear()


func after_test() -> void:
	for c in clients:
		c.leave()
		c.free()
	clients.clear()
	if server:
		server.stop()
		server.free()
		server = null


func _start(cfg := ServerConfig.defaults(), local := []) -> NetServer:
	cfg.port = port
	server = NetServer.new()
	server.manual_poll = true
	add_child(server)
	assert_int(server.start(cfg, NetIdentity.throwaway(), local)).is_equal(OK)
	return server


func _client(names := ["Ann"], password := "", ident: NetIdentity = null) -> NetClient:
	var c := NetClient.new()
	c.manual_poll = true
	add_child(c)
	clients.append(c)
	var players := []
	for n: String in names:
		players.append({ "name": n, "color": "ff0000" })
	assert_int(c.join("127.0.0.1", port, players, password, ident if ident else NetIdentity.throwaway())).is_equal(OK)
	return c


## Polls everything until `done` is true or 3 s pass.
func _pump(done: Callable, seconds := 3.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if server:
			server.poll()
		for c in clients:
			c.poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func _result(c: NetClient) -> Dictionary:
	var out := { "reason": "", "joined": false }
	c.joined.connect(func(_info: Dictionary) -> void: out.joined = true)
	c.failed.connect(func(reason: String) -> void: out.reason = reason)
	c.left.connect(func(reason: String) -> void: out.reason = reason)
	return out


func test_clients_join_with_their_players() -> void:
	_start(ServerConfig.defaults(), [{ "name": "Host", "color": "00ff00" }])
	var joins := []
	server.peer_joined.connect(func(peer: int) -> void: joins.append(peer))
	var a := _client(["Ann"])
	var b := _client(["Bo", "Cy", "Di"])
	var ra := _result(a)
	var rb := _result(b)
	assert_bool(_pump(func() -> bool: return ra.joined and rb.joined and joins.size() == 2)).is_true()
	assert_int(server.player_count()).is_equal(5)
	assert_int(a.player_ids().size()).is_equal(1)
	assert_int(b.player_ids().size()).is_equal(3)
	var names := []
	for p: NetPlayer in server.players.values():
		names.append(p.name)
	assert_array(names).contains_exactly_in_any_order(["Host", "Ann", "Bo", "Cy", "Di"])
	var ids := Array(a.player_ids()) + Array(b.player_ids())
	assert_int(ids.size()).is_equal(4)
	assert_bool(server.players.has(ids[0]) and server.players[ids[0]].peer != 1).is_true()
	assert_bool(server.is_admin(1)).is_true()
	assert_bool(server.is_admin(joins[0])).is_false()


func test_messages_go_both_ways() -> void:
	_start()
	var a := _client()
	var ra := _result(a)
	var got := []
	server.message.connect(func(peer: int, type: int, data: Dictionary) -> void: got.append([peer, type, data]))
	var raw := []
	a.raw.connect(func(bytes: PackedByteArray) -> void: raw.append(bytes))
	assert_bool(_pump(func() -> bool: return ra.joined)).is_true()
	a.send(50, { "hi": 1 })
	assert_bool(_pump(func() -> bool: return got.size() == 1)).is_true()
	assert_int(got[0][1]).is_equal(50)
	assert_int(got[0][2].hi).is_equal(1)
	server.send_raw(got[0][0], PackedByteArray([NetProtocol.RAW_FIRST, 7, 7]), NetProtocol.CH_STATE)
	assert_bool(_pump(func() -> bool: return raw.size() == 1)).is_true()
	assert_int(raw[0][1]).is_equal(7)


func test_password() -> void:
	var cfg := ServerConfig.defaults()
	cfg.password = "secret"
	_start(cfg)
	var none := _result(_client(["A"]))
	var wrong := _result(_client(["B"], "guess"))
	var right := _result(_client(["C"], "secret"))
	assert_bool(_pump(func() -> bool: return none.reason != "" and wrong.reason != "" and right.joined)).is_true()
	assert_str(none.reason).is_equal("Password needed")
	assert_str(wrong.reason).is_equal("Wrong password")
	assert_int(server.player_count()).is_equal(1)


func test_full_server() -> void:
	var cfg := ServerConfig.defaults()
	cfg.max_players = 3
	_start(cfg, [{ "name": "Host", "color": "ffffff" }])
	var a := _result(_client(["A", "B"]))
	assert_bool(_pump(func() -> bool: return a.joined)).is_true()
	var b := _result(_client(["C"]))
	assert_bool(_pump(func() -> bool: return b.reason != "")).is_true()
	assert_str(b.reason).is_equal("Server full")


func test_one_key_joins_once() -> void:
	_start()
	var me := NetIdentity.throwaway()
	var a := _result(_client(["A"], "", me))
	assert_bool(_pump(func() -> bool: return a.joined)).is_true()
	var b := _result(_client(["A again"], "", me))
	assert_bool(_pump(func() -> bool: return b.reason != "")).is_true()
	assert_str(b.reason).is_equal("Already on this server")


func test_kick_and_ban() -> void:
	_start()
	var me := NetIdentity.throwaway()
	var a := _result(_client(["A"], "", me))
	var peers := []
	server.peer_joined.connect(func(peer: int) -> void: peers.append(peer))
	assert_bool(_pump(func() -> bool: return a.joined and peers.size() == 1)).is_true()
	server.kick(peers[0], "Be nice")
	assert_bool(_pump(func() -> bool: return a.reason != "")).is_true()
	assert_str(a.reason).is_equal("Be nice")
	assert_bool(_pump(func() -> bool: return server.player_count() == 0)).is_true()
	# Back again, then banned: the key can't come back.
	var b := _result(_client(["A"], "", me))
	assert_bool(_pump(func() -> bool: return b.joined and peers.size() == 2)).is_true()
	server.ban(peers[1])
	assert_bool(_pump(func() -> bool: return b.reason != "")).is_true()
	assert_bool(server.config.is_banned(me.fingerprint)).is_true()
	var c := _result(_client(["A"], "", me))
	assert_bool(_pump(func() -> bool: return c.reason != "")).is_true()
	assert_str(c.reason).is_equal("Banned")


func test_whitelist() -> void:
	var cfg := ServerConfig.defaults()
	var friend := NetIdentity.throwaway()
	cfg.whitelist.append(friend.fingerprint)
	_start(cfg)
	var a := _result(_client(["Friend"], "", friend))
	var b := _result(_client(["Stranger"]))
	assert_bool(_pump(func() -> bool: return a.joined and b.reason != "")).is_true()
	assert_str(b.reason).is_equal("Not on the whitelist")


func test_old_versions_are_turned_away() -> void:
	_start()
	# A hand-made client that claims another protocol version.
	var api := SceneMultiplayer.new()
	api.root_path = NodePath("/root")
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port, NetProtocol.EXTRA_CHANNELS)
	var me := NetIdentity.throwaway()
	var reason := [""]
	api.auth_callback = func(_id: int, bytes: PackedByteArray) -> void:
		var msg := NetProtocol.decode(bytes)
		if msg.type == NetProtocol.Msg.CHALLENGE:
			api.send_auth(1, NetProtocol.encode(NetProtocol.Msg.HELLO, { "protocol": 999, "game": "0.0.1",
				"key": me.public_pem, "signature": me.sign(msg.data.nonce), "proof": PackedByteArray(),
				"players": [{ "name": "Old", "color": "ffffff" }] }))
		elif msg.type == NetProtocol.Msg.REJECT:
			reason[0] = msg.data.reason
	api.multiplayer_peer = peer
	assert_bool(_pump(func() -> bool:
		api.poll()
		return reason[0] != "")).is_true()
	assert_str(reason[0]).starts_with("Version mismatch")
	peer.close()


func test_a_forged_key_is_refused() -> void:
	_start()
	var api := SceneMultiplayer.new()
	api.root_path = NodePath("/root")
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port, NetProtocol.EXTRA_CHANNELS)
	var victim := NetIdentity.throwaway()
	var me := NetIdentity.throwaway()
	var reason := [""]
	api.auth_callback = func(_id: int, bytes: PackedByteArray) -> void:
		var msg := NetProtocol.decode(bytes)
		if msg.type == NetProtocol.Msg.CHALLENGE:
			# Claims the victim's key, but can only sign with its own.
			api.send_auth(1, NetProtocol.encode(NetProtocol.Msg.HELLO, { "protocol": NetProtocol.VERSION,
				"game": NetProtocol.game_version(), "key": victim.public_pem, "signature": me.sign(msg.data.nonce),
				"proof": PackedByteArray(), "players": [{ "name": "Fake", "color": "ffffff" }] }))
		elif msg.type == NetProtocol.Msg.REJECT:
			reason[0] = msg.data.reason
	api.multiplayer_peer = peer
	assert_bool(_pump(func() -> bool:
		api.poll()
		return reason[0] != "")).is_true()
	assert_str(reason[0]).is_equal("Bad key")
	peer.close()


func test_no_server() -> void:
	var a := _result(_client(["A"]))
	var t0 := Time.get_ticks_msec()
	assert_bool(_pump(func() -> bool: return a.reason != "", 10.0)).is_true()
	assert_str(a.reason).is_equal("Server not found")
	assert_int(Time.get_ticks_msec() - t0).is_less(8000)
