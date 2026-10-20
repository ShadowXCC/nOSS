extends GdUnitTestSuite
## The pause menu (Changes.md): it opens inside the view of the player who paused, so in
## splitscreen it gets a quarter of the screen while the list of buttons is at its longest. The
## buttons scroll, and the scroll follows the focus — which is how a pad or the keyboard scrolls
## it, since both move the focus rather than a pointer.

var menu: PauseMenu


func before() -> void:
	Settings.use_folder("user://tests/pause_menu")


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	menu = PauseMenu.new()
	# Everything the menu can offer at once, so the list is as long as it ever gets.
	menu.can_setup = true
	menu.can_end_session = true
	menu.can_restart = true
	menu.ghost_items = [["none", "No ghost"], ["best", "Your best"]]
	menu.leaderboard_title = "Test track"
	menu.online = true
	menu.is_host = true
	add_child(menu)
	await get_tree().process_frame


func after_test() -> void:
	if menu and is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame


func _scroll() -> ScrollContainer:
	var found: Array[Node] = menu.find_children("*", "ScrollContainer", true, false)
	return found[0] as ScrollContainer if not found.is_empty() else null


func test_the_buttons_scroll_and_the_scroll_follows_the_focus() -> void:
	var scroll := _scroll()
	assert_object(scroll).override_failure_message("no scroll area: the buttons would run off screen").is_not_null()
	# Without this a pad could move the focus to a button it cannot see.
	assert_bool(scroll.follow_focus).is_true()
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	# It is allowed to shrink to the room there is (UiKit.panel), but it starts with a height.
	assert_float(scroll.custom_minimum_size.y).is_greater(0.0)


## Nothing is pinned outside the scroll: Resume is the first button and is focused on open, so it
## is already in view.
func test_every_button_is_inside_the_scroll() -> void:
	var scroll := _scroll()
	var outside: Array[String] = []
	for b: Button in menu.find_children("*", "Button", true, false):
		if not scroll.is_ancestor_of(b):
			outside.append(UiKit.text_of(b))
	assert_array(outside).is_empty()
	assert_int(menu._buttons.size()).is_greater(10)


## The player's own settings and the machine's are two different buttons, one above the other, so
## the first says what it is rather than just "Settings".
func test_driving_settings_reads_apart_from_game_settings() -> void:
	var names: Array[String] = []
	for b: Button in menu.find_children("*", "Button", true, false):
		names.append(UiKit.text_of(b))
	assert_array(names).contains(["Driving Settings", "Game settings"])
	assert_array(names).not_contains(["Settings"])


## The whole panel fits a quarter-screen splitscreen view, which is what it has to do: it used to
## run off the top and bottom with no way to reach the buttons down there. The menu is sized
## directly rather than the window, because that is what UiKit.panel() measures (the player's
## view, not the screen) -- and a headless window will not shrink anyway.
func test_the_panel_fits_a_splitscreen_view() -> void:
	var view_size := Vector2(640, 360) # one view of a four-player splitscreen at 1280 x 720
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.size = view_size
	for i in 4:
		await get_tree().process_frame
	assert_vector(menu.size).is_equal(view_size) # or the check below proves nothing
	var box: PanelContainer = menu.find_children("*", "PanelContainer", true, false)[0]
	assert_bool(Rect2(Vector2.ZERO, view_size).encloses(box.get_global_rect())) \
		.override_failure_message("the panel is %s in a %s view" % [box.get_global_rect(), view_size]).is_true()
	# It fits because the scroll gave up height, not because the panel is clipped.
	var scroll := _scroll()
	assert_float(scroll.custom_minimum_size.y).is_less(float(scroll.get_meta(&"max_height")))
