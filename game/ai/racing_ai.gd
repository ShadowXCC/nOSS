class_name RacingAI
extends Node
## Drives a racer's car around the RacingLine (AI-01, AI-05) through the same controls as a
## player, on the same platform and assists: no grip or power help. Skill (0-100) sets how much
## of the grip it uses, its following gap and its line precision.
##
## Every tick (120 Hz) it steers by pure pursuit on the line plus its planned offset and follows
## the line's target speed. A few times a second it plans around the other cars, which it reads
## from the RaceField: keep a gap, pass on a side with room, hold its line side by side, defend
## once per straight, let lapping cars by, and brake hard if a crash is close. It reverses out
## or resets when stuck.

const CAR_LENGTH := 4.6
const CAR_WIDTH := 2.0
## Lateral room kept between cars side by side, m.
const SIDE_GAP := 1.1
const PLAN_HZ := 30.0
const LOOK_BEHIND_M := 30.0
## After a standing start the car keeps its grid column this far.
const START_HOLD_M := 200.0
const CAUTION_GRIP := 0.93
## Lateral speed of the planned offset, m/s.
const OFFSET_RATE := 2.5
## Body slip past this catches a slide (steering toward where the car is going), degrees.
const CATCH_SLIP_DEG := 2.0
## Skill 0 -> 100.
const GRIP := Vector2(0.78, 0.95)
const GAP_TIME := Vector2(1.1, 0.55)
const LINE_NOISE := Vector2(0.7, 0.1)

var racer: Racer
## 0-100 (docs/GAMEMODES.md §0).
var skill := 80.0
## Works out controls for a player's access assists instead of driving (VehicleController
## blends them with the player's): it leaves the car's assists alone and never resets the car.
var as_guide := false
## Planned offset from the racing line, m (+ = left). Moves toward the plan at OFFSET_RATE.
var offset := 0.0
## What the planner decided last ("line", "follow", "pass", "side", "defend", "yield", "start").
var intent := "line"

var _line: RacingLine
var _profile := PackedFloat32Array()
var _caution_profile := PackedFloat32Array()
## Deceleration at full brake pedal, m/s² (before the tires' limit).
var _brake_full := 14.0
## What emergency braking counts on, m/s² (the brake balance's limit, with margin).
var _emergency_decel := 9.0
var _want := 0.0 # planned offset from the line
var _speed_cap := INF
var _emergency := false
var _plan_time := 0.0
var _covered := 0.0 # metres since leaving a standstill hold
var _start_lateral := 0.0
var _passing: Racer
var _defended := false
var _noise_phase := Vector2.ZERO
var _stuck_time := 0.0
var _reverse_time := 0.0
var _trouble_time := 0.0
var _rng := RandomNumberGenerator.new()
var _road_grip := 1.0
var _road_check := 0.0
## Stuck this long: back out; this long: reset (a kart AI is quicker with both).
var stuck_reverse_s := 2.5
var stuck_reset_s := 7.0
## Stopped behind a car counts as stuck too (a kart jammed behind another; off for cars, which
## queue at a start).
var stuck_behind := false


func _ready() -> void:
	process_physics_priority = -50 # after the RaceField, before the vehicles
	_rng.seed = hash(racer.number) ^ 0x5eed
	_plan_time = _rng.randf() / PLAN_HZ # spread planning over ticks
	_noise_phase = Vector2(_rng.randf() * TAU, _rng.randf() * TAU)
	_line = RacingLine.for_track(racer.track)
	_make_profiles()
	var p := racer.vehicle.platform
	_brake_full = float(p.brakes.max_torque_nm) / float(p.geometry.wheel_radius_m.ref) / float(p.mass.kg)
	_emergency_decel = 0.8 * RacingLine.max_braking(p, float(p.tires.mu_peak))
	if as_guide:
		return
	# The assists a player can use on this platform (AI-05: no other help).
	var allowed: Array = p.get("assists_allowed", [])
	var assists := {}
	for a in ["abs", "tcs", "stability", "auto_gearbox"]:
		assists[a] = a in allowed
	assists.auto_clutch = true
	racer.vehicle.sim.set_assists(assists)
	_start_lateral = racer.lateral
	offset = racer.lateral - _line.offset_at(racer.distance)
	_want = offset


func _skill() -> float:
	return clampf(skill, 0.0, 100.0) / 100.0


## The share of the tires' grip it drives on (KartAI adds the kart's).
func _base_grip() -> float:
	return lerpf(GRIP.x, GRIP.y, _skill())


## Speeds from the line for its grip on this road (wet or snowy roads are slower, D153).
func _make_profiles() -> void:
	var grip := _base_grip() * _road_grip
	_profile = _line.speed_profile(racer.vehicle.base_platform, grip)
	_caution_profile = _line.speed_profile(racer.vehicle.base_platform, grip * CAUTION_GRIP)


## The road's grip under the car (EnvDirector sets its conditions), in steps of 0.05 so the
## profiles (cached per grip) are made again only when the weather really changes.
func _check_road() -> void:
	if racer.vehicle == null or not is_instance_valid(racer.vehicle):
		return
	var c := racer.vehicle.sim.get_conditions()
	var road := snappedf(VehicleSim.surface_grip(VehicleSim.SURFACE_ASPHALT, c.x, c.y), 0.05)
	if not is_equal_approx(road, _road_grip):
		_road_grip = road
		_make_profiles()


func _physics_process(delta: float) -> void:
	if as_guide:
		return
	var c := controls(delta)
	if c.is_empty():
		return
	var vehicle := racer.vehicle
	vehicle.steer = c.steer
	vehicle.throttle = c.throttle
	vehicle.brake = c.brake
	vehicle.handbrake = c.handbrake


## This tick's controls: {steer, throttle, brake, handbrake}, or {} without a car.
func controls(delta: float) -> Dictionary:
	var vehicle := racer.vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		return {}
	_road_check -= delta
	if _road_check <= 0.0:
		_road_check = 0.5
		_check_road()
	var out := { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 0.0 }
	if racer.held or racer.waiting:
		_hold(out)
		return out
	var v := maxf(racer.speed, 0.0)
	_covered += v * delta
	_plan_time -= delta
	if _plan_time <= 0.0:
		_plan_time += 1.0 / PLAN_HZ
		_plan()
	offset = move_toward(offset, _want, OFFSET_RATE * delta)
	if not as_guide and _recover(out, delta):
		return out
	_steer(vehicle, v, out)
	_pedals(vehicle, v, out)
	return out


## Waits on the handbrake: holding the brake at a standstill would select reverse with the
## automatic gearbox.
func _hold(out: Dictionary) -> void:
	out.throttle = 0.0
	out.brake = 0.0
	out.steer = 0.0
	out.handbrake = 1.0
	_covered = 0.0
	_start_lateral = racer.lateral
	offset = racer.lateral - _line.offset_at(racer.distance)
	_want = offset
	_stuck_time = 0.0


# --- control (every tick) -----------------------------------------------------------------


func _steer(vehicle: Vehicle, v: float, out: Dictionary) -> void:
	var look := clampf(5.0 + 0.32 * v, 6.0, 32.0)
	var d := racer.distance + look
	var lateral := clampf(_line.offset_at(d) + offset, _line.corridor(d).y, _line.corridor(d).x)
	# Pure pursuit cuts corners by about look² κ / 8; aim that much wide.
	lateral -= _line.curvature_at(racer.distance + look * 0.5) * look * look / 8.0
	out.steer = _pursue(vehicle, racer.track.transform_at(d, lateral).origin, v)
	out.handbrake = 0.0


## Pure pursuit: the arc through `target`, steered through the reference wheelbase, catching
## slides by steering toward where the car is going.
func _pursue(vehicle: Vehicle, target: Vector3, v: float) -> float:
	var local := vehicle.global_basis.inverse() * (target - racer.com())
	var dist2 := maxf(local.x * local.x + local.z * local.z, 1.0)
	var kappa := 2.0 * local.x / dist2 # + = left
	var wheelbase := float(vehicle.platform.geometry.wheelbase_m.ref)
	var max_steer := deg_to_rad(float(vehicle.platform.steering.max_road_angle_deg))
	var steer := -atan(wheelbase * kappa) / max_steer
	var local_v := vehicle.global_basis.inverse() * vehicle.linear_velocity
	if v > 6.0:
		# Only the slide past CATCH_SLIP: a car held at its limit through a long corner (an oval's)
		# runs a couple of degrees of slip all the way round, and steering against all of it ran
		# the car wide.
		var slip := atan2(local_v.x, absf(local_v.z)) # + = sliding left
		var past := absf(slip) - deg_to_rad(CATCH_SLIP_DEG)
		if past > 0.0:
			steer += clampf(-signf(slip) * past * 0.8 / max_steer, -0.5, 0.5)
	return clampf(steer, -1.0, 1.0)


func _pedals(vehicle: Vehicle, v: float, out: Dictionary) -> void:
	var profile := _caution_profile if _cautious() else _profile
	var here := racer.distance + v * 0.1
	var target := _line.speed_at(profile, here)
	if racer.finished:
		target *= 0.6 # cool-down lap
	# Off the line in a corner the radius is different: a little slower.
	if absf(_line.curvature_at(here)) > 0.004:
		target *= 1.0 - 0.02 * absf(offset)
	target = minf(target, _speed_cap)
	# The deceleration the line plans just ahead, as the brake pedal's feed-forward.
	var v_near := _line.speed_at(profile, here + 2.0)
	var v_far := _line.speed_at(profile, here + 12.0)
	var decel := maxf((v_near * v_near - v_far * v_far) / 20.0, 0.0)
	var error := target - v
	var throttle := 0.0
	var brake := 0.0
	if _emergency:
		brake = 1.0
	elif error < -1.0 or (decel > 0.5 and error < 1.0):
		# Too fast, or on the line's braking curve: follow its deceleration.
		brake = clampf(decel / _brake_full + maxf(-error, 0.0) * 0.12 - maxf(error, 0.0) * 0.3, 0.0, 1.0)
	else:
		throttle = clampf(0.5 + error, 0.0, 1.0)
	# Sliding: ease off the brakes so the tires can hold the car, and gently on the throttle.
	var local_v := vehicle.global_basis.inverse() * vehicle.linear_velocity
	var slip := absf(rad_to_deg(atan2(local_v.x, absf(local_v.z)))) if v > 8.0 else 0.0
	if slip > 3.0 and not _emergency:
		brake *= clampf(1.0 - (slip - 3.0) / 4.0, 0.0, 1.0)
		throttle = minf(throttle, 0.3)
	out.throttle = throttle
	out.brake = brake


## Lap 1 is driven with care until the track's caution distance past the start line (past the
## first corners).
func _cautious() -> bool:
	var until := racer.track.caution_until_m
	return racer.timer.lap <= 1 and racer.track.from_start(racer.distance) < until and _covered < until + 300.0


# --- planning (PLAN_HZ) -------------------------------------------------------------------


func _plan() -> void:
	var s := _skill()
	var v := maxf(racer.speed, 0.0)
	var line_here := _line.offset_at(racer.distance)
	var corridor := _line.corridor(racer.distance)
	var gap_time := lerpf(GAP_TIME.x, GAP_TIME.y, s) + (0.3 if _cautious() else 0.0)
	_speed_cap = INF
	var formation := racer.pace_limit > 0.0
	if formation:
		_speed_cap = racer.pace_limit
	_emergency = false
	intent = "line"

	# Where we'd be without traffic: the line, with a little wander, or the grid column at the start.
	var noise := lerpf(LINE_NOISE.x, LINE_NOISE.y, s) * sin(racer.distance / 97.0 + _noise_phase.x) * sin(racer.distance / 41.0 + _noise_phase.y)
	var want_lat := line_here + noise
	if _covered < START_HOLD_M:
		want_lat = _start_lateral
		intent = "start"
	var me_lat := racer.lateral
	var field := racer.session.field
	var cars := field.around(racer, 60.0 + v * 2.0, LOOK_BEHIND_M)

	# Braking zone close ahead: no new passing moves unless already alongside.
	var braking_soon := _line.speed_at(_profile, racer.distance + 40.0 + v * 0.5) < v - 6.0
	var inside := signf(_upcoming_turn())

	# 1. The car ahead in our path: pass it if there's room, otherwise follow it.
	var lead: Dictionary = {}
	for c: Dictionary in cars:
		var other: Racer = c.racer
		if c.gap <= 0.0 or _ignore(other):
			continue
		if c.gap - CAR_LENGTH > 0.5 and absf(c.lateral - want_lat) < CAR_WIDTH + SIDE_GAP and absf(c.lateral - me_lat) < CAR_WIDTH + SIDE_GAP + absf(want_lat - me_lat):
			lead = c
			break
	if _passing and not is_instance_valid(_passing):
		_passing = null
	if not lead.is_empty():
		var other: Racer = lead.racer
		var bumper: float = lead.gap - CAR_LENGTH
		var their_v := maxf(other.speed, 0.0)
		var my_pace := _line.speed_at(_profile, other.distance)
		var faster := their_v < my_pace - 1.0 or v > their_v + 1.0
		var side := 0.0
		if faster and not formation and bumper < 35.0 and (not braking_soon or bumper < 2.0 or _passing == other):
			side = _pass_side(other, cars, inside, me_lat)
		if side != 0.0:
			want_lat = other.lateral + side * (CAR_WIDTH + SIDE_GAP + 0.2)
			_passing = other
			intent = "pass"
			# Still in their lane: keep the gap until we're out of it.
			if absf(other.lateral - me_lat) < CAR_WIDTH + 0.4:
				_follow(other, bumper, v, gap_time * 0.6)
		else:
			_follow(other, bumper, v, gap_time)
			intent = "follow"
	else:
		_passing = null

	# 2. Cars alongside, or about to be in another lane: each keeps to its own side of the
	# midpoint between them, half the room each, so two cars moving at once can't meet.
	# Never steer across one. Squeezed with no room, the car further back gives way.
	var lo := corridor.y
	var hi := corridor.x
	var room := CAR_WIDTH + SIDE_GAP
	var squeeze_ahead: Racer = null
	for c: Dictionary in cars:
		var other: Racer = c.racer
		if _ignore(other):
			continue
		var along := absf(c.gap)
		var overlap := along < CAR_LENGTH + 1.0
		var other_lane := absf(other.lateral - me_lat) > CAR_WIDTH * 0.75 and along < CAR_LENGTH + 3.0 + v * 0.15
		if not overlap and not other_lane:
			continue
		var mid := (me_lat + other.lateral) / 2.0
		if other.lateral >= me_lat:
			hi = minf(hi, mid - room / 2.0)
		else:
			lo = maxf(lo, mid + room / 2.0)
		if c.gap > 0.0:
			squeeze_ahead = other
	if lo > hi:
		want_lat = clampf(me_lat, hi, lo)
		intent = "side"
		if squeeze_ahead:
			_speed_cap = minf(_speed_cap, maxf(squeeze_ahead.speed, 0.0) - 1.5)
	elif want_lat > hi or want_lat < lo:
		want_lat = clampf(want_lat, lo, hi)
		intent = "side"

	# 3. Cars behind: let lapping cars by; defend once per straight.
	if absf(_line.curvature_at(racer.distance)) > 0.006:
		_defended = false
	for c: Dictionary in cars:
		var other: Racer = c.racer
		if c.gap >= 0.0 or _ignore(other):
			continue
		if other.timer.lap > racer.timer.lap and -c.gap < 60.0 and other.speed > v - 2.0:
			# Blue flag: move off the line and ease off on the straight.
			want_lat = line_here - signf(line_here if line_here != 0.0 else 1.0) * 3.0
			if absf(_line.curvature_at(racer.distance)) < 0.004:
				_speed_cap = minf(_speed_cap, v * 0.97)
			intent = "yield"
			break
		if intent == "line" and not _defended and -c.gap < 25.0 and other.speed > v + 0.5 and braking_soon and inside != 0.0:
			_defended = true
			intent = "defend"
		if intent == "defend":
			want_lat = clampf(line_here + inside * 2.0, corridor.y, corridor.x)

	# 4. Something stopped or much slower in our path close ahead: brake now.
	for c: Dictionary in cars:
		var other: Racer = c.racer
		if c.gap <= 0.0 or _ignore(other):
			continue
		var bumper: float = c.gap - CAR_LENGTH
		var closing := v - maxf(other.speed, 0.0)
		var in_path := absf(other.lateral - me_lat) < CAR_WIDTH + 0.4 or absf(other.lateral - (want_lat if intent != "pass" else me_lat)) < CAR_WIDTH + 0.4
		# Room to lose the closing speed braking hard, plus a reaction margin.
		var needed := closing * closing / (2.0 * _emergency_decel) + closing * (0.5 + 0.3 * (1.0 - s))
		if in_path and closing > 0.5 and bumper < needed:
			_emergency = true
			_speed_cap = minf(_speed_cap, maxf(other.speed, 0.0) - 2.0)

	if lo <= hi:
		want_lat = clampf(want_lat, lo, hi)
	_want = clampf(want_lat, corridor.y, corridor.x) - line_here


## Speed limit to stay behind `other` with a safe gap (time gap plus what the speed difference
## needs, assuming they brake as hard as we can).
func _follow(other: Racer, bumper: float, v: float, gap_time: float) -> void:
	var their_v := maxf(other.speed, 0.0)
	var keep := 2.0 + v * gap_time
	var brake := 0.5 * float(racer.vehicle.platform.tires.mu_peak) * 9.81
	var cap: float
	if bumper < keep:
		cap = their_v - (keep - bumper) * 0.6
	else:
		cap = sqrt(their_v * their_v + 2.0 * brake * (bumper - keep))
	_speed_cap = minf(_speed_cap, maxf(cap, 0.0))


## Which side to pass `other` on: +1 left, -1 right, 0 none. Needs room on the road and no car
## there; prefers the inside of the next turn, then the side we're already on.
func _pass_side(other: Racer, cars: Array[Dictionary], inside: float, me_lat: float) -> float:
	var best := 0.0
	var best_score := -INF
	var corridor := _line.corridor(other.distance)
	for side: float in [1.0, -1.0]:
		var lat := other.lateral + side * (CAR_WIDTH + SIDE_GAP + 0.2)
		if lat > corridor.x or lat < corridor.y:
			continue
		var clear := true
		for c: Dictionary in cars:
			var r: Racer = c.racer
			if r == other or _ignore(r):
				continue
			if c.gap > -CAR_LENGTH - 4.0 and c.gap < field_gap(other) + CAR_LENGTH + 12.0 and absf(r.lateral - lat) < CAR_WIDTH + SIDE_GAP:
				clear = false
				break
		if not clear:
			continue
		var score := -absf(lat - me_lat) * 0.3 + (2.0 if side == inside else 0.0)
		if _passing == other and signf(me_lat - other.lateral) == side:
			score += 3.0 # keep the side we committed to
		if score > best_score:
			best_score = score
			best = side
	return best


func field_gap(other: Racer) -> float:
	return racer.session.field.gap(racer, other)


## +: the next real corner within 200 m turns left, -: right, 0: none.
func _upcoming_turn() -> float:
	var d := 20.0
	while d < 200.0:
		var k := _line.curvature_at(racer.distance + d)
		if absf(k) > 0.006:
			return signf(k)
		d += 10.0
	return 0.0


func _ignore(other: Racer) -> bool:
	return other.vehicle == null or other.ghosted or other.waiting


# --- recovery -----------------------------------------------------------------------------


## Reverses out when stuck, then resets if that doesn't work. True while it's handling the car.
func _recover(out: Dictionary, delta: float) -> bool:
	var vehicle := racer.vehicle
	var v := absf(racer.speed)
	var upright := vehicle.global_basis.y.y > 0.3
	var heading := vehicle.global_basis.z.dot(racer.track.tangents[maxi(racer.track_index, 0)])
	var off := absf(racer.lateral) > racer.track.half_width(racer.distance, racer.lateral) + racer.track.apron(racer.track_index, racer.lateral) + 4.0
	var backwards := heading < -0.2 and v > 3.0
	if not upright or off or backwards:
		_trouble_time += delta
	else:
		_trouble_time = maxf(_trouble_time - delta * 2.0, 0.0)
	if v < 1.0 and not racer.held and (_speed_cap > 1.0 or stuck_behind):
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _trouble_time > 3.0 or _stuck_time > stuck_reset_s:
		_trouble_time = 0.0
		_stuck_time = 0.0
		_reverse_time = 0.0
		racer.reset_car()
		return false
	# Stuck against something: back out for a moment, steering away from where the line is.
	if _stuck_time > stuck_reverse_s and _reverse_time <= 0.0:
		_reverse_time = 1.6
	if _reverse_time > 0.0:
		_reverse_time -= delta
		out.throttle = 0.0
		out.brake = 0.7 # the auto gearbox selects reverse at a standstill
		out.steer = clampf((racer.lateral - _line.offset_at(racer.distance)) * 0.3, -1.0, 1.0)
		out.handbrake = 0.0
		return true
	return false
