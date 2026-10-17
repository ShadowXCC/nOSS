extends GdUnitTestSuite
## The sky's state (ENV-01…03, D153): a pure function of the settings and the clock.


func _state(time := "track", rate := 0, weather := "track", seed := 7, track_env := {}) -> EnvState:
	return EnvState.from_settings(time, rate, weather, seed, track_env, { "elevation_deg": 38, "azimuth_deg": 140 })


func test_the_track_default_is_the_fixed_sun_and_clear() -> void:
	var s := _state()
	var a := s.at(0.0)
	assert_float(a.hour).is_equal(-1.0)
	assert_float(a.elevation).is_equal(38.0)
	assert_float(a.azimuth).is_equal(140.0)
	assert_float(a.cloud).is_equal(0.0)
	assert_float(a.wetness).is_equal(0.0)
	# It stands still, whatever the time.
	assert_float(s.at(5000.0).elevation).is_equal(38.0)
	# The track's own block: its sun and weather.
	var t := _state("track", 0, "track", 7, { "sun_elevation_deg": 20.0, "weather": "rain" })
	assert_float(t.at(0.0).elevation).is_equal(20.0)
	assert_float(t.at(0.0).precip).is_greater(0.5)


func test_the_sun_follows_the_hour() -> void:
	var noon := EnvState.sun_position(12.0)
	assert_float(noon.x).is_equal_approx(55.0, 0.01)
	assert_float(noon.y).is_equal_approx(180.0, 0.01)
	assert_float(EnvState.sun_position(0.0).x).is_less(-30.0)
	assert_float(EnvState.sun_position(9.0).y).is_less(180.0) # morning: the east
	assert_float(EnvState.sun_position(15.0).y).is_greater(180.0)
	# Dawn rises: the sun climbs through the horizon between 5 and 6.
	assert_float(EnvState.sun_position(5.0).x).is_less(0.0)
	assert_float(EnvState.sun_position(6.5).x).is_greater(0.0)
	# Noon stands where the track's fixed sun does.
	var s := _state("noon")
	assert_float(s.at(0.0).azimuth).is_equal_approx(140.0 + EnvState.sun_position(12.5).y - 180.0, 0.001)


func test_time_runs_at_its_rate() -> void:
	var s := _state("morning", 60) # an hour a minute
	assert_float(s.at(0.0).hour).is_equal_approx(9.0, 1e-6)
	assert_float(s.at(60.0).hour).is_equal_approx(10.0, 1e-6)
	assert_float(s.at(60.0 * 15).hour).is_equal_approx(0.0, 1e-6) # round past midnight
	assert_float(_state("morning", 0).at(3600.0).hour).is_equal_approx(9.0, 1e-6)


func test_set_weather_is_steady_and_rain_starts_wet() -> void:
	var rain := _state("track", 0, "rain")
	assert_float(rain.at(0.0).wetness).is_equal(1.0)
	assert_float(rain.at(900.0).wetness).is_equal(1.0)
	var snow := _state("track", 0, "snow")
	assert_bool(snow.at(0.0).snowing).is_true()
	assert_float(snow.at(0.0).snow).is_equal(1.0)
	assert_float(snow.at(0.0).wetness).is_equal(0.0)
	var storm := _state("track", 0, "storm").at(10.0)
	assert_float(storm.storm).is_equal(1.0)
	assert_float(_state("track", 0, "fog").at(0.0).fog).is_equal(1.0)
	assert_float(_state("track", 0, "fog").at(0.0).wetness).is_equal(0.0)


## Changing weather: the same seed gives the same sky anywhere (a late joiner computes it the
## same), fronts come and go, and the road soaks and dries with them.
func test_changing_weather_is_the_same_from_the_same_seed() -> void:
	var a := _state("track", 0, "changing", 99)
	var b := _state("track", 0, "changing", 99)
	var c := _state("track", 0, "changing", 100)
	var kinds := {}
	var differs := false
	for i in 200:
		var t := i * 37.0
		var x := a.at(t)
		assert_dict(b.at(t)).is_equal(x)
		if c.at(t) != x:
			differs = true
		kinds[[x.cloud, x.precip, x.fog]] = true
	assert_bool(differs).is_true()
	assert_int(kinds.size()).is_greater(3) # several kinds of weather in two hours
	# Asked for in any order, a time gives the same answer.
	var late := _state("track", 0, "changing", 99)
	assert_dict(late.at(7000.0)).is_equal(a.at(7000.0))


func test_the_road_soaks_and_dries() -> void:
	var s := _state("track", 0, "changing", 3)
	var wettest := 0.0
	var dried := false
	var prev := -1.0
	for i in 2000:
		var w: float = s.at(i * 5.0).wetness
		wettest = maxf(wettest, w)
		if prev > 0.5 and w < prev:
			dried = true
		prev = w
	# Over almost three hours some rain falls and dries again (for this seed).
	assert_float(wettest).is_greater(0.6)
	assert_bool(dried).is_true()
