extends SceneTree
## Checks the conformance harness against the game's own physics: a real Vehicle on Jolt
## (120 Hz) runs the launch and braking maneuvers on a flat plane, and the results must stay
## within 5% of NossConformance's flat-ground harness for the same platform and fit.
##   tools/godot.sh --headless --fixed-fps 120 -s res://tests/conformance/engine_check.gd

const PLATFORM := "official.track.gt"
const CAR := "res://content/cars/noss_box"
const TOLERANCE_PCT := 5.0
const KMH := 1.0 / 3.6

var _vehicle: Vehicle
var _phase := "settle"
var _t := 0.0
var _phase_t := 0.0
var _prev := {}
var _integral := 0.0
var _hold := 0.0
var _results := { "t_0_100_s": NAN, "d_100_0_m": NAN }
var _s100 := NAN


func _initialize() -> void:
	physics_interpolation = false
	var ground := StaticBody3D.new()
	ground.collision_layer = Vehicle.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 8000.0)
	shape.shape = box
	shape.position = Vector3(0, -1.0, 3900.0)
	ground.add_child(shape)
	root.add_child(ground)

	var loaded := PlatformLoader.load_official(PLATFORM)
	var pkg := PackageLoader.load_package(CAR)
	if not loaded.ok() or not pkg.ok():
		print("FAIL can't load the platform or car")
		quit(1)
		return
	_vehicle = Vehicle.create(loaded, pkg)
	root.add_child(_vehicle)
	_vehicle.reset_to(Transform3D.IDENTITY)


func _physics_process(delta: float) -> bool:
	if _vehicle == null:
		return true
	_t += delta
	_phase_t += delta
	var v := _vehicle.speed()
	_vehicle.steer = _steer()
	match _phase:
		"settle":
			if _phase_t > 0.5:
				_next("launch")
		"launch":
			_vehicle.throttle = 1.0
			if _prev.has("v") and _prev.v < 100.0 * KMH and v >= 100.0 * KMH:
				_results.t_0_100_s = _phase_t - delta * (v - 100.0 * KMH) / (v - _prev.v)
				_next("hold")
		"hold":
			# Steady at 102 km/h for 2 s with the gear frozen, as the harness does.
			var error := 102.0 * KMH - v
			_integral = clampf(_integral + 0.4 * error * delta, -0.5, 1.0)
			var u := 0.4 * error + _integral
			_vehicle.throttle = clampf(u, 0.0, 1.0)
			_vehicle.brake = clampf(-u * 0.5, 0.0, 1.0)
			if absf(error) < 0.5 * KMH and _hold == 0.0:
				_vehicle.sim.set_assists(true, true, false, true)
			if absf(error) < 0.5 * KMH or _hold > 0.0:
				_hold += delta
			if _hold >= 2.0:
				_next("brake")
		"brake":
			_vehicle.throttle = 0.0
			_vehicle.brake = 1.0
			var s := _vehicle.global_transform * _vehicle.center_of_mass
			if is_nan(_s100) and _prev.v >= 100.0 * KMH and v < 100.0 * KMH:
				_s100 = lerpf(_prev.s, s.z, (_prev.v - 100.0 * KMH) / (_prev.v - v))
			if _prev.v >= 0.5 and v < 0.5:
				_results.d_100_0_m = lerpf(_prev.s, s.z, (_prev.v - 0.5) / (_prev.v - v)) - _s100
				_finish()
				return true
	_prev = { "v": v, "s": (_vehicle.global_transform * _vehicle.center_of_mass).z }
	if _t > 120.0:
		print("FAIL timed out in ", _phase)
		quit(1)
		return true
	return false


func _next(phase: String) -> void:
	_phase = phase
	_phase_t = 0.0


## Holds the line x = 0 with the centre of mass, like the harness's driver on a straight.
func _steer() -> float:
	var com := _vehicle.global_transform * _vehicle.center_of_mass
	var forward := _vehicle.global_basis.z
	var heading := atan2(forward.x, forward.z)
	var v := maxf(_vehicle.speed(), 1.0)
	var look := 5.0 + 0.35 * v
	var kappa := -2.0 * (com.x + look * sin(heading)) / (look * look)
	var platform := _vehicle.platform
	var road := kappa * float(platform.geometry.wheelbase_m.ref)
	return clampf(-road / deg_to_rad(float(platform.steering.max_road_angle_deg)), -1.0, 1.0)


func _finish() -> void:
	var geometry := { "ground_y": _vehicle.fitted.ground_y, "wheels": _vehicle.fitted.wheels }
	var jobs := []
	for maneuver in ["launch", "braking"]:
		jobs.append({ "platform": _vehicle.platform, "geometry": geometry, "maneuver": maneuver, "options": {} })
	var harness := NossConformance.run_batch(jobs, 2)
	var expected := { "t_0_100_s": harness[0].metrics.get("t_0_100_s"), "d_100_0_m": harness[1].metrics.get("d_100_0_m") }
	var failed := 0
	for metric: String in _results:
		var ref: Variant = expected[metric]
		var got: float = _results[metric]
		var delta := (got - float(ref)) / float(ref) * 100.0 if ref != null else INF
		var ok := absf(delta) <= TOLERANCE_PCT
		failed += 0 if ok else 1
		print("%s engine %s: Jolt %.3f, harness %s (%+.2f%%)" % ["PASS" if ok else "FAIL", metric, got, ref, delta])
	quit(1 if failed else 0)
