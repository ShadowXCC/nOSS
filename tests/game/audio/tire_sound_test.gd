extends GdUnitTestSuite
## Tire sounds (D90, docs/ART_AUDIO.md §7): built-in profiles picked per car, Squeal by default,
## Classic exactly the first nOSS tire tone, and the level following the slip.

## The first tire loop (0.5 s at 44.1 kHz), before tire sounds could be picked.
const CLASSIC_SHA := "0f43abe52361807afd119d21379371b02bd33bea3530d1502691391685aa7da7"


func test_built_in_tire_sounds() -> void:
	var list := EngineSound.tire_profiles()
	assert_str(list[0][0]).is_equal("squeal")
	assert_array(list.map(func(p: Array) -> String: return p[0])).contains_exactly_in_any_order(["squeal", "classic"])
	for p: Array in list:
		var entry := EngineSound._load_tire_profile(p[0])
		assert_array(JsonSchema.validate(entry.profile, JsonSchema.load_schema("tire_profile"))).is_empty()
		var loop: AudioStreamWAV = entry.squeal
		assert_int(loop.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	var squeal: AudioStreamWAV = EngineSound._load_tire_profile("squeal").squeal
	assert_int(squeal.data.size()).is_equal(int(44100 * 2.5) * 2)
	assert_object(EngineSound._load_tire_profile("squeal").scrub).is_not_null()
	assert_dict(EngineSound._load_tire_profile("../classic")).is_empty()


func test_classic_is_the_first_tire_sound() -> void:
	var loop: AudioStreamWAV = EngineSound._load_tire_profile("classic").squeal
	assert_str(PlatformLoader.sha256_hex(loop.data)).is_equal(CLASSIC_SHA)


func test_cars_get_squeal_unless_they_pick() -> void:
	var sound: EngineSound = auto_free(EngineSound.new())
	sound.set_profile({ "schema": "noss.sound/1", "base": "i4" })
	assert_str(sound._tire.id).is_equal("squeal")
	sound.set_profile({ "schema": "noss.sound/1", "base": "i4", "tires": { "base": "classic" } })
	assert_str(sound._tire.id).is_equal("classic")
	assert_object(sound._scrub.stream).is_null()
	sound.set_profile({ "schema": "noss.sound/1", "base": "i4", "tires": { "base": "rubber_duck" } })
	assert_str(sound._tire.id).is_equal("squeal")


func test_classic_follows_the_slip_as_before() -> void:
	var sound: EngineSound = auto_free(EngineSound.new())
	sound.set_profile({ "schema": "noss.sound/1", "base": "i4", "tires": { "base": "classic" } })
	sound._update_road({ "slip": 4.5 }, 0.016)
	# Then: squeal = (slip - 1.5) / 6, at 0.7 and pitch 0.9 + squeal * 0.25, at once.
	assert_float(sound._tires.volume_db).is_equal_approx(linear_to_db(0.5 * 0.7), 0.01)
	assert_float(sound._tires.pitch_scale).is_equal_approx(1.025, 0.001)


func test_squeal_comes_in_fast_and_fades_slowly() -> void:
	var sound: EngineSound = auto_free(EngineSound.new())
	sound.set_profile({ "schema": "noss.sound/1", "base": "i4" })
	for i in 3:
		sound._update_road({ "slip": 9.0, "lock": 1.0 }, 0.01)
	var up := sound._squeal
	var scrub := sound._scrubbing
	for i in 3:
		sound._update_road({ "slip": 0.0 }, 0.01)
	var down := sound._squeal
	assert_float(up).is_greater(0.6) # 30 ms in, at a 30 ms attack
	assert_float(scrub).is_greater(0.6)
	assert_float(down).is_greater(0.5) # 30 ms out, at a 160 ms release
	assert_float(down).is_less(up)
