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


## Ride height lowers the wheels on the body; it's packed only when it's set.
func test_ride_height() -> void:
	var before: float = _bay._preview.fitted.wheels[0].center.y
	_bay._set_lift(0.05)
	var f := _bay._preview.fitted
	assert_float(f.wheels[0].center.y).is_equal_approx(before - 0.05 * f.scale, 0.0001)
	assert_str(_bay.draft.files()["fit.json"].get_string_from_utf8()).contains("body_lift_m")
	_bay._set_lift(0.0)
	assert_str(_bay.draft.files()["fit.json"].get_string_from_utf8()).not_contains("body_lift_m")


## A body lowered into the ground is reported, and Lift clear raises it to just over it.
func test_lift_clear() -> void:
	var clearance := -_bay._clip_depth()
	assert_float(clearance).is_between(0.0, 0.5)
	_bay._set_lift(-(clearance + 0.1) / _bay._preview.fitted.scale)
	assert_float(_bay._clip_depth()).is_equal_approx(0.1, 0.001)
	assert_str(_bay._status.text).contains("Body 10 cm in the ground")
	_bay._show_step("Wheels")
	var lift := _button("Lift clear")
	assert_object(lift).is_not_null()
	if lift == null:
		return
	lift.pressed.emit()
	assert_float(_bay._clip_depth()).is_between(-0.03, 0.0)
	assert_str(_bay._status.text).not_contains("in the ground")


## A wheel off the ground (an older import's roof part) is shown and can be removed.
func test_a_wheel_off_the_ground_can_be_removed() -> void:
	_bay.draft.fit.wheels.append({ "id": "C2", "axle": 2, "side": "C", "center": [0.0, 1.5, 0.0], "radius": 0.3, "width": 0.2 })
	_bay._refresh()
	assert_str(_bay._status.text).contains("Wheel C2 is off the ground")
	_bay._show_step("Wheels")
	var remove := _button("Remove it")
	assert_object(remove).is_not_null()
	if remove == null:
		return
	remove.pressed.emit()
	assert_int(_bay.draft.fit.wheels.size()).is_equal(4)
	assert_str(_bay._status.text).not_contains("off the ground")


## The Wheels step picks a wheel and lists its parts; the preview rings it and tints them.
func test_the_wheels_step_edits_one_wheel() -> void:
	_bay._wheel_id = "LF"
	_bay._show_step("Wheels")
	assert_object(_button("Find wheels again")).is_not_null()
	assert_object(_button("Remove wheel")).is_not_null()
	var checks: Array = _bay._content.find_children("*", "CheckButton", true, false).filter(func(c: CheckButton) -> bool: return c.text.begins_with("wheel-front-left"))
	assert_int(checks.size()).is_equal(1)
	assert_int(_bay._preview.selected).is_equal(_bay._wheels().index_of("LF"))
	assert_array(Array(_bay._preview.lit)).contains_exactly(["wheel-front-left"])
	assert_bool(_bay._preview.pick_enabled).is_true()
	_bay._show_step("Paint")
	assert_bool(_bay._preview.pick_enabled).is_false()


## A click on a wheel of the picked wheel drops it; clicked again, it's back.
func test_a_click_on_the_model_drops_and_adds_a_part() -> void:
	_bay._wheel_id = "LF"
	_bay._show_step("Wheels")
	var i := _bay._wheels().index_of("LF")
	var c: Vector3 = _bay._preview.fitted.wheels[i].center + Vector3(0, -_bay._preview.fitted.ground_y, 0)
	var hit := _bay._preview.pick_ray(c + Vector3(5, 0, 0), Vector3(-1, 0, 0)) # from the left
	assert_str(String(hit.get("node", ""))).is_equal("wheel-front-left")
	_bay._on_part_clicked(hit)
	assert_str(_bay._status.text).is_equal("Dropped from LF")
	assert_array(_bay.draft.fit.wheels[i].spin_nodes).is_empty()
	_bay._on_part_clicked(_bay._preview.pick_ray(c + Vector3(5, 0, 0), Vector3(-1, 0, 0)))
	assert_str(_bay._status.text).is_equal("Added to LF")
	assert_array(_bay.draft.fit.wheels[_bay._wheels().index_of("LF")].spin_nodes).contains_exactly(["wheel-front-left"])


func test_paint_assignment() -> void:
	_bay._assign_material("primary", "colormap")
	assert_array(_bay.draft.paint.slots.primary.materials).contains_exactly(["colormap"])
	_bay._assign_material("", "colormap")
	assert_bool(_bay.draft.paint.slots.has("primary")).is_false()


func test_draft_packs() -> void:
	if FileAccess.file_exists(_bay.draft.edit_path):
		DirAccess.remove_absolute(_bay.draft.edit_path)
	_bay.draft.fit.body_lift_m = 0.05
	var result := _bay.draft.pack()
	assert_str(result.error).is_empty()
	var pkg := PackageLoader.load_package(result.path)
	assert_str(pkg.error).is_empty()
	assert_float(float(pkg.fit.get("body_lift_m", 0.0))).is_equal(0.05)
	pkg.free_scenes()


func test_a_noss_file_can_be_imported() -> void:
	var path := _write_noss("user://tests/writer/bay_import.noss", "Bay Import")
	_bay._import(path)
	assert_bool(await _until(func() -> bool: return not _bay._busy)).is_true()
	assert_str(_bay.draft.car_name).is_equal("Bay Import")
	# The picked file is never written back over: the garage decides where it lands.
	assert_str(_bay.draft.edit_path).is_empty()
	assert_object(_bay.draft.scene).is_not_null()
	assert_dict(_bay.draft.paint).contains_keys(["slots"])
	assert_dict(_bay.draft.fit).contains_keys(["wheels", "model_transform"])
	DirAccess.remove_absolute(path)


func test_a_noss_already_in_the_garage_asks_first() -> void:
	var path := _write_noss(PackageWriter.garage_path("Bay Twin", PackageWriter.new_uuid()), "Bay Twin")
	var was := String(PackageLoader.read_manifest(path).id)
	_bay._import(path)
	assert_bool(await _until(func() -> bool: return is_instance_valid(_bay._overlay))).is_true()
	# "Add as a new car" is the second choice; it keeps the garage car and renames the import.
	var buttons: Array = _bay._overlay.find_children("*", "Button", true, false)
	assert_int(buttons.size()).is_equal(3)
	buttons[1].pressed.emit()
	assert_str(_bay.draft.car_name).is_equal("Bay Twin copy")
	assert_str(_bay.draft.id).is_not_equal(was)
	assert_str(_bay.draft.edit_path).is_empty()
	assert_object(_bay.draft.scene).is_not_null() # the question must not free it
	assert_bool(is_instance_valid(_bay._overlay)).is_false()
	DirAccess.remove_absolute(path)


## LB/RB (the tab actions) step through the steps with a car in, both ways and wrapping, but not
## while a text field is being typed in (docs/UI_FLOW.md §8). The prompt bar says "Steps".
func test_the_tab_actions_step_through_the_steps() -> void:
	_bay._show_step("Import")
	await get_tree().process_frame
	await _push("ui_tab_next")
	assert_str(_bay._step).is_equal("Orient")
	await _push("ui_tab_prev")
	await _push("ui_tab_prev")
	assert_str(_bay._step).is_equal("Save")
	_bay._show_step("Import")
	await get_tree().process_frame
	var field := _bay._content.find_children("*", "LineEdit", true, false)[0] as LineEdit
	field.grab_focus()
	await get_tree().process_frame # reached by keys, a field waits for confirm (UiKit.text_field)
	field.edit()
	await _push("ui_tab_next")
	assert_str(_bay._step).is_equal("Import")
	field.unedit()
	var bar := _bay.find_children("*", "PromptBar", true, false)[0] as PromptBar
	assert_array(bar.extra).contains_exactly([["tabs", "Steps"]])


## Moving down a long step with a pad (no mouse to scroll) brings each control into view.
func test_the_panel_follows_the_focus() -> void:
	var old_size := get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	_bay._wheel_id = "LF"
	_bay._show_step("Wheels")
	for i in 3:
		await get_tree().process_frame
	var scroll := _bay._scroll
	assert_float(_bay._content.size.y).override_failure_message("a step that fits would never scroll").is_greater(scroll.size.y)
	var targets: Array = _bay._content.get_children().map(func(c: Control) -> Control: return UiKit._focus_target(c)) \
		.filter(func(c: Control) -> bool: return c != null)
	(targets[-1] as Control).grab_focus()
	for i in 3:
		await get_tree().process_frame
	assert_int(scroll.scroll_vertical).override_failure_message("the panel did not follow the focus").is_greater(0)
	assert_bool(scroll.get_global_rect().encloses((targets[-1] as Control).get_global_rect())) \
		.override_failure_message("the focused control is not in view").is_true()
	var down := scroll.scroll_vertical
	(targets[0] as Control).grab_focus()
	for i in 3:
		await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_less(down)
	assert_bool(scroll.get_global_rect().encloses((targets[0] as Control).get_global_rect())).is_true()
	get_tree().root.size = old_size


## Without a car only Import is on: LB/RB stay there.
func test_the_tab_actions_wait_for_a_car() -> void:
	var empty := FittingBay.new()
	add_child(empty)
	await get_tree().process_frame
	await _push("ui_tab_next")
	assert_str(empty._step).is_equal("Import")
	empty.free()


func _push(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		get_tree().root.push_input(e)
	await get_tree().process_frame
	await get_tree().process_frame


## The step's button labelled `text` (not one of the old step's, still waiting to be freed).
func _button(text: String) -> Button:
	for b: Button in _bay._content.find_children("*", "Button", true, false):
		if b.text == text and not b.is_queued_for_deletion():
			return b
	return null


## A .noss of the built-in box at `path`, named `car_name`.
func _write_noss(path: String, car_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var written := PackageWriter.write(path, { "name": car_name, "author": "test", "license": "CC0-1.0", "family": "car" },
		PackageWriter.read_folder("res://content/cars/noss_box"))
	assert_str(String(written.error)).is_empty()
	return path


## Waits for `done` to come true, a frame at a time.
func _until(done: Callable, frames := 900) -> bool:
	for i in frames:
		if done.call():
			return true
		await get_tree().process_frame
	return false
