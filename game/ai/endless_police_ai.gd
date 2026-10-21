class_name EndlessPoliceAI
extends EndlessDriver
## A police unit's driver on the endless road (D194). Parked it waits. After a target it drives
## the road the players' way faster than the target, in the target's lane, by in the passing lane
## when something holds it up (the oncoming lane, one each way, only when that's clear for
## CLEAR_M); within PoliceTuning.CLOSE_M PoliceBrain takes over, as on a highway. Heading back
## it's just traffic, its siren off.

## The same modes as PoliceAI's.
const PARKED := 0
const PURSUE := 1
const RETURN := 2
## Passing in the oncoming lane: clear this far.
const CLEAR_M := 150.0
## Held up by something this far ahead going this much slower: it goes by.
const HELD_M := 45.0
const HELD_SLOWER := 3.0

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
var brain := PoliceBrain.new()


func _physics_process(delta: float) -> void:
	var v := racer.vehicle
	if v == null or not is_instance_valid(v):
		return
	v.siren = mode == PURSUE
	v.light_bar = mode == PURSUE
	match mode:
		PARKED:
			v.steer = 0.0
			v.throttle = 0.0
			v.brake = 0.0
			v.handbrake = 1.0
		RETURN:
			speed_factor = 1.0
			super(delta)
		PURSUE:
			_pursue(delta)


## Back on the road somewhere new: in the lane traffic keeps to.
func deployed() -> void:
	lane = lanes.keep_lane(EndlessLanes.UP)
	_passing = false


func _pursue(delta: float) -> void:
	var v := racer.vehicle
	var road := racer.track as RoadWindow
	if target == null or not is_instance_valid(target) or target.vehicle == null or road == null or road.samples.size() < 4:
		mode = RETURN
		return
	var tv := target.vehicle
	var c: Dictionary
	if tv.global_position.distance_to(v.global_position) > PoliceTuning.CLOSE_M:
		c = follow(_lane_to_drive(road), _chase_speed(road))
	else:
		c = brain.controls(v, tv, delta)
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## Down the road: as fast as the level allows over the limit, behind what's ahead in its lane.
func _chase_speed(road: RoadWindow) -> float:
	var t := PoliceTuning.at(level)
	var limit := road.limit_at(racer.distance)
	var want := clampf(absf(target.vehicle.speed()) + float(t.closing_mps), limit, limit * float(t.max_factor))
	var ahead := _ahead(road, racer.distance, lane)
	if not ahead.is_empty() and not _is_target(ahead.get("what")):
		var safe := GAP_M + GAP_S * maxf(racer.vehicle.speed(), 0.0)
		if float(ahead.gap) < safe:
			want = minf(want, maxf(float(ahead.speed) * float(ahead.gap) / safe, 0.0))
	return want


## The target's lane if it's the players' way's; by in the passing lane when held up, if that's
## clear (the oncoming one for CLEAR_M).
func _lane_to_drive(road: RoadWindow) -> int:
	var d := racer.distance
	var theirs := lanes.lane_at(road, target.distance, target.lateral)
	var into := theirs if EndlessLanes.dir_of(theirs) == EndlessLanes.UP else lanes.keep_lane(EndlessLanes.UP)
	var ahead := _ahead(road, d, into)
	var held: bool = not ahead.is_empty() and not _is_target(ahead.get("what")) and float(ahead.gap) < HELD_M \
		and float(ahead.speed) < absf(target.vehicle.speed()) - HELD_SLOWER
	if held:
		var by := lanes.pass_lane(EndlessLanes.UP) if into != lanes.pass_lane(EndlessLanes.UP) else lanes.keep_lane(EndlessLanes.UP)
		var traffic: Variant = racer.session.get(&"endless_traffic")
		var clear := true
		if traffic != null:
			clear = not traffic.oncoming_within(d, d + CLEAR_M) if lanes.passes_oncoming() else traffic.lane_clear(by, d - 15.0, d + 40.0)
		if clear:
			into = by
	lane = into
	return into


func _is_target(what: Variant) -> bool:
	return what is Racer and what == target
