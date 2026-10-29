extends GdUnitTestSuite
## Custom's presets (docs/UI_FLOW.md §6.1): "Save preset" asks for a name and keeps the rows and the
## class in user://event_presets/<slug>.json (the folder follows Settings.use_folder); "Preset"
## steps through None and the saved ones, and picking one fills the rows; a race's and a time
## trial's are apart; "Delete preset" asks first.

const DIR := "user://tests/event_presets"

var _holder: Control
var _stack: MenuStack


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Settings.use_folder("user://")


func before_test() -> void:
	Settings.profile.event_memory = {}
	Settings.race_event = {}
	if DirAccess.dir_exists_absolute(EventPresets.dir):
		for file in DirAccess.get_files_at(EventPresets.dir):
			DirAccess.remove_absolute(EventPresets.dir.path_join(file))


func after_test() -> void:
	if is_instance_valid(_holder):
		_holder.free()


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _page(tt := false) -> EventSettingsPage:
	_holder = Control.new()
	_holder.size = Vector2(1920, 1080)
	add_child(_holder)
	_stack = MenuStack.new()
	_holder.add_child(_stack)
	var flow := EventFlow.racing("custom", tt)
	flow.recall()
	var page := EventSettingsPage.new()
	page.flow = flow
	_stack.push(page)
	return page


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


func _name(page: EventSettingsPage, label: String) -> String:
	return String(page.row_named(label).accessibility_name)


func test_the_folder_follows_use_folder() -> void:
	assert_str(EventPresets.dir).is_equal(DIR.path_join("event_presets/"))
	assert_str(EventPresets.slug("My Race!")).is_equal("my_race")
	assert_str(EventPresets.slug("  ")).is_equal("preset")


func test_custom_rows() -> void:
	var page := _page()
	await _frames(4)
	assert_str(page.title).is_equal("Custom race")
	assert_str(page.step_text()).is_equal("Step 2 of 4")
	var rows := page.body.get_children().map(func(c: Control) -> String:
		return String(UiKit._focus_target(c).accessibility_name).get_slice(":", 0) if UiKit._focus_target(c) else "")
	assert_array(rows).contains_exactly(["Preset", "Save preset", "Delete preset", "Track", "Practice", "Qualifying", "Race length",
		"Race", "AI cars", "AI skill", "AI cars look", "Start", "Drafting", "Fuel use", "Tire wear", "Restrictor", "Grid", "Collisions",
		"Track limits", "Items", "Time", "Time runs", "Weather"])
	assert_str(_name(page, "Preset")).is_equal("Preset: None")
	assert_bool((page.row_named("Delete preset") as Button).disabled).is_true()
	assert_str(page.row_named("Items").accessibility_description).starts_with("Kart classes only")
	_holder.free()
	page = _page(true)
	await _frames(4)
	assert_str(page.title).is_equal("Custom time trial")
	rows = page.body.get_children().map(func(c: Control) -> String:
		return String(UiKit._focus_target(c).accessibility_name).get_slice(":", 0) if UiKit._focus_target(c) else "")
	assert_array(rows).contains_exactly(["Preset", "Save preset", "Delete preset", "Track", "Track limits", "Time", "Time runs", "Weather"])


## Save: the name page, then the preset's in the list and picked; another setup, then the preset
## again fills the rows back.
func test_save_and_pick_a_preset() -> void:
	var page := _page()
	await _frames(4)
	var flow := page.flow
	flow.event.race_laps = 12
	flow.event.grid = "reverse"
	flow.class_id = "official.kart.light"
	flow.track = TrackLibrary.BUILTIN_DIR + "gearworks"
	(page.row_named("Save preset") as Button).pressed.emit()
	await _frames(4)
	var ask := _stack.top() as NamePage
	assert_object(ask).is_not_null()
	assert_str(ask.title).is_equal("Save preset")
	assert_str((ask.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive › Racing › Custom › Save preset")
	assert_str(String(_focused().accessibility_name)).is_equal("Name")
	(ask.find_child("Save", true, false) as Button).pressed.emit() # no name yet
	assert_str(ask.status.text).is_equal("Type a name")
	ask.value = "Night Laps"
	(ask.find_child("Save", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_object(_stack.top()).is_same(page)
	assert_bool(FileAccess.file_exists(EventPresets.dir.path_join("night_laps.json"))).is_true()
	assert_str(_name(page, "Preset")).is_equal("Preset: Night Laps")
	assert_str(String(_focused().accessibility_name)).is_equal("Preset: Night Laps")
	assert_bool((page.row_named("Delete preset") as Button).disabled).is_false()
	# Change the setup, then pick the preset again: None, then Night Laps.
	flow.event.race_laps = 3
	flow.event.grid = "random"
	flow.track = TrackLibrary.BUILTIN_DIR + "proving_ground"
	page.rebuild("Preset")
	await _frames(2)
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	page.row_named("Preset").gui_input.emit(right) # wraps to None
	await _frames(2)
	assert_str(_name(page, "Preset")).is_equal("Preset: None")
	page.row_named("Preset").gui_input.emit(right)
	await _frames(2)
	assert_str(_name(page, "Preset")).is_equal("Preset: Night Laps")
	assert_int(flow.event.race_laps).is_equal(12)
	assert_str(flow.event.grid).is_equal("reverse")
	assert_str(flow.class_id).is_equal("official.kart.light")
	assert_str(_name(page, "Track")).starts_with("Track: Gearworks")
	assert_str(_name(page, "Race")).is_equal("Race: 12 laps")
	# A time trial's presets are its own.
	assert_int(EventPresets.list(true).size()).is_zero()
	assert_int(EventPresets.list(false).size()).is_equal(1)


## Delete asks first: Keep keeps it, Delete takes it and the row goes back to None.
func test_delete_asks_first() -> void:
	var flow := EventFlow.racing("custom")
	flow.recall()
	var path := EventPresets.save("Sprint", flow)
	assert_str(path).ends_with("sprint.json")
	var page := _page()
	page.preset = path
	page.rebuild("Preset")
	await _frames(4)
	assert_str(_name(page, "Preset")).is_equal("Preset: Sprint")
	page.row_named("Delete preset").grab_focus()
	(page.row_named("Delete preset") as Button).pressed.emit()
	await _frames(4)
	var confirm := _stack.top() as ConfirmPage
	assert_str(confirm.title).is_equal("Delete Sprint?")
	assert_str(String(_focused().accessibility_name)).is_equal("Keep")
	(confirm.find_child("No", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(String(_focused().accessibility_name)).is_equal("Delete preset")
	(page.row_named("Delete preset") as Button).pressed.emit()
	await _frames(4)
	(_stack.top().find_child("Yes", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_str(_name(page, "Preset")).is_equal("Preset: None")
	assert_str(String(_focused().accessibility_name)).is_equal("Preset: None")
