class_name LapTimer
extends RefCounted
## Lap timing for track modes (docs/GAMEMODES.md §1, MODE-01): the start/finish line, three
## sectors and invisible checkpoints every ~100 m. A lap counts only if every checkpoint is
## passed in order. Fed with along-track positions once per physics tick.

signal lap_started(lap: int)
signal lap_completed(time: float, valid: bool, best: bool)
signal sector_completed(sector: int, time: float, delta: float)
signal invalidated(reason: String)

## Largest believable progress in one tick, m.
const MAX_STEP := 30.0
## The live delta compares lap times every this many metres.
const TRACE_M := 10.0

var track_length := 0.0
var sector_ends := PackedFloat32Array() # from the start line; the last sector ends at the line
var checkpoint_spacing := 100.0

var lap := 0 # current lap number, 0 before the first crossing
var lap_time := 0.0
var valid := true
var last_lap := -1.0
var best_lap := -1.0
var best_sectors := PackedFloat32Array()
var current_sectors := PackedFloat32Array()
var wrong_way := false

var _prev := -1.0 # previous position from the line
var _next_checkpoint := 1
var _checkpoint_count := 0
var _sector := 0
var _sector_start := 0.0
var _best_splits := PackedFloat32Array() # cumulative split times of the best lap
var _backwards_time := 0.0
var _trace := PackedFloat32Array() # lap time at each TRACE_M mark of this lap
var _best_trace := PackedFloat32Array() # the same for the best lap


func setup(length: float, sectors: PackedFloat32Array, spacing: float) -> void:
	track_length = length
	sector_ends = sectors
	checkpoint_spacing = maxf(spacing, 10.0)
	_checkpoint_count = int(floor(track_length / checkpoint_spacing))
	best_sectors.resize(sector_ends.size() + 1)
	best_sectors.fill(-1.0)


func sector_count() -> int:
	return sector_ends.size() + 1


## Advance by one tick. `pos` is the distance from the start line, [0, length).
func update(pos: float, dt: float, speed: float) -> void:
	if _prev < 0.0:
		_prev = pos
		return
	var delta := pos - _prev
	if delta > track_length / 2.0:
		delta -= track_length
	elif delta < -track_length / 2.0:
		delta += track_length

	# Wrong way: going backwards along the track at speed for a while.
	if delta < -0.01 and speed > 4.0:
		_backwards_time += dt
	else:
		_backwards_time = maxf(_backwards_time - dt * 2.0, 0.0)
	wrong_way = _backwards_time > 1.5

	if lap > 0:
		lap_time += dt
	if delta > MAX_STEP:
		invalidate("Shortcut") # the nearest track point jumped: cut across or teleported
	elif delta > 0.0:
		_forward(_prev, delta, dt)
	_prev = pos


## Marks the current lap as not counting (e.g. after a car reset).
func invalidate(reason: String) -> void:
	if lap > 0 and valid:
		valid = false
		invalidated.emit(reason)


## Re-syncs after a teleport without crossing anything in between.
func teleported(pos: float) -> void:
	_prev = pos


## Live delta to the best lap at the current spot, or NAN: + = slower.
func live_delta() -> float:
	if _best_trace.is_empty() or lap == 0 or _prev < 0.0:
		return NAN
	var i := int(_prev / TRACE_M)
	if i + 1 >= _best_trace.size():
		return NAN
	var f := (_prev - i * TRACE_M) / TRACE_M
	return lap_time - lerpf(_best_trace[i], _best_trace[i + 1], f)


## Live delta to the best lap at the last split, or NAN.
func delta_to_best() -> float:
	if _best_splits.is_empty() or _sector == 0:
		return NAN
	var split := 0.0
	for s in current_sectors:
		split += s
	return split - _best_splits[_sector - 1]


func _forward(from: float, distance: float, dt: float) -> void:
	var to := from + distance
	# Fraction of this tick at which a position was passed, for sub-tick timing.
	var at := func(mark: float) -> float: return lap_time - dt * (1.0 - (mark - from) / distance)

	# Live delta trace.
	if lap > 0:
		var mark := ceilf(from / TRACE_M) * TRACE_M
		while mark <= to and mark < track_length:
			if int(mark / TRACE_M) == _trace.size():
				_trace.append(at.call(mark))
			mark += TRACE_M

	# Checkpoints.
	if lap > 0:
		for k in range(_next_checkpoint, _checkpoint_count):
			var mark := k * checkpoint_spacing
			if mark > to:
				break
			if mark > from:
				_next_checkpoint = k + 1
		# Skipping ahead past unvisited checkpoints in one tick means a shortcut.
		var reached := int(floor(fposmod(to, track_length) / checkpoint_spacing))
		if to < track_length and reached > _next_checkpoint:
			invalidate("Missed checkpoint")

	# Sectors.
	if lap > 0 and _sector < sector_ends.size():
		var end := sector_ends[_sector]
		if from < end and to >= end:
			_close_sector(at.call(end))

	# Start/finish line.
	if to >= track_length:
		var crossed := at.call(track_length) as float
		if lap > 0:
			if _next_checkpoint < _checkpoint_count:
				invalidate("Missed checkpoint")
			_close_sector(crossed)
			_finish_lap(crossed)
		lap += 1
		lap_time = lap_time - crossed if lap > 1 else dt * (to - track_length) / distance
		valid = true
		_next_checkpoint = 1
		_sector = 0
		_sector_start = 0.0
		current_sectors.clear()
		_trace.clear()
		_trace.append(0.0)
		lap_started.emit(lap)


func _close_sector(time: float) -> void:
	var t := time - _sector_start
	current_sectors.append(t)
	var delta := NAN
	if not _best_splits.is_empty():
		var split := 0.0
		for s in current_sectors:
			split += s
		delta = split - _best_splits[current_sectors.size() - 1]
	if valid and (best_sectors[_sector] < 0.0 or t < best_sectors[_sector]):
		best_sectors[_sector] = t
	sector_completed.emit(_sector, t, delta)
	_sector += 1
	_sector_start = time


func _finish_lap(time: float) -> void:
	last_lap = time
	var is_best := valid and (best_lap < 0.0 or time < best_lap)
	if is_best:
		best_lap = time
		_best_trace = _trace.duplicate()
		_best_trace.append(time) # the line
		_best_splits.clear()
		var split := 0.0
		for s in current_sectors:
			split += s
			_best_splits.append(split)
	lap_completed.emit(time, valid, is_best)
