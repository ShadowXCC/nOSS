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
	var names := ["FreeDriveButton", "GarageButton", "FittingBayButton", "SettingsButton", "QuitButton"]
	for i in names.size():
		var b: Button = runner.find_child(names[i])
		assert_str(b.accessibility_name).is_not_empty()
		var below := b.get_node(b.focus_neighbor_bottom) as Button
		assert_str(below.name).is_equal(names[(i + 1) % names.size()])
