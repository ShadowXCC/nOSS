extends GdUnitTestSuite

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"


func test_title_reads_noss() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var title: Label = runner.find_child("TitleLabel")
	assert_str(title.text).is_equal("nOSS")


func test_shows_game_version() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var version: Label = runner.find_child("VersionLabel")
	assert_str(version.text).is_equal("v" + ProjectSettings.get_setting("application/config/version"))


func test_free_drive_button_has_focus() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await runner.simulate_frames(2)
	var drive: Button = runner.find_child("FreeDriveButton")
	assert_bool(drive.has_focus()).is_true()


func test_buttons_have_accessible_names_and_focus_order() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var names := ["FreeDriveButton", "RaceButton", "OnlineButton", "TimeTrialButton", "GarageButton", "FittingBayButton", "SettingsButton", "QuitButton"]
	for i in names.size():
		var b: Button = runner.find_child(names[i])
		assert_str(b.accessibility_name).is_not_empty()
		var below := b.get_node(b.focus_neighbor_bottom) as Button
		assert_str(below.name).is_equal(names[(i + 1) % names.size()])


## Every button is on screen in the default window (Changes.md: Quit was cut off); with big
## text the buttons scroll, and the focused one is always shown.
func test_buttons_stay_on_screen() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	for text_scale in [1.0, 1.5]:
		root.content_scale_factor = text_scale
		var runner := scene_runner(TITLE_SCENE)
		var screen := runner.scene() as Control
		screen.set_process_unhandled_input(false)
		root.content_scale_factor = text_scale # the screen applies the players' scale on start
		await runner.simulate_frames(6)
		var area := Rect2(Vector2.ZERO, screen.size)
		var scroll: ScrollContainer = runner.find_child("Buttons")
		assert_bool(area.encloses(scroll.get_global_rect())).override_failure_message("scale %s: buttons area off screen" % text_scale).is_true()
		if text_scale == 1.0:
			for b: Button in scroll.find_children("*", "Button", true, false):
				assert_bool(area.encloses(b.get_global_rect())).override_failure_message("%s off screen" % b.name).is_true()
		var quit: Button = runner.find_child("QuitButton")
		quit.grab_focus()
		await runner.simulate_frames(4)
		assert_bool(scroll.get_global_rect().grow(1.0).encloses(quit.get_global_rect())).override_failure_message("scale %s: focused Quit not shown" % text_scale).is_true()
	root.content_scale_factor = 1.0
	root.size = old_size
