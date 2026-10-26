extends Node
## Online play (autoload "Net", docs/NETWORKING.md): this game's server and its rules (when
## hosting, or as the dedicated server) or its client (when joined), and this install's identity.
## Menus use the same calls either way: requests go to the local NetHost when hosting and to the
## server when joined, and the lobby and chat come back as the same messages.

signal state_changed
signal lobby_changed
## {from, name, color, text, kind}: chat ("chat") or the server's own lines ("server").
signal chat_line(line: Dictionary)
## A short message for this game from the server ("Slow down", "Admins only").
signal notice(text: String)
## Joined a server (client), or the server started (host).
signal joined
## Couldn't join, or cut off from the server.
signal disconnected(reason: String)
## A session starts ({track, class, event, roster}); who's in it changed; it ended.
signal session_started(data: Dictionary)
signal roster_changed(roster: Array)
signal session_ended
## RACE_BEGIN, RESULTS or NOTE from the server (NetRace).
signal race_message(type: int, data: Dictionary)
## The server's highway traffic as it is (HighwayNet, D109).
signal traffic_full(data: Dictionary)
## One of the server's boards for this session's track (D118): [{name, car, time or score}].
signal board_received(board: String, entries: Array)
## Police news for one of this game's cars (D115): {id, kind (heat, busted, evaded), level, evading, text}.
signal highway_event(data: Dictionary)
## An endless road's traffic owners, used-up slots and players' spots from the server (D159).
signal endless_state(data: Dictionary)
## The sky changed mid-session (an admin's /time or /weather): {time, time_rate, weather, seed, t0}.
signal env_changed(env: Dictionary)

const CHAT_KEEP := 100

var server: NetServer
var host_logic: NetHost
var client: NetClient
## Content transfer: cars, tracks and platforms by hash.
var content: NetContent
## The lobby as last sent by the server (NetHost.lobby_dict), and its players.
var lobby := {}
var roster: Array[NetPlayer] = []
## This game's players' ids on the server, in local order (local index i: Players slot i).
var my_ids := PackedInt32Array()
## Recent chat and server lines.
var chat_log: Array[Dictionary] = []
## The session on now (its SESSION message, roster kept up to date), or {} in the lobby.
var session := {}
## The latest RACE_BEGIN of the session, for a session still being built when it came.
var race_begin := {}
## Player ids whose chat this game hides.
var muted := {}

var _identity: NetIdentity


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## This install's key pair, made on first use.
func identity() -> NetIdentity:
	if _identity == null:
		_identity = NetIdentity.load_or_create(NetIdentity.dir)
	return _identity


## Uses `ident` instead of the saved one (bots, tests).
func use_identity(ident: NetIdentity) -> void:
	_identity = ident


func forget_identity() -> void:
	_identity = null


## Starts a server with `config`. `local`: this machine's players ([{name, color}]) for a listen
## server; empty for a dedicated one. `on_log` gets the server's log lines.
func host(config: ServerConfig, local: Array = [], on_log := Callable()) -> Error:
	leave()
	_reset()
	server = NetServer.new()
	server.name = "NetServer"
	add_child(server)
	if on_log.is_valid():
		server.log_line.connect(on_log)
	var err := server.start(config, identity(), local)
	if err != OK:
		server.queue_free()
		server = null
		state_changed.emit()
		return err
	content = NetContent.new()
	content.name = "NetContent"
	content.setup(true, func(peer: int, type: int, d: Dictionary) -> void: server.send(peer, type, d),
		func(peer: int, bytes: PackedByteArray) -> void:
			server.send_raw(peer, bytes, NetProtocol.CH_CONTENT))
	content.link_rate = int(config.caps.client_kbps) * 1024
	content.file_rate = int(config.caps.transfer_kbps) * 1024
	content.own_sounds = bool(config.caps.own_sounds)
	content.car_cap = int(config.caps.max_package_mb) << 20
	add_child(content)
	server.raw.connect(func(peer: int, bytes: PackedByteArray) -> void: content.handle_raw(peer, bytes))
	server.peer_left.connect(func(peer: int, _reason: String, _names: String) -> void: content.drop_link(peer))
	host_logic = NetHost.new(server)
	host_logic.name = "NetHost"
	host_logic.content = content
	host_logic.local_sink = _handle
	if on_log.is_valid():
		host_logic.log_line.connect(on_log)
	add_child(host_logic)
	for p in server.players_of(1):
		my_ids.append(p.id)
	state_changed.emit()
	joined.emit()
	return OK


## Joins a server with `local` players ([{name, color}]); `joined` or `disconnected` follows.
func join(host_name: String, port: int, local: Array, password := "") -> Error:
	leave()
	_reset()
	client = NetClient.new()
	client.name = "NetClient"
	add_child(client)
	client.joined.connect(func(_info: Dictionary) -> void:
		my_ids = client.player_ids()
		state_changed.emit()
		joined.emit())
	client.failed.connect(_on_cut_off)
	client.left.connect(_on_cut_off)
	client.message.connect(_handle)
	content = NetContent.new()
	content.name = "NetContent"
	if Game.dev.has("bot") and not Game.dev.has("bot-full"):
		content.max_tier = "data" # bots never draw a car (--bot-full: they fetch it all, net_check --fresh)
	content.setup(false, func(_peer: int, type: int, d: Dictionary) -> void: client.send(type, d),
		func(_peer: int, bytes: PackedByteArray) -> void:
			client.send_raw(bytes, NetProtocol.CH_CONTENT))
	add_child(content)
	client.raw.connect(func(bytes: PackedByteArray) -> void: content.handle_raw(1, bytes))
	content.file_ready.connect(func(_h: String) -> void: lobby_changed.emit()) # a class arrived
	lobby_changed.connect(_fetch_cars)
	session_started.connect(func(data: Dictionary) -> void: _fetch_session_cars(data.roster))
	roster_changed.connect(_fetch_session_cars)
	var err := client.join(host_name, port, local, password, identity())
	if err != OK:
		client.queue_free()
		client = null
	state_changed.emit()
	return err


func leave() -> void:
	if lobby_changed.is_connected(_fetch_cars):
		lobby_changed.disconnect(_fetch_cars)
	if roster_changed.is_connected(_fetch_session_cars):
		roster_changed.disconnect(_fetch_session_cars)
	for c: Dictionary in session_started.get_connections():
		if c.callable.get_object() == self:
			session_started.disconnect(c.callable)
	if content:
		content.queue_free()
		content = null
	if host_logic:
		host_logic.queue_free()
		host_logic = null
	if server:
		server.stop()
		server.queue_free()
		server = null
	if client:
		client.leave()
		client.queue_free()
		client = null
	state_changed.emit()


func is_server() -> bool:
	return server != null


func is_client() -> bool:
	return client != null and client.state != NetClient.State.IDLE


func online() -> bool:
	return is_server() or is_client()


## Whether this game may use admin commands (always when hosting).
func is_admin() -> bool:
	return is_server() or (client != null and bool(client.info.get("admin", false)))


func player(id: int) -> NetPlayer:
	for p in roster:
		if p.id == id:
			return p
	return null


## Sends a request to the server (or hands it to this game's NetHost when hosting).
func request(type: int, data: Dictionary) -> void:
	if host_logic:
		host_logic.handle(1, type, data)
	elif client:
		client.send(type, data)


## This game's player on Players slot `local_index` (the player's local index on the server),
## or 0. By the index, not the list's order (LOC-05).
func id_of(local_index: int) -> int:
	for p in roster:
		if p.local_index == local_index and p.id in my_ids:
			return p.id
	return my_ids[local_index] if local_index >= 0 and local_index < my_ids.size() else 0


## Which of this game's players (their Players slot) player `id` is, or -1 for someone else's.
func local_of(id: int) -> int:
	if not id in my_ids:
		return -1
	var p := player(id)
	return p.local_index if p else Array(my_ids).find(id)


func say(text: String, local_index := 0) -> void:
	var id := id_of(local_index)
	if id:
		request(NetProtocol.Msg.CHAT, { "player": id, "text": text })


## This game's player `local_index` is ready (or not); -1: every one of them. Each player readies
## on their own (docs/UI_FLOW.md §7.5).
func set_ready(on: bool, local_index := -1) -> void:
	for i in my_ids.size():
		var id := id_of(i)
		if id and (local_index < 0 or i == local_index):
			request(NetProtocol.Msg.READY, { "player": id, "ready": on })


## What this game's player `local_index` drives with and the assists they have on, for everyone's
## roster, with their name and colour: `info` {device, assists, name, color}.
func send_info(local_index: int, info: Dictionary) -> void:
	var id := id_of(local_index)
	if id:
		request(NetProtocol.Msg.PLAYER_INFO, info.merged({ "player": id }, true))


## Picks the car at `path` for this game's player `local_index`, with their kart class (the
## server keeps it for kart sessions, D149).
func pick_car(local_index: int, path: String) -> void:
	var id := id_of(local_index)
	if not id:
		return
	var m := PackageLoader.read_manifest(path)
	if not ContentIndex.shareable(m):
		return
	var h := package_hash(path)
	if content:
		content.share_car(h) # the server fetches it from here
	var profile := Players.slots[local_index].profile if local_index < Players.slots.size() else Settings.primary
	request(NetProtocol.Msg.PICK, { "player": id, "car": h, "bytes": NetContent.package_bytes(path),
		"car_name": String(m.get("name", path.get_file())).left(64), "family": String(m.get("family", "car")).left(16),
		"class": String(profile.data.get("kart_class", "")).left(64) })


func admin(cmd: String, target := "") -> void:
	request(NetProtocol.Msg.ADMIN, { "cmd": cmd, "target": target })


## A local player joined in the lobby ({name, color}): they play too (LOC-05).
func add_local(entry: Dictionary) -> void:
	request(NetProtocol.Msg.ADD_LOCAL, entry)


## This game's player `local_index` left; the server closes up the others' local indexes, as
## Players does its slots.
func remove_local(local_index: int) -> void:
	var id := id_of(local_index)
	if id:
		request(NetProtocol.Msg.REMOVE_LOCAL, { "player": id })


func mute(id: int, on: bool) -> void:
	if on:
		muted[id] = true
	else:
		muted.erase(id)


## This machine's joined players as [{name, color}] for a server: the Players slots, or P1.
static func local_players() -> Array:
	var out := []
	for slot in Players.slots:
		if not slot.ai or Game.dev.has("bot"):
			out.append({ "name": slot.profile.display_name(), "color": slot.color().to_html(false) })
	if out.is_empty():
		out.append({ "name": Settings.primary.display_name(), "color": Palette.color(Settings.primary, "p1").to_html(false) })
	return out


## Checked roster entries (NetPlayer dicts) from a message.
static func _roster(v: Variant) -> Array:
	var out := []
	if v is Array and (v as Array).size() <= 64:
		for d: Variant in v:
			if d is Dictionary and NetPlayer.from_dict(d):
				out.append(d)
	return out


## A package's hash ("sha256:" + its manifest's); "" if unreadable.
static func package_hash(path: String) -> String:
	return ContentIndex.package_hash(path)


func _reset() -> void:
	lobby = {}
	session = {}
	race_begin = {}
	roster.clear()
	my_ids = PackedInt32Array()
	chat_log.clear()
	muted.clear()


func _on_cut_off(reason: String) -> void:
	state_changed.emit()
	disconnected.emit(reason)


## The platform `id` with this `class_hash`: the official one here if it's the same file, else the
## server's copy in the cache (PLT-09). Not ok() until it's here.
static func platform_result(id: String, class_hash: String) -> PlatformLoader.Result:
	if id.begins_with("official."):
		var official := PlatformLoader.load_official(id)
		if official.ok() and (class_hash.is_empty() or official.hash == class_hash):
			return official
	var r := PlatformLoader.Result.new()
	if ContentStore.has_file("platforms", class_hash):
		r = PlatformLoader.load_file(ContentStore.file_path("platforms", class_hash))
		if r.ok() and r.platform.id.begins_with("official."):
			r.errors.append("A server's platform can't be official")
	else:
		r.errors.append("Not here yet")
	return r


## Clients fetch the lobby's track and platform if they aren't here, and every car in the lobby
## they don't have (each tier for all of them first).
func _fetch_cars() -> void:
	if content == null or is_server():
		return
	_fetch_track(String(lobby.get("track", "")), int(lobby.get("track_bytes", -1)))
	var class_hash := String(lobby.get("class_hash", ""))
	if class_hash and not platform_result(String(lobby.get("class", "")), class_hash).ok():
		content.fetch_file("platforms", class_hash, 1)
	content.own_sounds = bool(lobby.get("rules", {}).get("own_sounds", true))
	for p in roster:
		if p.car and p.car_note.is_empty() and not p.id in my_ids:
			content.fetch_car(p.car, 1, content.max_tier)


## A session's sky from the server, checked: {time, time_rate, weather, seed, t0}, or {}.
static func _env_of(d: Variant) -> Dictionary:
	if not (d is Dictionary and NetProtocol.has_fields(d, { "time": [TYPE_STRING, 16], "time_rate": TYPE_INT, "weather": [TYPE_STRING, 16],
			"seed": TYPE_INT, "t0": TYPE_FLOAT })):
		return {}
	return { "time": String(d.time), "time_rate": clampi(d.time_rate, 0, 600), "weather": String(d.weather), "seed": maxi(int(d.seed), 1), "t0": float(d.t0) }


func _fetch_track(h: String, bytes: int) -> void:
	if content and not is_server() and ContentStore.valid_hash(h):
		content.fetch_track(h, 1, bytes)


## Whether the lobby's track is here (always, when hosting).
func track_here() -> bool:
	if is_server():
		return true
	var h := String(lobby.get("track", ""))
	return not ContentStore.valid_hash(h) or content != null and content.track_path(h) != ""


## Every car in the session (AI cars included) this game doesn't have.
func _fetch_session_cars(session_roster: Array) -> void:
	if content == null or is_server():
		return
	for d: Dictionary in session_roster:
		var id := int(d.id)
		if String(d.car) and String(d.get("car_note", "")).is_empty() and not id in my_ids:
			content.fetch_car(String(d.car), 1, content.max_tier)


## A message from the server (or from this game's NetHost).
func _handle(type: int, data: Dictionary) -> void:
	if content and content.handle_control(1, type, data):
		return
	match type:
		NetProtocol.Msg.LOBBY:
			if not data.get("players") is Array:
				return
			lobby = data
			roster.clear()
			for d: Variant in data.players:
				var p := NetPlayer.from_dict(d) if d is Dictionary else null
				if p:
					roster.append(p)
			lobby_changed.emit()
		NetProtocol.Msg.CHAT_LINE:
			if not NetProtocol.has_fields(data, { "from": TYPE_INT, "name": [TYPE_STRING, 64], "color": [TYPE_STRING, 8],
					"text": [TYPE_STRING, NetChat.MAX_CHARS * 2], "kind": [TYPE_STRING, 8] }):
				return
			if muted.has(data.from):
				return
			var line := { "from": data.from, "name": NetProtocol.clean_name(data.name) if data.name else "",
				"color": data.color, "text": NetChat.clean(data.text), "kind": data.kind }
			chat_log.append(line)
			if chat_log.size() > CHAT_KEEP:
				chat_log.pop_front()
			chat_line.emit(line)
		NetProtocol.Msg.NOTICE:
			if NetProtocol.has_fields(data, { "text": [TYPE_STRING, 200] }):
				notice.emit(NetChat.clean(data.text))
		NetProtocol.Msg.YOUR_PLAYERS:
			if data.get("players") is PackedInt32Array:
				my_ids = data.players
				lobby_changed.emit()
		NetProtocol.Msg.SESSION:
			var roster := _roster(data.get("roster"))
			if not NetProtocol.has_fields(data, { "track": [TYPE_STRING, 256], "class": [TYPE_STRING, 64], "event": TYPE_DICTIONARY }) \
					or roster.is_empty() and not is_server():
				return
			session = { "track": data.track, "track_name": String(data.get("track_name", "")), "track_bytes": int(data.get("track_bytes", -1)),
				"class": data["class"], "class_hash": String(data.get("class_hash", "")),
				"event": data.event, "roster": roster, "rules": data.get("rules", {}) if data.get("rules") is Dictionary else {} }
			var hw: Variant = data.get("highway")
			if hw is Dictionary and NetProtocol.has_fields(hw, { "seed": TYPE_INT, "count": TYPE_INT, "t0": TYPE_FLOAT }):
				session.highway = { "seed": hw.seed, "count": clampi(hw.count, -1, RaceEvent.TRAFFIC_MAX), "t0": float(hw.t0) }
			var env := _env_of(data.get("environment"))
			if not env.is_empty():
				session.environment = env
			var el: Variant = data.get("endless")
			if el is Dictionary and NetProtocol.has_fields(el, { "t0": TYPE_FLOAT, "at": TYPE_DICTIONARY }) and (el.at as Dictionary).size() <= NetProtocol.MAX_PLAYERS:
				session.endless = { "t0": float(el.t0), "at": el.at }
			_fetch_track(String(data.track), int(data.get("track_bytes", -1)))
			race_begin = {}
			session_started.emit(session)
		NetProtocol.Msg.ROSTER:
			if session.is_empty():
				return
			var roster := _roster(data.get("roster"))
			session.roster = roster
			roster_changed.emit(roster)
		NetProtocol.Msg.SESSION_END:
			session = {}
			race_begin = {}
			session_ended.emit()
		NetProtocol.Msg.TRAFFIC_FULL:
			if not session.is_empty():
				traffic_full.emit(data)
		NetProtocol.Msg.ENDLESS_STATE:
			if not session.is_empty():
				endless_state.emit(data)
		NetProtocol.Msg.ENV:
			var env := _env_of(data)
			if not session.is_empty() and not env.is_empty():
				session.environment = env
				env_changed.emit(env)
		NetProtocol.Msg.HW_EVENT:
			if NetProtocol.has_fields(data, { "id": TYPE_INT, "kind": [TYPE_STRING, 16], "level": TYPE_INT, "evading": TYPE_FLOAT, "text": [TYPE_STRING, 64] }) \
					and data.kind in ["heat", "busted", "evaded"]:
				highway_event.emit({ "id": data.id, "kind": data.kind, "level": clampi(data.level, 0, 5), "evading": clampf(data.evading, 0.0, 1.0),
					"text": NetChat.clean(String(data.text)) })
		NetProtocol.Msg.BOARD:
			if NetProtocol.has_fields(data, { "board": [TYPE_STRING, 160], "entries": [TYPE_ARRAY, Leaderboard.KEEP] }):
				var entries := (data.entries as Array).filter(func(e: Variant) -> bool: return e is Dictionary).map(func(e: Dictionary) -> Dictionary:
					return { "name": NetProtocol.clean_name(String(e.get("name", ""))), "car": String(e.get("car", "")).left(64),
						"time": float(e.get("time", 0.0)), "score": int(e.get("score", 0)) })
				board_received.emit(String(data.board), entries)
		NetProtocol.Msg.RACE_BEGIN, NetProtocol.Msg.RESULTS, NetProtocol.Msg.NOTE:
			if type == NetProtocol.Msg.RACE_BEGIN:
				race_begin = data
			race_message.emit(type, data)
