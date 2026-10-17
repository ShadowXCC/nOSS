extends GdUnitTestSuite
## Weather (D153): lightning within Reduce flashing's limit, strikes the same on every game, rain
## and snow boxes per player, the ambience following the weather.


## ACC-04: with Reduce flashing a strike is one soft pulse, so even a strike every second stays at
## one flash a second (the limit is three); without it, three quick flickers.
func test_calm_lightning_flashes_at_most_three_times_a_second() -> void:
	var calm := func(t: float) -> float: return Lightning.flash(fmod(t, 1.0), true)
	var full := func(t: float) -> float: return Lightning.flash(fmod(t, 1.0), false)
	assert_int(Flash.most_per_second(calm)).is_less_equal(int(Flash.CALM_MAX))
	assert_int(Flash.most_per_second(full)).is_greater(int(Flash.CALM_MAX)) # the full one does flicker
	var peak_calm := 0.0
	var peak_full := 0.0
	for ms in 1500:
		peak_calm = maxf(peak_calm, Lightning.flash(ms / 1000.0, true))
		peak_full = maxf(peak_full, Lightning.flash(ms / 1000.0, false))
	assert_float(peak_calm).is_less_equal(peak_full * 0.35)
	assert_float(Lightning.flash(-0.1, false)).is_equal(0.0)
	assert_float(Lightning.flash(2.0, true)).is_equal(0.0)


func test_strikes_come_from_the_seed() -> void:
	var count := 0
	for slot in 600:
		var a := Lightning.strike(42, slot, 1.0)
		assert_dict(a).is_equal(Lightning.strike(42, slot, 1.0))
		assert_dict(Lightning.strike(42, slot, 0.0)).is_empty()
		if not a.is_empty():
			count += 1
			assert_float(a.at).is_between(float(slot), float(slot) + 1.0)
			assert_float(a.distance).is_between(Lightning.NEAREST_M, Lightning.FARTHEST_M)
	# About CHANCE a second at full storm.
	assert_int(count).is_between(40, 110)


func test_a_bolt_mesh() -> void:
	var m := Lightning.bolt_mesh(7, 700.0)
	assert_int(m.get_surface_count()).is_equal(1)
	assert_float(m.get_aabb().size.y).is_greater(600.0)


func test_weather_boxes_per_player_and_shelter() -> void:
	var box: WeatherBox = auto_free(WeatherBox.create(1))
	assert_int(box.layers).is_equal(1 << (WeatherBox.FIRST_LAYER))
	box.set_weather(0.5, false, 1.0, false)
	assert_int(box.multimesh.visible_instance_count).is_equal(roundi(box.multimesh.instance_count * 0.5))
	assert_bool(box.visible).is_true()
	box.set_weather(1.0, true, 0.3, true) # under shelter: nothing
	assert_int(box.multimesh.visible_instance_count).is_equal(0)
	assert_bool(box.visible).is_false()
	assert_bool(box.snowing).is_true()
	var mask := WeatherBox.cull_mask_for(1, 0xFFFFF)
	for i in 4:
		var bit := 1 << (WeatherBox.FIRST_LAYER - 1 + i)
		assert_bool(mask & bit != 0).is_equal(i == 1)


func test_the_ambience_follows_its_levels() -> void:
	var a: Ambience = auto_free(Ambience.new())
	add_child(a)
	a.set_levels({ "rain": 1.0, "wind": 0.4 })
	for i in 30:
		a._process(0.1)
	assert_float(a.level("rain")).is_equal_approx(1.0, 0.01)
	assert_float(a.level("wind")).is_equal_approx(0.4, 0.01)
	a.set_levels({})
	for i in 30:
		a._process(0.1)
	assert_float(a.level("rain")).is_equal(0.0)
	for kind: String in Ambience.LOOPS:
		var s := Ambience.stream(kind)
		assert_int(s.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_float(s.get_length()).is_greater(2.0)
	assert_int(Ambience.stream("thunder").loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
