extends GdUnitTestSuite
## Every control on the settings pages has a description (docs/ACCESSIBILITY.md §2, the build
## rule): a screen reader reads it after the name, and a tabbed page's help line shows it. Every
## tab of Settings and Driving Settings, and every event type's Settings page, on Local Drive and
## hosting.

const DIR := "user://tests/descriptions"

var _holder: Control


func before() -> void:
	Players.clear()
	Settings.use_folder(DIR)


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	if is_instance_valid(_holder):
		_holder.free()


func _push(page: Control) -> Control:
	_holder = Control.new()
	_holder.size = Vector2(1920, 1080)
	add_child(_holder)
	var stack := MenuStack.new()
	_holder.add_child(stack)
	stack.push(page)
	return page


## "<where>: <name>" for each control in `page`'s focus order with no description.
func _undescribed(page: MenuPage, where: String) -> Array:
	var out := []
	for c: Control in page._focus_list():
		var t := UiKit._focus_target(c)
		if t and String(t.accessibility_description).strip_edges().is_empty():
			out.append("%s: %s" % [where, String(t.accessibility_name)])
	return out


func test_settings_and_driving_settings() -> void:
	Settings.primary.data.palette = "custom" # its colour rows too
	var missing := []
	var settings := _push(SettingsMenu.new()) as SettingsMenu
	await get_tree().process_frame
	for i in settings.tabs.size():
		settings.show_tab(i)
		missing.append_array(_undescribed(settings, "Settings › " + settings.tabs[i]))
	var driving := settings._open_player()
	await get_tree().process_frame
	for i in driving.tabs.size():
		driving.show_tab(i)
		missing.append_array(_undescribed(driving, "Driving Settings › " + driving.tabs[i]))
	Settings.primary.data.palette = "default"
	assert_array(missing).is_empty()


func test_event_settings_pages() -> void:
	var missing := []
	for where: String in ["local", "host"]:
		for v: String in EventFlow.RACING:
			for tt: bool in [false, true]:
				missing.append_array(await _event(EventFlow.make("racing", v, tt, where)))
		for v: String in EventFlow.MINI:
			missing.append_array(await _event(EventFlow.make("mini", v, false, where)))
		for t: String in EventFlow.PLAIN:
			missing.append_array(await _event(EventFlow.make(t, "", false, where)))
		# The rows that come with a choice: a kart cup, a highway run.
		var cup := EventFlow.make("racing", "kart", false, where)
		cup.cup = String(CupRun.list()[0].path)
		missing.append_array(await _event(cup, false))
		var run := EventFlow.make("highway", "", false, where)
		run.recall()
		run.event.sub = "run"
		missing.append_array(await _event(run, false))
	assert_array(missing).is_empty()


func _event(flow: EventFlow, recall := true) -> Array:
	if recall:
		flow.recall()
	if flow.context == "host":
		flow.server = ServerConfig.new()
	var page := EventSettingsPage.new()
	page.flow = flow
	_push(page)
	await get_tree().process_frame
	var out := _undescribed(page, "%s (%s)" % [flow.name(), flow.context])
	_holder.free()
	return out
