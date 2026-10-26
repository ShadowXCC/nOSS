extends GdUnitTestSuite
## Kart from the main menu by keys alone (M8, D144, D145): main menu -> Local Drive -> Racing -> Kart -> a race on a kart track
## (laps, AI, items) -> a kart class -> Players -> Ready; and a battle (an arena, most hits); and a
## cup goes to its first race. Every control on the Kart menu and the cup builder is named.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/kart_menu")
	PlayersMenu.countdown_s = 0.0 # everyone Ready starts at once
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Game.cup = null
	Players.clear()
	PlayersMenu.countdown_s = 3.0
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	_requested.clear()
	Settings.profile.last_drive = {} # no Drive again: Racing comes first
	# The last setup is remembered per profile (and profiles load again as players join).
	Settings.profile.erase("last_kart")
	for id in Settings.profile_ids():
		var p := Settings.get_profile(id)
		p.data.erase("last_kart")
		p.data.erase("kart_class")
		p.save() # (it loads again from its file when a player joins)


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


func _focused(runner: GdUnitSceneRunner) -> String:
	var c := runner.scene().get_viewport().gui_get_focus_owner()
	return String(c.accessibility_name) if c else "<none>"


func _named(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c).is_not_empty()


## Right on the focused spinner until it reads `want` (an injected key can go missing while the
## menu settles under load; at most three tries).
func _right_until(runner: GdUnitSceneRunner, want: String) -> void:
	for i in 3:
		await _key(KEY_RIGHT)
		await _frames(2)
		if _focused(runner) == want:
			return


## From the title into the Kart menu, its first row focused.
func _to_kart_menu(runner: GdUnitSceneRunner) -> KartMenu:
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Racing")
	await _key(KEY_ENTER)
	await _frames(4)
	for i in 2: # Stock Car, Kart
		await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Kart")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_str(_focused(runner)).starts_with("Play: ")
	return runner.scene().find_child("KartMenu", true, false) as KartMenu


## On from Next: the players (no class step: each picks on their card), a player joins, Ready.
func _class_players_ready(runner: GdUnitSceneRunner) -> void:
	while _focused(runner) != "Next":
		await _key(KEY_DOWN)
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


func test_keyboard_only_to_a_kart_race() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var menu := await _to_kart_menu(runner)
	_named(menu)
	assert_str(_focused(runner)).is_equal("Play: Race")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).ends_with("· Kart") # a kart track first
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Laps: 3")
	await _key(KEY_RIGHT)
	await _class_players_ready(runner)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("race")
	assert_int(e.race_laps).is_equal(4)
	assert_int(e.practice_min + e.qualifying_min).is_zero()
	assert_bool(e.items).is_true()
	assert_str(String(_requested[0][1])).is_equal("official.kart.medium")


func test_keyboard_only_to_a_battle() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var menu := await _to_kart_menu(runner)
	await _right_until(runner, "Play: Battle")
	assert_str(_focused(runner)).is_equal("Play: Battle")
	_named(menu)
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).starts_with("Arena: ")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Rule: Last one standing")
	await _key(KEY_RIGHT)
	assert_str(_focused(runner)).is_equal("Rule: Most hits")
	await _class_players_ready(runner)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("battle")
	assert_str(e.battle_rule).is_equal("hits")


func test_a_cup_starts_its_first_race() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var menu := await _to_kart_menu(runner)
	await _right_until(runner, "Play: Battle")
	await _right_until(runner, "Play: Cup")
	assert_str(_focused(runner)).is_equal("Play: Cup")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Cup: Spark Cup")
	_named(menu)
	await _class_players_ready(runner)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("race")
	assert_int(e.race_laps).is_equal(2) # the Proving Ground first
	var run: CupRun = Game.cup
	assert_object(run).is_not_null()
	assert_str(String(run.cup.id)).is_equal("spark_cup")
	assert_int(run.index).is_zero()


func test_the_cup_builder_is_named() -> void:
	var b := CupBuilder.new()
	add_child(b)
	await _frames(2)
	_named(b)
	b.queue_free()
