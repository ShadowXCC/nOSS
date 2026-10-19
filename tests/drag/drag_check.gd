extends Node
## Drag soak check (D168): a field of AI cars runs the ladder headless at a fixed 120 Hz, faster
## than real time. Fails on no winner inside the time the passes could take, a pass that ends
## with nobody winning it, the ladder not eliminating one car a pass, a stuck car, a bot's
## reaction outside what a tree allows, bots that cannot hold their lane, a field that never
## shifts in the window at high skill, a car that never stops inside the shutdown, or a car left
## parked when it should be running.
## Runs as a scene so the autoloads are there:
##   tools/drag_check.sh [--cars=8] [--class=street|pro|top_fuel] [--length=201|402|805]
##                       [--boost=0-3] [--skill=50-90] [--seed=1] [--no-timing] [--no-qtes]
##                       [--no-tree] [--no-two-step] [--no-burnout] [--no-shake] [--no-chain]
##                       [--no-money-shift] [--no-centreline] [--garage-ai]

## A car doing less than this with the throttle down is stuck.
const STUCK_SPEED := 0.8
const STUCK_S := 5.0
## What a tree allows: a bot that reacts slower than this is asleep, and under this is a red
## light the check expects to be marked as one.
const REACTION_MAX_S := 1.2
## With every bot at this skill or better, most shifts should land in the window; with any field
## whose best bots are good, a decent share should. Below that, missing the window is the point
## of a skill setting, so nothing is asserted beyond "they shift at all".
const SHARP_SKILL := 85.0
const SHARP_PERFECT := 0.6
const DECENT_SKILL := 80.0
const DECENT_PERFECT := 0.25
## At most this share of passes may be lost to the centreline: bots are meant to hold a lane.
const CENTRELINE_RATE := 0.15
## Margin on top of what every pass could take.
const SLACK_S := 60.0

var opts := { "cars": "8", "class": "street", "length": "402", "boost": "1", "skill": "50-90", "seed": "1" }
var session: TrackSession
var time := 0.0
var ticks := 0
var tick_us := 0
var started := false
var reported := false
var problems: Array[String] = []
var stuck := {}
## Per pass: {round, cars, reactions, ets, fouls, won}.
var runs: Array[Dictionary] = []
var grades := { "perfect": 0, "good": 0, "miss": 0 }
var fouls := {}
var blown := 0
var boosts := 0
var shakes := 0
## racer -> the furthest down the strip it got, to see it stopped in the shutdown.
var furthest := {}
var expected_passes := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	seed(int(opts.seed))
	Game.dev["seed"] = opts.seed
	get_tree().physics_frame.connect(_tick)
	_start.call_deferred()


func _start() -> void:
	Settings.use_folder("user://tests/drag_check")
	Players.clear()
	session = TrackSession.new()
	# The session always makes one player slot ("one player can just drive"); a dev slot is
	# driven by the mode's AI, so the whole field is bots.
	session.autodrive = true
	session.platform_id = "official.drag." + String(opts["class"])
	var skill := String(opts.skill).split("-")
	var e := RaceEvent.drag(int(opts.length), int(opts.boost))
	for pair: Array in [["no-timing", "drag_timing"], ["no-qtes", "drag_qtes"], ["no-tree", "drag_tree"],
			["no-two-step", "drag_two_step"], ["no-burnout", "drag_burnout"], ["no-shake", "drag_shake"],
			["no-chain", "drag_chain"], ["no-money-shift", "drag_money_shift"],
			["no-centreline", "drag_centreline"]]:
		if opts.has(pair[0]):
			e.set(String(pair[1]), false)
	e.ai_count = maxi(int(opts.cars) - 1, 0)
	e.ai_skill = (float(skill[0]) + float(skill[skill.size() - 1])) / 2.0
	e.ai_cars = "garage" if opts.has("garage-ai") else "builtin"
	session.event = e
	session.drag_seed = int(opts.seed)
	session.ai_skill_spread = float(skill[skill.size() - 1]) - float(skill[0])
	add_child(session)
	session.race.session_ended.connect(_on_ended)
	print("drag_check: %d cars, %s, %d m, %d boost(s), skill %s, seed %s" % [int(opts.cars),
		opts["class"], int(opts.length), int(opts.boost), opts.skill, opts.seed])


func drag() -> DragControl:
	return session.drag


## What every pass could take, back to back, plus a margin.
func budget() -> float:
	var per_pass := DragControl.BURNOUT_S + DragControl.STAGE_S + DragControl.AMBERS * DragControl.AMBER_S \
		+ 20.0 + float(int(opts.length)) * 0.06 + DragControl.SETTLE_S
	return per_pass * maxi(expected_passes, 1) + SLACK_S


func _tick() -> void:
	if session == null or not is_instance_valid(session) or reported:
		return
	var t0 := Time.get_ticks_usec()
	var dt := 1.0 / Engine.physics_ticks_per_second
	time += dt
	ticks += 1
	if not started:
		if drag() and not session.racers.is_empty() and session.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			started = true
			expected_passes = maxi(session.racers.size() - 1, 1)
			var humans := session.racers.filter(func(r: Racer) -> bool: return r.is_human).size()
			print("Field: %d cars (%d human), ladder of %d pass(es)" % [session.racers.size(), humans, expected_passes])
			if humans > 0:
				problems.append("%d human car(s) in an AI-only check: they will never drive" % humans)
			drag().shift_graded.connect(func(_r: Racer, grade: String, _gear: int) -> void:
				grades[grade] = int(grades[grade]) + 1)
			drag().fouled.connect(func(_r: Racer, why: String) -> void:
				fouls[why] = int(fouls.get(why, 0)) + 1)
			drag().engine_blown.connect(func(_r: Racer) -> void: blown += 1)
			drag().boost_used.connect(func(_r: Racer) -> void: boosts += 1)
			drag().shake_changed.connect(func(_r: Racer, on: bool) -> void:
				if on:
					shakes += 1)
			drag().pass_ended.connect(_on_pass)
		tick_us += Time.get_ticks_usec() - t0
		return
	for r in session.racers:
		_watch(r, dt)
	if time > budget():
		problems.append("no winner after %.0f s (%d of %d passes, round %s)" % [time,
			drag().passes_run, expected_passes, drag().ladder.round_text()])
		_report()
	tick_us += Time.get_ticks_usec() - t0


func _watch(r: Racer, dt: float) -> void:
	var d := drag()
	if r.vehicle == null or not is_instance_valid(r.vehicle):
		return
	var state: Dictionary = d.run_of(r)
	if state.is_empty() or r.parked:
		stuck.erase(r)
		return
	furthest[r] = maxf(float(furthest.get(r, -INF)), r.com().z)
	# A car in the pass should be driving, not sitting there with the throttle down.
	if d.phase == DragControl.Phase.RUN and not bool(state.done) and not bool(state.blown) \
			and absf(r.speed) < STUCK_SPEED and r.vehicle.throttle > 0.3:
		stuck[r] = float(stuck.get(r, 0.0)) + dt
		if float(stuck[r]) > STUCK_S:
			stuck.erase(r)
			problems.append("%s stuck on the strip at %.0f s" % [r.display_name, time])
	else:
		stuck.erase(r)


func _on_pass(won: Racer) -> void:
	var d := drag()
	var entry: Dictionary = d.ladder.passes.back() if not d.ladder.passes.is_empty() else {}
	var names: Array[String] = []
	var numbers: Array[String] = []
	for r: Racer in entry.get("cars", []):
		names.append(r.display_name)
		var state: Dictionary = d.run_of(r)
		var reaction := float(state.get("reaction", -1.0))
		var et := float(state.get("et", -1.0))
		var foul := String(state.get("foul", ""))
		var trap := float(state.get("trap", -1.0))
		numbers.append("%s %s %s%s" % [
			"RT %.3f" % reaction if reaction >= 0.0 else "RT -",
			"ET %.3f" % et if et >= 0.0 else "ET -",
			"%.0f km/h" % (trap * 3.6) if trap >= 0.0 else "-",
			" (%s)" % foul if foul else ""])
		if reaction > REACTION_MAX_S:
			problems.append("%s reacted in %.2f s, slower than a tree allows" % [r.display_name, reaction])
		if reaction < 0.0 and et >= 0.0 and session.event.drag_tree and foul.is_empty():
			problems.append("%s went through the lights with no reaction timed" % r.display_name)
	runs.append({ "round": int(entry.get("round", 0)), "cars": names, "won": won.display_name if won else "-" })
	print("  pass %d (round %d): %s -> %s  [%s]" % [d.passes_run, int(entry.get("round", 0)) + 1,
		" vs ".join(names), won.display_name if won else "nobody", "; ".join(numbers)])
	if won == null and names.size() > 1:
		problems.append("pass %d ended with nobody winning it" % d.passes_run)


func _on_ended(_kind: String, results: Array) -> void:
	var d := drag()
	var winner: Racer = results[0].racer if not results.is_empty() else null
	if winner == null or d.ladder.winner == null:
		problems.append("the match ended with no winner")
	elif winner != d.ladder.winner:
		problems.append("the results lead with %s but the ladder won with %s" % [winner.display_name, d.ladder.winner.display_name])
	if d.passes_run != expected_passes:
		problems.append("%d passes run, %d expected for a field of %d" % [d.passes_run, expected_passes, session.racers.size()])
	# Everyone but the winner should be out, one a pass.
	var still_in := d.standing().size()
	if still_in != 1:
		problems.append("%d cars still in the ladder at the end" % still_in)
	# Nobody should end up in the sand: the shutdown is as long as the strip for a reason.
	for r: Variant in furthest:
		if float(furthest[r]) >= d.layout.trap_z():
			problems.append("%s ran into the sand (%.0f m, trap at %.0f m)" % [
				(r as Racer).display_name, float(furthest[r]), d.layout.trap_z()])
	var shifts := int(grades.perfect) + int(grades.good) + int(grades.miss)
	if session.event.drag_timing and shifts == 0:
		problems.append("not one shift was graded: the field never shifted")
	var parts := String(opts.skill).split("-")
	var skill_low := float(parts[0])
	var skill_top := float(parts[-1])
	if session.event.drag_timing and shifts > 0:
		var rate := float(grades.perfect) / shifts
		if skill_low >= SHARP_SKILL and rate < SHARP_PERFECT:
			problems.append("only %.0f%% of %d shifts were perfect with every bot at skill %.0f+" % [rate * 100.0, shifts, skill_low])
		elif skill_top >= DECENT_SKILL and rate < DECENT_PERFECT:
			problems.append("only %.0f%% of %d shifts were perfect with bots up to skill %.0f" % [rate * 100.0, shifts, skill_top])
	if session.event.drag_centreline and d.passes_run > 0:
		var rate := float(int(fouls.get("centreline", 0))) / float(d.passes_run * 2)
		if rate > CENTRELINE_RATE:
			problems.append("%.0f%% of runs lost to the centreline: bots cannot hold a lane" % (rate * 100.0))
	print("Drag: %.0f s, %d passes; winner %s; shifts %d perfect / %d good / %d missed; %d boost(s), %d shake(s), %d blown; fouls %s" % [
		time, d.passes_run, winner.display_name if winner else "-",
		int(grades.perfect), int(grades.good), int(grades.miss), boosts, shakes, blown,
		_fouls_text()])
	_report()


func _fouls_text() -> String:
	if fouls.is_empty():
		return "none"
	var parts: Array[String] = []
	for why: String in fouls:
		parts.append("%s %d" % [why, int(fouls[why])])
	return ", ".join(parts)


func _report() -> void:
	if reported:
		return
	reported = true
	var ms := float(tick_us) / 1000.0
	print("Ticks: %d in %.0f ms (%.3f ms a tick)" % [ticks, ms, ms / maxi(ticks, 1)])
	if problems.is_empty():
		print("PASS drag_check")
		get_tree().quit(0)
		return
	for p in problems:
		print("  ! " + p)
	print("FAIL drag_check: %d problem(s)" % problems.size())
	get_tree().quit(1)
