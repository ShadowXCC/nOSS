extends GdUnitTestSuite
## The Fitting Bay (docs/VEHICLE_PACKAGE.md §7): every step builds for an imported car, edits
## land in the draft, and the draft packs into a package that loads.

var _bay: FittingBay


func before_test() -> void:
	var result := ModelImport.import_file("res://tests/fixtures/models/kenney/sedan-sports.glb")
	_bay = FittingBay.new()
	_bay.draft = FittingDraft.from_import(result)
	_bay.draft.edit_path = "user://tests/writer/bay_sedan.noss"
	DirAccess.make_dir_recursive_absolute("user://tests/writer")
	add_child(_bay)


func after_test() -> void:
	_bay._leave()
	_bay._discard_draft()
	_bay.free()


func test_every_step_builds() -> void:
	for step in FittingBay.STEPS:
		_bay._show_step(step)
		assert_str(_bay._step).is_equal(step)
		assert_int(_bay._content.get_child_count()).override_failure_message(step).is_greater(0)
	assert_object(_bay._preview.visual).is_not_null()
	assert_int(_bay._preview.visual.wheel_count()).is_equal(4)


func test_turning_and_scaling_change_the_fit() -> void:
	_bay._rotate(Vector3.UP, 90.0)
	assert_float(_bay.draft.fit.model_transform.rotation_deg[1]).is_equal_approx(90.0, 0.01)
	_bay._rotate(Vector3.UP, -90.0)
	var length := _bay._model_length()
	assert_float(length).is_equal_approx(2.55, 0.01)
	_bay.draft.fit.model_transform.scale = 4.4 / length
	_bay._refresh()
	assert_float(_bay._preview.fitted.envelope.size.z).is_greater(3.0)


func test_stock_wheels_follow_the_anchors() -> void:
	_bay.draft.fit.wheel_mode = "stock"
	_bay._move_anchor("track", 1.7)
	var a := _bay._anchors()
	assert_float(a.track).is_equal_approx(1.7, 0.001)
	assert_float(_bay._preview.fitted.track).is_greater(1.6)


func test_paint_assignment() -> void:
	_bay._assign_material("primary", "colormap")
	assert_array(_bay.draft.paint.slots.primary.materials).contains_exactly(["colormap"])
	_bay._assign_material("", "colormap")
	assert_bool(_bay.draft.paint.slots.has("primary")).is_false()


func test_draft_packs() -> void:
	if FileAccess.file_exists(_bay.draft.edit_path):
		DirAccess.remove_absolute(_bay.draft.edit_path)
	var result := _bay.draft.pack()
	assert_str(result.error).is_empty()
	var pkg := PackageLoader.load_package(result.path)
	assert_str(pkg.error).is_empty()
	pkg.free_scenes()
