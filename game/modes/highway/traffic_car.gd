class_name TrafficCar
extends Node
## A traffic car turned into a physics car near a player (D110, D120): a Vehicle on its type's
## traffic platform, driven by the native lane driver after its lane-sim shadow (NossTraffic.drive),
## in lite mode (no engine sound, visuals once a frame). The TrafficManager makes and removes them.
## Online, the game that owns it drives it and sends its states; everywhere else it's a `remote`
## proxy (kinematic) shown where those states put it, or where its shadow is until they come.

## A unit with its siren on this close behind: it slows to this share of its lane's pace (the lane
## sim moves it over, D192).
const SIREN_M := 120.0
const SIREN_PACE := 0.45
## Stopped this long while its shadow drives on, or on its side: a wreck.
const STUCK_S := 4.0
const STUCK_EVERY := 8
const RESHADOW_M := 15.0
const OFF_LANE_S := 2.0
## A proxy without a state this long follows its shadow again (its owner stopped sending it here).
const STALE_S := 1.0
## Spawned on another car: no contact until it's clear, this long at most.
const GHOST_S := 3.0
## A proxy put this far from where it was shown (its owner's first states, a correction) jumps
## there without touching anything until it's clear: a kinematic body moved into a car would
## throw it.
const JUMP_M := 1.5
## A proxy far from everything its game drives (TrafficManager.NEAR_DRIVEN_M; NEAR_SEEN_M where
## cars are drawn) follows its owner's states only every this many ticks: FAR_EVERY where nobody
## sees it (a server, a headless bot), FAR_EVERY_SEEN where cars are drawn.
const FAR_EVERY := 4
const FAR_EVERY_SEEN := 2
const NEAR_SEEN_M := 150.0

var manager: TrafficManager
var car := -1
var vehicle: Vehicle
## Where the driver last had it: lane, s (its front, m), m off the lane's line, heading error.
var lane := -1
var s := 0.0
var lateral := 0.0
var heading_error := 0.0
var blocked := false
var gap := INF
var wrecked := false
var stuck_time := 0.0
## Seconds nobody has been near it (TrafficManager).
var alone := 0.0
## Another game drives it: shown from its owner's states (D110).
var remote := false
var buffer := MotionBuffer.new()
## The owner's word on it (CarState flags2: wrecked, on its lane's line).
var remote_flags := 0
## No contact while it starts on top of another car.
var ghost_time := 0.0
## Bots (NetRacer.measure): how far off a proxy was shown, against its owner's states for then.
var errors := PackedFloat32Array()
var _shown_t := PackedFloat64Array()
var _shown_p := PackedVector3Array()
## Counts as a wreck at the next decision (wreck()).
var _wreck_now := false
var _moved_frame := -1
var _off_time := 0.0
var _wheelbase := 2.7
var _max_steer := 0.55
var _half := Vector2(2.25, 0.9)


func _ready() -> void:
	process_physics_priority = -50
	var p := vehicle.platform
	_wheelbase = float(p.geometry.wheelbase_m.ref)
	_max_steer = deg_to_rad(float(p.steering.max_road_angle_deg))
	var e := vehicle.fitted.envelope
	_half = Vector2(e.size.z / 2.0, e.size.x / 2.0)
	var assists := { "abs": true, "tcs": true, "stability": true, "auto_gearbox": true, "auto_clutch": true }
	vehicle.sim.set_assists(assists)


func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if ghost_time > 0.0:
		ghost_time -= delta
		if ghost_time <= 0.0 or not manager.overlaps(self):
			ghost_time = 0.0
			vehicle.set_ghost(false)
	if remote:
		var every := FAR_EVERY_SEEN if Vehicle.drawn else FAR_EVERY
		var near := NEAR_SEEN_M if Vehicle.drawn else TrafficManager.NEAR_DRIVEN_M
		if (Engine.get_physics_frames() + car) % every == 0 or manager.near_driven(vehicle.global_position, near):
			_follow(delta)
		return
	if wrecked:
		vehicle.throttle = 0.0
		vehicle.brake = 0.0
		vehicle.handbrake = 1.0
		vehicle.indicators = 3 # hazards
		return
	var out := manager.sim.drive(car, car, vehicle.global_position, vehicle.global_basis.z, vehicle.speed(), _wheelbase, _max_steer, _half, manager.members())
	vehicle.steer = out[0]
	vehicle.throttle = out[1]
	vehicle.brake = out[2]
	vehicle.handbrake = out[3]
	lane = int(out[4])
	s = out[5]
	lateral = out[6]
	heading_error = out[7]
	blocked = out[8] > 0.5
	vehicle.indicators = 1 if out[9] > 0.5 else (2 if out[9] < -0.5 else 0)
	gap = out[10]
	if manager.siren_behind(vehicle, SIREN_M) and vehicle.speed() > float(manager.sim.car(car).get("v", 0.0)) * SIREN_PACE:
		vehicle.throttle = 0.0
		vehicle.brake = maxf(vehicle.brake, 0.25)
	# Stuck: not moving while the lane sim's version of it is (a queue or a merge isn't stuck).
	# Looked at every STUCK_EVERY ticks.
	if (Engine.get_physics_frames() + car) % STUCK_EVERY == 0:
		var shadow_v := float(manager.sim.car(car).get("v", 0.0))
		stuck_time = stuck_time + delta * STUCK_EVERY if absf(vehicle.speed()) < 1.0 and shadow_v > 3.0 else 0.0


## A proxy: where its owner's states put it now, or where its shadow is if none have come lately.
func _follow(delta: float) -> void:
	var now := manager.now()
	var p := buffer.pose(now, delta) if not buffer.is_empty() else {}
	if not p.is_empty() and now - (p.state as CarState).time < STALE_S:
		var st: CarState = p.state
		vehicle.remote_state = st
		_move(p.xform, p.velocity, p.angular, st.flags & CarState.FLAG_TELEPORT != 0)
		CarState.show_on(vehicle, st.flags2)
		remote_flags = st.flags2
		if NetRacer.measure:
			_shown_t.append(now)
			_shown_p.append(p.xform.origin)
			if _shown_t.size() > 120:
				_shown_t = _shown_t.slice(60)
				_shown_p = _shown_p.slice(60)
		return
	var at := manager.shadow_pose(car)
	if not at.is_empty():
		_move(at.xform, at.velocity, Vector3.ZERO, false)


## A proxy to `xform`: a jump goes there at once, with no contact until it's clear.
func _move(xform: Transform3D, velocity: Vector3, angular: Vector3, snap: bool) -> void:
	var frame := Engine.get_physics_frames()
	var ticks := clampi(frame - _moved_frame, 1, FAR_EVERY) if _moved_frame >= 0 else 1
	_moved_frame = frame
	var jump := vehicle.ground_reference().origin.distance_to(xform.origin) > JUMP_M + velocity.length() * ticks / Engine.physics_ticks_per_second
	if jump and ghost_time <= 0.0:
		ghost_time = GHOST_S
		vehicle.set_ghost(true, false)
	vehicle.move_remote(xform, velocity, angular, snap or jump)


## A state from its owner (online).
func push_state(st: CarState, now: float) -> void:
	if NetRacer.measure and st.flags & CarState.FLAG_TELEPORT == 0:
		for i in range(_shown_t.size() - 2, -1, -1):
			if _shown_t[i] <= st.time and st.time <= _shown_t[i + 1]:
				var u := (st.time - _shown_t[i]) / maxf(_shown_t[i + 1] - _shown_t[i], 1e-6)
				errors.append(_shown_p[i].lerp(_shown_p[i + 1], u).distance_to(st.xform.origin))
				break
	buffer.push(st, now)


## Where the lane sim would have a proxy now (its lane, how far along, how far off the line),
## from where it is: the server rules on it from that (D110).
func observe() -> void:
	var at := manager.sim.locate(vehicle.global_position + Vector3.UP * 0.5)
	lane = int(at.get("lane", -1))
	s = float(at.get("s", 0.0))
	lateral = float(at.get("lateral", 0.0))
	heading_error = 0.0 if remote_flags & CarState.FLAG2_LANE_OK else 1.0


## Its driver's word for the network: wrecked, back on its lane's line.
func flags2() -> int:
	return (CarState.FLAG2_WRECKED if wrecked or crashed() else 0) | (CarState.FLAG2_LANE_OK if lane_ok() else 0)


## Back on its lane's line, heading along it and the right way up: it can go back into the lane sim.
func lane_ok() -> bool:
	if remote:
		return lane >= 0 and remote_flags & CarState.FLAG2_LANE_OK != 0
	return lane >= 0 and absf(lateral) < 1.2 and absf(heading_error) < 0.2 and vehicle.global_basis.y.y > 0.95


## On its side or roof, or stopped where nothing holds it up: a wreck.
func crashed() -> bool:
	if remote:
		return _wreck_now or remote_flags & CarState.FLAG2_WRECKED != 0
	return _wreck_now or vehicle.global_basis.y.y < 0.5 or stuck_time > STUCK_S


## Makes it a wreck at the next decision (police stops; tests).
func wreck() -> void:
	_wreck_now = true


## Far enough from its shadow that the lane sim should be told where it really is (RESHADOW).
func drifted(delta: float) -> bool:
	var shadow := manager.sim.car(car)
	if shadow.is_empty() or lane < 0:
		return false
	if int(shadow.lane) == lane:
		_off_time = 0.0
		return absf(float(shadow.s) - s) > RESHADOW_M
	if int(shadow.lc_from) == lane:
		return false # its shadow is moving over and it isn't yet
	_off_time += delta
	return _off_time > OFF_LANE_S
