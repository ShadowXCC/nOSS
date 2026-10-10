extends GdUnitTestSuite
## Built-in engine sound profiles and the player (docs/ART_AUDIO.md §6, AV-05, AV-06).


func test_four_built_in_profiles() -> void:
	var ids := EngineSound.profiles().map(func(p: Array) -> String: return p[0])
	assert_array(ids).contains_exactly_in_any_order(["i4", "v8_crossplane", "flat6", "ev"])
	for id: String in ids:
		var entry := EngineSound._load_profile(id)
		for emitter in EngineSound.EMITTERS:
			var loops: Dictionary = entry.loops[emitter]
			assert_int(loops.on.size()).is_equal(loops.rpm.size())
			assert_int(loops.off.size()).is_equal(loops.rpm.size())
			var wav: AudioStreamWAV = loops.on[0]
			assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
			assert_int(wav.data.size()).is_greater(10000)


func test_player_follows_rpm_and_load() -> void:
	var sound := EngineSound.new()
	sound.manual = { "rpm": 950.0, "load": 0.0, "throttle": 0.0, "speed": 0.0, "idle": 950.0, "redline": 8000.0 }
	sound.set_profile({ "schema": "noss.sound/1", "base": "flat6", "tweaks": { "pitch": 1.1, "turbo": "twin" } })
	add_child(sound)
	sound._process(0.1)
	var exhaust: Dictionary = sound._layers.exhaust
	var low_pitch: float = exhaust.slots.on[0].player.pitch_scale
	sound.manual.rpm = 7000.0
	sound.manual.load = 1.0
	sound.manual.throttle = 1.0
	for i in 30:
		sound._process(0.05)
	var playing: Array = exhaust.slots.on.filter(func(s: Dictionary) -> bool: return s.player.volume_db > -40.0)
	assert_int(playing.size()).is_greater(0)
	assert_float(playing[0].player.pitch_scale).is_greater(0.5)
	assert_float(sound._extra_players.turbo.volume_db).is_greater(-40.0) # boost whistle with load
	assert_float(low_pitch).is_greater(0.0)
	sound.free()


func test_unknown_profile_falls_back() -> void:
	var sound := EngineSound.new()
	sound.set_profile({ "schema": "noss.sound/1", "base": "w16_quad_turbo" })
	assert_str(sound._profile.id).is_equal(EngineSound.DEFAULT_PROFILE)
	sound.free()
