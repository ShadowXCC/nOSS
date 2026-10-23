extends Node
## Highway check (M7): a highway session runs headless at a fixed 120 Hz, faster than real time.
##   tools/highway_check.sh [--scenario=cruise|loop] [--track=<ref>] [--players=1] [--traffic=150]
##                          [--seconds=120] [--laps=3] [--seed=1] [--verbose]
##                          [--police [--heat=1-5] [--flat-out]] [--platform=<id>]
## cruise: autodriven players in traffic; fails if a player gets stuck, the traffic population
##   changes, or no traffic became a physics car near a player.
## loop (acceptance 3): two players going opposite ways for --laps laps of player 1; fails unless
##   they pass each other every lap and at least 60% of the cars met on the other carriageway one
##   lap come round again the next.
## --police: police on, and a line on how they did (PoliceWatch); --heat holds player 1's heat at
## that level, --flat-out drives the players as fast as they can (D201). With police on, driving the
## wrong way is reported, not a fail: a PIT spins the car round.

const STUCK_S := 10.0
const RECUR_MIN := 0.6

var opts := { "scenario": "cruise", "players": "1", "traffic": "-1", "seconds": "120", "laps": "3", "seed": "1" }
var session: TrackSession
var time := 0.0
var ticks := 0
var started := false
var reported := false
var stuck := {}
var stuck_events: Array[String] = []
var travelled := {}
var last_pos := {}
var population := -1
var wrong_way := {}
var max_physics := 0
var traffic_contacts := 0
var _frame_us := 0
var _frame_sum := 0.0
var _frames := 0
## Loop scenario.
var loop: LoopWatch
var police_watch: PoliceWatch


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	seed(int(opts.seed))
	get_tree().physics_frame.connect(_tick)
	_start.call_deferred()


func _start() -> void:
	Settings.use_folder("user://tests/highway_check")
	Players.clear()
	var track := TrackLibrary.resolve(String(opts.get("track", "")))
	if track.is_empty():
		var highways := TrackLibrary.list(true, true, "highway")
		track = highways[0].path if not highways.is_empty() else "res://tests/fixtures/tracks/highway_ring_small.json"
	session = TrackSession.new()
	session.track_path = track
	session.autodrive = true
	session.platform_id = String(opts.get("platform", "official.highway.street"))
	session.event = RaceEvent.highway("loop" if opts.scenario == "loop" else "cruise", opts.has("police"), int(opts.traffic))
	session.traffic_seed = int(opts.seed)
	var players := 2 if opts.scenario == "loop" else int(opts.players)
	session.ai_players = players - 1
	if opts.scenario == "loop":
		session.directions = [1, -1]
	add_child(session)


func _tick() -> void:
	if session == null or not session.is_inside_tree():
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	var now_us := Time.get_ticks_usec()
	if _frame_us > 0 and started:
		_frame_sum += float(now_us - _frame_us) / 1000.0
		_frames += 1
	_frame_us = now_us
	if not started:
		if session.players.size() == (2 if opts.scenario == "loop" else int(opts.players)) and session.players.all(func(p: SessionPlayer) -> bool: return p.vehicle != null):
			started = true
			var tm := session.traffic
			population = tm.sim.get_count() if tm else 0
			print("Highway: %s, %d players, %d traffic, %s, seed %s" % [session.track.display_name, session.players.size(), population, opts.scenario, opts.seed])
			if opts.has("flat-out"):
				for p in session.players:
					if p.driver is HighwayDriver:
						(p.driver as HighwayDriver).flat_out()
		return
	time += dt
	ticks += 1
	if session.police and police_watch == null:
		police_watch = PoliceWatch.new(session.police, session.players[0], int(opts.get("heat", "0")))
	if police_watch:
		police_watch.step(dt)
	var tm := session.traffic
	if tm:
		max_physics = maxi(max_physics, tm.cars.size())
		if tm.sim.active_count() + tm.sim.away_count() != population:
			_fail_now("traffic population changed: %d" % (tm.sim.active_count() + tm.sim.away_count()))
	for p in session.players:
		var v := p.vehicle
		var pos := v.global_position
		travelled[p] = float(travelled.get(p, 0.0)) + (pos.distance_to(last_pos[p]) if last_pos.has(p) else 0.0)
		last_pos[p] = pos
		if v.traffic_impulse > 150.0:
			traffic_contacts += 1
			if opts.has("verbose"):
				print("  traffic contact %.1f s: %s (%.0f N·s)" % [time, p.display_name, v.traffic_impulse])
		if p.wrong_way:
			wrong_way[p] = float(wrong_way.get(p, 0.0)) + dt
		if absf(p.speed) < 1.0 and time > 15.0:
			stuck[p] = float(stuck.get(p, 0.0)) + dt
			if stuck[p] > STUCK_S and stuck[p] - dt <= STUCK_S:
				stuck_events.append("%s at %.0f m, %.1f s" % [p.display_name, p.distance, time])
		else:
			stuck[p] = 0.0
	if opts.scenario == "loop":
		if loop == null:
			loop = LoopWatch.new(session, session.players[0], session.players[1])
		if loop.step() and opts.has("verbose"):
			print("  met at %.0f s on lap %d" % [time, session.players[0].timer.lap])
		if session.players[0].timer.lap > int(opts.laps) + 1:
			_report()
		elif time > (int(opts.laps) + 2) * session.track.length / 12.0: # laps + 1 at 12 m/s at least
			_report()
	elif time >= float(opts.seconds):
		_report()


func _fail_now(why: String) -> void:
	print("FAIL " + why)
	reported = true
	get_tree().quit(1)


func _report() -> void:
	if reported:
		return
	reported = true
	var fails := PackedStringArray()
	for s in stuck_events:
		fails.append("stuck: " + s)
	for p: SessionPlayer in wrong_way:
		var why := "%s drove the wrong way for %.1f s" % [p.display_name, wrong_way[p]]
		if session.police:
			print("  " + why)
		else:
			fails.append(why)
	var tm := session.traffic
	var stats := ""
	if tm:
		stats = "traffic %d (%d away), physics cars %d at most, promotions %d, demotions %d, wrecks %d, tows %d" % [
			population, tm.sim.away_count(), max_physics, tm.promotions, tm.demotions, tm.wrecks, tm.tows]
		if tm.promotions == 0 and population > 0:
			fails.append("no traffic became a physics car")
	print("Time %.0f s, %s, traffic contacts %d, %.2f ms a frame" % [time, stats, traffic_contacts, _frame_sum / maxi(_frames, 1)])
	for p in session.players:
		print("  %s: %.1f km, lap %d, dir %d" % [p.display_name, float(travelled.get(p, 0.0)) / 1000.0, p.timer.lap, p.direction])
	if police_watch:
		print(police_watch.line())
	if opts.scenario == "loop":
		# Whole laps of player 1: from its first lap line crossing to its last.
		var rows := loop.rows() if loop else []
		for row: Dictionary in rows.slice(0, int(opts.laps)):
			print("  lap %d: met player 2 %d times, %d traffic cars met, %.0f%% met again next lap" % [row.lap, row.met, row.traffic, maxf(row.again, 0.0) * 100.0])
			if row.met < 1:
				fails.append("lap %d: the players never passed" % row.lap)
			if row.again >= 0.0 and row.again < RECUR_MIN:
				fails.append("lap %d: only %.0f%% of the traffic came round again" % [row.lap, row.again * 100.0])
		if rows.size() < int(opts.laps):
			fails.append("player 1 drove %d of %d laps" % [rows.size(), int(opts.laps)])
	if fails.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("FAIL " + f)
		get_tree().quit(1)
