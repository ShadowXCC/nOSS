class_name NetRace
extends Node
## A track event online (D85). The server's RaceControl runs it; this tells the clients: when a
## session begins (and its grid), the race state ten times a second (phase, clock, lights-out
## time, and per car: held, flag, laps, best, penalties, finish, position), the results, and notes
## for one car's driver ("Track limits: warning"). On a client it feeds its RaceControl, which
## then only follows (`mirror`). Owners report the assists their cars used, for the results.

const MSG_STATE := 103
const STATE_HZ := 10.0
const KINDS := ["free", "time_trial", "practice", "qualifying", "race", "battle"]
const FLAGS := ["", "green", "yellow", "blue", "checkered"]
const HEADER := 32
const CAR_SIZE := 21
## A link this bad for BAD_LINK_S ghosts its cars (rules.ghost_bad_links).
const BAD_RTT_MS := 250.0
const BAD_LOSS := 0.05
const BAD_LINK_S := 3.0
const ENET_LOSS_SCALE := 65536.0
## While the start waits (D127), each game says how many of the session's cars it has this often.
const SYNC_EVERY_S := 0.5

var session: TrackSession
var race: RaceControl
var net: NetSession

var _time := 0.0
var _assist_time := 0.0
var _assists_sent := {} # car id -> what was sent last (JSON)
var _link_time := 0.0
var _bad_since := {} # peer -> seconds its link has been bad
var _bad_peers := {} # peer -> true while ghosted
var _sync_time := 0.0
var _sync_sent := Vector2i(-1, -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -54 # after the race control
	race = session.race
	net = session.net
	if Net.server:
		race.session_started.connect(_on_begin)
		race.session_ended.connect(_on_end)
		if Net.host_logic:
			Net.host_logic.assists_reported.connect(_on_assists)
	elif Net.client:
		Net.client.raw.connect(_on_raw)
		Net.race_message.connect(_on_message)
		if not Net.race_begin.is_empty(): # it came before this session was built
			_on_message.call_deferred(NetProtocol.Msg.RACE_BEGIN, Net.race_begin)


func _exit_tree() -> void:
	if Net.client and Net.client.raw.is_connected(_on_raw):
		Net.client.raw.disconnect(_on_raw)
	if Net.race_message.is_connected(_on_message):
		Net.race_message.disconnect(_on_message)
	if Net.host_logic and Net.host_logic.assists_reported.is_connected(_on_assists):
		Net.host_logic.assists_reported.disconnect(_on_assists)


func _physics_process(delta: float) -> void:
	if not Game.dedicated and race.phase == RaceControl.Phase.LOADING:
		_sync_time += delta
		if _sync_time >= SYNC_EVERY_S:
			_sync_time = 0.0
			report_sync()
	if Net.server:
		_link_time += delta
		if _link_time >= 1.0:
			_link_time = 0.0
			_check_links()
		_time += delta
		if _time >= 1.0 / STATE_HZ:
			_time = 0.0
			var bytes := pack_state()
			for peer: int in Net.server.peers:
				if peer != 1 and Net.server.peers[peer].connected:
					Net.server.send_raw(peer, bytes, NetProtocol.CH_STATE)
	elif Net.client:
		_assist_time += delta
		if _assist_time >= 1.0:
			_assist_time = 0.0
			_report_assists()


# --- Server ---------------------------------------------------------------------------------

func _on_begin(kind: String) -> void:
	var data := { "kind": kind, "index": race.index, "grid": race.grid_ids.duplicate() }
	Net.server.broadcast(NetProtocol.Msg.RACE_BEGIN, data)


func _on_end(kind: String, results: Array) -> void:
	var rows := []
	for row: Dictionary in results:
		var r: Racer = row.racer
		var out := row.duplicate()
		out.erase("racer")
		out.id = r.net_id
		out.human = r.is_human
		out.assists = ResultsMenu.assists_text(r)
		rows.append(out)
	Net.server.broadcast(NetProtocol.Msg.RESULTS, { "kind": kind, "index": race.index, "rows": rows })


## This game's part of the start (D127): how many of the session's cars are here and loaded
## (own cars spawned, others' whole as this game fetches them), sent when it changes.
func report_sync() -> void:
	var have := 0
	for r in session.racers:
		var here := (r as NetRacer).settled() if r is NetRacer else r.vehicle != null
		if here:
			have += 1
	var now := Vector2i(have, session.racers.size())
	if now != _sync_sent:
		_sync_sent = now
		Net.request(NetProtocol.Msg.SYNCED, { "have": now.x, "of": now.y })


## Server: which clients' links are bad now (their cars race ghosted).
func _check_links() -> void:
	if Net.host_logic == null or not bool(Net.host_logic.config.rules.get("ghost_bad_links", true)):
		_bad_peers.clear()
		return
	for peer: int in Net.server.peers:
		var p := Net.server.enet.get_peer(peer) if peer != 1 else null
		if p == null:
			continue
		var loss := p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / ENET_LOSS_SCALE
		var bad := p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) > BAD_RTT_MS or loss > BAD_LOSS
		_bad_since[peer] = float(_bad_since.get(peer, 0.0)) + 1.0 if bad else 0.0
		if _bad_since[peer] >= BAD_LINK_S:
			_bad_peers[peer] = true
		elif not bad:
			_bad_peers.erase(peer)


func _bad_link(r: Racer) -> bool:
	return r is NetRacer and _bad_peers.has((r as NetRacer).peer)


## A message for car `r`'s driver, wherever they are.
static func note(r: Racer, text: String, seconds: float) -> void:
	if Net.server and r is NetRacer:
		Net.server.send((r as NetRacer).peer, NetProtocol.Msg.NOTE, { "id": r.net_id, "text": text.left(80), "seconds": seconds })


func _on_assists(id: int, used: Dictionary) -> void:
	var r: Racer = net.racers.get(id)
	if r:
		r.assists_used = used


## The race state: [103][time f64][kind][index][phase][lights][clock f32][go_at f64]
## [leader finished f32][n][games synced][games] then per car [id u16][bits][pace][lap u16][best f32][last f32][penalty]
## [warnings][finish f32][position]. bits: held 1, finished 2, dnf 4, flag << 3.
func pack_state() -> PackedByteArray:
	var cars: Array[Racer] = []
	for r in session.racers:
		if r.net_id > 0:
			cars.append(r)
	var p := PackedByteArray()
	p.resize(HEADER + cars.size() * CAR_SIZE)
	p[0] = MSG_STATE
	p.encode_double(1, net.now())
	p[9] = maxi(KINDS.find(race.kind), 0)
	p[10] = race.index
	p[11] = race.phase
	p[12] = race.lights
	p.encode_float(13, race.clock)
	p.encode_double(17, race.go_at)
	p.encode_float(25, race.leader_finished_at)
	p[29] = cars.size()
	p[30] = clampi(race.synced.x, 0, 255)
	p[31] = clampi(race.synced.y, 0, 255)
	var at := HEADER
	for r in cars:
		p.encode_u16(at, r.net_id)
		var o := at + 1 # the fields after the id, each where [o + n] says
		var flag := maxi(FLAGS.find(r.flag), 0)
		p[o + 1] = (1 if r.held else 0) | (2 if r.finished else 0) | (4 if r.dnf else 0) | (flag << 3) | (64 if _bad_link(r) else 0)
		p[o + 2] = clampi(roundi(r.pace_limit), 0, 255)
		p.encode_u16(o + 3, clampi(r.timer.lap, 0, 65535))
		p.encode_float(o + 5, r.timer.best_lap)
		p.encode_float(o + 9, r.timer.last_lap)
		p[o + 13] = clampi(roundi(r.penalty_s), 0, 255)
		p[o + 14] = clampi(r.warnings, 0, 255)
		p.encode_float(o + 15, r.finish_time)
		p[o + 19] = clampi(race.position_of(r), 0, 255)
		at += CAR_SIZE
	return p


# --- Client ---------------------------------------------------------------------------------

func _on_raw(bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes[0] != MSG_STATE or bytes.size() < HEADER:
		return
	var n := bytes[29]
	if bytes.size() != HEADER + n * CAR_SIZE or bytes[9] >= KINDS.size():
		return
	if KINDS[bytes[9]] != race.kind or bytes[10] != race.index:
		return # a session this game hasn't begun yet
	# DONE comes with the results (another channel: the state may beat them here).
	if race.phase != RaceControl.Phase.DONE:
		race.phase = clampi(bytes[11], 0, RaceControl.Phase.CHECKERED) as RaceControl.Phase
	race.lights = clampi(bytes[12], 0, RaceControl.LIGHTS)
	var clock := bytes.decode_float(13)
	if is_finite(clock) and absf(clock - race.clock) > 0.25:
		race.clock = clock
	var go_at := bytes.decode_double(17)
	race.go_at = go_at if is_finite(go_at) else -1.0
	var leader := bytes.decode_float(25)
	race.leader_finished_at = leader if is_finite(leader) else -1.0
	race.synced = Vector2i(bytes[30], bytes[31])
	var at := HEADER
	for k in n:
		var r: Racer = net.racers.get(bytes.decode_u16(at))
		if r:
			_apply_car(r, bytes, at + 1) # its fields from [at + 1 + n] as packed
		at += CAR_SIZE


func _apply_car(r: Racer, b: PackedByteArray, at: int) -> void:
	var bits := b[at + 1]
	var own := net.owned.has(r.net_id)
	# Own cars go at the scheduled lights-out themselves; after that the grid hold is over.
	var released := race.phase == RaceControl.Phase.COUNTDOWN and race.go_at >= 0.0 and race.now() >= race.go_at
	r.held = bits & 1 != 0 and not released
	r.finished = bits & 2 != 0
	r.dnf = bits & 4 != 0
	r.flag = FLAGS[clampi((bits >> 3) & 7, 0, FLAGS.size() - 1)]
	var bad := bits & 64 != 0
	if own and bad != r.forced_ghost:
		r.forced_ghost = bad
		r.set_ghost(bad or session.ghosted or r.waiting)
		r.notify("Bad link: ghosted" if bad else "Link fine again", 3.0)
	r.pace_limit = b[at + 2]
	r.penalty_s = b[at + 13]
	r.warnings = b[at + 14]
	var finish := b.decode_float(at + 15)
	r.finish_time = finish if is_finite(finish) else -1.0
	race.net_positions[r.net_id] = b[at + 19]
	if not own: # its own game's timer is the one it drives by
		r.timer.lap = b.decode_u16(at + 3)
		var best := b.decode_float(at + 5)
		var last := b.decode_float(at + 9)
		r.timer.best_lap = best if is_finite(best) else -1.0
		r.timer.last_lap = last if is_finite(last) else -1.0


func _on_message(type: int, d: Dictionary) -> void:
	match type:
		NetProtocol.Msg.RACE_BEGIN:
			if not NetProtocol.has_fields(d, { "kind": [TYPE_STRING, 16], "index": TYPE_INT, "grid": [TYPE_ARRAY, 64] }) or d.kind not in KINDS:
				return
			session.close_results()
			race.begin_mirror(d.kind, d.index, d.grid)
		NetProtocol.Msg.RESULTS:
			if not NetProtocol.has_fields(d, { "kind": [TYPE_STRING, 16], "index": TYPE_INT, "rows": [TYPE_ARRAY, 64] }):
				return
			race.mirror_results(d.kind, _rows(d.rows))
		NetProtocol.Msg.NOTE:
			if NetProtocol.has_fields(d, { "id": TYPE_INT, "text": [TYPE_STRING, 80], "seconds": TYPE_FLOAT }):
				var r: Racer = net.owned.get(d.id)
				if r:
					r.notify(NetChat.clean(d.text), clampf(d.seconds, 0.5, 10.0))


## Results rows with each car's Racer here (a stand-in for one that left).
func _rows(raw: Array) -> Array:
	var out := []
	for v: Variant in raw:
		if not v is Dictionary or not NetProtocol.has_fields(v, { "id": TYPE_INT, "position": TYPE_INT, "name": [TYPE_STRING, 64],
				"number": TYPE_INT, "car": [TYPE_STRING, 64], "time": TYPE_FLOAT, "best": TYPE_FLOAT, "laps": TYPE_INT,
				"penalty": TYPE_FLOAT, "dnf": TYPE_BOOL, "gap": [TYPE_STRING, 32], "human": TYPE_BOOL, "assists": [TYPE_STRING, 120],
				"flagged": TYPE_BOOL }):
			continue
		var row: Dictionary = v.duplicate()
		# A battle's columns (D144) and a sumo match's tier (D162), when there.
		for key: String in ["lives", "hits", "taken", "tier"]:
			if row.has(key) and typeof(row[key]) != TYPE_INT:
				row.erase(key)
		if row.has("lasted") and typeof(row.lasted) != TYPE_FLOAT:
			row.erase("lasted")
		if row.has("out") and typeof(row.out) != TYPE_BOOL:
			row.erase("out")
		var r: Racer = net.racers.get(row.id)
		if r == null:
			r = Racer.new()
			r.display_name = row.name
			r.is_human = row.human
			r.number = row.number
			add_child(r) # freed with the session
		row.racer = r
		row.name = NetProtocol.clean_name(row.name)
		out.append(row)
	return out


func _report_assists() -> void:
	for id: int in net.owned:
		var r: Racer = net.owned[id]
		var used := r.assists_used.duplicate()
		if r.custom_setup:
			used["setup"] = true
		var text := JSON.stringify(used)
		if _assists_sent.get(id, "") != text:
			_assists_sent[id] = text
			Net.client.send(NetProtocol.Msg.ASSISTS, { "id": id, "used": used })
