extends GdUnitTestSuite
## Pages (docs/UI_FLOW.md §1, §2, §4): the breadcrumb and step row, the Back row and cancel, the
## prompt bar following the focus, the right pane, the confirm page, and the body scrolling to the
## focus in the main window and inside a player's view.


func before() -> void:
	Settings.use_folder("user://tests/menu_page")


func after() -> void:
	Players.clear()
	Devices.test_devices = []
	Devices.last_family = "keyboard"
	Settings.use_folder("user://")


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _page(rows := 0, room := Vector2(1920, 1080)) -> MenuPage:
	var page := MenuPage.new()
	page.title = "Regular race"
	page.crumbs = ["Local Drive", "Racing", "Regular", "Settings"]
	page.steps = ["Event", "Settings", "Class", "Players"]
	page.step = 1
	var holder := Control.new() # pages fill their parent
	holder.size = room
	add_child(holder)
	holder.add_child(page)
	for i in rows:
		page.add_row(UiKit.button("Row %d" % i, func() -> void: pass))
	page.chain()
	return page


func test_crumbs_steps_and_title() -> void:
	var page := _page(2)
	await _frames()
	assert_str((page.find_child("Title", true, false) as Label).text).is_equal("Regular race")
	assert_str((page.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive › Racing › Regular › Settings")
	var steps := page.find_child("Steps", true, false) as RichTextLabel
	assert_bool(steps.visible).is_true()
	assert_str(page.step_text()).is_equal("Step 2 of 4")
	assert_str(steps.get_parsed_text()).is_equal("Step 2 of 4   Event · Settings · Class · Players")
	assert_str(steps.text).contains("[color=#%s]Settings[/color]" % UiKit.ACCENT.to_html(false))
	assert_str(String(steps.accessibility_name)).is_equal("Step 2 of 4: Settings")
	# The look (§2): 34 px rows 72 tall, a 56 px title, the main menu's background.
	assert_int(page.theme.default_font_size).is_equal(34)
	assert_int((page.find_child("Title", true, false) as Label).get_theme_font_size(&"font_size")).is_equal(56)
	assert_float(page.body.get_child(0).size.y).is_greater_equal(72.0)
	assert_object((page.find_child("Background", true, false) as ColorRect).color).is_equal(UiKit.BACKGROUND)
	page.get_parent().free()
	# Off an event's flow: crumbs, no step row.
	var plain := MenuPage.new()
	plain.title = "Settings"
	plain.crumbs = ["Settings"]
	add_child(plain)
	await _frames()
	assert_bool((plain.find_child("Steps", true, false) as Control).visible).is_false()
	assert_str((plain.find_child("Crumbs", true, false) as Label).text).is_equal("Settings")
	plain.free()


func test_back_row_and_cancel_close_it() -> void:
	var page := _page(2)
	await _frames()
	var closes := [0]
	page.closed.connect(func() -> void: closes[0] += 1)
	assert_object(page.back_button).is_not_null()
	assert_str(page.back_button.text).is_equal("Back")
	# Back is the last row: up from the first wraps to it.
	assert_str(String((get_viewport().gui_get_focus_owner() as Button).text)).is_equal("Row 0")
	page.back_button.pressed.emit()
	assert_int(closes[0]).is_equal(1)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	get_viewport().push_input(cancel)
	assert_int(closes[0]).is_equal(2)
	page.get_parent().free()


func test_the_prompt_bar_follows_the_focus() -> void:
	var page := MenuPage.new()
	page.title = "Prompts"
	page.prompts = [["tabs", "Tabs"]]
	add_child(page)
	var button := page.add_row(UiKit.button("Plain", func() -> void: pass)) as Button
	var spinner := page.add_row(UiKit.spinner("Laps", [[1, "1"], [2, "2"]], 1, func(_v: int) -> void: pass)) as Button
	var field := page.add_row(UiKit.text_field("Name", "", func(_t: String) -> void: pass))
	page.chain(false)
	button.grab_focus()
	await _frames()
	assert_array(page.prompt_bar.entries()).is_equal([["confirm", "Select"], ["tabs", "Tabs"], ["cancel", "Back"]])
	spinner.grab_focus()
	assert_array(page.prompt_bar.entries()).is_equal([["confirm", "Select"], ["change", "Change"], ["tabs", "Tabs"], ["cancel", "Back"]])
	(field.get_child(1) as LineEdit).grab_focus()
	assert_array(page.prompt_bar.entries()).is_equal([["confirm", "Type"], ["tabs", "Tabs"], ["cancel", "Back"]])
	# Shown as the window's last device: the keyboard's keys, then a PlayStation pad's.
	Devices.last_family = "keyboard"
	button.grab_focus()
	await _frames()
	assert_array(_glyph_names(page.prompt_bar)).is_equal(["Enter", "Select", "Q", "E", "Tabs", "Esc", "Back"])
	Devices.last_family = "playstation"
	await _frames()
	assert_array(_glyph_names(page.prompt_bar)).is_equal(["Cross", "Select", "L1", "R1", "Tabs", "Circle", "Back"])
	page.free()


func test_the_pane_shows_only_with_room() -> void:
	var page := _page(2)
	page.set_pane(ColorRect.new())
	await _frames()
	assert_bool(page.pane_shown()).is_true()
	(page.get_parent() as Control).size = Vector2(1000, 1080) # text at 2.0, a small view
	await _frames()
	assert_bool(page.pane_shown()).is_false()
	page.get_parent().free()


## Down to the last of many rows by ui_down: the focused row is always in view.
func test_the_body_scrolls_to_the_focus() -> void:
	var page := _page(30)
	await _frames(4)
	for i in 29:
		_action(get_viewport(), "ui_down")
		await _frames(2)
	var focused := get_viewport().gui_get_focus_owner() as Button
	assert_str(focused.text).is_equal("Row 29")
	assert_int(page.scroll().scroll_vertical).is_greater(0)
	assert_bool(_in_view(page, focused)).is_true()
	# And back up to the top.
	for i in 29:
		_action(get_viewport(), "ui_up")
		await _frames(2)
	focused = get_viewport().gui_get_focus_owner() as Button
	assert_str(focused.text).is_equal("Row 0")
	assert_bool(_in_view(page, focused)).is_true()
	page.get_parent().free()


## In a player's view (a quarter of the screen, its menus scaled), driven by that player's own
## pushed actions as Players does it.
func test_the_body_scrolls_to_the_focus_in_a_players_view() -> void:
	Players.clear()
	var slot := Players.primary_slot()
	slot.profile.data.text_scale = 1.5
	var view := PlayerView.new()
	view.slot = slot
	view.size = Vector2(960, 540)
	add_child(view)
	slot.menu_target = view.viewport
	var page := MenuPage.new()
	page.title = "Driving Settings"
	view.overlay_root.add_child(page)
	for i in 24:
		page.add_row(UiKit.spinner("Row %d" % i, [[0, "Off"], [1, "On"]], 0, func(_v: int) -> void: pass))
	page.chain()
	await _frames(4)
	for i in 23:
		Players.push_action(view.viewport, "ui_down")
		await _frames(2)
	var focused := Players.focus_of(view.viewport) as Button
	assert_str(String(focused.accessibility_name)).starts_with("Row 23")
	assert_int(page.scroll().scroll_vertical).is_greater(0)
	assert_bool(_in_view(page, focused)).is_true()
	# Cancel from the player's own input closes it.
	var closes := [0]
	page.closed.connect(func() -> void: closes[0] += 1)
	Players.push_action(view.viewport, "ui_cancel")
	assert_int(closes[0]).is_equal(1)
	await _frames()
	view.free()
	slot.profile.data.text_scale = 1.0
	Players.clear()


## The safe answer is focused first; cancel is the safe answer too.
func test_confirm_page() -> void:
	var page := ConfirmPage.new()
	page.title = "Reset Sound?"
	page.detail = "Every volume goes back to its default."
	page.no_text = "Keep"
	page.yes_text = "Reset"
	add_child(page)
	await _frames()
	assert_object(page.back_button).is_null()
	assert_str((get_viewport().gui_get_focus_owner() as Button).text).is_equal("Keep")
	var said := []
	page.confirmed.connect(func() -> void: said.append("yes"))
	page.closed.connect(func() -> void: said.append("no"))
	(page.find_child("Yes", true, false) as Button).pressed.emit()
	(page.find_child("No", true, false) as Button).pressed.emit()
	_action(get_viewport(), "ui_cancel")
	assert_array(said).is_equal(["yes", "no", "no"])
	page.free()


## The pause menu asks with a ConfirmPage before a restart that would lose a whole ladder.
func test_pause_menu_restart_asks_on_a_confirm_page() -> void:
	var pause := PauseMenu.new()
	pause.can_restart = true
	pause.confirm_restart = true
	pause.restart_text = "Restart ladder"
	add_child(pause)
	await _frames()
	var restarts := [0]
	pause.restart.connect(func() -> void: restarts[0] += 1)
	var restart: Button = pause.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Restart ladder")[0]
	restart.pressed.emit()
	await _frames()
	var confirm := pause.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is ConfirmPage)
	assert_int(confirm.size()).is_equal(1)
	assert_str((confirm[0] as ConfirmPage).title).is_equal("Restart ladder?")
	assert_bool(restart.is_visible_in_tree()).is_false()
	_action(get_viewport(), "ui_cancel") # keep going: back to the pause menu
	await _frames()
	assert_int(restarts[0]).is_equal(0)
	assert_bool(restart.is_visible_in_tree()).is_true()
	restart.pressed.emit()
	await _frames()
	(pause.find_child("Yes", true, false) as Button).pressed.emit()
	assert_int(restarts[0]).is_equal(1)
	pause.free()


static func _action(vp: Viewport, action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		vp.push_input(e)


static func _in_view(page: MenuPage, c: Control) -> bool:
	var area := page.scroll().get_global_rect()
	var r := c.get_global_rect()
	return r.position.y >= area.position.y - 1.0 and r.end.y <= area.end.y + 1.0


static func _glyph_names(bar: PromptBar) -> Array:
	var out := []
	for group in bar.get_children():
		for c in group.get_children():
			if c is TextureRect:
				out.append(String(c.accessibility_name))
			elif c is Label:
				out.append((c as Label).text)
			elif c is PanelContainer:
				out.append((c.get_child(0) as Label).text)
	return out
