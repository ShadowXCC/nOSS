extends GdUnitTestSuite
## Kart's pages by keys alone (M8, D144, D145, docs/UI_FLOW.md §6.1): main menu -> Local Drive ->
## Racing -> Kart -> a race on a kart track (laps, AI, items) -> Players (each picks their kart
## class on their card) -> Ready; a cup goes to its first race; the cup builder saves a cup, and
## deleting one asks first; and Kart Battle from Mini Games (an arena, most hits). Every control
## on the pages is named.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"
const DIR := "user://tests/kart_menu"

var _requested: Array = []


func before() -> void:
	Settings.use_folder(DIR)
	PlayersMenu.countdown_s = 0.0 # everyone Ready starts at once
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Game.cup = null
	Game.flow_return = {}
	Players.clear()
	PlayersMenu.countdown_s = 3.0
	for file in DirAccess.get_files_at(CupRun.user_dir):
		DirAccess.remove_absolute(CupRun.user_dir + file)
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	_requested.clear()
	Settings.profile.last_drive = {} # no Drive again: Racing comes first
	# The last setup is remembered per profile (and profiles load again as players join).
	for id in Settings.profile_ids():
		var p := Settings.get_profile(id)
		for key in ["last_kart", "kart_class"]:
			p.data.erase(key)
		p.data.event_memory = {}
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


func _stack(runner: GdUnitSceneRunner) -> MenuStack:
	return runner.scene().find_child("MenuStack", true, false) as MenuStack


func _named(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c).is_not_empty()


func _rows(page: MenuPage) -> Array:
	return page.body.get_children().filter(func(c: Node) -> bool: return c is Control and UiKit._focus_target(c) != null) \
		.map(func(c: Control) -> String: return String(UiKit._focus_target(c).accessibility_name).get_slice(":", 0))


## Right on the focused spinner until it reads `want` (an injected key can go missing while the
## page settles under load; at most three tries).
func _right_until(runner: GdUnitSceneRunner, want: String) -> void:
	for i in 3:
		await _key(KEY_RIGHT)
		await _frames(2)
		if _focused(runner) == want:
			return


## From the main menu to Kart's Settings page, its first row focused.
func _to_kart(runner: GdUnitSceneRunner) -> EventSettingsPage:
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
	return _stack(runner).top() as EventSettingsPage


## On from Next: the players (no class step: each picks on their card), a player joins, Ready.
func _players_ready(runner: GdUnitSceneRunner) -> void:
	(_stack(runner).top() as EventSettingsPage).focus_next()
	await _frames(2)
	await _key(KEY_ENTER)
	await _frames(4)
	assert_bool(_stack(runner).top() is PlayersMenu).is_true()
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
	var page := await _to_kart(runner)
	_named(page)
	assert_str(page.title).is_equal("Kart race")
	assert_str(page.step_text()).is_equal("Step 2 of 3")
	assert_str(page.next_button.accessibility_description).is_equal("The players: each picks a car and a class")
	assert_array(_rows(page)).contains_exactly(["Play", "Track", "Laps", "AI karts", "AI skill", "Items", "Time", "Time runs", "Weather"])
	assert_str(_focused(runner)).is_equal("Play: Race")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).ends_with("· Kart") # a kart track first
	assert_str(page.pane.text()).contains("Kart")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Laps: 3")
	await _key(KEY_RIGHT)
	await _players_ready(runner)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("race")
	assert_int(e.race_laps).is_equal(4)
	assert_int(e.practice_min + e.qualifying_min).is_zero()
	assert_bool(e.items).is_true()
	assert_str(e.ai_cars).is_equal("builtin")
	assert_str(String(_requested[0][1])).is_equal(EventFlow.KART)
	assert_int(int(Settings.profile.event_memory["racing/kart"].event.race_laps)).is_equal(4)


## Play: Cup shows the cup and its races; on to its first race. Back to Race, and Cup again: the
## same cup.
func test_a_cup_starts_its_first_race() -> void:
	var mine := { "schema": CupRun.SCHEMA, "id": "", "name": "Mine", "races": [] }
	for id in ["proving_ground", "gearworks", "marble_mile", "skyhop_ridge"]:
		mine.races.append({ "track": id, "laps": 2 })
	assert_str(CupRun.save(mine)).is_empty()
	var runner := scene_runner(TITLE_SCENE)
	var page := await _to_kart(runner)
	await _right_until(runner, "Play: Cup")
	assert_str(_focused(runner)).is_equal("Play: Cup") # the rows came again, the focus kept
	assert_str(page.title).is_equal("Kart cup")
	assert_array(_rows(page)).contains_exactly(["Play", "Cup", "New cup", "AI karts", "AI skill", "Items", "Time", "Time runs", "Weather"])
	_named(page)
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Cup: Spark Cup")
	await _key(KEY_RIGHT)
	await _frames(2)
	assert_str(_focused(runner)).is_equal("Cup: Mine (yours)")
	assert_array(_rows(page)).contains(["Change this cup", "Delete this cup"]) # the player's own
	await _key(KEY_UP)
	await _right_until(runner, "Play: Race")
	await _right_until(runner, "Play: Cup")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Cup: Mine (yours)")
	await _key(KEY_LEFT) # the Spark Cup again
	await _frames(2)
	await _players_ready(runner)
	CupRun.delete(String(mine.id))
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("race")
	assert_int(e.race_laps).is_equal(2) # the Proving Ground first
	var run: CupRun = Game.cup
	assert_object(run).is_not_null()
	assert_str(String(run.cup.id)).is_equal("spark_cup")
	assert_int(run.index).is_zero()


## New cup: the builder page (named; Save in the action bar) saves it, and it's the cup picked;
## Delete this cup asks first, and Keep keeps it.
func test_the_cup_builder_saves_and_deleting_asks_first() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var page := await _to_kart(runner)
	await _right_until(runner, "Play: Cup")
	(page.row_named("New cup") as Button).pressed.emit()
	await _frames(4)
	var builder := _stack(runner).top() as CupBuilderPage
	assert_object(builder).is_not_null()
	_named(builder)
	assert_str((builder.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive › Racing › Kart › Cup builder")
	assert_array(_rows(builder)).contains_exactly(["Name", "Race 1", "Race 1 laps", "Race 2", "Race 2 laps", "Race 3", "Race 3 laps",
		"Race 4", "Race 4 laps"])
	var save: Button = builder.find_child("Save", true, false)
	assert_bool(builder.scroll().is_ancestor_of(save)).is_false() # always on screen
	builder.cup.name = "Test Cup"
	save.pressed.emit()
	await _frames(4)
	assert_object(_stack(runner).top()).is_same(page)
	assert_str(page.flow.cup).is_equal(CupRun.user_dir + "test_cup.cup.json")
	assert_str(String(page.row_named("Cup").accessibility_name)).is_equal("Cup: Test Cup (yours)")
	assert_str(_focused(runner)).is_equal("Cup: Test Cup (yours)")
	# Delete: a question first, Keep focused.
	(page.row_named("Delete this cup") as Button).pressed.emit()
	await _frames(4)
	var confirm := _stack(runner).top() as ConfirmPage
	assert_object(confirm).is_not_null()
	assert_str(confirm.title).is_equal("Delete Test Cup?")
	assert_str(_focused(runner)).is_equal("Keep")
	await _key(KEY_ENTER)
	await _frames(4)
	assert_bool(FileAccess.file_exists(CupRun.user_dir + "test_cup.cup.json")).is_true()
	(page.row_named("Delete this cup") as Button).pressed.emit()
	await _frames(4)
	(_stack(runner).top().find_child("Yes", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_bool(FileAccess.file_exists(CupRun.user_dir + "test_cup.cup.json")).is_false()
	assert_object(_stack(runner).top()).is_same(page)
	assert_str(_focused(runner)).is_equal("Cup: Spark Cup")


## Kart Battle: Mini Games -> Kart Battle -> an arena, Most hits (its Hits to win row comes) ->
## Players -> Ready.
func test_keyboard_only_to_a_battle() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	for i in 3: # Endless, Highway, Mini Games
		await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Mini Games")
	await _key(KEY_ENTER)
	await _frames(4)
	var mini := _stack(runner).top() as MiniGamesPage
	assert_object(mini).is_not_null()
	_named(mini)
	assert_array(_rows(mini)).contains_exactly(["Sumo Wrestling", "Drag Strip", "Kart Battle"])
	await _key(KEY_UP)
	await _key(KEY_UP) # Back, Kart Battle
	assert_str(_focused(runner)).is_equal("Kart Battle")
	assert_str(mini.step_text()).is_equal("Step 1 of 3")
	await _key(KEY_ENTER)
	await _frames(4)
	var page := _stack(runner).top() as EventSettingsPage
	_named(page)
	assert_str(page.title).is_equal("Kart Battle")
	assert_str((page.find_child("Crumbs", true, false) as Label).text).is_equal("Local Drive › Mini Games › Kart Battle › Settings")
	assert_str(_focused(runner)).starts_with("Arena: ")
	assert_str(page.pane.text()).contains("Arena")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Rule: Last one standing")
	await _key(KEY_RIGHT)
	await _frames(2)
	assert_str(_focused(runner)).is_equal("Rule: Most hits")
	assert_array(_rows(page)).contains_exactly(["Arena", "Rule", "Hits to win", "Minutes", "AI karts", "AI skill", "Time", "Time runs", "Weather"])
	await _players_ready(runner)
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("battle")
	assert_str(e.battle_rule).is_equal("hits")
	assert_str(String(_requested[0][1])).is_equal(EventFlow.KART)
