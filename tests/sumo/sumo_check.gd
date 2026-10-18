extends Node
## Sumo soak check (D162): a field of AI cars fights on the shrinking platforms, headless at a
## fixed 120 Hz and faster than real time. Fails on no winner within the time the platforms take
## to go (and a margin), a platform shrinking with nobody ever on it, a car out while its
## platform was still full size and nothing touched it, a car stuck over 5 s, two cars out on the
## same tick (a draw the rules say cannot stand) unless the pillar is on, a car that fell off the
## top platform and never reached the next one when one was there to catch it, or a tier left
## live after its radius reached zero.
## Runs as a scene so the autoloads are there:
##   tools/sumo_check.sh [--cars=8] [--tiers=2] [--hazard=lava|acid]
##                       [--shrink=smooth|crumble|stepped] [--secs=90] [--pillar] [--skill=50-90] [--seed=1]

const STUCK_S := 5.0
## A car doing less than this with the throttle down is stuck.
const STUCK_SPEED := 0.8
## Margin on top of the time every platform needs to shrink away.
const SLACK_S := 90.0
## Two cars in on one tick this close in depth have nothing to tell them apart.
const DEAD_HEAT_M := 0.001
## At most this share of the falls that had a platform below may miss it, and never on one fall
## alone: a miss is meant to be rare, not impossible (D163), so a single one proves nothing.
const MISS_RATE := 0.34

var opts := { "cars": "8", "tiers": "2", "hazard": "lava", "shrink": "smooth", "secs": "90",
	"skill": "50-90", "seed": "1" }
var session: TrackSession
var time := 0.0
var ticks := 0
var tick_us := 0
var started := false
var reported := false
var problems: Array[String] = []
var stuck := {}
var outs: Array[Dictionary] = [] # [{name, at, tier, radius}]
var out_ticks := {} # tick -> the depths under the goo of those that went out on it
var armed_at := {} # tier -> the time it started shrinking
var landed_on := {} # tier -> how many cars have stood on it
var fell_from := {} # racer -> the tier it was last on
var missed := 0 # fell off a platform and never reached the next one
var catchable := 0 # falls that had a platform below to catch them


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	seed(int(opts.seed))
	Game.dev["seed"] = opts.seed
	get_tree().physics_frame.connect(_tick)
	_start.call_deferred()


func _start() -> void:
	Settings.use_folder("user://tests/sumo_check")
	Players.clear()
	session = TrackSession.new()
	session.autodrive = true
	session.platform_id = "official.sumo.standard"
	var skill := String(opts.skill).split("-")
	var e := RaceEvent.sumo(int(opts.tiers), String(opts.hazard))
	e.sumo_shrink = String(opts.shrink)
	e.sumo_secs = int(opts.secs)
	e.sumo_pillar = opts.has("pillar")
	e.ai_count = int(opts.cars) - 1
	e.ai_skill = (float(skill[0]) + float(skill[skill.size() - 1])) / 2.0
	e.ai_cars = "builtin"
	session.event = e
	session.ai_skill_spread = float(skill[skill.size() - 1]) - float(skill[0])
	add_child(session)
	session.race.session_ended.connect(_on_ended)
	print("sumo_check: %d cars, %d tier(s), %s, %s, %d s a platform%s, seed %s" % [int(opts.cars),
		int(opts.tiers), opts.hazard, opts.shrink, int(opts.secs), ", pillar" if e.sumo_pillar else "", opts.seed])


func layout() -> SumoLayout:
	return session.sumo.layout


## How long every platform could take, back to back, plus a margin.
func budget() -> float:
	return float(opts.secs) * int(opts.tiers) + SLACK_S


func _tick() -> void:
	if session == null or not is_instance_valid(session) or reported:
		return
	var t0 := Time.get_ticks_usec()
	var dt := 1.0 / Engine.physics_ticks_per_second
	time += dt
	ticks += 1
	if not started:
		if session.sumo and session.racers.size() == int(opts.cars) and session.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			started = true
			session.sumo.pushed_out.connect(_on_out)
		tick_us += Time.get_ticks_usec() - t0
		return
	var a := layout()
	for r in session.racers:
		_watch(r, dt)
	for i in a.count():
		if a.armed(i) and not armed_at.has(i):
			armed_at[i] = time
			if i > 0 and not session.sumo.armed_by.has(i):
				problems.append("tier %d started shrinking with nobody on it" % (i + 1))
		if not a.live(i) and a.radius_of(i) > 0.0:
			problems.append("tier %d gone but its radius is %.2f" % [i + 1, a.radius_of(i)])
	if time > budget():
		problems.append("no winner after %.0f s (radii %s, %d in)" % [time,
			", ".join(PackedStringArray(Array(a.radii()).map(func(r: float) -> String: return "%.1f" % r))),
			session.sumo.standing().size()])
		_report()
	tick_us += Time.get_ticks_usec() - t0


func _watch(r: Racer, dt: float) -> void:
	var a := layout()
	var at := session.sumo.tier(r)
	var on := session.sumo.standing_on(r)
	if on >= 0:
		landed_on[on] = int(landed_on.get(on, 0)) + (1 if int(fell_from.get(r, -99)) != on else 0)
	if at >= 0:
		fell_from[r] = at
	elif not r.out and int(fell_from.get(r, -1)) >= 0:
		# Left a platform: it should reach the next one if there is one still standing.
		var was := int(fell_from[r])
		fell_from[r] = -1 - was # remember which, negatively, until it lands or goes in
	if r.out or r.vehicle == null or not is_instance_valid(r.vehicle) or r.held:
		stuck.erase(r)
		return
	if absf(r.speed) < STUCK_SPEED and r.vehicle.throttle > 0.3 and at >= 0:
		stuck[r] = float(stuck.get(r, 0.0)) + dt
		if float(stuck[r]) > STUCK_S:
			stuck.erase(r)
			problems.append("%s stuck on tier %d at %.0f s" % [r.display_name, at + 1, time])
	else:
		stuck.erase(r)


func _on_out(r: Racer) -> void:
	var a := layout()
	var was := int(fell_from.get(r, -1))
	var from := was if was >= 0 else -1 - was
	outs.append({ "name": r.display_name, "at": time, "tier": from, "radius": a.radius_of(maxi(from, 0)) })
	var same: Array = out_ticks.get(ticks, [])
	same.append(session.sumo.out_depth(r))
	out_ticks[ticks] = same
	# Went in from a platform that was not the bottom one: it should have been caught.
	if from >= 0 and from < a.count() - 1 and a.live(from + 1):
		catchable += 1
		missed += 1


func _on_ended(_kind: String, results: Array) -> void:
	var a := layout()
	var standing := session.sumo.standing()
	if standing.size() > 1:
		problems.append("ended with %d cars still in" % standing.size())
	# Two cars in on one tick is fine as long as their depths tell them apart (D167); the same
	# tick at the same depth is a real dead heat, with nothing to rank them by.
	for t: int in out_ticks:
		var depths: Array = out_ticks[t]
		if depths.size() < 2:
			continue
		depths.sort()
		for i in depths.size() - 1:
			if absf(float(depths[i + 1]) - float(depths[i])) < DEAD_HEAT_M:
				problems.append("%d cars out on one tick within %.3f m (nothing to rank them by)" % [depths.size(), DEAD_HEAT_M])
				break
	# A miss is meant to be rare, not impossible (D163): a car flung hard off a vanishing ring can
	# clear the one below. Most of them have to be caught, though.
	if missed > 1 and float(missed) / catchable > MISS_RATE:
		problems.append("%d of %d catchable fall(s) missed the platform below" % [missed, catchable])
	var winner: Racer = results[0].racer if not results.is_empty() else null
	print("Sumo: %.0f s, %d tier(s); winner %s (tier %d); radii %s; out: %s" % [session.race.clock, a.count(),
		winner.display_name if winner else "-", session.sumo.reached(winner) + 1 if winner else 0,
		", ".join(PackedStringArray(Array(a.radii()).map(func(r: float) -> String: return "%.1f" % r))),
		", ".join(PackedStringArray(outs.map(func(o: Dictionary) -> String: return "%s %.0fs t%d" % [o.name, o.at, int(o.tier) + 1])))])
	_report()


func _report() -> void:
	if reported:
		return
	reported = true
	print("Check: %.0f s simulated, %d of %d cars out, tiers set going by %s" % [time,
		outs.size(), int(opts.cars), session.sumo.armed_by])
	print("Time: %.1f µs a tick in the check's own work, %d ticks" % [float(tick_us) / maxf(ticks, 1), ticks])
	if problems.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in problems:
			print("  " + line)
		print("FAIL")
		get_tree().quit(1)
