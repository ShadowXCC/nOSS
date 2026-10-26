extends GdUnitTestSuite
## Drag Strip's pages (docs/UI_FLOW.md §6.1): more settings than fit a screen, so they scroll, and
## the scroll follows the focus (how a controller or a keyboard scrolls it: both move the focus).
## Next and Back sit in the action bar under the rows, always on screen. The class is no longer a
## row: it's the next step, Street, Pro or Top Fuel. The old menu's memory still counts.

var _holder: Control
var _stack: MenuStack


func before() -> void:
	Settings.use_folder("user://tests/drag_menu")


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	Settings.profile.event_memory = {}
	Settings.profile.erase("last_drag")
	Settings.profile.erase("last_drag_class")


func after_test() -> void:
	if is_instance_valid(_holder):
		_holder.free()


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


## Drag's Settings page on a stack in a `room`-sized holder.
func _page(room := Vector2(1920, 1080)) -> EventSettingsPage:
	_holder = Control.new()
	_holder.size = room
	add_child(_holder)
	_stack = MenuStack.new()
	_holder.add_child(_stack)
	var flow := EventFlow.make("mini", "drag")
	flow.recall()
	var page := EventSettingsPage.new()
	page.flow = flow
	_stack.push(page)
	return page


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


func test_every_setting_scrolls_and_next_and_back_do_not() -> void:
	var page := _page()
	await _frames(4)
	assert_str(page.title).is_equal("Drag Strip")
	assert_str(page.step_text()).is_equal("Step 2 of 4")
	var inside: Array[String] = []
	var outside: Array[String] = []
	for b: Button in page.find_children("*", "Button", true, false):
		var name := String(b.accessibility_name).get_slice(":", 0)
		(inside if page.scroll().is_ancestor_of(b) else outside).append(name)
	assert_array(outside).contains_exactly(["Back", "Next"])
	assert_array(inside).not_contains(["Class"])
	assert_array(inside).contains(["Length", "Boost", "Timing shifts", "Quick time events", "Christmas tree", "Two-step", "Burnout",
		"Tire shake", "Shift chain", "Money shift", "Centreline", "AI cars", "AI skill", "AI models", "Time", "Weather"])
	var headings := page.body.get_children().filter(func(c: Node) -> bool: return c is Label).map(func(l: Label) -> String: return l.text)
	assert_array(headings).contains_exactly(["Gimmicks", "Field"])
	assert_str(page.next_button.accessibility_description).is_equal("Pick the class")


## In a short window, down through every row reaches Next and Back, the scroll following, and
## then wraps to the top.
func test_the_focus_runs_through_every_row_and_the_scroll_follows() -> void:
	var page := _page(Vector2(1920, 600))
	await _frames(4)
	var first := _focused()
	assert_str(String(first.accessibility_name)).starts_with("Length: ")
	var names: Array[String] = []
	var at := first
	for i in 40:
		names.append(String(at.accessibility_name).get_slice(":", 0))
		var next := at.find_valid_focus_neighbor(SIDE_BOTTOM)
		if next == null or next == first:
			break
		at = next
	assert_str(names[-2]).is_equal("Next")
	assert_str(names[-1]).is_equal("Back")
	assert_object(at.find_valid_focus_neighbor(SIDE_BOTTOM)).is_same(first)
	# The last setting: focused, scrolled to, in view.
	var weather := page.row_named("Weather")
	weather.grab_focus()
	await _frames(3)
	assert_int(page.scroll().scroll_vertical).is_greater(0)
	assert_bool(page.scroll().get_global_rect().grow(1.0).encloses(weather.get_global_rect())).is_true()


## The old menu's last setup (last_drag, last_drag_class) until Drag has its own; its class is
## the Class step's, which lists the three drag classes.
func test_the_class_step_and_the_old_memory() -> void:
	var old := RaceEvent.drag(805, 3)
	old.drag_tree = false
	Settings.profile.last_drag = old.to_dict()
	Settings.profile.last_drag_class = "official.drag.pro"
	var page := _page()
	await _frames(4)
	assert_str(String(page.row_named("Boost").accessibility_name)).is_equal("Boost: 3")
	assert_str(String(page.row_named("Christmas tree").accessibility_name)).is_equal("Christmas tree: Off")
	assert_str(String(page.row_named("Length").accessibility_name)).ends_with("805 m" if Settings.units != "imperial" else "1/2 mile")
	page.go_on()
	await _frames(4)
	var classes := _stack.top() as ClassPage
	assert_object(classes).is_not_null()
	var names := classes.body.get_children().filter(func(c: Node) -> bool: return c is Button).map(func(b: Button) -> String: return String(b.accessibility_name))
	assert_array(names).contains_exactly(["Drag Street", "Drag Pro, last used", "Drag Top Fuel"])
	assert_str(String(_focused().accessibility_name)).is_equal("Drag Pro, last used")
