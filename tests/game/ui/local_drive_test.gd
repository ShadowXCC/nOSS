extends GdUnitTestSuite
## Local Drive (docs/UI_FLOW.md §5): boot to a race with only the keyboard and with only a
## controller (the M4 acceptance; the screen-reader part is tools/a11y_check.py): main menu ->
## Local Drive -> Racing -> Regular -> Settings -> Class -> Players -> Ready, by directions and
## confirm alone. Stock Car skips the Class step; the Race | Time Trial switch; Drive again; the
## results' Event menu back to the Settings page.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"
const PAD_ID := 7

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/local_drive")
	PlayersMenu.countdown_s = 0.0 # everyone Ready starts at once (players_menu_test has the countdown)
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Game.hold_scenes = false
	Game.flow_return = {}
	Game.reopen_flow = false
	PlayersMenu.countdown_s = 3.0
	Players.clear()
	Devices.test_devices = []
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	_requested.clear()
	Settings.race_event = {}
	Settings.profile.event_memory = {}
	Settings.profile.last_drive = {}
	Settings.profile.last_track = ""
	Settings.profile.last_platform = "official.track.gt"


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


func _button(b: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = PAD_ID
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await _frames()
	var up := e.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await _frames()


func _focused(runner: GdUnitSceneRunner) -> String:
	var c := runner.scene().get_viewport().gui_get_focus_owner()
	return String(c.accessibility_name) if c else "<none>"


func _stack(runner: GdUnitSceneRunner) -> MenuStack:
	return runner.scene().find_child("MenuStack", true, false) as MenuStack


func _named(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c).is_not_empty()


## From the main menu to a started Regular race with `down`, `up` and `confirm` (keys or buttons).
func _walk(runner: GdUnitSceneRunner, down: Callable, up: Callable, confirm: Callable) -> void:
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Local Drive")
	await confirm.call()
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Racing")
	await confirm.call()
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Regular")
	assert_bool(_stack(runner).top() is RacingPage).is_true()
	await confirm.call()
	await _frames(4)
	var settings := _stack(runner).top() as EventSettingsPage
	assert_object(settings).is_not_null()
	_named(settings)
	assert_str(settings.title).is_equal("Regular race")
	assert_str((settings.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive › Racing › Regular › Settings")
	assert_str(settings.step_text()).is_equal("Step 2 of 4")
	assert_str(_focused(runner)).starts_with("Track: ")
	await down.call()
	assert_str(_focused(runner)).is_equal("Practice: Off")
	await up.call()
	await up.call() # wraps to Back
	await up.call()
	assert_str(_focused(runner)).is_equal("Next")
	await confirm.call()
	await _frames(4)
	assert_bool(_stack(runner).top() is ClassPage).is_true()
	assert_str(_focused(runner)).is_equal("Track GT, last used")
	await down.call()
	assert_str(_focused(runner)).starts_with("Track Stock Car")
	await up.call()
	await confirm.call()
	await _frames(4)
	assert_bool(_stack(runner).top() is PlayersMenu).is_true()
	await confirm.call() # joins
	await _frames(6)
	assert_int(Players.count()).is_equal(1)
	# The card: Up from the first row wraps to Leave, then Ready.
	var v := Players.slots[0].menu_target
	assert_object(v).is_not_null()
	await up.call()
	await up.call()
	var c := Players.focus_of(v)
	assert_str(UiKit.text_of(c as Button)).starts_with("Ready")
	await confirm.call()
	await _frames(4)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("race")
	assert_int(e.race_laps).is_equal(5)
	assert_int(e.ai_count).is_equal(7)
	assert_str(String(_requested[0][1])).is_equal("official.track.gt")
	assert_str(String(Settings.profile.last_drive.variant)).is_equal("regular")


func test_keyboard_only_boot_to_race() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _walk(runner, _key.bind(KEY_DOWN), _key.bind(KEY_UP), _key.bind(KEY_ENTER))


func test_controller_only_boot_to_race() -> void:
	Devices.test_devices = [{ "kind": "gamepad", "key": "pad:test#%d" % PAD_ID, "name": "Test pad", "id": PAD_ID, "guid": "test%d" % PAD_ID, "preset": "pad_standard" }]
	var runner := scene_runner(TITLE_SCENE)
	await _walk(runner, _button.bind(JOY_BUTTON_DPAD_DOWN), _button.bind(JOY_BUTTON_DPAD_UP), _button.bind(JOY_BUTTON_A))


## Local Drive's page: its types in order, the step row following the one in focus.
func test_local_drive_page() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER)
	await _frames(4)
	var page := _stack(runner).top() as LocalDrivePage
	assert_object(page).is_not_null()
	_named(page)
	assert_str((page.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive")
	assert_str(page.step_text()).is_equal("Step 1 of 4")
	var names := page.body.get_children().map(func(b: Button) -> String: return String(b.accessibility_name))
	assert_array(names).contains_exactly(["Racing", "Endless", "Highway", "Mini Games", "Free Drive"])
	assert_str(page.back_button.accessibility_description).is_equal("Back to the main menu")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_int(_stack(runner).depth()).is_zero()
	assert_str(_focused(runner)).is_equal("Local Drive")


## Stock Car: ovals only, its own class, and no Class step: Next goes to the players.
func test_stock_car_skips_the_class_step() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	await _key(KEY_ENTER) # Racing
	await _frames(4)
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Stock Car")
	var racing := _stack(runner).top() as RacingPage
	assert_str(racing.step_text()).is_equal("Step 1 of 3") # the steps of the type in focus
	await _key(KEY_ENTER)
	await _frames(4)
	var settings := _stack(runner).top() as EventSettingsPage
	assert_str(settings.title).is_equal("Stock Car race")
	assert_str(settings.step_text()).is_equal("Step 2 of 3")
	assert_str(_focused(runner)).starts_with("Track: Piedmont Speedway")
	assert_str(settings.pane.text()).contains("Oval · Real-world")
	await _key(KEY_RIGHT) # the only oval: it stays
	assert_str(_focused(runner)).starts_with("Track: Piedmont Speedway")
	for i in 3:
		await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Laps: 10 laps")
	assert_str(settings.next_button.accessibility_description).is_equal("The players: each picks a car")
	settings.next_button.grab_focus()
	await _key(KEY_ENTER)
	await _frames(4)
	var players := _stack(runner).top() as PlayersMenu
	assert_object(players).is_not_null()
	assert_str(players.platform_id).is_equal(EventFlow.STOCK_CAR)
	await _key(KEY_ESCAPE) # nobody joined: back
	await _frames(4)
	assert_object(_stack(runner).top()).is_same(settings)
	assert_str(_focused(runner)).is_equal("Next")


## The Race | Time Trial switch: E (ui_tab_next) from a type flips it, the descriptions follow,
## and a Regular time trial has no AI rows; its class goes on to the players, and Ready starts it.
func test_time_trial_switch() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	await _key(KEY_ENTER) # Racing
	await _frames(4)
	var racing := _stack(runner).top() as RacingPage
	assert_str(String(racing.get_viewport().gui_get_focus_owner().accessibility_description)).is_equal("Laps against AI, simple settings")
	await _key(KEY_E)
	await _frames(2)
	assert_bool(racing.tt).is_true()
	assert_str(_focused(runner)).is_equal("Regular")
	assert_str(String(racing.get_viewport().gui_get_focus_owner().accessibility_description)).is_equal("Laps against your ghost")
	assert_str(racing.step_text()).is_equal("Step 1 of 4")
	var kart: Button = racing.body.find_child("Kart", false, false)
	assert_bool(kart.disabled).is_false()
	assert_str(kart.accessibility_description).is_equal("Kart laps against your ghost")
	# Q flips it back, and again.
	await _key(KEY_Q)
	assert_bool(racing.tt).is_false()
	await _key(KEY_Q)
	assert_bool(racing.tt).is_true()
	await _key(KEY_ENTER)
	await _frames(4)
	var settings := _stack(runner).top() as EventSettingsPage
	assert_str(settings.title).is_equal("Regular time trial")
	var rows := settings.body.get_children().map(func(b: Button) -> String: return String(b.accessibility_name).get_slice(":", 0))
	assert_array(rows).contains_exactly(["Track", "Time", "Time runs", "Weather"])
	settings.next_button.pressed.emit()
	await _frames(4)
	assert_bool(_stack(runner).top() is ClassPage).is_true()
	assert_str((_stack(runner).top() as ClassPage).step_text()).is_equal("Step 3 of 4")
	await _key(KEY_ENTER) # GT, last used
	await _frames(4)
	assert_bool(_stack(runner).top() is PlayersMenu).is_true()
	assert_bool(_requested.is_empty()).is_true()
	await _key(KEY_ENTER) # joins
	await _frames(6)
	await _key(KEY_UP)
	await _key(KEY_UP) # Ready
	await _key(KEY_ENTER)
	await _frames(4)
	assert_int(_requested.size()).is_equal(1)
	assert_str((_requested[0][0] as RaceEvent).kind).is_equal("time_trial")
	assert_bool(bool(Settings.profile.last_drive.tt)).is_true()


## Drive again: first on Local Drive, it opens the last event's Players page straight away, the
## pages before it under it; Back goes to its Settings page (Next focused), Racing, Local Drive.
func test_drive_again() -> void:
	var last := EventFlow.racing("stock_car")
	last.recall()
	last.event.race_laps = 25
	Settings.profile.last_drive = last.to_dict()
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Drive again")
	var again: Button = _stack(runner).top().find_child("DriveAgain", true, false)
	assert_str(again.accessibility_description).is_equal("Stock Car race · Piedmont Speedway · Stock Car")
	await _key(KEY_ENTER)
	await _frames(4)
	var stack := _stack(runner)
	assert_int(stack.depth()).is_equal(4)
	assert_bool(stack.top() is PlayersMenu).is_true()
	assert_str((stack.top() as PlayersMenu).platform_id).is_equal(EventFlow.STOCK_CAR)
	for page: Control in stack.pages().slice(0, 3):
		assert_bool(page.visible).is_false()
	await _key(KEY_ENTER) # joins
	await _frames(6)
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_ENTER) # Ready
	await _frames(4)
	assert_int(_requested.size()).is_equal(1)
	assert_int((_requested[0][0] as RaceEvent).race_laps).is_equal(25)
	assert_str(String(_requested[0][1])).is_equal(EventFlow.STOCK_CAR)
	# Back out, a page at a time.
	Players.clear()
	await _frames(2)
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(stack.top() is EventSettingsPage).is_true()
	assert_str((stack.top() as EventSettingsPage).title).is_equal("Stock Car race")
	assert_str(_focused(runner)).is_equal("Next")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(stack.top() is RacingPage).is_true()
	assert_str(_focused(runner)).is_equal("Stock Car")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(stack.top() is LocalDrivePage).is_true()
	assert_str(_focused(runner)).is_equal("Racing")


## Drive again isn't offered when its track has gone.
func test_no_drive_again_without_its_track() -> void:
	var last := EventFlow.racing("regular")
	last.recall()
	last.track = "user://tests/local_drive/tracks/gone.nosstrack"
	Settings.profile.last_drive = last.to_dict()
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Racing")
	assert_object(_stack(runner).top().find_child("DriveAgain", true, false)).is_null()


## The results of an event from these pages offer "Event menu" and "Main menu"; Event menu opens
## the main menu on that event's Settings page, Next focused, the pages before it under it.
func test_event_menu_after_the_results() -> void:
	var r1: Racer = auto_free(Racer.new())
	r1.display_name = "Vega"
	var results: ResultsMenu = auto_free(ResultsMenu.new())
	results.results = [{ "racer": r1, "position": 1, "name": "Vega", "number": 5, "car": "nOSS Box", "time": 75.5,
		"best": 72.1, "laps": 1, "penalty": 0.0, "dnf": false, "gap": "" }]
	results.event_menu = true
	var asked := [false]
	results.to_event_menu.connect(func() -> void: asked[0] = true)
	add_child(results)
	await _frames(2)
	var names := results.find_children("*", "Button", true, false).map(func(b: Button) -> String: return String(b.accessibility_name))
	assert_array(names).contains(["Restart", "Event menu", "Main menu"])
	(results.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Event menu")[0] as Button).pressed.emit()
	assert_bool(asked[0]).is_true()
	results.queue_free()
	# Started from the pages: Game keeps the flow; Event menu goes to the main menu with it.
	var flow := EventFlow.racing("stock_car")
	flow.recall()
	flow.event.race_laps = 30
	flow.start()
	assert_str(String(Game.flow_return.variant)).is_equal("stock_car")
	Game.hold_scenes = true
	var went := []
	var on_scene := func(n: String, _scene: Node) -> void: went.append(n)
	Game.scene_requested.connect(on_scene)
	Game.go_event_menu()
	Game.scene_requested.disconnect(on_scene)
	Game.hold_scenes = false
	assert_array(went).contains_exactly(["TitleScreen"])
	assert_bool(Game.reopen_flow).is_true()
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	assert_bool(Game.reopen_flow).is_false()
	var stack := _stack(runner)
	assert_int(stack.depth()).is_equal(3)
	var settings := stack.top() as EventSettingsPage
	assert_object(settings).is_not_null()
	assert_str(settings.title).is_equal("Stock Car race")
	assert_str(_focused(runner)).is_equal("Next")
	var laps: Button = settings.body.get_children().filter(func(b: Button) -> bool: return String(b.accessibility_name).begins_with("Laps"))[0]
	assert_str(String(laps.accessibility_name)).is_equal("Laps: 30 laps")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(stack.top() is RacingPage).is_true()
	assert_str(_focused(runner)).is_equal("Stock Car")
