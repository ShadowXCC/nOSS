extends GdUnitTestSuite
## The menus still on their old screens, by keys alone: Highway and Free Drive from the main menu
## to Ready, and back out of Highway a screen at a time; and the results by keys and buttons.
## Racing's walks (boot to race with only the keyboard and with only a controller, the M4
## acceptance) are in local_drive_test.gd.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"
const PAD_ID := 7

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/menu_flow")
	PlayersMenu.countdown_s = 0.0 # everyone Ready starts at once
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Players.clear()
	Devices.test_devices = []
	PlayersMenu.countdown_s = 3.0
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	_requested.clear()
	Settings.profile.last_platform = "official.track.gt" # the class lists focus the last one used
	Settings.profile.last_highway = {} # the highway menu starts from its defaults
	Settings.profile.last_drive = {} # no Drive again: Racing comes first on Local Drive


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


func _find(root: Node, cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls:
			return n
	return null


func test_results_by_keys_and_buttons() -> void:
	for input: Array in [[KEY_DOWN, KEY_RIGHT, KEY_ENTER], [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A]]:
		var r1: Racer = auto_free(Racer.new())
		r1.display_name = "Vega"
		r1.number = 5
		var menu: ResultsMenu = auto_free(ResultsMenu.new())
		menu.kind = "race"
		menu.results = [{ "racer": r1, "position": 1, "name": "Vega", "number": 5, "car": "nOSS Box", "time": 75.5,
			"best": 72.1, "laps": 1, "penalty": 0.0, "dnf": false, "gap": "" }]
		var quit := [false]
		menu.quit_to_title.connect(func() -> void: quit[0] = true)
		add_child(menu)
		await _frames(2)
		assert_str(menu.row_text(0)).starts_with("P1, Vega, nOSS Box, 1:15.500")
		var tap := func(code: int) -> void:
			if code < 100:
				await _button(code as JoyButton)
			else:
				await _key(code as Key)
		if input[0] is int and input[0] < 100:
			Devices.test_devices = []
		await tap.call(input[1]) # Restart -> Main menu
		await tap.call(input[2])
		assert_bool(quit[0]).is_true()
		menu.queue_free()
		await _frames(1)


## Highway (M7) by keys alone: title -> Highway -> the Lumen Ring -> the highway menu (score
## attack, both ways) -> a highway class -> Players -> Ready.
func test_keyboard_only_boot_to_a_highway() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN) # Endless, Highway
	assert_str(_focused(runner)).is_equal("Highway")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Lumen Ring")
	await _key(KEY_ENTER)
	await _frames(4)
	var menu: HighwayMenu = _find(runner.scene(), "HighwayMenu")
	assert_object(menu).is_not_null()
	for c: Control in menu.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c).is_not_empty()
	assert_str(_focused(runner)).starts_with("Mode: ")
	while not _focused(runner).begins_with("Mode: Score attack"):
		await _key(KEY_RIGHT)
	await _key(KEY_DOWN) # Traffic
	await _key(KEY_DOWN) # Police
	assert_str(_focused(runner)).is_equal("Police: Off")
	await _key(KEY_DOWN) # Way round
	assert_str(_focused(runner)).starts_with("Way round: ")
	while not _focused(runner).ends_with("Both ways"):
		await _key(KEY_RIGHT)
	await _key(KEY_DOWN) # the sky (D153)
	assert_str(_focused(runner)).is_equal("Time: Track's")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Time runs: Still")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Weather: Track's")
	while _focused(runner) != "Weather: Rain":
		await _key(KEY_RIGHT)
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Next")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Highway")
	await _key(KEY_ENTER)
	await _frames(4)
	await _key(KEY_ENTER) # joins
	await _frames(6)
	var v := Players.slots[0].menu_target
	await _key(KEY_UP)
	await _key(KEY_UP)
	assert_str(UiKit.text_of(Players.focus_of(v) as Button)).starts_with("Ready")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("highway")
	assert_str(e.sub).is_equal("score")
	assert_int(e.direction).is_equal(0)
	assert_str(e.weather).is_equal("rain")
	assert_str(String(_requested[0][1])).starts_with("official.highway.")


## Highway back out by keys: Players -> the class -> the highway menu -> the tracks -> the title,
## focus landing on each screen in turn.
func test_keyboard_back_out_of_the_highway_menus() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN) # Endless, Highway
	await _key(KEY_ENTER)
	await _frames(4)
	await _key(KEY_ENTER) # the Lumen Ring
	await _frames(4)
	while _focused(runner) != "Next":
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Highway")
	await _key(KEY_ENTER) # the class: Players, nobody joined yet
	await _frames(6)
	assert_object(_find(runner.scene(), "PlayersMenu")).is_not_null()
	await _key(KEY_ESCAPE)
	await _frames(6)
	assert_str(_focused(runner)).starts_with("Highway Street")
	# Again with a player joined, back by the Players screen's Back (the mouse's way).
	await _key(KEY_ENTER)
	await _frames(6)
	await _key(KEY_ENTER) # joins
	await _frames(6)
	var players: PlayersMenu = _find(runner.scene(), "PlayersMenu")
	var back: Button = players.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Back")[0]
	back.pressed.emit()
	await _frames(6)
	assert_str(_focused(runner)).starts_with("Highway Street")
	Players.clear()
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Mode: ")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Lumen Ring")
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Highway") # back on Local Drive's entry
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Local Drive")


## Free Drive by keys alone (Changes.md: it had no setup): title -> Free Drive -> class -> the
## setup (2 AI cars, ghosted) -> Players -> Ready; and back out of the setup to the class.
func test_keyboard_only_boot_to_free_drive_with_ai() -> void:
	Settings.profile.erase("last_free")
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Local Drive")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Racing")
	await _key(KEY_UP) # wraps to Back
	await _key(KEY_UP)
	assert_str(_focused(runner)).is_equal("Free Drive")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Track GT")
	await _key(KEY_ENTER)
	await _frames(4)
	var menu: FreeDriveMenu = _find(runner.scene(), "FreeDriveMenu")
	assert_object(menu).is_not_null()
	for c: Control in menu.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c).is_not_empty()
	assert_str(_focused(runner)).starts_with("Track: ")
	# Back to the class, and in again.
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_object(_find(runner.scene(), "FreeDriveMenu")).is_null()
	assert_str(_focused(runner)).starts_with("Track")
	for i in 12:
		if _focused(runner).begins_with("Track GT"):
			break
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _frames(4)
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("AI cars: Off")
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	assert_str(_focused(runner)).is_equal("AI cars: 2")
	for i in 3:
		await _key(KEY_DOWN)
	assert_str(_focused(runner)).starts_with("Collisions")
	await _key(KEY_RIGHT)
	assert_str(_focused(runner)).is_equal("Collisions: Ghosted")
	await _key(KEY_DOWN) # Track limits
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Time: Track's")
	while _focused(runner) != "Time: Night":
		await _key(KEY_RIGHT)
	await _key(KEY_DOWN) # Time runs
	await _key(KEY_DOWN) # Weather
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Next")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_object(_find(runner.scene(), "PlayersMenu")).is_not_null()
	await _key(KEY_ENTER) # joins
	await _frames(6)
	var v := Players.slots[0].menu_target
	await _key(KEY_UP)
	await _key(KEY_UP)
	assert_str(UiKit.text_of(Players.focus_of(v) as Button)).starts_with("Ready")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("free")
	assert_int(e.ai_count).is_equal(2)
	assert_bool(e.collisions).is_false()
	assert_str(e.time).is_equal("night")
	assert_str(String(_requested[0][1])).is_equal("official.track.gt")
	# Remembered for next time.
	assert_int(FreeDriveMenu.last().ai_count).is_equal(2)
