extends Node
## Endless check (M9 acceptance 1): an autodriven endless drive, headless at a fixed 120 Hz.
##   tools/endless_check.sh [--minutes=10] [--code=FOREST-0000007 | --seed=n --biome=1] [--traffic=light] [--lanes=2|4] [--side=right|left]
##                          [--players=1] [--no-rebase] [--weather=..] [--time=..] [--verbose] [--windowed]
## Fails on:
## - precision: each tick the car's centre of mass must move by its velocity × dt, give or take the
##   32-bit float's step where it is. Near the origin that's under 0.1 mm; far out (no floating
##   origin) it grows to centimetres. The RMS over the last 10 minutes must stay under PRECISION_M.
## - a rebase that changes the car's velocity (it must carry on as if nothing happened).
## - memory: static memory growing more than MEMORY_MB_PER_H after the first 10 minutes, orphan
##   nodes piling up, or world pieces built and not freed; drawn (--windowed), video memory growing
##   more than VIDEO_MB_PER_H after the first 10 minutes.
## - the car stuck (under 2 m/s) for STUCK_S, or the world not built where the car is.

const PRECISION_M := 0.0005
const REBASE_DV := 0.5
const MEMORY_MB_PER_H := 40.0
const VIDEO_MB_PER_H := 40.0
const WARMUP_MIN := 10.0
const STUCK_S := 30.0
const SAMPLE_S := 60.0

var opts := { "minutes": "10", "traffic": "light", "players": "1", "seed": "7", "biome": "1" }
var session: TrackSession
var time := 0.0
var started := false
var done := false
var _last_com := Vector3.ZERO
var _last_shifts := 0
var _last_resets := 0
var _have_last := false
var _residuals: Array = [] # per minute: [sum of squares, count]
var _rebase_dv := 0.0
var _rebases := 0
var _resets := 0
var _stuck := 0.0
var _stuck_events := 0
var _not_built := 0
var _memory: Array = [] # [minute, static MB, objects, nodes, orphans, video MB, texture MB]
var _next_sample := 0.0
var _start_d := 0.0
var _max_scene := 0.0
var _frame_us := 0
var _frames: PackedFloat32Array = []
var _v_before := Vector3.ZERO


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	get_tree().physics_frame.connect(_tick)
	_start.call_deferred()


func _start() -> void:
	Settings.use_folder("user://tests/endless_check")
	Players.clear()
	var e := RaceEvent.endless(int(opts.seed), int(opts.biome))
	if opts.has("code"):
		var d := EndlessCode.decode(String(opts.code))
		if not d.is_empty():
			e = RaceEvent.endless(int(d.seed), int(d.biome))
	e.endless_traffic = String(opts.traffic) if String(opts.traffic) in RaceEvent.CHOICES.endless_traffic else "light"
	e.lanes = 4 if int(opts.get("lanes", "2")) >= 4 else 2
	e.drive_side = "left" if opts.get("side") == "left" else "right"
	session = TrackSession.new()
	session.platform_id = String(opts.get("platform", "official.endless.cruiser"))
	session.event = e
	session.autodrive = true
	session.ai_players = int(opts.players) - 1
	add_child(session)
	print("Endless: %s, %s traffic, %d lanes on the %s, %s players, %s min%s" % [EndlessCode.encode(e.road_seed, e.biome), e.endless_traffic, e.lanes, e.drive_side, opts.players, opts.minutes,
		", no floating origin (the negative control)" if opts.has("no-rebase") else ""])


func _tick() -> void:
	if done or session == null or not session.is_inside_tree():
		return
	var now_us := Time.get_ticks_usec()
	if _frame_us > 0 and started:
		_frames.append(float(now_us - _frame_us) / 1000.0)
	_frame_us = now_us
	if not started:
		if not session.players.is_empty() and session.players.all(func(p: SessionPlayer) -> bool: return p.vehicle != null):
			started = true
			if opts.has("no-rebase"):
				session.origin.enabled = false
			_start_d = session.players[0].distance
			_last_resets = session.players[0].vehicle.reset_count
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	time += dt
	var p := session.players[0]
	var v := p.vehicle
	var com := v.global_transform * v.center_of_mass
	var shifts := session.origin.shifts
	var resets := v.reset_count
	var vel := v.linear_velocity
	if _have_last and shifts == _last_shifts and resets == _last_resets and not p.waiting:
		var residual := ((com - _last_com) - vel * dt).length()
		var minute := int(time / 60.0)
		while _residuals.size() <= minute:
			_residuals.append([0.0, 0])
		_residuals[minute][0] += residual * residual
		_residuals[minute][1] += 1
	if shifts != _last_shifts and _have_last:
		_rebases += 1
		_rebase_dv = maxf(_rebase_dv, (vel - _v_before).length())
	if resets != _last_resets:
		_resets += 1
	_v_before = vel
	_last_com = com
	_last_shifts = shifts
	_last_resets = resets
	_have_last = true
	_max_scene = maxf(_max_scene, Vector2(com.x, com.z).length())
	# Stuck, or off the built world.
	_stuck = _stuck + dt if p.speed < 2.0 else 0.0
	if _stuck > STUCK_S:
		_stuck_events += 1
		_stuck = 0.0
		print("  stuck at %.0f m (%.1f min)" % [p.distance, time / 60.0])
	if int(time * 120.0) % 120 == 0 and not session.endless_world.built_at(p.distance):
		_not_built += 1
	if time >= _next_sample:
		_next_sample += SAMPLE_S
		_memory.append([time / 60.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		if opts.has("verbose"):
			var m: Array = _memory[-1]
			print("  %3.0f min %6.1f km  mem %.1f MB  video %.1f MB  objects %d  nodes %d  world %s  rms %.3f mm" % [m[0], (p.distance - _start_d) / 1000.0, m[1], m[5],
				m[2], m[3], session.endless_world.counts(), _rms(int(time / 60.0) - 1) * 1000.0])
	if time >= float(opts.minutes) * 60.0:
		done = true
		_report()


func _rms(minute: int) -> float:
	if minute < 0 or minute >= _residuals.size() or int(_residuals[minute][1]) == 0:
		return 0.0
	return sqrt(float(_residuals[minute][0]) / float(_residuals[minute][1]))


func _rms_over(from_min: int, to_min: int) -> float:
	var sum := 0.0
	var n := 0
	for m in range(maxi(from_min, 0), mini(to_min, _residuals.size())):
		sum += float(_residuals[m][0])
		n += int(_residuals[m][1])
	return sqrt(sum / maxf(n, 1))


## Least-squares slope of a memory column (static: 1, video: 5; MB per hour) after the warm-up.
func _memory_slope(col := 1) -> float:
	var pts := _memory.filter(func(m: Array) -> bool: return float(m[0]) >= WARMUP_MIN)
	if pts.size() < 3:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for m: Array in pts:
		mx += float(m[0])
		my += float(m[col])
	mx /= pts.size()
	my /= pts.size()
	var num := 0.0
	var den := 0.0
	for m: Array in pts:
		num += (float(m[0]) - mx) * (float(m[col]) - my)
		den += (float(m[0]) - mx) * (float(m[0]) - mx)
	return num / maxf(den, 1e-9) * 60.0


func _report() -> void:
	var p := session.players[0]
	var km := (p.distance - _start_d) / 1000.0
	var minutes := int(float(opts.minutes))
	var first := _rms_over(1, mini(11, minutes))
	var last := _rms_over(maxi(minutes - 10, 1), minutes)
	var w := session.endless_world
	var leaks: int = (w.stats.road - w.stats.freed_road) - w.counts().road + (w.stats.tiles - w.stats.freed_tiles) - w.counts().tiles \
		+ (w.stats.far - w.stats.freed_far) - w.counts().far
	var frames := Array(_frames)
	frames.sort()
	var p99: float = frames[int(frames.size() * 0.99)] if not frames.is_empty() else 0.0
	var mean := 0.0
	for f: float in frames:
		mean += f
	mean /= maxf(frames.size(), 1)
	var mem_first: Array = _memory[mini(int(WARMUP_MIN), _memory.size() - 1)] if not _memory.is_empty() else [0, 0, 0, 0, 0, 0, 0]
	var mem_last: Array = _memory[-1] if not _memory.is_empty() else [0, 0, 0, 0, 0, 0, 0]
	var slope := _memory_slope()
	var video_slope := _memory_slope(5)
	var drawn := float(mem_last[5]) > 0.0
	print("Endless: %.1f km in %d min (%.0f km/h on average), %d rebases, furthest from the scene's origin %.0f m" % [km, minutes, km / (minutes / 60.0), _rebases, _max_scene])
	print("  precision: rms %.4f mm in the first 10 min, %.4f mm in the last 10; largest velocity change at a rebase %.3f m/s" % [first * 1000.0, last * 1000.0, _rebase_dv])
	print("  memory: %.1f MB at %d min, %.1f MB at the end (%.1f MB/h after %d min); objects %d -> %d, nodes %d -> %d, orphans %d" % [mem_first[1], int(WARMUP_MIN),
		mem_last[1], slope, int(WARMUP_MIN), mem_first[2], mem_last[2], mem_first[3], mem_last[3], mem_last[4]])
	if drawn:
		print("  video memory: %.1f MB at %d min, %.1f MB at the end (%.1f MB/h after %d min); textures %.1f -> %.1f MB" % [mem_first[5], int(WARMUP_MIN),
			mem_last[5], video_slope, int(WARMUP_MIN), mem_first[6], mem_last[6]])
	print("  world: %s, built %s; resets %d, stuck %d, not built under the car %d" % [w.counts(), w.stats, _resets, _stuck_events, _not_built])
	print("Time %.0f s of driving: frames %.2f ms on average, p99 %.2f ms" % [time, mean, p99])
	var fails := PackedStringArray()
	if last > PRECISION_M:
		fails.append("precision: rms %.3f mm in the last 10 min (over %.3f mm)" % [last * 1000.0, PRECISION_M * 1000.0])
	if _rebase_dv > REBASE_DV:
		fails.append("a rebase changed the car's velocity by %.2f m/s" % _rebase_dv)
	if minutes > WARMUP_MIN + 5 and slope > MEMORY_MB_PER_H:
		fails.append("memory growing %.1f MB/h" % slope)
	if drawn and minutes > WARMUP_MIN + 5 and video_slope > VIDEO_MB_PER_H:
		fails.append("video memory growing %.1f MB/h" % video_slope)
	# Orphans: the traffic's car packages are kept out of the tree on purpose (copies are made from
	# them); what counts is more of them over time.
	var orphans_then := int(_memory[mini(1, _memory.size() - 1)][4]) if not _memory.is_empty() else 0
	if int(mem_last[4]) - orphans_then > 50:
		fails.append("%d more orphan nodes than at 1 min" % (int(mem_last[4]) - orphans_then))
	if leaks != 0:
		fails.append("%d world pieces built and never freed" % leaks)
	if _stuck_events > 0:
		fails.append("stuck %d times" % _stuck_events)
	if _not_built > 2:
		fails.append("no road built under the car %d times" % _not_built)
	if km < minutes * 0.6:
		fails.append("only %.1f km" % km)
	for f in fails:
		print("FAIL ", f)
	if fails.is_empty():
		print("PASS")
	get_tree().quit(1 if not fails.is_empty() else 0)
