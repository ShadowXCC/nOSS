class_name PoliceControl
extends Node
## The police (docs/GAMEMODES.md §3, §4, D115, D192, MODE-04) on the road they work (PoliceRoad: a
## highway, run where the session is decided; the endless road, run by each game for its own
## players). A unit waits at each speed trap, parked on the shoulder, watching. Each player has
## heat (Heat) from what any unit sees; the level (PoliceTuning) says how many units come after
## them, sent in from behind out of their sight, how hard they drive, and when the lanes ahead
## close bar one, with two units parked across them. Busted: what the road says (a highway takes
## the unbanked score and puts the car on the shoulder). Evaded: the units head off and go back to
## the pool. Every change reaches its player as a caption (and narration) and on their HUD's heat
## meter.

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
## Spike strips: this far ahead of the player (the first straight in it), on a straight this long.
const SPIKES_FROM_M := 300.0
const SPIKES_TO_M := 450.0
const SPIKES_STRAIGHT_M := 90.0

var session: TrackSession
var road: PoliceRoad
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
var spikes_laid := 0
var patrols_converted := 0
## The spike strips down now.
var strips: Array[SpikeStrip] = []

var _trap_units := {} # PoliceRacer -> trap index
var _miss := {} # Racer -> NearMiss
var _knocked := {} # Racer -> time of the last crash or ram counted
var _blocks := {} # Racer -> {closures, at_m, units}
var _clock := 0.0
var _placed := false
var _told := {} # NetRacer -> [level, evading] last sent to its game
var _seen := {} # Racer -> seen by a unit when last looked
var _ticks := 0
var _next_spikes := {} # Racer -> when the next strip may go down (the police's clock)


func _ready() -> void:
	process_physics_priority = -44 # after the drivers and the score
	_make_units.call_deferred() # after the players: their places and directions come first


func _make_units() -> void:
	var traps: Array = road.traps()
	for i in traps.size() + road.chase_units():
		var u := PoliceRacer.new()
		u.configure(i)
		u.police_class = police_class
		u.road = road
		u.net_id = road.unit_id(i)
		u.spawn_at = Transform3D(Basis(), Vector3(0, -500.0 - i * 10.0, 0))
		session._add_racer(u)
		u.load_car(PoliceRacer.CAR)
		road.register_unit(u)
		units.append(u)
		if i < traps.size():
			_trap_units[u] = i


## Who has heat (the road says).
func players() -> Array:
	return road.watched_players()


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
	_spikes()
	road.move_over(units.filter(func(u: PoliceRacer) -> bool: return not u.waiting and u.vehicle and u.vehicle.siren))


## Every unit loaded: the trap ones parked at their traps, the rest in the pool. False until then.
func _place_units() -> bool:
	if units.any(func(u: PoliceRacer) -> bool: return u.vehicle == null):
		return false
	for u in units:
		if _trap_units.has(u):
			var trap: Dictionary = road.traps()[_trap_units[u]]
			u.deploy(_trap_spot(trap), Vector3.ZERO)
			u.ai.mode = PoliceAI.Mode.PARKED
		else:
			u.stand_down()
	return true


## A trap's unit: on the shoulder at the trap, facing the way it watches.
func _trap_spot(trap: Dictionary) -> Transform3D:
	return road.trap_spot(trap)


## What the units see of player `p` this tick, and where the chase stands. Sight and near misses
## are looked at on `look` ticks (LOOK_EVERY), what was seen held in between.
func _watch(p: Racer, delta: float, look: bool) -> void:
	var h := heat_of(p)
	var was := h.level()
	var sight := float(PoliceTuning.at(was).sight_m)
	var v := p.vehicle
	var nearest := INF
	var seen := false
	var close := false
	# Patrol cars in the traffic watch too (D192).
	for pt: Dictionary in road.patrols(v.global_position, sight) if look else []:
		if not seen and _sees_from((pt.xform as Transform3D).origin, p):
			seen = true
	for u in units:
		if u.waiting or u.vehicle == null:
			continue
		var d := u.vehicle.global_position.distance_to(v.global_position)
		nearest = minf(nearest, d)
		if look and not seen and d < sight and _sees(u, p):
			seen = true
		if d < 8.0:
			var gap := NossTraffic.box_gap(u.vehicle.global_position, u.vehicle.global_basis.z, _half(u.vehicle), v.global_position, v.global_basis.z, _half(v))
			close = close or gap < Heat.BUST_M
	if look:
		_seen[p] = seen
	else:
		seen = bool(_seen.get(p, false))
	if seen:
		h.seen_speeding(absf(v.speed()) * 3.6 - road.limit_mps(p) * 3.6, delta)
		if look:
			var rows := road.near_rows(v, 30.0)
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
	return _sees_from(u.vehicle.global_position, p)


func _sees_from(at: Vector3, p: Racer) -> bool:
	var space := p.vehicle.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * EYE_M, p.vehicle.global_position + Vector3.UP * EYE_M, Vehicle.LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


## Busted: what the road does about it, and the units head off.
func _busted(p: Racer) -> void:
	road.after_bust(p, _clock)
	for n: Dictionary in heat_of(p).news:
		if n.kind == "busted":
			n.text = road.bust_text(p)
	_end_chase(p)


## A speed camera snapped `r` going `speed` (m/s, EndlessTraps): seen speeding if they were.
func camera_snap(r: Racer, trap: Dictionary, speed: float) -> void:
	if trap.kind == "camera" and (speed - road.limit_mps(r)) * 3.6 >= Heat.SPEEDING_KMH:
		heat_of(r).seen("camera")


func _end_chase(p: Racer) -> void:
	_next_spikes.erase(p)
	for u in units:
		if u.ai and u.ai.target == p:
			u.ai.target = null
			u.ai.mode = PoliceAI.Mode.PARKED if _trap_units.has(u) else PoliceAI.Mode.RETURN
	_open_roadblock(p)


## Each player with heat has as many units after them as their level calls for (the trap units
## that saw them join first), driving to that level; units nobody's after go back once everyone's
## far.
func _dispatch() -> void:
	for key: Variant in heat.keys():
		if not is_instance_valid(key):
			heat.erase(key) # gone from the session
			continue
		var p := key as Racer
		var h: Heat = heat[p]
		if h.level() == 0 or p.vehicle == null:
			continue
		var level := h.level()
		var chasing := units.filter(func(u: PoliceRacer) -> bool: return u.ai and u.ai.target == p)
		while chasing.size() < int(PoliceTuning.at(level).units):
			var u := _free_unit(p)
			if u == null:
				break
			_chase(u, p)
			chasing.append(u)
		# Roles in the pool's order, sides alternating: the first two come at it from either side.
		for i in chasing.size():
			var u: PoliceRacer = chasing[i]
			u.ai.level = level
			u.ai.role = PoliceTuning.role(level, i)
			u.ai.side = 1.0 if i % 2 == 0 else -1.0
	for u in units:
		if u.waiting or u.vehicle == null or _trap_units.has(u) or (u.ai and u.ai.target):
			continue
		var far := players().all(func(p: Racer) -> bool: return p.vehicle == null or p.vehicle.global_position.distance_to(u.vehicle.global_position) > STAND_DOWN_M)
		if far:
			u.stand_down()


## A unit to send after `p`: a trap unit near them first, then a patrol car near them (a pool unit
## takes its place in the traffic, as it was going), else one from the pool.
func _free_unit(p: Racer) -> PoliceRacer:
	var sight := float(PoliceTuning.at(heat_of(p).level()).sight_m)
	for u in units:
		if _trap_units.has(u) and u.ai and u.ai.target == null and u.vehicle and u.vehicle.global_position.distance_to(p.vehicle.global_position) < sight:
			return u
	var pool := _pool_unit()
	if pool == null:
		return null
	var best: Dictionary = {}
	for pt: Dictionary in road.patrols(p.vehicle.global_position, sight):
		if best.is_empty() or (pt.xform as Transform3D).origin.distance_to(p.vehicle.global_position) < (best.xform as Transform3D).origin.distance_to(p.vehicle.global_position):
			best = pt
	if not best.is_empty():
		road.convert_patrol(best)
		pool.deploy(best.xform, best.velocity)
		patrols_converted += 1
	return pool


func _chase(u: PoliceRacer, p: Racer) -> void:
	if u.waiting:
		# In from behind, out of sight, at the player's speed, in a lane of their way.
		var at := road.lane_xform(road.way(p), randi() % road.lanes(), road.along(p, -SEND_BEHIND_M))
		u.deploy(at, at.basis.z * (maxf(absf(p.vehicle.speed()), 25.0) + SEND_FASTER_MPS))
	u.ai.level = heat_of(p).level()
	u.ai.target = p
	u.ai.mode = PoliceAI.Mode.PURSUE


## From the level that calls for it, a roadblock ahead of each player chased: their way's lanes
## closed bar one, two units parked across; it opens once they're past (or the chase ends).
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
			if road.past(p, float(b.at_m)) > ROADBLOCK_PAST_M:
				_open_roadblock(p)
			continue
		if not PoliceTuning.at(h.level()).roadblock or h.level() == 0:
			continue
		var dir := road.way(p)
		var at_m := road.along(p, ROADBLOCK_AHEAD_M)
		var closures := road.close_lanes(p, dir, at_m - dir * ROADBLOCK_LENGTH_M, ROADBLOCK_LENGTH_M * 2.0)
		var parked := []
		var across := road.block_lanes(dir)
		for i in mini(across.size(), 2):
			var u := _pool_unit()
			if u == null:
				break
			u.deploy(road.across_xform(dir, int(across[i]), at_m, i), Vector3.ZERO)
			u.ai.mode = PoliceAI.Mode.PARKED
			u.vehicle.light_bar = true
			parked.append(u)
		_blocks[p] = { "closures": closures, "at_m": at_m, "units": parked }
		roadblocks += 1
		p.notify("Roadblock ahead", 3.0)


## From the level that calls for them, now and then a spike strip on a straight ahead of each
## player chased, half a lane left open; each comes up once they're well past it.
func _spikes() -> void:
	for strip in strips.duplicate():
		if strip.done():
			strips.erase(strip)
			strip.queue_free()
	if not road.spikes_allowed():
		return
	for key: Variant in heat.keys():
		if not is_instance_valid(key):
			continue
		var p := key as Racer
		var every := float(PoliceTuning.at((heat[p] as Heat).level()).spikes_s)
		if p.vehicle == null or (heat[p] as Heat).level() == 0 or every <= 0.0:
			_next_spikes.erase(p)
			continue
		if not _next_spikes.has(p):
			_next_spikes[p] = _clock + every * 0.5
		if _clock < float(_next_spikes[p]):
			continue
		_next_spikes[p] = _clock + every
		var way := road.way(p)
		var m := SPIKES_FROM_M
		while m <= SPIKES_TO_M:
			var d := road.along(p, m)
			if road.straight_clear(road.along(p, m - SPIKES_STRAIGHT_M / 2.0), way, SPIKES_STRAIGHT_M):
				lay_spikes(p, d)
				break
			m += 25.0


## A strip for `p` at distance `d` across their way.
func lay_spikes(p: Racer, d: float) -> SpikeStrip:
	var strip := SpikeStrip.new()
	strip.road = road
	strip.at_m = d
	var span := road.strip_span(road.way(p), d)
	strip.lat_from = span.x
	strip.lat_to = span.y
	strip.for_racer = p
	strip.watch = players()
	session.add_child(strip)
	strips.append(strip)
	spikes_laid += 1
	p.notify("Spikes ahead", 2.5)
	return strip


func _pool_unit() -> PoliceRacer:
	for u in units:
		if not _trap_units.has(u) and u.waiting and u.vehicle:
			return u
	return null


func _open_roadblock(p: Racer) -> void:
	if not _blocks.has(p):
		return
	var b: Dictionary = _blocks[p]
	road.open_lanes(b.closures)
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
