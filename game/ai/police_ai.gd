class_name PoliceAI
extends HighwayDriver
## A police unit's driver on a highway (D115, AI-04, D192). Parked at a speed trap it waits,
## watching (PoliceControl decides what it sees). After a target it drives the lanes
## (HighwayDriver) faster than the target, moving to the target's lane; within
## PoliceTuning.CLOSE_M PoliceBrain takes over. Heading back, it drives the lanes at their limit with
## the siren off.

enum Mode { PARKED, PURSUE, RETURN }

var mode := Mode.PARKED
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
	v.siren = mode == Mode.PURSUE
	v.light_bar = mode == Mode.PURSUE
	match mode:
		Mode.PARKED:
			v.steer = 0.0
			v.throttle = 0.0
			v.brake = 0.0
			v.handbrake = 1.0
		Mode.RETURN:
			speed_factor = 1.0
			super(delta)
		Mode.PURSUE:
			_pursue(delta)


## Back on the road somewhere new: its lane is found again.
func deployed() -> void:
	lane = -1


func _pursue(delta: float) -> void:
	var v := racer.vehicle
	if target == null or not is_instance_valid(target) or target.vehicle == null:
		mode = Mode.RETURN
		return
	var tv := target.vehicle
	var to := tv.global_position - v.global_position
	var tm := racer.session.traffic
	if to.length() > PoliceTuning.CLOSE_M or tm == null:
		# Down the lanes: the target's lane, faster than it.
		if tm:
			var at := tm.sim.locate(tv.global_position + Vector3.UP * 0.5)
			var their := int(at.get("lane", -1))
			if their >= 0 and lane >= 0 and their != lane and _same_way(their):
				lane = their
		var t := PoliceTuning.at(level)
		var limit := tm.sim.lane_limit(maxi(lane, 0), maxf(_s, 0.0)) if tm and lane >= 0 else 30.0
		speed_factor = clampf((absf(tv.speed()) + float(t.closing_mps)) / maxf(limit, 1.0), 1.0, float(t.max_factor))
		super._physics_process(delta)
		return
	var c := brain.controls(v, tv, delta)
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## True if lane `l` goes the way this car is going (not the other carriageway).
func _same_way(l: int) -> bool:
	var tm := racer.session.traffic
	return int(tm.sim.lane_info(l).get("dir", 0)) == int(tm.sim.lane_info(lane).get("dir", 0))
