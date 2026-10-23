class_name HighwayPoliceRoad
extends PoliceRoad
## The police's road on a highway (D115, D192): its layout's lanes, limits and traps, its traffic
## (the lane sim and the physics cars), the field for who's on a ramp, and the score a bust costs.
## The police run where the session is decided: offline this game, online the server, which
## watches every player's car. The road is a loop: distances wrap.

var layout: HighwayLayout
## Each siren's lane closed ahead of it (D192): PoliceRacer -> closure id; renewed every MOVE_S.
var _moving := {}
var _move_left := 0.0

## Traffic moves over out of a siren's lane this far ahead of it, renewed this often.
const MOVE_AHEAD_M := 150.0
const MOVE_S := 1.0


static func make(s: TrackSession) -> HighwayPoliceRoad:
	var r := HighwayPoliceRoad.new()
	r.session = s
	r.layout = s.track.highway
	r.layout.bend_room(1) # made now, not mid-chase
	r.layout.bend_room(-1)
	return r


## This game's players offline; on a server, every player's car.
func watched_players() -> Array:
	var out: Array = []
	out.append_array(session.players) # a plain array: other games' cars go in too
	if Net.is_server():
		for r in session.racers:
			if r is NetRacer and r.is_human:
				out.append(r)
	return out


## The carriageway's limit, or the ramp's on a ramp.
func limit_mps(p: Racer) -> float:
	var at: Dictionary = session.highway_field.at(p) if session.highway_field else {}
	if not at.is_empty() and int(at.get("road", -1)) >= 0:
		return float(layout.ramps[int(at.road)].speed)
	return layout.speed_at(p.direction, p.distance)


func way(p: Racer) -> int:
	return p.direction


func along(p: Racer, m: float) -> float:
	return fposmod(p.distance + p.direction * m, layout.main.length)


func past(p: Racer, at_m: float) -> float:
	var length := layout.main.length
	var ahead := fposmod(p.direction * (p.distance - at_m), length)
	return ahead if ahead < length / 2.0 else ahead - length


func delta_m(a: float, b: float) -> float:
	var length := layout.main.length
	return fposmod(a - b + length / 2.0, length) - length / 2.0


func lanes() -> int:
	return layout.lanes


func project(pos: Vector3) -> Dictionary:
	return layout.main.project(pos)


## Lane 0 is the outer one.
func lane_xform(way_dir: int, lane: int, d: float) -> Transform3D:
	var at := layout.main.transform_at(d, layout.lane_lateral(way_dir, lane))
	if way_dir < 0:
		at.basis = Basis(-at.basis.x, at.basis.y, -at.basis.z)
	return at


func shoulder_xform(way_dir: int, d: float) -> Transform3D:
	var at := layout.main.transform_at(d, -way_dir * (layout.half - 1.6))
	if way_dir < 0:
		at.basis = Basis(-at.basis.x, at.basis.y, -at.basis.z)
	return at


## On the outer shoulder of `p`'s carriageway about `m` on, clear of ramp mouths and traps (where
## a player starts or is reset). Nowhere while `p` is on a ramp: where they're headed isn't known.
func ahead_spot(p: Racer, m: float) -> Dictionary:
	var at: Dictionary = session.highway_field.at(p) if session.highway_field else {}
	if session.highway == null or int(at.get("road", -1)) >= 0:
		return {}
	var d: float = session.highway.clear_shoulder(p.direction, along(p, m))
	return { "xform": session.highway.shoulder_spot(p.direction, d), "at_m": d }


## Across the carriageway as it lies (the units don't turn round for the way they face).
func across_xform(way_dir: int, lane: int, d: float, i: int) -> Transform3D:
	var spot := layout.main.transform_at(d, layout.lane_lateral(way_dir, lane))
	spot.basis = Basis(Vector3.UP, PI / 2.0 * (1 if i == 0 else -1)) * spot.basis
	return spot


## Nearly straight (no bend tighter than 600 m) for `length` m on.
func straight_clear(d: float, way_dir: int, length: float) -> bool:
	var main := layout.main
	var s := 0.0
	while s <= length:
		if absf(main.curvature[main.index_at(fposmod(d + way_dir * s, main.length))]) > 1.0 / 600.0:
			return false
		s += 10.0
	return true


## Not online: the server can't flatten a tyre on a car another game drives.
func spikes_allowed() -> bool:
	return not session.is_online()


## The carriageway from the median's edge out, half its outer lane left open.
func strip_span(way_dir: int, _d: float) -> Vector2:
	var a := -way_dir * layout.inner
	var b := -way_dir * (layout.inner + (layout.lanes - 0.5) * layout.lane_m)
	return Vector2(minf(a, b), maxf(a, b))


func near_rows(v: Vehicle, radius: float) -> Array:
	return session.traffic.near_rows(v, radius) if session.traffic else []


## Every lane but the outer one.
func close_lanes(_p: Racer, way_dir: int, d: float, length: float) -> Array:
	var out := []
	if session.traffic:
		for lane in range(1, layout.lanes):
			var id := session.traffic.close_lane(way_dir, lane, d, length)
			if id >= 0:
				out.append(id)
	return out


func open_lanes(closures: Array) -> void:
	for id: int in closures:
		if session.traffic:
			session.traffic.open_lanes(id)


func block_lanes(_way: int) -> Array:
	return [1, 2]


func patrols(pos: Vector3, radius: float) -> Array:
	return session.traffic.patrols_near(pos, radius) if session.traffic else []


func convert_patrol(patrol: Dictionary) -> void:
	session.traffic.retire(int(patrol.car))


## The lane sim moves its cars out of each siren's lane, from the unit to MOVE_AHEAD_M ahead (a
## closure that goes along with it); physics cars slow as one comes up (TrafficCar).
func move_over(units: Array) -> void:
	var tm := session.traffic
	if tm == null or not tm.authority:
		return
	_move_left -= 1.0 / Engine.physics_ticks_per_second
	for u: PoliceRacer in _moving.keys():
		if not u in units:
			tm.open_lanes(int(_moving[u]))
			_moving.erase(u)
	if _move_left > 0.0:
		return
	_move_left = MOVE_S
	for u: PoliceRacer in units:
		if _moving.has(u):
			tm.open_lanes(int(_moving[u]))
			_moving.erase(u)
		var proj := layout.main.project(u.vehicle.global_position)
		var dir := HighwayLayout.carriageway_at(float(proj.lateral))
		if u.vehicle.global_basis.z.dot(layout.main.transform_at(float(proj.distance)).basis.z) * dir < 0.0:
			continue # against its carriageway: nothing to clear
		var id := tm.close_lane(dir, layout.lane_at(float(proj.lateral)), float(proj.distance), MOVE_AHEAD_M, true)
		if id >= 0:
			_moving[u] = id


func traps() -> Array:
	return layout.traps


## On the outer shoulder at the trap, facing the way its carriageway drives.
func trap_spot(trap: Dictionary) -> Transform3D:
	return shoulder_xform(int(trap.dir), float(trap.at_m))


## Online the units are the server's cars.
func unit_id(i: int) -> int:
	return NetProtocol.FIRST_POLICE_ID + i if session.is_online() else 0


func register_unit(u: PoliceRacer) -> void:
	if session.net and session.is_online():
		session.net.add(u, true)


func make_driver(_u: PoliceRacer) -> Node:
	return PoliceAI.new()


## The unbanked score goes, the car goes back to the shoulder (a server leaves another game's car
## to that game).
func after_bust(p: Racer, clock: float) -> void:
	var score := session.get_node_or_null(^"HighwayScore") as HighwayScore
	if score:
		score.rules_for(p).contact(INF, clock)
	if p is SessionPlayer or not session.is_online():
		session.highway.reset(p)
