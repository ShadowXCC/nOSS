extends GdUnitTestSuite
## Mounting models on a platform (docs/PLATFORMS.md §4.1, §4.3).

var _platform: Dictionary


func before() -> void:
	_platform = PlatformLoader.load_official("official.track.gt").platform


func test_in_range_model_is_unchanged() -> void:
	var r := Fitting.fit(_platform, _fit(2.55, 1.57))
	assert_float(r.scale).is_equal(1.0)
	assert_float(r.wheelbase).is_equal_approx(2.55, 0.001)
	assert_float(r.track).is_equal_approx(1.57, 0.001)
	assert_array(r.notes).is_empty()
	assert_vector(r.wheels[0].center).is_equal_approx(Vector3(0.785, 0.30, 1.275), Vector3.ONE * 0.001)


func test_long_model_is_scaled_down() -> void:
	var r := Fitting.fit(_platform, _fit(3.54, 2.0))
	assert_float(r.scale).is_equal_approx(2.95 / 3.54, 0.0001)
	assert_float(r.wheelbase).is_equal_approx(2.95, 0.001)
	assert_array(r.notes).contains(["Scaled to 83%"])
	assert_float(r.wheels[0].radius).is_equal_approx(0.3 * r.scale, 0.0001)


func test_narrow_track_moves_wheels_out() -> void:
	var r := Fitting.fit(_platform, _fit(2.6, 1.37))
	assert_float(r.track).is_equal_approx(1.45, 0.0001)
	assert_array(r.notes).contains(["Wheels moved 4 cm out"])
	var lf: Dictionary = r.wheels.filter(func(w: Dictionary) -> bool: return w.id == "LF")[0]
	var rf: Dictionary = r.wheels.filter(func(w: Dictionary) -> bool: return w.id == "RF")[0]
	assert_float(lf.center.x - rf.center.x).is_equal_approx(1.45, 0.0001)


func test_envelope_is_clamped_to_platform_box() -> void:
	var data := _fit(2.6, 1.6)
	data.envelope = { "min": [-1.5, -0.15, -3.0], "max": [1.5, 2.0, 3.0] }
	var r := Fitting.fit(_platform, data)
	assert_vector(r.envelope.size).is_equal_approx(Vector3(2.05, 1.45, 4.9), Vector3.ONE * 0.0001)
	assert_float(r.envelope.position.y).is_equal_approx(-0.15, 0.0001)


func test_model_transform_applies() -> void:
	var data := _fit(2.6, 1.6)
	data.model_transform = { "scale": 0.01, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] }
	for w: Dictionary in data.wheels:
		w.center = [w.center[0] * 100.0, w.center[1] * 100.0, w.center[2] * 100.0]
		w.radius *= 100.0
	var r := Fitting.fit(_platform, data)
	assert_float(r.wheelbase).is_equal_approx(2.6, 0.001)
	assert_float(r.wheels[0].radius).is_equal_approx(0.3, 0.0001)


func test_compatible_follows_accepts_families() -> void:
	assert_bool(Fitting.compatible(_platform, "car")).is_true()
	assert_bool(Fitting.compatible(_platform, "truck")).is_false()
	var kart := _platform.duplicate(true)
	kart.accepts_families = ["car", "open", "truck"]
	assert_bool(Fitting.compatible(kart, "truck")).is_true()
	kart.erase("accepts_families")
	assert_bool(Fitting.compatible(kart, "car")).is_true() # defaults to its own family


func test_ground_comes_from_the_wheels() -> void:
	var data := _fit(2.6, 1.6)
	data.ground_y = -0.05
	var r := Fitting.fit(_platform, data)
	assert_float(r.ground_y).is_equal_approx(0.0, 0.0001)
	assert_array(r.notes).contains(["Ground moved 5 cm"])


func _fit(wheelbase: float, track: float) -> Dictionary:
	var wheels := []
	for id in ["LF", "RF", "LR", "RR"]:
		var x := track / 2.0 * (1.0 if id[0] == "L" else -1.0)
		var z := wheelbase / 2.0 if id[1] == "F" else -wheelbase / 2.0
		wheels.append({ "id": id, "axle": 1 if id[1] == "F" else 2, "side": id[0], "center": [x, 0.30, z], "radius": 0.3, "width": 0.22 })
	return {
		"schema": "noss.fit/1",
		"model_transform": { "scale": 1.0, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] },
		"ground_y": 0.0, "wheel_mode": "model", "wheels": wheels,
		"envelope": { "min": [-0.9, 0.0, -2.2], "max": [0.9, 1.3, 2.2] },
	}
