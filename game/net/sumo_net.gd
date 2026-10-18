class_name SumoNet
extends Node
## Sumo matches online (D166, docs/NETWORKING.md §13). The server is the authority: it shrinks the
## platforms and rules on who is in the goo. Nothing of the arena itself goes on the wire — every
## game builds the same platforms from the same settings (D162) — so all that is sent is how far
## each one has shrunk and where each car stands. A ring-out goes out at once as a reliable event,
## so the splash and the message land on the tick they happened; five times a second the server
## sends how things stand, which heals drift and brings a joiner up to date.
##   [107][tiers u8][radius f32 × tiers][cars u8 × 5 B]   SUMO_STATE, server -> clients, 5 Hz
## A car: id u16 · tier i8 (-1: in the air or gone) · flags u8 (1: out) · charge u8 (ram, 0-255).
##   [113][8-byte records…]   SUMO_EVENTS, server -> clients, reliable
## A record: kind u8 · car u16 · tier u8 · time u32 (ms).

const MSG_STATE := 107
const MSG_EVENTS := 113
const RECORD := 8
const CAR_BYTES := 5
const STATE_HZ := 5.0
enum Ev { OUT = 1, ARMED }

var session: TrackSession
var sumo: SumoControl
## Counters (net_check): ring-outs the server sent, and how far this client's platforms were from
## the server's at the last snapshot.
var outs := 0
var radius_error := 0.0

var _state_time := 0.0
var _states: Array[PackedByteArray] = [] # client: snapshots in, read at its next tick


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -52 # just after SumoControl (-53): states as of this tick
	if is_server():
		Net.server.raw.connect(_on_server_raw)
		sumo.pushed_out.connect(func(r: Racer) -> void:
			outs += 1
			_broadcast([_record(Ev.OUT, r.net_id, maxi(sumo.reached(r), 0))]))
	else:
		Net.client.raw.connect(_on_client_raw)
		sumo.authority = false


func _exit_tree() -> void:
	if Net.server and Net.server.raw.is_connected(_on_server_raw):
		Net.server.raw.disconnect(_on_server_raw)
	if Net.client and Net.client.raw.is_connected(_on_client_raw):
		Net.client.raw.disconnect(_on_client_raw)


func is_server() -> bool:
	return Net.server != null


func now() -> float:
	return session.net.now() if session and session.net else ClockSync.local_now()


func _physics_process(delta: float) -> void:
	if not is_server():
		# The newest snapshot, against this game's platforms as of this same tick.
		if not _states.is_empty():
			_on_state(_states.back())
			_states.clear()
		return
	_state_time += delta
	if _state_time >= 1.0 / STATE_HZ:
		_state_time = 0.0
		var p := pack_state()
		for peer: int in Net.server.peers:
			if peer != 1:
				Net.server.send_raw(peer, p, NetProtocol.CH_STATE)


## How things stand: every platform's radius, and every car's tier, out and ram charge.
func pack_state() -> PackedByteArray:
	var layout := sumo.layout
	var p := PackedByteArray([MSG_STATE])
	var tiers := layout.count()
	var head := p.size()
	p.resize(head + 1 + tiers * 4)
	p[head] = tiers
	for i in tiers:
		p.encode_float(head + 1 + i * 4, layout.radius_of(i))
	var cars := session.racers.filter(func(r: Racer) -> bool: return r.vehicle != null).slice(0, 255)
	head = p.size()
	p.resize(head + 1 + cars.size() * CAR_BYTES)
	p[head] = cars.size()
	for k in cars.size():
		var r: Racer = cars[k]
		var at := head + 1 + k * CAR_BYTES
		p.encode_u16(at, r.net_id)
		p.encode_s8(at + 2, clampi(sumo.tier(r), -1, 127))
		p[at + 3] = 1 if r.out else 0
		p[at + 4] = clampi(roundi(sumo.charge(r) * 255.0), 0, 255)
	return p


## Client: the server's platforms and cars.
func _on_state(bytes: PackedByteArray) -> void:
	if bytes.size() < 2:
		return
	var layout := sumo.layout
	var tiers: int = bytes[1]
	if bytes.size() < 2 + tiers * 4:
		return
	var radii := PackedFloat32Array()
	for i in tiers:
		radii.append(bytes.decode_float(2 + i * 4))
	radius_error = 0.0
	for i in mini(tiers, layout.count()):
		radius_error = maxf(radius_error, absf(layout.radius_of(i) - radii[i]))
	layout.apply_radii(radii)
	var at := 2 + tiers * 4
	if bytes.size() <= at:
		return
	var cars: int = bytes[at]
	at += 1
	for k in cars:
		var o := at + k * CAR_BYTES
		if bytes.size() < o + CAR_BYTES:
			return
		var r := _racer(bytes.decode_u16(o))
		if r == null:
			continue
		sumo.apply_net(r, bytes.decode_s8(o + 2), bytes[o + 3] & 1 != 0)


## Client: a ring-out, as it happened.
func _on_events(bytes: PackedByteArray) -> void:
	var n := (bytes.size() - 1) / RECORD
	for i in n:
		var at := 1 + i * RECORD
		var kind: int = bytes[at]
		var r := _racer(bytes.decode_u16(at + 1))
		if r == null:
			continue
		match kind:
			Ev.OUT:
				outs += 1
				sumo.apply_net(r, -1, true)
			Ev.ARMED:
				sumo.layout.arm(bytes[at + 3])


func _racer(id: int) -> Racer:
	for r in session.racers:
		if r.net_id == id:
			return r
	return null


func _record(kind: int, car: int, tier: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(RECORD)
	p[0] = kind
	p.encode_u16(1, car)
	p[3] = clampi(tier, 0, 255)
	p.encode_u32(4, int(now() * 1000.0) & 0xFFFFFFFF)
	return p


func _broadcast(recs: Array) -> void:
	if recs.is_empty() or Net.server == null:
		return
	var p := PackedByteArray([MSG_EVENTS])
	for r: PackedByteArray in recs:
		p.append_array(r)
	for peer: int in Net.server.peers:
		if peer != 1:
			Net.server.send_raw(peer, p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _on_server_raw(_peer: int, _bytes: PackedByteArray) -> void:
	pass # a sumo match has nothing a client may report: the server sees every fall itself


func _on_client_raw(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	match bytes[0]:
		MSG_STATE:
			_states.append(bytes)
		MSG_EVENTS:
			_on_events(bytes)
