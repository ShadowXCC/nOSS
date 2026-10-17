class_name MotionBuffer
extends RefCounted
## Where a remote car is now (D84). Its owner's states arrive about half a round trip late, so the
## car is extrapolated from the newest one to the present server time: velocity, the acceleration
## between the last two states, and the turn rate. When a new state disagrees with what was
## shown, the difference fades out over SMOOTH_S instead of jumping, unless it's more than
## SNAP_M or the car was placed (a reset). With `delay` set, it's shown that far in the past
## instead, interpolated between states (for comparing the two in net_check).

const KEEP := 8
const MAX_EXTRAPOLATE_S := 0.5
const MAX_ACCEL := 20.0
const SNAP_M := 3.0
const SMOOTH_S := 0.15

## > 0: show the car this many seconds in the past, between states.
var delay := 0.0
var states: Array[CarState] = []

var _offset := Vector3.ZERO
var _offset_rot := Quaternion.IDENTITY
var _shown_at := -1.0


## The floating origin moved (D155): every state moves with the world.
func shift(delta: Vector3) -> void:
	for s in states:
		s.xform.origin += delta


func latest() -> CarState:
	return states[-1] if not states.is_empty() else null


func is_empty() -> bool:
	return states.is_empty()


## Adds a state. Returns false for one that's older than the newest (it's dropped). `now` is
## the server time the car is being shown at, for smoothing the correction.
func push(s: CarState, now: float) -> bool:
	if not states.is_empty() and s.time <= states[-1].time:
		return false
	var had := not states.is_empty() and _shown_at >= 0.0
	var before := _raw(now) if had else {}
	states.append(s)
	if states.size() > KEEP:
		states.pop_front()
	if had:
		var after := _raw(now)
		var jump: Vector3 = before.xform.origin - after.xform.origin
		if s.flags & CarState.FLAG_TELEPORT or jump.length() > SNAP_M:
			_offset = Vector3.ZERO
			_offset_rot = Quaternion.IDENTITY
		else:
			_offset += jump
			var qb: Quaternion = before.xform.basis.get_rotation_quaternion()
			var qa: Quaternion = after.xform.basis.get_rotation_quaternion()
			_offset_rot = (qb * qa.inverse() * _offset_rot).normalized()
	return true


## {xform (ground reference), velocity, angular, state (the newest)} at server time `now`, with
## the fading correction; {} before any state. `delta`: time since the last call.
func pose(now: float, delta: float) -> Dictionary:
	if states.is_empty():
		return {}
	var p := _raw(now)
	var fade := exp(-maxf(delta, 0.0) / SMOOTH_S)
	_offset *= fade
	_offset_rot = Quaternion.IDENTITY.slerp(_offset_rot, fade)
	_shown_at = now
	var q: Quaternion = (_offset_rot * p.xform.basis.get_rotation_quaternion()).normalized()
	p.xform = Transform3D(Basis(q), p.xform.origin + _offset)
	return p


## The pose from the states alone.
func _raw(now: float) -> Dictionary:
	var t := now - delay
	var newest: CarState = states[-1]
	if delay > 0.0 and states.size() >= 2 and t < newest.time:
		var i := states.size() - 2
		while i > 0 and states[i].time > t:
			i -= 1
		var a: CarState = states[i]
		var b: CarState = states[i + 1]
		if t >= a.time:
			var span := maxf(b.time - a.time, 1e-4)
			var u := clampf((t - a.time) / span, 0.0, 1.0)
			var pos := Motion.hermite(a.xform.origin, a.velocity, b.xform.origin, b.velocity, span, u)
			var q := a.xform.basis.get_rotation_quaternion().slerp(b.xform.basis.get_rotation_quaternion(), u)
			return { "xform": Transform3D(Basis(q), pos), "velocity": a.velocity.lerp(b.velocity, u),
				"angular": a.angular.lerp(b.angular, u), "state": newest }
	# Past the newest state: extrapolate (constant turn rate and acceleration), capped.
	var dt := clampf(t - newest.time, 0.0, MAX_EXTRAPOLATE_S)
	var accel := Vector3.ZERO
	if states.size() >= 2:
		var prev: CarState = states[-2]
		var span := newest.time - prev.time
		if span > 0.005:
			accel = ((newest.velocity - prev.velocity) / span).limit_length(MAX_ACCEL)
	var origin := newest.xform.origin + newest.velocity * dt + accel * (0.5 * dt * dt)
	var q := Motion.rotate(newest.xform.basis.get_rotation_quaternion(), newest.angular, dt)
	return { "xform": Transform3D(Basis(q), origin), "velocity": newest.velocity + accel * dt,
		"angular": newest.angular, "state": newest }


## How far the newest state is from where the car was predicted to be at its time, from the
## state before it (metres): the extrapolation error net_check reports.
func prediction_error() -> float:
	if states.size() < 2:
		return 0.0
	var prev: CarState = states[-2]
	var newest: CarState = states[-1]
	var dt := clampf(newest.time - prev.time, 0.0, MAX_EXTRAPOLATE_S)
	var guess := prev.xform.origin + prev.velocity * dt
	return guess.distance_to(newest.xform.origin)
