extends GdUnitTestSuite
## The Drag Strip setup screen: there are more settings than fit a screen, so they scroll, and
## the scroll follows the focus — which is how a controller or a keyboard scrolls it, since both
## move the focus rather than a pointer. Next and Back stay outside the scroll, so they are on
## screen whatever the settings are scrolled to.

var menu: DragMenu


func before() -> void:
	Settings.use_folder("user://tests/drag_menu")


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	menu = DragMenu.new()
	add_child(menu)
	await get_tree().process_frame


func after_test() -> void:
	if menu and is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame


func _scroll() -> ScrollContainer:
	var found: Array[Node] = menu.find_children("*", "ScrollContainer", true, false)
	return found[0] as ScrollContainer if not found.is_empty() else null


func test_the_settings_scroll_and_the_scroll_follows_the_focus() -> void:
	var scroll := _scroll()
	assert_object(scroll).override_failure_message("no scroll area: the settings would run off screen").is_not_null()
	# Without this a controller could move the focus to a row it cannot see.
	assert_bool(scroll.follow_focus).is_true()
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	# It is allowed to shrink to the room there is (UiKit.panel), but it starts with a height.
	assert_float(scroll.custom_minimum_size.y).is_greater(0.0)


func test_every_setting_is_inside_the_scroll_and_next_and_back_are_not() -> void:
	var scroll := _scroll()
	var inside: Array[String] = []
	var outside: Array[String] = []
	for b: Button in menu.find_children("*", "Button", true, false):
		var name := String(b.accessibility_name).get_slice(":", 0)
		if scroll.is_ancestor_of(b):
			inside.append(name)
		else:
			outside.append(name)
	# The two that must always be reachable, and nothing else, sit outside.
	assert_array(outside).contains_exactly(["Next", "Back"])
	# A sample of the settings, from the first row to the last of the gimmicks.
	assert_array(inside).contains(["Class", "Length", "Boost", "Timing shifts", "Quick time events",
		"Christmas tree", "Two-step", "Burnout", "Tire shake", "Shift chain", "Money shift",
		"Centreline", "AI cars", "AI skill", "AI models"])


## Stepping down from the first row reaches every other one, Next and Back included, before it
## comes back round: UiKit.chain_focus wires the rows into a ring, so "off the end" is the top
## again rather than nowhere.
func test_the_focus_order_runs_through_every_row_to_back() -> void:
	var rows: Array = menu._rows
	assert_int(rows.size()).is_greater(15)
	var start: Control = rows[0] as Control
	var at := start
	var names: Array[String] = [String(at.accessibility_name).get_slice(":", 0)]
	for i in rows.size() * 2:
		var next := at.find_valid_focus_neighbor(SIDE_BOTTOM)
		if next == null or next == start:
			break
		at = next
		names.append(String(at.accessibility_name).get_slice(":", 0))
	assert_int(names.size()).override_failure_message("the ring is %s" % [names]).is_equal(rows.size())
	assert_array(names).contains(["Class", "Boost", "Christmas tree", "AI models", "Next", "Back"])
	# Back is the last of them, so stepping down once more is back to the top.
	assert_str(names[names.size() - 1]).is_equal("Back")
	assert_object(at.find_valid_focus_neighbor(SIDE_BOTTOM)).is_equal(start)
	for row: Control in rows:
		assert_str(String(row.accessibility_name)).is_not_empty()
