extends GdUnitTestSuite
## Settings and Driving Settings in tabs (docs/UI_FLOW.md §4, §9, §10.1): the tabs switched by
## the tab actions from anywhere on the page (Q in the window, a player's own Next tab in their
## view) and by left and right on the row, the body scrolling to the focus, the help line, Reset
## to defaults, Clear downloads, and one name for the per-player settings.

const DIR := "user://tests/settings_tabs"


func before() -> void:
	Players.clear()
	Settings.use_folder(DIR)
	Settings.reset_keys(Settings.MACHINE.keys()) # not this machine's own (it keeps them in a new folder)


func after() -> void:
	Players.clear()
	ContentStore.root = "user://cache/content/"
	Settings.use_folder("user://")


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


## `page` full screen in a holder (pages fill their parent).
func _open(page: Control, room := Vector2(1920, 1080)) -> Control:
	var holder := Control.new()
	holder.size = room
	add_child(holder)
	holder.add_child(page)
	return page


func _focused(vp: Viewport = null) -> Control:
	vp = vp if vp else get_viewport()
	var c := Players.focus_of(vp)
	return c if c else vp.gui_get_focus_owner()


func _focused_name(vp: Viewport = null) -> String:
	var c := _focused(vp)
	return String(c.accessibility_name) if c else ""


func _row_names(page: MenuPage) -> Array:
	var out := []
	for c: Control in page._rows:
		var t := UiKit._focus_target(c)
		if t:
			out.append(String(t.accessibility_name).get_slice(":", 0))
	return out


## The tabs shown as current (pressed).
func _pressed_tabs(page: TabbedPage) -> Array:
	var out := []
	for i in page.tabs.size():
		if page.tab_row.button(i).button_pressed:
			out.append(page.tabs[i])
	return out


func test_settings_tabs_switch_by_action_and_by_key() -> void:
	var menu := _open(SettingsMenu.new()) as SettingsMenu
	await _frames()
	assert_array(Array(menu.tabs)).is_equal(["Display", "Sound", "Splitscreen", "General", "Players"])
	assert_str(menu.title).is_equal("Settings")
	assert_str((menu.find_child("Crumbs", true, false) as Label).text).is_equal("Settings")
	assert_str(menu.tab_name()).is_equal("Display")
	assert_array(_row_names(menu)).is_equal(["Graphics", "Fullscreen", "Reset to defaults"])
	assert_str(_focused_name()).is_equal("Graphics: Medium")
	# The action, from a row.
	_action(get_viewport(), "ui_tab_next")
	await _frames()
	assert_str(menu.tab_name()).is_equal("Sound")
	assert_str(_focused_name()).is_equal("Volume")
	assert_array(_pressed_tabs(menu)).is_equal(["Sound"]) # only the current one underlined
	assert_array(_row_names(menu)).is_equal(["Volume", "Own engine", "Other engines", "Tires and wind", "Effects", "Ambience", "Music",
		"Menus", "Spotter voice", "Narration", "Mono", "Reset to defaults"])
	# Q and E in the window, wrapping.
	await _key(KEY_Q)
	assert_str(menu.tab_name()).is_equal("Display")
	await _key(KEY_Q)
	assert_str(menu.tab_name()).is_equal("Players")
	assert_array(_row_names(menu)).is_equal(["Driving Settings", "Profiles"]) # nothing to reset
	await _key(KEY_E)
	assert_str(menu.tab_name()).is_equal("Display")
	assert_array(_pressed_tabs(menu)).is_equal(["Display"])
	# On the row: up from the first row, then right and left switch, the focus staying on it.
	_action(get_viewport(), "ui_up")
	await _frames()
	assert_object(_focused()).is_same(menu.tab_row.button())
	_action(get_viewport(), "ui_right")
	await _frames()
	assert_str(menu.tab_name()).is_equal("Sound")
	assert_object(_focused()).is_same(menu.tab_row.button())
	assert_str(_focused_name()).is_equal("Sound")
	_action(get_viewport(), "ui_left")
	_action(get_viewport(), "ui_left")
	await _frames()
	assert_str(menu.tab_name()).is_equal("Players")
	_action(get_viewport(), "ui_tab_prev") # from the row, the focus stays on it
	await _frames()
	assert_str(_focused_name()).is_equal("General")
	_action(get_viewport(), "ui_down")
	await _frames()
	assert_str(_focused_name()).is_equal("Units: km/h")
	menu.get_parent().free()
	# Mid-session (the pause menu): no Players tab.
	var paused := SettingsMenu.new()
	paused.in_session = true
	_open(paused)
	await _frames()
	assert_array(Array(paused.tabs)).is_equal(["Display", "Sound", "Splitscreen", "General"])
	assert_str((paused.find_child("Crumbs", true, false) as Label).text).is_equal("Pause › Settings")
	paused.get_parent().free()


## A text field being typed in keeps the tab keys (Q and E are letters); not typing, they switch.
func test_tabs_wait_while_typing() -> void:
	var page := _open(FieldTabs.new()) as TabbedPage
	await _frames()
	var field := page.body.find_children("*", "LineEdit", true, false)[0] as LineEdit
	field.grab_focus()
	await _frames() # reached by keys, a field waits for confirm (UiKit.text_field)
	field.edit()
	_action(get_viewport(), "ui_tab_next")
	await _frames()
	assert_str(page.tab_name()).is_equal("One")
	field.unedit()
	_action(get_viewport(), "ui_tab_next")
	await _frames()
	assert_str(page.tab_name()).is_equal("Two")
	page.get_parent().free()


## Hidden under another page (or a page opened in its place), its tabs stay put.
func test_tabs_only_switch_on_top() -> void:
	var stack := MenuStack.new()
	add_child(stack)
	var menu := SettingsMenu.new()
	stack.push(menu)
	await _frames()
	stack.push(SettingsMenu.new())
	await _frames()
	_action(get_viewport(), "ui_tab_next")
	await _frames()
	assert_str(menu.tab_name()).is_equal("Display")
	assert_str((stack.top() as SettingsMenu).tab_name()).is_equal("Sound")
	stack.free()


## In a player's view (their menus scaled), by their own pushed actions: the tabs switch, the
## body scrolls to the focus, and the help line follows it.
func test_driving_settings_in_a_players_view() -> void:
	Players.clear()
	var slot := Players.primary_slot()
	slot.profile.data.text_scale = 1.5
	var view := PlayerView.new()
	view.slot = slot
	view.size = Vector2(960, 540)
	add_child(view)
	slot.menu_target = view.viewport
	var menu := PlayerSettingsMenu.new()
	menu.slot = slot
	menu.crumbs = ["Players", "Driving Settings"]
	view.overlay_root.add_child(menu)
	await _frames(4)
	var vp := view.viewport
	assert_str(menu.title).is_equal("Driving Settings · %s" % slot.profile.display_name())
	assert_array(Array(menu.tabs)).is_equal(["Assists", "Comfort", "Vision & Hearing", "HUD & Display", "Controls"])
	assert_str(_focused_name(vp)).is_equal("ABS")
	assert_str(menu.help.text).is_equal("Brakes without locking")
	Players.push_action(vp, "ui_tab_next")
	await _frames()
	assert_str(menu.tab_name()).is_equal("Comfort")
	assert_array(_row_names(menu)).is_equal(["Camera shake", "Head movement", "Speed FOV", "Horizon lock", "Game speed", "Reset to defaults"])
	for i in 3:
		Players.push_action(vp, "ui_tab_next")
		await _frames()
	assert_str(menu.tab_name()).is_equal("Controls")
	# Down to Wheel setup, the last row before Reset: in view, and the help line says what it is.
	for i in 40:
		if _focused_name(vp) == "Wheel setup":
			break
		Players.push_action(vp, "ui_down")
		await _frames(2)
	var focused := _focused(vp)
	assert_str(String(focused.accessibility_name)).is_equal("Wheel setup")
	assert_int(menu.scroll().scroll_vertical).is_greater(0)
	assert_bool(_in_view(menu, focused)).is_true()
	assert_str(menu.help.text).is_equal("Device, axes, rotation and force feedback")
	# A spinner's description without its "Left and right to change".
	Players.push_action(vp, "ui_tab_prev")
	await _frames()
	assert_str(menu.tab_name()).is_equal("HUD & Display")
	for i in 3:
		Players.push_action(vp, "ui_down")
		await _frames(2)
	assert_str(_focused_name(vp)).starts_with("Font")
	assert_str(menu.help.text).is_equal("Clear: an easy-to-read font")
	# Cancel from the player's own input closes it.
	var closes := [0]
	menu.closed.connect(func() -> void: closes[0] += 1)
	Players.push_action(vp, "ui_cancel")
	assert_int(closes[0]).is_equal(1)
	await _frames()
	view.free()
	slot.profile.data.text_scale = 1.0
	Players.clear()


func test_the_body_scrolls_to_the_focus_in_the_window() -> void:
	var menu := _open(SettingsMenu.new(), Vector2(1920, 1080)) as SettingsMenu
	await _frames()
	menu.show_tab(1)
	await _frames(2)
	for i in 11:
		_action(get_viewport(), "ui_down")
		await _frames(2)
	var focused := _focused()
	assert_str(String(focused.accessibility_name)).is_equal("Reset to defaults")
	assert_int(menu.scroll().scroll_vertical).is_greater(0)
	assert_bool(_in_view(menu, focused)).is_true()
	assert_str(menu.help.text).is_equal("Sound settings back to their defaults")
	# A new tab starts at the top.
	_action(get_viewport(), "ui_tab_next")
	await _frames(2)
	assert_int(menu.scroll().scroll_vertical).is_equal(0)
	menu.get_parent().free()


func test_reset_to_defaults_asks_first() -> void:
	Settings.set_value("master_volume", 0.3)
	Settings.set_value("vol_music", 0.1)
	Settings.set_value("units", "imperial")
	var menu := _open(SettingsMenu.new()) as SettingsMenu
	await _frames()
	menu.show_tab(1)
	await _frames()
	var reset := menu.find_child("Reset", true, false) as Button
	reset.grab_focus()
	reset.pressed.emit()
	await _frames()
	var confirm := _confirm(menu)
	assert_object(confirm).is_not_null()
	assert_str(confirm.title).is_equal("Reset Sound?")
	assert_str(_focused_name()).is_equal("Keep")
	assert_bool(reset.is_visible_in_tree()).is_false()
	_action(get_viewport(), "ui_cancel") # keep
	await _frames()
	assert_float(Settings.master_volume).is_equal(0.3)
	assert_object(_focused()).is_same(reset)
	reset.pressed.emit()
	await _frames()
	(_confirm(menu).find_child("Yes", true, false) as Button).pressed.emit()
	await _frames()
	assert_float(Settings.master_volume).is_equal(0.8)
	assert_float(Settings.vol_music).is_equal(0.6)
	assert_str(Settings.units).is_equal("imperial") # another tab's
	assert_object(_confirm(menu)).is_null()
	assert_str(_focused_name()).is_equal("Reset to defaults")
	# The sliders show the defaults.
	var volume := menu.body.find_children("*", "HSlider", true, false)[0] as HSlider
	assert_float(volume.value).is_equal(80.0)
	menu.get_parent().free()
	Settings.reset_keys(["units"])


## On the page stack (the main menu's), the question is a page of its own on it.
func test_reset_on_the_stack() -> void:
	Settings.set_value("graphics", "high")
	var stack := MenuStack.new()
	add_child(stack)
	var menu := SettingsMenu.new()
	stack.push(menu)
	await _frames()
	(menu.find_child("Reset", true, false) as Button).grab_focus()
	(menu.find_child("Reset", true, false) as Button).pressed.emit()
	await _frames()
	assert_int(stack.depth()).is_equal(2)
	assert_bool(stack.top() is ConfirmPage).is_true()
	assert_str((stack.top().find_child("Crumbs", true, false) as Label).text).is_equal("Settings › Reset Display")
	(stack.top().find_child("Yes", true, false) as Button).pressed.emit()
	await _frames()
	assert_int(stack.depth()).is_equal(1)
	assert_str(Settings.graphics).is_equal("medium")
	assert_str(_focused_name()).is_equal("Reset to defaults")
	stack.free()


## Controls' reset takes the custom buttons and keys too, and says so; the wheel's setup stays.
func test_driving_settings_reset() -> void:
	var p := Settings.primary
	p.data.input.bindings = { "kb_full": { "brake": [{ "key": KEY_K }] } }
	p.data.input.toggles = ["throttle"]
	p.data.input.presets.gamepad = "pad_left_hand"
	p.data.wheel = { "rotation_deg": 540.0 }
	p.data.camera_shake = 0.1
	p.save()
	var menu := PlayerSettingsMenu.new()
	menu.profile = p
	_open(menu)
	await _frames()
	menu.show_tab(4)
	await _frames()
	(menu.find_child("Reset", true, false) as Button).pressed.emit()
	await _frames()
	var confirm := _confirm(menu)
	assert_str(confirm.title).is_equal("Reset Controls?")
	assert_str(confirm.detail).is_equal("Custom buttons and keys go too. Wheel setup stays.")
	(confirm.find_child("Yes", true, false) as Button).pressed.emit()
	await _frames()
	assert_dict(p.data.input.bindings).is_empty()
	assert_array(p.data.input.toggles).is_empty()
	assert_str(String(p.data.input.presets.gamepad)).is_equal("pad_standard")
	assert_dict(p.data.wheel).is_equal({ "rotation_deg": 540.0 })
	assert_float(p.data.camera_shake).is_equal(0.1) # Comfort's
	# Saved, and the defaults copied: changing them now leaves DEFAULTS alone.
	assert_dict(PlayerProfile.load_id(p.id).data.input.bindings).is_empty()
	p.data.input.toggles.append("brake")
	assert_array(PlayerProfile.DEFAULTS.input.toggles).is_empty()
	p.reset_keys(["input.toggles", "hud_hidden", "assists"])
	p.data.hud_hidden.append("speed")
	p.data.assists.abs = false
	assert_array(PlayerProfile.DEFAULTS.hud_hidden).is_empty()
	assert_bool(PlayerProfile.DEFAULTS.assists.abs).is_true()
	p.reset_keys(["hud_hidden", "assists", "wheel", "camera_shake"])
	menu.get_parent().free()


## A row that comes or goes builds only this tab again, the focus back on its row.
func test_custom_colours_rebuild_the_tab() -> void:
	var menu := PlayerSettingsMenu.new()
	menu.profile = Settings.primary
	_open(menu)
	await _frames()
	menu.show_tab(2)
	await _frames()
	var colours := _focused() as Button
	assert_str(String(colours.accessibility_name)).starts_with("Colours")
	var before := _row_names(menu).size()
	for i in Palette.PRESET_NAMES.size():
		if String(colours.accessibility_name).ends_with("Custom"):
			break
		_action(get_viewport(), "ui_right")
		await _frames()
		colours = _focused() as Button
	await _frames()
	assert_str(menu.tab_name()).is_equal("Vision & Hearing")
	assert_int(_row_names(menu).size()).is_equal(before + 4)
	assert_str(_focused_name()).starts_with("Colours")
	Settings.primary.reset_keys(["palette"])
	menu.get_parent().free()


func test_clear_downloads() -> void:
	ContentStore.root = DIR.path_join("cache/")
	DirAccess.make_dir_recursive_absolute(ContentStore.root.path_join("cars/abc"))
	var f := FileAccess.open(ContentStore.root.path_join("cars/abc/model.glb"), FileAccess.WRITE)
	var bytes := PackedByteArray()
	bytes.resize(1_500_000)
	f.store_buffer(bytes)
	f.close()
	var menu := _open(SettingsMenu.new()) as SettingsMenu
	await _frames()
	menu.show_tab(3)
	await _frames()
	var clear := _button(menu, "Clear downloads")
	assert_str(clear.text).is_equal("Clear downloads (1.4 MB)")
	assert_bool(clear.disabled).is_false()
	clear.grab_focus()
	clear.pressed.emit()
	await _frames()
	var confirm := _confirm(menu)
	assert_str(confirm.title).is_equal("Clear downloads?")
	assert_str(confirm.detail).starts_with("1.4 MB of cars and tracks")
	(confirm.find_child("No", true, false) as Button).pressed.emit()
	await _frames()
	assert_bool(FileAccess.file_exists(ContentStore.root.path_join("cars/abc/model.glb"))).is_true()
	clear.pressed.emit()
	await _frames()
	(_confirm(menu).find_child("Yes", true, false) as Button).pressed.emit()
	await _frames()
	assert_bool(DirAccess.dir_exists_absolute(ContentStore.root)).is_false()
	assert_str(_focused_name()).is_equal("Clear downloads (0 MB)")
	menu.get_parent().free()
	# Online, a host serves from it: off.
	var online := _open(OnlineSettings.new()) as SettingsMenu
	await _frames()
	online.show_tab(3)
	await _frames()
	clear = _button(online, "Clear downloads")
	assert_bool(clear.disabled).is_true()
	assert_str(String(clear.accessibility_description)).is_equal("Not while online")
	online.get_parent().free()
	assert_str(SettingsMenu.size_text(0)).is_equal("0 MB")
	assert_str(SettingsMenu.size_text(12_900_000)).is_equal("12.3 MB")
	assert_str(SettingsMenu.size_text(3 << 30)).is_equal("3.00 GB")


## The Players tab opens Driving Settings and Profiles as pages; Back comes back to the button.
func test_players_tab_opens_pages() -> void:
	var menu := _open(SettingsMenu.new()) as SettingsMenu
	await _frames()
	menu.show_tab(4)
	await _frames()
	var driving := _button(menu, "Driving Settings")
	assert_str(String(driving.accessibility_description)).is_equal("%s: assists, comfort, HUD and controls" % Settings.primary.display_name())
	driving.grab_focus()
	driving.pressed.emit()
	await _frames()
	var sub := menu.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is PlayerSettingsMenu)
	assert_int(sub.size()).is_equal(1)
	var page := sub[0] as PlayerSettingsMenu
	assert_str((page.find_child("Crumbs", true, false) as Label).text).is_equal("Settings › Driving Settings")
	assert_bool(driving.is_visible_in_tree()).is_false()
	# Its own sub-page: Buttons and keys, with the tab actions in it.
	page.show_tab(4)
	await _frames()
	_button(page, "Buttons and keys").grab_focus()
	_button(page, "Buttons and keys").pressed.emit()
	await _frames()
	var keys := page.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is BindingsMenu)
	assert_int(keys.size()).is_equal(1)
	var names := []
	for b: Button in (keys[0] as BindingsMenu).body.find_children("*", "Button", true, false):
		names.append(String(b.accessibility_name).get_slice(":", 0))
	assert_array(names).contains(["Previous tab", "Next tab"])
	_action(get_viewport(), "ui_cancel")
	await _frames()
	assert_str(_focused_name()).is_equal("Buttons and keys")
	_action(get_viewport(), "ui_cancel")
	await _frames()
	assert_object(_focused()).is_same(driving)
	_button(menu, "Profiles").pressed.emit()
	await _frames()
	var profiles := menu.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is ProfilesMenu)
	assert_int(profiles.size()).is_equal(1)
	assert_object(_button(profiles[0], "Driving Settings")).is_not_null()
	menu.get_parent().free()


## "Driving Settings" everywhere (§9.2): no "Player settings", "Settings" or "More settings".
func test_one_name_for_driving_settings() -> void:
	var first := FirstBootMenu.new()
	add_child(first)
	await _frames()
	var texts := first.find_children("*", "Button", true, false).map(func(b: Button) -> String: return UiKit.text_of(b))
	assert_array(texts).contains(["Driving Settings"])
	assert_array(texts).not_contains(["More settings"])
	first.free()
	var pause := PauseMenu.new()
	add_child(pause)
	await _frames()
	texts = pause.find_children("*", "Button", true, false).map(func(b: Button) -> String: return UiKit.text_of(b))
	assert_array(texts).contains(["Driving Settings"])
	pause.free()


## Wheel setup is a page; its rows scroll.
func test_wheel_setup_is_a_page() -> void:
	Players.clear()
	var slot := Players.primary_slot()
	var wheel := WheelMenu.new()
	wheel.slot = slot
	_open(wheel, Vector2(1920, 1080))
	await _frames(4)
	assert_str(wheel.title).is_equal("Wheel setup")
	for i in 30:
		_action(get_viewport(), "ui_down")
		await _frames(2)
		if _focused_name() == "Test FFB":
			break
	assert_str(_focused_name()).is_equal("Test FFB")
	assert_int(wheel.scroll().scroll_vertical).is_greater(0)
	assert_bool(_in_view(wheel, _focused())).is_true()
	wheel.get_parent().free()
	Players.clear()


static func _confirm(page: Node) -> ConfirmPage:
	var found := page.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is ConfirmPage and n.is_inside_tree() and not n.is_queued_for_deletion())
	return found[0] if not found.is_empty() else null


static func _button(page: Node, prefix: String) -> Button:
	for b: Button in page.find_children("*", "Button", true, false):
		if UiKit.text_of(b).begins_with(prefix) and not b.is_queued_for_deletion():
			return b
	return null


static func _action(vp: Viewport, action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		vp.push_input(e)


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


static func _in_view(page: MenuPage, c: Control) -> bool:
	var area := page.scroll().get_global_rect()
	var r := c.get_global_rect()
	return r.position.y >= area.position.y - 1.0 and r.end.y <= area.end.y + 1.0


## Settings while online.
class OnlineSettings:
	extends SettingsMenu

	func _online() -> bool:
		return true


## Two tabs with a text field each.
class FieldTabs:
	extends TabbedPage

	func _ready() -> void:
		tabs = ["One", "Two"]
		super._ready()

	func _build_tab(which: String) -> void:
		add_row(UiKit.text_field("Name " + which, "", func(_t: String) -> void: pass))

	func _can_reset(_which: String) -> bool:
		return false
