class_name EndlessPoliceRoad
extends PoliceRoad
## The police's road on the endless road (D194): its window (RoadWindow) and lanes, the limits
## (EndlessLimits), its traffic (EndlessTraffic: near misses, patrols, roadblocks, moving over for
## sirens) and its speed traps (EndlessTraps: a camera's snap raises heat; a parked patrol watches
## and joins the chase). Each game runs the police for its own players, so on a split screen each
## has their own heat. They chase the players' way. Busted, you're pulled over: held a few seconds
## on the shoulder, then on your way.

## The most units out at once, per game.
const CHASE_UNITS := 6
## Pulled over this long.
const PULLED_OVER_S := 4.0

var traffic: EndlessTraffic
var road_lanes: EndlessLanes
## Busts per racer this drive.
var busts := {}


static func make(s: TrackSession) -> EndlessPoliceRoad:
	var r := EndlessPoliceRoad.new()
	r.session = s
	r.traffic = s.endless_traffic
	r.road_lanes = s.endless_lanes
	return r


func _road() -> RoadWindow:
	return session.endless_world.road


func watched_players() -> Array:
	var out: Array = []
	out.append_array(session.players)
	return out


func chase_units() -> int:
	return CHASE_UNITS


func limit_mps(p: Racer) -> float:
	return _road().limit_at(p.distance)


func lanes() -> int:
	return road_lanes.per_dir


func project(pos: Vector3) -> Dictionary:
	return _road().project(pos)


func straight_clear(d: float, way_dir: int, length: float) -> bool:
	var road := _road()
	var s := 0.0
	while s <= length:
		var at := d + way_dir * s
		var i := road.index_of(at)
		if i < 0 or road.lifted[i] or absf(road.curvature[i]) > 1.0 / 600.0:
			return false
		s += 10.0
	return true


## Lane `lane` of `way` (0: the one by the centre), facing that way.
func lane_xform(way_dir: int, lane: int, d: float) -> Transform3D:
	var road := _road()
	var dir := EndlessLanes.UP if way_dir > 0 else EndlessLanes.DOWN
	var xf := road.transform_at(d, road_lanes.lateral(road, EndlessLanes.id(clampi(lane, 0, road_lanes.per_dir - 1), dir), d))
	if dir == EndlessLanes.DOWN:
		xf.basis = xf.basis.rotated(xf.basis.y, PI)
	return xf


func shoulder_xform(way_dir: int, d: float) -> Transform3D:
	var road := _road()
	var dir := EndlessLanes.UP if way_dir > 0 else EndlessLanes.DOWN
	var xf := road.transform_at(d, road_lanes.shoulder(road, dir, d))
	if dir == EndlessLanes.DOWN:
		xf.basis = xf.basis.rotated(xf.basis.y, PI)
	return xf


## Across the road where the lane is (each unit square across it).
func across_xform(way_dir: int, lane: int, d: float, i: int) -> Transform3D:
	var at := lane_xform(way_dir, lane, d)
	at.basis = Basis(Vector3.UP, PI / 2.0 * (1 if i == 0 else -1)) * at.basis
	return at


## The traffic's physics cars round `v`, as near-miss rows.
func near_rows(v: Vehicle, radius: float) -> Array:
	var out := []
	if traffic == null:
		return out
	var env := v.fitted.envelope if v.fitted else AABB(Vector3(-0.9, 0, -2.2), Vector3(1.8, 1.4, 4.4))
	var me := v.global_transform * env.get_center()
	var fwd := Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized()
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	var half := Vector2(env.size.z / 2.0, env.size.x / 2.0)
	for key: Vector2i in traffic.cars:
		var o := (traffic.cars[key] as EndlessTrafficCar).vehicle
		if o == null or not is_instance_valid(o) or o == v:
			continue
		var oe := o.fitted.envelope if o.fitted else env
		var oc := o.global_transform * oe.get_center()
		var d := oc - me
		if Vector2(d.x, d.z).length() > radius:
			continue
		var of := Vector3(o.global_basis.z.x, 0.0, o.global_basis.z.z).normalized()
		var oh := Vector2(oe.size.z / 2.0, oe.size.x / 2.0)
		out.append([EndlessTraffic.slot_of(key), NossTraffic.box_gap(me, fwd, half, oc, of, oh), d.dot(fwd), d.dot(left),
			v.speed() - o.speed() * of.dot(fwd), half.x + oh.x])
	return out


func spikes_allowed() -> bool:
	return true


## Every lane of that way, from the centre line out, half the edge lane left open.
func strip_span(way_dir: int, d: float) -> Vector2:
	var road := _road()
	var dir := EndlessLanes.UP if way_dir > 0 else EndlessLanes.DOWN
	var side := road_lanes.side_sign(dir)
	var a := 0.0
	var b := side * road_lanes.lane_w(road, d) * (road_lanes.per_dir - 0.5)
	return Vector2(minf(a, b), maxf(a, b))


## Two lanes: the player's lane; four: both lanes of their way, the shoulder left.
func close_lanes(p: Racer, way_dir: int, d: float, length: float) -> Array:
	if traffic == null:
		return []
	var dir := EndlessLanes.UP if way_dir > 0 else EndlessLanes.DOWN
	var ids := [EndlessLanes.id(0, dir)] if road_lanes.per_dir == 1 else [EndlessLanes.id(0, dir), EndlessLanes.id(1, dir)]
	return [traffic.close(ids, d, d + way_dir * length)]


func open_lanes(closures: Array) -> void:
	if traffic:
		for id: int in closures:
			traffic.open(id)


func block_lanes(_way: int) -> Array:
	return [0] if road_lanes.per_dir == 1 else [0, 1]


func move_over(units: Array) -> void:
	if traffic:
		traffic.sirens = units.map(func(u: PoliceRacer) -> Vehicle: return u.vehicle)


func patrols(pos: Vector3, radius: float) -> Array:
	return traffic.patrols_near(pos, radius) if traffic else []


func convert_patrol(patrol: Dictionary) -> void:
	traffic.retire(patrol.key)


func make_driver(_u: PoliceRacer) -> Node:
	var ai := EndlessPoliceAI.new()
	ai.lanes = road_lanes
	return ai


func bust_text(p: Racer) -> String:
	return "Busted (%d). Pulled over" % int(busts.get(p, 0))


## Pulled over: on the shoulder where they are, held a moment, then on their way.
func after_bust(p: Racer, _clock: float) -> void:
	busts[p] = int(busts.get(p, 0)) + 1
	if p.vehicle:
		var at := shoulder_xform(1, p.distance)
		p.vehicle.reset_to(at)
		p.vehicle.repair()
	p.held = true
	session.get_tree().create_timer(PULLED_OVER_S, false, true).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.held = false
			p.notify("Drive on", 2.0))
