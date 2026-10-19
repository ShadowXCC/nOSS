class_name DragNet
extends Node
## Drag matches online (D175, docs/NETWORKING.md §14). The server is the authority: it draws the
## ladder, runs the tree, rules on the centreline and the lights, and says who won each pass.
## Nothing of the strip goes on the wire — every game builds the same one from the same settings
## (D168) — so all that is sent is what the pass is doing and where each car stands in it.
##
## Each game still drives its own car, so each one grades its own shifts and feels its own surge
## at once rather than a round trip later; it reports them up so the server's results carry them.
##   [108][phase u8][time f32][pass u8][cars u8 x 12 B]   DRAG_STATE, server -> clients, 5 Hz
## A car: id u16 · lane i8 · flags u8 (1 in the pass, 2 launched, 4 done, 8 blown, 16 out)
##        · foul u8 · boosts u8 · reaction f32 (-1 none) · et u16 (ms/10, 0 none).
##   [114][12-byte records...]   DRAG_EVENTS, server -> clients, reliable
## A record: kind u8 · car u16 · value f32 · time u32 (ms).
##   [115][12-byte records...]   DRAG_REPORT, client -> server, reliable
## The same records, for the two things only the driver's own game sees: its reaction and its
## shift grades.

const MSG_STATE := 108
const MSG_EVENTS := 114
const MSG_REPORT := 115
const RECORD := 12
const CAR_BYTES := 12
const STATE_HZ := 5.0
## A pass's elapsed time on the wire: hundredths, up to 655 s.
const ET_SCALE := 100.0

enum Ev { PASS = 1, GREEN, FOUL, FINISH, PASS_END, MATCH_END, REACTION, GRADE, BOOST }
## Foul codes, so a client shows the same words for it.
const FOULS := ["", "red", "centreline", "off", "reset", "stopped", "timeout"]
const GRADES := ["", "perfect", "good", "miss"]

var session: TrackSession
var drag: DragControl
## Counters (net_check): events the server sent, grades it took from clients, and how far this
## client's pass clock was from the server's at the last snapshot.
var events := 0
var grades_taken := 0
var time_error := 0.0

var _state_time := 0.0
var _states: Array[PackedByteArray] = [] # client: snapshots in, read at its next tick


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -44 # just after DragControl (-45): states as of this tick
	if is_server():
		Net.server.raw.connect(_on_server_raw)
		drag.pass_started.connect(func(cars: Array) -> void: _send_pass(cars))
		drag.fouled.connect(func(r: Racer, why: String) -> void:
			_broadcast([_record(Ev.FOUL, r.net_id, float(maxi(FOULS.find(why), 0)))]))
		drag.run_finished.connect(func(r: Racer, et: float, _trap: float) -> void:
			_broadcast([_record(Ev.FINISH, r.net_id, et)]))
		drag.pass_ended.connect(func(won: Racer) -> void:
			_broadcast([_record(Ev.PASS_END, won.net_id if won else 0, 0.0)]))
	else:
		Net.client.raw.connect(_on_client_raw)
		drag.authority = false
		# Its own game saw these; the server did not.
		drag.shift_graded.connect(func(r: Racer, grade: String, _gear: int) -> void:
			if _is_local(r):
				_report([_record(Ev.GRADE, r.net_id, float(maxi(GRADES.find(grade), 0)))]))
		drag.boost_used.connect(func(r: Racer) -> void:
			if _is_local(r):
				_report([_record(Ev.BOOST, r.net_id, 0.0)]))


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
		# The newest snapshot, against this game's pass as of this same tick.
		if not _states.is_empty():
			_on_state(_states.back())
			_states.clear()
		_report_reactions()
		return
	_state_time += delta
	if _state_time >= 1.0 / STATE_HZ:
		_state_time = 0.0
		var p := pack_state()
		for peer: int in Net.server.peers:
			if peer != 1:
				Net.server.send_raw(peer, p, NetProtocol.CH_STATE)


## What the pass is doing, and where every car stands in it.
func pack_state() -> PackedByteArray:
	var p := PackedByteArray([MSG_STATE])
	p.resize(7)
	p[1] = drag.phase
	p.encode_float(2, drag.phase_time)
	# Which pass this is, so a client can tell a new one from a snapshot that arrived late.
	p[6] = drag.passes_run & 0xFF
	var cars := session.racers.filter(func(r: Racer) -> bool: return r.vehicle != null).slice(0, 255)
	var head := p.size()
	p.resize(head + 1 + cars.size() * CAR_BYTES)
	p[head] = cars.size()
	for k in cars.size():
		var r: Racer = cars[k]
		var state: Dictionary = drag.run_of(r)
		var at := head + 1 + k * CAR_BYTES
		p.encode_u16(at, r.net_id)
		p.encode_s8(at + 2, int(state.get("lane", -1)) if not state.is_empty() else -1)
		var flags := 0
		if not state.is_empty():
			flags |= 1
			flags |= 2 if bool(state.launched) else 0
			flags |= 4 if bool(state.done) else 0
			flags |= 8 if bool(state.blown) else 0
		flags |= 16 if r.out else 0
		p[at + 3] = flags
		p[at + 4] = maxi(FOULS.find(String(state.get("foul", ""))), 0)
		p[at + 5] = clampi(int(state.get("boosts", 0)), 0, 255)
		p.encode_float(at + 6, float(state.get("reaction", -1.0)))
		p.encode_u16(at + 10, clampi(roundi(maxf(float(state.get("et", -1.0)), 0.0) * ET_SCALE), 0, 65535))
	return p


## Client: the pass as the server has it.
func _on_state(bytes: PackedByteArray) -> void:
	if bytes.size() < 8:
		return
	var phase: int = bytes[1]
	var at_time := bytes.decode_float(2)
	time_error = absf(drag.phase_time - at_time)
	drag.apply_net_phase(phase, at_time, bytes[6])
	var cars: int = bytes[7]
	for k in cars:
		var o := 8 + k * CAR_BYTES
		if bytes.size() < o + CAR_BYTES:
			return
		var r := _racer(bytes.decode_u16(o))
		if r == null:
			continue
		var flags: int = bytes[o + 3]
		var et := float(bytes.decode_u16(o + 10)) / ET_SCALE
		drag.apply_net(r, {
			"in_pass": flags & 1 != 0,
			"lane": bytes.decode_s8(o + 2),
			"launched": flags & 2 != 0,
			"done": flags & 4 != 0,
			"blown": flags & 8 != 0,
			"out": flags & 16 != 0,
			"foul": FOULS[clampi(bytes[o + 4], 0, FOULS.size() - 1)],
			"boosts": bytes[o + 5],
			"reaction": bytes.decode_float(o + 6),
			"et": et if et > 0.0 else -1.0,
		})


## Client: the moments, as they happened.
func _on_events(bytes: PackedByteArray) -> void:
	var n := (bytes.size() - 1) / RECORD
	for i in n:
		var at := 1 + i * RECORD
		var kind: int = bytes[at]
		var value := bytes.decode_float(at + 3)
		var r := _racer(bytes.decode_u16(at + 1))
		match kind:
			Ev.PASS:
				# The pair and their lanes come as one record a car, so this is the car's lane.
				if r:
					drag.net_pass_car(r, int(value))
			Ev.GREEN:
				drag.net_green()
			Ev.FOUL:
				if r:
					drag.net_foul(r, FOULS[clampi(int(value), 0, FOULS.size() - 1)])
			Ev.FINISH:
				if r:
					drag.net_finish(r, value)
			Ev.PASS_END:
				drag.net_pass_end(r)
			Ev.MATCH_END:
				drag.net_match_end(r)


## Server: what a client's own game saw of its own car.
func _on_server_raw(peer: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes[0] != MSG_REPORT or (bytes.size() - 1) % RECORD != 0 or bytes.size() > 1 + RECORD * 32:
		return
	var n := (bytes.size() - 1) / RECORD
	for i in n:
		var at := 1 + i * RECORD
		var r := _racer(bytes.decode_u16(at + 1))
		if r == null or not _owned_by(r, peer):
			continue # only ever its own cars
		match int(bytes[at]):
			Ev.REACTION:
				drag.take_net_reaction(r, bytes.decode_float(at + 3))
			Ev.GRADE:
				grades_taken += 1
				drag.take_net_grade(r, GRADES[clampi(int(bytes.decode_float(at + 3)), 0, GRADES.size() - 1)])
			Ev.BOOST:
				drag.take_net_boost(r)


func _on_client_raw(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	match bytes[0]:
		MSG_STATE:
			_states.append(bytes)
		MSG_EVENTS:
			_on_events(bytes)


## Server: the pair and their lanes, and the green when it comes.
func _send_pass(cars: Array) -> void:
	var recs: Array = []
	for r: Racer in cars:
		recs.append(_record(Ev.PASS, r.net_id, float(int(drag.run_of(r).get("lane", 0)))))
	_broadcast(recs)


## Called by DragControl on the server when the lights go green, and at the end of the match.
func send_green() -> void:
	_broadcast([_record(Ev.GREEN, 0, 0.0)])


func send_match_end(won: Racer) -> void:
	_broadcast([_record(Ev.MATCH_END, won.net_id if won else 0, 0.0)])


## Client: its own cars' reactions, once each, as soon as they are timed.
func _report_reactions() -> void:
	for r in drag.cars:
		if not _is_local(r):
			continue
		var state: Dictionary = drag.run_of(r)
		if state.is_empty() or float(state.get("reaction", -1.0)) < 0.0 or bool(state.get("reported", false)):
			continue
		state.reported = true
		_report([_record(Ev.REACTION, r.net_id, float(state.reaction))])


func _is_local(r: Racer) -> bool:
	return r is SessionPlayer and r.vehicle != null and not r.vehicle.remote


func _owned_by(r: Racer, peer: int) -> bool:
	return session.net != null and session.net._peer_of(r.net_id) == peer


func _racer(id: int) -> Racer:
	for r in session.racers:
		if r.net_id == id:
			return r
	return null


func _record(kind: int, car: int, value: float) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(RECORD)
	p[0] = kind
	p.encode_u16(1, car)
	p.encode_float(3, value)
	p.encode_u32(8, int(now() * 1000.0) & 0xFFFFFFFF)
	return p


func _broadcast(recs: Array) -> void:
	if recs.is_empty() or Net.server == null:
		return
	events += recs.size()
	var p := PackedByteArray([MSG_EVENTS])
	for r: PackedByteArray in recs:
		p.append_array(r)
	for peer: int in Net.server.peers:
		if peer != 1:
			Net.server.send_raw(peer, p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _report(recs: Array) -> void:
	if recs.is_empty() or Net.client == null:
		return
	var p := PackedByteArray([MSG_REPORT])
	for r: PackedByteArray in recs:
		p.append_array(r)
	Net.client.send_raw(p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
