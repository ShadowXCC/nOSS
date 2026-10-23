class_name PoliceAI
extends HighwayDriver
## A police unit's driver on a highway (D115, AI-04, D192, D201). Parked at a speed trap it waits,
## watching (PoliceControl decides what it sees); ready, it waits with its light bar on (ahead of a
## player, or across a roadblock). After a target it drives the lanes (HighwayDriver) at its own
## speed: faster than the target, as hard into bends as its heat says, over toward the target's
## lane a lane at a time, never keeping a following gap behind the target; within
## PoliceTuning.CLOSE_M PoliceBrain takes over. One that waited ahead blocks until the target is
## past it, then takes the level's lead role. Heading back, it drives the lanes at their limit
## with the siren off.

enum Mode { PARKED, PURSUE, RETURN, READY }

## Over a lane toward the target's within this far of it (further off it gets by traffic as it
## likes), at most this often (s).
const TOWARD_WITHIN_M := 150.0
const TOWARD_AGAIN_S := 2.0

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
## It waited ahead of its target (PoliceControl), and the target has gone past it up close.
var ahead := false
var passed := false
var brain := PoliceBrain.new()


func _ready() -> void:
	super()
	overtake_after_s = 0.5
	change_again_s = 2.0


func _physics_process(delta: float) -> void:
	var v := racer.vehicle
	if v == null or not is_instance_valid(v):
		return
	v.siren = mode == Mode.PURSUE
	v.light_bar = mode == Mode.PURSUE or mode == Mode.READY
	match mode:
		Mode.PARKED, Mode.READY:
			v.steer = 0.0
			v.throttle = 0.0
			v.brake = 0.0
			v.handbrake = 1.0
		Mode.RETURN:
			lateral = 0.0
			want_speed = INF
			keep_out = true
			speed_factor = 1.0
			super(delta)
		Mode.PURSUE:
			_pursue(delta)


## Back on the road somewhere new: its lane is found again.
func deployed() -> void:
	lane = -1
	passed = false


func _pursue(delta: float) -> void:
	var v := racer.vehicle
	if target == null or not is_instance_valid(target) or target.vehicle == null:
		mode = Mode.RETURN
		return
	var tv := target.vehicle
	var dist := tv.global_position.distance_to(v.global_position)
	var tm := racer.session.traffic
	if dist > PoliceTuning.CLOSE_M or tm == null:
		# Down the lanes at its own speed, over toward the target's lane.
		if tm:
			if dist < TOWARD_WITHIN_M:
				_toward_target_lane(tm, tv)
			keep_out = false
			lateral = PoliceTuning.grip_mps2(level, v)
			var limit := tm.sim.lane_limit(lane, maxf(_s, 0.0)) if lane >= 0 else 30.0
			var waiting_for := ahead and not passed and (racer as PoliceRacer).road.past(target, racer.distance) < 0.0
			want_speed = PoliceBrain.chase_speed(level, absf(tv.speed()), dist, limit, lateral * _grip(v), waiting_for)
		super._physics_process(delta)
		return
	if ahead:
		var r := PoliceBrain.ahead_role(PoliceBrain.state_of(v), PoliceBrain.state_of(tv), level, passed, side)
		role = r[0]
		passed = r[1]
		side = r[2]
	var c := brain.controls(v, tv, delta)
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## Over a lane toward the target's (on its own carriageway) when there's room, at most every
## TOWARD_AGAIN_S: straight into its lane swerved into what was beside.
func _toward_target_lane(tm: TrafficManager, tv: Vehicle) -> void:
	if lane < 0 or _clock - _changed_at < TOWARD_AGAIN_S:
		return
	var their := int(tm.sim.locate(tv.global_position + Vector3.UP * 0.5).get("lane", -1))
	if their < 0 or their == lane or not _same_way(their):
		return
	var info := tm.sim.lane_info(lane)
	var inner := int(tm.sim.lane_info(their).index) > int(info.index)
	var to := int(info.get("inner" if inner else "outer", -1))
	if to >= 0 and not _closed(to) and _room(inner):
		lane = to
		_s = -1.0
		_changed_at = _clock


## Everything the lane driver keeps clear of but the target: it's chased, not followed (the lane
## driver would keep a headway behind it, too far back to ever close in).
func _members(tm: TrafficManager) -> PackedFloat32Array:
	var all := tm.members()
	if mode != Mode.PURSUE or target == null or not is_instance_valid(target):
		return all
	var id := float(tm.member_id(target))
	for i in range(0, all.size(), 9):
		if all[i] == id:
			var out := all.slice(0, i)
			out.append_array(all.slice(i + 9))
			return out
	return all


## True if lane `l` goes the way this car is going (not the other carriageway).
func _same_way(l: int) -> bool:
	var tm := racer.session.traffic
	return int(tm.sim.lane_info(l).get("dir", 0)) == int(tm.sim.lane_info(lane).get("dir", 0))
