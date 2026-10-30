extends GdUnitTestSuite
## Built-in engine sound profiles and the player (docs/ART_AUDIO.md §6, AV-05, AV-06).


func test_built_in_profiles() -> void:
	var ids := EngineSound.profiles().map(func(p: Array) -> String: return p[0])
	assert_array(ids).contains_exactly_in_any_order(["i4", "v8_crossplane", "flat6", "ev", "two_stroke",
		"v12", "v10", "v8_flatplane", "i6", "v6", "i5", "flat4", "i3", "rotary", "diesel", "vtwin", "single"])
	for id: String in ids:
		var entry := EngineSound._load_profile(id)
		for emitter in EngineSound.EMITTERS:
			var loops: Dictionary = entry.loops[emitter]
			assert_int(loops.on.size()).is_equal(loops.rpm.size())
			assert_int(loops.off.size()).is_equal(loops.rpm.size())
			var wav: AudioStreamWAV = loops.on[0]
			assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
			assert_int(wav.data.size()).is_greater(10000)


func test_profiles_by_name() -> void:
	var names := EngineSound.profiles().map(func(p: Array) -> String: return p[1])
	var vs := names.filter(func(n: String) -> bool: return n.begins_with("V"))
	assert_array(vs).contains_exactly(["V6", "V8 cross-plane", "V8 flat-plane", "V10", "V12", "V-twin"])
	for i in names.size() - 1:
		assert_int(String(names[i]).naturalnocasecmp_to(names[i + 1])).is_less(0)


## Every profile file is well formed: the synth reads what it can and plays the rest as defaults.
func test_profile_files() -> void:
	for file in DirAccess.get_files_at(EngineSound.PROFILE_DIR):
		if not file.ends_with(".json"):
			continue
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EngineSound.PROFILE_DIR + file))
		assert_str(p.schema).is_equal("noss.sound_profile/1")
		assert_str(p.id).override_failure_message(file).is_equal(file.get_basename())
		assert_str(p.name).is_not_empty()
		var points: Array = p.rpm_points
		assert_int(points.size()).override_failure_message(file).is_equal(6)
		for i in points.size():
			assert_float(points[i]).override_failure_message(file).is_between(float(p.rpm_idle), float(p.rpm_max))
			if i > 0:
				assert_float(points[i]).override_failure_message(file).is_greater(points[i - 1])
		for key: String in p.mix:
			assert_array(EngineSound.EMITTERS).override_failure_message(file + ": " + key).contains([key])
		var synth: Dictionary = p.synth
		if synth.get("electric", false):
			continue
		var fire: Array = synth.fire_deg
		var bank: Array = synth.bank
		assert_int(bank.size()).override_failure_message(file).is_equal(fire.size())
		for i in fire.size():
			assert_float(fire[i]).override_failure_message(file).is_greater_equal(0.0)
			assert_float(fire[i]).override_failure_message(file).is_less(720.0)
			if i > 0:
				assert_float(fire[i]).override_failure_message(file).is_greater(fire[i - 1])
			assert_bool(bank[i] == 0 or bank[i] == 1).override_failure_message(file).is_true()


## The rotary, diesel and cylinder-spread keys are off at 0: the older sounds play as they did.
func test_character_keys_off_at_zero() -> void:
	var synth: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EngineSound.PROFILE_DIR + "flat6.json")).synth
	var zeros := synth.duplicate()
	zeros.merge({ "pulse_hold_deg": 0, "knock": 0.0, "cyl_spread": 0.0 })
	for emitter in EngineSound.EMITTERS:
		for load in [0.0, 1.0]:
			var a: Dictionary = NossAudio.render_loop(synth, 3100.0, load, emitter, 0.5)
			var b: Dictionary = NossAudio.render_loop(zeros, 3100.0, load, emitter, 0.5)
			assert_bool(a.data == b.data).override_failure_message(emitter).is_true()
	var spread := synth.duplicate()
	spread.cyl_spread = 0.2
	assert_bool(NossAudio.render_loop(spread, 3100.0, 1.0, "exhaust", 0.5).data == NossAudio.render_loop(synth, 3100.0, 1.0, "exhaust", 0.5).data).is_false()


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
