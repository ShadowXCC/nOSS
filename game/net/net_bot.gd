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
## drove at once, and the slowest its lane sim kept up (ticks a second). In a kart session it
## reports its items (D141): uses, hits on its cars, the server's corrections and how far its
## items were from the server's (p95). On an endless road (D159) it reports how far it drove, its
## origin's moves, where it started against the leader, the traffic cars it drove and showed from
## other games, and how long another player was near. In a time trial (P10) it reports the most
## drivers it saw on the server's live board and whether its own car was ever on it.

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
var _kart := {}
var _kart_errors := PackedFloat32Array()
var _chaser_errors := PackedFloat32Array()
var _kart_uses := 0
var _kart_hits := 0
var _endless := {}
var _endless_lead := NAN # the furthest player's spot when it joined (m)
var _spawn_m := NAN # where its first player started on the road (m)
var _proxies_max := 0
var _siren_proxies := 0
var _owned_traffic_max := 0
var _near_s := 0
var _kart_hooked: KartItems
var _tt := {}


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
		_kart_sample(session)
		_endless_sample(session)
		_tt_sample(session)
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
		if session.origin: # world metres: each game has its own origin
			p += Vector3(session.origin.x, 0.0, session.origin.z)
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


## Once a second: an endless road's counters.
func _endless_sample(session: TrackSession) -> void:
	var en := session.endless_net
	if en == null or session.players.is_empty():
		return
	if is_nan(_endless_lead):
		var at: Variant = session.online.get("endless", {}).get("at", {})
		_endless_lead = -1.0
		for v: Variant in at.values() if at is Dictionary else []:
			if v is Array and not (v as Array).is_empty():
				_endless_lead = maxf(_endless_lead, float(v[0]))
	var t: EndlessTraffic = session.endless_traffic
	if t:
		var proxies := 0
		for c: EndlessTrafficCar in t.cars.values():
			proxies += 1 if c.remote else 0
		_proxies_max = maxi(_proxies_max, proxies)
		_owned_traffic_max = maxi(_owned_traffic_max, t.cars.size() - proxies)
	var me: Racer = session.players[0]
	if is_nan(_spawn_m) and me.vehicle:
		_spawn_m = float(session.track.project(me.spawn_at.origin).distance)
	for id: int in en.at:
		if not id in Net.my_ids and absf(en.distance_of(id) - me.distance) < 300.0:
			_near_s += 1
			break
	# The police (D195): this game's chases, and the most of another game's units seen with sirens on.
	var sirens := 0
	for r in session.racers:
		if r is NetRacer and NetProtocol.is_endless_police(r.net_id) and r.vehicle and r.vehicle.siren:
			sirens += 1
	_siren_proxies = maxi(_siren_proxies, sirens)
	_endless = { "km": (me.distance - session.endless_start_m) / 1000.0, "start_m": session.endless_start_m, "spawn_m": _spawn_m, "lead_m": _endless_lead,
		"shifts": session.origin.shifts, "owned_max": _owned_traffic_max, "proxies_max": _proxies_max, "handovers": en.handovers,
		"gone": t.gone.size() if t else 0, "near_s": _near_s, "pursuits": session.police.pursuits if session.police else 0,
		"siren_proxies": _siren_proxies }


## Once a second: a time trial's live board (TimeTrialNet), as the server sent it.
func _tt_sample(session: TrackSession) -> void:
	var tn := session.time_trial_net
	if tn == null:
		return
	var on := bool(_tt.get("on_board", false))
	for id: int in session.net.owned:
		on = on or tn.place_of(id) > 0
	_tt = { "board_max": maxi(int(_tt.get("board_max", 0)), tn.entries.size()), "on_board": on }


## Once a second: the kart items' counters.
func _kart_sample(session: TrackSession) -> void:
	var kn := session.get_node_or_null(^"KartNet") as KartNet
	if kn == null:
		return
	if _kart_hooked != session.kart.items:
		_kart_hooked = session.kart.items
		_kart_hooked.used.connect(func(r: Racer, _item: String) -> void:
			if session.net.owned.has(r.net_id):
				_kart_uses += 1)
		_kart_hooked.hit_landed.connect(func(victim: Racer, _a: Racer, _kind: String, _blocked: bool) -> void:
			if session.net.owned.has(victim.net_id):
				_kart_hits += 1)
	_kart_errors.append_array(PackedFloat32Array(kn.entity_errors))
	kn.entity_errors.clear()
	_chaser_errors.append_array(PackedFloat32Array(kn.chaser_errors))
	kn.chaser_errors.clear()
	var e := Array(_kart_errors)
	e.sort()
	var c := Array(_chaser_errors)
	c.sort()
	_kart = { "uses": _kart_uses, "hits": _kart_hits, "corrections": kn.corrections, "err_n": e.size(),
		"err_p95": e[int(e.size() * 0.95)] if not e.is_empty() else 0.0,
		"chaser_p95": c[int(c.size() * 0.95)] if not c.is_empty() else 0.0,
		"class": String(session.players[0].platform.platform.id) if not session.players.is_empty() and session.players[0].platform else "" }


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
		"cars": _cars, "preview_s": _preview_s, "full_s": _full_s, "traffic": _traffic, "kart": _kart, "endless": _endless, "tt": _tt,
	}))


static func _avg(a: Array) -> float:
	var total := 0.0
	for x: float in a:
		total += x
	return total / a.size() if not a.is_empty() else 0.0
