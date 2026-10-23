class_name EndlessDriver
extends Node
## Drives a car down the endless road (D157): players' autodrive and lane assists, bots, the long
## drive check. It keeps to the lane traffic keeps to (EndlessLanes, D190) by pure pursuit, at a
## cruising speed that slows for bends and crests ahead (braking in time, less on a wet or snowy
## road), behind anything slower in its lane. It passes slower cars (traffic) and comes back once
## by: one lane each way, in the oncoming lane, with a clear straight and nothing coming; two each
## way, in the passing lane once that's clear. Stuck or on its side or roof for a while, it resets.
## Police after a target (D201) and dev --flat-out take bends and brake harder (`lateral`,
## `braking`).

## Sideways and braking acceleration it plans with, on a dry road (m/s^2).
const LATERAL := 2.8
const BRAKING := 2.6
## Look this far ahead for the steering: a base and a time at speed (m, s).
const LOOK_BASE_M := 5.0
const LOOK_TIME_S := 0.85
const LOOK_MIN_M := 9.0
const LOOK_MAX_M := 42.0
## Its cruising speed is the road's traffic speed times this, at most CRUISE_MAX.
const CRUISE_OVER := 1.18
const CRUISE_MAX := 125.0 / 3.6
## Following: a gap of this plus this many seconds.
const GAP_M := 6.0
const GAP_S := 1.5
## Passing: held up this long behind something this much slower, with a clear stretch this long.
const PASS_AFTER_S := 2.0
const PASS_SLOWER := 4.0
const PASS_CLEAR_M := 420.0
const STUCK_S := 6.0
const UPSET_S := 3.0
## Dev --flat-out: a player's autodrive at this share of its tyres' grip, with no cruising limit.
const FLAT_OUT_GRIP := 0.85

var racer: Racer
var as_guide := false
## Off: never passes (a guide; tests).
var overtakes := true
## Of its usual cruising speed (dev: --speed-factor).
var speed_factor := 1.0
## Sideways and braking acceleration it plans with on a dry road (m/s^2), and how hard it brakes
## for each m/s over what it wants.
var lateral := LATERAL
var braking := BRAKING
var brake_gain := 0.22
## As fast as it can (flat_out): no cruising limit.
var flat := false
## Resets so far (checks).
var resets := 0
## The road's lanes, and the one it's in (EndlessLanes ids: the keep lane, or the passing one).
var lanes: EndlessLanes
var lane := 0
var _held := 0.0
var _passing := false
var _passing_what: Variant # the Racer or the traffic slot being passed
var _stuck := 0.0
var _upset := 0.0


func _ready() -> void:
	process_physics_priority = -50
	if lanes == null:
		var l: Variant = racer.session.get(&"endless_lanes") if racer.session else null
		lanes = l if l is EndlessLanes else EndlessLanes.new()
	lane = lanes.keep_lane(EndlessLanes.UP)
	if racer is SessionPlayer and Game.dev.has("speed-factor"):
		speed_factor = clampf(float(Game.dev["speed-factor"]), 0.5, 2.0)
	if as_guide or racer.vehicle == null:
		return
	var allowed: Array = racer.vehicle.platform.get("assists_allowed", [])
	var assists := {}
	for a in ["abs", "tcs", "stability", "auto_gearbox"]:
		assists[a] = a in allowed
	assists.auto_clutch = true
	racer.vehicle.sim.set_assists(assists)
	if racer is SessionPlayer and Game.dev.has("flat-out"):
		flat_out()


## As fast as it can (dev --flat-out, checks: a player driving flat out): no cruising limit, and
## bends and braking at FLAT_OUT_GRIP of its tyres' grip.
func flat_out() -> void:
	flat = true
	lateral = FLAT_OUT_GRIP * float(racer.vehicle.platform.get("tires", {}).get("mu_peak", 1.2)) * 9.81
	braking = lateral


func _physics_process(delta: float) -> void:
	if as_guide:
		return
	var c := controls(delta)
	if c.is_empty():
		return
	if _trouble(c, delta):
		racer.reset_car()
		resets += 1
		return
	var v := racer.vehicle
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## This tick's controls: {steer, throttle, brake, handbrake}, or {} without a car or road.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	var road := racer.track as RoadWindow
	if v == null or not is_instance_valid(v) or road == null or road.samples.size() < 4:
		return {}
	if racer.held or racer.waiting:
		return { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 1.0 }
	var speed := maxf(v.speed(), 0.0)
	var d := racer.distance
	var want := INF if flat else _cruise(road, d) * speed_factor
	if racer.pace_limit > 0.0:
		want = minf(want, racer.pace_limit)
	# Passing: back once well past what it passed; in the oncoming lane, back at once if anything
	# comes the other way.
	if _passing:
		var oncoming := _ahead(road, d, lane) if lanes.passes_oncoming() else {}
		var passed_s := _where(_passing_what)
		if (not oncoming.is_empty() and float(oncoming.speed) < 0.0 and float(oncoming.gap) < 250.0) \
				or is_nan(passed_s) or d > passed_s + 15.0:
			_passing = false
			_held = 0.0
			lane = lanes.keep_lane(EndlessLanes.UP)
	# Anything ahead in its lane.
	var ahead := _ahead(road, d, lane)
	if not ahead.is_empty():
		var gap: float = ahead.gap
		var lead_v: float = ahead.speed
		var safe := GAP_M + GAP_S * speed
		if gap < safe:
			want = minf(want, maxf(lead_v * gap / safe, 0.0))
		_passing_rules(delta, road, d, speed, want, ahead)
	var c := follow(lane, want)
	if Game.dev.has("endless-debug") and Engine.get_physics_frames() % 60 == 0:
		print("driver: want %.1f speed %.1f steer %.2f ahead %s" % [want, speed, c.steer, ahead])
	return c


## Driving lane `in_lane` (`offset` m to its left) at up to `want` m/s, slowing in time for the
## bends and crests ahead (by the grip there is): {steer, throttle, brake, handbrake}.
func follow(in_lane: int, want: float, offset := 0.0) -> Dictionary:
	var v := racer.vehicle
	var road := racer.track as RoadWindow
	var speed := maxf(v.speed(), 0.0)
	var d := racer.distance
	# Steering: pure pursuit on the lane's centre.
	var look := clampf(LOOK_BASE_M + LOOK_TIME_S * speed, LOOK_MIN_M, LOOK_MAX_M)
	var aim := minf(d + look, road.end_m())
	var target := road.transform_at(aim, lanes.lateral(road, in_lane, aim) + offset).origin
	var local := v.global_transform.basis.inverse() * (target - v.global_position)
	var alpha := atan2(local.x, maxf(local.z, 0.5))
	var p := v.platform
	var wheelbase := float(p.geometry.wheelbase_m.ref)
	var max_steer := deg_to_rad(float(p.steering.max_road_angle_deg))
	var steer := clampf(-atan(2.0 * wheelbase * sin(alpha) / look) / max_steer, -1.0, 1.0) # the input: + = right
	# Speed: slowing in time for what's ahead.
	var grip := _grip(v)
	var reach := minf(speed * speed / (2.0 * braking * grip) + 40.0, road.end_m() - d)
	var s := 4.0
	while s < reach:
		var k := absf(road.curvature[road.index_at(d + s)])
		if k > 1e-4:
			var bend := sqrt(lateral * grip / k)
			want = minf(want, sqrt(bend * bend + 2.0 * braking * grip * s))
		s += 4.0
	var here := absf(road.curvature[road.index_at(d)])
	if here > 1e-4:
		want = minf(want, sqrt(lateral * grip / here))
	var err := want - speed
	var throttle := clampf(0.2 + err * 0.3, 0.0, 1.0) if err > 0.0 else 0.0
	var brake := clampf(-err * brake_gain, 0.0, 1.0) if err < -0.8 else 0.0
	return { "steer": steer, "throttle": throttle, "brake": brake, "handbrake": 0.0 }


## The cruising speed here: the road's traffic speed (bends already in it) a little over.
func _cruise(road: RoadWindow, d: float) -> float:
	var i := road.index_at(d)
	var best := 0.0
	for j in range(i, mini(i + 150, road.speed_up.size()), 10):
		best = maxf(best, road.speed_up[j])
	return minf(best * CRUISE_OVER, CRUISE_MAX)


## Grip on the road under it now, of dry (wet and snow lower it, D153).
func _grip(v: Vehicle) -> float:
	var c := v.road_conditions()
	return VehicleSim.surface_grip(VehicleSim.SURFACE_ASPHALT, c.x, c.y)


## The nearest thing ahead in lane `in_lane` within 160 m: {gap (m, nose to tail), speed}, or {}.
func _ahead(road: RoadWindow, d: float, in_lane: int) -> Dictionary:
	var best := {}
	var best_gap := 160.0
	var lane_lat := lanes.lateral(road, in_lane, d)
	var lane_w := lanes.lane_w(road, d)
	for r: Racer in racer.session.racers:
		if r == racer or r.vehicle == null or r.waiting:
			continue
		var gap := r.distance - d - 5.0
		if gap > -2.0 and gap < best_gap and absf(r.lateral - lane_lat) < lane_w * 0.7:
			best_gap = gap
			best = { "gap": maxf(gap, 0.0), "speed": maxf(r.speed, 0.0), "what": r }
	var traffic: Variant = racer.session.get(&"endless_traffic")
	if traffic != null and traffic.has_method(&"ahead"):
		var t: Dictionary = traffic.ahead(d, in_lane, best_gap)
		if not t.is_empty() and float(t.gap) < best_gap:
			best = t
	return best


## Where what it's passing is now (absolute m), or NAN if it's gone.
func _where(what: Variant) -> float:
	if what is Racer:
		return (what as Racer).distance if is_instance_valid(what) else NAN
	var traffic: Variant = racer.session.get(&"endless_traffic")
	if what is Vector2i and traffic != null:
		return traffic.position_of(what)
	return NAN


## Held up behind something slower: over into the passing lane when it's clear, back once by.
func _passing_rules(delta: float, road: RoadWindow, d: float, speed: float, want: float, ahead: Dictionary) -> void:
	if not overtakes or as_guide:
		return
	if lane == lanes.keep_lane(EndlessLanes.UP):
		var slower := float(ahead.speed) < _cruise(road, d) - PASS_SLOWER
		_held = _held + delta if slower and float(ahead.gap) < 60.0 else 0.0
		if _held > PASS_AFTER_S and _clear_to_pass(road, d, speed):
			lane = lanes.pass_lane(EndlessLanes.UP)
			_passing = true
			_passing_what = ahead.get("what")
			_held = 0.0


## In the oncoming lane: a straight stretch long enough, and nothing coming the other way through
## it. In a passing lane of its own: nothing in it alongside or just ahead.
func _clear_to_pass(road: RoadWindow, d: float, speed: float) -> bool:
	if not lanes.passes_oncoming():
		var into := lanes.pass_lane(EndlessLanes.UP)
		var lat := lanes.lateral(road, into, d)
		for r: Racer in racer.session.racers:
			if r != racer and r.vehicle and not r.waiting and absf(r.distance - d) < 30.0 and absf(r.lateral - lat) < lanes.lane_w(road, d) * 0.7:
				return false
		var traffic: Variant = racer.session.get(&"endless_traffic")
		return traffic == null or not traffic.has_method(&"lane_clear") or traffic.lane_clear(into, d - 25.0, d + 60.0)
	if d + PASS_CLEAR_M > road.end_m():
		return false
	var s := 0.0
	while s < PASS_CLEAR_M:
		if absf(road.curvature[road.index_at(d + s)]) > 1.0 / 600.0:
			return false
		s += 10.0
	var traffic: Variant = racer.session.get(&"endless_traffic")
	if traffic != null and traffic.has_method(&"oncoming_within"):
		return not traffic.oncoming_within(d, d + PASS_CLEAR_M + speed * 8.0)
	return true


func _trouble(c: Dictionary, delta: float) -> bool:
	var v := racer.vehicle
	if racer.held or racer.waiting:
		_stuck = 0.0
		_upset = 0.0
		return false
	_upset = _upset + delta if v.global_basis.y.y < 0.3 else 0.0
	_stuck = _stuck + delta if absf(v.speed()) < 1.0 and float(c.throttle) > 0.3 else 0.0
	if _upset > UPSET_S or _stuck > STUCK_S:
		_upset = 0.0
		_stuck = 0.0
		return true
	return false
