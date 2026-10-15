class_name PerfLog
extends Node
## Dev (--perf-log, M7 acceptance 1): how this game ran, as one line every SUMMARY_S and at exit:
##   PERF_LOG frames=… avg=…ms p95=… p99=… fps_avg=… physics_avg=…ms physics_p95=… owned_max=…
## Frame times from the start of a session on (menus and loading don't count); owned_max is the
## most highway traffic cars this game drove at once (online: those it owned).

const SUMMARY_S := 30.0

var _frames := PackedFloat32Array()
var _physics := PackedFloat32Array()
var _owned_max := 0
var _since := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var session := get_tree().current_scene as TrackSession
	if session == null or session.players.is_empty():
		return
	_frames.append(delta * 1000.0)
	_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if session.traffic:
		var owned := session.net.traffic_owned.size() if session.net else session.traffic.cars.size()
		_owned_max = maxi(_owned_max, owned)
	_since += delta
	if _since >= SUMMARY_S:
		_since = 0.0
		print(summary())


func _exit_tree() -> void:
	if not _frames.is_empty():
		print(summary())


## The line, from everything so far.
func summary() -> String:
	var f := Array(_frames)
	var ph := Array(_physics)
	f.sort()
	ph.sort()
	var avg := _mean(f)
	return "PERF_LOG frames=%d avg=%.2fms p95=%.2fms p99=%.2fms fps_avg=%.1f physics_avg=%.2fms physics_p95=%.2fms owned_max=%d" % [
		f.size(), avg, _at(f, 0.95), _at(f, 0.99), 1000.0 / maxf(avg, 0.001), _mean(ph), _at(ph, 0.95), _owned_max]


static func _mean(a: Array) -> float:
	var total := 0.0
	for x: float in a:
		total += x
	return total / maxi(a.size(), 1)


static func _at(sorted: Array, q: float) -> float:
	return float(sorted[mini(int(sorted.size() * q), sorted.size() - 1)]) if not sorted.is_empty() else 0.0
