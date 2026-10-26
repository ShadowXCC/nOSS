extends GdUnitTestSuite
## The lobby over real ENet (MP-03, MP-06, MP-07, LOC-05; docs/UI_FLOW.md §7.5, §7.6): what
## everyone sees, cars, devices, assists and pings, ready per player, the countdown and a forced
## start, the playlist, chat and its limits, admin commands, local players joining and leaving
## (closing up their local indexes), LAN discovery, and a kart cup's standings kept on the server
## (P10).

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
	NetHost.countdown_s = -1.0
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
	a.send(NetProtocol.Msg.READY, { "player": me, "ready": true })
	assert_bool(_pump(func() -> bool:
		var players: Array = _last(box, NetProtocol.Msg.LOBBY).get("players", [])
		return players.any(func(d: Dictionary) -> bool: return d.id == me and d.car_name == "Box" and d.ready))).is_true()
	assert_bool(host.all_ready()).is_false() # the host hasn't readied
	host.handle(1, NetProtocol.Msg.READY, { "player": server.players_of(1)[0].id, "ready": true })
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


## Ready is per player (docs/UI_FLOW.md §7.5): a PC with two players is ready once both are; a
## game can't ready someone else's player.
func test_ready_is_per_player() -> void:
	_start()
	var a := _client(["Ann", "Bo"])
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var ids := a.player_ids()
	var host_id := server.players_of(1)[0].id
	host.handle(1, NetProtocol.Msg.READY, { "player": host_id, "ready": true })
	a.send(NetProtocol.Msg.READY, { "player": ids[0], "ready": true })
	a.send(NetProtocol.Msg.READY, { "player": host_id, "ready": false }) # not theirs
	a.send(NetProtocol.Msg.READY, { "ready": true }) # protocol 12's: ignored
	assert_bool(_pump(func() -> bool: return server.players[ids[0]].ready)).is_true()
	_pump(func() -> bool: return false, 0.2)
	assert_bool(server.players[host_id].ready).is_true()
	assert_bool(server.players[ids[1]].ready).is_false()
	assert_bool(host.all_ready()).is_false()
	a.send(NetProtocol.Msg.READY, { "player": ids[1], "ready": true })
	assert_bool(_pump(func() -> bool: return host.all_ready())).is_true()


## A player's device, assists and ping travel in the lobby and come back out of it whole; junk is
## dropped, and a new name is made unique (but not against the player's own).
func test_player_info_round_trips() -> void:
	_start()
	var a := _client(["Ann"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var me := a.player_ids()[0]
	a.send(NetProtocol.Msg.PLAYER_INFO, { "player": me, "device": "playstation", "assists": ["abs", "tcs", "abs", "warp"],
		"name": "Ann", "color": "00ffff" })
	assert_bool(_pump(func() -> bool:
		var players: Array = _last(box, NetProtocol.Msg.LOBBY).get("players", [])
		return players.any(func(d: Dictionary) -> bool: return d.id == me and d.device == "playstation"))).is_true()
	var d: Dictionary = (_last(box, NetProtocol.Msg.LOBBY).players as Array).filter(func(x: Dictionary) -> bool: return x.id == me)[0]
	var p := NetPlayer.from_dict(d)
	assert_object(p).is_not_null()
	assert_str(p.name).is_equal("Ann") # its own name isn't taken
	assert_str(p.device).is_equal("playstation")
	assert_array(Array(p.assists)).contains_exactly(["abs", "tcs"])
	assert_str(p.color.to_html(false)).is_equal("00ffff")
	assert_int(p.ping).is_greater_equal(0)
	var round_trip := NetPlayer.from_dict(p.to_dict())
	assert_str(round_trip.device).is_equal("playstation")
	assert_array(Array(round_trip.assists)).contains_exactly(["abs", "tcs"])
	assert_int(round_trip.ping).is_equal(p.ping)
	# The host's name is taken; a device nobody knows is no device.
	a.send(NetProtocol.Msg.PLAYER_INFO, { "player": me, "device": "toaster", "assists": [], "name": "Host", "color": "00ffff" })
	assert_bool(_pump(func() -> bool: return server.players[me].name == "Host 2")).is_true()
	assert_str(server.players[me].device).is_empty()
	# Not theirs: nothing changes.
	a.send(NetProtocol.Msg.PLAYER_INFO, { "player": server.players_of(1)[0].id, "device": "wheel", "assists": [] })
	_pump(func() -> bool: return false, 0.2)
	assert_str(server.players_of(1)[0].device).is_empty()
	# The host's own players' ping is 0 (they're on it); everyone's is in the lobby.
	assert_int(server.players_of(1)[0].ping).is_equal(0)
	for x: Dictionary in _last(box, NetProtocol.Msg.LOBBY).players:
		assert_bool(x.has("ping") and x.has("device") and x.has("assists")).is_true()


## Everyone ready starts the countdown ("Starting in"); anyone un-readying holds it; ready again,
## it runs out and the session starts (docs/UI_FLOW.md §7.6). With nobody ready, Force start
## starts at once.
func test_countdown_starts_and_holds() -> void:
	NetHost.countdown_s = 0.6
	_start()
	var a := _client(["Ann"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var me := a.player_ids()[0]
	var host_id := server.players_of(1)[0].id
	host.handle(1, NetProtocol.Msg.READY, { "player": host_id, "ready": true })
	a.send(NetProtocol.Msg.READY, { "player": me, "ready": true })
	assert_bool(_pump(func() -> bool: return int(_last(box, NetProtocol.Msg.LOBBY).get("starting", 0)) == 1)).is_true()
	assert_str(host.state).is_equal("lobby")
	assert_bool(_lines(box).has("Starting in 1")).is_false() # under a second: no line, just the count
	a.send(NetProtocol.Msg.READY, { "player": me, "ready": false })
	assert_bool(_pump(func() -> bool: return _lines(box).has("Start held: not everyone's ready"))).is_true()
	assert_int(host.starting).is_equal(0)
	_pump(func() -> bool: return false, 0.8)
	assert_str(host.state).is_equal("lobby")
	a.send(NetProtocol.Msg.READY, { "player": me, "ready": true })
	assert_bool(_pump(func() -> bool: return host.state == "session")).is_true()
	assert_bool(_last(box, NetProtocol.Msg.SESSION).is_empty()).is_false()
	# Back in the lobby everyone readies again; Force start doesn't wait for them.
	host.end_session()
	assert_bool(host.all_ready()).is_false()
	host.admin(1, "start")
	assert_str(host.state).is_equal("session")


## The countdown's length: the config's (3 s, the dedicated server's too), unless a test sets it;
## a server waits for min_players.
func test_countdown_length_and_min_players() -> void:
	var errors := PackedStringArray()
	var cfg := ServerConfig.from_dict({ "schema": ServerConfig.SCHEMA, "countdown_s": 5 }, errors)
	assert_array(Array(errors)).is_empty()
	assert_float(cfg.countdown_s).is_equal(5.0)
	assert_float(ServerConfig.from_dict(cfg.to_dict()).countdown_s).is_equal(5.0)
	assert_object(ServerConfig.from_dict({ "schema": ServerConfig.SCHEMA, "countdown_s": 600 })).is_null()
	assert_float(ServerConfig.defaults().countdown_s).is_equal(3.0)
	NetHost.countdown_s = 0.0
	_start()
	host.min_players = 2
	host.handle(1, NetProtocol.Msg.READY, { "player": server.players_of(1)[0].id, "ready": true })
	_pump(func() -> bool: return false, 0.2)
	assert_str(host.state).is_equal("lobby") # one player of two
	host.min_players = 1
	assert_bool(_pump(func() -> bool: return host.state == "session")).is_true()
	NetHost.countdown_s = -1.0
	assert_float(host.countdown()).is_equal(3.0)


## The playlist (docs/UI_FLOW.md §7.5): the host sets it, Change event takes the place of the one
## up, and it moves on after each session. A car or kart class the new class can't take is dropped,
## and everyone readies again.
func test_playlist_moves_on_and_change_event() -> void:
	_start()
	var p: NetPlayer = server.players_of(1)[0]
	var race := RaceEvent.new()
	race.kind = "race"
	var items := [
		{ "track": "proving_ground", "class": "official.track.gt", "event": race.to_dict(), "name": "Regular race" },
		{ "track": "proving_ground", "class": "official.track.formula", "event": race.to_dict(), "name": "Custom race" },
	]
	var changed := [0]
	host.rotation_changed.connect(func() -> void: changed[0] += 1)
	host.set_rotation(items, 0)
	assert_int(changed[0]).is_equal(1)
	assert_str(host.platform_id()).is_equal("official.track.gt")
	host.handle(1, NetProtocol.Msg.PICK, { "player": p.id, "car": "sha256:" + "a".repeat(64), "car_name": "Box", "family": "car" })
	host.handle(1, NetProtocol.Msg.READY, { "player": p.id, "ready": true })
	host.start_session()
	host.end_session()
	assert_int(host.rotation_index).is_equal(1)
	assert_str(host.platform_id()).is_equal("official.track.formula")
	assert_bool(p.ready).is_false()
	assert_str(p.car).is_empty() # Formula takes open-wheelers only
	assert_bool(_lines(sunk).any(func(t: String) -> bool: return t.begins_with("Next: "))).is_true()
	host.end_session() # not in a session: nothing moves
	assert_int(host.rotation_index).is_equal(1)
	# Change event: the one up now is replaced; the rest stay. A kart class goes with a kart event.
	host.set_event({ "track": "proving_ground", "class": EventFlow.KART, "event": race.to_dict(), "name": "Kart race" })
	host.handle(1, NetProtocol.Msg.PICK, { "player": p.id, "car": "sha256:" + "a".repeat(64), "car_name": "Box", "family": "car",
		"class": "official.kart.heavy" })
	assert_str(p.kart_class).is_equal("official.kart.heavy")
	var sumo := { "track": "proving_ground", "class": EventFlow.SUMO, "event": RaceEvent.sumo().to_dict(), "name": "Sumo Wrestling" }
	host.set_event(sumo)
	assert_str(p.kart_class).is_empty()
	assert_str(p.car_name).is_equal("Box") # sumo takes any car
	assert_int(host.config.rotation.size()).is_equal(2)
	assert_int(host.rotation_index).is_equal(1)
	assert_str(host.event().kind).is_equal("sumo")
	assert_str(String(host.config.rotation[0].name)).is_equal("Regular race")
	# A reorder that keeps the same event up changes nothing for the players.
	host.handle(1, NetProtocol.Msg.READY, { "player": p.id, "ready": true })
	host.set_rotation([host.config.rotation[1], host.config.rotation[0]], 0)
	assert_str(host.event().kind).is_equal("sumo")
	assert_bool(p.ready).is_true()
	# The lobby says it all.
	assert_str(String(host.lobby_dict()["class"])).is_equal(EventFlow.SUMO)
	assert_bool(host.lobby_dict().has("starting")).is_true()


## Local players join and leave in the lobby: the server closes up the others' local indexes as
## Players closes up its slots, so local index i is always slot i (LOC-05), and the new one comes
## last.
func test_local_players_close_up() -> void:
	_start()
	var a := _client(["Ann", "Bo", "Cy"])
	var box := _inbox(a)
	assert_bool(_pump(func() -> bool: return a.state == NetClient.State.JOINED)).is_true()
	var ids := a.player_ids()
	a.send(NetProtocol.Msg.REMOVE_LOCAL, { "player": ids[1] })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.YOUR_PLAYERS).get("players", PackedInt32Array()).size() == 2)).is_true()
	assert_int(server.players[ids[0]].local_index).is_equal(0)
	assert_int(server.players[ids[2]].local_index).is_equal(1)
	a.send(NetProtocol.Msg.ADD_LOCAL, { "name": "Di", "color": "0000ff" })
	assert_bool(_pump(func() -> bool: return _last(box, NetProtocol.Msg.YOUR_PLAYERS).get("players", PackedInt32Array()).size() == 3)).is_true()
	var now: PackedInt32Array = _last(box, NetProtocol.Msg.YOUR_PLAYERS).players
	assert_int(now[0]).is_equal(ids[0])
	assert_int(now[1]).is_equal(ids[2])
	assert_str(server.players[now[2]].name).is_equal("Di")
	for i in now.size():
		assert_int(server.players[now[i]].local_index).is_equal(i)


## Net finds this game's players by their local index (a Players slot), not by their place in a
## list; a local player who goes takes their own id with them.
func test_net_matches_players_by_local_index() -> void:
	var cfg := ServerConfig.defaults()
	cfg.port = port
	cfg.lan = false
	assert_int(Net.host(cfg, [{ "name": "Me", "color": "ffffff" }, { "name": "You", "color": "ff00ff" }])).is_equal(OK)
	Net.server.manual_poll = true
	Net.host_logic._physics_process(0.0)
	var me := Net.id_of(0)
	var you := Net.id_of(1)
	assert_int(Net.local_of(you)).is_equal(1)
	assert_int(Net.local_of(12345)).is_equal(-1)
	Net.set_ready(true, 1)
	assert_bool(Net.server.players[you].ready).is_true()
	assert_bool(Net.server.players[me].ready).is_false()
	Net.send_info(1, { "device": "wheel", "assists": ["abs"] })
	assert_str(Net.server.players[you].device).is_equal("wheel")
	Net.remove_local(0)
	Net.host_logic._physics_process(0.0)
	assert_array(Array(Net.my_ids)).contains_exactly([you])
	assert_int(Net.id_of(0)).is_equal(you)
	assert_int(Net.local_of(you)).is_equal(0)
	Net.add_local({ "name": "Them", "color": "00ff00" })
	Net.host_logic._physics_process(0.0)
	assert_int(Net.my_ids.size()).is_equal(2)
	assert_str(Net.player(Net.id_of(1)).name).is_equal("Them")
	Net.leave()


## A kart cup online (P10): its races are the playlist; the server keeps the standings (by player
## id, the AI by name), a restarted race's results take the place of the first go's, the cup's AI
## field stays the same from race to race, and the lobby carries the standings, the final too.
func test_a_cup_keeps_its_standings_on_the_server() -> void:
	_start()
	var flow := EventFlow.racing("kart", false, "host")
	flow.recall()
	flow.cup = "res://data/cups/spark_cup.cup.json"
	flow.event.ai_count = 2
	flow.fit()
	host.set_events(flow.rotation_items())
	assert_int(host.config.rotation.size()).is_equal(4)
	assert_int(host.cup_item().race).is_equal(0)
	var me: NetPlayer = server.players_of(1)[0]
	var ann := Racer.new()
	ann.net_id = me.id
	ann.display_name = "Host"
	var bot := Racer.new()
	bot.net_id = NetProtocol.FIRST_AI_ID
	bot.display_name = AiRacer.NAMES[0]
	var rows := func(first: Racer, second: Racer) -> Array:
		return [{ "racer": first, "position": 1, "dnf": false }, { "racer": second, "position": 2, "dnf": false }]
	host.start_session()
	assert_object(host.cup).is_not_null()
	var ai_first: Array = host.session_dict().roster.filter(func(d: Dictionary) -> bool: return d.get("ai", false))
	assert_int(ai_first.size()).is_equal(2)
	host.session_results("race", rows.call(ann, bot))
	assert_int(host.cup.index).is_equal(1)
	# Restart: the second go's results take the first's place.
	host.session_results("race", rows.call(bot, ann))
	assert_int(host.cup.index).is_equal(1)
	var table := host.cup.standings()
	assert_str(String(table[0].key)).is_equal("ai:" + AiRacer.NAMES[0])
	assert_int(int(table[0].points)).is_equal(CupRun.POINTS[0])
	assert_str(String(table[1].key)).is_equal("net:%d" % me.id)
	# The lobby: the race up and the standings so far.
	host.end_session()
	var cup: Dictionary = host.lobby_dict().cup
	assert_int(int(cup.race)).is_equal(2)
	assert_int(int(cup.run)).is_equal(1)
	assert_str(String(cup.standings[0].name)).is_equal(AiRacer.NAMES[0])
	assert_str(LobbyPage.standings_text(cup)).starts_with("After race 1 of 4: ")
	# The next race: the same cup, the same AI field.
	host.start_session()
	var ai_next: Array = host.session_dict().roster.filter(func(d: Dictionary) -> bool: return d.get("ai", false))
	assert_array(ai_next.map(func(d: Dictionary) -> String: return d.car)).is_equal(ai_first.map(func(d: Dictionary) -> String: return d.car))
	assert_array(ai_next.map(func(d: Dictionary) -> float: return d.skill)).is_equal(ai_first.map(func(d: Dictionary) -> float: return d.skill))
	for i in 3:
		host.session_results("race", rows.call(ann, bot))
		host.end_session()
		if i < 2:
			host.start_session()
	assert_bool(host.cup.done()).is_true()
	cup = host.lobby_dict().cup
	assert_int(int(cup.race)).is_equal(1) # round again: the first race is up
	assert_str(LobbyPage.standings_text(cup)).starts_with("Spark Cup final: 1st ")
	# Its first race again starts a new cup; another event drops the standings.
	host.start_session()
	assert_int(host.cup.index).is_equal(0)
	host.end_session()
	host.set_event({ "track": "proving_ground", "class": "official.track.gt", "event": RaceEvent.free_drive().to_dict(), "name": "Free Drive" })
	host.start_session()
	assert_object(host.cup).is_null()
	assert_dict(host.lobby_dict().cup).is_empty()
	ann.free()
	bot.free()
