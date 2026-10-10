extends GdUnitTestSuite
## noss_core GDExtension is loaded and callable from GDScript.


func test_core_class_registered() -> void:
	assert_bool(ClassDB.class_exists(&"NossCore")).is_true()


func test_core_version_matches_game() -> void:
	assert_str(NossCore.version()).is_equal(ProjectSettings.get_setting("application/config/version"))
