class_name NetSession
extends Node
## Online play inside a track session (docs/NETWORKING.md §6, D84). Each game sends the states of
## the cars it drives: a client to the server, at 30 per second (60 on a fast link); the server
## sends everyone every other car's freshest states 60 times a second (a client's own cars
## excepted), its own cars (a listen host's players, AI) included. Remote cars are NetRacers. A
## client keeps the server's clock (ClockSync); the server's is its own.

const MSG_STATE := 100
const MSG_CONTACT := 104
const CONTACT_SIZE := 27
## Contact relay (D86): most per second between two cars, the largest change of speed it may
## give (m/s), and how near the car it must be (m).
const CONTACT_PER_S := 10.0
const CONTACT_MAX_DV := 3.0
const CONTACT_NEAR_M := 8.0
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
var _contact_sent := {} # "a:b" -> time, so a pair relays at most CONTACT_PER_S
var _own_contact := {} # "own:other" -> time this game's car last touched that car itself
var _contact_routed := {} # server: "a:b" -> time last passed on
var _plaus := {} # server: car id -> Plausibility
var _plaus_said := {} # server: car id -> time the driver last heard why
var _plaus_logged := {} # server: car id -> time last logged


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
	_relay_contacts()
	if is_server():
		_server_tick(delta)
	elif Net.client and Net.client.state == NetClient.State.JOINED:
		_client_tick(delta)


## This game's cars' knocks with remote cars go to those cars' games (D86).
func _relay_contacts() -> void:
	var t := now()
	for id: int in owned:
		var v: Vehicle = owned[id].vehicle
		if v == null or not is_instance_valid(v):
			continue
		for c: Array in v.remote_contacts:
			var other := _id_of(c[0])
			if other < 0:
				continue
			_own_contact["%d:%d" % [id, other]] = t
			var pair := "%d:%d" % [id, other]
			if t - float(_contact_sent.get(pair, -1.0)) < 1.0 / CONTACT_PER_S:
				continue
			_contact_sent[pair] = t
			var p := PackedByteArray()
			p.resize(CONTACT_SIZE)
			p[0] = MSG_CONTACT
			p[1] = id
			p[2] = other
			for k in 3:
				p.encode_float(3 + k * 4, -(c[1] as Vector3)[k]) # what the other car gets
				p.encode_float(15 + k * 4, (c[2] as Vector3)[k])
			if is_server():
				_route_contact(1, p)
			elif Net.client:
				Net.client.send_raw(p, NetProtocol.CH_STATE)


func _id_of(v: Vehicle) -> int:
	for id: int in racers:
		if racers[id].vehicle == v:
			return id
	return -1


## Server: plausibility checks on a client's car (D87), and the server's response.
func _check(peer: int, s: CarState, t: float) -> void:
	var mode := String(Net.host_logic.config.plausibility) if Net.host_logic else "off"
	if mode == "off":
		return
	var p: Plausibility = _plaus.get(s.id)
	if p == null:
		p = Plausibility.for_platform(session.platform.platform, session.track)
		_plaus[s.id] = p
	var contact := false
	for pair: String in _contact_routed:
		if (pair.begins_with("%d:" % s.id) or pair.ends_with(":%d" % s.id)) and t - float(_contact_routed[pair]) < 0.5:
			contact = true
	var found := p.check(s, t, session.track, contact)
	if not found.is_empty() and p.strike(found, t):
		respond(peer, s.id, p.reasons(), mode)
		p.clear()


## Server: a car failed the checks: warn its driver, flag its laps, or kick its game.
func respond(peer: int, id: int, why: String, mode := "") -> void:
	if mode.is_empty():
		mode = String(Net.host_logic.config.plausibility) if Net.host_logic else "flag"
	var r: Racer = racers.get(id)
	var name := r.display_name if r else "car %d" % id
	if Net.host_logic and (mode == "kick" or now() - float(_plaus_logged.get(id, -100.0)) > 10.0):
		_plaus_logged[id] = now()
		Net.host_logic.log_line.emit("Checks failed: %s (%s): %s" % [name, mode, why])
	match mode:
		"kick":
			Net.server.kick(peer, "Failed checks: " + why)
		"flag":
			if r:
				r.set_meta(&"flagged", why)
			_tell(id, r, "Flagged: " + why)
		_:
			_tell(id, r, "Checks: " + why)


func _tell(id: int, r: Racer, text: String) -> void:
	if r and now() - float(_plaus_said.get(id, -100.0)) > 10.0:
		_plaus_said[id] = now()
		NetRace.note(r, text, 4.0)


## Server: a car's lap, timed here: faster than the ideal line allows?
func check_lap(r: Racer, seconds: float) -> void:
	var p: Plausibility = _plaus.get(r.net_id)
	if p and p.check_lap(seconds) and r is NetRacer:
		respond((r as NetRacer).peer, r.net_id, "lap %.3f s" % seconds)


## Server: a car's game says it knocked car `to`: checked, then to that car's game.
func _route_contact(from_peer: int, p: PackedByteArray) -> void:
	if p.size() != CONTACT_SIZE:
		return
	var from := p[1]
	var to := p[2]
	if from_peer != 1 and not _owned_by(from, from_peer):
		return
	var pair := "%d:%d" % [from, to]
	if now() - float(_contact_routed.get(pair, -1.0)) < 0.5 / CONTACT_PER_S:
		return # more than a game sends on its own
	_contact_routed[pair] = now()
	var target: Racer = racers.get(to)
	if target == null or target.vehicle == null:
		return
	var impulse := Vector3(p.decode_float(3), p.decode_float(7), p.decode_float(11))
	var point := Vector3(p.decode_float(15), p.decode_float(19), p.decode_float(23))
	if not impulse.is_finite() or not point.is_finite() or point.distance_to(target.vehicle.global_position) > CONTACT_NEAR_M:
		return
	impulse = impulse.limit_length(target.vehicle.mass * CONTACT_MAX_DV)
	for k in 3:
		p.encode_float(3 + k * 4, impulse[k])
	var owner_peer := 1 if owned.has(to) else int(Net.server.players[to].peer) if Net.server.players.has(to) else -1
	if owner_peer == 1:
		_apply_contact(p)
	elif owner_peer > 1:
		Net.server.send_raw(owner_peer, p, NetProtocol.CH_STATE)


## A knock from another game, unless this game's car felt that one itself.
func _apply_contact(p: PackedByteArray) -> void:
	var from := p[1]
	var to := p[2]
	var r: Racer = owned.get(to)
	if r == null or r.vehicle == null:
		return
	var rtt := clock.rtt if not is_server() else 0.1
	if now() - float(_own_contact.get("%d:%d" % [to, from], -10.0)) < rtt + 0.1:
		return # it hit the other car here too
	var impulse := Vector3(p.decode_float(3), p.decode_float(7), p.decode_float(11))
	var point := Vector3(p.decode_float(15), p.decode_float(19), p.decode_float(23))
	r.vehicle.apply_remote_impulse(impulse.limit_length(r.vehicle.mass * CONTACT_MAX_DV), point)


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
			_dev_cheat(s)
			states.append(s)
	for packet in pack(states):
		Net.client.send_raw(packet, NetProtocol.CH_STATE)


## Dev (--cheat=speed|teleport|time, bots): sends false states, so net_check can see the server's
## checks catch them.
func _dev_cheat(s: CarState) -> void:
	match String(Game.dev.get("cheat", "")):
		"speed":
			s.velocity = s.xform.basis.z * 150.0
		"teleport":
			if int(now() * 2.0) % 10 == 0:
				s.xform.origin += s.xform.basis.z * 60.0
		"time":
			s.time += 2.0


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
		MSG_CONTACT:
			_apply_contact(bytes)
		MSG_STATE:
			var t := now()
			for s in unpack(bytes, t):
				var r: NetRacer = racers.get(s.id) as NetRacer
				if r:
					r.push_state(s, t)


func _on_server_raw(peer: int, bytes: PackedByteArray) -> void:
	match bytes[0]:
		MSG_CONTACT:
			_route_contact(peer, bytes)
		ClockSync.PING:
			var pong := ClockSync.pong(bytes, now())
			if not pong.is_empty():
				Net.server.send_raw(peer, pong, NetProtocol.CH_STATE)
		MSG_STATE:
			var t := now()
			for s in unpack(bytes, t):
				if not _owned_by(s.id, peer):
					continue # a client only speaks for its own cars
				_check(peer, s, t)
				_latest[s.id] = s
				var r: NetRacer = racers.get(s.id) as NetRacer
				if r:
					r.push_state(s, t)
