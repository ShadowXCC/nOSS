extends GdUnitTestSuite
## Boot to race with only the keyboard, and with only a controller (M4 acceptance; the screen
## reader part is tools/a11y_check.py): title -> Race -> class -> event -> Players -> Ready,
## by menu directions and confirm alone. Results by keys and buttons are checked too.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"
const PAD_ID := 7

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/menu_flow")
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Players.clear()
	Devices.test_devices = []
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	_requested.clear()


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


## Goes from the title to a started race with `down`, `up` and `confirm` (keys or buttons).
func _walk(runner: GdUnitSceneRunner, down: Callable, up: Callable, confirm: Callable) -> void:
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Free Drive")
	await down.call()
	assert_str(_focused(runner)).is_equal("Race")
	await confirm.call()
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Track GT")
	await confirm.call()
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Track")
	await up.call() # wraps to Back
	await up.call()
	assert_str(_focused(runner)).is_equal("Next")
	await confirm.call()
	await _frames(4)
	var players: PlayersMenu = runner.find_child("*", true, false) if false else _find(runner.scene(), "PlayersMenu")
	assert_object(players).is_not_null()
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
	assert_str((_requested[0][0] as RaceEvent).kind).is_equal("race")
	assert_str(String(_requested[0][1])).is_equal("official.track.gt")


func _find(root: Node, cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls:
			return n
	return null


func test_keyboard_only_boot_to_race() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _walk(runner, _key.bind(KEY_DOWN), _key.bind(KEY_UP), _key.bind(KEY_ENTER))


func test_controller_only_boot_to_race() -> void:
	Devices.test_devices = [{ "kind": "gamepad", "key": "pad:test#%d" % PAD_ID, "name": "Test pad", "id": PAD_ID, "guid": "test%d" % PAD_ID, "preset": "pad_standard" }]
	var runner := scene_runner(TITLE_SCENE)
	await _walk(runner, _button.bind(JOY_BUTTON_DPAD_DOWN), _button.bind(JOY_BUTTON_DPAD_UP), _button.bind(JOY_BUTTON_A))


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
		await tap.call(input[1]) # Restart -> Title
		await tap.call(input[2])
		assert_bool(quit[0]).is_true()
		menu.queue_free()
		await _frames(1)


## Highway (M7) by keys alone: title -> Highway -> the Lumen Ring -> the highway menu (score
## attack, both ways) -> a highway class -> Players -> Ready.
func test_keyboard_only_boot_to_a_highway() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
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
	await _key(KEY_DOWN) # Way round
	assert_str(_focused(runner)).starts_with("Way round: ")
	while not _focused(runner).ends_with("Both ways"):
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
	assert_str(String(_requested[0][1])).starts_with("official.highway.")
