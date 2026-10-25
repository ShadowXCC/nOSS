extends GdUnitTestSuite
## The page stack (docs/UI_FLOW.md §1, §4): only the top page shows, cancel pops it, and the focus
## comes back where it was. The main menu runs every screen on it, the old menus too.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"


func before() -> void:
	Settings.use_folder("user://tests/menu_stack")
	Game.hold_events = true


func after() -> void:
	Game.hold_events = false
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	Settings.profile.last_platform = "official.track.gt"


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _page(title: String, rows: Array) -> MenuPage:
	var page := MenuPage.new()
	page.title = title
	page.crumbs = [title]
	page.ready.connect(func() -> void:
		for r: String in rows:
			page.add_row(UiKit.button(r, func() -> void: pass))
		page.chain())
	return page


func _focused() -> String:
	var c := get_viewport().gui_get_focus_owner()
	return UiKit.text_of(c as Button) if c is Button else "<none>"


func test_only_the_top_page_shows_and_focus_comes_back() -> void:
	var stack := MenuStack.new()
	var holder := Control.new()
	add_child(holder)
	var base := Button.new()
	base.text = "Base"
	holder.add_child(base)
	holder.add_child(stack)
	stack.base.append(base)
	base.grab_focus()
	var first := stack.push(_page("First", ["A", "B", "C"])) as MenuPage
	await _frames()
	assert_bool(base.is_inside_tree()).is_false()
	assert_str(_focused()).is_equal("A")
	(first.body.get_child(2) as Button).grab_focus() # on C
	var second := stack.push(_page("Second", ["X"])) as MenuPage
	await _frames()
	assert_bool(first.visible).is_false()
	assert_bool(second.visible).is_true()
	assert_object(stack.top()).is_same(second)
	assert_int(stack.depth()).is_equal(2)
	assert_str(_focused()).is_equal("X")
	# Cancel pops the top page; the one under shows with its focus back on C.
	_cancel()
	await _frames()
	assert_int(stack.depth()).is_equal(1)
	assert_bool(is_instance_valid(second)).is_false()
	assert_bool(first.visible).is_true()
	assert_str(_focused()).is_equal("C")
	# Its Back row pops it too, and the base comes back with its focus.
	var emptied := [0]
	stack.emptied.connect(func() -> void: emptied[0] += 1)
	first.back_button.pressed.emit()
	await _frames()
	assert_int(stack.depth()).is_equal(0)
	assert_int(emptied[0]).is_equal(1)
	assert_bool(base.is_inside_tree()).is_true()
	assert_int(base.get_index()).is_equal(0)
	assert_str(_focused()).is_equal("Base")
	# Freed with a page up (a session started from one), the base goes with it.
	stack.push(_page("Again", ["Z"]))
	await _frames()
	holder.free()
	await _frames()
	assert_bool(is_instance_valid(base)).is_false()


## Closing a page under others takes those off too; an old menu's own refocus is used.
func test_closing_a_lower_page_and_refocus() -> void:
	var stack := MenuStack.new()
	add_child(stack)
	var calls := [0]
	var first := stack.push(_page("First", ["A", "B"]), func() -> void: calls[0] += 1)
	var second := stack.push(_page("Second", ["X"]))
	var third := stack.push(_page("Third", ["Y"]))
	await _frames()
	stack.close(second)
	await _frames()
	assert_int(stack.depth()).is_equal(1)
	assert_bool(is_instance_valid(third)).is_false()
	assert_bool(first.visible).is_true()
	assert_int(calls[0]).is_equal(1)
	stack.clear()
	await _frames()
	assert_int(stack.depth()).is_equal(0)
	stack.free()


## The main menu: its logo and buttons hide under the first screen, and only the top screen shows
## (a screen reader never reads the ones under it). Back out, a screen at a time, to the buttons.
func test_the_main_menu_runs_its_screens_on_the_stack() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	var title := runner.scene()
	var stack := title.find_child("MenuStack", true, false) as MenuStack
	assert_object(stack).is_not_null()
	assert_str(_focused()).is_equal("Local Drive")
	(title.find_child("LocalDriveButton", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_int(stack.depth()).is_equal(1)
	for part in ["Logo", "TaglineLabel", "Menu", "VersionLabel"]:
		assert_object(title.get_node_or_null(part)).override_failure_message(part + " is still there under a page").is_null()
	var solo := stack.top()
	assert_str(solo.name).is_equal("SoloMenu")
	await _key(KEY_DOWN) # Race
	await _frames()
	await _key(KEY_ENTER)
	await _frames(4)
	assert_int(stack.depth()).is_equal(2)
	assert_bool(solo.visible).is_false()
	assert_bool(stack.top() is ClassPicker).is_true()
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_int(stack.depth()).is_equal(1)
	assert_bool(solo.visible).is_true()
	assert_str(_focused()).is_equal("Race") # Local Drive, on the mode backed out of
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_int(stack.depth()).is_equal(0)
	for part in ["Logo", "TaglineLabel", "Menu", "VersionLabel"]:
		assert_object(title.get_node_or_null(part)).override_failure_message(part + " didn't come back").is_not_null()
	assert_int(title.get_node("Menu").get_index()).is_less(stack.get_index()) # under the pages again
	assert_str(_focused()).is_equal("Local Drive")
	# Settings, then back: the focus is on Settings again.
	(title.find_child("SettingsButton", true, false) as Button).grab_focus()
	(title.find_child("SettingsButton", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_int(stack.depth()).is_equal(1)
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_int(stack.depth()).is_equal(0)
	assert_str(_focused()).is_equal("Settings")


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await _frames()
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _frames()


func _cancel() -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = &"ui_cancel"
		e.pressed = pressed
		get_viewport().push_input(e)
