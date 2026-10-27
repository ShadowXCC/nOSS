extends GdUnitTestSuite
## The Race and Check tools (EDT-05…07): clicks put the start and sector lines on the road;
## dragging the AI line pins it (one undo); the line and the checks run by themselves; problems
## list in Check and stop a save.

const DIR := "user://tests/race_tool"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Game.track_draft = null
	Settings.use_folder("user://")


func _hit(p: Vector3) -> Dictionary:
	return { "hit": true, "position": p, "normal": Vector3.UP, "collider": null }


func _ev(kind: String, p: Vector3) -> Dictionary:
	return { "kind": kind, "screen": Vector2(-50, -50), "hit": _hit(p), "shift": false, "alt": false, "crosshair": false }


func _editor(d: TrackDraft) -> TrackEditor:
	Game.track_draft = d
	var e := TrackEditor.new()
	add_child(e)
	return e


## Waits for the editor's AI line and checks to catch up with the draft.
func _analysed(e: TrackEditor) -> void:
	for k in 600:
		await get_tree().process_frame
		if e.analysis.get("stamp", -1) == e._changes and e._analyse_in < 0.0:
			return


func test_start_and_sector_lines_go_where_clicked() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Race")
	var tool: EditorTool = e.tool
	var t := d.track()
	tool.pointer(_ev("press", t.samples[300]))
	tool.pointer(_ev("release", t.samples[300]))
	assert_float(d.track().start_m).is_equal_approx(t.distances[300], 0.2)
	assert_str(d.undo()).is_equal("Move start")
	# Off the road it says so and changes nothing.
	tool.pointer(_ev("press", Vector3(0, 0, 0)))
	assert_str(e._status.text).is_equal("Not on the road")
	assert_float(d.track().start_m).is_equal_approx(120.0, 0.01)
	# A sector line, then four even sectors.
	tool.set("click", "sector")
	tool.pointer(_ev("press", t.samples[100]))
	assert_int(d.track().sectors_m.size()).is_equal(3)
	tool.call("_even_sectors", 4)
	var s := d.track().sectors_m
	assert_int(s.size()).is_equal(3)
	for k in 3:
		assert_float(s[k]).is_equal_approx(d.track().length * (k + 1) / 4.0, 0.2)
	e.queue_free()
	await get_tree().process_frame


func test_dragging_the_ai_line_pins_it() -> void:
	var d := TrackTemplates.make("circuit")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Race")
	await _analysed(e)
	assert_str((e.tools.Race as EditorTool).call("_lap_text")).starts_with("AI lap ").not_contains("…")
	var tool: EditorTool = e.tool
	tool.set("click", "pin")
	var t := d.track()
	var i := 400
	var version := d.history.version()
	tool.pointer(_ev("press", t.samples[i]))
	for lateral in [1.0, 2.0, 3.5]:
		tool.pointer(_ev("drag", t.samples[i] + t.lefts[i] * lateral))
	# Way past the edge: held at the corridor.
	tool.pointer(_ev("drag", t.samples[i] + t.lefts[i] * 30.0))
	tool.pointer(_ev("release", t.samples[i] + t.lefts[i] * 30.0))
	assert_int(d.history.version()).is_equal(version + 1)
	var pins: Array = d.layout.race.ai.pins
	assert_int(pins.size()).is_equal(1)
	var at := float(pins[0].at_m)
	assert_float(at).is_equal_approx(t.distances[i], 0.1)
	var c := RacingLine.corridor_at(d.track(), at)
	assert_float(float(pins[0].offset_m)).is_equal_approx(c.x, 0.06)
	# The line goes through it once solved again.
	await _analysed(e)
	var line: RacingLine = e.analysis.line
	assert_float(line.offsets[d.track().index_at(at)]).is_equal_approx(float(pins[0].offset_m), 0.001)
	# Undo takes the pin away; the layout (and records) never changed.
	assert_str(d.undo()).is_equal("Pin AI line")
	assert_array(d.layout.race.ai.pins).is_empty()
	assert_str(d.track().layout_hash).is_equal(t.layout_hash)
	e.queue_free()
	await get_tree().process_frame


func test_race_changes_keep_the_road() -> void:
	var d := TrackTemplates.make("oval")
	var before := d.track()
	d.set_race("start_m", 400.0)
	var after := d.track()
	assert_object(after).is_not_same(before)
	assert_float(after.start_m).is_equal(400.0)
	assert_float(before.start_m).is_equal(120.0)
	assert_array(Array(after.samples)).is_equal(Array(before.samples))


func test_problems_show_in_check_and_stop_a_save() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	d.set_race("grid/slots", 1)
	await _analysed(e)
	assert_str((e._tool_buttons.Check as Button).text).is_equal("Check (1)")
	e.show_tool("Check")
	var buttons := e._content.get_children().filter(func(c: Node) -> bool: return c is Button and UiKit.text_of(c).contains("Grid too small"))
	assert_int(buttons.size()).is_equal(1)
	(buttons[0] as Button).pressed.emit()
	assert_str(e._status.text).is_equal("Grid too small")
	assert_float(e.view.camera._target.pivot.distance_to(d.track().point_at(d.track().start_m))).is_less(1.0)
	await e.save()
	assert_str(e._status.text).is_equal("Can't save: Grid too small")
	# Fixed: the count goes.
	d.set_race("grid/slots", 16)
	await _analysed(e)
	assert_str((e._tool_buttons.Check as Button).text).is_equal("Check")
	e.queue_free()
	await get_tree().process_frame


## The track's own sky (D153): the Race tool's Time and Weather rows write the environment block
## (one undo each), and back to the default takes the key out.
func test_the_sky_rows_set_the_tracks_own_time_and_weather() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Race")
	var rows: Array = (e.tool as EditorTool).panel()
	var time: Button
	var weather: Button
	for c in rows:
		if c is Button and String(c.accessibility_name).begins_with("Time: "):
			time = c
		if c is Button and String(c.accessibility_name).begins_with("Weather: "):
			weather = c
	assert_object(time).is_not_null()
	assert_object(weather).is_not_null()
	assert_str(String(time.accessibility_name)).is_equal("Time: Fixed sun")
	d.set_env("time", "dusk")
	d.set_env("weather", "rain")
	assert_str(String(d.layout.environment.time)).is_equal("dusk")
	assert_str(String(d.layout.environment.weather)).is_equal("rain")
	var state := EnvState.from_settings("track", 0, "track", 1, d.layout.environment, {})
	assert_float(state.at(0.0).hour).is_equal(EnvState.HOURS.dusk)
	assert_float(state.at(0.0).wetness).is_equal(1.0)
	assert_str(d.undo()).is_equal("Set weather")
	d.set_env("time", "")
	assert_bool(d.layout.environment.has("time")).is_false()
	for c: Node in rows:
		c.free()
	e.queue_free()


## A setting (D221): the Race tool's Setting row writes the environment's biome, the track still
## validates, and None takes the key out.
func test_the_setting_row_sets_the_tracks_biome() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Race")
	var rows: Array = (e.tool as EditorTool).panel()
	var setting: Button
	for c in rows:
		if c is Button and String(c.accessibility_name).begins_with("Setting: "):
			setting = c
	assert_object(setting).is_not_null()
	assert_str(String(setting.accessibility_name)).is_equal("Setting: None")
	d.set_env("biome", "haunted")
	assert_str(String(d.layout.environment.biome)).is_equal("haunted")
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	assert_str(d.undo()).is_equal("Set biome")
	d.set_env("biome", "haunted")
	d.set_env("biome", "")
	assert_bool(d.layout.environment.has("biome")).is_false()
	for c: Node in rows:
		c.free()
	e.queue_free()
