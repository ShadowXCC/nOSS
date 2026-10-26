extends GdUnitTestSuite
## The Local Drive types besides Racing (docs/UI_FLOW.md §6, §6.1): Endless (its road code), Sumo
## Wrestling (no Class step), Highway's Run mode, Drive again through Mini Games, and the Garage's
## Drive on the Class page.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"

var _holder: Control
var _stack: MenuStack
var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/local_types")
	PlayersMenu.countdown_s = 0.0
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Game.flow_return = {}
	PlayersMenu.countdown_s = 3.0
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	_requested.clear()
	Players.clear()
	Settings.profile.event_memory = {}
	Settings.profile.last_drive = {}
	Settings.profile.last_endless = {}
	Settings.profile.last_highway = {}
	Settings.profile.last_platform = "official.track.gt"


func after_test() -> void:
	if is_instance_valid(_holder):
		_holder.free()


func _on_event(e: RaceEvent, platform_id: String) -> void:
	_requested.append([e, platform_id])


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


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


func _page(flow: EventFlow) -> EventSettingsPage:
	_holder = Control.new()
	_holder.size = Vector2(1920, 1080)
	add_child(_holder)
	_stack = MenuStack.new()
	_holder.add_child(_stack)
	flow.recall()
	var page := EventSettingsPage.new()
	page.flow = flow
	_stack.push(page)
	return page


func _rows(page: MenuPage) -> Array:
	return page.body.get_children().filter(func(c: Node) -> bool: return c is Control and UiKit._focus_target(c) != null) \
		.map(func(c: Control) -> String: return String(UiKit._focus_target(c).accessibility_name).get_slice(":", 0))


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


## Endless: a code that isn't one says so and puts the road's back; a friend's code drives their
## road; New road makes another. Next picks the class (Cruiser or Sport).
func test_endless_and_its_road_code() -> void:
	var page := _page(EventFlow.make("endless"))
	await _frames(2)
	assert_str(page.title).is_equal("Endless")
	assert_array(_rows(page)).contains_exactly(["Road code", "New road", "Start in", "Lanes", "Drive on", "Traffic", "Garage cars",
		"Oncoming", "Speed traps", "Police", "Far apart", "Time", "Time runs", "Weather"])
	var e := page.flow.event
	var code := page.row_named("Road code") as LineEdit
	assert_str(code.text).is_equal(EndlessCode.encode(e.road_seed, e.biome))
	code.text = "not a code"
	code.text_submitted.emit(code.text)
	assert_str(page.status.text).is_equal("Not a road code")
	assert_str(code.text).is_equal(EndlessCode.encode(e.road_seed, e.biome))
	var friend := EndlessCode.encode(4242, EndlessBiomes.index_of("forest"))
	code.text = friend
	code.text_submitted.emit(friend)
	await _frames(2)
	assert_str(page.status.text).is_empty()
	assert_int(e.road_seed).is_equal(4242)
	assert_str((page.row_named("Road code") as LineEdit).text).is_equal(friend)
	(page.row_named("New road") as Button).pressed.emit()
	await _frames(2)
	assert_int(e.road_seed).is_not_equal(4242)
	assert_str(String(_focused().accessibility_name)).is_equal("New road")
	page.go_on()
	await _frames(2)
	var classes := _stack.top() as ClassPage
	var names := classes.body.get_children().filter(func(c: Node) -> bool: return c is Button).map(func(b: Button) -> String: return String(b.accessibility_name))
	assert_int(names.size()).is_equal(2)
	assert_bool(names.all(func(n: String) -> bool: return n.begins_with("Endless "))).is_true()


## Sumo Wrestling: its rows, no track pane, and Next straight to the players in its own class.
func test_sumo_goes_straight_to_the_players() -> void:
	var page := _page(EventFlow.make("mini", "sumo"))
	await _frames(2)
	assert_str(page.title).is_equal("Sumo Wrestling")
	assert_str(page.step_text()).is_equal("Step 2 of 3")
	assert_array(_rows(page)).contains_exactly(["Platforms", "Underneath", "Shrink", "Length", "Sudden death", "Drift", "AI cars",
		"AI skill", "AI models", "Time", "Time runs", "Weather"])
	assert_object(page.pane).is_null()
	assert_str(page.next_button.accessibility_description).is_equal("The players: each picks a car")
	page.go_on()
	await _frames(2)
	assert_str((_stack.top() as PlayersMenu).platform_id).is_equal(EventFlow.SUMO)


## Highway's Mode: Run swaps Way round for the Run row (the Lumen Ring's runs), the focus kept on
## Mode.
func test_highway_run_mode() -> void:
	var page := _page(EventFlow.make("highway"))
	await _frames(2)
	assert_array(_rows(page)).contains_exactly(["Highway", "Mode", "Traffic", "Police", "Way round", "Time", "Time runs", "Weather"])
	assert_array(["Way round: Clockwise", "Way round: Anticlockwise"]).contains([String(page.row_named("Way round").accessibility_name)])
	var mode := page.row_named("Mode")
	mode.grab_focus()
	for i in 2: # Score attack, Run
		(mode as Button).pressed.emit()
	await _frames(2)
	assert_array(_rows(page)).contains_exactly(["Highway", "Mode", "Traffic", "Police", "Run", "Time", "Time runs", "Weather"])
	assert_str(String(_focused().accessibility_name)).is_equal("Mode: Run")
	assert_str(page.flow.event.run).is_not_empty()


## Drive again for Kart Battle: its Players page over its Settings page, over Mini Games (Kart
## Battle focused), over Local Drive; back a page at a time.
func test_drive_again_through_mini_games() -> void:
	var last := EventFlow.make("mini", "kart_battle")
	last.recall()
	last.event.battle_min = 7
	Settings.profile.last_drive = last.to_dict()
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	var again: Button = runner.scene().find_child("DriveAgain", true, false)
	assert_str(again.accessibility_description).starts_with("Kart Battle · ")
	await _key(KEY_ENTER)
	await _frames(4)
	var stack := runner.scene().find_child("MenuStack", true, false) as MenuStack
	assert_int(stack.depth()).is_equal(4)
	assert_bool(stack.pages()[1] is MiniGamesPage).is_true()
	assert_bool(stack.top() is PlayersMenu).is_true()
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_str((stack.top() as EventSettingsPage).title).is_equal("Kart Battle")
	assert_str(String((stack.top() as EventSettingsPage).row_named("Minutes").accessibility_name)).is_equal("Minutes: 7")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(stack.top() is MiniGamesPage).is_true()
	assert_str(String(runner.scene().get_viewport().gui_get_focus_owner().accessibility_name)).is_equal("Kart Battle")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_str(String(runner.scene().get_viewport().gui_get_focus_owner().accessibility_name)).is_equal("Mini Games")


## The Garage's Drive: the Class page without a flow lists the classes that take the car, shows
## that car, and reports the pick.
func test_the_garage_class_page() -> void:
	_holder = Control.new()
	_holder.size = Vector2(1920, 1080)
	add_child(_holder)
	var page := ClassPage.new()
	page.car = "res://content/cars/noss_box" # a "car": not an open-wheeler, not a kart
	var got := [""]
	page.picked.connect(func(id: String) -> void: got[0] = id)
	_holder.add_child(page)
	await _frames(2)
	assert_str((page.find_child("Crumbs", true, false) as Label).text).is_equal("Garage › nOSS Box › Class")
	assert_str(page.step_text()).is_empty()
	assert_str(page.back_button.accessibility_description).is_equal("Back to nOSS Box") # its page (P7b)
	var ids := page.classes().map(func(r: PlatformLoader.Result) -> String: return String(r.platform.id))
	assert_array(ids).contains(["official.track.gt"])
	assert_array(ids).not_contains(["official.track.formula"])
	assert_str(ClassPage.car_for(PlatformLoader.load_official("official.track.gt").platform, page.car)).is_equal(page.car)
	(page.body.find_child("official_track_gt", true, false) as Button).pressed.emit()
	assert_str(got[0]).is_equal("official.track.gt")
	assert_bool(_requested.is_empty()).is_true()
