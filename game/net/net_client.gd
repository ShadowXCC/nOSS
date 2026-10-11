class_name NetClient
extends Node
## The client side of online play (docs/NETWORKING.md §5): connects to a server, proves its key
## and password (D81), and passes messages on. One connection carries up to four local players
## (LOC-05). Polled every physics tick before anything reads input, or by hand in tests.

## Let in: the server's ACCEPT ({name, players: [ids], admin, motd, server_fp}).
signal joined(info: Dictionary)
## Couldn't join (no answer, refused, version mismatch, password needed…).
signal failed(reason: String)
## Cut off after joining (kicked, server closed, connection lost).
signal left(reason: String)
signal message(type: int, data: Dictionary)
## A car-state or content packet from the server (first byte: its type).
signal raw(bytes: PackedByteArray)

enum State { IDLE, CONNECTING, JOINED }

## ENet timeouts (retry limit, least and most ms): while connecting, give up after the fourth try
## (about 3.5 s: "Server not found"); once joined, "Connection lost" within 15 s.
const CONNECT_TIMEOUT := [4, 3000, 8000]
const JOINED_TIMEOUT := [32, 5000, 15000]

var identity: NetIdentity
var api := SceneMultiplayer.new()
var enet: ENetMultiplayerPeer
var state := State.IDLE
## The server's ACCEPT, and its CHALLENGE (name, password needed).
var info := {}
var server_name := ""
var needs_password := false
var manual_poll := false

var _players: Array = []
var _password := ""
var _reason := ""
var _polling := false
var _close_after_poll := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -95


## Connects to `host`:`port` with `players` ([{name, color}], 1-4).
func join(host: String, port: int, players: Array, password := "", ident: NetIdentity = null) -> Error:
	leave()
	identity = ident
	_players = players.slice(0, NetProtocol.MAX_LOCAL)
	_password = password
	_reason = ""
	info = {}
	enet = ENetMultiplayerPeer.new()
	var err := enet.create_client(host, port, NetProtocol.EXTRA_CHANNELS)
	if err != OK:
		return err
	for p: ENetPacketPeer in enet.host.get_peers(): # the server, still connecting
		p.set_timeout(CONNECT_TIMEOUT[0], CONNECT_TIMEOUT[1], CONNECT_TIMEOUT[2])
	api = SceneMultiplayer.new()
	api.root_path = NodePath("/root")
	api.allow_object_decoding = false
	api.auth_timeout = NetServer.AUTH_TIMEOUT_S
	api.auth_callback = _on_auth
	# As soon as ENet is connected: its throttle drops unreliable packets while the round trip
	# grows, and it had fallen to 2/32 by the end of the join, losing most car states and acks.
	api.peer_authenticating.connect(func(_id: int) -> void:
		var p := enet.get_peer(1) if enet else null
		if p:
			p.throttle_configure(NetProtocol.THROTTLE_INTERVAL_MS, 32, 0))
	api.peer_authentication_failed.connect(func(_id: int) -> void: _fail(_reason if _reason else "Server didn't answer"))
	api.connected_to_server.connect(_on_connected)
	api.connection_failed.connect(func() -> void: _fail(_reason if _reason else "Server not found"))
	api.server_disconnected.connect(_on_server_disconnected)
	api.peer_packet.connect(_on_packet)
	api.multiplayer_peer = enet
	state = State.CONNECTING
	return OK


## Disconnects. Safe inside a signal from poll(): the peer closes once poll() returns.
func leave() -> void:
	state = State.IDLE
	if _polling:
		_close_after_poll = true
		return
	if enet:
		enet.close()
	if api:
		api.multiplayer_peer = null
	enet = null


func _physics_process(_delta: float) -> void:
	if not manual_poll:
		poll()


func poll() -> void:
	if state != State.IDLE and api.multiplayer_peer:
		_polling = true
		api.poll()
		_polling = false
	if _close_after_poll:
		_close_after_poll = false
		leave()


func send(type: int, data: Dictionary) -> void:
	if state == State.JOINED:
		api.send_bytes(NetProtocol.encode(type, data), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_CONTROL)


## Packed binary to the server: car states or content, unreliable and sequenced (a late packet
## is dropped; see NetServer.send_raw).
func send_raw(bytes: PackedByteArray, channel: int, mode := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED) -> void:
	if state == State.JOINED:
		api.send_bytes(bytes, 1, mode, channel)


## Round-trip time to the server in ms.
func rtt_ms() -> float:
	var p := enet.get_peer(1) if enet else null
	return p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if p else 0.0


## This connection's players' ids on the server.
func player_ids() -> PackedInt32Array:
	return PackedInt32Array(info.get("players", []))


func _on_auth(_id: int, bytes: PackedByteArray) -> void:
	var msg := NetProtocol.decode(bytes, NetProtocol.MAX_AUTH_BYTES)
	if msg.is_empty():
		_fail("Bad answer from server")
		return
	var d: Dictionary = msg.data
	match msg.type:
		NetProtocol.Msg.CHALLENGE:
			if not NetProtocol.has_fields(d, { "protocol": TYPE_INT, "game": [TYPE_STRING, 32],
					"nonce": [TYPE_PACKED_BYTE_ARRAY, 64], "password": TYPE_BOOL, "name": [TYPE_STRING, 48] }):
				_fail("Bad answer from server")
				return
			server_name = d.name
			needs_password = d.password
			if d.protocol != NetProtocol.VERSION or d.game != NetProtocol.game_version():
				_fail("Version mismatch (server %s)" % d.game)
				return
			if needs_password and _password.is_empty():
				_fail("Password needed")
				return
			if identity == null:
				identity = NetIdentity.throwaway()
			var players := []
			for p: Dictionary in _players:
				players.append({ "name": String(p.get("name", "Player")).left(64), "color": String(p.get("color", "ffffff")).left(8) })
			api.send_auth(1, NetProtocol.encode(NetProtocol.Msg.HELLO, {
				"protocol": NetProtocol.VERSION, "game": NetProtocol.game_version(),
				"key": identity.public_pem, "signature": identity.sign(d.nonce),
				"proof": NetAuth.password_proof(_password, d.nonce), "players": players,
			}))
		NetProtocol.Msg.ACCEPT:
			if not NetProtocol.has_fields(d, { "name": [TYPE_STRING, 48], "players": [TYPE_PACKED_INT32_ARRAY, -1],
					"admin": TYPE_BOOL, "motd": [TYPE_STRING, 200] }) or (d.players as PackedInt32Array).size() != _players.size():
				_fail("Bad answer from server")
				return
			info = d
			api.complete_auth(1)
		NetProtocol.Msg.REJECT:
			_fail(String(d.get("reason", "Refused")).left(80))
		_:
			_fail("Bad answer from server")


func _on_connected() -> void:
	state = State.JOINED
	var p := enet.get_peer(1)
	if p:
		p.throttle_configure(NetProtocol.THROTTLE_INTERVAL_MS, 32, 0)
		p.set_timeout(JOINED_TIMEOUT[0], JOINED_TIMEOUT[1], JOINED_TIMEOUT[2])
	joined.emit(info)


func _on_server_disconnected() -> void:
	if state == State.JOINED:
		state = State.IDLE
		left.emit(_reason if _reason else "Connection lost")
	else:
		_fail(_reason if _reason else "Server closed the connection")


func _fail(reason: String) -> void:
	if state == State.IDLE:
		return
	_reason = reason
	leave()
	failed.emit(reason)


func _on_packet(_id: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	if bytes[0] >= NetProtocol.RAW_FIRST:
		raw.emit(bytes)
		return
	var msg := NetProtocol.decode(bytes)
	if msg.is_empty():
		return
	if msg.type == NetProtocol.Msg.BYE:
		_reason = String(msg.data.get("reason", "Disconnected")).left(80)
		if state == State.JOINED:
			leave()
			left.emit(_reason)
		return
	message.emit(msg.type, msg.data)
