class_name PoliceControl
extends Node
## The police in a highway session (docs/GAMEMODES.md §3, D115, MODE-04), run where the session
## is decided (offline this game, online the server). A unit waits at each speed trap, parked on
## the shoulder, watching. Each player has heat (Heat) from what any unit sees; a level brings
## that many units after them, sent in from behind out of their sight; from ROADBLOCK_LEVEL the
## lanes ahead close bar one, with two units parked across them. Busted: the unbanked score goes,
## the car goes back to the shoulder. Evaded: the units head off and go back to the pool. Every
## change reaches its player as a caption (and narration) and on their HUD's heat meter.

## Units a game may have out at once (the trap units come on top).
const CHASE_UNITS := 5
## Sent in this far behind a player (out of sight), this much faster than them (m/s).
const SEND_BEHIND_M := 400.0
const SEND_FASTER_MPS := 10.0
## A unit nobody's after and every player is this far from goes back to the pool.
const STAND_DOWN_M := 450.0
## Line of sight: from this high on the unit to this high on the car.
const EYE_M := 1.4
## Knocks: a crash the police see, and a ram into a unit (N·s), counted once in this long.
const CRASH_NS := 3000.0
const RAM_NS := 400.0
const KNOCK_AGAIN_S := 2.0
## A roadblock: this far ahead of the player, and opened again once they're this far past it.
const ROADBLOCK_AHEAD_M := 900.0
const ROADBLOCK_LENGTH_M := 60.0
const ROADBLOCK_PAST_M := 150.0
## Sight (line of sight is a ray) and near misses are looked at every this many ticks per player.
const LOOK_EVERY := 2

var session: TrackSession
var layout: HighwayLayout
var police_class := "official.highway.interceptor"
## The pool: every unit (trap ones first).
var units: Array[PoliceRacer] = []
## Racer -> Heat.
var heat := {}
## Counters (checks): pursuits begun, busts, evades, roadblocks.
var pursuits := 0
var busts := 0
var evades := 0
var roadblocks := 0

var _trap_units := {} # PoliceRacer -> trap index
var _miss := {} # Racer -> NearMiss
var _knocked := {} # Racer -> time of the last crash or ram counted
var _blocks := {} # Racer -> {closures, at_m, units}
var _clock := 0.0
var _placed := false
var _told := {} # NetRacer -> [level, evading] last sent to its game
var _seen := {} # Racer -> seen by a unit when last looked
var _ticks := 0


func _ready() -> void:
	process_physics_priority = -44 # after the drivers and the score
	_make_units.call_deferred() # after the players: their places and directions come first


func _make_units() -> void:
	var traps: Array = layout.traps
	for i in traps.size() + CHASE_UNITS:
		var u := PoliceRacer.new()
		u.configure(i)
		u.police_class = police_class
		u.net_id = NetProtocol.FIRST_POLICE_ID + i if session.is_online() else 0
		u.spawn_at = Transform3D(Basis(), Vector3(0, -500.0 - i * 10.0, 0))
		session._add_racer(u)
		u.load_car(PoliceRacer.CAR)
		if session.net and session.is_online():
			session.net.add(u, true)
		units.append(u)
		if i < traps.size():
			_trap_units[u] = i


## Who has heat: this game's players offline; on a server, every player's car.
func players() -> Array:
	var out: Array = []
	out.append_array(session.players) # a plain array: other games' cars go in too
	if Net.is_server():
		for r in session.racers:
			if r is NetRacer and r.is_human:
				out.append(r)
	return out


## Racer `r`'s heat (made the first time).
func heat_of(r: Racer) -> Heat:
	if not heat.has(r):
		heat[r] = Heat.new()
		_miss[r] = NearMiss.new()
	return heat[r]


func _physics_process(delta: float) -> void:
	_clock += delta
	if not _placed:
		_placed = not units.is_empty() and _place_units()
		return
	_ticks += 1
	var i := 0
	for p: Racer in players():
		i += 1
		if p.vehicle == null or not is_instance_valid(p.vehicle) or p.waiting:
			continue
		_watch(p, delta, (i + _ticks) % LOOK_EVERY == 0)
	_dispatch()
	_roadblocks()


## Every unit loaded: the trap ones parked at their traps, the rest in the pool. False until then.
func _place_units() -> bool:
	if units.any(func(u: PoliceRacer) -> bool: return u.vehicle == null):
		return false
	for u in units:
		if _trap_units.has(u):
			var trap: Dictionary = layout.traps[_trap_units[u]]
			u.deploy(_trap_spot(trap), Vector3.ZERO)
			u.ai.mode = PoliceAI.Mode.PARKED
		else:
			u.stand_down()
	return true


## A trap's unit: on the outer shoulder at the trap, facing the way its carriageway drives.
func _trap_spot(trap: Dictionary) -> Transform3D:
	var dir := int(trap.dir)
	var lat := -dir * (layout.half - 1.6)
	var at := layout.main.transform_at(float(trap.at_m), lat)
	if dir < 0:
		at.basis = Basis(-at.basis.x, at.basis.y, -at.basis.z)
	return at


## What the units see of player `p` this tick, and where the chase stands. Sight and near misses
## are looked at on `look` ticks (LOOK_EVERY), what was seen held in between.
func _watch(p: Racer, delta: float, look: bool) -> void:
	var h := heat_of(p)
	var was := h.level()
	var v := p.vehicle
	var nearest := INF
	var seen := false
	var close := false
	for u in units:
		if u.waiting or u.vehicle == null:
			continue
		var d := u.vehicle.global_position.distance_to(v.global_position)
		nearest = minf(nearest, d)
		if look and not seen and d < Heat.SEEN_M and _sees(u, p):
			seen = true
		if d < 8.0:
			var gap := NossTraffic.box_gap(u.vehicle.global_position, u.vehicle.global_basis.z, _half(u.vehicle), v.global_position, v.global_basis.z, _half(v))
			close = close or gap < Heat.BUST_M
	if look:
		_seen[p] = seen
	else:
		seen = bool(_seen.get(p, false))
	if seen:
		var at: Dictionary = session.highway_field.at(p) if session.highway_field else {}
		var limit := layout.speed_at(p.direction, p.distance) * 3.6
		if not at.is_empty() and int(at.get("road", -1)) >= 0:
			limit = float(layout.ramps[int(at.road)].speed) * 3.6
		h.seen_speeding(absf(v.speed()) * 3.6 - limit, delta)
		if look:
			var rows: Array = session.traffic.near_rows(v, 30.0) if session.traffic else []
			for d: Dictionary in (_miss[p] as NearMiss).step(rows, _clock):
				if not d.has("split") and float(d.gap) < ScoreAttack.NEAR_M and absf(float(d.relative_kmh)) >= ScoreAttack.MIN_RELATIVE_KMH:
					h.seen("close" if float(d.gap) < ScoreAttack.CLOSE_M else "near")
		if _clock - float(_knocked.get(p, -INF)) > KNOCK_AGAIN_S and maxf(v.wall_impulse, v.traffic_impulse) > CRASH_NS:
			_knocked[p] = _clock
			h.seen("crash")
	elif look:
		(_miss[p] as NearMiss).step([], _clock)
	# A remote car's knocks come from its game: a crash as its states say, a ram as relayed.
	if v.remote:
		var knocked := v.remote_state != null and v.remote_state.flags & CarState.FLAG_KNOCK != 0
		if seen and knocked and _clock - float(_knocked.get(p, -INF)) > KNOCK_AGAIN_S:
			_knocked[p] = _clock
			h.seen("crash")
		for u in units:
			if session.net and session.net.touched(p.net_id, u.net_id, 0.3):
				close = true
				if _clock - float(_knocked.get(p, -INF)) > KNOCK_AGAIN_S:
					_knocked[p] = _clock
					h.seen("ram")
	# A ram into a unit (seen or not: it's right there).
	elif v.last_hit and v.car_impulse > RAM_NS and units.any(func(u: PoliceRacer) -> bool: return u.vehicle == v.last_hit):
		close = true
		if _clock - float(_knocked.get(p, -INF)) > KNOCK_AGAIN_S:
			_knocked[p] = _clock
			h.seen("ram")
	match h.update(delta, seen, nearest, absf(v.speed()) * 3.6, close):
		"busted":
			busts += 1
			_busted(p)
		"evaded":
			evades += 1
			_end_chase(p)
	if was == 0 and h.level() > 0:
		pursuits += 1
	_tell(p, h)


## Line of sight from unit `u` to `p`'s car over everything solid but cars.
func _sees(u: PoliceRacer, p: Racer) -> bool:
	var space := u.vehicle.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(u.vehicle.global_position + Vector3.UP * EYE_M, p.vehicle.global_position + Vector3.UP * EYE_M,
		Vehicle.LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


## Busted: the unbanked score goes, the car goes back to the shoulder, the units head off.
func _busted(p: Racer) -> void:
	var score := session.get_node_or_null(^"HighwayScore") as HighwayScore
	if score:
		score.rules_for(p).contact(INF, _clock)
	if p is SessionPlayer or not session.is_online():
		session.highway.reset(p)
	_end_chase(p)


func _end_chase(p: Racer) -> void:
	for u in units:
		if u.ai and u.ai.target == p:
			u.ai.target = null
			u.ai.mode = PoliceAI.Mode.PARKED if _trap_units.has(u) else PoliceAI.Mode.RETURN
	_open_roadblock(p)


## Each player with heat has as many units after them as their level (the trap units that saw
## them join first); units nobody's after go back once everyone's far.
func _dispatch() -> void:
	for key: Variant in heat.keys():
		if not is_instance_valid(key):
			heat.erase(key) # gone from the session
			continue
		var p := key as Racer
		var h: Heat = heat[p]
		if h.level() == 0 or p.vehicle == null:
			continue
		var after := units.filter(func(u: PoliceRacer) -> bool: return u.ai and u.ai.target == p).size()
		while after < h.level():
			var u := _free_unit(p)
			if u == null:
				break
			_chase(u, p)
			after += 1
	for u in units:
		if u.waiting or u.vehicle == null or _trap_units.has(u) or (u.ai and u.ai.target):
			continue
		var far := players().all(func(p: Racer) -> bool: return p.vehicle == null or p.vehicle.global_position.distance_to(u.vehicle.global_position) > STAND_DOWN_M)
		if far:
			u.stand_down()


## A unit to send after `p`: a trap unit near them first, else one from the pool.
func _free_unit(p: Racer) -> PoliceRacer:
	for u in units:
		if _trap_units.has(u) and u.ai and u.ai.target == null and u.vehicle and u.vehicle.global_position.distance_to(p.vehicle.global_position) < Heat.SEEN_M:
			return u
	for u in units:
		if not _trap_units.has(u) and u.waiting and u.vehicle:
			return u
	return null


func _chase(u: PoliceRacer, p: Racer) -> void:
	if u.waiting:
		# In from behind, out of sight, at the player's speed, in a lane of their carriageway.
		var dir := p.direction
		var lane := randi() % layout.lanes
		var at := layout.main.transform_at(p.distance - dir * SEND_BEHIND_M, layout.lane_lateral(dir, lane))
		if dir < 0:
			at.basis = Basis(-at.basis.x, at.basis.y, -at.basis.z)
		u.deploy(at, at.basis.z * (maxf(absf(p.vehicle.speed()), 25.0) + SEND_FASTER_MPS))
	u.ai.target = p
	u.ai.side = 1.0 if units.find(u) % 2 == 0 else -1.0
	u.ai.mode = PoliceAI.Mode.PURSUE


## From ROADBLOCK_LEVEL a roadblock ahead of each player chased: their carriageway's lanes closed
## bar the outer one, two units parked across; it opens once they're past (or the chase ends).
func _roadblocks() -> void:
	for key: Variant in heat.keys():
		if not is_instance_valid(key):
			continue
		var p := key as Racer
		if p.vehicle == null:
			continue
		var h: Heat = heat[p]
		if _blocks.has(p):
			var b: Dictionary = _blocks[p]
			if fposmod(p.direction * (p.distance - float(b.at_m)), layout.main.length) < layout.main.length / 2.0 \
					and fposmod(p.direction * (p.distance - float(b.at_m)), layout.main.length) > ROADBLOCK_PAST_M:
				_open_roadblock(p)
			continue
		if h.level() < Heat.ROADBLOCK_LEVEL:
			continue
		var dir := p.direction
		var at_m := fposmod(p.distance + dir * ROADBLOCK_AHEAD_M, layout.main.length)
		var closures := []
		if session.traffic:
			for lane in range(1, layout.lanes):
				var id := session.traffic.close_lane(dir, lane, at_m - dir * ROADBLOCK_LENGTH_M, ROADBLOCK_LENGTH_M * 2.0)
				if id >= 0:
					closures.append(id)
		var parked := []
		for i in 2:
			var u := _pool_unit()
			if u == null:
				break
			var lat := layout.lane_lateral(dir, 1 + i)
			var spot := layout.main.transform_at(at_m, lat)
			spot.basis = Basis(Vector3.UP, PI / 2.0 * (1 if i == 0 else -1)) * spot.basis # across the lanes
			u.deploy(spot, Vector3.ZERO)
			u.ai.mode = PoliceAI.Mode.PARKED
			u.vehicle.light_bar = true
			parked.append(u)
		_blocks[p] = { "closures": closures, "at_m": at_m, "units": parked }
		roadblocks += 1
		p.notify("Roadblock ahead", 3.0)


func _pool_unit() -> PoliceRacer:
	for u in units:
		if not _trap_units.has(u) and u.waiting and u.vehicle:
			return u
	return null


func _open_roadblock(p: Racer) -> void:
	if not _blocks.has(p):
		return
	var b: Dictionary = _blocks[p]
	for id: int in b.closures:
		if session.traffic:
			session.traffic.open_lanes(id)
	for u: PoliceRacer in b.units:
		u.stand_down()
	_blocks.erase(p)


## What changed for `p`: a caption (and narration) for this game's players, and the heat meter;
## online, the same for another game's player goes to that game (HW_EVENT).
func _tell(p: Racer, h: Heat) -> void:
	if p is NetRacer:
		var sent: Array = _told.get(p, [-1, -1.0])
		var evading := snappedf(h.evading(), 0.1)
		if not h.news.is_empty() or h.level() != int(sent[0]) or evading != float(sent[1]):
			_told[p] = [h.level(), evading]
			var news: Dictionary = h.news.back() if not h.news.is_empty() else { "kind": "heat", "text": "" }
			Net.server.send((p as NetRacer).peer, NetProtocol.Msg.HW_EVENT, { "id": p.net_id, "kind": String(news.kind),
				"level": h.level(), "evading": evading, "text": String(news.text) })
		h.news.clear()
		return
	for n: Dictionary in h.news:
		p.notify(String(n.text), 2.5)
		if p is SessionPlayer and Narrator.race_on((p as SessionPlayer).slot.profile):
			Narrator.say(String(n.text))
	h.news.clear()
	if p is SessionPlayer:
		var panel := (p as SessionPlayer).hud.get_node_or_null(^"HeatPanel") as HeatPanel
		if panel == null:
			panel = HeatPanel.new()
			panel.name = "HeatPanel"
			(p as SessionPlayer).hud.add_child(panel)
		panel.show_heat(h.level(), h.evading())


static func _half(v: Vehicle) -> Vector2:
	var e := v.fitted.envelope if v.fitted else AABB(Vector3(-0.9, 0, -2.2), Vector3(1.8, 1.4, 4.4))
	return Vector2(e.size.z / 2.0, e.size.x / 2.0)
