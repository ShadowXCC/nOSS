extends SceneTree
## Conformance runner (docs/PLATFORMS.md §5, PLT-06): drives every official platform through
## the standard maneuvers across its geometry grid, and checks that each metric stays within
## 2% of the platform's reference geometry. Writes conformance.csv and summary.json to
## tests/conformance/out/. Exits 1 on any failure.
## Then the weather (ENV-02): each platform's reference config dry, wet and under snow, with the
## wet cornering grip and braking distance checked against dry (summary.json's "weather").
##   tools/run_conformance.sh [--quick] [--platform=official.track.gt] [--no-weather]

const Grid := preload("res://tests/conformance/conformance_grid.gd")
const TRACK := "res://content/tracks/proving_ground/track.json"
const OUT_DIR := "res://tests/conformance/out"
const TOLERANCE_PCT := 2.0
## Absolute tolerances for metrics whose reference value is small (half a physics tick).
const FLOORS := { "yaw_rise_s": 0.004 }
const COLUMNS := ["platform", "platform_hash", "config", "wheelbase", "track", "radius", "fit_notes", "maneuver", "metric", "value", "ref", "delta_pct", "pass", "error"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true # autoloads and script classes exist from the first frame on
	quit(_run())
	return false


func _run() -> int:
	var args := _args()
	var quick := args.has("quick")
	var only: String = args.get("platform", "")
	var threads := int(args.get("threads", "0"))
	var track := TrackData.load_file(TRACK)
	var points := PackedVector2Array()
	for p in track.samples:
		points.append(Vector2(p.x, p.z))
	var options := { "track": points, "track_width": track.width, "track_start_s": track.start_m }

	var rows: Array[Dictionary] = []
	var summary := { "quick": quick, "tolerance_pct": TOLERANCE_PCT, "platforms": {} }
	var failures := 0
	var t0 := Time.get_ticks_msec()
	for path in PlatformLoader.list_official():
		var loaded := PlatformLoader.load_file(path)
		if not loaded.ok():
			print("FAIL %s: %s" % [path, loaded.errors[0]])
			failures += 1
			continue
		var platform := loaded.platform
		if only and platform.id != only:
			continue
		var report := _run_platform(platform, loaded.hash, options, quick, threads, rows)
		summary.platforms[platform.id] = report
		failures += int(report.failed)
		print("%s %s: %d configs, %d checks, %d failed, worst %s %+.2f%% (%s), %d ms" % [
			"PASS" if report.failed == 0 else "FAIL", platform.id, report.configs, report.checks,
			report.failed, report.worst_metric, report.worst_pct, report.worst_config, report.ms])
		for line: String in report.failures.slice(0, 12):
			print("  ", line)
		if not args.has("no-weather"):
			var weather := _weather(platform, options, threads)
			summary.platforms[platform.id].weather = weather
			failures += int(not weather.pass)
			print("%s %s weather: skidpad wet %.2fx, snow %.2fx; braking wet %.2fx, snow %.2fx; lap wet %.2fx" % [
				"PASS" if weather.pass else "FAIL", platform.id, weather.lat_g_wet, weather.lat_g_snow,
				weather.braking_wet, weather.braking_snow, weather.lap_wet])
	summary.failed = failures
	summary.ms = Time.get_ticks_msec() - t0
	_write(rows, summary)
	print("%s: %d failed, %d ms. Report: tests/conformance/out/" % ["PASS" if failures == 0 else "FAIL", failures, summary.ms])
	return 1 if failures else 0


func _run_platform(platform: Dictionary, platform_hash: String, track_options: Dictionary, quick: bool, threads: int, rows: Array[Dictionary]) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var configs := Grid.configs(platform, quick)
	# Braking and step steer run at 100 km/h, or lower on a platform that can't hold it.
	var options := track_options.duplicate()
	var test_kmh := _test_speed(platform, configs[0])
	options.brake_speed = test_kmh
	options.step_speed = test_kmh / 3.6
	var jobs := []
	var index := []
	var arcade := GameModes.arcade(GameModes.mode_for(platform.id)) # kart platforms drive with their layer
	for config in configs:
		var fitted := Fitting.fit(platform, config.fit, config.get("mode", "normal"))
		var geometry := { "ground_y": fitted.ground_y, "wheels": fitted.physics_wheels }
		for maneuver in NossConformance.maneuvers():
			jobs.append({ "platform": platform, "geometry": geometry, "maneuver": maneuver, "options": options, "arcade": arcade })
			index.append([config, maneuver, fitted])
	var results := NossConformance.run_batch(jobs, threads)

	var ref := {}
	for i in results.size():
		if index[i][0].id == "ref":
			ref[index[i][1]] = results[i]
	var report := { "configs": configs.size(), "checks": 0, "failed": 0, "worst_pct": 0.0, "worst_metric": "-", "worst_config": "-", "failures": [] }
	for i in results.size():
		var config: Dictionary = index[i][0]
		var maneuver: String = index[i][1]
		var fitted: Fitting.Result = index[i][2]
		var result: Dictionary = results[i]
		var base := {
			"platform": platform.id, "platform_hash": platform_hash, "config": config.id,
			"wheelbase": fitted.wheelbase, "track": fitted.track, "radius": fitted.wheels[0].radius,
			"fit_notes": " / ".join(fitted.notes), "maneuver": maneuver,
		}
		if not result.ok:
			report.failed += 1
			report.failures.append("%s %s: %s" % [config.id, maneuver, result.error])
			rows.append(base.merged({ "pass": false, "error": result.error }))
			continue
		var ref_result: Dictionary = ref.get(maneuver, {})
		for metric: String in result.metrics:
			var value: Variant = result.metrics[metric]
			var ref_value: Variant = ref_result.metrics.get(metric) if ref_result.get("ok", false) else null
			var check := _compare(metric, value, ref_value)
			report.checks += 1
			if not check.pass:
				report.failed += 1
				report.failures.append("%s %s.%s: %s vs %s (%+.2f%%)" % [config.id, maneuver, metric, value, ref_value, check.delta])
			if absf(check.delta) > absf(report.worst_pct):
				report.worst_pct = check.delta
				report.worst_metric = maneuver + "." + metric
				report.worst_config = config.id
			rows.append(base.merged({ "metric": metric, "value": value, "ref": ref_value, "delta_pct": check.delta, "pass": check.pass }))
	report.ms = Time.get_ticks_msec() - t0
	return report


## The reference config's skidpad, braking and lap dry, wet and under snow (ENV-02, M9's "rain
## measurably lowers grip"). Ratios are wet (or snow) over dry; wet must lose at least 10% of the
## cornering grip (on a 30 m circle, so karts reach their grip before their top speed), brake at
## least 5% longer (brake torque, not grip, stops some light cars) and lap slower; snow more so.
static func _weather(platform: Dictionary, track_options: Dictionary, threads: int) -> Dictionary:
	var ref: Dictionary = Grid.configs(platform, true)[0]
	var fitted := Fitting.fit(platform, ref.fit, ref.get("mode", "normal"))
	var geometry := { "ground_y": fitted.ground_y, "wheels": fitted.physics_wheels }
	var arcade := GameModes.arcade(GameModes.mode_for(platform.id))
	var test_kmh := _test_speed(platform, ref)
	var jobs := []
	var conditions := [{}, { "wetness": 1.0 }, { "snow": 1.0 }]
	for c: Dictionary in conditions:
		var options := track_options.merged(c).merged({ "brake_speed": test_kmh, "skidpad_radius": 30.0 })
		for maneuver in ["skidpad", "braking", "lap"]:
			jobs.append({ "platform": platform, "geometry": geometry, "maneuver": maneuver, "options": options, "arcade": arcade })
	var results := NossConformance.run_batch(jobs, threads)
	var value := func(i: int, metric: String) -> float:
		return float(results[i].metrics.get(metric, NAN)) if results[i].ok else NAN
	var brake_metric := "d_%d_0_m" % int(test_kmh)
	var out := {
		"lat_g": [value.call(0, "lat_g"), value.call(3, "lat_g"), value.call(6, "lat_g")],
		"braking_m": [value.call(1, brake_metric), value.call(4, brake_metric), value.call(7, brake_metric)],
		"lap_s": [value.call(2, "lap_s"), value.call(5, "lap_s"), value.call(8, "lap_s")],
	}
	out.lat_g_wet = out.lat_g[1] / out.lat_g[0]
	out.lat_g_snow = out.lat_g[2] / out.lat_g[0]
	out.braking_wet = out.braking_m[1] / out.braking_m[0]
	out.braking_snow = out.braking_m[2] / out.braking_m[0]
	out.lap_wet = out.lap_s[1] / out.lap_s[0]
	out.pass = out.lat_g_wet < 0.9 and out.braking_wet > 1.05 and out.lap_wet > 1.03 \
		and out.lat_g_snow < out.lat_g_wet and out.braking_snow > out.braking_wet
	return out


## 100 km/h, or 85% of the reference config's top speed rounded down to 10 km/h.
static func _test_speed(platform: Dictionary, ref: Dictionary) -> float:
	var fitted := Fitting.fit(platform, ref.fit)
	var job := { "platform": platform, "geometry": { "ground_y": fitted.ground_y, "wheels": fitted.physics_wheels }, "maneuver": "top_speed", "options": {} }
	var top: Variant = NossConformance.run_batch([job], 1)[0].metrics.get("v_60s_kmh")
	return minf(100.0, floorf(0.85 * float(top) / 10.0) * 10.0) if top != null else 100.0


## {delta (percent), pass}. Not reached on both sides passes; on one side fails.
static func _compare(metric: String, value: Variant, ref_value: Variant) -> Dictionary:
	if value == null and ref_value == null:
		return { "delta": 0.0, "pass": true }
	if value == null or ref_value == null:
		return { "delta": 999.0, "pass": false }
	var delta := (float(value) - float(ref_value)) / maxf(absf(float(ref_value)), 1e-9) * 100.0
	var ok: bool = absf(delta) <= TOLERANCE_PCT or absf(float(value) - float(ref_value)) <= float(FLOORS.get(metric, 0.0))
	return { "delta": delta, "pass": ok }


func _write(rows: Array[Dictionary], summary: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	# Keep Godot from importing the CSV as a translation.
	FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	var csv := FileAccess.open(dir.path_join("conformance.csv"), FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(COLUMNS))
	for row in rows:
		var line := PackedStringArray()
		for column: String in COLUMNS:
			var v: Variant = row.get(column, "")
			line.append("" if v == null else ("%.6f" % v) if v is float else str(v))
		csv.store_csv_line(line)
	csv.close()
	var json := FileAccess.open(dir.path_join("summary.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify(summary, "  ", true) + "\n")
	json.close()


static func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
