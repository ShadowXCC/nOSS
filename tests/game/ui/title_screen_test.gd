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


func test_quit_button_has_focus() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var quit: Button = runner.find_child("QuitButton")
	assert_bool(quit.has_focus()).is_true()
