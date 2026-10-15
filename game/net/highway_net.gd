class_name HighwayNet
extends Node
## A highway session's traffic online (D109, docs/NETWORKING.md §10). Every game runs the same
## lane sim from the session's seed, stepped by the server's clock: tick = (server time - t0) ×
## 20. Only the server decides anything; its events (promote, demote, wreck, tow, reshadow,
## handover) go to every game on their own reliable channel, set `lead` ticks ahead so they get
## there in time; one that's late anyway rolls the lane sim back and replays it (64 ticks). Once
## a second the server sends a checksum of its lane sim; a game out of step three times running,
## or one joining, gets the server's traffic as it is (TRAFFIC_FULL).
##   [105][tick u32][checksum i64]           TRAFFIC_BEAT, server -> clients, once a second
##   [110][24-byte event records...]         TRAFFIC_EVENTS, server -> clients, reliable

const MSG_BEAT := 105
const MSG_EVENTS := 110
const BEAT_S := 1.0
## Checksums that disagree this many times running: ask for the server's traffic again.
const MISSES := 3
## Events land this far ahead: half the worst round trip and a margin, within these bounds (s).
const LEAD_MARGIN_S := 0.15
const LEAD_MIN_S := 0.25
const LEAD_MAX_S := 0.6
## The heartbeat names a tick this many ticks behind the server's (no late event can change it).
const BEAT_BACK := 2
## A client asks again if the server's traffic hasn't come in this long.
const ASK_AGAIN_S := 3.0
## TRAFFIC_FULL's lane sim, compressed.
const COMPRESSION := FileAccess.COMPRESSION_ZSTD

var session: TrackSession
var traffic: TrafficManager
## Server time of tick 0.
var t0 := 0.0
## Counters (net_check): checksums that disagreed, full states asked for, late events rolled
## back, handovers, heartbeats compared.
var mismatches := 0
var resyncs := 0
var late := 0
var handovers := 0
var beats := 0

var _beat_time := 0.0
var _lead_time := 0.0
var _misses := 0
var _beats: Array = [] # client: [tick, checksum] not yet reached
var _sent: Array = [] # server: [tick, record] sent lately (for joiners' TRAFFIC_FULL)
var _ask_time := -INF
var _early := PackedByteArray() # client: events that came before the server's traffic
var _stats_time := 0.0
var _events_sent := 0
var _desync_at := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -59 # before the TrafficManager steps (-58)
	if is_server():
		Net.server.raw.connect(_on_server_raw)
		if Net.host_logic:
			Net.host_logic.resync_requested.connect(_send_full)
		traffic.lead = _lead_ticks()
	else:
		Net.client.raw.connect(_on_client_raw)
		Net.traffic_full.connect(_on_full)
		traffic.synced = false


func _exit_tree() -> void:
	if Net.server and Net.server.raw.is_connected(_on_server_raw):
		Net.server.raw.disconnect(_on_server_raw)
	if Net.host_logic and Net.host_logic.resync_requested.is_connected(_send_full):
		Net.host_logic.resync_requested.disconnect(_send_full)
	if Net.client and Net.client.raw.is_connected(_on_client_raw):
		Net.client.raw.disconnect(_on_client_raw)
	if Net.traffic_full.is_connected(_on_full):
		Net.traffic_full.disconnect(_on_full)


func is_server() -> bool:
	return Net.server != null


## The lane sim's tick by the server's clock, with how far into the next one.
func tick_float() -> float:
	return maxf((session.net.now() - t0) * TrafficManager.TICK_HZ, 0.0)


func tick_now() -> int:
	return int(tick_float())


func _physics_process(delta: float) -> void:
	if is_server():
		_server_tick(delta)
	else:
		_client_tick()


# --- Server ----------------------------------------------------------------------------------


func _server_tick(delta: float) -> void:
	_stats_time += delta
	if _stats_time >= 10.0 and Game.dev.has("net-stats"):
		_stats_time = 0.0
		var t := traffic
		print("NETCHECK_SERVER " + JSON.stringify({ "promotions": t.promotions, "demotions": t.demotions, "tows": t.tows, "wrecks": t.wrecks,
			"handovers": handovers, "events": _events_sent, "full_sent": resyncs, "server_owned": session.net.traffic_owned.size(),
			"physics": t.cars.size(), "lead_ticks": t.lead, "tick": t.sim.get_tick(),
			"pursuits": session.police.pursuits if session.police else 0, "busts": session.police.busts if session.police else 0,
			"evades": session.police.evades if session.police else 0, "roadblocks": session.police.roadblocks if session.police else 0 }))
	_lead_time += delta
	if _lead_time >= 1.0:
		_lead_time = 0.0
		traffic.lead = _lead_ticks()
	_beat_time += delta
	if _beat_time < BEAT_S:
		return
	_beat_time = 0.0
	var tick := traffic.sim.get_tick() - traffic.lead - BEAT_BACK
	if not traffic.sim.has_checksum(tick):
		return
	var p := PackedByteArray()
	p.resize(13)
	p[0] = MSG_BEAT
	p.encode_u32(1, tick)
	p.encode_s64(5, traffic.sim.checksum_at(tick))
	_to_clients(p)
	# Forget what a joiner no longer needs (it gets the lane sim from past these).
	while not _sent.is_empty() and int(_sent[0][0]) < traffic.sim.get_tick() - 64:
		_sent.pop_front()


## Lead in ticks for the worst round trip now.
func _lead_ticks() -> int:
	var worst := 0.0
	for peer: int in Net.server.peers:
		if peer != 1 and Net.server.peers[peer].connected:
			worst = maxf(worst, Net.server.rtt_ms(peer) / 1000.0)
	var lead := clampf(0.5 * worst + LEAD_MARGIN_S, LEAD_MIN_S, LEAD_MAX_S)
	return ceili(lead * TrafficManager.TICK_HZ)


## Server: an event this game scheduled, to every client.
func send_events(records: PackedByteArray) -> void:
	if not is_server():
		return
	for k in range(0, records.size(), 24):
		_sent.append([records.decode_u32(k + 3), records.slice(k, k + 24)])
		_events_sent += 1
	var p := PackedByteArray([MSG_EVENTS])
	p.append_array(records)
	_to_clients(p)


func _to_clients(p: PackedByteArray) -> void:
	for peer: int in Net.server.peers:
		if peer != 1 and Net.server.peers[peer].connected:
			Net.server.send_raw(peer, p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


## The traffic as it is, to a client joining or out of step.
func _send_full(peer: int) -> void:
	var sim := traffic.sim
	var state := sim.full_state()
	var events := PackedByteArray()
	for e: Array in _sent:
		if int(e[0]) >= sim.get_tick():
			events.append_array(e[1])
	var pairs := PackedInt32Array()
	for car: int in traffic.owners:
		pairs.append_array([car, int(traffic.owners[car])])
	Net.server.send(peer, NetProtocol.Msg.TRAFFIC_FULL, { "tick": sim.get_tick(), "state": state.compress(COMPRESSION), "size": state.size(),
		"events": events, "owners": pairs, "graph": str(sim.graph_hash()) })
	resyncs += 1


func _on_server_raw(_peer: int, _bytes: PackedByteArray) -> void:
	pass # clients send nothing on their own: their cars' states go through the NetSession


# --- Client ----------------------------------------------------------------------------------


func _client_tick() -> void:
	if Game.dev.has("traffic-desync") and traffic.synced and _desync_at < 0 and traffic.sim.get_tick() > 400:
		# Dev (net_check --desync): this game's traffic goes out of step once; it must come back.
		_desync_at = traffic.sim.get_tick()
		for car in traffic.sim.get_count():
			var c := traffic.sim.car(car)
			if int(c.lane) >= 0 and not traffic.owners.has(car):
				traffic.sim.place(car, int(c.lane), float(c.s) + 50.0, 5.0)
				break
	if not traffic.synced:
		if session.net.clock.synced and Time.get_ticks_msec() / 1000.0 - _ask_time > ASK_AGAIN_S:
			_ask()
		return
	# Heartbeats this lane sim has reached.
	var sim := traffic.sim
	while not _beats.is_empty() and int(_beats[0][0]) <= sim.get_tick():
		var b: Array = _beats.pop_front()
		if not sim.has_checksum(int(b[0])):
			continue
		beats += 1
		if sim.checksum_at(int(b[0])) == int(b[1]):
			_misses = 0
			continue
		mismatches += 1
		_misses += 1
		if _misses >= MISSES:
			_misses = 0
			_ask()


func _ask() -> void:
	_ask_time = Time.get_ticks_msec() / 1000.0
	Net.request(NetProtocol.Msg.RESYNC, {})


func _on_client_raw(bytes: PackedByteArray) -> void:
	match bytes[0]:
		MSG_EVENTS:
			var records := bytes.slice(1)
			if records.size() % 24 != 0:
				return
			if not traffic.synced:
				_early.append_array(records)
			elif not traffic.receive(records):
				_ask() # too late to replay
		MSG_BEAT:
			if bytes.size() == 13:
				_beats.append([bytes.decode_u32(1), bytes.decode_s64(5)])
				if _beats.size() > 30:
					_beats.pop_front()


func _on_full(data: Dictionary) -> void:
	if not NetProtocol.has_fields(data, { "tick": TYPE_INT, "state": TYPE_PACKED_BYTE_ARRAY, "size": TYPE_INT, "events": TYPE_PACKED_BYTE_ARRAY,
			"owners": TYPE_PACKED_INT32_ARRAY, "graph": TYPE_STRING }):
		return
	if String(data.graph) != str(traffic.sim.graph_hash()):
		push_warning("Traffic: this game's lane graph isn't the server's")
		return
	var size := clampi(int(data.size), 0, 4 << 20)
	var state := (data.state as PackedByteArray).decompress(size, COMPRESSION)
	var events: PackedByteArray = data.events
	events.append_array(_early)
	_early = PackedByteArray()
	if traffic.load_full(state, int(data.tick), events, data.owners):
		_beats.clear()
		_misses = 0
		resyncs += 1
