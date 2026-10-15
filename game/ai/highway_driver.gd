class_name HighwayDriver
extends Node
## Drives a car along a highway's lanes (D113): players' autodrive and lane assists
## (docs/ACCESSIBILITY.md §5: on highways they follow the lanes), dev players and bots, and police
## on patrol. It keeps the lane it's in at up to the lane's limit, following what's ahead; the
## native lane driver (NossTraffic.follow) works out steering and pedals.

var racer: Racer
## Works out controls for a player's access assists instead of driving (VehicleController blends
## them with the player's).
var as_guide := false
## Of the lane's limit.
var speed_factor := 1.0
## The lane followed (the lane graph's index) and where along it, m; -1 until found.
var lane := -1
var _s := -1.0
var _lost := 0.0


func _ready() -> void:
	process_physics_priority = -50 # after the fields, before the vehicles
	if as_guide or racer.vehicle == null:
		return
	# The assists a player can use on this platform (AI-05: no other help).
	var allowed: Array = racer.vehicle.platform.get("assists_allowed", [])
	var assists := {}
	for a in ["abs", "tcs", "stability", "auto_gearbox"]:
		assists[a] = a in allowed
	assists.auto_clutch = true
	racer.vehicle.sim.set_assists(assists)


func _physics_process(delta: float) -> void:
	if as_guide:
		return
	var c := controls(delta)
	if c.is_empty():
		return
	var v := racer.vehicle
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## This tick's controls: {steer, throttle, brake, handbrake}, or {} without a car or traffic.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	var tm := racer.session.traffic
	if v == null or not is_instance_valid(v) or tm == null or tm.sim == null:
		return {}
	if racer.held or racer.waiting:
		return { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 1.0 }
	var pos := v.global_position
	if lane < 0:
		var found := tm.sim.locate(pos + Vector3.UP * 0.5)
		lane = int(found.lane)
		_s = float(found.get("s", -1.0))
		if lane < 0:
			return { "steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": 0.0 }
	var p := v.platform
	var e := v.fitted.envelope
	var limit := tm.sim.lane_limit(lane, maxf(_s, 0.0)) * speed_factor
	if racer.pace_limit > 0.0:
		limit = minf(limit, racer.pace_limit) # a run's rolling start
	var out := tm.sim.follow(lane, _s, limit, tm.member_id(racer), pos, v.global_basis.z, v.speed(),
		float(p.geometry.wheelbase_m.ref), deg_to_rad(float(p.steering.max_road_angle_deg)), Vector2(e.size.z / 2.0, e.size.x / 2.0), tm.members())
	_s = out[5]
	# Off the end of a ramp, or far from the lane: find the lane it's on now.
	var info := tm.sim.lane_info(lane)
	if absf(out[6]) > 6.0 or (not bool(info.closed) and _s > float(info.length) - 2.0):
		_lost += delta
		if _lost > 0.3:
			lane = -1
			_lost = 0.0
	else:
		_lost = 0.0
	return { "steer": out[0], "throttle": out[1], "brake": out[2], "handbrake": out[3] }
