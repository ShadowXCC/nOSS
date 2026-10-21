class_name PoliceBrain
extends RefCounted
## A police unit close to its target (D192): what it does with the target within
## PoliceTuning.CLOSE_M, worked out from the two cars alone so it can be tested on its own. Both
## PoliceAI (highways) and EndlessPoliceAI hand over to it up close.
##
## It aims at the target's rear quarter on its `side`, a little faster than the target, and past
## it, slows to box the target in.

## Which side it comes at the target from (+1 left, -1 right).
var side := 1.0
## The heat level it drives to (PoliceTuning).
var level := 1


## This tick's controls for unit `v` on target `tv`: {steer, throttle, brake, handbrake}.
func controls(v: Vehicle, tv: Vehicle) -> Dictionary:
	var t := PoliceTuning.at(level)
	var to := tv.global_position - v.global_position
	var fwd := Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized()
	var ahead := to.dot(fwd)
	var tf := Vector3(tv.global_basis.z.x, 0.0, tv.global_basis.z.z).normalized()
	var right := Vector3(-tf.z, 0.0, tf.x)
	var aim := tv.global_position - tf * PoliceTuning.AIM_BACK_M - right * side * PoliceTuning.AIM_SIDE_M + tv.linear_velocity * float(t.lead_s)
	var local := v.global_transform.affine_inverse() * aim
	var want := absf(tv.speed()) + (PoliceTuning.RAM_MPS if ahead > 0.0 else -PoliceTuning.RAM_MPS * 2.0)
	var speed := v.speed()
	return {
		"steer": clampf(atan2(local.x, maxf(local.z, 0.5)) * float(t.steer_gain), -1.0, 1.0),
		"throttle": clampf((want - speed) * 0.3, 0.0, 1.0),
		"brake": clampf((speed - want) * 0.25, 0.0, 1.0),
		"handbrake": 0.0,
	}
