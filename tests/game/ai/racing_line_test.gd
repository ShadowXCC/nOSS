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
