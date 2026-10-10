extends GdUnitTestSuite

const Boot := preload("res://game/app/boot.gd")


func test_core_version_found() -> void:
	assert_str(Boot.core_version()).is_equal(Boot.game_version())


func test_title_scene_exists() -> void:
	assert_bool(ResourceLoader.exists(Boot.TITLE_SCENE)).is_true()
