extends GdUnitTestSuite
## Assists (INP-07, ACC-07): platform and mode rules, settings by device, the v3 profile
## migration, access assists that drive, and the racing line on each player's own layer.


func before() -> void:
	Settings.use_folder("user://tests/assist_suite")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func test_allowed_is_what_both_platform_and_mode_allow() -> void:
	var p := { "assists_allowed": ["abs", "tcs", "racing_line", "autodrive"] }
	var m := { "assists": { "allowed": ["abs", "racing_line", "steer_aid"] } }
	assert_array(AssistRules.allowed(p, m)).contains_exactly(["abs", "racing_line"])
	assert_array(AssistRules.allowed(p, {})).contains_exactly(["abs", "tcs", "racing_line", "autodrive"])


func test_auto_settings_follow_the_device() -> void:
	var gt := PlatformLoader.load_official("official.track.gt").platform
	var mode := GameModes.mode_for("official.track.gt")
	var profile := PlayerProfile.create("assist_a")
	var pad := AssistRules.effective(profile, gt, mode, false, false)
	assert_bool(pad.auto_gearbox).is_true()
	assert_bool(pad.steer_aid).is_true()
	assert_bool(pad.auto_clutch).is_true()
	var wheel := AssistRules.effective(profile, gt, mode, true, true)
	assert_bool(wheel.auto_gearbox).is_false()
	assert_bool(wheel.steer_aid).is_false()
	assert_bool(wheel.auto_clutch).is_false()
	profile.data.assists.auto_gearbox = "on"
	assert_bool(AssistRules.effective(profile, gt, mode, true, true).auto_gearbox).is_true()
	# Without a clutch pedal the auto clutch is always on.
	profile.data.assists.auto_clutch = "off"
	assert_bool(AssistRules.effective(profile, gt, mode, true, false).auto_clutch).is_true()


func test_v2_profiles_move_to_auto_by_device() -> void:
	var p := PlayerProfile.create("assist_b", { "version": 2, "assists": { "abs": false, "steer_aid": true, "auto_gearbox": false } })
	assert_int(p.data.version).is_equal(3)
	assert_str(p.data.assists.steer_aid).is_equal("auto")
	assert_str(p.data.assists.auto_gearbox).is_equal("off")
	assert_bool(p.data.assists.abs).is_false()
	assert_float(p.data.assists.brake_assist).is_equal(0.0)


func test_autodrive_drives_a_players_car() -> void:
	Players.clear()
	Settings.primary.data.assists.autodrive = true
	var s := TrackSession.new()
	add_child(s)
	for i in 600:
		await get_tree().process_frame
		if s.players.size() == 1 and s.players[0].vehicle:
			break
	var p := s.players[0]
	var start := p.distance
	await get_tree().create_timer(4.0).timeout
	var moved := fposmod(p.distance - start, s.track.length)
	Settings.primary.data.assists.autodrive = false
	assert_float(moved).is_greater(40.0)
	assert_float(absf(p.lateral)).is_less(s.track.width / 2.0)
	s.queue_free()
	await get_tree().process_frame


func test_racing_line_is_on_its_players_layer_only() -> void:
	var t := TrackData.load_file("res://content/tracks/proving_ground/track.json")
	var gt := PlatformLoader.load_official("official.track.gt").platform
	var view: RacingLineView = auto_free(RacingLineView.create(t, gt, 1, Palette.PRESETS.default))
	assert_int(view.layers).is_equal(1 << (RacingLineView.FIRST_LAYER))
	assert_int(view.mesh.get_surface_count()).is_equal(1)
	var mask := RacingLineView.cull_mask_for(1, 0xFFFFF)
	assert_bool(mask & view.layers != 0).is_true()
	assert_bool(RacingLineView.cull_mask_for(0, 0xFFFFF) & view.layers != 0).is_false()
