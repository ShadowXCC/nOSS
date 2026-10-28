extends GdUnitTestSuite
## The AI's racing line and speed profile (AI-01): inside the road, smoother than the
## centreline, and target speeds a platform can drive.

const TRACK := "res://content/tracks/proving_ground/track.json"


func test_line_stays_on_the_road_and_bends_less_than_the_centreline() -> void:
	var t := TrackData.load_file(TRACK)
	var line := RacingLine.for_track(t)
	var peak_line := 0.0
	var peak_centre := 0.0
	for i in t.samples.size():
		var limit := t.width / 2.0 - RacingLine.EDGE_MARGIN + (RacingLine.CURB_USE if t.curbs[i] else 0.0)
		assert_float(absf(line.offsets[i])).is_less_equal(limit + 0.001)
		peak_line = maxf(peak_line, absf(line.curvature[i]))
		peak_centre = maxf(peak_centre, absf(t.curvature[i]))
	assert_float(peak_line).is_less(peak_centre * 0.9)
	# Same turning direction as the centreline overall.
	var agree := 0.0
	for i in t.samples.size():
		agree += line.curvature[i] * t.curvature[i]
	assert_float(agree).is_greater(0.0)


func test_line_is_solved_once_per_track() -> void:
	var t := TrackData.load_file(TRACK)
	assert_object(RacingLine.for_track(t)).is_same(RacingLine.for_track(TrackData.load_file(TRACK)))


func test_speed_profile_is_drivable_and_follows_grip() -> void:
	var t := TrackData.load_file(TRACK)
	var line := RacingLine.for_track(t)
	var gt := PlatformLoader.load_official("official.track.gt").platform
	var full := line.speed_profile(gt, 1.0)
	var less := line.speed_profile(gt, 0.85)
	var lap := line.lap_time(full)
	assert_float(lap).is_between(55.0, 80.0)
	assert_float(line.lap_time(less)).is_greater(lap)
	for i in full.size():
		assert_float(full[i]).is_greater(10.0)
		assert_float(full[i]).is_less_equal(RacingLine.MAX_SPEED)
	# A faster class laps faster.
	var formula := PlatformLoader.load_official("official.track.formula").platform
	assert_float(line.lap_time(line.speed_profile(formula, 1.0))).is_less(lap)


func test_braking_is_limited_by_the_brake_balance() -> void:
	var gt := PlatformLoader.load_official("official.track.gt").platform
	var mu := float(gt.tires.mu_peak)
	var balanced := RacingLine.max_braking(gt, mu)
	assert_float(balanced).is_less(mu * RacingLine.GRAVITY)
	# More front bias: the rear lasts longer, so it brakes harder.
	var front := gt.duplicate(true)
	front.brakes.bias_front = 0.7
	assert_float(RacingLine.max_braking(front, mu)).is_greater(balanced)


## A stadium oval turning left: 400 m straights, 150 m radius ends, every height given.
static func _oval(defaults: Dictionary) -> TrackData:
	var points := []
	for end in [1.0, -1.0]: # the top straight and right end, then the bottom and left
		for x in [-200.0, -100.0, 0.0, 100.0, 200.0]:
			points.append({ "p": [x * end, 0.0, 150.0 * end] })
		for deg in [30.0, 60.0, 90.0, 120.0, 150.0]:
			var a := deg_to_rad(deg)
			points.append({ "p": [(200.0 + 150.0 * sin(a)) * end, 0.0, 150.0 * cos(a) * end] })
	var d := TrackFormat.blank("oval", "Oval")
	d.road.points = points
	d.road.defaults.merge({ "height": "set", "curb_l": "off", "curb_r": "off" }, true)
	d.road.defaults.merge(defaults, true)
	return TrackData.from_dict(d)


## On banking, a move along the road is a shorter move across the map (cos(bank)). The line on a
## 24°, 31° or 45° oval must be the line a flat oval of the same plan-view width gets.
func test_banked_line_matches_the_flat_line_seen_from_above() -> void:
	for deg in [24.0, 31.0, 45.0]:
		var bank := deg_to_rad(deg)
		var half := 8.0
		var flat_half := (half - RacingLine.EDGE_MARGIN) * cos(bank) + RacingLine.EDGE_MARGIN
		var banked := _oval({ "width_l": half, "width_r": half, "bank_deg": -deg })
		var flat := _oval({ "width_l": flat_half, "width_r": flat_half })
		var mean := 0.0
		for c in banked.curvature:
			mean += c
		assert_float(mean).is_greater(0.0) # turning left
		var a := RacingLine.solve(banked)
		var b := RacingLine.solve(flat)
		assert_bool(a.flat).is_false()
		var worst := 0.0
		for i in banked.samples.size():
			var pa := Vector2(a.points[i].x, a.points[i].z)
			var pb := Vector2(b.points[i].x, b.points[i].z)
			worst = maxf(worst, pa.distance_to(pb))
			assert_float(absf(a.offsets[i])).is_less_equal(half - RacingLine.EDGE_MARGIN + 0.001)
		assert_float(worst).override_failure_message("%.0f°: %.3f m off" % [deg, worst]).is_less(0.02)


## Steeper banking in the turns holds a car in them at more speed, all the way to the 45° cap,
## and the speed found is the corner's limit: grip to spare just under it, none just over. (Loaded
## tires grip less; passing the load to the grip and back three times once swung past the answer,
## so 38° came out slower than 31°.)
func test_steeper_banking_corners_faster() -> void:
	var car := PlatformLoader.load_official("official.track.stock_car").platform
	var mu := float(car.tires.mu_peak) * RacingLine.GRIP_SHARE
	var sensitivity := float(car.tires.load_sensitivity) * RacingLine.LOAD_SPREAD
	var downforce := 0.5 * RacingLine.AIR_DENSITY * -(float(car.aero.cl_a_front) + float(car.aero.cl_a_rear)) / float(car.mass.kg)
	for radius: float in [150.0, 300.0]:
		var k := 1.0 / radius
		var last := 0.0
		for deg in range(0, 46):
			var b := deg_to_rad(deg)
			var v := RacingLine._corner_speed(k, b, mu, sensitivity, downforce)
			assert_float(v).override_failure_message("%.0f m, %d°: %.1f m/s after %.1f" % [radius, deg, v, last]).is_greater_equal(last)
			last = v
			if v < RacingLine.MAX_SPEED:
				var spare := func(u: float) -> float: return RacingLine._corner_spare(u, k, cos(b), sin(b), mu, sensitivity, downforce)
				assert_float(spare.call(v - 0.05)).is_greater_equal(0.0)
				assert_float(spare.call(v + 0.05)).is_less(0.0)


## Drafting (D208): less drag laps faster; the ceiling (corners and braking only) is never under
## the profile.
func test_less_drag_laps_faster_and_the_ceiling_is_above() -> void:
	var t := TrackData.load_file(TRACK)
	var line := RacingLine.for_track(t)
	var car := PlatformLoader.load_official("official.track.stock_car").platform
	var plain := line.speed_profile(car, 1.0)
	assert_object(line.speed_profile(car, 1.0, 1.0)).is_same(plain) # the same profile, cached
	var drafted := line.speed_profile(car, 1.0, 0.7)
	assert_float(line.lap_time(drafted)).is_less(line.lap_time(plain))
	var ceiling := line.ceiling(car, 1.0)
	for i in plain.size():
		assert_float(ceiling[i]).is_greater_equal(plain[i] - 0.001)
