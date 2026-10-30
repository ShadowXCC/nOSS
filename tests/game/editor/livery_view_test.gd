extends GdUnitTestSuite
## Pointing at the car in the Fitting Bay's Livery step (docs/VEHICLE_PACKAGE.md §12): a pick
## knows the point on the model and the way the body faces there; a layer is picked by pointing
## at it, carried and put down; keys and a pad do what the mouse does; Esc and B go back to the
## list and never out of the bay.

var _bay: FittingBay
var _left := []
var _old_size: Vector2i


func before_test() -> void:
	_old_size = get_tree().root.size
	get_tree().root.size = Vector2i(1600, 900) # headless windows start tiny
	Game.hold_scenes = true
	Game.scene_requested.connect(_on_scene)
	var result := ModelImport.import_file("res://tests/fixtures/models/kenney/sedan-sports.glb")
	_bay = FittingBay.new()
	_bay.draft = FittingDraft.from_import(result)
	_bay.draft.paint.slots = { "primary": { "materials": ["colormap"], "color": "#1F4FB5", "finish": "metallic" } }
	_bay.start_step = "Livery"
	add_child(_bay)
	await get_tree().process_frame
	await get_tree().process_frame
	_bay._livery_edit().new_livery()
	_bay._livery_edit().add("shape", "rect")
	_bay._show_step("Livery")
	await get_tree().process_frame # the list's own focus comes first
	await get_tree().process_frame


func after_test() -> void:
	Game.scene_requested.disconnect(_on_scene)
	Game.hold_scenes = false
	_bay._leave()
	_bay._discard_draft()
	_bay.free()
	_left.clear()
	get_tree().root.size = _old_size


func _on_scene(scene_name: String, _scene: Node) -> void:
	_left.append(scene_name)


func _view() -> LiveryView:
	return _bay._preview.livery_view


## Where a model-space point shows on the view (control coordinates).
func _screen(model_point: Vector3) -> Vector2:
	var p := _bay._preview
	var world := p.visual.model_root.global_transform * model_point
	return p.camera.unproject_position(world) * p.size / Vector2(p.viewport.size)


func _layer_screen() -> Vector2:
	return _screen(LiveryEdit._v(_bay._livery_edit().current().at))


func _key(code: Key, ctrl := false, shift := false) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	get_viewport().push_input(k)


func _pad(button: JoyButton) -> void:
	var b := InputEventJoypadButton.new()
	b.button_index = button
	b.pressed = true
	get_viewport().push_input(b)


func test_the_view_points_in_the_livery_step_only() -> void:
	assert_object(_view()).is_not_null()
	assert_int(_bay._preview.focus_mode).is_equal(Control.FOCUS_ALL)
	_bay._show_step("Paint")
	assert_object(_bay._preview.livery_view).is_null()
	assert_int(_bay._preview.focus_mode).is_equal(Control.FOCUS_NONE)


## A pick gives the point on the model and the body's smoothed normal there, facing out.
func test_a_pick_knows_the_surface() -> void:
	var at := _layer_screen()
	var hit := _bay._preview.pick(at)
	assert_bool(hit.has("position")).is_true()
	var e := _bay._livery_edit()
	var n := (e.car_xform().basis * (hit.normal as Vector3)).normalized()
	assert_float(n.x).is_greater(0.6) # the car's left side faces +X
	# On the body: cast back in along the normal and it's there.
	var back := e.raycast_model((hit.position as Vector3) + (hit.normal as Vector3) * 0.5, -(hit.normal as Vector3))
	assert_vector(back.position).is_equal_approx(hit.position, Vector3.ONE * 0.002)
	assert_int(_view().layer_at(hit)).is_equal(0)
	assert_int(_view().layer_at(_bay._preview.pick(Vector2(5, 5)))).is_equal(-1)


## Enter picks up the layer under the crosshair, the arrows carry it, Enter puts it down there.
func test_keys_carry_a_layer() -> void:
	_bay._preview.grab_focus()
	await get_tree().process_frame
	_view()._set_keys(true)
	_view().cross.at = _layer_screen()
	var before := LiveryEdit._v(_bay._livery_edit().current().at)
	_key(KEY_ENTER)
	assert_bool(_view().carrying).is_true()
	_view().cross.at += Vector2(-60, 0)
	_view()._follow(_view().cross.spot(), true)
	_key(KEY_ENTER)
	assert_bool(_view().carrying).is_false()
	assert_str(_bay._status.text).is_equal("Placed")
	assert_vector(LiveryEdit._v(_bay._livery_edit().current().at)).is_not_equal(before)
	assert_bool(_bay._preview.has_focus()).is_true() # still pointing


func test_keys_change_the_layer() -> void:
	_bay._preview.grab_focus()
	await get_tree().process_frame
	var e := _bay._livery_edit()
	var p := e.placement()
	_key(KEY_R)
	assert_float(e.placement().turn).is_equal_approx(float(p.turn) + LiveryView.TURN_STEP, 0.1)
	_key(KEY_EQUAL)
	assert_float(e.placement().size).is_equal_approx(float(p.size) * LiveryView.SIZE_STEP, 0.001)
	_key(KEY_F)
	assert_str(e.placement().flip).is_equal("across")
	_key(KEY_M)
	assert_bool(e.current().get("mirror", false)).is_true()
	_key(KEY_D, true)
	assert_int(e.layers().size()).is_equal(2)
	_key(KEY_BRACKETLEFT)
	assert_int(e.layer).is_equal(0)
	_key(KEY_DELETE)
	assert_int(e.layers().size()).is_equal(1)
	_key(KEY_Z, true)
	assert_int(e.layers().size()).is_equal(2)
	assert_bool(_bay._preview.has_focus()).is_true()


func test_a_pad() -> void:
	_bay._preview.grab_focus()
	await get_tree().process_frame
	var e := _bay._livery_edit()
	_pad(JOY_BUTTON_Y)
	assert_int(e.layers().size()).is_equal(2)
	_pad(JOY_BUTTON_DPAD_DOWN)
	assert_int(e.layer).is_equal(0)
	_pad(JOY_BUTTON_X)
	assert_int(e.layers().size()).is_equal(1)
	_pad(JOY_BUTTON_DPAD_LEFT)
	assert_int(e.layers().size()).is_equal(2) # undone
	# Carrying: the D-pad turns and sizes.
	_view()._set_keys(true)
	_view().cross.at = _layer_screen()
	_pad(JOY_BUTTON_A)
	assert_bool(_view().carrying).is_true()
	var size: float = e.placement().size
	_pad(JOY_BUTTON_DPAD_UP)
	assert_float(e.placement().size).is_equal_approx(size * LiveryView.SIZE_STEP, 0.001)


## Esc and B leave the view for the list; the bay stays open.
func test_back_goes_to_the_list() -> void:
	for back: Callable in [func() -> void: _key(KEY_ESCAPE), func() -> void: _pad(JOY_BUTTON_B)]:
		_bay._preview.grab_focus()
		await get_tree().process_frame
		back.call()
		await get_tree().process_frame
		assert_bool(_bay._preview.has_focus()).is_false()
		var focus := UiKit.focus_owner(_bay)
		assert_str(focus.accessibility_name if focus else "").starts_with("Layer")
		assert_array(_left).is_empty()
		assert_bool(is_instance_valid(_bay._overlay)).is_false()
		assert_str(_bay._step).is_equal("Livery")
