class_name NetBot
extends Node
## A headless bot client for load tests (`--bot`, tools/net_check.py, D88): joins with throwaway
## keys and its own players (`--players=n`), picks cars, readies and drives with the racing AI. It
## prints what it measured as one line, "NETCHECK {json}", when it quits: bytes per second down
## and up, how far off the remote cars it showed were, its cars' contacts with other cars (for
## pile-ups), each also printed as it happens ("NETCHECK_CONTACT …"), and the lowest ENet packet
## throttle it saw (below 32, ENet drops car states). A track it had to fetch prints
## "NETCHECK_TRACK <ms>" when it's here. On a highway it also reports its traffic (D109):
## checksums that disagreed, full states taken, late events, handovers, the most physics cars it
## drove at once, and the slowest its lane sim kept up (ticks a second).

const CONTACT_IMPULSE := 150.0 # N·s in one tick counts as contact (as race_check)

var _down: Array[float] = [] # bytes per second, while in a session
var _up: Array[float] = []
var _contacts := 0
var _sample := 0.0
var _sessions := 0
var _last_hit := {} # own car id -> [other id, time]
var _errors := PackedFloat32Array()
var _remote_cars := 0
var _throttle_min := 32 # ENet's packet throttle toward the server (32: nothing dropped)
## --bot-full: when every car in the session was here as a preview and whole (s after it began).
var _session_start := -1.0
var _cars := 0
var _preview_s := -1.0
var _full_s := -1.0
var _traffic := {}
var _owned_max := 0
var _tick_last := -1
var _tick_rate_min := INF
var _traffic_errors := PackedFloat32Array()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	NetRacer.measure = true
	Net.session_started.connect(func(_d: Dictionary) -> void:
		_sessions += 1
		if _session_start < 0.0:
			_session_start = Time.get_ticks_msec() / 1000.0)


func _physics_process(delta: float) -> void:
	if Net.content and not Net.content.track_ready.is_connected(_on_track):
		Net.content.track_ready.connect(_on_track)
	_time_cars()
	var session := _session()
	if session == null or session.net == null:
		return
	_sample += delta
	if _sample >= 1.0:
		_sample = 0.0
		var host := Net.client.enet.host if Net.client and Net.client.enet else null
		if host:
			_down.append(host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
			_up.append(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
			var p := Net.client.enet.get_peer(1)
			if p:
				_throttle_min = mini(_throttle_min, int(p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)))
		# The session may be gone when this quits: collect as it goes.
		var remote := 0
		for r: Racer in session.racers:
			if r is NetRacer:
				remote += 1
				_errors.append_array((r as NetRacer).errors)
				(r as NetRacer).errors.clear()
		_remote_cars = maxi(_remote_cars, remote) # the most seen at once
		_traffic_sample(session)
	for id: int in session.net.owned:
		var r: Racer = session.net.owned[id]
		var v := r.vehicle
		if v == null or v.car_impulse < CONTACT_IMPULSE or not v.last_hit or not is_instance_valid(v.last_hit):
			continue
		var other := _id_of(session, v.last_hit)
		var now := session.net.now()
		var last: Array = _last_hit.get(id, [-1, -10.0])
		if other == last[0] and now - float(last[1]) < 0.5:
			continue # the same knock
		_last_hit[id] = [other, now]
		_contacts += 1
		var p := v.global_position
		print("NETCHECK_CONTACT %.3f %d %d %.1f %.1f %.1f" % [now, id, other, p.x, p.y, p.z])


## Once a second: the highway traffic's counters (the session may be gone when this quits).
func _traffic_sample(session: TrackSession) -> void:
	var hn := session.get_node_or_null(^"HighwayNet") as HighwayNet
	if hn == null or session.traffic == null:
		return
	_owned_max = maxi(_owned_max, session.net.traffic_owned.size())
	for tc: TrafficCar in session.traffic.cars.values():
		_traffic_errors.append_array(tc.errors)
		tc.errors.clear()
	var tick := session.traffic.sim.get_tick()
	if session.traffic.synced and _tick_last >= 0 and hn.resyncs > 0:
		_tick_rate_min = minf(_tick_rate_min, tick - _tick_last)
	_tick_last = tick if session.traffic.synced else -1
	var e := Array(_traffic_errors)
	e.sort()
	_traffic = { "mismatches": hn.mismatches, "resyncs": hn.resyncs, "late": hn.late, "handovers": hn.handovers, "beats": hn.beats,
		"owned_max": _owned_max, "tick_rate_min": _tick_rate_min if _tick_rate_min < INF else -1.0, "physics_max": session.traffic.cars.size(),
		"err_n": e.size(), "err_p95": e[int(e.size() * 0.95)] if not e.is_empty() else 0.0 }


func _on_track(h: String) -> void:
	print("NETCHECK_TRACK %d" % Net.content.track_ms(h))


## --bot-full: has every car of the session arrived (as a preview, whole)?
func _time_cars() -> void:
	if _session_start < 0.0 or _full_s >= 0.0 or Net.content == null or Net.session.is_empty():
		return
	var hashes := {}
	for d: Dictionary in Net.session.get("roster", []):
		if String(d.get("car", "")) and String(d.get("car_note", "")).is_empty():
			hashes[d.car] = true
	_cars = hashes.size()
	var preview := true
	var full := true
	for h: String in hashes:
		var tier := String(Net.content.car(h).get("tier", ""))
		preview = preview and tier in ["preview", "full"]
		full = full and tier == "full"
	var t := Time.get_ticks_msec() / 1000.0 - _session_start
	if preview and _preview_s < 0.0:
		_preview_s = t
		print("NETCHECK_CARS preview %.1f s (%d cars)" % [t, _cars])
	if full:
		_full_s = t
		print("NETCHECK_CARS full %.1f s (%d cars)" % [t, _cars])


func _session() -> TrackSession:
	return get_tree().current_scene as TrackSession


static func _id_of(session: TrackSession, v: Vehicle) -> int:
	if v.traffic_id >= 0:
		return NetProtocol.FIRST_TRAFFIC_ID + v.traffic_id
	for id: int in session.net.racers:
		var r: Racer = session.net.racers[id]
		if r.vehicle == v:
			return id
	return -1


func _exit_tree() -> void:
	var e := Array(_errors)
	e.sort()
	# Bandwidth from the steady part: the first seconds carry the lobby and car data.
	var steady := _down.slice(mini(10, _down.size() / 3))
	var steady_up := _up.slice(mini(10, _up.size() / 3))
	print("NETCHECK " + JSON.stringify({
		"players": Net.my_ids.size(), "sessions": _sessions, "seconds": _down.size(),
		"down_avg": _avg(steady) / 1024.0, "down_max": (steady.max() if not steady.is_empty() else 0.0) / 1024.0,
		"up_avg": _avg(steady_up) / 1024.0,
		"err_n": e.size(), "err_median": e[e.size() / 2] if not e.is_empty() else 0.0,
		"err_p95": e[int(e.size() * 0.95)] if not e.is_empty() else 0.0, "err_max": e.back() if not e.is_empty() else 0.0,
		"contacts": _contacts, "remote_cars": _remote_cars, "throttle_min": _throttle_min,
		"rtt_ms": Net.client.rtt_ms() if Net.client else 0.0,
		"cars": _cars, "preview_s": _preview_s, "full_s": _full_s, "traffic": _traffic,
	}))


static func _avg(a: Array) -> float:
	var total := 0.0
	for x: float in a:
		total += x
	return total / a.size() if not a.is_empty() else 0.0
