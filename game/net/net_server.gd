class_name NetServer
extends Node
## The server side of online play (docs/NETWORKING.md, MP-01, MP-02): an ENet host that lets
## clients in after the join checks (D81), keeps the players, and passes messages on. The same
## code runs inside a player's game (a listen server, whose own players are on peer 1) and in the
## dedicated server. Polled every physics tick before anything reads input, or by hand in tests.

signal peer_joined(peer: int)
## `names`: its players, as "Ann, Bo".
signal peer_left(peer: int, reason: String, names: String)
## A control message from a client.
signal message(peer: int, type: int, data: Dictionary)
## A car-state or content packet from a client (first byte: its type).
signal raw(peer: int, bytes: PackedByteArray)
signal log_line(text: String)

const AUTH_TIMEOUT_S := 10.0
## A rejected or kicked client gets this long to receive why before it's cut off.
const DROP_DELAY_MS := 400
## Control messages a client may send per second before it's kicked.
const MAX_CONTROL_PER_S := 120
## Colours for players whose own colour is taken (16, far apart).
const COLORS := [
	Color("#e6194b"), Color("#3cb44b"), Color("#ffe119"), Color("#4363d8"), Color("#f58231"), Color("#911eb4"),
	Color("#46f0f0"), Color("#f032e6"), Color("#bcf60c"), Color("#fabebe"), Color("#008080"), Color("#e6beff"),
	Color("#9a6324"), Color("#fffac8"), Color("#aaffc3"), Color("#ffffff"),
]

class PeerInfo:
	var fingerprint := ""
	var public_pem := ""
	var address := ""
	var nonce := PackedByteArray()
	var admin := false
	var players := PackedInt32Array()
	## Passed the join checks.
	var joined := false
	## Connected: messages can be sent.
	var connected := false
	var control_count := 0
	var control_window := 0

var config: ServerConfig
var identity: NetIdentity
var api := SceneMultiplayer.new()
var enet: ENetMultiplayerPeer
## peer id -> PeerInfo (authenticating ones too).
var peers := {}
## player id -> NetPlayer, in joining order.
var players := {}
## Tests poll by hand.
var manual_poll := false

var _drops := {} # peer -> time (ms) to cut it off
var _next_id := 1
var _polling := false
var _stop_after_poll := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -95 # before players' input and the race


## Opens the port and lets clients in. `local` are this machine's players ([{name, color}]) on a
## listen server; empty on a dedicated server.
func start(cfg: ServerConfig, ident: NetIdentity, local: Array = []) -> Error:
	config = cfg
	identity = ident
	enet = ENetMultiplayerPeer.new()
	enet.set_bind_ip("*")
	var err := enet.create_server(config.port, NetProtocol.MAX_PLAYERS + 4, NetProtocol.EXTRA_CHANNELS)
	if err != OK:
		log_line.emit("Can't open UDP %d: %s" % [config.port, error_string(err)])
		return err
	api.root_path = NodePath("/root") # no RPCs, but SceneMultiplayer wants one
	api.allow_object_decoding = false
	api.server_relay = false
	api.auth_timeout = AUTH_TIMEOUT_S
	api.auth_callback = _on_auth
	api.peer_authenticating.connect(_on_authenticating)
	api.peer_authentication_failed.connect(func(id: int) -> void: _forget(id, "Join timed out"))
	api.peer_connected.connect(_on_connected)
	api.peer_disconnected.connect(func(id: int) -> void: _forget(id, "Left"))
	api.peer_packet.connect(_on_packet)
	api.multiplayer_peer = enet
	var host := PeerInfo.new()
	host.joined = true
	host.connected = true
	host.fingerprint = identity.fingerprint if identity else ""
	host.admin = true
	peers[1] = host
	for i in mini(local.size(), NetProtocol.MAX_LOCAL):
		_add_player(1, i, local[i], host)
	log_line.emit("Server \"%s\" on UDP %d" % [config.name, config.port])
	return OK


## Closes the server. Safe inside a signal from poll(): it closes once poll() returns.
func stop() -> void:
	if _polling:
		_stop_after_poll = true
		return
	for id: int in peers.keys():
		send(id, NetProtocol.Msg.BYE, { "reason": "Server closed" })
	if enet:
		api.poll()
		enet.close()
	api.multiplayer_peer = null
	peers.clear()
	players.clear()


func _physics_process(_delta: float) -> void:
	if not manual_poll:
		poll()


func poll() -> void:
	if api.multiplayer_peer == null:
		return
	_polling = true
	api.poll()
	_polling = false
	if _stop_after_poll:
		_stop_after_poll = false
		stop()
		return
	if not _drops.is_empty():
		var now := Time.get_ticks_msec()
		for id: int in _drops.keys():
			if now >= _drops[id]:
				_drops.erase(id)
				if peers.has(id) or id in api.get_authenticating_peers():
					api.disconnect_peer(id)


func player_count() -> int:
	return players.size()


## Players on `peer`, in their local order.
func players_of(peer: int) -> Array[NetPlayer]:
	var out: Array[NetPlayer] = []
	if peers.has(peer):
		for id in peers[peer].players:
			out.append(players[id])
	return out


func is_admin(peer: int) -> bool:
	return peers.has(peer) and peers[peer].admin


## Whether ENet still has `peer` connected (a client that quit may not be forgotten yet).
func _open(peer: int) -> bool:
	if peer == 1 or not peers.has(peer) or not peers[peer].connected or _drops.has(peer):
		return false
	var p := enet.get_peer(peer) if enet else null
	return p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED


func send(peer: int, type: int, data: Dictionary) -> void:
	if not _open(peer):
		return # the server's own players are handled in process
	api.send_bytes(NetProtocol.encode(type, data), peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_CONTROL)


## To every joined client except `except`.
func broadcast(type: int, data: Dictionary, except := 0) -> void:
	var bytes := NetProtocol.encode(type, data)
	for id: int in peers:
		if id != except and _open(id):
			api.send_bytes(bytes, id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_CONTROL)


## Packed binary to a client: car states or content, unreliable and sequenced (a late packet is
## dropped). Unsequenced packets (TRANSFER_MODE_UNRELIABLE) aren't used: from client to server
## ENet lost a share of them even on a perfect link (Godot 4.7).
func send_raw(peer: int, bytes: PackedByteArray, channel: int, mode := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED) -> void:
	if _open(peer):
		api.send_bytes(bytes, peer, mode, channel)


## Round-trip time to a client in ms (0 for the server's own players).
func rtt_ms(peer: int) -> float:
	var p := enet.get_peer(peer) if enet and peer != 1 else null
	return p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if p else 0.0


func address_of(peer: int) -> String:
	return peers[peer].address if peers.has(peer) else ""


func kick(peer: int, reason := "Kicked") -> void:
	if peer == 1 or not peers.has(peer):
		return
	log_line.emit("Kicked %s: %s" % [_who(peer), reason])
	_drop(peer, reason)


## Kicks and bans the connection's key (saved to the config file, if there is one).
func ban(peer: int, reason := "Banned") -> void:
	if peer == 1 or not peers.has(peer):
		return
	var fp: String = peers[peer].fingerprint
	if fp and fp not in config.bans:
		config.bans.append(fp)
		config.save()
	log_line.emit("Banned %s (%s)" % [_who(peer), NetIdentity.short(fp)])
	_drop(peer, reason)


func _drop(peer: int, reason: String) -> void:
	send(peer, NetProtocol.Msg.BYE, { "reason": reason })
	_drops[peer] = Time.get_ticks_msec() + DROP_DELAY_MS


func _who(peer: int) -> String:
	var names := PackedStringArray()
	for p in players_of(peer):
		names.append(p.name)
	return ", ".join(names) if not names.is_empty() else "peer %d" % peer


func _on_authenticating(id: int) -> void:
	var info := PeerInfo.new()
	info.nonce = NetAuth.nonce()
	var p := enet.get_peer(id)
	if p:
		info.address = p.get_remote_address()
		p.throttle_configure(NetProtocol.THROTTLE_INTERVAL_MS, 32, 0) # never let ENet's throttle drop car states
	peers[id] = info
	api.send_auth(id, NetProtocol.encode(NetProtocol.Msg.CHALLENGE, {
		"protocol": NetProtocol.VERSION, "game": NetProtocol.game_version(), "nonce": info.nonce,
		"password": not config.password.is_empty(), "name": config.name,
	}))


func _on_auth(id: int, bytes: PackedByteArray) -> void:
	var info: PeerInfo = peers.get(id)
	var msg := NetProtocol.decode(bytes, NetProtocol.MAX_AUTH_BYTES)
	if info == null or info.joined or msg.is_empty() or msg.type != NetProtocol.Msg.HELLO:
		_reject(id, "Bad hello")
		return
	var d: Dictionary = msg.data
	if not NetProtocol.has_fields(d, { "protocol": TYPE_INT, "game": [TYPE_STRING, 32] }) \
			or d.protocol != NetProtocol.VERSION or d.game != NetProtocol.game_version():
		_reject(id, "Version mismatch (server %s)" % NetProtocol.game_version())
		return
	if not NetProtocol.has_fields(d, {
		"key": [TYPE_STRING, NetIdentity.MAX_PUBLIC_PEM], "signature": [TYPE_PACKED_BYTE_ARRAY, 1024],
		"proof": [TYPE_PACKED_BYTE_ARRAY, 64], "players": [TYPE_ARRAY, NetProtocol.MAX_LOCAL],
	}) or (d.players as Array).is_empty():
		_reject(id, "Bad hello")
		return
	if not NetIdentity.verify(d.key, info.nonce, d.signature):
		_reject(id, "Bad key")
		return
	var fp := NetIdentity.fingerprint_of(d.key)
	if config.is_banned(fp):
		_reject(id, "Banned")
		return
	if not config.is_allowed(fp):
		_reject(id, "Not on the whitelist")
		return
	if not NetAuth.check_password(config.password, info.nonce, d.proof):
		_reject(id, "Wrong password")
		return
	for other: int in peers:
		if other != id and peers[other].joined and peers[other].fingerprint == fp:
			_reject(id, "Already on this server")
			return
	var wanted: Array = d.players
	if player_count() + wanted.size() > config.max_players:
		_reject(id, "Server full")
		return
	for entry: Variant in wanted:
		if not entry is Dictionary or not NetProtocol.has_fields(entry, { "name": [TYPE_STRING, 64], "color": [TYPE_STRING, 8] }):
			_reject(id, "Bad hello")
			return
	info.fingerprint = fp
	info.public_pem = d.key
	info.admin = config.is_admin(fp)
	info.joined = true
	for i in wanted.size():
		_add_player(id, i, wanted[i], info)
	api.send_auth(id, NetProtocol.encode(NetProtocol.Msg.ACCEPT, {
		"name": config.name, "players": info.players, "admin": info.admin, "motd": config.motd,
		"server_fp": identity.fingerprint if identity else "",
	}))
	api.complete_auth(id)


func _reject(id: int, reason: String) -> void:
	log_line.emit("Refused %s: %s" % [peers[id].address if peers.has(id) else "peer %d" % id, reason])
	api.send_auth(id, NetProtocol.encode(NetProtocol.Msg.REJECT, { "reason": reason }))
	_drops[id] = Time.get_ticks_msec() + DROP_DELAY_MS


## A player joins on `peer` (at start, or a local guest later). Names are made unique ("Ann 2").
func add_player(peer: int, entry: Dictionary) -> NetPlayer:
	if not peers.has(peer) or peers[peer].players.size() >= NetProtocol.MAX_LOCAL or player_count() >= config.max_players:
		return null
	var used := []
	for id in peers[peer].players:
		used.append(players[id].local_index)
	var index := 0
	while index in used:
		index += 1
	return _add_player(peer, index, entry, peers[peer])


func remove_player(id: int) -> void:
	var p: NetPlayer = players.get(id)
	if p == null:
		return
	players.erase(id)
	if peers.has(p.peer):
		var list: PackedInt32Array = peers[p.peer].players
		list.remove_at(list.find(id))
		peers[p.peer].players = list


## `name`, or "name 2", "name 3"… if someone already has it.
func unique_name(name: String) -> String:
	var taken := {}
	for p: NetPlayer in players.values():
		taken[p.name.to_lower()] = true
	if not taken.has(name.to_lower()):
		return name
	var n := 2
	while taken.has(("%s %d" % [name.left(NetProtocol.MAX_NAME - 3), n]).to_lower()):
		n += 1
	return "%s %d" % [name.left(NetProtocol.MAX_NAME - 3), n]


## `wanted`, unless another player has it: then the first colour of COLORS nobody has.
func free_color(wanted: Color) -> Color:
	var used := {}
	for p: NetPlayer in players.values():
		used[p.color.to_html(false)] = true
	if not used.has(wanted.to_html(false)):
		return wanted
	for c: Color in COLORS:
		if not used.has(c.to_html(false)):
			return c
	return wanted


## The player called `name` (ignoring case), its id as text, or null.
func find_player(name: String) -> NetPlayer:
	for p: NetPlayer in players.values():
		if p.name.to_lower() == name.strip_edges().to_lower() or str(p.id) == name.strip_edges():
			return p
	return null


func _add_player(peer: int, local_index: int, entry: Dictionary, info: PeerInfo) -> NetPlayer:
	var p := NetPlayer.new()
	p.id = _free_id()
	p.peer = peer
	p.local_index = local_index
	p.name = unique_name(NetProtocol.clean_name(String(entry.get("name", ""))))
	p.color = free_color(Color.from_string(String(entry.get("color", "")), Color.WHITE))
	p.fingerprint = info.fingerprint
	p.admin = info.admin
	players[p.id] = p
	info.players.append(p.id)
	return p


func _free_id() -> int:
	var top := NetProtocol.FIRST_AI_ID - 1 # the rest are AI cars'
	for i in top:
		var id := (_next_id + i - 1) % top + 1
		if not players.has(id):
			_next_id = id % top + 1
			return id
	return 0


func _on_connected(id: int) -> void:
	if not peers.has(id) or not peers[id].joined:
		api.disconnect_peer(id)
		return
	peers[id].connected = true
	log_line.emit("Joined: %s from %s (%s)" % [_who(id), peers[id].address, NetIdentity.short(peers[id].fingerprint)])
	peer_joined.emit(id)


func _forget(id: int, reason: String) -> void:
	_drops.erase(id)
	var info: PeerInfo = peers.get(id)
	if info == null:
		return
	var was_joined := info.connected
	var who := _who(id)
	if was_joined:
		log_line.emit("Left: %s (%s)" % [who, reason])
	for pid in info.players:
		players.erase(pid)
	peers.erase(id)
	if was_joined:
		peer_left.emit(id, reason, who)


func _on_packet(id: int, bytes: PackedByteArray) -> void:
	var info: PeerInfo = peers.get(id)
	if info == null or not info.connected or bytes.is_empty() or _drops.has(id):
		return
	if bytes[0] >= NetProtocol.RAW_FIRST:
		raw.emit(id, bytes)
		return
	var now := Time.get_ticks_msec() / 1000
	if now != info.control_window:
		info.control_window = now
		info.control_count = 0
	info.control_count += 1
	if info.control_count > MAX_CONTROL_PER_S:
		kick(id, "Too many messages")
		return
	var msg := NetProtocol.decode(bytes)
	if not msg.is_empty():
		message.emit(id, msg.type, msg.data)
