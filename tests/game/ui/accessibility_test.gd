extends GdUnitTestSuite
## Accessibility options (ACC-02, ACC-03, ACC-05, ACC-08, ACC-09): first-boot presets, HUD
## presets, volume groups and mono, narration text.


func before() -> void:
	Settings.use_folder("user://tests/access_suite")


func after() -> void:
	Settings.use_folder("user://")


func test_quick_presets_apply_combine_and_undo() -> void:
	var p := PlayerProfile.create("access_a")
	FirstBootMenu.apply_preset(p, "vision", true)
	FirstBootMenu.apply_preset(p, "motion", true)
	assert_str(p.data.font).is_equal("clear")
	assert_bool(p.data.high_contrast).is_true()
	assert_bool(p.data.reduce_flashing).is_true()
	assert_float(p.data.camera_shake).is_equal(0.0)
	assert_bool(FirstBootMenu.has_preset(p, "vision")).is_true()
	FirstBootMenu.apply_preset(p, "vision", false)
	assert_str(p.data.font).is_equal("retro")
	assert_bool(FirstBootMenu.has_preset(p, "motion")).is_true()
	FirstBootMenu.apply_preset(p, "minimal_input", true)
	assert_bool(p.data.assists.stability).is_true()
	assert_array(p.data.input.toggles).contains(["throttle"])
	FirstBootMenu.set_one_handed(p, "left")
	assert_str(p.data.input.presets.gamepad).is_equal("pad_left_hand")
	assert_str(p.data.input.presets.keyboard).is_equal("kb_left")
	FirstBootMenu.set_one_handed(p, "off")
	assert_str(p.data.input.presets.gamepad).is_equal("pad_standard")


func test_first_boot_screen_finishes_once() -> void:
	Settings.first_boot_done = false
	var menu: FirstBootMenu = auto_free(FirstBootMenu.new())
	add_child(menu)
	await get_tree().process_frame
	var buttons := menu.find_children("*", "Button", true, false)
	var done: Button = buttons.filter(func(b: Button) -> bool: return b.text == "Done")[0]
	for b: Button in buttons:
		assert_str(b.accessibility_name).is_not_empty()
	done.pressed.emit()
	assert_bool(Settings.first_boot_done).is_true()


func test_hud_presets_hide_elements() -> void:
	var p := PlayerProfile.create("access_b", { "hud_preset": "minimal", "hud_hidden": ["flags"] })
	var hud: Hud = auto_free(Hud.new())
	hud.apply_profile(p)
	assert_bool(hud.shows("speed")).is_true()
	assert_bool(hud.shows("timing")).is_false()
	assert_bool(hud.shows("flags")).is_false()
	p.data.hud_preset = "off"
	p.data.hud_hidden = []
	hud.apply_profile(p)
	for id: Array in Hud.ELEMENTS:
		assert_bool(hud.shows(id[0])).is_false()


func test_captions_show_spoken_lines() -> void:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.caption("Car left")
	hud.caption("Clear")
	hud.caption("Final lap")
	var label: Label = hud._captions
	assert_str(label.text).is_equal("Clear\nFinal lap")


func test_volume_groups_and_mono() -> void:
	Settings.set_value("vol_tires", 0.5)
	var tires := AudioServer.get_bus_index(&"Tires")
	assert_int(tires).is_greater(0)
	assert_float(db_to_linear(AudioServer.get_bus_volume_db(tires))).is_equal_approx(0.5, 0.01)
	assert_str(String(AudioServer.get_bus_send(tires))).is_equal("Cars")
	Settings.set_value("mono", true)
	var master := AudioServer.get_bus_index(&"Master")
	var on := false
	for k in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, k) is AudioEffectStereoEnhance:
			on = AudioServer.is_bus_effect_enabled(master, k)
	assert_bool(on).is_true()
	Settings.set_value("mono", false)


func test_narration_describes_controls() -> void:
	var c := UiKit.check("Captions", true, func(_on: bool) -> void: pass, "Spoken lines as text")
	assert_str(Narrator.describe(c)).is_equal("Captions, on. Spoken lines as text")
	var s := UiKit.spinner("Spotter", [["off", "Off"], ["voice", "Voice"]], "voice", func(_v: Variant) -> void: pass)
	assert_str(Narrator.describe(s)).is_equal("Spotter: Voice")
	c.free()
	s.free()
