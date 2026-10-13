extends Node
## Traffic bench (M7, D120): what one more car costs per 120 Hz physics tick, by kind, on flat
## ground. Sets the cap on traffic cars that become full physics cars near players.
##   tools/traffic_bench.sh [--cars=24] [--ticks=600] [--platform=official.highway.street]
## Kinds:
##   full       a Vehicle as players and AI drive it (visuals every tick), GDScript lane keeping
##   lite       the same without per-tick visuals (how promoted traffic runs)
##   kinematic  a remote-style kinematic car moved every tick (proxies, fallback boxes)
## Prints µs per car per tick for each kind, over an empty-world baseline (wall time per frame,
## headless at a fixed 120 fps, one tick a frame).

const KINDS := ["full", "lite", "kinematic"]
const SPEED := 30.0
const LANE_M := 4.0
const GAP_M := 14.0

var opts := { "cars": "24", "ticks": "600", "warmup": "240", "platform": "official.highway.street", "car": "res://content/cars/noss_box" }
var platform: PlatformLoader.Result
var pkg: VehiclePackage
var cars: Array[Vehicle] = []
var kind := ""
var results := {}
var _queue: Array = []
var _ticks := 0
var _sum := 0.0
var _last_us := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	platform = PlatformLoader.load_official(String(opts.platform))
	if not platform.ok():
		print("FAIL: platform " + String(opts.platform))
		get_tree().quit(1)
		return
	pkg = PackageLoader.load_package(String(opts.car))
	if pkg == null:
		print("FAIL: car " + String(opts.car))
		get_tree().quit(1)
		return
	_ground()
	_queue = ["base"] + KINDS
	get_tree().physics_frame.connect(_tick)
	_next.call_deferred()


func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Vehicle.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 40000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 19000.0)
	body.add_child(shape)
	add_child(body)


func _next() -> void:
	for v in cars:
		v.queue_free()
	cars.clear()
	if _queue.is_empty():
		_report()
		return
	kind = _queue.pop_front()
	var n := 0 if kind == "base" else int(opts.cars)
	for i in n:
		var v := Vehicle.create(platform, PackageLoader.copy(pkg))
		add_child(v)
		var lane := i % 6
		var row := i / 6
		v.reset_to(Transform3D(Basis(), Vector3((lane - 2.5) * LANE_M, 0.0, row * GAP_M)))
		v.linear_velocity = Vector3(0.0, 0.0, SPEED * 0.5)
		if kind == "kinematic":
			v.set_remote(true)
		elif kind == "lite":
			v.set_physics_process(false)
		cars.append(v)
	_ticks = 0
	_sum = 0.0


func _tick() -> void:
	if kind.is_empty():
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	for v in cars:
		if kind == "kinematic":
			var t := v.global_transform
			t.origin.z += SPEED * dt
			v.move_remote(Transform3D(t.basis, t.origin + t.basis.y * v.fitted.ground_y), Vector3(0, 0, SPEED), Vector3.ZERO)
			continue
		# Lane keeping and cruise: what the native lane driver will do, in a few lines.
		var lat := v.global_position.x - roundf(v.global_position.x / LANE_M - 0.5) * LANE_M - LANE_M * 0.5
		var heading := v.global_basis.z.x
		v.steer = clampf(lat * 0.08 + heading * 1.5, -1.0, 1.0)
		var speed := v.linear_velocity.z
		v.throttle = clampf((SPEED - speed) * 0.3, 0.0, 1.0)
		v.brake = clampf((speed - SPEED) * 0.3, 0.0, 1.0)
		if kind == "lite":
			v.sim.set_controls(v.steer, v.throttle, v.brake, 0.0, 0.0)
	_ticks += 1
	var warmup := int(opts.warmup)
	# Headless at a fixed 120 fps runs flat out, so the wall time between ticks is one frame's
	# whole cost (physics, scripts, the dummy renderer).
	var now := Time.get_ticks_usec()
	if _ticks > warmup:
		_sum += float(now - _last_us) / 1e6
	_last_us = now
	if _ticks >= warmup + int(opts.ticks):
		results[kind] = _sum / float(int(opts.ticks)) * 1e6
		_next.call_deferred()
		kind = ""


func _report() -> void:
	var base: float = results.get("base", 0.0)
	var n := float(int(opts.cars))
	print("Traffic bench: %d cars per kind, %s, %s, %d ticks" % [int(n), opts.platform, String(opts.car).get_file(), int(opts.ticks)])
	print("  empty world %.0f µs/tick" % base)
	for k in KINDS:
		var per: float = (results[k] - base) / n
		print("  %-10s %6.0f µs/tick total, %5.1f µs per car" % [k, results[k], per])
	var lite: float = (results["lite"] - base) / n
	var cap := "24 per game, 12 per player" if lite <= 40.0 else "12 per game, 6 per player" if lite <= 80.0 else "promote on contact only"
	print("Gate (lite %.1f µs, ≤40 / ≤80): %s; i7-7700 estimate %.0f µs per car" % [lite, cap, lite * 1.8])
	get_tree().quit(0)
