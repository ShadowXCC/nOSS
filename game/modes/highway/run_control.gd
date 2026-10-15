class_name RunControl
extends Node
## A run (docs/GAMEMODES.md §3 "Runs"): a sprint between two marks on the highway through
## traffic. The players line up in its carriageway's lanes ROLL_M before the start, with the
## lanes closed behind them (a traffic break) so nothing comes through, and roll up at PACE_KMH;
## each one's clock starts as they cross the line. A checkpoint every CHECK_M must be passed on
## the run's carriageway (an exit or a crossover is out of the run); the finish stops the clock.
## When everyone is done (or DONE_WAIT_S after the first finish) the results come up, and each
## finish goes on the run's local board. Restart runs it again.

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
## racer -> {started (clock, -1 before), finished (clock, -1), checks passed, out (why, "")}
var state := {}

var _length := 0.0
var _first_finish := -1.0
var _closures: Array = []


func _ready() -> void:
	process_physics_priority = -45
	_length = fposmod(int(run.dir) * (float(run.to_m) - float(run.from_m)), layout.main.length)


## Lines everyone up and closes the lanes behind them: a fresh run.
func begin() -> void:
	phase = Phase.ROLLING
	clock = 0.0
	_first_finish = -1.0
	state.clear()
	var dir := int(run.dir)
	for i in session.racers.size():
		var r := session.racers[i]
		if r.vehicle == null:
			continue
		var lane := i % layout.lanes
		var d := float(run.from_m) - dir * (ROLL_M + (i / layout.lanes) * ROW_M)
		var at := layout.main.transform_at(d, layout.lane_lateral(dir, lane))
		if dir < 0:
			at.basis = Basis(-at.basis.x, at.basis.y, -at.basis.z)
		r.direction = dir
		r.vehicle.reset_to(at, at.basis.z * PACE_KMH / 3.6)
		r.pace_limit = PACE_KMH / 3.6 # m/s
		state[r] = { "started": -1.0, "finished": -1.0, "checks": 0, "out": "" }
		r.notify("Rolling start", 2.0)
	_break(true)


## Where `r` is along the run: metres past the start (negative before it).
func progress(r: Racer) -> float:
	var p := fposmod(int(run.dir) * (r.distance - float(run.from_m)), layout.main.length)
	return p - layout.main.length if p > layout.main.length - ROLL_M - 200.0 else p


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	clock += delta
	var everyone := true
	for r: Racer in state:
		var s: Dictionary = state[r]
		if s.finished >= 0.0 or s.out:
			continue
		everyone = false
		if r.vehicle == null:
			continue
		var p := progress(r)
		if s.started < 0.0:
			if p >= 0.0 and p < SLACK_M:
				s.started = clock
				r.pace_limit = 0.0
				r.notify("Go", 1.5)
				phase = Phase.RUNNING
				if state.values().all(func(x: Dictionary) -> bool: return x.started >= 0.0 or x.out):
					_break(false)
			continue
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
			r.notify("Finish %s" % Hud.format_time(clock - float(s.started)), 3.0)
			if _first_finish < 0.0:
				_first_finish = clock
		elif not on_run and p > 0.0 and int(at.get("dir", run.dir)) != int(run.dir):
			_out(r, "Wrong way")
	if everyone or (_first_finish >= 0.0 and clock - _first_finish > DONE_WAIT_S):
		_finish()


func _out(r: Racer, why: String) -> void:
	state[r].out = why
	r.notify(why, 2.5)


## The results, best first: finishers by time, then those out of it.
func rows() -> Array:
	var out := []
	for r: Racer in state:
		var s: Dictionary = state[r]
		var time := float(s.finished) - float(s.started) if s.finished >= 0.0 else INF
		out.append({ "racer": r, "time": time, "best": time, "dnf": s.finished < 0.0, "name": r.display_name, "number": r.number,
			"car": r.vehicle.package.display_name() if r.vehicle and r.vehicle.package else "", "laps": 1 if s.finished >= 0.0 else 0, "penalty": 0.0, "gap": "",
			"position": 0, "assists": ResultsMenu.assists_text(r) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	for i in out.size():
		out[i].position = i + 1
		if i > 0 and not out[i].dnf:
			out[i].gap = "+%.3f" % (float(out[i].time) - float(out[0].time))
		elif out[i].dnf:
			out[i].gap = String(state[out[i].racer].out) if state[out[i].racer].out else "Unfinished"
	return out


func _finish() -> void:
	phase = Phase.DONE
	_break(false)
	var results := rows()
	if not session.is_online():
		for row: Dictionary in results:
			var r: Racer = row.racer
			if not row.dnf and (r is SessionPlayer):
				Leaderboard.submit(session.track.record_key(), Leaderboard.entry_of(r, { "time": float(row.time) }), "%s|run:%s" % [session.platform_id, run.id])
	done.emit(results)


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
