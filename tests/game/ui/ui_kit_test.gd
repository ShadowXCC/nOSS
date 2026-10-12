extends GdUnitTestSuite
## UiKit controls: a spinner's arrows step by mouse in their own direction (Changes.md: they all
## stepped forward), and directions still step it.

var _root_size := Vector2i.ZERO


func before() -> void:
	_root_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720) # headless windows start at 64 x 64


func after() -> void:
	get_tree().root.size = _root_size


func _click(c: Control, local: Vector2) -> void:
	var at := get_tree().root.get_final_transform() * (c.get_global_transform_with_canvas() * local)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_tree().root.push_input(e)
		await get_tree().process_frame


func test_spinner_arrows_step_by_side() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var got := []
	var b := UiKit.spinner("Laps", [[1, "One"], [2, "Two"], [3, "Three"]], 2, func(v: int) -> void: got.append(v))
	b.position = Vector2(100, 100)
	b.size = Vector2(700, 64)
	host.add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	var value := b.get_node(^"Row/Value") as Label
	var row := b.get_node(^"Row") as Control
	var left := row.position.x + value.position.x
	await _click(b, Vector2(left + 4.0, 32.0)) # ‹
	await _click(b, Vector2(left + value.size.x - 4.0, 32.0)) # ›
	await _click(b, Vector2(left + value.size.x - 4.0, 32.0))
	await _click(b, Vector2(40.0, 32.0)) # on the name: forward, like confirm
	assert_array(got).is_equal([1, 2, 3, 1])
	assert_str(b.accessibility_name).is_equal("Laps: One")
	assert_bool(b.has_focus()).is_true()
	host.queue_free()


func test_spinner_steps_with_directions_and_confirm() -> void:
	var got := []
	var b := UiKit.spinner("Grid", [["a", "A"], ["b", "B"]], "a", func(v: String) -> void: got.append(v))
	add_child(b)
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	b.gui_input.emit(left)
	b.pressed.emit()
	assert_array(got).is_equal(["b", "a"])
	assert_str(UiKit.text_of(b)).is_equal("Grid   ‹ A ›")
	b.queue_free()
