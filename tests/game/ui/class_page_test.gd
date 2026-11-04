extends GdUnitTestSuite
## The Class page (docs/UI_FLOW.md §5.6): the type's classes named "<Mode> <Class>", the focus on
## the last one used, the list scrolling to the focus (the Free Drive bug in Changes.md), and the
## turntable's car: P1's last car fitted to the class in focus once the focus settles, or the
## class's default car when it can't take P1's.

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/class_page")
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Game.flow_return = {}
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	_requested.clear()
	Settings.profile.event_memory = {}
	Settings.profile.last_car = "res://content/cars/noss_box" # family "car"


func _on_event(e: RaceEvent, platform_id: String) -> void:
	_requested.append([e, platform_id])


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


## A ClassPage on a stack in a `room`-sized holder (pages fill their parent); free the holder after.
func _page(flow: EventFlow, room := Vector2(1920, 1080)) -> ClassPage:
	var holder := Control.new()
	holder.size = room
	add_child(holder)
	var stack := MenuStack.new()
	holder.add_child(stack)
	var page := ClassPage.new()
	page.flow = flow
	stack.push(page)
	return page


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


static func _action(vp: Viewport, action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		vp.push_input(e)


func test_classes_named_and_last_one_focused() -> void:
	var flow := EventFlow.racing("regular")
	flow.recall()
	flow.class_id = "official.track.prototype"
	var page := _page(flow)
	await _frames(4)
	assert_str(page.title).is_equal("Choose class")
	assert_str((page.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive › Racing › Regular › Class")
	assert_str(page.step_text()).is_equal("Step 3 of 4")
	var names := page.body.get_children().filter(func(c: Node) -> bool: return c is Button).map(func(b: Button) -> String: return String(b.accessibility_name))
	assert_array(names).contains(["Track GT", "Track Formula", "Track Prototype, last used"])
	assert_str(String(_focused().accessibility_name)).is_equal("Track Prototype, last used")
	assert_str(String(_focused().accessibility_description)).contains("kW")
	page.get_parent().get_parent().free()


## A short window: down to the last class, it's in view, then Back in the bar; and up again.
func test_the_list_scrolls_to_the_focus() -> void:
	var flow := EventFlow.racing("regular")
	flow.recall()
	var page := _page(flow, Vector2(1920, 520))
	await _frames(4)
	var buttons := page.body.get_children().filter(func(c: Node) -> bool: return c is Button)
	(buttons[0] as Button).grab_focus()
	await _frames(2)
	for i in buttons.size():
		_action(get_viewport(), "ui_down")
		await _frames(2)
	assert_object(_focused()).is_same(page.back_button)
	var area := page.scroll().get_global_rect().grow(1.0)
	# Back is in the action bar under the scroll, so it takes the focus without scrolling the rows.
	assert_bool(area.encloses(page.back_button.get_global_rect())).is_false()
	assert_bool(page.get_global_rect().encloses(page.back_button.get_global_rect())).is_true()
	assert_bool(area.encloses((buttons[-1] as Button).get_global_rect())).is_true()
	assert_int(page.scroll().scroll_vertical).is_greater(0)
	for i in buttons.size():
		_action(get_viewport(), "ui_up")
		await _frames(2)
	assert_object(_focused()).is_same(buttons[0])
	assert_bool(area.encloses((buttons[0] as Button).get_global_rect())).is_true()
	page.get_parent().get_parent().free()


## P1's box car fits GT; Formula takes only open-wheelers, so its default car shows instead. The
## fit waits for the focus to settle.
func test_the_turntable_falls_back_to_the_class_default() -> void:
	var flow := EventFlow.racing("regular")
	flow.recall()
	flow.class_id = "official.track.gt"
	var page := _page(flow)
	await _frames(4)
	await get_tree().create_timer(ClassPage.FIT_DELAY + 0.1).timeout
	assert_str(page.shown_class).is_equal("official.track.gt")
	assert_str(page.shown_car).is_equal("res://content/cars/noss_box")
	var formula: Button = page.body.find_child("official_track_formula", false, false)
	formula.grab_focus()
	await _frames(2)
	assert_str(page.shown_class).is_equal("official.track.gt") # not yet
	await get_tree().create_timer(ClassPage.FIT_DELAY + 0.1).timeout
	assert_str(page.shown_class).is_equal("official.track.formula")
	var platform := PlatformLoader.load_official("official.track.formula").platform
	assert_str(page.shown_car).is_equal(GameModes.default_car(platform))
	assert_str(String(PackageLoader.read_manifest(page.shown_car).family)).is_equal("open")
	page.get_parent().get_parent().free()


## Confirm on a class goes on to the players, a time trial's too.
func test_confirm_goes_on() -> void:
	var flow := EventFlow.racing("regular")
	flow.recall()
	var page := _page(flow)
	await _frames(4)
	var formula: Button = page.body.find_child("official_track_formula", false, false)
	formula.pressed.emit()
	await _frames(2)
	var stack := page.get_parent() as MenuStack
	assert_bool(stack.top() is PlayersMenu).is_true()
	assert_str((stack.top() as PlayersMenu).platform_id).is_equal("official.track.formula")
	assert_str(String(Settings.profile.event_memory["racing/regular"].class_id)).is_equal("official.track.formula")
	stack.get_parent().free()
	var tt := EventFlow.racing("regular", true)
	tt.recall()
	page = _page(tt)
	await _frames(4)
	(page.body.find_child("official_track_touring", false, false) as Button).pressed.emit()
	await _frames(2)
	stack = page.get_parent() as MenuStack
	assert_bool(stack.top() is PlayersMenu).is_true()
	assert_str((stack.top() as PlayersMenu).platform_id).is_equal("official.track.touring")
	assert_bool(_requested.is_empty()).is_true()
	stack.get_parent().free()


## Custom lists every mode's classes, so the page scrolls, and it opens focused on the class used
## last — row 13 of 22 for a highway class. A row that starts out of the scroll's view is out of
## the screen-reader tree until it has the focus (docs/ARCHITECTURE.md §36), so Back goes in the
## action bar, where it is always reachable (the walk's stop in Changes.md).
func test_the_all_modes_page_keeps_back_in_reach() -> void:
	Settings.profile.last_platform = "official.highway.super"
	var flow := EventFlow.racing("custom")
	flow.recall()
	assert_str(flow.class_id).is_equal("official.highway.super")
	var page := _page(flow, Vector2(1920, 700))
	await _frames(4)
	var names := page.body.get_children().filter(func(c: Node) -> bool: return c is Button).map(func(b: Button) -> String: return String(b.accessibility_name))
	assert_array(names).contains(["Track GT", "Highway Super, last used"])
	assert_int(names.size()).is_greater(10) # every mode's
	# It opens on the highway class, which scrolls Track GT out of view.
	assert_str(String(_focused().accessibility_name)).is_equal("Highway Super, last used")
	assert_int(page.scroll().scroll_vertical).is_greater(0)
	var gt: Button = page.body.find_child("official_track_gt", false, false)
	assert_bool(page.scroll().get_global_rect().encloses(gt.get_global_rect())).is_false()
	# Back is in the bar under the body, not a row: in view whatever the scroll is at.
	assert_bool(page.scroll().is_ancestor_of(page.back_button)).is_false()
	assert_bool(page.back_button.is_visible_in_tree()).is_true()
	assert_bool(page.get_global_rect().encloses(page.back_button.get_global_rect())).is_true()
	page.get_parent().get_parent().free()
