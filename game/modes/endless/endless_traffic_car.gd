class_name EndlessTrafficCar
extends Node
## An endless traffic car near a player, as a physics car (D158): it drives its lane on its
## slot's schedule, catching up a little when held back, and yields to anything ahead in its lane
## (a player, another car). Knocked hard, rolled, or left well behind its slot, it leaves the slot:
## a knocked or rolled car stops with its hazards on; one left behind drives on at the lane's
## speed. Either way it goes once nobody's near (EndlessTraffic). Online, a car another game drives
## is a `remote` proxy of its states (D159).

## Catching up: m/s more per metre behind its slot, within these.
const CATCH_UP := 0.35
const CATCH_MIN := -3.0
const CATCH_MAX := 4.0
const LEAVE_SLOT_M := 25.0
## A knock this hard (N·s) or this long upset (s) and it's out.
const KNOCK_NS := 1800.0
const UPSET_S := 1.0
const LOOK_M := 14.0
const GAP_M := 5.0
const GAP_S := 1.4
## A proxy with no state this recent goes on along its slot.
const STALE_S := 1.0

var traffic: EndlessTraffic
var key: Vector2i
var vehicle: Vehicle
## Where it is: absolute distance along the road, and its speed (m/s, its own way).
var s := 0.0
var speed := 0.0
var left_slot := false
var wrecked := false
## Online: shown from its owner's states (`buffer`), not driven here.
var remote := false
var buffer := MotionBuffer.new()
var remote_flags := 0
var _index := -1
var _upset := 0.0
var _wheelbase := 2.7
var _max_steer := 0.55


func _ready() -> void:
	process_physics_priority = -50
	add_to_group(&"origin_shift")
	var p := vehicle.platform
	_wheelbase = float(p.geometry.wheelbase_m.ref)
	_max_steer = deg_to_rad(float(p.steering.max_road_angle_deg))
	vehicle.sim.set_assists({ "abs": true, "tcs": true, "stability": true, "auto_gearbox": true, "auto_clutch": true })


func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var road := traffic.world.road
	if road.samples.size() < 4:
		return
	var proj := road.project(vehicle.global_position, _index)
	_index = int(proj.index)
	s = float(proj.distance)
	speed = vehicle.speed()
	if remote:
		_follow(delta)
		return
	var dir := 1.0 if EndlessLanes.dir_of(key.x) == EndlessTraffic.UP else -1.0
	_upset = _upset + delta if vehicle.global_basis.y.y < 0.4 else 0.0
	if vehicle.car_impulse > KNOCK_NS or vehicle.wall_impulse > KNOCK_NS or _upset > UPSET_S:
		wrecked = true
		left_slot = true
	if key.x == EndlessTraffic.PARKED and not wrecked:
		# A speed trap's patrol: parked, watching.
		vehicle.steer = 0.0
		vehicle.throttle = 0.0
		vehicle.brake = 0.0
		vehicle.handbrake = 1.0
		return
	if wrecked:
		vehicle.indicators = 3
		vehicle.steer = 0.0
		vehicle.throttle = 0.0
		vehicle.brake = 0.6
		return
	var lane_v := traffic.lane_speed(key.x, s)
	var want := lane_v
	var target := traffic.slot_s(key)
	if not left_slot and not is_nan(target):
		var lag := (target - s) * dir
		if lag > LEAVE_SLOT_M:
			left_slot = true
		else:
			want = lane_v + clampf(lag * CATCH_UP, CATCH_MIN, CATCH_MAX)
	# Yield to anything ahead in its lane.
	var fwd := vehicle.global_basis.z
	var left := vehicle.global_basis.x
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var other := node as Vehicle
		if other == vehicle or other == null or not other.is_inside_tree():
			continue
		var rel := other.global_position - vehicle.global_position
		var along := rel.dot(fwd)
		if along <= 0.0 or along > 70.0 or absf(rel.dot(left)) > 2.3:
			continue
		var gap := along - GAP_M
		var safe := GAP_M + GAP_S * maxf(speed, 0.0)
		if gap < safe:
			var lead := maxf((other.remote_velocity if other.remote else other.linear_velocity).dot(fwd), 0.0)
			want = minf(want, lead * maxf(gap, 0.0) / safe)
	# A roadblock ahead in its lane: stop before it.
	var closed := traffic.closed_ahead(key.x, s, 80.0) if not traffic.closures.is_empty() else INF
	if is_finite(closed):
		want = minf(want, sqrt(maxf(closed - 6.0, 0.0) * 2.0 * 2.5))
	# A siren behind: over to the shoulder, slowly (D194).
	var yielding := traffic.siren_behind(vehicle)
	if yielding:
		want = minf(want, lane_v * EndlessTraffic.SIREN_PACE)
	# Steering: pure pursuit on its lane, its own way.
	var at := clampf(s + dir * LOOK_M, road.offset_m, road.end_m())
	var lat := traffic.lanes.shoulder(road, EndlessLanes.dir_of(key.x), at) if yielding else traffic.lanes.lateral(road, key.x, at)
	var aim := road.transform_at(at, lat).origin
	var local := vehicle.global_basis.inverse() * (aim - vehicle.global_position)
	var alpha := atan2(local.x, maxf(local.z, 0.5))
	vehicle.steer = clampf(-atan(2.0 * _wheelbase * sin(alpha) / LOOK_M) / _max_steer, -1.0, 1.0)
	var err := want - speed
	vehicle.throttle = clampf(0.2 + err * 0.3, 0.0, 1.0) if err > 0.0 else 0.0
	vehicle.brake = clampf(-err * 0.25, 0.0, 1.0) if err < -0.8 else 0.0
	vehicle.handbrake = 0.0
	vehicle.indicators = 0


## The scene's origin moved (FloatingOrigin): the states waiting move with it (the car moves itself).
func origin_shifted(delta: Vector3) -> void:
	buffer.shift(delta)


## Its driver's word for the network: wrecked, still on its slot.
func flags2() -> int:
	return (CarState.FLAG2_WRECKED if wrecked else 0) | (0 if left_slot else CarState.FLAG2_LANE_OK)


## A proxy: where its owner's states put it now; with none lately, its slot's spot.
func _follow(delta: float) -> void:
	var now := traffic.session.net.now() if traffic.session.net else 0.0
	var p := buffer.pose(now, delta) if not buffer.is_empty() else {}
	if not p.is_empty() and now - (p.state as CarState).time < STALE_S:
		var st: CarState = p.state
		vehicle.remote_state = st
		vehicle.move_remote(p.xform, p.velocity, p.angular, st.flags & CarState.FLAG_TELEPORT != 0)
		CarState.show_on(vehicle, st.flags2)
		wrecked = st.flags2 & CarState.FLAG2_WRECKED != 0
		left_slot = left_slot or st.flags2 & CarState.FLAG2_LANE_OK == 0
		return
	var at := traffic.slot_s(key)
	if not left_slot and not is_nan(at):
		var xf := traffic.pose(key.x, at)
		vehicle.move_remote(xf, xf.basis.z * traffic.lane_speed(key.x, at), Vector3.ZERO, false)


## This game drives it from now on (it was a proxy): as its owner's last word left it.
func take_over() -> void:
	wrecked = remote_flags & CarState.FLAG2_WRECKED != 0
	left_slot = left_slot or (remote_flags != 0 and remote_flags & CarState.FLAG2_LANE_OK == 0)
	_upset = 0.0
