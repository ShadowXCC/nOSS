extends GdUnitTestSuite
## F11 toggles fullscreen (Game polls it, Settings.toggle_fullscreen() saves it like the Settings
## row) and an open Settings page's Fullscreen row follows. F11 is the game's, not a player's key.

const DIR := "user://tests/fullscreen"


func before() -> void:
	Players.clear()
	Settings.use_folder(DIR)
	Settings.reset_keys(Settings.MACHINE.keys()) # not this machine's own (it keeps them in a new folder)


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _f11(pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_F11
	e.physical_keycode = KEY_F11
	e.pressed = pressed
	Input.parse_input_event(e)
	await _frames()


func _saved() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(DIR.path_join("settings.cfg"))
	return bool(cfg.get_value("display", "fullscreen", false))


func test_toggle_flips_and_saves() -> void:
	Settings.set_value("fullscreen", false)
	Settings.toggle_fullscreen()
	assert_bool(Settings.fullscreen).is_true()
	assert_bool(_saved()).is_true()
	Settings.toggle_fullscreen()
	assert_bool(Settings.fullscreen).is_false()
	assert_bool(_saved()).is_false()


func test_f11_toggles_once_a_press() -> void:
	Settings.set_value("fullscreen", false)
	await _f11(true)
	await _frames(5) # held: still one toggle
	assert_bool(Settings.fullscreen).is_true()
	await _f11(false)
	assert_bool(Settings.fullscreen).is_true()
	await _f11(true)
	await _f11(false)
	assert_bool(Settings.fullscreen).is_false()


func test_settings_row_follows() -> void:
	Settings.set_value("fullscreen", false)
	var holder := Control.new()
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var menu := SettingsMenu.new()
	holder.add_child(menu)
	await _frames()
	assert_str(menu.tab_name()).is_equal("Display")
	var row := menu._fullscreen
	assert_bool(row.button_pressed).is_false()
	Settings.toggle_fullscreen()
	assert_bool(row.button_pressed).is_true()
	Settings.toggle_fullscreen()
	assert_bool(row.button_pressed).is_false()
	holder.free()


func test_f11_is_not_a_players_key() -> void:
	assert_bool(KEY_F11 in PlayerInput.CAPTURE_KEYS).is_false()
