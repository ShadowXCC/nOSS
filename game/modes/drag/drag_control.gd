class_name DragControl
extends Node
## Drag passes (D168-D173): the burnout, the staging, the tree, the shifts timed against a fake
## tachometer, the gimmicks and the ladder. Two cars run a pass; the rest are parked out of play
## until their turn (D170).
##
## The needle is the mode's own, not the engine's (D169): it sweeps every gear at one fixed rate
## for every car, class and model, so nobody can time their shifts better by what they brought.
## The real gearbox still shifts and still loses drive out of its band — a perfect shift adds a
## surge on top, a missed one bogs.
##
## The authority decides (offline: this game); RaceControl runs the session and the results. It
## is given no lights of its own for a drag session: the tree here is the countdown.

signal pass_started(cars: Array)
signal pass_ended(won: Racer)
## grade: "perfect", "good" or "miss".
signal shift_graded(r: Racer, grade: String, gear: int)
signal fouled(r: Racer, why: String)
signal run_finished(r: Racer, et: float, trap: float)
signal boost_used(r: Racer)
signal engine_blown(r: Racer)
## A tire-shake QTE opened or closed for this car.
signal shake_changed(r: Racer, on: bool)

## What the pass is up to. The tree is the countdown, so RaceControl's lights stay dark.
enum Phase { IDLE, BURNOUT, STAGE, TREE, RUN, SETTLE }

## HUD elements a drag pass never shows: no laps, no sectors, no places, no racing line.
const HUD_HIDDEN := ["timing", "delta", "position", "standings", "flags"]

## The fake tachometer: how long the needle takes to sweep a gear, where it lands after a shift,
## and how far past the end it may go (past 1.0 is over-revving).
const SWEEP_S := 2.2
const NEEDLE_AFTER_SHIFT := 0.14
const NEEDLE_MAX := 1.35
## The shift window per gear, [centre, width]: later gears are later and tighter. Past the end of
## the table the last row stands.
const WINDOWS := [[0.72, 0.17], [0.74, 0.15], [0.76, 0.13], [0.78, 0.12], [0.80, 0.11], [0.82, 0.10]]
## A perfect shift is within half a window of its centre; a good one within a whole window.
## A perfect one surges, a missed one bogs.
const SURGE_S := 0.9
const SURGE_ACCEL := 3.2
const BOG_S := 0.45
const BOG_THROTTLE := 0.25
## The chain: each perfect shift in a row adds this to the surge, up to this many.
const CHAIN_MAX := 4
const CHAIN_STEP := 0.14
## Over-revving: seconds past the needle's end to a blown engine, and the power lost on the way.
const STRAIN_S := 3.5
const STRAIN_POWER := 0.45
## One boost charge: a surge of this long, this strong.
const BOOST_S := 1.2
const BOOST_ACCEL := 5.2
## The two-step: the rev band to hold on the line, and what missing it costs at the launch.
const TWO_STEP_BAND := Vector2(0.55, 0.85)
const LAUNCH_ASSIST_ACCEL := 2.4
const LAUNCH_S := 1.2
## The burnout: how long the box is open, the heat that pays best, and where it turns against you.
const BURNOUT_S := 5.0
const HEAT_BEST_S := 2.0
const HEAT_MAX_S := 4.2
## Staging before the tree starts, then an amber every this long, three of them.
const STAGE_S := 2.0
const AMBERS := 3
const AMBER_S := 0.5
## Tire shake: the slip that starts it, how long there is to save it, and what missing it costs.
const SHAKE_SLIP := 0.34
const SHAKE_WINDOW_S := 0.45
const SHAKE_FROM_S := 1.6
const SHAKE_COST_S := 1.0
const SHAKE_COST_THROTTLE := 0.45
## A car this slow for this long, with the line not crossed, has finished nothing.
const DEAD_SPEED := 2.0
const DEAD_S := 3.0
## After the last car resolves, this long to roll out before the next pass.
const SETTLE_S := 3.0
## Where cars wait their turn.
const PARK_Y := -600.0

var session: TrackSession
var layout: DragLayout
var builder: DragBuilder
var ladder := DragLadder.new()
var sounds: DragSounds
var authority := true
## The ladder's draw seed (0: drawn freshly). Dev and tests set it so a match repeats.
var drag_seed := 0
var ended := false
## What the pass is up to, and how long it has been there.
var phase := Phase.IDLE
var phase_time := 0.0
## The cars in the pass now, lane 0 first.
var cars: Array[Racer] = []

## racer -> this pass's state (_blank_run).
var _run := {}
## Ambers already lit this tree, so each one is heard once.
var _ambers_lit := 0
## racer -> the best numbers it has set in the match: {reaction, et, trap}.
var _best := {}
## Passes run, for the soak check.
var passes_run := 0


func _ready() -> void:
	# After the player's controls and the bots (-50), before the vehicles: this reads what they
	# wrote this tick and changes it (a bog, a surge, a blown engine).
	process_physics_priority = -45
	session.race.session_started.connect(func(_kind: String) -> void: reset())


## A new match: the field drawn again, every car back out of play, the first pass about to set up.
func reset() -> void:
	ended = false
	phase = Phase.IDLE
	phase_time = 0.0
	cars = []
	passes_run = 0
	_run.clear()
	_best.clear()
	if builder:
		builder.reset_tree()
	for r in session.racers:
		r.out = false
		r.finished = false
	if authority:
		ladder.seed_field(session.racers, drag_seed)


## Cars still in the ladder.
func standing() -> Array[Racer]:
	return session.racers.filter(func(r: Racer) -> bool: return not ladder.out_in.has(r))


## The order now (RaceControl's standings down a strip): the ladder's.
func standings() -> Array[Racer]:
	return ladder.standings(session.racers)


## The drag columns for `r`'s results row.
func row(r: Racer) -> Dictionary:
	var best: Dictionary = _best.get(r, {})
	return {
		"reaction": float(best.get("reaction", -1.0)),
		"et": float(best.get("et", -1.0)),
		"trap": float(best.get("trap", -1.0)),
		"round": ladder.round_of(r),
	}


## "Round 2/3 · Stage", for the HUD's session line.
func session_text() -> String:
	if ended:
		return "Done"
	var what := String({ Phase.IDLE: "", Phase.BURNOUT: "Burnout", Phase.STAGE: "Stage",
		Phase.TREE: "Tree", Phase.RUN: "Pass", Phase.SETTLE: "" }.get(phase, ""))
	var round_name := ladder.round_text()
	return "%s · %s" % [round_name, what] if what else round_name


## This car's pass state, or {} if it is not in the pass.
func run_of(r: Racer) -> Dictionary:
	return _run.get(r, {})


## Where the needle stands for `r`, 0..NEEDLE_MAX (the HUD's tach). Before the green it is the
## two-step's rev instead, which is the same dial doing the other job.
func needle(r: Racer) -> float:
	var s: Dictionary = _run.get(r, {})
	if s.is_empty():
		return 0.0
	return float(s.rev) if phase in [Phase.STAGE, Phase.TREE] else float(s.needle)


## The window to shift in for `r` now: [centre, width], or [] when timing is off.
func window(r: Racer) -> Array:
	if not session.event.drag_timing:
		return []
	var s: Dictionary = _run.get(r, {})
	if s.is_empty() or r.vehicle == null or not is_instance_valid(r.vehicle):
		return []
	if phase in [Phase.STAGE, Phase.TREE]:
		return [] if not session.event.drag_two_step else [(TWO_STEP_BAND.x + TWO_STEP_BAND.y) * 0.5, TWO_STEP_BAND.y - TWO_STEP_BAND.x]
	var gear := maxi(r.vehicle.sim.get_gear(), 1)
	var row: Array = WINDOWS[mini(gear - 1, WINDOWS.size() - 1)]
	return row.duplicate()


## A driver leaving the line. Before the green that is a red light (D169).
func launch(r: Racer) -> void:
	var s: Dictionary = _run.get(r, {})
	if s.is_empty() or bool(s.launched):
		return
	s.launched = true
	if phase == Phase.TREE or phase in [Phase.BURNOUT, Phase.STAGE]:
		if session.event.drag_tree:
			_foul(r, "red")
		return
	if phase == Phase.RUN and float(s.reaction) < 0.0 and session.event.drag_tree:
		s.reaction = phase_time


## Spends one boost charge: a surge forward for about a second. Nothing without a charge left,
## outside a running pass, or on a blown engine.
func use_boost(r: Racer) -> bool:
	var s: Dictionary = _run.get(r, {})
	if s.is_empty() or phase != Phase.RUN or int(s.boosts) <= 0 or bool(s.blown) or bool(s.done):
		return false
	s.boosts = int(s.boosts) - 1
	s.boost = BOOST_S
	boost_used.emit(r)
	r.notify("Boost", 1.2)
	return true


## A bot's rev level on the line, 0..1 (a player's comes from their own throttle).
func rev(r: Racer, value: float) -> void:
	var s: Dictionary = _run.get(r, {})
	if not s.is_empty():
		s.rev = clampf(value, 0.0, 1.0)


## What `r` has to let go of to launch: "clutch" if they have one, else "brake"; with the
## two-step off it is simply the throttle. DragPrompts turns this into words per device.
func launch_action(r: Racer) -> String:
	if not session.event.drag_two_step or not session.event.drag_qtes:
		return "throttle"
	var input := _input_of(r)
	if input and (input.wheel.has_clutch() or input.has_binding("clutch")):
		return "clutch"
	return "brake"


## A reset mid-pass: back in its lane where it last was, and the pass is lost (nothing is towed
## back down a strip). Between passes it is simply set down again.
func recover(r: Racer) -> void:
	if r.vehicle == null or not is_instance_valid(r.vehicle) or r.vehicle.remote:
		return
	var lane := int(_run.get(r, {}).get("lane", 0))
	var at := r.last_valid_xform
	if layout.off_deck(at.origin):
		at = layout.spawn_of(lane)
	r.vehicle.reset_to(at)
	r.ghost_for(1.0)
	if phase == Phase.RUN and _run.has(r) and not bool(_run[r].done):
		_foul(r, "reset")


func _physics_process(delta: float) -> void:
	_forget_gone()
	if ended or session.race.phase != RaceControl.Phase.RUNNING:
		return
	phase_time += delta
	match phase:
		Phase.IDLE:
			_begin_pass()
		Phase.BURNOUT:
			_tick_burnout(delta)
		Phase.STAGE:
			_tick_stage(delta)
		Phase.TREE:
			_tick_tree(delta)
		Phase.RUN:
			_tick_run(delta)
		Phase.SETTLE:
			if phase_time >= SETTLE_S:
				_end_pass()


## Cars that left the game drop out of the tables (they keep the results they were in).
func _forget_gone() -> void:
	cars.assign(cars.filter(func(r: Variant) -> bool: return is_instance_valid(r)))
	for d: Dictionary in [_run, _best]:
		for k: Variant in d.keys():
			if not is_instance_valid(k):
				d.erase(k)


## The next pair up, parked cars put away and the pass's cars on the line.
func _begin_pass() -> void:
	if not authority:
		return
	var pair := ladder.current()
	if pair.is_empty():
		_finish_match()
		return
	cars = pair
	for r in session.racers:
		if r in cars:
			continue
		_park(r)
	for i in cars.size():
		var r := cars[i]
		_run[r] = _blank_run(i)
		_unpark(r)
	var burnout: bool = session.event.drag_burnout and session.event.drag_qtes
	_place(burnout)
	_to(Phase.BURNOUT if burnout else Phase.STAGE)
	if not burnout:
		_hold(true)
	pass_started.emit(cars.duplicate())
	for r in cars:
		r.notify("Burnout" if burnout else "Stage", 2.0)


func _blank_run(lane: int) -> Dictionary:
	return {
		"lane": lane, "rev": 0.0, "needle": 0.0, "chain": 0, "strain": 0.0, "blown": false,
		"boosts": clampi(int(session.event.drag_boost), 0, 3), "boost": 0.0, "surge": 0.0,
		"bog": 0.0, "launched": false, "reaction": -1.0, "et": -1.0, "crossed": -1.0, "trap": -1.0,
		"foul": "", "done": false, "heat": 0.0, "grip": 0.0, "shake": 0.0, "shook": false,
		"shifting": false, "dead": 0.0, "launch_held": false, "furthest": 0.0, "foul_at": 0.0,
		"shake_done": false,
	}


## Both cars in their lanes, at the water box or on the line.
func _place(at_burnout: bool) -> void:
	for r in cars:
		if r.vehicle == null or not is_instance_valid(r.vehicle) or r.vehicle.remote:
			continue
		var lane := int(_run[r].lane)
		var at := layout.burnout_of(lane) if at_burnout else layout.spawn_of(lane)
		at.origin.y += 0.05
		r.spawn_at = at
		r.last_valid_xform = at
		r.vehicle.reset_to(at)
		# A staged car is in first. VehicleModel.reset only forces a gear when it was in reverse,
		# so without this a car that finished the last pass in top gear would launch in it.
		r.vehicle.sim.select_gear(1)
		r.set_ghost(session.ghosted)


## Holds the cars on the line (or lets them go). A held car's throttle is cut, so the two-step's
## revs are read from the driver's input, never from the engine.
func _hold(on: bool) -> void:
	for r in cars:
		r.held = on


func _to(next: int) -> void:
	phase = next
	phase_time = 0.0


## Out of play until its turn: hidden, frozen, below the strip (PoliceRacer.stand_down).
func _park(r: Racer) -> void:
	if r.parked:
		return
	r.parked = true
	r.waiting = true
	r.held = true
	if r.vehicle and is_instance_valid(r.vehicle) and not r.vehicle.remote:
		r.vehicle.visible = false
		r.vehicle.set_ghost(true, false)
		r.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, PARK_Y - r.number * 10.0, 0.0)))
		r.vehicle.freeze = true


func _unpark(r: Racer) -> void:
	r.parked = false
	r.waiting = false
	if r.vehicle and is_instance_valid(r.vehicle) and not r.vehicle.remote:
		r.vehicle.freeze = false
		r.vehicle.visible = true


## The water box: throttle against the brake heats the tires. The best heat pays a little grip
## at the launch; cooking them past that pays it back (D172).
func _tick_burnout(delta: float) -> void:
	for r in cars:
		var s: Dictionary = _run[r]
		if r.vehicle == null or not is_instance_valid(r.vehicle):
			continue
		if r.vehicle.throttle > 0.6 and r.vehicle.brake > 0.4:
			s.heat = float(s.heat) + delta
	if phase_time < BURNOUT_S:
		return
	for r in cars:
		var s: Dictionary = _run[r]
		s.grip = _heat_grip(float(s.heat))
	_place(false)
	_hold(true)
	_to(Phase.STAGE)
	for r in cars:
		r.notify("Stage", 1.5)


## Grip from a burnout, -1..1: best at HEAT_BEST_S, nothing cold, against you past HEAT_MAX_S.
static func _heat_grip(heat: float) -> float:
	if heat <= 0.0:
		return 0.0
	if heat <= HEAT_BEST_S:
		return heat / HEAT_BEST_S
	if heat <= HEAT_MAX_S:
		return 1.0 - (heat - HEAT_BEST_S) / (HEAT_MAX_S - HEAT_BEST_S)
	return -clampf((heat - HEAT_MAX_S) / HEAT_MAX_S, 0.0, 1.0)


## On the line: the pre-stage and stage bulbs, then the tree starts.
func _tick_stage(delta: float) -> void:
	_read_drivers(delta)
	if builder:
		for r in cars:
			var lane := int(_run[r].lane)
			builder.set_bulb(lane, DragBuilder.Bulb.PRE_STAGE, true)
			builder.set_bulb(lane, DragBuilder.Bulb.STAGE, phase_time > STAGE_S * 0.5)
	if phase_time >= STAGE_S:
		_ambers_lit = 0
		_to(Phase.TREE)


## The tree: three ambers, then green. Leaving before it is a red light.
func _tick_tree(delta: float) -> void:
	_read_drivers(delta)
	var lit := mini(int(phase_time / AMBER_S), AMBERS)
	if lit > _ambers_lit:
		_ambers_lit = lit
		if sounds and not cars.is_empty() and cars[0].vehicle:
			sounds.bulb(cars[0].vehicle.global_position)
	if builder:
		for r in cars:
			var lane := int(_run[r].lane)
			for i in AMBERS:
				builder.set_bulb(lane, DragBuilder.Bulb.AMBER_1 + i, i < lit)
	if phase_time >= AMBERS * AMBER_S:
		_green()


func _green() -> void:
	_to(Phase.RUN)
	if sounds and not cars.is_empty() and cars[0].vehicle and is_instance_valid(cars[0].vehicle):
		sounds.bulb(cars[0].vehicle.global_position, true)
	_hold(false)
	if builder:
		for r in cars:
			var s: Dictionary = _run[r]
			var lane := int(s.lane)
			for i in AMBERS:
				builder.set_bulb(lane, DragBuilder.Bulb.AMBER_1 + i, false)
			var red := String(s.foul) == "red"
			builder.set_bulb(lane, DragBuilder.Bulb.GREEN, not red)
			builder.set_bulb(lane, DragBuilder.Bulb.RED, red)
	for r in cars:
		# Holding the throttle against a two-step is not leaving the line: the reaction is timed
		# from the green to the moment the launch input is let go (_read_drivers).
		r.notify("Go", 1.0)


## Down the strip: the needle, the shifts, the gimmicks and the line.
func _tick_run(delta: float) -> void:
	_read_drivers(delta)
	for r in cars:
		var s: Dictionary = _run[r]
		if r.vehicle == null or not is_instance_valid(r.vehicle):
			continue
		var v := r.vehicle
		_watch_shift(r, s)
		_advance_needle(r, s, delta)
		_shake(r, s, delta)
		_timers(s, delta)
		_apply(r, s, delta)
		if bool(s.done):
			continue
		var com := r.com()
		s.furthest = maxf(float(s.furthest), com.z)
		if session.event.drag_centreline and layout.crossed_centreline(com, int(s.lane)):
			_foul(r, "centreline")
			continue
		if layout.off_deck(com):
			_foul(r, "off")
			continue
		if layout.past_finish(com):
			_through_lights(r, s, v)
			continue
		# Stopped on the strip with the line not crossed: nothing more is coming.
		if absf(v.speed()) < DEAD_SPEED:
			s.dead = float(s.dead) + delta
			if float(s.dead) >= DEAD_S:
				_foul(r, "stopped")
		else:
			s.dead = 0.0
	if _all_done() or phase_time >= _pass_limit():
		for r in cars:
			if not bool(_run[r].done):
				_foul(r, "timeout")
		_to(Phase.SETTLE)


## Through the lights: the time from the launch (as a strip measures it, not from the green: the
## reaction is its own number) and the speed it was doing.
func _through_lights(r: Racer, s: Dictionary, v: Vehicle) -> void:
	s.crossed = phase_time
	s.et = phase_time - maxf(float(s.reaction), 0.0)
	s.trap = absf(v.speed())
	s.done = true
	var best: Dictionary = _best.get(r, {})
	if not best.has("et") or float(s.et) < float(best.et):
		best = { "et": float(s.et), "trap": float(s.trap), "reaction": float(s.reaction) }
		_best[r] = best
	run_finished.emit(r, float(s.et), float(s.trap))
	r.notify("%.3f s" % float(s.et), 3.0)


## A shift starting: graded against the window the needle was in (D169).
func _watch_shift(r: Racer, s: Dictionary) -> void:
	var shifting := r.vehicle.sim.is_shifting()
	var was := bool(s.shifting)
	s.shifting = shifting
	if not shifting or was or not session.event.drag_timing:
		return
	var gear := maxi(r.vehicle.sim.get_gear(), 1)
	var row: Array = WINDOWS[mini(gear - 1, WINDOWS.size() - 1)]
	var centre := float(row[0])
	var width := float(row[1])
	var off := absf(float(s.needle) - centre)
	var grade := "miss"
	if off <= width * 0.5:
		grade = "perfect"
	elif off <= width:
		grade = "good"
	match grade:
		"perfect":
			s.chain = mini(int(s.chain) + 1, CHAIN_MAX) if session.event.drag_chain else 0
			s.surge = SURGE_S
		"miss":
			s.chain = 0
			s.bog = BOG_S
	s.needle = NEEDLE_AFTER_SHIFT
	s.strain = 0.0
	shift_graded.emit(r, grade, gear)


## The needle: one rate for every car, sweeping while the driver is on the throttle.
func _advance_needle(r: Racer, s: Dictionary, delta: float) -> void:
	if not session.event.drag_timing:
		s.needle = 0.0
		return
	if bool(s.shifting) or bool(s.blown):
		return
	if r.vehicle.throttle > 0.2:
		s.needle = minf(float(s.needle) + delta / SWEEP_S, NEEDLE_MAX)
	else:
		s.needle = maxf(float(s.needle) - delta / SWEEP_S, 0.0)
	# Past the end it is over-revving: power falls away, and far enough the engine lets go. In top
	# gear there is nothing to shift into, so the needle simply sits at its end and costs nothing.
	if float(s.needle) >= 1.0 and r.vehicle.throttle > 0.5 and not _in_top_gear(r):
		s.strain = float(s.strain) + delta / STRAIN_S
		if float(s.strain) >= 1.0 and session.event.drag_money_shift and not bool(s.blown):
			s.blown = true
			s.chain = 0
			engine_blown.emit(r)
			r.notify("Engine", 3.0)
	elif float(s.needle) < 1.0:
		s.strain = maxf(float(s.strain) - delta / STRAIN_S, 0.0)


## Nothing left to shift into: the last of the platform's ratios.
func _in_top_gear(r: Racer) -> bool:
	var ratios: Array = r.vehicle.platform.gearbox.ratios
	return r.vehicle.sim.get_gear() >= ratios.size()


## Tire shake: the drive wheels lighting up early in the run opens a window to feather it.
func _shake(r: Racer, s: Dictionary, delta: float) -> void:
	if not session.event.drag_shake or not session.event.drag_qtes or bool(s.done):
		return
	if float(s.shake) > 0.0:
		s.shake = float(s.shake) - delta
		if r.vehicle.throttle < 0.3:
			s.shake = 0.0
			s.shook = false
			s.shake_done = true
			shake_changed.emit(r, false)
			r.notify("Caught it", 1.2)
		elif float(s.shake) <= 0.0:
			s.shook = true
			s.shake_done = true
			s.bog = SHAKE_COST_S
			shake_changed.emit(r, false)
			r.notify("Shake", 1.5)
		return
	if bool(s.shake_done) or phase_time > SHAKE_FROM_S:
		return
	var slip := SHAKE_SLIP * (1.0 + 0.5 * float(s.grip))
	if _drive_slip(r) > slip:
		s.shake = SHAKE_WINDOW_S
		shake_changed.emit(r, true)


## The worst slip ratio under the driven wheels.
func _drive_slip(r: Racer) -> float:
	var telemetry: Dictionary = r.vehicle.sim.get_telemetry()
	var worst := 0.0
	for w: Dictionary in telemetry.get("wheels", []):
		worst = maxf(worst, absf(float(w.get("slip_ratio", 0.0))))
	return worst


func _timers(s: Dictionary, delta: float) -> void:
	for key: String in ["surge", "bog", "boost"]:
		if float(s[key]) > 0.0:
			s[key] = maxf(float(s[key]) - delta, 0.0)


## What the mode does to the car this tick: the surge of a perfect shift, a boost, the bog of a
## missed one, the power lost to strain, and the grip a burnout bought at the launch. Forces are
## mass times an acceleration, so the change in speed is the same whatever the car weighs (D164).
func _apply(r: Racer, s: Dictionary, delta: float) -> void:
	var v := r.vehicle
	if bool(s.blown):
		v.throttle = 0.0
		return
	if float(s.bog) > 0.0:
		v.throttle = minf(v.throttle, SHAKE_COST_THROTTLE if bool(s.shook) else BOG_THROTTLE)
	if float(s.strain) > 0.0:
		v.throttle *= 1.0 - STRAIN_POWER * clampf(float(s.strain), 0.0, 1.0)
	var accel := 0.0
	if float(s.surge) > 0.0:
		accel += SURGE_ACCEL * (1.0 + CHAIN_STEP * int(s.chain))
	if float(s.boost) > 0.0:
		accel += BOOST_ACCEL
	if phase_time < LAUNCH_S and float(s.grip) != 0.0:
		accel += LAUNCH_ASSIST_ACCEL * float(s.grip)
	if is_zero_approx(accel) or v.remote:
		return
	var dir := v.global_basis.z.slide(Vector3.UP).normalized()
	if dir.length() > 0.5:
		v.apply_central_force(dir * v.mass * accel)


## Players' inputs: the revs on the line, the launch and the boost. Bots push theirs in through
## launch(), rev() and use_boost(), so both end up in the same place.
func _read_drivers(_delta: float) -> void:
	for r in cars:
		var s: Dictionary = _run.get(r, {})
		if s.is_empty():
			continue
		var input := _input_of(r)
		if input == null:
			continue
		if input.just_pressed("boost"):
			use_boost(r)
		s.rev = input.analog("throttle")
		var action := launch_action(r)
		if action == "throttle":
			if not bool(s.launched) and float(s.rev) > 0.5:
				launch(r)
			continue
		var held_now := input.analog(action) > 0.5
		if held_now:
			s.launch_held = true
		elif bool(s.launch_held) and not bool(s.launched):
			launch(r)


func _input_of(r: Racer) -> PlayerInput:
	var p := r as SessionPlayer
	return p.controller.input if p and p.controller else null


## A pass lost: a red light, the centreline, off the deck, a reset or never getting there.
func _foul(r: Racer, why: String) -> void:
	var s: Dictionary = _run.get(r, {})
	if s.is_empty() or bool(s.done):
		return
	s.foul = why
	s.done = true
	s.foul_at = phase_time
	var text := String({ "red": "Red light", "centreline": "Centreline", "off": "Off the strip",
		"reset": "Reset", "stopped": "Stopped", "timeout": "Too slow" }.get(why, "Out"))
	r.notify(text, 3.0)
	fouled.emit(r, why)
	if builder and why == "red":
		builder.set_bulb(int(s.lane), DragBuilder.Bulb.RED, true)


func _all_done() -> bool:
	for r in cars:
		if not bool(_run.get(r, {}).get("done", true)):
			return false
	return true


func _pass_limit() -> float:
	return 20.0 + layout.length_m * 0.06


## The pass is over: who won it goes to the ladder, then the next pair.
func _end_pass() -> void:
	if cars.is_empty():
		_to(Phase.IDLE)
		return
	var won := _winner()
	var ets := []
	var reactions := []
	for r in cars:
		var s: Dictionary = _run[r]
		ets.append(float(s.et))
		reactions.append(float(s.reaction))
		if r == won and cars.size() > 1:
			r.notify("Won it", 3.0)
		elif cars.size() > 1:
			r.notify("Out", 3.0)
	passes_run += 1
	ladder.record(cars, won, { "ets": ets, "reactions": reactions })
	pass_ended.emit(won)
	for r in cars:
		if ladder.out_in.has(r):
			r.out = true
			r.set_ghost(session.ghosted)
	cars = []
	if builder:
		builder.reset_tree()
	if ladder.finished():
		_finish_match()
		return
	_to(Phase.IDLE)


## The pass's winner: a clean run beats a foul, the lower time beats the higher, and with
## neither car through the lights whoever got furthest takes it. Two red lights: the later one,
## since the first to leave is the one that lost it.
func _winner() -> Racer:
	var best: Racer = null
	var best_key := []
	for r in cars:
		var s: Dictionary = _run[r]
		var clean := String(s.foul).is_empty()
		var key := [
			1 if clean else 0,
			1 if float(s.crossed) >= 0.0 else 0,
			-float(s.crossed) if float(s.crossed) >= 0.0 else float(s.furthest),
			float(s.foul_at),
		]
		if best == null or _better(key, best_key):
			best = r
			best_key = key
	return best


static func _better(a: Array, b: Array) -> bool:
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return float(a[i]) > float(b[i])
	return false


## The match is over: the winner is told, and RaceControl shows the results.
func _finish_match() -> void:
	ended = true
	var won := ladder.winner
	if won:
		won.notify("Winner", 4.0)
	for r in session.racers:
		r.held = true
	session.race.end_session()


## Online client: the pass as the server has it (DragNet).
func apply_net(_r: Racer, _state: Dictionary) -> void:
	pass
