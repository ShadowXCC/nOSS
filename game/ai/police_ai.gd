class_name PoliceAI
extends HighwayDriver
## A police unit's driver (D115, AI-04). Parked at a speed trap it waits, watching (PoliceControl
## decides what it sees). After a target it drives the lanes (HighwayDriver) faster than the
## target, moving to the target's lane; within CLOSE_M it drives at the target's rear quarter to
## knock it round (a ram), and past it, it brakes to box the target in. Heading back, it drives the
## lanes at their limit with the siren off.

enum Mode { PARKED, PURSUE, RETURN }

const CLOSE_M := 35.0
## How much faster than the target it goes while closing, m/s, and at most this times the limit.
const CLOSING_MPS := 15.0
const MAX_FACTOR := 2.2
## Near the target: closing speed (m/s), and where it aims: this far behind the target's centre,
## this far to one side (its rear quarter).
const RAM_MPS := 4.0
const AIM_BACK_M := 2.0
const AIM_SIDE_M := 0.8
## Steering: how far ahead it looks (s) and how hard it turns for an angle.
const LEAD_S := 0.3
const STEER_GAIN := 2.0

var mode := Mode.PARKED
var target: Racer
## Which side it comes at the target from (+1 left, -1 right).
var side := 1.0


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


func _pursue(delta: float) -> void:
	var v := racer.vehicle
	if target == null or not is_instance_valid(target) or target.vehicle == null:
		mode = Mode.RETURN
		return
	var tv := target.vehicle
	var to := tv.global_position - v.global_position
	var fwd := Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized()
	var ahead := to.dot(fwd)
	var tm := racer.session.traffic
	if to.length() > CLOSE_M or tm == null:
		# Down the lanes: the target's lane, faster than it.
		if tm:
			var at := tm.sim.locate(tv.global_position + Vector3.UP * 0.5)
			var their := int(at.get("lane", -1))
			if their >= 0 and lane >= 0 and their != lane and _same_way(their):
				lane = their
		var limit := tm.sim.lane_limit(maxi(lane, 0), maxf(_s, 0.0)) if tm and lane >= 0 else 30.0
		speed_factor = clampf((absf(tv.speed()) + CLOSING_MPS) / maxf(limit, 1.0), 1.0, MAX_FACTOR)
		super._physics_process(delta)
		return
	# Close: at the rear quarter, a little faster than the target; past it, slow (box it in).
	var tf := Vector3(tv.global_basis.z.x, 0.0, tv.global_basis.z.z).normalized()
	var right := Vector3(-tf.z, 0.0, tf.x)
	var aim := tv.global_position - tf * AIM_BACK_M - right * side * AIM_SIDE_M + tv.linear_velocity * LEAD_S
	var local := v.global_transform.affine_inverse() * aim
	v.steer = clampf(atan2(local.x, maxf(local.z, 0.5)) * STEER_GAIN, -1.0, 1.0)
	var want := absf(tv.speed()) + (RAM_MPS if ahead > 0.0 else -RAM_MPS * 2.0)
	var speed := v.speed()
	v.throttle = clampf((want - speed) * 0.3, 0.0, 1.0)
	v.brake = clampf((speed - want) * 0.25, 0.0, 1.0)
	v.handbrake = 0.0


## True if lane `l` goes the way this car is going (not the other carriageway).
func _same_way(l: int) -> bool:
	var tm := racer.session.traffic
	return int(tm.sim.lane_info(l).get("dir", 0)) == int(tm.sim.lane_info(lane).get("dir", 0))
