class_name HighwayDriver
extends Node
## Drives a car along a highway's lanes (D113): players' autodrive and lane assists
## (docs/ACCESSIBILITY.md §5: on highways they follow the lanes), dev players and bots, and police
## on patrol. It keeps its lane at up to the lane's limit, following what's ahead; the native lane
## driver (NossTraffic.follow) works out steering and pedals. Held up behind something slower it
## moves to a lane beside with room (the inner one first), and after a while with a clear road it
## moves back out: it keeps to the outside. Stuck (wanting to go but not moving, or lost off the
## lanes) or on its side or roof for a while, it resets (to the shoulder).

## Held up this long: over a lane; not again for this long; back out after this long clear.
const OVERTAKE_AFTER_S := 1.5
const CHANGE_AGAIN_S := 4.0
const KEEP_OUT_S := 8.0
## Something slower within this far ahead holds it up (the IDM eases off from well back).
const HELD_GAP_M := 120.0
## Room a lane beside needs: this far ahead, this far behind (m).
const ROOM_AHEAD_M := 40.0
const ROOM_BEHIND_M := 15.0
## Stuck this long, or on its side or roof this long (s): reset.
const STUCK_S := 6.0
const UPSET_S := 3.0

var racer: Racer
## Changes lanes to get by (autodrive, bots, police); a guide never does (the player steers).
var overtakes := true
## Works out controls for a player's access assists instead of driving (VehicleController blends
## them with the player's).
var as_guide := false
## Of the lane's limit.
var speed_factor := 1.0
## The lane followed (the lane graph's index) and where along it, m; -1 until found.
var lane := -1
var _s := -1.0
var _lost := 0.0
var _held := 0.0
var _clear := 0.0
var _clock := 0.0
var _changed_at := -INF
var _stuck := 0.0
var _upset := 0.0


func _ready() -> void:
	process_physics_priority = -50 # after the fields, before the vehicles
	if racer is SessionPlayer and Game.dev.has("speed-factor"):
		speed_factor = clampf(float(Game.dev["speed-factor"]), 0.5, 2.0) # dev: autodrive past the limit (police checks)
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
	if _trouble(c, delta):
		racer.reset_car()
		lane = -1
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
	if overtakes and not as_guide:
		_overtake(delta, float(out[10]), float(out[11]), limit)
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


## True once it has wanted to go but not moved (against a barrier or a wreck; a queue isn't
## stuck: it isn't asking to go), been lost off the lanes, or been on its side or roof for long
## enough.
func _trouble(c: Dictionary, delta: float) -> bool:
	var v := racer.vehicle
	if racer.held or racer.waiting:
		_stuck = 0.0
		_upset = 0.0
		return false
	_upset = _upset + delta if v.global_basis.y.y < 0.3 else 0.0
	_stuck = _stuck + delta if absf(v.speed()) < 1.0 and (float(c.throttle) > 0.3 or lane < 0) else 0.0
	if _upset > UPSET_S or _stuck > STUCK_S:
		_upset = 0.0
		_stuck = 0.0
		return true
	return false


## Held up (`gap` m to what's ahead, going `lead_v`): over a lane with room; clear for a while:
## back out a lane.
func _overtake(delta: float, gap: float, lead_v: float, limit: float) -> void:
	_clock += delta
	var held := gap < HELD_GAP_M and lead_v < limit * 0.9
	_held = _held + delta if held else 0.0
	_clear = _clear + delta if not held else 0.0
	if _clock - _changed_at < CHANGE_AGAIN_S:
		return
	var tm := racer.session.traffic
	var info := tm.sim.lane_info(lane)
	var to := -1
	if _held > OVERTAKE_AFTER_S:
		for side: String in ["inner", "outer"]:
			if int(info.get(side, -1)) >= 0 and _room(side == "inner"):
				to = int(info[side])
				break
	elif _clear > KEEP_OUT_S and int(info.get("outer", -1)) >= 0 and _room(false):
		to = int(info.outer)
	if to >= 0:
		lane = to
		_s = -1.0 # found again on the new lane
		_changed_at = _clock
		_held = 0.0
		_clear = 0.0


## True if the lane beside (to the driver's left if `left`) is clear from ROOM_BEHIND_M behind to
## ROOM_AHEAD_M ahead: traffic, and every other car (players, police).
func _room(left: bool) -> bool:
	var tm := racer.session.traffic
	var v := racer.vehicle
	var lane_m := racer.session.track.highway.lane_m if racer.session.track.highway else 3.6
	var lo := lane_m * 0.5 if left else -lane_m * 1.5
	var hi := lane_m * 1.5 if left else -lane_m * 0.5
	for row: Array in tm.near_rows(v, ROOM_AHEAD_M + 10.0):
		var along: float = row[2]
		var across: float = row[3]
		if across > lo and across < hi and along > -ROOM_BEHIND_M - float(row[5]) and along < ROOM_AHEAD_M:
			return false
	var fwd := Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized()
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	for r in racer.session.racers:
		if r == racer or r.vehicle == null or not is_instance_valid(r.vehicle) or r.waiting:
			continue
		var d := r.vehicle.global_position - v.global_position
		var along := d.dot(fwd)
		var across := d.dot(side)
		if across > lo and across < hi and along > -ROOM_BEHIND_M - 5.0 and along < ROOM_AHEAD_M:
			return false
	return true
