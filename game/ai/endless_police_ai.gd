class_name EndlessPoliceAI
extends EndlessDriver
## A police unit's driver on the endless road (D194, D201). Parked it waits; ready, it waits with
## its light bar on (ahead of a player, or across a roadblock). After a target it drives the road
## the players' way faster than the target, as hard into bends as its heat says, in the target's
## lane, by in the passing lane when something holds it up (the oncoming lane, one each way, only
## when that's clear far enough for its speed); within PoliceTuning.CLOSE_M PoliceBrain takes
## over, as on a highway. One that waited ahead blocks until the target is past it, then takes
## the level's lead role. Heading back it's just traffic, its siren off.

## The same modes as PoliceAI's.
const PARKED := 0
const PURSUE := 1
const RETURN := 2
const READY := 3
## Passing in the oncoming lane: clear this far, or this many seconds at its speed if further.
const CLEAR_M := 150.0
const CLEAR_S := 4.0
## Held up by something this far ahead (and two seconds of the speed it's closing at) going this
## much slower than the target: it goes by.
const HELD_M := 45.0
const HELD_SLOWER := 3.0
## Behind what's ahead in its lane: GAP_M plus this many seconds of the lead's speed.
const CHASE_GAP_S := 0.8
## How hard it brakes for each m/s over what it wants, after a target.
const CHASE_BRAKE_GAIN := 0.5

var mode := PARKED
var target: Racer
## Which side it comes at the target from (+1 left, -1 right), the heat level it drives to and its
## role up close (PoliceTuning).
var side := 1.0:
	set(v):
		side = v
		brain.side = v
var level := 1:
	set(v):
		level = v
		brain.level = v
var role := "ram":
	set(v):
		role = v
		brain.role = v
## It waited ahead of its target (PoliceControl), and the target has gone past it up close.
var ahead := false
var passed := false
var brain := PoliceBrain.new()


func _physics_process(delta: float) -> void:
	var v := racer.vehicle
	if v == null or not is_instance_valid(v):
		return
	v.siren = mode == PURSUE
	v.light_bar = mode == PURSUE or mode == READY
	match mode:
		PARKED, READY:
			v.steer = 0.0
			v.throttle = 0.0
			v.brake = 0.0
			v.handbrake = 1.0
		RETURN:
			lateral = LATERAL
			braking = BRAKING
			brake_gain = 0.22
			speed_factor = 1.0
			super(delta)
		PURSUE:
			_pursue(delta)


## Back on the road somewhere new: in the lane traffic keeps to.
func deployed() -> void:
	lane = lanes.keep_lane(EndlessLanes.UP)
	_passing = false
	passed = false


func _pursue(delta: float) -> void:
	var v := racer.vehicle
	var road := racer.track as RoadWindow
	if target == null or not is_instance_valid(target) or target.vehicle == null or road == null or road.samples.size() < 4:
		mode = RETURN
		return
	var tv := target.vehicle
	var dist := tv.global_position.distance_to(v.global_position)
	var c: Dictionary
	if dist > PoliceTuning.CLOSE_M:
		lateral = PoliceTuning.grip_mps2(level, v)
		braking = lateral
		brake_gain = CHASE_BRAKE_GAIN
		c = follow(_lane_to_drive(road), _chase_speed(road, dist))
		if _trouble(c, delta):
			racer.reset_car()
			resets += 1
			return
	else:
		if ahead:
			var r := PoliceBrain.ahead_role(PoliceBrain.state_of(v), PoliceBrain.state_of(tv), level, passed, side)
			role = r[0]
			passed = r[1]
			side = r[2]
		c = brain.controls(v, tv, delta)
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## Down the road `dist` m from the target: as fast as the level allows (PoliceBrain.chase_speed),
## slowing in time for what's ahead in its lane.
func _chase_speed(road: RoadWindow, dist: float) -> float:
	var b := braking * _grip(racer.vehicle)
	var waiting_for := ahead and not passed and (racer as PoliceRacer).road.past(target, racer.distance) < 0.0
	var want := PoliceBrain.chase_speed(level, absf(target.vehicle.speed()), dist, road.limit_at(racer.distance), b, waiting_for)
	var next := _ahead(road, racer.distance, lane)
	if not next.is_empty() and not _is_target(next.get("what")):
		var lead := maxf(float(next.speed), 0.0)
		want = minf(want, sqrt(lead * lead + 2.0 * b * maxf(float(next.gap) - GAP_M - CHASE_GAP_S * lead, 0.0)))
	return want


## The target's lane if it's the players' way's; by in the passing lane when held up, if that's
## clear (the oncoming one far enough for its speed).
func _lane_to_drive(road: RoadWindow) -> int:
	var d := racer.distance
	var speed := maxf(racer.vehicle.speed(), 0.0)
	var theirs := lanes.lane_at(road, target.distance, target.lateral)
	var into := theirs if EndlessLanes.dir_of(theirs) == EndlessLanes.UP else lanes.keep_lane(EndlessLanes.UP)
	var next := _ahead(road, d, into)
	var held: bool = not next.is_empty() and not _is_target(next.get("what")) \
		and float(next.gap) < HELD_M + maxf(speed - float(next.speed), 0.0) * 2.0 \
		and float(next.speed) < absf(target.vehicle.speed()) - HELD_SLOWER
	if held:
		var by := lanes.pass_lane(EndlessLanes.UP) if into != lanes.pass_lane(EndlessLanes.UP) else lanes.keep_lane(EndlessLanes.UP)
		var traffic: Variant = racer.session.get(&"endless_traffic")
		var clear := true
		if traffic != null:
			clear = not traffic.oncoming_within(d, d + maxf(CLEAR_M, speed * CLEAR_S)) if lanes.passes_oncoming() else traffic.lane_clear(by, d - 15.0, d + 40.0)
		if clear:
			into = by
	lane = into
	return into


func _is_target(what: Variant) -> bool:
	return what is Racer and what == target
