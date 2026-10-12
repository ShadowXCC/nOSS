class_name NetHost
extends Node
## The game server's rules on top of NetServer (docs/NETWORKING.md §4–5, MP-06, MP-07): the
## lobby (players, their cars, who's ready), chat and its commands, kicks and bans, and which
## event runs next (the config's rotation). A listen server's own players are peer 1: their
## requests come in through handle(), and everything sent to all clients also reaches this
## game's Net (`local_sink`), so the menus work the same when hosting and when joined.

signal log_line(text: String)
## An admin asked for the session to start.
signal start_requested
## A client's car's assists (for results).
signal assists_reported(id: int, used: Dictionary)
## The router mapping's result (UPnP), as a short line for the host.
signal port_checked(ok: bool, message: String)

var server: NetServer
var config: ServerConfig
## Content transfer (set by Net before this enters the tree).
var content: NetContent
## Called with (type, data) for messages to this game's own players.
var local_sink := Callable()
## Which rotation item is up.
var rotation_index := 0
## "lobby" or "session".
var state := "lobby"
## peer -> true when that connection's players are ready.
var ready_peers := {}

var discovery: NetDiscovery.Responder
var upnp: UpnpMapper

var _chat := NetChat.Limiter.new()
var _ai: Array = [] # the session's AI cars (roster entries)
var _ai_paths := {} # AI car id -> its package here
var _in_session := {} # player ids in the session (a race takes no one mid-way)
var _dirty := false
var _names := {} # platform id -> display name
var _tracks := {} # track path (the config's) -> track_info()


func _init(p_server: NetServer) -> void:
	server = p_server
	config = p_server.config


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -94 # right after the server polls
	server.peer_joined.connect(_on_joined)
	server.peer_left.connect(_on_left)
	server.message.connect(handle)
	if content:
		content.car_refused.connect(_on_car_refused)
	_dirty = true
	if config.lan:
		discovery = NetDiscovery.Responder.new()
		discovery.name = "Discovery"
		add_child(discovery)
		if discovery.start(config.port, discovery_info) != OK:
			log_line.emit("LAN discovery off: UDP %d in use" % NetDiscovery.discovery_port(config.port))
	if config.upnp:
		upnp = UpnpMapper.new()
		upnp.name = "Upnp"
		add_child(upnp)
		upnp.done.connect(func(ok: bool, _ip: String, message: String) -> void:
			log_line.emit(message)
			port_checked.emit(ok, message))
		upnp.open(config.port)


func _physics_process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_to_all(NetProtocol.Msg.LOBBY, lobby_dict())


func platform_id() -> String:
	return String(config.rotation[rotation_index].get("class", "official.track.gt"))


## The current class's platform (official, or the server's own, PLT-09); a custom one is sent to
## players by hash.
func platform_result() -> PlatformLoader.Result:
	var r := config.platform(rotation_index)
	if r.ok() and not r.path.begins_with(PlatformLoader.OFFICIAL_DIR) and content:
		content.share_file(r.path)
	return r


## Where the session's track is here (what track_info() settled on).
func track_path() -> String:
	return String(track_info().path)


## The current track as it goes to players (EDT-08): {path, hash, id, name, bytes}. A track that
## can't go online (personal use, over the size cap, unreadable) gives way to the default one,
## with a log line. The track is offered to anyone who asks for it by hash.
func track_info() -> Dictionary:
	var path := config.track_path(rotation_index)
	if not _tracks.has(path):
		_tracks[path] = _make_track_info(path)
		if content and _tracks[path].hash:
			content.share_track(_tracks[path].path)
	return _tracks[path]


func _make_track_info(path: String) -> Dictionary:
	var source := path
	if path.ends_with(".json"):
		source = _package_json(path)
	var m := TrackLoader.read_manifest(source) if source else {}
	var bytes := NetContent.package_bytes(source, TrackLoader.LIMITS) if not m.is_empty() else 0
	var why := ""
	if m.is_empty():
		why = "Track not found"
	elif not ContentIndex.shareable(m):
		why = "Personal-use tracks stay offline"
	elif bytes > int(config.caps.get("max_track_mb", 100)) << 20:
		why = "Track too large"
	if why:
		log_line.emit("%s: %s" % [why, path])
		var fallback := TrackLibrary.DEFAULT
		return _make_track_info(fallback) if path != fallback else { "path": fallback, "hash": "", "id": "", "name": "", "bytes": 0 }
	return { "path": source, "hash": TrackLibrary.manifest_hash(source), "id": String(m.get("id", "")),
		"name": String(m.get("name", source.get_file())), "bytes": bytes }


## A bare track.json (no manifest) as a package in the cache, so it can be sent by hash.
func _package_json(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var layout: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not layout is Dictionary:
		return ""
	if layout.get("schema") == TrackFormat.LEGACY:
		layout = TrackFormat.upgrade_v0(layout)
		bytes = PackageWriter.canonical_json(layout).to_utf8_buffer()
	var dir := ContentStore.root.path_join("hosted").path_join(PlatformLoader.sha256_hex(bytes).left(16))
	if not FileAccess.file_exists(dir.path_join("manifest.json")):
		var info := { "id": String(layout.get("id", "")), "version": 1, "name": String(layout.get("name", path.get_file().get_basename())),
			"author": "Unknown", "license": "CC-BY-SA-4.0", "created": Time.get_date_string_from_unix_time(FileAccess.get_modified_time(path)) }
		if TrackWriter.write_folder(dir, info, { "track.json": bytes }):
			return ""
	return dir


func event() -> RaceEvent:
	return config.event(rotation_index)


## What every client's lobby shows.
func lobby_dict() -> Dictionary:
	var players := []
	for p: NetPlayer in server.players.values():
		var d := p.to_dict()
		d.ready = ready_peers.get(p.peer, false)
		players.append(d)
	return {
		"name": config.name, "motd": config.motd, "state": state, "max": config.max_players,
		"track": track_info().hash, "track_id": track_info().id, "track_name": track_info().name, "track_bytes": track_info().bytes,
		"class": platform_id(), "class_name": _class_name(platform_id()), "class_hash": platform_result().hash,
		"event": event().to_dict(), "players": players,
		"rules": { "own_sounds": config.caps.own_sounds, "custom_platforms": config.caps.custom_platforms,
			"max_package_mb": config.caps.max_package_mb, "tuning": config.rules.tuning },
	}


## The answer to LAN discovery.
func discovery_info() -> Dictionary:
	return {
		"name": config.name, "port": config.port, "players": server.player_count(), "max": config.max_players,
		"password": not config.password.is_empty(), "track": track_info().name, "class": _class_name(platform_id()),
		"state": state, "version": NetProtocol.game_version(),
		"fp": NetIdentity.short(server.identity.fingerprint) if server.identity else "",
	}


## A request from a client, or from this game's own players (peer 1).
func handle(peer: int, type: int, data: Dictionary) -> void:
	if peer != 1 and content and content.handle_control(peer, type, data):
		return
	match type:
		NetProtocol.Msg.PICK:
			if NetProtocol.has_fields(data, { "player": TYPE_INT, "car": [TYPE_STRING, 80], "car_name": [TYPE_STRING, 64], "family": [TYPE_STRING, 16] }):
				_pick(peer, data)
		NetProtocol.Msg.READY:
			if NetProtocol.has_fields(data, { "ready": TYPE_BOOL }):
				ready_peers[peer] = data.ready
				_dirty = true
		NetProtocol.Msg.CHAT:
			if NetProtocol.has_fields(data, { "player": TYPE_INT, "text": [TYPE_STRING, NetChat.MAX_CHARS * 2] }):
				chat(peer, data.player, data.text)
		NetProtocol.Msg.ADMIN:
			if NetProtocol.has_fields(data, { "cmd": [TYPE_STRING, 16], "target": [TYPE_STRING, 64] }):
				admin(peer, data.cmd, data.target)
		NetProtocol.Msg.ADD_LOCAL:
			if NetProtocol.has_fields(data, { "name": [TYPE_STRING, 64], "color": [TYPE_STRING, 8] }):
				var p := server.add_player(peer, data)
				if p == null:
					_notice(peer, "Server full")
				else:
					_say("%s joined" % p.name)
					_send_ids(peer)
					_dirty = true
		NetProtocol.Msg.ASSISTS:
			if NetProtocol.has_fields(data, { "id": TYPE_INT, "used": TYPE_DICTIONARY }) and _owns(peer, data.id):
				var used := {}
				for key: Variant in data.used:
					if key is String and (key in ResultsMenu.ASSIST_NAMES) and data.used[key] is bool:
						used[key] = data.used[key]
				assists_reported.emit(data.id, used)
		NetProtocol.Msg.REMOVE_LOCAL:
			if NetProtocol.has_fields(data, { "player": TYPE_INT }) and _owns(peer, data.player) and server.players_of(peer).size() > 1:
				var name: String = server.players[data.player].name
				server.remove_player(data.player)
				_say("%s left" % name)
				_send_ids(peer)
				_dirty = true


## A chat line from `player` on `peer`, or a command if it starts with "/".
func chat(peer: int, player: int, text: String) -> void:
	if not _owns(peer, player):
		return
	var line := NetChat.clean(text)
	if line.is_empty():
		return
	if not _chat.allow(peer, Time.get_ticks_msec() / 1000.0):
		_notice(peer, "Slow down")
		return
	var cmd := NetChat.command(line)
	if not cmd.is_empty():
		admin(peer, cmd.cmd, cmd.arg)
		return
	var p: NetPlayer = server.players[player]
	log_line.emit("<%s> %s" % [p.name, line])
	_to_all(NetProtocol.Msg.CHAT_LINE, { "from": p.id, "name": p.name, "color": p.color.to_html(false), "text": line, "kind": "chat" })


## Admin commands: kick and ban (a player's name or id), start, next, restart. Peer 1 (the host,
## or the dedicated server's console) may always use them.
func admin(peer: int, cmd: String, target := "") -> void:
	if cmd == "help":
		_notice(peer, NetChat.COMMANDS.help)
		return
	if not NetChat.COMMANDS.has(cmd):
		_notice(peer, "Unknown command")
		return
	if not server.is_admin(peer):
		_notice(peer, "Admins only")
		return
	match cmd:
		"kick", "ban":
			var p := server.find_player(target)
			if p == null:
				_notice(peer, "No such player")
			elif p.peer == 1:
				_notice(peer, "Can't %s the host" % cmd)
			else:
				var name := p.name
				_say("%s was %s" % [name, "kicked" if cmd == "kick" else "banned"])
				if cmd == "kick":
					server.kick(p.peer, "Kicked")
				else:
					server.ban(p.peer, "Banned")
		"start", "restart":
			start_requested.emit()
			start_session()
		"next":
			if state == "session":
				end_session()
			next_event()


## Starts the rotation's current event for everyone in the lobby.
func start_session() -> void:
	_in_session.clear()
	for id: int in server.players:
		_in_session[id] = true
	_ai = []
	state = "session"
	_to_all(NetProtocol.Msg.SESSION, session_dict())
	log_line.emit("Session: %s, %s, %s" % [track_info().name, _class_name(platform_id()), event().kind])
	_dirty = true


## Back to the lobby.
func end_session() -> void:
	if state != "session":
		return
	state = "lobby"
	_ai = []
	ready_peers.clear()
	_to_all(NetProtocol.Msg.SESSION_END, {})
	_dirty = true


## What a session needs: track, class, event and everyone's car, in grid order.
func session_dict() -> Dictionary:
	if state != "session" or _ai.is_empty():
		_ai = _ai_entries()
	var t := track_info()
	return { "track": t.hash, "track_id": t.id, "track_name": t.name, "track_bytes": t.bytes,
		"class": platform_id(), "class_hash": platform_result().hash, "event": event().to_dict(), "roster": roster(), "rules": rules_dict() }


## The server's rules a session follows (MP-06).
func rules_dict() -> Dictionary:
	return {
		"assists": config.rules.assists if config.rules.get("assists") is Array else null,
		"tuning": config.rules.tuning, "fitting": config.rules.fitting, "hotswap": config.rules.hotswap,
		"own_sounds": config.caps.own_sounds,
	}


## The session's players, then the AI cars the server runs (races).
func roster() -> Array:
	var out := []
	for p: NetPlayer in server.players.values():
		if state != "session" or _in_session.has(p.id):
			out.append(p.to_dict())
	out.append_array(_ai)
	return out


## Where AI car `id`'s package is here.
func ai_path(id: int) -> String:
	return String(_ai_paths.get(id, ""))


## AI cars for a race (D88): the event's count, fewer if the grid would pass 16 cars; built-in
## cars or the server's garage cars the class takes (those travel like players' cars).
func _ai_entries() -> Array:
	var e := event()
	var out := []
	_ai_paths.clear()
	if e.kind != "race":
		return out
	var count := mini(e.ai_count, NetProtocol.MAX_PLAYERS - server.player_count())
	if count <= 0:
		return out
	var platform := platform_result()
	var pool := []
	for path in PackageLoader.list_available():
		if e.ai_cars == "builtin" and not path.begins_with("res://"):
			continue
		var m := PackageLoader.read_manifest(path)
		if platform.ok() and Fitting.compatible(platform.platform, m.get("family", "")) and ContentIndex.shareable(m):
			pool.append([path, m])
	if pool.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var skills := []
	for i in count:
		skills.append(clampf(e.ai_skill + 10.0 * (0.5 - float(i) / maxf(count - 1, 1)), 0.0, 100.0))
	skills.shuffle()
	pool.shuffle() # every car once before any twice
	for i in count:
		var pick: Array = pool[i % pool.size()]
		var h := ContentIndex.package_hash(pick[0])
		if content:
			content.share_car(h)
		out.append({
			"id": NetProtocol.FIRST_AI_ID + i, "peer": 1, "local": i, "name": AiRacer.NAMES[i % AiRacer.NAMES.size()],
			"color": AiRacer.COLOR.to_html(false), "fp": "", "admin": false, "car": h,
			"car_name": String(pick[1].get("name", "")).left(64), "family": String(pick[1].get("family", "car")).left(16),
			"car_note": "", "ready": true, "ai": true, "skill": skills[i],
		})
		_ai_paths[NetProtocol.FIRST_AI_ID + i] = pick[0]
	return out


## The next event in the rotation (back in the lobby).
func next_event() -> void:
	rotation_index = (rotation_index + 1) % config.rotation.size()
	state = "lobby"
	ready_peers.clear()
	_say("Next: %s, %s" % [track_info().name, _class_name(platform_id())])
	_dirty = true


## A line from the server to everyone.
func say(text: String) -> void:
	_say(text)


## Everyone's players are ready (and there's someone to race).
func all_ready() -> bool:
	if server.player_count() == 0:
		return false
	for peer: int in server.peers:
		if not server.peers[peer].players.is_empty() and not ready_peers.get(peer, false):
			return false
	return true


func _pick(peer: int, data: Dictionary) -> void:
	if not _owns(peer, data.player):
		return
	var family := String(data.family)
	var platform := platform_result()
	if platform.ok() and not Fitting.compatible(platform.platform, family):
		_notice(peer, "Car doesn't fit this class")
		return
	var p: NetPlayer = server.players[data.player]
	p.car = data.car if ContentStore.valid_hash(String(data.car)) else ""
	p.car_name = NetChat.clean(data.car_name).left(64)
	p.family = family
	p.car_note = ""
	var bytes := int(data.get("bytes", -1)) if data.get("bytes") is int else -1
	if content and p.car:
		var cap := int(config.caps.max_package_mb) << 20
		if bytes > cap:
			p.car_note = "Car too large for this server"
			_notice(peer, p.car_note)
		elif peer == 1:
			content.share_car(p.car)
		else:
			content.fetch_car(p.car, peer, "full", bytes)
	_roster_changed()
	_dirty = true


func _on_car_refused(car_hash: String, reason: String) -> void:
	for p: NetPlayer in server.players.values():
		if p.car == car_hash and p.car_note.is_empty():
			p.car_note = reason
			_notice(p.peer, reason)
	_roster_changed()
	_dirty = true


func _owns(peer: int, player: int) -> bool:
	return server.players.has(player) and server.players[player].peer == peer


func _on_joined(peer: int) -> void:
	var names := PackedStringArray()
	for p in server.players_of(peer):
		names.append(p.name)
	_say("%s joined" % ", ".join(names))
	if config.motd:
		_notice(peer, config.motd)
	if state == "session" and event().kind != "race": # joins the drive in progress
		for p in server.players_of(peer):
			_in_session[p.id] = true
		server.send(peer, NetProtocol.Msg.SESSION, session_dict())
		_roster_changed(peer)
	elif state == "session":
		_notice(peer, "Race on: you're in the next one")
	_dirty = true


## Everyone already in the session hears who's in it now.
func _roster_changed(except := 0) -> void:
	if state != "session":
		return
	var data := { "roster": roster() }
	server.broadcast(NetProtocol.Msg.ROSTER, data, except)
	if local_sink.is_valid():
		local_sink.call(NetProtocol.Msg.ROSTER, data)


func _on_left(peer: int, reason: String, names: String) -> void:
	ready_peers.erase(peer)
	_chat.forget(peer)
	if reason in ["Left", "Kicked", "Banned"]:
		_say("%s left" % names)
	else:
		_say("%s left (%s)" % [names, reason.to_lower()])
	_roster_changed()
	_dirty = true


func _say(text: String) -> void:
	_to_all(NetProtocol.Msg.CHAT_LINE, { "from": 0, "name": "", "color": "", "text": text, "kind": "server" })


func _notice(peer: int, text: String) -> void:
	if peer == 1:
		if local_sink.is_valid():
			local_sink.call(NetProtocol.Msg.NOTICE, { "text": text })
	else:
		server.send(peer, NetProtocol.Msg.NOTICE, { "text": text })


func _send_ids(peer: int) -> void:
	var ids := PackedInt32Array()
	for p in server.players_of(peer):
		ids.append(p.id)
	if peer == 1:
		if local_sink.is_valid():
			local_sink.call(NetProtocol.Msg.YOUR_PLAYERS, { "players": ids })
	else:
		server.send(peer, NetProtocol.Msg.YOUR_PLAYERS, { "players": ids })


## To every client and this game's own players.
func _to_all(type: int, data: Dictionary) -> void:
	server.broadcast(type, data)
	if local_sink.is_valid():
		local_sink.call(type, data)


func _class_name(id: String) -> String:
	if not _names.has(id):
		var r := platform_result() if id == platform_id() else PlatformLoader.load_official(id)
		_names[id] = String(r.platform.get("name", id)) if r.ok() else id
	return _names[id]
