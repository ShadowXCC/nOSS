class_name DragAI
extends Node
## The drag AI (D174): heats its tires, holds the revs on the line, leaves on the green with a
## reaction time of its own, shifts against the same fake tachometer the players read, spends its
## bottle and holds its lane. A strip needs no pathfinding, so there is no nav here at all.
##
## Skill sets every one of those: a poor bot reacts late (and now and then goes red), shifts wide
## of the window, heats its tires badly and wanders in its lane. As a guide it works out the
## steering a player's steering assist follows.

## Reaction to the green (s), skill 0 -> 100. A real tree is won and lost inside a tenth.
const REACTION := Vector2(0.45, 0.05)
## How often a bot jumps the green, skill 0 -> 100.
const RED_CHANCE := Vector2(0.10, 0.0)
## How far off the window's centre it shifts, skill 0 -> 100.
const SHIFT_ERROR := Vector2(0.26, 0.015)
## Burnout: the heat it goes for (s), skill 0 -> 100. The best is DragControl.HEAT_BEST_S.
const HEAT_WANT := Vector2(0.6, 2.0)
## Where in the band it holds the revs: 0 is the bottom, 1 the top. Skill 0 -> 100 centres it.
const REV_SPREAD := Vector2(0.45, 0.06)
## It spends the bottle this long after the launch (s), skill 0 -> 100.
const BOOST_AT := Vector2(2.6, 0.4)
## Lane keeping: how far ahead it aims (the faster it goes the further, so a correction stays
## gentle), how much of the sideways drift it takes out, and the lock it allows itself at speed.
const LANE_LOOK_S := 2.0
const LANE_LOOK_MIN_M := 30.0
const LANE_DAMP := 0.8
const LANE_LOCK := Vector2(1.0, 0.3) # slow -> fast
## With the timing off there is no window to read, so it shifts off the real engine.
const PLAIN_SHIFT := 0.95

var racer: Racer
var skill := 80.0
var as_guide := false
## What it is doing: "wait", "burnout", "stage", "launch", "run" or "coast".
var intent := "wait"

var _rng := RandomNumberGenerator.new()
var _reaction := 0.0
var _rev_want := 0.0
var _heat_want := 0.0
var _boost_at := 0.0
var _shift_error := 0.0
var _since_green := 0.0
var _launched := false
var _planned_pass := -1


func _ready() -> void:
	process_physics_priority = -50
	_rng.seed = hash(racer.number) ^ 0x4d2a
	if as_guide or racer.vehicle == null:
		return
	# No automatic gearbox down a strip (the mode does not allow one): it shifts for itself.
	var allowed: Array = racer.vehicle.platform.get("assists_allowed", [])
	var assists := {}
	for a in ["abs", "tcs", "stability"]:
		assists[a] = a in allowed
	assists.auto_clutch = true
	assists.auto_gearbox = false
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


## This tick's controls: {steer, throttle, brake, handbrake}, or {} without a car or a strip.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	var drag: DragControl = racer.session.drag
	if v == null or not is_instance_valid(v) or drag == null:
		return {}
	var out := { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 0.0 }
	var state: Dictionary = drag.run_of(racer)
	if racer.parked or racer.waiting or state.is_empty():
		intent = "wait"
		_launched = false
		return out
	_plan(drag)
	match drag.phase:
		DragControl.Phase.BURNOUT:
			_burnout(out, state)
		DragControl.Phase.STAGE, DragControl.Phase.TREE:
			_stage(out, drag, delta)
		DragControl.Phase.RUN:
			_run(out, drag, state, delta)
		_:
			intent = "coast"
			out.brake = 1.0
	out.steer = _steer(drag, state)
	return out


## Its numbers for this pass, drawn once (a new pass has a new reaction and a new error).
func _plan(drag: DragControl) -> void:
	if _planned_pass == drag.passes_run:
		return
	_planned_pass = drag.passes_run
	var t := clampf(skill / 100.0, 0.0, 1.0)
	_reaction = maxf(lerpf(REACTION.x, REACTION.y, t) + _rng.randfn(0.0, 0.03), 0.0)
	_heat_want = lerpf(HEAT_WANT.x, HEAT_WANT.y, t) + _rng.randfn(0.0, 0.3)
	_shift_error = lerpf(SHIFT_ERROR.x, SHIFT_ERROR.y, t)
	_boost_at = maxf(lerpf(BOOST_AT.x, BOOST_AT.y, t) + _rng.randfn(0.0, 0.2), 0.0)
	var spread := lerpf(REV_SPREAD.x, REV_SPREAD.y, t)
	_rev_want = clampf(0.5 + _rng.randfn(0.0, spread), 0.0, 1.0)
	_since_green = 0.0
	_launched = false
	# Now and then a poor bot leaves before the green and takes the red light for it.
	if _rng.randf() < lerpf(RED_CHANCE.x, RED_CHANCE.y, t):
		_reaction = -_rng.randf_range(0.05, 0.25)


## The water box: throttle against the brake until the tires are as hot as it wants them.
func _burnout(out: Dictionary, state: Dictionary) -> void:
	intent = "burnout"
	if float(state.heat) < _heat_want:
		out.throttle = 0.85
		out.brake = 0.6
	else:
		out.brake = 1.0


## On the line: the revs it holds, in the band DragControl asks for.
func _stage(out: Dictionary, drag: DragControl, delta: float) -> void:
	intent = "stage"
	var band: Array = drag.window(racer)
	var level := 0.0
	if band.is_empty():
		level = _rev_want
	else:
		var centre := float(band[0])
		var width := float(band[1])
		level = centre + (_rev_want - 0.5) * width
	drag.rev(racer, clampf(level, 0.0, 1.0))
	out.handbrake = 1.0
	# A bot that drew a negative reaction leaves while the tree is still amber: a red light.
	if _reaction < 0.0 and drag.phase == DragControl.Phase.TREE and not _launched:
		_since_green += delta
		if _since_green >= DragControl.AMBERS * DragControl.AMBER_S + _reaction:
			_launched = true
			drag.launch(racer)


## Down the strip: away on the green, flat out, shifting on the needle, and the bottle in time.
func _run(out: Dictionary, drag: DragControl, state: Dictionary, delta: float) -> void:
	_since_green += delta
	if not _launched:
		intent = "launch"
		if _since_green < maxf(_reaction, 0.0):
			out.brake = 0.3
			return
		_launched = true
		drag.launch(racer)
	intent = "run"
	if bool(state.done) or bool(state.blown):
		# Through the lights (or out of engine): stop inside the shutdown, well short of the sand.
		intent = "coast"
		out.brake = 1.0
		return
	# Feathering it is how a shake is caught (DragControl._shake).
	if float(state.shake) > 0.0:
		out.throttle = 0.0
		out.brake = 0.1
		return
	out.throttle = 1.0
	_maybe_shift(drag, state)
	if int(state.boosts) > 0 and _since_green >= maxf(_reaction, 0.0) + _boost_at:
		drag.use_boost(racer)


## Shifts when the needle reaches where it means to shift: the window's centre, off by as much
## as its skill lets it be. With the timing off it reads the real engine instead.
func _maybe_shift(drag: DragControl, _state: Dictionary) -> void:
	var v := racer.vehicle
	if v.sim.is_shifting() or v.sim.get_gear() >= _top_gear():
		return
	var band: Array = drag.window(racer)
	if band.is_empty():
		var limiter := float(v.platform.engine.limiter_rpm)
		if v.sim.get_rpm() >= limiter * PLAIN_SHIFT:
			v.sim.shift(1)
		return
	if drag.needle(racer) >= float(band[0]) + _shift_error:
		v.sim.shift(1)


func _top_gear() -> int:
	return int((racer.vehicle.platform.gearbox.ratios as Array).size())


## Holds its lane: aims at a point down the strip on the lane's middle line and steers at it,
## taking out the sideways drift on the way. Positive steer is to the right, which is -X with the
## cars facing +Z, so a car too far +X steers positive to come back.
func _steer(drag: DragControl, state: Dictionary) -> float:
	var v := racer.vehicle
	var lane := int(state.get("lane", 0))
	var off := racer.com().x - drag.layout.lane_x(lane)
	var fwd := v.global_basis.z.slide(Vector3.UP).normalized()
	if fwd.length() < 0.5:
		return 0.0
	var speed := absf(v.speed())
	var look := maxf(speed * LANE_LOOK_S, LANE_LOOK_MIN_M)
	# The heading that leads back to the middle, and the one it is actually pointing in.
	var want := -atan2(off, look)
	var heading := atan2(fwd.x, fwd.z)
	var local_v := v.global_basis.inverse() * v.linear_velocity
	var drift := atan2(local_v.x, maxf(absf(local_v.z), 1.0))
	var max_steer := deg_to_rad(float(v.platform.steering.max_road_angle_deg))
	var cmd := (heading + drift * LANE_DAMP - want) / max_steer
	var lock := lerpf(LANE_LOCK.x, LANE_LOCK.y, clampf(speed / 60.0, 0.0, 1.0))
	return clampf(cmd, -lock, lock)
