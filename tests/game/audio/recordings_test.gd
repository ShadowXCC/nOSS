extends GdUnitTestSuite
## Own engine recordings (AV-06): files are checked, travel inside the package, play over the
## built-in base, and are kept when the car is edited.

const DIR := "user://tests/recordings/"


func before() -> void:
	Settings.use_folder("user://tests/recordings")
	DirAccess.make_dir_recursive_absolute(DIR)


func after() -> void:
	Settings.use_folder("user://")


## A WAV file's bytes: `seconds` of a tone.
static func wav(rate := 44100, channels := 1, bits := 16, seconds := 0.5) -> PackedByteArray:
	var frames := int(rate * seconds)
	var block := channels * bits / 8
	var pcm := PackedByteArray()
	pcm.resize(frames * block)
	if bits == 16:
		for i in frames * channels:
			pcm.encode_s16(i * 2, int(sin(TAU * 200.0 * (i / channels) / rate) * 12000))
	var out := "RIFF".to_ascii_buffer()
	var n := PackedByteArray()
	n.resize(4)
	n.encode_u32(0, 36 + pcm.size())
	out.append_array(n)
	out.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, channels)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * block)
	fmt.encode_u16(16, block)
	fmt.encode_u16(18, bits)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	n.encode_u32(0, pcm.size())
	out.append_array(n)
	out.append_array(pcm)
	return out


func _write(name: String, bytes: PackedByteArray) -> String:
	var path := DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


func test_files_are_checked() -> void:
	var ok := SoundImport.inspect(wav(), "wav")
	assert_bool(ok.ok).is_true()
	assert_float(ok.seconds).is_equal_approx(0.5, 0.01)
	assert_str(SoundImport.inspect(wav(44100, 2), "wav").error).is_equal("Use mono")
	assert_str(SoundImport.inspect(wav(22050), "wav").error).is_equal("Use 44.1 or 48 kHz")
	assert_str(SoundImport.inspect(wav(44100, 1, 8), "wav").error).is_equal("Use 16-bit WAV")
	assert_str(SoundImport.inspect(wav(48000, 1, 16, 25.0), "wav").error).is_equal("Too long for a loop")
	assert_str(SoundImport.inspect(PackedByteArray([1, 2, 3]), "wav").error).is_equal("Not a WAV file")
	assert_str(SoundImport.inspect(PackedByteArray([1, 2, 3]), "ogg").error).is_equal("Not an OGG file")
	assert_str(SoundImport.inspect(wav(), "mp3").error).is_equal("Use OGG or WAV")
	# An OGG's first page names Vorbis, its channels and rate.
	var ogg := PackedByteArray()
	ogg.resize(70)
	ogg.encode_u32(0, 0x5367674F) # "OggS"
	ogg[26] = 1
	ogg[27] = 30
	var body := 28
	ogg[body] = 1
	for i in 6:
		ogg[body + 1 + i] = "vorbis".unicode_at(i)
	ogg[body + 11] = 2
	ogg.encode_u32(body + 12, 44100)
	assert_str(SoundImport.inspect(ogg, "ogg").error).is_equal("Use mono")
	var stream := SoundImport.stream(wav(), "wav")
	assert_object(stream).is_not_null()
	assert_int((stream as AudioStreamWAV).loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)


func _package_with_recordings(name: String) -> String:
	var files := PackageWriter.read_folder("res://content/cars/noss_box")
	files["sound/exhaust_on_2000.wav"] = wav()
	files["sound/exhaust_on_6000.wav"] = wav(48000)
	files["sound/start.wav"] = wav()
	var sound := { "schema": "noss.sound/1", "name": "Mine", "base": "i4", "rpm_idle": 900, "rpm_max": 7000,
		"layers": [{ "emitter": "exhaust", "samples": [{ "rpm": 6000, "on": "exhaust_on_6000.wav" }, { "rpm": 2000, "on": "exhaust_on_2000.wav" }] }],
		"extras": { "start": "start.wav" } }
	files["sound/profile.json"] = PackageWriter.canonical_json(sound).to_utf8_buffer()
	var path := DIR.path_join(name)
	DirAccess.remove_absolute(path)
	var result := PackageWriter.write(path, { "name": "Loud", "author": "test", "license": "CC0-1.0", "family": "car" }, files)
	assert_bool(result.ok).override_failure_message(String(result.error)).is_true()
	return path


func test_recordings_travel_and_play() -> void:
	var path := _package_with_recordings("loud.noss")
	var pkg := PackageLoader.load_package(path)
	assert_str(pkg.error).is_empty()
	assert_int(pkg.sound_streams.size()).is_equal(3)
	var sound: EngineSound = auto_free(EngineSound.new())
	add_child(sound)
	sound.set_profile(pkg.sound, pkg.sound_streams)
	# The exhaust plays the recordings, lowest rpm first; the engine and intake the built-in i4.
	assert_array(sound._loops.exhaust.rpm).is_equal([2000.0, 6000.0])
	assert_object(sound._loops.exhaust.on[0]).is_same(pkg.sound_streams["exhaust_on_2000.wav"])
	assert_object(sound._loops.exhaust.off[0]).is_same(pkg.sound_streams["exhaust_on_2000.wav"])
	assert_array(sound._spaces.exhaust).is_equal([900.0, 7000.0])
	assert_bool(sound._spaces.has("engine")).is_false()
	assert_bool(sound._recorded.has("start")).is_true()
	pkg.free_scenes()
	# Without its recordings (a server that doesn't send them) it's the tuned built-in.
	var partial_dir := DIR.path_join("partial")
	DirAccess.make_dir_recursive_absolute(partial_dir)
	PackageWriter.unpack(path, partial_dir)
	for f in ["exhaust_on_2000.wav", "exhaust_on_6000.wav", "start.wav"]:
		DirAccess.remove_absolute(partial_dir.path_join("sound").path_join(f))
	assert_str(PackageLoader.load_package(partial_dir).error).starts_with("Missing")
	var base := PackageLoader.load_package(partial_dir, {}, { "partial": true })
	assert_str(base.error).is_empty()
	assert_bool(base.sound.has("layers")).is_false()
	assert_str(base.sound.base).is_equal("i4")
	base.free_scenes()


func test_the_bay_keeps_and_edits_recordings() -> void:
	var pkg := PackageLoader.load_package(_package_with_recordings("keep.noss"))
	var draft := FittingDraft.from_package(pkg)
	assert_int(draft.sound_files.size()).is_equal(3)
	var files := draft.files()
	assert_bool(files.has("sound/exhaust_on_6000.wav")).is_true()
	# Add an off-load loop at 2000 rpm, an intake loop and a backfire; refuse a stereo file.
	assert_str(draft.add_recording(_write("off.wav", wav()), "exhaust", 2000.0, "off")).is_empty()
	assert_str(draft.add_recording(_write("in.wav", wav()), "intake", 4000.0, "on")).is_empty()
	assert_str(draft.add_recording(_write("bang.wav", wav()), "backfire")).is_empty()
	assert_str(draft.add_recording(_write("stereo.wav", wav(44100, 2)), "engine", 3000.0)).is_equal("Use mono")
	var labels := draft.recordings_list().map(func(x: Array) -> String: return x[0])
	assert_array(labels).contains(["Exhaust 2000 rpm off-load", "Intake 4000 rpm on-load", "Backfire"])
	assert_array(JsonSchema.validate(draft.sound, JsonSchema.load_schema("sound"))).is_empty()
	# Saved, it loads with all of them.
	var path := DIR.path_join("edited.noss")
	DirAccess.remove_absolute(path)
	draft.edit_path = ""
	draft.id = PackageWriter.new_uuid()
	var result := PackageWriter.write(path, draft.info(), draft.files())
	assert_bool(result.ok).is_true()
	var back := PackageLoader.load_package(path)
	assert_int(back.sound_streams.size()).is_equal(6)
	back.free_scenes()
	# Taken out again: the profile goes back to the built-in.
	draft.clear_recordings()
	assert_bool(draft.sound.has("layers")).is_false()
	assert_bool(draft.files().keys().any(func(k: String) -> bool: return k.ends_with(".wav"))).is_false()
	draft.free_scene()
	pkg.free_scenes()
