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
## or resets when stuck. In a pack (D213: drafting on a track that suggests it) it runs in the
## line's grooves instead: close in the draft, runs into a free groove, blocks.

const CAR_LENGTH := 4.6
const CAR_WIDTH := 2.0
## Lateral room kept between cars side by side, m.
const SIDE_GAP := 1.1
const PLAN_HZ := 30.0
const LOOK_BEHIND_M := 30.0
## After a standing start the car keeps its grid column this far.
const START_HOLD_M := 200.0
const CAUTION_GRIP := 0.93
## Lateral speed of the planned offset across the road, m/s (keeping its place while the line
## sweeps across under it is free).
const OFFSET_RATE := 2.5
## The plan keeps to the road as narrow as it gets over the next car length plus 10 m plus this
## much travel, s.
const AHEAD_S := 0.6
## Body slip past this catches a slide (steering toward where the car is going), degrees.
const CATCH_SLIP_DEG := 2.0
## Pure pursuit steers by the geometry alone; loaded in a long fast corner the tires need more lock
## than that (their slip angles), so it would settle wide of its line. Above TRIM_SPEED (m/s), in
## a corner (the line's curvature past TRIM_CURVATURE), it trims the curvature it asks for by how
## far the car's own (its yaw rate over its speed) falls short: TRIM_GAIN a second, up to
## TRIM_MAX (1/m), held while it slides, fading at TRIM_LEAK a second.
const TRIM_SPEED := 15.0
const TRIM_CURVATURE := 0.002
const TRIM_GAIN := 1.0
const TRIM_LEAK := 0.5
const TRIM_MAX := 0.015
## Pit road (D210): a car pitting slows on its line from this far before the entry (braking for
## the limit line at PIT_BRAKE, never past the line's own pace) and eases down to the paved edge
## over the last PIT_DROP_M; brakes for its box at PIT_BOX_BRAKE (m/s²); looks PIT_GAP_M (plus a
## metre a m/s) ahead for a car in its path.
const PIT_APPROACH_M := 450.0
const PIT_DROP_M := 160.0
const PIT_BRAKE := 3.5
const PIT_BOX_BRAKE := 3.5
const PIT_GAP_M := 14.0
## ...and follows a car ahead in its path this far back, s (a pack pits together).
const PIT_GAP_S := 0.5
## Pack racing (D213): following gap in the draft by skill (0 -> 100), s. With a free groove beside
## the car ahead in its groove, a car closes up to RUN_GAP_S behind it in the draft, then pulls out
## into that groove carrying the speed (a run): when it's held up there, or closing RUN_SPEED (m/s)
## or more. It gives the run up if it hasn't gained for RUN_DEAD_S before getting alongside, and
## sets up the next no sooner than RUN_RETRY_S (a few seconds more by chance). A run on a car
## within BLOCK_RANGE_M behind is blocked (by a car as likely to as it's skilled), once a while.
const PACK_GAP_S := Vector2(0.35, 0.2)
const RUN_GAP_S := 0.06
## Closing up for a run: this much faster than the car ahead a metre of gap still to close, 1/s.
const RUN_CLOSE := 0.4
const RUN_SPEED := 0.5
const RUN_DEAD_S := 1.5
const RUN_RETRY_S := Vector2(3.0, 8.0)
const BLOCK_RANGE_M := 20.0
const BLOCK_COOLDOWN_S := 5.0
## Mistakes in a pack (D229), by how far the skill is under MISTAKE_SKILL (none at it or over; the
## most at 0): a run coming from behind not seen until it's LATE_OVERLAP_M alongside, then moved
## over on (LATE_BLOCK, a chance per run); a run pulled out for without looking behind in that groove
## (CHOP, a chance per run set up); and the gap in the draft misjudged, tucking right up to the
## bumper and closing at up to SHORT_CLOSE m/s for SHORT_GAP_S (SHORT_GAP_RATE, a chance a second).
## A late block or a run pulled out for without looking leaves the cars behind unseen for
## MISTAKE_BLIND_S: it doesn't keep to its side of one alongside (they may still give way), and
## it moves over MISTAKE_LUNGE times as fast as it would.
const MISTAKE_SKILL := 0.9
const LATE_BLOCK := 0.3
const LATE_OVERLAP_M := 2.5
const CHOP := 0.2
const SHORT_GAP_RATE := 0.03
const SHORT_GAP_S := Vector2(2.0, 4.0)
const SHORT_CLOSE := 6.0
const MISTAKE_BLIND_S := 1.0
const MISTAKE_LUNGE := 1.8
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
## What the planner decided last ("line", "follow", "pass", "side", "defend", "yield", "start";
## in a pack "groove", "draft", "run", "back", "block").
var intent := "line"
## Racing in a pack (D213): the event's pack racing (the track suggests it, drafting is on).
var pack := false

var _line: RacingLine
var _profile := PackedFloat32Array()
var _caution_profile := PackedFloat32Array()
## With drafting (D208): how fast the corners and their braking allow, power aside; a car a tow
## has carried past its own pace keeps its foot down up to it. Empty without drafting.
var _ceiling := PackedFloat32Array()
## Driving pit road last tick (so the line's offset is picked up again after).
var _was_pitting := false
## In pit road, held at a stop by another car last tick (a queue, a gap to pull out into): waiting,
## not stuck.
var _pit_waiting := false
## The line's offset from the centre last tick, m.
var _line_was := 0.0
## Pack racing: the grooves (RacingLine.grooves()), the one the car is in (its _line), the car
## it's making a run on, how long the run has been losing ground, when it may block again.
var _grooves: Array = []
var _groove := 0
var _run: Racer
var _run_dead := 0.0
var _run_wait := 0.0
var _block_wait := 0.0
## Mistakes (D229): the run it hasn't seen coming yet, whether the next run is pulled out for
## without looking, and how much longer it's misjudging the gap.
var _late_block: Racer
var _chop := false
var _short_gap := 0.0
var _blind := 0.0
## Deceleration at full brake pedal, m/s² (before the tires' limit).
var _brake_full := 14.0
## What emergency braking counts on, m/s² (the brake balance's limit, with margin).
var _emergency_decel := 9.0
var _want := 0.0 # planned offset from the line
var _kappa_trim := 0.0 # curvature added to pure pursuit's, 1/m
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
	var event: RaceEvent = racer.session.get("event") if racer.session else null
	pack = event != null and event.pack and racer.session.get("draft") != null
	if pack:
		_grooves = _line.grooves()
		_groove = _nearest_groove(racer, racer.lateral)
		_line = _grooves[_groove]
		_run_wait = _rng.randf() * RUN_RETRY_S.y
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
	var power := racer.vehicle.power_cap # a restrictor plate (D226)
	_profile = _line.speed_profile(racer.vehicle.base_platform, grip, 1.0, true, power)
	_caution_profile = _line.speed_profile(racer.vehicle.base_platform, grip * CAUTION_GRIP, 1.0, true, power)
	var drafting := racer.session != null and racer.session.draft != null and DraftControl.drafts(racer.vehicle.base_platform)
	_ceiling = _line.ceiling(racer.vehicle.base_platform, grip) if drafting else PackedFloat32Array()


## The road's grip under the car (EnvDirector sets its conditions), in steps of 0.05 so the
## profiles (cached per grip) are made again only when the weather really changes.
func _check_road() -> void:
	if racer.vehicle == null or not is_instance_valid(racer.vehicle):
		return
	var c := racer.vehicle.sim.get_conditions()
	var road := VehicleSim.surface_grip(VehicleSim.SURFACE_ASPHALT, c.x, c.y)
	# Worn tires grip less too (D209).
	var wear := racer.session.wear.of(racer) if racer.session and racer.session.wear else null
	if wear:
		road *= wear.tire_grip()
	road = snappedf(road, 0.05)
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
	if racer.pit_hold: # in its box for service: on the handbrake, nothing else changes
		out.handbrake = 1.0
		return out
	var v := maxf(racer.speed, 0.0)
	if not as_guide and _pitting():
		_was_pitting = true
		if not _recover(out, delta):
			_pit_drive(vehicle, v, out)
		return out
	if _was_pitting:
		# Back on the road: the line from where the car is.
		_was_pitting = false
		_pit_waiting = false
		offset = racer.lateral - _line.offset_at(racer.distance)
		_want = offset
	_covered += v * delta
	_plan_time -= delta
	if _plan_time <= 0.0:
		_plan_time += 1.0 / PLAN_HZ
		_plan()
	var line_now := _line.offset_at(racer.distance)
	var step := OFFSET_RATE * delta * (MISTAKE_LUNGE if _blind > 0.0 else 1.0)
	var shift := line_now - _line_was
	if absf(shift) < 1.0 and signf(_want - offset) == -signf(shift):
		step += absf(shift)
	_line_was = line_now
	offset = move_toward(offset, _want, step)
	if not as_guide and _recover(out, delta):
		return out
	_steer(vehicle, v, out)
	_pedals(vehicle, v, out)
	return out


# --- pit road (D210) -----------------------------------------------------------------------


## In the pit lane, or heading for it to pit.
func _pitting() -> bool:
	var pit := racer.track.pit
	if pit == null:
		return false
	if racer.in_pit:
		return true
	if not racer.pit_plan:
		return false
	# Heading for the entry, or past it and still getting into the lane.
	return fposmod(pit.entry_m - racer.distance, racer.track.length) < PIT_APPROACH_M \
		or (pit.beside(racer.distance) and racer.pit_distance < pit.limit_in_m)


## Pit road: along the lane (its fast half, its box half near the box), the limit between the
## lines, a stop in the box when it's pitting, room to a car ahead; out at the line's pace.
func _pit_drive(vehicle: Vehicle, v: float, out: Dictionary) -> void:
	var pit := racer.track.pit
	var pits := racer.session.pits
	var t := racer.track
	var d := racer.pit_distance if pit.beside(racer.distance) else -fposmod(pit.entry_m - racer.distance, t.length)
	var stopping := racer.pit_plan and pits != null and pits.services() and String(pits.stop_of(racer).state) in ["track", "lane"]
	var box := pits.box_m(racer) if pits else -1.0
	var look := clampf(4.0 + 0.3 * v, 6.0, 22.0)
	# The fast half of the lane, into the box half only past the box before its own (and past the
	# car in it, if there is one).
	var lane := -pit.side * pit.width / 4.0
	if stopping and box - d < pit.box_m + 4.0:
		var before := box - pit.box_m
		var taken := false
		for other: Racer in racer.session.racers:
			taken = taken or (other != racer and other.in_pit and absf(other.pit_distance - before) < pit.box_m / 2.0 and absf(other.speed) < 3.0)
		if not taken or d > before + CAR_LENGTH + 0.5:
			lane = pit.side * pit.width / 4.0
	var just_out := pits != null and String(pits.stop_of(racer).state) == "leaving" and absf(box - d) < pit.box_m
	var at := d + look
	var target: Vector3
	if at < 0.0:
		# Still on the road: along the line, easing down to the paved edge for the mouth.
		var ahead := racer.distance + look
		var down := smoothstep(0.0, 1.0, 1.0 - (-at) / PIT_DROP_M)
		var edge := pit.side * (t.half_width(ahead, pit.side) + t.apron(t.index_at(ahead), pit.side) * 0.5)
		target = t.transform_at(ahead, lerpf(_line.offset_at(ahead), edge, down)).origin
	else:
		var aim := minf(at, pit.track.length)
		var room := maxf(pit.track.half_width(aim, 1.0) - 1.0, 0.0)
		target = pit.track.transform_at(aim, clampf(lane, -room, room)).origin
	out.steer = _pursue(vehicle, target, v)
	var want := RacingLine.MAX_SPEED
	if d < pit.limit_in_m:
		want = sqrt(pit.speed * pit.speed + 2.0 * PIT_BRAKE * maxf(pit.limit_in_m - d, 0.0))
		if d < 0.0:
			want = minf(want, _line.speed_at(_profile, racer.distance))
	elif d <= pit.limit_out_m:
		want = pit.speed * 0.98
	else:
		want = _line.speed_at(_profile, racer.distance)
	if stopping and box >= 0.0:
		var to_box := box - d
		want = minf(want, 0.0 if to_box < 1.0 else sqrt(2.0 * PIT_BOX_BRAKE * to_box))
	var free_want := want
	for other: Racer in racer.session.racers:
		if other == racer or other.vehicle == null:
			continue
		var rel := other.vehicle.global_position - vehicle.global_position
		# A car ahead in our path, on the way in (a pack pits together) or in this half of the lane
		# (one held in its box too): keep room behind it. In the lane "ahead" is along the lane, one
		# order for everyone in it (by heading, two cars angled at each other could each wait for
		# the other).
		var both_in := other.in_pit and racer.in_pit
		var ahead := other.pit_distance - d if both_in else rel.dot(vehicle.global_basis.z)
		# In the lane, in our path: where we are across it, or where we're going (a car moving into
		# the box half sees the one stopped there).
		var in_path := absf(other.pit_lateral - racer.pit_lateral) < CAR_WIDTH + 0.3 or absf(other.pit_lateral - lane) < CAR_WIDTH + 0.3 \
			if both_in else absf(rel.dot(vehicle.global_basis.x)) < CAR_WIDTH
		if ahead > 0.0 and rel.length() < PIT_GAP_M + v and in_path:
			_speed_cap = INF
			_follow(other, ahead - CAR_LENGTH, v, PIT_GAP_S)
			want = minf(want, _speed_cap)
		# Out of the box: not across a car coming up the fast half.
		if just_out and other.in_pit and not other.pit_hold and other.pit_distance < d and other.pit_distance > d - PIT_GAP_M * 1.5 and other.speed > 3.0:
			want = 0.0
	_pit_waiting = want < 1.0 and free_want >= 1.0
	var error := want - v
	if error < -0.3:
		out.brake = clampf(-error * 0.3, 0.0, 1.0)
		out.throttle = 0.0
	else:
		out.throttle = clampf(0.4 + error * 0.4, 0.0, 1.0)
		out.brake = 0.0
	if want <= 0.0 and v < 2.0:
		# Waiting (its box, a queue, a gap): on the handbrake, as _hold() does; the brake held at a
		# standstill selects reverse, and it backed into the car behind.
		out.brake = 0.0
		out.throttle = 0.0
		out.handbrake = 1.0


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
	var local_v := vehicle.global_basis.inverse() * vehicle.linear_velocity
	var dt := get_physics_process_delta_time()
	_kappa_trim *= 1.0 - TRIM_LEAK * dt
	if v > TRIM_SPEED and absf(_line.curvature_at(racer.distance)) > TRIM_CURVATURE \
			and absf(rad_to_deg(atan2(local_v.x, absf(local_v.z)))) < CATCH_SLIP_DEG + 1.0:
		var turning := vehicle.global_basis.y.dot(vehicle.angular_velocity) / v
		_kappa_trim = clampf(_kappa_trim + (kappa - turning) * TRIM_GAIN * dt, -TRIM_MAX, TRIM_MAX)
	var steer := -atan(wheelbase * (kappa + _kappa_trim)) / max_steer
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
	# Carried past its own pace by a tow: keep it, up to what the corners allow.
	if not _ceiling.is_empty() and profile == _profile and v > target - 1.0:
		target = maxf(target, minf(v + 2.0, _line.speed_at(_ceiling, here)))
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
	# The road as narrow as it gets in the next moment: no move to where it runs out.
	var corridor := _line.corridor_ahead(racer.distance, CAR_LENGTH + 10.0 + v * AHEAD_S)
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
	if pack:
		want_lat = line_here
	elif _covered < START_HOLD_M:
		want_lat = _start_lateral
		intent = "start"
	var me_lat := racer.lateral
	var field := racer.session.field
	var cars := field.around(racer, 60.0 + v * 2.0, LOOK_BEHIND_M)

	# Braking zone close ahead: no new passing moves unless already alongside.
	var braking_soon := _line.speed_at(_profile, racer.distance + 40.0 + v * 0.5) < v - 6.0
	var inside := signf(_upcoming_turn())

	# 1. The car ahead in our path: pass it if there's room, otherwise follow it; in a pack, the
	# grooves' way (D213).
	if pack:
		want_lat = _plan_pack(cars, v, s, formation)
	else:
		want_lat = _plan_lead(cars, v, want_lat, me_lat, gap_time, formation, braking_soon, inside)

	# 2. Cars alongside, or about to be in another lane: each keeps to its own side of the
	# midpoint between them, half the room each, so two cars moving at once can't meet.
	# Never steer across one. Squeezed with no room, the car further back gives way.
	var lo := corridor.y
	var hi := corridor.x
	var room := CAR_WIDTH + SIDE_GAP
	var squeeze_ahead: Racer = null
	for c: Dictionary in cars:
		var other: Racer = c.racer
		if _ignore(other) or (_blind > 0.0 and c.gap < 0.0): # a mistake: not looking behind (D229)
			continue
		var along := absf(c.gap)
		var overlap := along < CAR_LENGTH + 1.0
		var other_lane := absf(other.lateral - me_lat) > CAR_WIDTH * 0.75 and along < CAR_LENGTH + 3.0 + v * 0.15
		if not overlap and not other_lane:
			continue
		# (Further apart than that, the room from where it is: the midpoint would follow us away.)
		var mid := (me_lat + other.lateral) / 2.0
		if other.lateral >= me_lat:
			hi = minf(hi, maxf(mid - room / 2.0, other.lateral - room))
		else:
			lo = maxf(lo, minf(mid + room / 2.0, other.lateral + room))
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

	# 3. Cars behind: let lapping cars by; defend once per straight (in a pack, blocking runs is
	# the grooves' part).
	if absf(_line.curvature_at(racer.distance)) > 0.006:
		_defended = false
	for c: Dictionary in ([] as Array[Dictionary]) if pack else cars:
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
	_want = clampf(want_lat, corridor.y, corridor.x) - _line.offset_at(racer.distance) # a pack's groove may have changed


## Puts the car in groove `g` (where pack racing has it), or on the line it's on, from where it is
## now at full speed (a test placing it, a rejoin).
func resync(g := -1) -> void:
	if pack and g >= 0 and g < _grooves.size():
		_groove = g
		_line = _grooves[g]
		_make_profiles()
	_run = null
	_run_wait = 0.0
	_covered = START_HOLD_M
	offset = racer.lateral - _line.offset_at(racer.distance)
	_line_was = _line.offset_at(racer.distance)
	_want = offset


## The groove nearest `lateral` at `r`'s place.
func _nearest_groove(r: Racer, lateral: float) -> int:
	var best := 0
	for g in _grooves.size():
		if absf((_grooves[g] as RacingLine).offset_at(r.distance) - lateral) < absf((_grooves[best] as RacingLine).offset_at(r.distance) - lateral):
			best = g
	return best


## Into groove `g`: the car keeps its place across the road and moves over at OFFSET_RATE.
func _to_groove(g: int) -> void:
	if g == _groove or g < 0 or g >= _grooves.size():
		return
	var lat := _line.offset_at(racer.distance) + offset
	_groove = g
	_line = _grooves[g]
	_make_profiles()
	offset = lat - _line.offset_at(racer.distance)
	_line_was = _line.offset_at(racer.distance)


## The groove `r` is in: an AI's in a pack its own, anyone else's (one pitting too) the nearest.
func _groove_of(r: Racer) -> int:
	var ai := r.driver as RacingAI
	return ai._groove if ai and ai.pack and ai._grooves.size() == _grooves.size() and not r.pit_plan else _nearest_groove(r, r.lateral)


## A few seconds before setting up the next run.
func _retry() -> float:
	_chop = _rng.randf() < _blunder() * CHOP # the next run's
	return _rng.randf_range(RUN_RETRY_S.x, RUN_RETRY_S.y)


## How prone to mistakes in a pack (D229): 0 from MISTAKE_SKILL up, 1 at skill 0.
func _blunder() -> float:
	return clampf((MISTAKE_SKILL - _skill()) / MISTAKE_SKILL, 0.0, 1.0)


## True if `r` is in groove `g` where it is: within half a groove of its middle, or with `room`
## (a car's width and a little, for whether a groove is free) anywhere in it.
func _in_groove(r: Racer, g: int, room := RacingLine.GROOVE_M / 2.0) -> bool:
	return absf(r.lateral - (_grooves[g] as RacingLine).offset_at(r.distance)) < room


## True if groove `g` is free of cars from `behind` m behind to `ahead` m ahead (but `but`).
func _groove_free(g: int, cars: Array[Dictionary], behind: float, ahead: float, but: Racer = null) -> bool:
	if g < 0 or g >= _grooves.size():
		return false
	for c: Dictionary in cars:
		var r: Racer = c.racer
		if r == but or _ignore(r):
			continue
		if c.gap > -behind and c.gap < ahead and _in_groove(r, g, CAR_WIDTH + 0.3):
			return false
	return true


## Step 1 in a pack (D213). The car ahead in our groove: follow it close in the draft, or close up
## and make a run into a free groove beside it (the middle one first), back out if the run dies
## before we're alongside. A run on us from behind: move over in front of it (blocking) if
## that groove is free beside us. Returns where to be across the road: our groove.
func _plan_pack(cars: Array[Dictionary], v: float, s: float, formation: bool) -> float:
	var dt := 1.0 / PLAN_HZ
	_block_wait = maxf(_block_wait - dt, 0.0)
	_run_wait = maxf(_run_wait - dt, 0.0)
	_short_gap = maxf(_short_gap - dt, 0.0)
	_blind = maxf(_blind - dt, 0.0)
	if _short_gap <= 0.0 and _rng.randf() < _blunder() * SHORT_GAP_RATE * dt:
		_short_gap = _rng.randf_range(SHORT_GAP_S.x, SHORT_GAP_S.y)
	if _late_block and (not is_instance_valid(_late_block) or _ignore(_late_block) or field_gap(_late_block) >= 0.0 \
			or field_gap(_late_block) < -BLOCK_RANGE_M * 2.0):
		_late_block = null
	intent = "groove"
	if _run and (not is_instance_valid(_run) or _ignore(_run)):
		_run = null
	if _run and _in_groove(_run, _groove):
		_run = null # it moved in front of us (a block): not round it again while it's moving
		_run_wait = _retry()
	if _run:
		var gap := field_gap(_run)
		if gap < -CAR_LENGTH - 1.0:
			_run = null # past it
			_run_wait = _retry()
		else:
			intent = "run"
			# Not gaining on it, and not alongside yet: the run's dying.
			_run_dead = _run_dead + dt if v < maxf(_run.speed, 0.0) + 0.1 and gap > CAR_LENGTH * 0.5 else 0.0
			var back := _nearest_groove(_run, _run.lateral)
			if _run_dead > RUN_DEAD_S and _groove_free(back, cars, CAR_LENGTH + 6.0, gap - 1.0, _run):
				_to_groove(back) # back in behind it
				_run = null
				_run_wait = _retry()
				intent = "back"
	if not _run:
		var lead: Dictionary = {}
		for c: Dictionary in cars:
			if c.gap > 0.0 and not _ignore(c.racer) and (_groove_of(c.racer) == _groove or _in_groove(c.racer, _groove, CAR_WIDTH)):
				lead = c
				break
		if not lead.is_empty():
			var other: Racer = lead.racer
			var bumper: float = lead.gap - CAR_LENGTH
			var closing := v - maxf(other.speed, 0.0)
			# A free groove beside it (the middle one first): close up in its draft for a run.
			var side := -1
			if not formation and _run_wait <= 0.0:
				var middle := _grooves.size() / 2
				var sides := [_groove - 1, _groove + 1]
				sides.sort_custom(func(a: int, b: int) -> bool: return absf(a - middle) < absf(b - middle))
				for g: int in sides:
					if _groove_free(g, cars, 0.0 if _chop else CAR_LENGTH + 6.0, lead.gap + CAR_LENGTH + 15.0, other):
						side = g
						break
			# Misjudging the gap (D229): right up to its bumper.
			var gap_s := RUN_GAP_S if side >= 0 else lerpf(PACK_GAP_S.x, PACK_GAP_S.y, s)
			if _short_gap > 0.0:
				gap_s = -2.0 / maxf(v, 1.0)
			_follow(other, bumper, v, gap_s)
			if side >= 0 or _short_gap > 0.0: # closing up in its draft: faster than a safe follow would
				_speed_cap = maxf(_speed_cap, maxf(other.speed, 0.0) + clampf((bumper - 2.0 - v * gap_s) * RUN_CLOSE, 0.0,
					SHORT_CLOSE if _short_gap > 0.0 else 4.0))
			# Close behind it and held up (or still closing): pull out.
			var held := _speed_cap < maxf(v, _line.speed_at(_profile, racer.distance)) + 0.5
			if side >= 0 and bumper < 2.0 + v * RUN_GAP_S + 4.0 and (closing > RUN_SPEED or held):
				_to_groove(side)
				if _chop:
					_blind = MISTAKE_BLIND_S
				_run = other
				_run_dead = 0.0
				_speed_cap = INF # out of its way now
				intent = "run"
			else:
				intent = "draft"
	# A run on us from behind, in a groove beside ours: into it, in front of them. One not seen
	# coming (D229) is moved over on once it's alongside.
	if not _run and not formation and _block_wait <= 0.0:
		for c: Dictionary in cars:
			var other: Racer = c.racer
			var behind: float = -c.gap - CAR_LENGTH
			var late := other == _late_block
			if c.gap >= 0.0 or _ignore(other) or behind > BLOCK_RANGE_M or other.speed < v + RUN_SPEED or (behind < 8.0 if not late else behind > -LATE_OVERLAP_M):
				continue
			for g: int in [_groove - 1, _groove + 1]:
				if g >= 0 and g < _grooves.size() and _in_groove(other, g) and not _in_groove(other, _groove) \
						and _groove_free(g, cars, 0.0, CAR_LENGTH + 8.0, other):
					if late:
						_late_block = null
						_block_wait = BLOCK_COOLDOWN_S
						_blind = MISTAKE_BLIND_S
						_to_groove(g)
						intent = "block"
					elif _rng.randf() < _blunder() * LATE_BLOCK:
						_late_block = other # not seen yet
					else:
						_block_wait = BLOCK_COOLDOWN_S
						if _rng.randf() < s:
							_to_groove(g)
							intent = "block"
					break
			if intent == "block" or _block_wait > 0.0:
				break
	return _line.offset_at(racer.distance)


## Step 1 of the plan: the car ahead in our path. Passes it on a side with room, or follows it.
## Returns where to be across the road.
func _plan_lead(cars: Array[Dictionary], v: float, want_lat: float, me_lat: float, gap_time: float, formation: bool, braking_soon: bool,
		inside: float) -> float:
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
	return want_lat


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
	var corridor := _line.corridor_ahead(other.distance, CAR_LENGTH + 20.0)
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
	var off := absf(racer.lateral) > racer.track.half_width(racer.distance, racer.lateral) + racer.track.apron(racer.track_index, racer.lateral) + 4.0 \
		and not racer.in_pit
	var backwards := heading < -0.2 and v > 3.0
	if not upright or off or backwards:
		_trouble_time += delta
	else:
		_trouble_time = maxf(_trouble_time - delta * 2.0, 0.0)
	if v < 1.0 and not racer.held and not racer.pit_hold and (_speed_cap > 1.0 or stuck_behind or (racer.in_pit and not _pit_waiting)):
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
