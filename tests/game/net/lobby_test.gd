extends GdUnitTestSuite
## The lobby over real ENet (MP-03, MP-06, MP-07, LOC-05): what everyone sees, cars and ready,
## chat and its limits, admin commands, local guests, and LAN discovery.

var port := 0
var server: NetServer
var host: NetHost
var clients: Array[NetClient] = []
var sunk: Array = [] # the host game's own messages [type, data]


func before() -> void:
	Settings.use_folder("user://tests/net_lobby")


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	port = 47900 + randi() % 90
	clients.clear()
	sunk.clear()


func after_test() -> void:
	for c in clients:
		c.leave()
		c.free()
	clients.clear()
	if host:
		host.free()
		host = null
	if server:
		server.stop()
		server.free()
		server = null


func _start(cfg := ServerConfig.defaults()) -> void:
	cfg.port = port
	cfg.lan = false
	server = NetServer.new()
	server.manual_poll = true
	add_child(server)
	assert_int(server.start(cfg, NetIdentity.throwaway(), [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	host = NetHost.new(server)
	host.set_physics_process(false)
	host.local_sink = func(type: int, data: Dictionary) -> void: sunk.append([type, data])
	add_child(host)


func _client(names := ["Ann"], ident: NetIdentity = null) -> NetClient:
	var c := NetClient.new()
	c.manual_poll = true
	add_child(c)
	clients.append(c)
	var players := []
	for n: String in names:
		players.append({ "name": n, "color": "ff0000" })
	c.join("127.0.0.1", port, players, "", ident if ident else NetIdentity.throwaway())
	return c


func _pump(done: Callable, seconds := 3.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		server.poll()
		host._physics_process(0.0)
		for c in clients:
			c.poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func _inbox(c: NetClient) -> Array:
	var got := []
	c.message.connect(func(type: int, data: Dictionary) -> void: got.append([type, data]))
	return got


func _last(box: Array, type: int) -> Dictionary:
	for i in range(box.size() - 1, -1, -1):
		if box[i][0] == type:
			return box[i][1]
	return {}


func _lines(box: Array) -> Array:
	return box.filter(func(m: Array) -> bool: return m[0] == NetProtocol.Msg.CHAT_LINE).map(func(m: Array) -> String: return m[1].text)


func test_everyone_sees_the_lobby() -> void:
	_start()
	var a := _client(["Ann", "Bo"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.LOBBY).get("players", []).size() == 3)).is_true()
	var lobby := _last(box, NetProtocol.Msg.LOBBY)
	assert_str(lobby.class).is_equal("official.track.gt")
	assert_str(lobby.track_name).is_equal("Proving Ground")
	assert_str(lobby.event.kind).is_equal("free")
	var names := []
	for d: Dictionary in lobby.players:
		var p := NetPlayer.from_dict(d)
		assert_object(p).is_not_null()
		names.append(p.name)
	assert_array(names).contains_exactly_in_any_order(["Host", "Ann", "Bo"])
	# The host game gets the same lobby.
	assert_int(_last(sunk, NetProtocol.Msg.LOBBY).players.size()).is_equal(3)
	assert_bool(_lines(box).any(func(t: String) -> bool: return t == "Ann, Bo joined")).is_true()


func test_cars_and_ready() -> void:
	_start()
	var a := _client(["Ann"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var me := a.player_ids()[0]
	a.send(NetProtocol.Msg.PICK, { "player": me, "car": "sha256:" + "a".repeat(64), "car_name": "Box", "family": "car" })
	a.send(NetProtocol.Msg.READY, { "ready": true })
	assert_bool(_pump(func() -> bool:
		var players: Array = _last(box, NetProtocol.Msg.LOBBY).get("players", [])
		return players.any(func(d: Dictionary) -> bool: return d.id == me and d.car_name == "Box" and d.ready))).is_true()
	assert_bool(host.all_ready()).is_false() # the host hasn't readied
	host.handle(1, NetProtocol.Msg.READY, { "ready": true })
	assert_bool(host.all_ready()).is_true()
	# A car the class can't take is refused; someone else's player can't be changed.
	a.send(NetProtocol.Msg.PICK, { "player": me, "car": "sha256:" + "b".repeat(64), "car_name": "Kart", "family": "kart" })
	a.send(NetProtocol.Msg.PICK, { "player": server.players_of(1)[0].id, "car": "sha256:" + "c".repeat(64), "car_name": "X", "family": "car" })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.NOTICE).get("text", "") == "Car doesn't fit this class")).is_true()
	assert_str(server.players[me].car_name).is_equal("Box")
	assert_str(server.players_of(1)[0].car_name).is_empty()


func test_chat_is_cleaned_and_limited() -> void:
	_start()
	var a := _client(["Ann"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var me := a.player_ids()[0]
	a.send(NetProtocol.Msg.CHAT, { "player": me, "text": "  hi [b]all[/b]\n\u0007 " })
	assert_bool(_pump(func() -> bool: return _lines(box).has("hi [b]all[/b]"))).is_true()
	var line := _last(box, NetProtocol.Msg.CHAT_LINE)
	assert_str(line.name).is_equal("Ann")
	assert_str(line.kind).is_equal("chat")
	for i in 8:
		a.send(NetProtocol.Msg.CHAT, { "player": me, "text": "spam %d" % i })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.NOTICE).get("text", "") == "Slow down")).is_true()
	assert_int(_lines(box).filter(func(t: String) -> bool: return t.begins_with("spam")).size()).is_less(NetChat.BURST)
	# Speaking for someone else's player goes nowhere.
	var before := _lines(box).size()
	a.send(NetProtocol.Msg.CHAT, { "player": server.players_of(1)[0].id, "text": "I am the host" })
	_pump(func() -> bool: return false, 0.3)
	assert_bool(_lines(box).has("I am the host")).is_false()
	assert_int(_lines(box).size()).is_equal(before)


func test_commands_need_an_admin() -> void:
	var cfg := ServerConfig.defaults()
	var boss := NetIdentity.throwaway()
	cfg.admins.append(boss.fingerprint)
	_start(cfg)
	var a := _client(["Ann"])
	var b := _client(["Boss"], boss)
	var abox := _inbox(a)
	var bbox := _inbox(b)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED and b.state == NetClient.State.JOINED)).is_true()
	a.send(NetProtocol.Msg.CHAT, { "player": a.player_ids()[0], "text": "/kick Boss" })
	assert_bool(_pump(func() -> bool: return _last(abox, NetProtocol.Msg.NOTICE).get("text", "") == "Admins only")).is_true()
	assert_bool(b.info.admin).is_true()
	var reason := [""]
	a.left.connect(func(r: String) -> void: reason[0] = r)
	b.send(NetProtocol.Msg.CHAT, { "player": b.player_ids()[0], "text": "/kick ann" })
	assert_bool(_pump(func() -> bool: return reason[0] != "")).is_true()
	assert_str(reason[0]).is_equal("Kicked")
	assert_bool(_lines(bbox).has("Ann was kicked")).is_true()
	# The host can't be kicked.
	b.send(NetProtocol.Msg.ADMIN, { "cmd": "kick", "target": "Host" })
	assert_bool(_pump(func() -> bool: return _last(bbox, NetProtocol.Msg.NOTICE).get("text", "") == "Can't kick the host")).is_true()


func test_next_event_and_start() -> void:
	var errors := PackedStringArray()
	_start(ServerConfig.load_file("res://data/server.example.json", errors))
	var started := [0]
	host.start_requested.connect(func() -> void: started[0] += 1)
	host.admin(1, "next")
	assert_str(host.platform_id()).is_equal("official.track.touring")
	assert_str(host.event().kind).is_equal("free")
	host.admin(1, "next")
	assert_str(host.platform_id()).is_equal("official.track.gt")
	host.admin(1, "start")
	assert_int(started[0]).is_equal(1)


func test_local_guests_join_and_leave() -> void:
	var cfg := ServerConfig.defaults()
	cfg.max_players = 3
	_start(cfg)
	var a := _client(["Ann"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	a.send(NetProtocol.Msg.ADD_LOCAL, { "name": "Ann", "color": "0000ff" })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.YOUR_PLAYERS).get("players", PackedInt32Array()).size() == 2)).is_true()
	var ids: PackedInt32Array = _last(box, NetProtocol.Msg.YOUR_PLAYERS).players
	assert_str(server.players[ids[1]].name).is_equal("Ann 2")
	assert_int(server.players[ids[1]].local_index).is_equal(1)
	a.send(NetProtocol.Msg.ADD_LOCAL, { "name": "Cy", "color": "0000ff" })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.NOTICE).get("text", "") == "Server full")).is_true()
	a.send(NetProtocol.Msg.REMOVE_LOCAL, { "player": ids[1] })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.YOUR_PLAYERS).get("players", PackedInt32Array()).size() == 1)).is_true()
	assert_int(server.player_count()).is_equal(2)


func test_net_mirror_and_mute() -> void:
	# The Net autoload's view of the lobby and chat, hosting.
	var cfg := ServerConfig.defaults()
	cfg.port = port
	cfg.lan = false
	assert_int(Net.host(cfg, [{ "name": "Me", "color": "ffffff" }])).is_equal(OK)
	Net.server.manual_poll = true
	Net.host_logic._physics_process(0.0)
	assert_int(Net.roster.size()).is_equal(1)
	assert_int(Net.my_ids.size()).is_equal(1)
	var heard := []
	Net.chat_line.connect(func(line: Dictionary) -> void: heard.append(line.text))
	Net.say("hello")
	assert_array(heard).contains(["hello"])
	Net.mute(Net.my_ids[0], true)
	Net.say("again")
	assert_bool(heard.has("again")).is_false()
	Net.leave()
	assert_bool(Net.online()).is_false()


func test_chat_helpers() -> void:
	assert_str(NetChat.clean("a\tb" + char(0x202E) + "c")).is_equal("a bc")
	assert_int(NetChat.clean("x".repeat(500)).length()).is_equal(NetChat.MAX_CHARS)
	assert_dict(NetChat.command("/kick Ann Lee")).is_equal({ "cmd": "kick", "arg": "Ann Lee" })
	assert_dict(NetChat.command("hello")).is_empty()
	assert_str(NetChat.escape_bbcode("[b]")).is_equal("[lb]b]")
	var lim := NetChat.Limiter.new()
	for i in NetChat.BURST:
		assert_bool(lim.allow(1, 0.0)).is_true()
	assert_bool(lim.allow(1, 1.0)).is_false()
	assert_bool(lim.allow(2, 1.0)).is_true()
	assert_bool(lim.allow(1, NetChat.WINDOW_S + 0.5)).is_true()


func test_lan_discovery_finds_both_servers() -> void:
	var responders: Array = []
	for game_port in [47806, 47808]:
		var r := NetDiscovery.Responder.new()
		add_child(r)
		assert_int(r.start(game_port, func() -> Dictionary: return { "name": "S%d" % game_port, "port": game_port,
			"players": 1, "max": 8, "password": false, "track": "Proving Ground", "class": "GT", "state": "lobby",
			"version": NetProtocol.game_version(), "fp": "%d" % game_port })).is_equal(OK)
		responders.append(r)
	var scan := NetDiscovery.Scanner.new()
	add_child(scan)
	assert_int(scan.start()).is_equal(OK)
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and scan.servers.size() < 2:
		for r: NetDiscovery.Responder in responders:
			r.poll()
		scan.poll(0.05)
		OS.delay_msec(10)
	var names := scan.servers.values().map(func(s: Dictionary) -> String: return s.name)
	assert_array(names).contains_exactly_in_any_order(["S47806", "S47808"])
	for s: Dictionary in scan.servers.values():
		assert_int(s.max).is_equal(8)
	for r: NetDiscovery.Responder in responders:
		r.queue_free()
	scan.queue_free()


## The server's AI cars come with a paint job each (D128), the same on every game: it travels in
## the roster, already clean.
## Each kart its own class (D149): a player's pick is kept if it's one of the server's kart mode,
## only in the lobby; the server's AI karts pick their own; outside karts nobody has one.
func test_kart_players_and_ai_pick_their_own_class() -> void:
	var cfg := ServerConfig.defaults()
	cfg.rotation[0]["class"] = "official.kart.medium"
	var e := RaceEvent.new()
	e.kind = "race"
	e.ai_count = 6
	e.ai_cars = "builtin"
	cfg.rotation[0].event = e.to_dict()
	_start(cfg)
	var a := _client(["Ann"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var me := a.player_ids()[0]
	var car := { "player": me, "car": "sha256:" + "a".repeat(64), "car_name": "Box", "family": "car" }
	a.send(NetProtocol.Msg.PICK, car.merged({ "class": "official.kart.heavy" }))
	assert_bool(_pump(func() -> bool:
		var players: Array = _last(box, NetProtocol.Msg.LOBBY).get("players", [])
		return players.any(func(d: Dictionary) -> bool: return d.id == me and d["class"] == "official.kart.heavy"))).is_true()
	assert_object(NetPlayer.from_dict(server.players[me].to_dict())).is_not_null()
	assert_str(NetPlayer.from_dict(server.players[me].to_dict()).kart_class).is_equal("official.kart.heavy")
	# Not a kart class: the server's. A session keeps what it started with.
	host.handle(server.players[me].peer, NetProtocol.Msg.PICK, car.merged({ "class": "official.track.gt" }))
	assert_str(server.players[me].kart_class).is_empty()
	host.handle(server.players[me].peer, NetProtocol.Msg.PICK, car.merged({ "class": "official.kart.light" }))
	host.state = "session"
	host.handle(server.players[me].peer, NetProtocol.Msg.PICK, car.merged({ "class": "official.kart.heavy" }))
	assert_str(server.players[me].kart_class).is_equal("official.kart.light")
	host.state = "lobby"
	var kart_classes := GameModes.kart_classes("official.kart.medium")
	for d: Dictionary in host.session_dict().roster.filter(func(d: Dictionary) -> bool: return d.get("ai", false)):
		assert_object(NetPlayer.from_dict(d)).is_not_null()
		assert_array(kart_classes).contains([d["class"]])


func test_outside_karts_nobody_picks_a_class() -> void:
	var cfg := ServerConfig.defaults()
	var e := RaceEvent.new()
	e.kind = "race"
	e.ai_count = 2
	e.ai_cars = "builtin"
	cfg.rotation[0].event = e.to_dict()
	_start(cfg)
	var host_player: NetPlayer = server.players_of(1)[0]
	host.handle(1, NetProtocol.Msg.PICK, { "player": host_player.id, "car": "sha256:" + "a".repeat(64), "car_name": "Box", "family": "car", "class": "official.kart.heavy" })
	assert_str(host_player.kart_class).is_empty()
	for d: Dictionary in host.session_dict().roster:
		assert_str(String(d["class"])).is_empty()


func test_ai_cars_bring_their_paint() -> void:
	var cfg := ServerConfig.defaults()
	var e := RaceEvent.new()
	e.kind = "race"
	e.ai_count = 6
	e.ai_cars = "builtin"
	cfg.rotation[0].event = e.to_dict()
	_start(cfg)
	var ai: Array = host.session_dict().roster.filter(func(d: Dictionary) -> bool: return d.get("ai", false))
	assert_int(ai.size()).is_equal(6)
	var looks := {}
	for d: Dictionary in ai:
		assert_bool(d.paint is Dictionary).is_true()
		assert_dict(CarVisual.clean_paint(d.paint)).is_equal(d.paint)
		looks[JSON.stringify(d.paint)] = true
	assert_int(looks.size()).is_greater(1)


## A session's start waits for every game's cars (D127): each game says how many it has, the
## server counts the games that have them all; one that leaves isn't waited for.
func test_the_start_counts_games_with_their_cars() -> void:
	_start()
	var a := _client(["Ann"])
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	host.start_session()
	assert_object(host.sync_state()).is_equal(Vector2i(0, 2))
	host.handle(1, NetProtocol.Msg.SYNCED, { "have": 3, "of": 3 })
	assert_object(host.sync_state()).is_equal(Vector2i(1, 2))
	a.send(NetProtocol.Msg.SYNCED, { "have": 2, "of": 3 })
	a.send(NetProtocol.Msg.SYNCED, { "have": "all" }) # junk is ignored
	assert_bool(_pump(func() -> bool: return host.synced.size() == 2)).is_true()
	assert_object(host.sync_state()).is_equal(Vector2i(1, 2))
	a.send(NetProtocol.Msg.SYNCED, { "have": 3, "of": 3 })
	assert_bool(_pump(func() -> bool: return host.sync_state() == Vector2i(2, 2))).is_true()
	# A new session starts the count again; a game that leaves isn't waited for.
	host.end_session()
	host.start_session()
	assert_object(host.sync_state()).is_equal(Vector2i(0, 2))
	host.handle(1, NetProtocol.Msg.SYNCED, { "have": 1, "of": 1 })
	a.leave()
	assert_bool(_pump(func() -> bool: return host.sync_state() == Vector2i(1, 1))).is_true()
