class_name NetSession
extends Node
## Online play inside a track session (docs/NETWORKING.md §6, D84). Each game sends the states of
## the cars it drives: a client to the server, at 30 per second (60 on a fast link); the server
## sends everyone every other car's freshest states 60 times a second (a client's own cars
## excepted), its own cars (a listen host's players, AI) included. Remote cars are NetRacers. A
## client keeps the server's clock (ClockSync); the server's is its own.

const MSG_STATE := 100
const RELAY_HZ := 60.0
## Most states in one packet (44 bytes each): stays under ENet's fragment size.
const PER_PACKET := 24
## A placed car's states carry the teleport flag this many times (one may be lost).
const TELEPORT_REPEAT := 3

var session: TrackSession
## car id -> Racer: every car in the session.
var racers := {}
## car id -> Racer this game drives.
var owned := {}
## Sends own cars this many times a second (0: 60 if the round trip is under 30 ms, else 30).
var send_rate := 0
var clock := ClockSync.new()

var _send_time := 0.0
var _relay_time := 0.0
var _latest := {} # server: car id -> newest CarState (all cars)
var _relayed := {} # server: car id -> time of the state last relayed
var _resets := {} # car id -> [reset_count seen, teleport flags left to send]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -80 # after the network is polled, before remote cars move
	if Net.server:
		Net.server.raw.connect(_on_server_raw)
	elif Net.client:
		Net.client.raw.connect(_on_client_raw)


func _exit_tree() -> void:
	if Net.server and Net.server.raw.is_connected(_on_server_raw):
		Net.server.raw.disconnect(_on_server_raw)
	if Net.client and Net.client.raw.is_connected(_on_client_raw):
		Net.client.raw.disconnect(_on_client_raw)


func is_server() -> bool:
	return Net.server != null


## Server time now (seconds).
func now() -> float:
	return ClockSync.local_now() if is_server() else clock.now()


func add(r: Racer, own: bool) -> void:
	racers[r.net_id] = r
	if own:
		owned[r.net_id] = r
	elif r is NetRacer:
		(r as NetRacer).clock = now


func remove(id: int) -> void:
	racers.erase(id)
	owned.erase(id)
	_latest.erase(id)
	_relayed.erase(id)
	_resets.erase(id)


func _physics_process(delta: float) -> void:
	if is_server():
		_server_tick(delta)
	elif Net.client and Net.client.state == NetClient.State.JOINED:
		_client_tick(delta)


func _client_tick(delta: float) -> void:
	var ping := clock.ping_due()
	if not ping.is_empty():
		Net.client.send_raw(ping, NetProtocol.CH_STATE)
	if not clock.synced:
		return
	_send_time += delta
	var rate := send_rate if send_rate > 0 else (60 if clock.rtt < 0.03 else 30)
	if _send_time < 1.0 / rate:
		return
	_send_time = 0.0
	var states: Array[CarState] = []
	for id: int in owned:
		var s := _own_state(id)
		if s:
			states.append(s)
	for packet in pack(states):
		Net.client.send_raw(packet, NetProtocol.CH_STATE)


func _server_tick(delta: float) -> void:
	_relay_time += delta
	if _relay_time < 1.0 / RELAY_HZ:
		return
	_relay_time = 0.0
	# The server's own cars.
	for id: int in owned:
		var s := _own_state(id)
		if s:
			_latest[id] = s
	# Fresh states go to every client but the car's owner.
	var fresh: Array[CarState] = []
	for id: int in _latest:
		var s: CarState = _latest[id]
		if s.time > float(_relayed.get(id, -1.0)):
			_relayed[id] = s.time
			fresh.append(s)
	if fresh.is_empty():
		return
	for peer: int in Net.server.peers:
		if peer == 1 or not Net.server.peers[peer].connected:
			continue
		var theirs := fresh.filter(func(s: CarState) -> bool: return not _owned_by(s.id, peer))
		for packet in pack(theirs):
			Net.server.send_raw(peer, packet, NetProtocol.CH_STATE)


func _owned_by(id: int, peer: int) -> bool:
	var p: NetPlayer = Net.server.players.get(id)
	return p != null and p.peer == peer


## The state of a car this game drives, flagged ghosted, waiting or placed as it is.
func _own_state(id: int) -> CarState:
	var r: Racer = owned[id]
	if r.vehicle == null or not is_instance_valid(r.vehicle):
		return null
	var s := CarState.of(r.vehicle, id, now())
	if r.ghosted:
		s.flags |= CarState.FLAG_GHOSTED
	if r.waiting:
		s.flags |= CarState.FLAG_WAITING
	var seen: Array = _resets.get(id, [r.vehicle.reset_count, 0])
	if r.vehicle.reset_count != seen[0]:
		seen = [r.vehicle.reset_count, TELEPORT_REPEAT]
	if seen[1] > 0:
		s.flags |= CarState.FLAG_TELEPORT
		seen[1] -= 1
	_resets[id] = seen
	return s


## States packed into packets of at most PER_PACKET: [100][count u8][states…].
static func pack(states: Array[CarState]) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var i := 0
	while i < states.size():
		var n := mini(states.size() - i, PER_PACKET)
		var p := PackedByteArray()
		p.resize(2 + n * CarState.SIZE)
		p[0] = MSG_STATE
		p[1] = n
		for k in n:
			states[i + k].encode(p, 2 + k * CarState.SIZE)
		out.append(p)
		i += n
	return out


static func unpack(bytes: PackedByteArray, time_base: float) -> Array[CarState]:
	var out: Array[CarState] = []
	if bytes.size() < 2 or bytes[0] != MSG_STATE:
		return out
	var n := bytes[1]
	if bytes.size() != 2 + n * CarState.SIZE:
		return out
	for k in n:
		var s := CarState.decode(bytes, 2 + k * CarState.SIZE, time_base)
		if s:
			out.append(s)
	return out


func _on_client_raw(bytes: PackedByteArray) -> void:
	match bytes[0]:
		ClockSync.PONG:
			clock.on_pong(bytes)
		MSG_STATE:
			var t := now()
			for s in unpack(bytes, t):
				var r: NetRacer = racers.get(s.id) as NetRacer
				if r:
					r.push_state(s, t)


func _on_server_raw(peer: int, bytes: PackedByteArray) -> void:
	match bytes[0]:
		ClockSync.PING:
			var pong := ClockSync.pong(bytes, now())
			if not pong.is_empty():
				Net.server.send_raw(peer, pong, NetProtocol.CH_STATE)
		MSG_STATE:
			var t := now()
			for s in unpack(bytes, t):
				if not _owned_by(s.id, peer):
					continue # a client only speaks for its own cars
				_latest[s.id] = s
				var r: NetRacer = racers.get(s.id) as NetRacer
				if r:
					r.push_state(s, t)
