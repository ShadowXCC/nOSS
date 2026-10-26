class_name RunControl
extends Node
## A run (docs/GAMEMODES.md §3 "Runs"): a sprint between two marks on the highway through
## traffic, run as the event's "run" session (RaceControl). The players line up in its
## carriageway's lanes ROLL_M before the start, with the lanes closed behind them (a traffic break)
## so nothing comes through, and roll up at PACE_KMH; each one's clock starts as they cross the
## line. A checkpoint every CHECK_M must be passed on the run's carriageway (an exit or a crossover
## is out of the run); the finish stops the clock. When everyone is done (or DONE_WAIT_S after the
## first finish) the session ends with the run's results, and each finish goes on the run's board.
## Restart runs it again.
##
## Online (docs/NETWORKING.md §15) the server is in charge (`authority`): it times every car from
## where it shows it, rules on the checkpoints and the finish, tells each driver (notes), and its
## results are everyone's. Each game lines up and releases only the cars it drives, by their place
## in the session's grid, so every game puts every car on the same spot.

signal done(rows: Array)

enum Phase { ROLLING, RUNNING, DONE }

const ROLL_M := 400.0
const PACE_KMH := 90.0
const ROW_M := 18.0
const CHECK_M := 400.0
## The traffic break: lanes closed this long behind the grid, until the run is under way.
const BREAK_M := 300.0
const DONE_WAIT_S := 60.0
## A start or a checkpoint counts within this much past it (a fast car moves on between ticks).
const SLACK_M := 60.0

var session: TrackSession
var layout: HighwayLayout
## {id, name, dir, from_m, to_m}
var run: Dictionary = {}
var phase := Phase.ROLLING
var clock := 0.0
## racer -> {started (clock, -1 before), finished (clock, -1), checks passed, out (why, ""), lined
## (seen behind the start since the line-up)}. The authority keeps every driver; a client only
## the cars it drives (their clocks for the HUD).
var state := {}
## Rules on the run: offline, and online the server. Clients follow it (NetRace).
var authority := true

var _length := 0.0
var _first_finish := -1.0
var _closures: Array = []


func _ready() -> void:
	process_physics_priority = -45
	_length = fposmod(int(run.dir) * (float(run.to_m) - float(run.from_m)), layout.main.length)
	authority = not session.is_online() or Net.is_server()
	session.race.standings_source = standings
	# A new "run" session (the first, or Restart) lines up again once it runs (HighwayControl).
	session.race.session_started.connect(func(kind: String) -> void:
		if kind == "run":
			reset())


## Back to before the line-up.
func reset() -> void:
	phase = Phase.ROLLING
	clock = 0.0
	_first_finish = -1.0
	state.clear()
	_break(false)


## Cars that take part: the players' (not police units).
static func drives(r: Racer) -> bool:
	return not r is PoliceRacer and r.net_id < NetProtocol.FIRST_POLICE_ID


## This game drives `r` (its own players; on a server, its AI).
static func own(r: Racer) -> bool:
	return not r is NetRacer


## The drivers in grid order: online the session's grid (every game the same), else as they came.
func lineup() -> Array[Racer]:
	var drivers: Array[Racer] = session.racers.filter(drives)
	if not session.is_online() or session.net == null:
		return drivers
	var out: Array[Racer] = []
	for id: Variant in session.race.grid_ids:
		var r: Racer = session.net.racers.get(int(id))
		if r and r in drivers and r not in out:
			out.append(r)
	for r in drivers:
		if r not in out:
			out.append(r)
	return out


## Where grid place `i` lines up: in the run's lanes ROLL_M before its start, a row every ROW_M.
func spot_for(i: int) -> Transform3D:
	var dir := int(run.dir)
	var lane := i % layout.lanes
	var d := float(run.from_m) - dir * (ROLL_M + (i / layout.lanes) * ROW_M)
	var at := layout.main.transform_at(d, layout.lane_lateral(dir, lane))
	if dir < 0:
		at.basis = Basis(-at.basis.x, at.basis.y, -at.basis.z)
	return at


## Lines everyone up and closes the lanes behind them: a fresh run. Each game places its own cars.
func begin() -> void:
	reset()
	var dir := int(run.dir)
	var cars := lineup()
	for i in cars.size():
		var r := cars[i]
		if r.vehicle == null:
			continue
		r.spawn_at = spot_for(i)
		if own(r):
			var at := r.spawn_at
			r.direction = dir
			r.vehicle.reset_to(at, at.basis.z * PACE_KMH / 3.6)
			r.pace_limit = PACE_KMH / 3.6 # m/s
			if session.is_online():
				r.set_ghost(true) # the others are still on their way to their spots
			r.notify("Rolling start", 2.0)
		if authority or own(r):
			state[r] = { "started": -1.0, "finished": -1.0, "checks": 0, "out": "", "lined": own(r) }
	_break(true)


## Where `r` is along the run: metres past the start (negative before it).
func progress(r: Racer) -> float:
	var p := fposmod(int(run.dir) * (r.distance - float(run.from_m)), layout.main.length)
	return p - layout.main.length if p > layout.main.length - ROLL_M - 200.0 else p


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE or state.is_empty():
		return
	clock += delta
	var everyone := true
	for key: Variant in state:
		var s: Dictionary = state[key]
		if s.finished >= 0.0 or s.out:
			continue
		everyone = false
		if not is_instance_valid(key) or (key as Racer).vehicle == null:
			continue
		var r: Racer = key
		if r.has_meta(&"left"):
			_out(r, "Left")
			continue
		var p := progress(r)
		if s.started < 0.0:
			# A car counts from behind the line: another game's may still be on its way to its spot.
			if p < 0.0:
				s.lined = true
			elif s.lined and p < SLACK_M:
				s.started = clock
				phase = Phase.RUNNING
				if own(r):
					r.pace_limit = 0.0
					if session.is_online():
						r.set_ghost(session.ghosted)
					r.notify("Go", 1.5)
				if authority and state.values().all(func(x: Dictionary) -> bool: return x.started >= 0.0 or x.out):
					_break(false)
			continue
		if not authority:
			continue # the server rules on the rest (its notes, NetRace)
		var at: Dictionary = session.highway_field.at(r) if session.highway_field else {}
		var on_run := not at.is_empty() and bool(at.get("main", true)) and int(at.get("dir", run.dir)) == int(run.dir)
		var next := (int(s.checks) + 1) * CHECK_M
		if next < _length and p >= next:
			if on_run and p < next + SLACK_M:
				s.checks = int(s.checks) + 1
			else:
				_out(r, "Off the run")
				continue
		if p >= _length and p < _length + SLACK_M and on_run:
			s.finished = clock
			var time := clock - float(s.started)
			r.finish_time = time
			r.finished = true
			r.notify("Finish %s" % Hud.format_time(time), 3.0)
			if _first_finish < 0.0:
				_first_finish = clock
		elif not on_run and p > 0.0 and int(at.get("dir", run.dir)) != int(run.dir):
			_out(r, "Wrong way")
	if authority and (everyone or (_first_finish >= 0.0 and clock - _first_finish > DONE_WAIT_S)):
		_finish()


func _out(r: Racer, why: String) -> void:
	state[r].out = why
	r.dnf = true
	if why != "Left":
		r.notify(why, 2.5)


## What the HUD's top line says for `r`: "Rolling", its run's clock, its time once through, "Out".
func status_text(r: Racer) -> String:
	if r.finish_time >= 0.0:
		return "Run " + Hud.format_time(r.finish_time)
	if r.dnf:
		return "Out"
	var s: Dictionary = state.get(r, {})
	if s.is_empty() or float(s.started) < 0.0:
		return "Rolling"
	return "Run " + Hud.format_time(clock - float(s.started))


## Standings now (RaceControl's): finishers by time, then the cars still running by how far along,
## then those out of it.
func standings() -> Array[Racer]:
	var out: Array[Racer] = []
	for r: Variant in state:
		if is_instance_valid(r): # a car that left after the run is gone
			out.append(r)
	out.sort_custom(func(a: Racer, b: Racer) -> bool:
		var sa: Dictionary = state[a]
		var sb: Dictionary = state[b]
		var fa := float(sa.finished) >= 0.0
		var fb := float(sb.finished) >= 0.0
		if fa != fb:
			return fa
		if fa:
			return float(sa.finished) - float(sa.started) < float(sb.finished) - float(sb.started)
		var oa := not String(sa.out).is_empty()
		if oa != (not String(sb.out).is_empty()):
			return not oa
		return progress(a) > progress(b))
	return out


## `r`'s part of the results (RaceControl's rows): its time, or why it's out ("Off the run").
func row(r: Racer) -> Dictionary:
	var s: Dictionary = state.get(r, {})
	var through := not s.is_empty() and float(s.finished) >= 0.0
	var time := float(s.finished) - float(s.started) if through else -1.0
	return { "time": time, "best": time, "laps": 1 if through else 0, "dnf": not through,
		"gap": "" if through else (String(s.out) if not s.is_empty() and s.out else "Unfinished") }


## The results, best first (the authority's).
func rows() -> Array:
	var out := []
	var order := standings()
	for i in order.size():
		var r := order[i]
		var d := row(r)
		d.merge({ "racer": r, "name": r.display_name, "number": r.number, "position": i + 1, "penalty": 0.0,
			"car": r.vehicle.package.display_name() if r.vehicle and r.vehicle.package else "", "assists": ResultsMenu.assists_text(r) })
		out.append(d)
	for i in range(1, out.size()):
		if not out[i].dnf and not out[0].dnf:
			out[i].gap = "+%.3f" % (float(out[i].time) - float(out[0].time))
	return out


## Everyone's done (or the wait's over): the board, then the session's results (everyone's, online).
func _finish() -> void:
	phase = Phase.DONE
	_break(false)
	var results := rows()
	for row: Dictionary in results:
		var r: Racer = row.racer
		if not row.dnf and (r is SessionPlayer or r.is_human):
			# Offline the local board; online the server's (it timed every car).
			Leaderboard.submit(session.track.record_key(), Leaderboard.entry_of(r, { "time": float(row.time) }), "%s|run:%s" % [session.platform_id, run.id],
				session.is_online())
	done.emit(results)
	if session.race.kind == "run":
		session.race.end_session()


## The traffic break: the run's lanes closed behind the grid (on), or open again.
func _break(on: bool) -> void:
	var tm := session.traffic
	if tm == null or not tm.authority:
		return
	for id: int in _closures:
		tm.open_lanes(id)
	_closures.clear()
	if not on:
		return
	var dir := int(run.dir)
	var back := float(run.from_m) - dir * (ROLL_M + 4.0 * ROW_M)
	for lane in layout.lanes:
		var id := tm.close_lane(dir, lane, back - dir * BREAK_M, BREAK_M)
		if id >= 0:
			_closures.append(id)
