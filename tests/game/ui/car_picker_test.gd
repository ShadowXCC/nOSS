extends GdUnitTestSuite
## The car picker in a player's view (hotswap mid-drive): it opens on the current car, the list
## follows the focus both ways (wrapping to Back), and only cancel closes it, not a press up.


func before() -> void:
	Settings.use_folder("user://tests/car_picker")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


## A short player view (a corner of a 4-way split at big text), so the list scrolls.
func _open(current: String) -> Array:
	Players.clear()
	var slot := Players.primary_slot()
	slot.profile.data.text_scale = 1.5
	var view := PlayerView.new()
	view.slot = slot
	view.size = Vector2(960, 400)
	add_child(view)
	slot.menu_target = view.viewport
	var picker := CarPicker.new()
	picker.current = current
	view.overlay_root.add_child(picker)
	await _frames(4)
	return [view, picker]


func _close(view: PlayerView) -> void:
	await _frames() # the screen reader's deferred follow first
	view.free()
	Players.primary_slot().profile.data.text_scale = 1.0
	Players.clear()


func test_opens_on_the_current_car_and_follows_the_focus() -> void:
	var cars := PackageLoader.list_available()
	var last := cars[-1]
	var opened := await _open(last)
	var view: PlayerView = opened[0]
	var picker: CarPicker = opened[1]
	var scroll := picker.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	var rows := scroll.get_child(0) as Control
	assert_float(rows.size.y).is_greater(scroll.size.y) # the list is longer than its view
	var focused := Players.focus_of(view.viewport) as Button
	assert_str(focused.text).ends_with("•")
	assert_int(scroll.scroll_vertical).is_greater(0)
	assert_bool(_in_view(scroll, focused)).is_true()
	# Down to Back (under the list), then round to the first car: the list scrolls back to the top.
	Players.push_action(view.viewport, "ui_down")
	await _frames(2)
	assert_str((Players.focus_of(view.viewport) as Button).text).is_equal("Back")
	Players.push_action(view.viewport, "ui_down")
	await _frames(2)
	focused = Players.focus_of(view.viewport) as Button
	assert_int(scroll.scroll_vertical).is_equal(0)
	assert_bool(_in_view(scroll, focused)).is_true()
	# Down through every car: each one is in view as it's reached.
	for i in cars.size() - 1:
		Players.push_action(view.viewport, "ui_down")
		await _frames(2)
		focused = Players.focus_of(view.viewport) as Button
		assert_bool(_in_view(scroll, focused)).is_true()
	assert_str(focused.text).ends_with("•")
	await _close(view)


func test_up_moves_and_only_cancel_closes() -> void:
	var opened := await _open("")
	var view: PlayerView = opened[0]
	var picker: CarPicker = opened[1]
	var closes := [0]
	picker.closed.connect(func() -> void: closes[0] += 1)
	var first := Players.focus_of(view.viewport) as Button
	assert_object(first).is_not_null()
	# Up from the first car wraps to Back.
	Players.push_action(view.viewport, "ui_up")
	await _frames(2)
	assert_str((Players.focus_of(view.viewport) as Button).text).is_equal("Back")
	assert_int(closes[0]).is_equal(0)
	Players.push_action(view.viewport, "ui_cancel")
	assert_int(closes[0]).is_equal(1)
	await _close(view)


static func _in_view(scroll: ScrollContainer, c: Control) -> bool:
	if not scroll.is_ancestor_of(c):
		return true # Back sits under the list
	var area := scroll.get_global_rect()
	var r := c.get_global_rect()
	return r.position.y >= area.position.y - 1.0 and r.end.y <= area.end.y + 1.0
