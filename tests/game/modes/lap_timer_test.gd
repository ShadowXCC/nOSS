extends GdUnitTestSuite
## Lap timing: valid laps, sectors, checkpoints, shortcuts (MODE-01).

const DT := 1.0 / 120.0

var _timer: LapTimer
var _events: Array


func before_test() -> void:
	_timer = LapTimer.new()
	_timer.setup(1000.0, PackedFloat32Array([300.0, 650.0]), 100.0)
	_events = []
	_timer.lap_completed.connect(func(t: float, v: bool, b: bool) -> void: _events.append(["lap", t, v, b]))
	_timer.sector_completed.connect(func(s: int, t: float, d: float) -> void: _events.append(["sector", s, t, d]))
	_timer.invalidated.connect(func(r: String) -> void: _events.append(["invalid", r]))


## Drives at `speed` m/s from `from` for `distance` metres.
func _drive(from: float, distance: float, speed: float) -> float:
	var pos := from
	var travelled := 0.0
	while travelled < distance:
		var step := minf(speed * DT, distance - travelled)
		travelled += step
		pos = fposmod(pos + step, 1000.0)
		_timer.update(pos, DT, speed)
	return pos


func test_first_crossing_starts_lap_one() -> void:
	_drive(980.0, 30.0, 50.0)
	assert_int(_timer.lap).is_equal(1)
	assert_float(_timer.lap_time).is_less(0.25)


func test_full_lap_is_valid_and_timed() -> void:
	var pos := _drive(990.0, 20.0, 50.0) # start lap 1
	pos = _drive(pos, 1000.0, 50.0)
	var laps := _events.filter(func(e: Array) -> bool: return e[0] == "lap")
	assert_int(laps.size()).is_equal(1)
	assert_float(laps[0][1]).is_equal_approx(20.0, 0.02) # 1000 m at 50 m/s
	assert_bool(laps[0][2]).is_true()
	assert_bool(laps[0][3]).is_true()
	assert_float(_timer.best_lap).is_equal_approx(20.0, 0.02)
	var sectors := _events.filter(func(e: Array) -> bool: return e[0] == "sector")
	assert_int(sectors.size()).is_equal(3)
	assert_float(sectors[0][2]).is_equal_approx(6.0, 0.02)
	assert_float(sectors[1][2]).is_equal_approx(7.0, 0.02)
	assert_float(sectors[2][2]).is_equal_approx(7.0, 0.02)


func test_faster_lap_shows_negative_delta() -> void:
	var pos := _drive(990.0, 20.0, 50.0)
	pos = _drive(pos, 1000.0, 50.0)
	_events.clear()
	pos = _drive(pos, 1000.0, 60.0)
	var sectors := _events.filter(func(e: Array) -> bool: return e[0] == "sector")
	assert_float(sectors[0][3]).is_less(0.0)
	# Lap 2 started 10 m before the speed change.
	assert_float(_timer.best_lap).is_equal_approx(10.0 / 50.0 + 990.0 / 60.0, 0.02)


func test_shortcut_invalidates_lap() -> void:
	var pos := _drive(990.0, 20.0, 50.0)
	pos = _drive(pos, 200.0, 50.0)
	_timer.update(600.0, DT, 50.0) # jumps 380 m in one tick
	pos = _drive(600.0, 410.0, 50.0)
	var laps := _events.filter(func(e: Array) -> bool: return e[0] == "lap")
	assert_int(laps.size()).is_equal(1)
	assert_bool(laps[0][2]).is_false()
	assert_float(_timer.best_lap).is_equal(-1.0)


func test_reset_invalidates_and_next_lap_counts() -> void:
	var pos := _drive(990.0, 20.0, 50.0)
	pos = _drive(pos, 300.0, 50.0)
	_timer.invalidate("Reset")
	pos = _drive(pos, 700.0, 50.0)
	pos = _drive(pos, 1000.0, 50.0)
	var laps := _events.filter(func(e: Array) -> bool: return e[0] == "lap")
	assert_int(laps.size()).is_equal(2)
	assert_bool(laps[0][2]).is_false()
	assert_bool(laps[1][2]).is_true()


func test_wrong_way_detected() -> void:
	var pos := 500.0
	_timer.update(pos, DT, 20.0)
	for i in 300:
		pos -= 20.0 * DT
		_timer.update(pos, DT, 20.0)
	assert_bool(_timer.wrong_way).is_true()
