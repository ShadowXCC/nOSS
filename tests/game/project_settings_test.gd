extends GdUnitTestSuite
## Engine settings the rest of the game relies on (ARCHITECTURE.md §5, §7, §10).


func test_physics_runs_jolt_at_120_hz() -> void:
	assert_str(ProjectSettings.get_setting("physics/3d/physics_engine")).is_equal("Jolt Physics")
	# A misspelled engine name silently falls back to the default, so check it's a real option.
	assert_array(_setting_options("physics/3d/physics_engine")).contains(["Jolt Physics"])
	assert_int(Engine.physics_ticks_per_second).is_equal(120)
	assert_bool(ProjectSettings.get_setting("physics/common/physics_interpolation")).is_true()


func test_renderer_is_forward_plus() -> void:
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method")).is_equal("forward_plus")


func test_user_dir_is_noss() -> void:
	assert_str(OS.get_user_data_dir().get_file()).is_equal("nOSS")


func test_main_scene_is_boot() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal("res://game/app/boot.tscn")


func _setting_options(setting: String) -> PackedStringArray:
	for property in ProjectSettings.get_property_list():
		if property.name == setting:
			return property.hint_string.split(",")
	return PackedStringArray()
