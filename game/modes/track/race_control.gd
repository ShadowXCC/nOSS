class_name RaceControl
extends Node
## Runs a track event's sessions (docs/GAMEMODES.md §1, MODE-02): free drive, time trial,
## practice, qualifying and the race. For a race it forms the grid (from qualifying, reversed or
## random), counts down with five lights or leads a rolling start, keeps the race clock and the
## standings, shows flags, rules on track limits, and brings everyone home after the checkered
## flag. When a session ends it hands its results to the session to show.

signal session_started(kind: String)
signal session_ended(kind: String, results: Array)

enum Phase { LOADING, GRID, COUNTDOWN, FORMATION, RUNNING, CHECKERED, DONE }

const LIGHTS := 5
const LIGHT_S := 1.0
## Race grid: pole this far behind the line, cars in one column this far apart.
const GRID_FRONT_M := 12.0
const GRID_ROW_M := 13.0
## Rolling start: the grid forms this much further back, runs at PACE_SPEED, and the green
## comes when the leader is this close to the line.
const ROLLING_BACK_M := 220.0
const PACE_SPEED := 22.0
const GREEN_BEFORE_LINE_M := 60.0
## After the leader finishes, the others have this long to finish their lap.
const FINISH_GRACE_S := 60.0
## Flags: a stopped or slow car within YELLOW_M ahead; a car a lap up within BLUE_M behind.
const YELLOW_M := 250.0
const BLUE_M := 100.0
const SLOW_SPEED := 8.0
const FLAG_UPDATE_S := 0.1
## Practice and qualifying release the AI one by one this far apart, so they spread out.
const RELEASE_GAP_S := 2.0
const PENALTY_S := { "lenient": 2.0, "strict": 5.0 }

var session: TrackSession
var event: RaceEvent
## The current session: "free", "time_trial", "practice", "qualifying" or "race".
var kind := "free"
var index := 0
var phase := Phase.LOADING
## Practice and qualifying: time since the start; race: time since the green.
var clock := 0.0
## Countdown lights lit, 0-5.
var lights := 0
## Results of the last session that ended: [{racer, position, time, gap, best, laps, penalty, dnf}].
var results: Array[Dictionary] = []
## The grid from the last qualifying, fastest first.
var qualifying_order: Array[Racer] = []
var leader_finished_at := -1.0

var _countdown := 0.0
var _out_delay := 0.0
var _flag_time := 0.0
var _green_until := 0.0
var _release := {} # racer -> clock at which it's released (practice, qualifying)
var _laps := {} # racer -> timer.lap seen last tick
var _rng := RandomNumberGenerator.new()
var _standings: Array[Racer] = []
var _standings_frame := -1


func _ready() -> void:
	process_physics_priority = -55 # after the RaceField, before drivers
	_rng.randomize()


## Starts the event's first session.
func start() -> void:
	index = 0
	begin(event.sessions()[0])


func has_next() -> bool:
	return index + 1 < event.sessions().size()


func next_session() -> void:
	if has_next():
		index += 1
		begin(event.sessions()[index])


func restart_session() -> void:
	begin(kind)


## A racer joined (or dropped in): listen for its track-limit cuts.
func watch(r: Racer) -> void:
	r.cut_track.connect(_on_cut.bind(r))
	_laps[r] = 0


func is_race() -> bool:
	return kind == "race"


## Laps or time left text for the HUD ("Lap 2/5", "12:04"), or "".
func session_text(r: Racer) -> String:
	match kind:
		"race":
			if phase in [Phase.LOADING, Phase.GRID, Phase.COUNTDOWN, Phase.FORMATION]:
				return "Grid" if phase != Phase.FORMATION else "Formation"
			if event.race_min > 0:
				return _clock_text(maxf(event.race_min * 60.0 - clock, 0.0))
			return "Lap %d/%d" % [clampi(r.timer.lap, 1, event.race_laps), event.race_laps]
		"practice", "qualifying":
			var left := maxf((event.practice_min if kind == "practice" else event.qualifying_min) * 60.0 - clock, 0.0)
			return "%s  %s" % ["Practice" if kind == "practice" else "Qualifying", _clock_text(left)]
	return ""


func begin(session_kind: String) -> void:
	kind = session_kind
	clock = 0.0
	lights = 0
	results.clear()
	leader_finished_at = -1.0
	_release.clear()
	_green_until = 0.0
	var racers := session.racers
	var order := _grid_order()
	for r in racers:
		r.new_session()
		r.flag = ""
		r.dnf = false
		_laps[r] = 0
		r.held = false
	session.hotswap_allowed = kind != "race"
	Players.joining = not session.solo and kind != "race"
	match kind:
		"race":
			phase = Phase.LOADING
			for i in order.size():
				_place(order[i], i, event.start == "rolling")
				order[i].held = true
		"practice", "qualifying":
			phase = Phase.RUNNING
			for i in order.size():
				_place(order[i], i, false)
				if not order[i].is_human:
					_release[order[i]] = RELEASE_GAP_S * i
					order[i].held = true
		_:
			phase = Phase.RUNNING
	session_started.emit(kind)


## Cars in grid order: from qualifying if it ran (players who didn't set a time behind), its
## reverse, or shuffled.
func _grid_order() -> Array[Racer]:
	var racers: Array[Racer] = session.racers.duplicate()
	if kind != "race":
		return racers
	match event.grid:
		"random":
			racers.shuffle()
		_:
			if not qualifying_order.is_empty():
				var known := qualifying_order.filter(func(r: Racer) -> bool: return r in racers)
				var rest := racers.filter(func(r: Racer) -> bool: return r not in known)
				rest.shuffle()
				racers.assign(known + rest)
			else:
				racers.shuffle()
			if event.grid == "reverse":
				racers.reverse()
	return racers


func _place(r: Racer, i: int, rolling: bool) -> void:
	var back := ROLLING_BACK_M if rolling else 0.0
	var at := session.grid_transform(i, GRID_FRONT_M + back, GRID_ROW_M)
	r.spawn_at = at
	if r.vehicle == null:
		return
	if r.waiting:
		r.waiting = false
		r.vehicle.freeze = false
		r.vehicle.visible = true
	r.set_ghost(session.ghosted)
	r.vehicle.reset_to(at)
	var proj := session.track.project(at.origin)
	r.distance = proj.distance
	r.lateral = proj.lateral
	r.last_valid = proj.distance
	r.track_index = -1
	r.timer.teleported(session.track.from_start(proj.distance))


func _physics_process(delta: float) -> void:
	match phase:
		Phase.LOADING:
			if session.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
				phase = Phase.GRID
				_countdown = 0.0
		Phase.GRID:
			_countdown += delta
			if _countdown >= 1.0:
				if event.start == "rolling":
					phase = Phase.FORMATION
					for r in session.racers:
						r.held = false
						r.pace_limit = PACE_SPEED
				else:
					phase = Phase.COUNTDOWN
					_countdown = 0.0
					_out_delay = _rng.randf_range(0.4, 1.4)
		Phase.COUNTDOWN:
			_countdown += delta
			lights = mini(int(_countdown / LIGHT_S) + 1, LIGHTS)
			if _countdown >= LIGHTS * LIGHT_S + _out_delay:
				_go()
		Phase.FORMATION:
			var leader := standings()[0] if not session.racers.is_empty() else null
			if leader and leader.timer.lap == 0 and session.track.from_start(leader.distance) >= session.track.length - GREEN_BEFORE_LINE_M:
				_go()
		Phase.RUNNING, Phase.CHECKERED:
			clock += delta
			_release_cars()
			if kind == "race":
				_check_finish()
			elif kind in ["practice", "qualifying"]:
				var limit := (event.practice_min if kind == "practice" else event.qualifying_min) * 60.0
				if clock >= limit:
					end_session()
	_flag_time -= delta
	if _flag_time <= 0.0:
		_flag_time = FLAG_UPDATE_S
		_update_flags()


func _go() -> void:
	phase = Phase.RUNNING
	lights = 0
	clock = 0.0
	_green_until = 3.0
	for r in session.racers:
		r.held = false
		r.pace_limit = 0.0


func _release_cars() -> void:
	for r: Racer in _release.keys():
		if clock >= _release[r]:
			r.held = false
			_release.erase(r)


func _check_finish() -> void:
	for r in session.racers:
		var lap := r.timer.lap
		var crossed: bool = lap > int(_laps.get(r, 0))
		_laps[r] = lap
		if r.finished or r.dnf or not crossed or lap < 2:
			continue
		var done := lap - 1 # laps completed (the first crossing starts lap 1)
		var leader_done := leader_finished_at >= 0.0
		var distance_done := event.race_min <= 0 and done >= event.race_laps
		var time_done := event.race_min > 0 and clock >= event.race_min * 60.0
		if leader_done or distance_done or time_done:
			_finish(r)
	if leader_finished_at >= 0.0:
		var all_in := session.racers.all(func(r: Racer) -> bool: return r.finished or r.dnf)
		if all_in or clock - leader_finished_at >= FINISH_GRACE_S:
			end_session()


func _finish(r: Racer) -> void:
	r.set_meta(&"finish_laps", _completed(r))
	r.finished = true
	r.finish_time = clock
	if leader_finished_at < 0.0:
		leader_finished_at = clock
		phase = Phase.CHECKERED
	r.flag = "checkered"
	var pos := position_of(r)
	r.notify("Finished P%d" % pos, 4.0)


## Ends the current session and publishes its results (cars keep driving: AI and finished
## players on a cool-down lap).
func end_session() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	var order := standings()
	if kind == "qualifying":
		qualifying_order = order.duplicate()
	results.clear()
	var leader_time := -1.0
	var leader_laps := 0
	for i in order.size():
		var r := order[i]
		var laps := _completed(r)
		var total := r.finish_time + r.penalty_s if r.finish_time >= 0.0 else -1.0
		if i == 0:
			leader_time = total
			leader_laps = laps
		var row := {
			"racer": r, "position": i + 1, "name": r.display_name, "number": r.number,
			"car": r.vehicle.package.display_name() if r.vehicle and r.vehicle.package else "-",
			"time": total, "best": r.timer.best_lap, "laps": laps, "penalty": r.penalty_s,
			"dnf": r.dnf, "gap": "",
		}
		if kind == "race":
			if r.dnf:
				row.gap = "DNF"
			elif i > 0 and laps < leader_laps:
				row.gap = "+%d lap%s" % [leader_laps - laps, "" if leader_laps - laps == 1 else "s"]
			elif i > 0 and total >= 0.0 and leader_time >= 0.0:
				row.gap = "+%.3f" % (total - leader_time)
		elif i > 0 and r.timer.best_lap > 0.0 and order[0].timer.best_lap > 0.0:
			row.gap = "+%.3f" % (r.timer.best_lap - order[0].timer.best_lap)
		results.append(row)
	for r in order:
		r.finished = true # everyone takes a cool-down lap
	session_ended.emit(kind, results)


## Positions now. Race: laps done, then finish time (with penalties) or track position.
## Practice and qualifying: best valid lap, then cars without a time.
func standings() -> Array[Racer]:
	var racers: Array[Racer] = session.racers.duplicate()
	if kind == "race":
		racers.sort_custom(_race_before)
	else:
		racers.sort_custom(func(a: Racer, b: Racer) -> bool:
			var ta := a.timer.best_lap
			var tb := b.timer.best_lap
			if ta > 0.0 and tb > 0.0:
				return ta < tb
			if (ta > 0.0) != (tb > 0.0):
				return ta > 0.0
			return a.number < b.number)
	return racers


func _race_before(a: Racer, b: Racer) -> bool:
	if a.dnf != b.dnf:
		return b.dnf
	var fa := a.finish_time >= 0.0
	var fb := b.finish_time >= 0.0
	if fa or fb:
		var la := _completed(a) if not fa else _finished_laps(a)
		var lb := _completed(b) if not fb else _finished_laps(b)
		if la != lb:
			return la > lb
		if fa and fb:
			return a.finish_time + a.penalty_s < b.finish_time + b.penalty_s
		return fa
	return _progress(a) > _progress(b)


## Laps a finished car had done when it took the flag.
func _finished_laps(r: Racer) -> int:
	return r.get_meta(&"finish_laps", _completed(r))


## 1-based position, from the standings worked out this tick.
func position_of(r: Racer) -> int:
	if Engine.get_physics_frames() != _standings_frame:
		_standings = standings()
		_standings_frame = Engine.get_physics_frames()
	return _standings.find(r) + 1


## Laps completed this session.
func _completed(r: Racer) -> int:
	return maxi(r.timer.lap - 1, 0)


## Distance along the race: laps plus the way round this one. Before the first crossing the
## car is just behind the line, so it's a little below zero.
func _progress(r: Racer) -> float:
	var t := session.track
	var from_line := t.from_start(r.distance)
	if r.timer.lap == 0:
		return from_line - t.length
	return (r.timer.lap - 1) * t.length + from_line


## Gap in seconds from `r` to the car `ahead` of it (by distance and speed).
func gap_seconds(r: Racer, ahead: Racer) -> float:
	var metres := _progress(ahead) - _progress(r)
	return metres / maxf(r.speed, 10.0)


func _update_flags() -> void:
	if kind == "free" or kind == "time_trial":
		for r in session.racers:
			r.flag = ""
		return
	var racers := session.racers
	for r in racers:
		if r.finished and kind == "race":
			r.flag = "checkered" if leader_finished_at >= 0.0 else r.flag
			continue
		var flag := ""
		if phase == Phase.RUNNING and clock < _green_until:
			flag = "green"
		for o in racers:
			if o == r or o.waiting or o.held:
				continue
			var gap := session.field.gap(r, o)
			# Yellow: stopped, very slow or off the road just ahead.
			if gap > 0.0 and gap < YELLOW_M and (absf(o.speed) < SLOW_SPEED or (not o.on_track and absf(o.speed) < 20.0)):
				flag = "yellow"
				break
			# Blue: a car at least most of a lap up, close behind.
			if kind == "race" and gap < 0.0 and gap > -BLUE_M and _progress(o) - _progress(r) > session.track.length * 0.5:
				flag = "blue"
		if r.flag == "yellow" and flag == "":
			flag = "green" # clear again
			r.set_meta(&"green_until", clock + 2.0)
		elif flag == "" and r.has_meta(&"green_until") and clock < float(r.get_meta(&"green_until")):
			flag = "green"
		r.flag = flag


func _on_cut(gained: bool, r: Racer) -> void:
	if event.track_limits == "off":
		return
	if kind != "race":
		r.timer.invalidate("Track limits")
		return
	if phase != Phase.RUNNING and phase != Phase.CHECKERED:
		return
	if not gained and event.track_limits != "strict":
		return
	if r.warnings == 0:
		r.warnings = 1
		r.notify("Track limits: warning", 3.0)
	else:
		var add: float = PENALTY_S.get(event.track_limits, 2.0)
		r.penalty_s += add
		r.notify("Track limits: +%d s" % roundi(add), 3.0)


static func _clock_text(seconds: float) -> String:
	var s := ceili(seconds)
	return "%d:%02d" % [s / 60, s % 60]
