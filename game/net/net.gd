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

const CHAT_KEEP := 100

var server: NetServer
var host_logic: NetHost
var client: NetClient
## The lobby as last sent by the server (NetHost.lobby_dict), and its players.
var lobby := {}
var roster: Array[NetPlayer] = []
## This game's players' ids on the server, in local order.
var my_ids := PackedInt32Array()
## Recent chat and server lines.
var chat_log: Array[Dictionary] = []
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
	host_logic = NetHost.new(server)
	host_logic.name = "NetHost"
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
	var err := client.join(host_name, port, local, password, identity())
	if err != OK:
		client.queue_free()
		client = null
	state_changed.emit()
	return err


func leave() -> void:
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


func say(text: String, local_index := 0) -> void:
	if local_index < my_ids.size():
		request(NetProtocol.Msg.CHAT, { "player": my_ids[local_index], "text": text })


func set_ready(on: bool) -> void:
	request(NetProtocol.Msg.READY, { "ready": on })


## Picks the car at `path` for this game's player `local_index`.
func pick_car(local_index: int, path: String) -> void:
	if local_index >= my_ids.size():
		return
	var m := PackageLoader.read_manifest(path)
	request(NetProtocol.Msg.PICK, { "player": my_ids[local_index], "car": package_hash(path),
		"car_name": String(m.get("name", path.get_file())).left(64), "family": String(m.get("family", "car")).left(16) })


func admin(cmd: String, target := "") -> void:
	request(NetProtocol.Msg.ADMIN, { "cmd": cmd, "target": target })


func add_local(entry: Dictionary) -> void:
	request(NetProtocol.Msg.ADD_LOCAL, entry)


func remove_local(local_index: int) -> void:
	if local_index < my_ids.size():
		request(NetProtocol.Msg.REMOVE_LOCAL, { "player": my_ids[local_index] })


func mute(id: int, on: bool) -> void:
	if on:
		muted[id] = true
	else:
		muted.erase(id)


## This machine's joined players as [{name, color}] for a server: the Players slots, or P1.
static func local_players() -> Array:
	var out := []
	for slot in Players.slots:
		if not slot.ai:
			out.append({ "name": slot.profile.display_name(), "color": slot.color().to_html(false) })
	if out.is_empty():
		out.append({ "name": Settings.primary.display_name(), "color": Palette.color(Settings.primary, "p1").to_html(false) })
	return out


## A package's hash ("sha256:" + its manifest's), as PackageLoader computes it; "" if unreadable.
static func package_hash(path: String) -> String:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if source.error or not source.has("manifest.json"):
		return ""
	var h := "sha256:" + PlatformLoader.sha256_hex(source.read("manifest.json"))
	source.close()
	return h


func _reset() -> void:
	lobby = {}
	roster.clear()
	my_ids = PackedInt32Array()
	chat_log.clear()
	muted.clear()


func _on_cut_off(reason: String) -> void:
	state_changed.emit()
	disconnected.emit(reason)


## A message from the server (or from this game's NetHost).
func _handle(type: int, data: Dictionary) -> void:
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
