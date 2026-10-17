class_name KartAI
extends RacingAI
## The kart AI (D143, AI-02): the racing AI on a kart, with the kart's own grip in its speeds,
## drifting through tight corners (a deeper tier at higher skill), round loops on the loop's own
## line, to an item box when it has nothing, around Oil Slicks, and using items (ItemPolicy). Same
## physics as players (AI-05).

## Drifts into corners that take this much grip at its speed (in g), at this speed or more, and
## no more than a drift holds (the tires' 0.4 g plus the drift's most, with a margin): tighter, it
## brakes first.
const DRIFT_G := 0.9
const DRIFT_MAX_G := 1.3
const DRIFT_SPEED := 12.0
## Lets go once the corner opens past this radius, or the kart is this far off its line.
const DRIFT_END_RADIUS := 70.0
const DRIFT_OFF_M := 1.8
const DRIFT_STEER_GAIN := 0.3 # tightness per metre off the line
## How far ahead (s at its speed) the corner's tightest part is looked for.
const DRIFT_LOOK_S := 1.2
const DRIFT_THROTTLE := 0.7
const DRIFT_BRAKE := 0.25
const NEAR_PIECE_M := 15.0
const BOX_LOOK_M := 70.0
## Just out of a drift the kart is still settling: no hard braking unless the line needs it.
const AFTER_DRIFT_S := 0.6
const AFTER_DRIFT_BRAKE := 0.3
const HARD_BRAKE := 0.6
const SLICK_LOOK_M := 35.0
const SLICK_CLEAR_M := 2.6

## Steered by a loop's lanes, not the racing line, this far before it and this long after.
const LOOP_APPROACH_M := 35.0
const LOOP_EXIT_S := 1.0
## Stuck in a loop (too slow to get round, or the wrong way): towed out after this long; and
## nobody takes longer than LOOP_MAX_S to get round one.
const LOOP_STUCK_S := 2.0
const LOOP_STUCK_SPEED := 4.0
const LOOP_MAX_S := 5.0

var items := ItemPolicy.new()
var _drift_dir := 0
var _corner_seen := false
var _loop_exit := 0.0
var _last_loop := {}
var _since_drift := INF
var _loop_stuck := 0.0
var _loop_time := 0.0


func _ready() -> void:
	super()
	# Stuck, a kart backs out sooner and calls the tow sooner (towing costs little, D132).
	stuck_reverse_s = 1.5
	stuck_reset_s = 4.0
	stuck_behind = true
	items.racer = racer
	items.skill = skill
	items.rng.seed = hash(racer.number) ^ 0x17e5


## A kart's grip is the arcade layer's on top (D130).
func _base_grip() -> float:
	var arcade: Dictionary = racer.vehicle.arcade
	return super() * (float(arcade.grip) if not arcade.is_empty() else 1.0)


## The deepest drift tier it waits for: 1 below skill 40, 2 from 40, 3 from 75.
func target_tier() -> int:
	return 1 if skill < 40.0 else (2 if skill < 75.0 else 3)


func _physics_process(delta: float) -> void:
	if as_guide:
		return
	var vehicle := racer.vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var kart := racer.session.kart
	_since_drift += delta
	var loop := racer.track.kart.loop_progress(racer.com()) if racer.track.kart else {}
	var near := racer.track.kart.loop_near(racer.distance, LOOP_APPROACH_M) if racer.track.kart and loop.is_empty() else {}
	_loop_exit = maxf(0.0, _loop_exit - delta)
	if not loop.is_empty():
		_round_loop(vehicle, loop)
		_last_loop = loop.piece
		_loop_exit = LOOP_EXIT_S
		_loop_stuck = _loop_stuck + delta if racer.speed < LOOP_STUCK_SPEED else 0.0
		_loop_time += delta
		if _loop_stuck > LOOP_STUCK_S or _loop_time > LOOP_MAX_S:
			_loop_stuck = 0.0
			_loop_time = 0.0
			racer.reset_car()
	else:
		_loop_time = 0.0
		var c := controls(delta)
		if c.is_empty():
			return
		vehicle.steer = c.steer
		vehicle.throttle = c.throttle
		vehicle.brake = c.brake if _since_drift > AFTER_DRIFT_S or c.brake > HARD_BRAKE else minf(c.brake, AFTER_DRIFT_BRAKE)
		vehicle.handbrake = 0.0
		if not near.is_empty() or _loop_exit > 0.0:
			# Into a loop down its entry lane, out of it down its exit lane (D137).
			var piece: Dictionary = near if not near.is_empty() else _last_loop
			var lanes := racer.track.kart.loop_lanes(piece)
			var lane := lanes.x if not near.is_empty() else lanes.y
			_end_drift(vehicle)
			_aim(vehicle, racer.track.transform_at(racer.distance + clampf(5.0 + 0.3 * racer.speed, 6.0, 14.0), lane).origin)
			vehicle.throttle = maxf(vehicle.throttle, 0.8) if not near.is_empty() else vehicle.throttle
		else:
			_drift(vehicle, c)
	if kart and not racer.held and not racer.finished:
		var back: Variant = items.think(delta)
		if back != null:
			kart.use(racer, bool(back))


## Round a loop: full throttle, aimed a little further round its own ribbon.
func _round_loop(vehicle: Vehicle, loop: Dictionary) -> void:
	_end_drift(vehicle)
	_aim(vehicle, racer.track.kart.loop_point(loop.piece, minf(float(loop.t) + 0.04, 1.0)))
	vehicle.throttle = 1.0
	vehicle.brake = 0.0


## Steers at `target` (pure pursuit in the kart's own frame, which also works upside down).
func _aim(vehicle: Vehicle, target: Vector3) -> void:
	vehicle.steer = _pursue(vehicle, target, maxf(racer.speed, 0.0))


## Drifts tight corners (D131): in with the steering the corner's way, the tightness from the
## line's curvature (the tires add about 0.4 g), corrected for how far off the line it's sliding;
## out once the corner opens, with the tier it waited for if it got there.
func _drift(vehicle: Vehicle, c: Dictionary) -> void:
	var v := maxf(racer.speed, 0.0)
	var ahead := racer.distance + v * 0.3
	var kappa := _line.curvature_at(ahead) # + = left
	var flags := vehicle.kart_flags()
	var tier := (flags >> VehicleSim.KART_FLAG_TIER_SHIFT) & 3
	var locked := flags & (VehicleSim.KART_FLAG_DRIFT_LEFT | VehicleSim.KART_FLAG_DRIFT_RIGHT) != 0
	var want_lat := _line.offset_at(racer.distance) + offset
	var off := racer.lateral - want_lat # + = left of its line
	if _drift_dir == 0:
		var need := v * v * _peak_curvature(racer.distance, v * DRIFT_LOOK_S) / 9.81
		if skill >= 20.0 and v >= DRIFT_SPEED and need > DRIFT_G and need < DRIFT_MAX_G and c.brake < 0.3 and not _near_piece() and not racer.towed:
			_drift_dir = -1 if kappa > 0.0 else 1 # turning left: drift left (steer -)
			_corner_seen = true
		else:
			vehicle.drift = false
			return
	var opening := absf(_line.curvature_at(racer.distance + v * 0.2)) < 1.0 / DRIFT_END_RADIUS
	if (opening and (tier >= target_tier() or tier >= 1)) or (opening and not locked) or absf(off) > DRIFT_OFF_M or v < DRIFT_SPEED * 0.75 or c.brake > 0.6:
		_end_drift(vehicle)
		return
	vehicle.drift = true
	if not locked:
		vehicle.steer = 0.6 * _drift_dir # into it, past the lock-in threshold
		return
	var a := v * v * absf(kappa) / 9.81
	var turn: Array = vehicle.arcade.drift.turn_g
	var tight := clampf((a - 0.4 - float(turn[0])) / (float(turn[1]) - float(turn[0])) + DRIFT_STEER_GAIN * off * _drift_dir, 0.0, 1.0)
	vehicle.steer = _drift_dir * (2.0 * tight - 1.0)
	# The line's pace through the corner: on the power unless it wants the kart slower, then off
	# it and a touch of brake (more would spin it).
	vehicle.throttle = 0.0 if c.brake > 0.05 else maxf(float(c.throttle), DRIFT_THROTTLE)
	vehicle.brake = minf(float(c.brake), DRIFT_BRAKE)


## The tightest |curvature| of the line from `from` over the next `span` m.
func _peak_curvature(from: float, span: float) -> float:
	var peak := 0.0
	var d := 0.0
	while d <= span:
		peak = maxf(peak, absf(_line.curvature_at(from + d)))
		d += 2.0
	return peak


func _end_drift(vehicle: Vehicle) -> void:
	if _drift_dir != 0:
		_since_drift = 0.0
	_drift_dir = 0
	vehicle.drift = false


## Karts up in a loop or under the tow drone aren't on the road to follow or pass.
func _ignore(other: Racer) -> bool:
	if other.towed:
		return true
	if racer.track.kart and not racer.track.kart.loop_progress(other.com()).is_empty():
		return true
	return super(other)


func _near_piece() -> bool:
	var k := racer.track.kart
	if k == null:
		return false
	for p in k.pieces:
		if p.has("at_m") and p.kind in ["jump", "loop", "boost_pad"]:
			var d := fposmod(float(p.at_m) - racer.distance + racer.track.length / 2.0, racer.track.length) - racer.track.length / 2.0
			if d > -NEAR_PIECE_M and d < NEAR_PIECE_M + maxf(racer.speed, 0.0) * 1.5:
				return true
	return false


## The racing AI's plan, then: to an item box with nothing held, around a Slick ahead.
func _plan() -> void:
	super()
	var kart := racer.session.kart
	if kart == null or racer.track.arena:
		return
	var corridor := _line.corridor(racer.distance)
	var line_here := _line.offset_at(racer.distance)
	# Into a loop only from its entry lane: no passing, no boxes, nothing else (D137).
	var loop := racer.track.kart.loop_near(racer.distance) if racer.track.kart else {}
	if not loop.is_empty():
		_want = racer.track.kart.loop_lanes(loop).x - line_here
		_passing = null
		return
	if kart.items.item_of(racer) == "" and kart.items.slot(racer).item == "" and _passing == null:
		var best := INF
		var lat := NAN
		var boxes := kart.boxes
		for i in mini(boxes.count(), boxes.along.size()):
			if not boxes.alive[i]:
				continue
			var d := fposmod(boxes.along[i] - racer.distance, racer.track.length)
			if d < BOX_LOOK_M and d > 4.0 and d < best:
				best = d
				lat = boxes.across[i]
		if not is_nan(lat):
			_want = clampf(lat - line_here, corridor.y - line_here, corridor.x - line_here)
	for e: Dictionary in kart.entities.list.values():
		if e.kind != "oil_slick" or not e.has("road_s"):
			continue # (still flying)
		var d := fposmod(float(e.road_s) - racer.distance, racer.track.length)
		var slick_lat := float(e.road_lat)
		var mine := line_here + _want
		if d < SLICK_LOOK_M and absf(slick_lat - mine) < SLICK_CLEAR_M:
			var side := 1.0 if slick_lat <= mine else -1.0
			_want = clampf(slick_lat + side * SLICK_CLEAR_M - line_here, corridor.y - line_here, corridor.x - line_here)
