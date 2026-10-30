extends GdUnitTestSuite
## The editor's Water tool (D240): it comes after Paint and its controls are named; clicks draw a
## lake's outline and closing it is one undo, just under the ground round it; an outline that
## crosses itself and a 17th lake are refused; Delete takes off the last corner drawn; a corner's
## drag is one undo that rebuilds only the water (one that crosses the outline is put back);
## corners are inserted and deleted (three kept, none that would cross); level, name, Pick height;
## Delete lake puts the hash back; Dig bed lowers the ground under it, one undo.

const DIR := "user://tests/water_tool"
## In the oval template's infield (its road crosses x = 0 at z = ±110), on flat ground.
const SQUARE := [Vector3(-40, 0, -20), Vector3(40, 0, -20), Vector3(40, 0, 20), Vector3(-40, 0, 20)]


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Game.track_draft = null
	Settings.use_folder("user://")


func _editor(d: TrackDraft) -> TrackEditor:
	Game.track_draft = d
	var e := TrackEditor.new()
	add_child(e)
	return e


func _event(kind: String, p: Vector3, crosshair := false) -> Dictionary:
	return { "kind": kind, "screen": Vector2(-100, -100), "hit": { "hit": true, "position": p, "normal": Vector3.UP, "collider": null },
		"shift": false, "alt": false, "crosshair": crosshair }


func _click(tool: EditorTool, p: Vector3, crosshair := false) -> void:
	tool.pointer(_event("press", p, crosshair))
	tool.pointer(_event("release", p, crosshair))


func _press(e: TrackEditor, text: String) -> void:
	for b in e._content.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			(b as Button).pressed.emit()
			return
	fail("No button " + text)


func _water_tool(e: TrackEditor) -> EditorTool:
	e.show_tool("Water")
	return e.tool


## The square drawn by clicks and closed on its first corner.
func _draw_square(tool: EditorTool) -> void:
	for p: Vector3 in SQUARE:
		_click(tool, p)
	_click(tool, SQUARE[0])


func test_the_water_tool_comes_after_paint_and_everything_is_named() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var order := e._tool_bar.get_children().map(func(b: Button) -> String: return b.text)
	assert_int(order.find("Water")).is_equal(order.find("Paint") + 1)
	var tool := _water_tool(e)
	# Its panel with no lakes, while drawing, and with a lake and a corner picked.
	for state in 3:
		if state == 1:
			_click(tool, SQUARE[0])
		elif state == 2:
			for k in range(1, 4):
				_click(tool, SQUARE[k])
			tool.call("_finish")
			tool.call("_select_point", 1)
		e.refresh_panel()
		await get_tree().process_frame
		for c: Control in e._content.find_children("*", "Control", true, false):
			if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() and (c is BaseButton or c is Range or c is LineEdit):
				assert_str(String(c.accessibility_name)).override_failure_message("state %d: unnamed %s" % [state, c]).is_not_empty()
	e.queue_free()
	await get_tree().process_frame


func test_clicks_draw_a_lake_just_under_the_ground_in_one_undo() -> void:
	var d := TrackTemplates.make("oval")
	var hash := d.track().layout_hash
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	var version := d.history.version()
	for p: Vector3 in SQUARE:
		_click(tool, p)
	assert_int((tool.get("drawing") as PackedVector2Array).size()).is_equal(4)
	assert_str(e._status.text).is_equal("Corner 4")
	assert_array(d.lakes()).is_empty() # nothing in the draft until it's closed
	assert_int(d.history.version()).is_equal(version)
	_click(tool, SQUARE[0]) # the first corner again closes it
	assert_int(d.lakes().size()).is_equal(1)
	assert_int(d.history.version()).is_equal(version + 1)
	assert_int(int(tool.get("selected"))).is_equal(0)
	assert_bool((tool.get("drawing") as PackedVector2Array).is_empty()).is_true()
	var lake: Dictionary = d.lake(0)
	assert_str(String(lake.name)).is_equal("Lake 1")
	assert_array(lake.points).is_equal([[-40.0, -20.0], [40.0, -20.0], [40.0, 20.0], [-40.0, 20.0]])
	var low := d.terrain.shore_low(TrackDraft.lake_outline(lake))
	assert_float(float(lake.y)).is_equal_approx(low.y - 0.2, 0.011)
	assert_str(e._status.text).is_equal("Lake 1 added · %.1f m" % float(lake.y))
	assert_int(d.track().water.size()).is_equal(1)
	await get_tree().process_frame
	assert_object(e.view.preview._water.get_node_or_null(^"Lake0")).is_not_null()
	# One undo takes it away, and the track hashes as before.
	assert_str(d.undo()).is_equal("Add lake")
	assert_bool(d.layout.has("water")).is_false()
	assert_str(d.track().layout_hash).is_equal(hash)
	await get_tree().process_frame
	assert_object(e.view.preview._water.get_node_or_null(^"Lake0")).is_null()
	# With the crosshair (keys or a controller): the same, closed by confirming on the first corner.
	for p: Vector3 in SQUARE:
		tool.pointer(_event("press", p, true))
	tool.pointer(_event("press", SQUARE[0] + Vector3(1.5, 0, 0), true))
	assert_int(d.lakes().size()).is_equal(1)
	assert_int((d.lake(0).points as Array).size()).is_equal(4)
	e.queue_free()
	await get_tree().process_frame


func test_a_crossing_outline_and_a_17th_lake_are_refused() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	for p: Vector3 in [Vector3(-40, 0, -20), Vector3(40, 0, 20), Vector3(40, 0, -20), Vector3(-40, 0, 20)]:
		_click(tool, p)
	_press(e, "Finish lake")
	assert_array(d.lakes()).is_empty()
	assert_str(e._status.text).is_equal("Outline crosses itself")
	_press(e, "Cancel")
	assert_bool((tool.get("drawing") as PackedVector2Array).is_empty()).is_true()
	for k in TrackDraft.MAX_LAKES:
		var x := -80.0 + 10.0 * k
		d.add_lake({ "name": "", "y": -1.0, "points": [[x, 60], [x + 5, 60], [x, 65]] })
	assert_int(d.add_lake({ "name": "", "y": -1.0, "points": [[0, 0], [5, 0], [0, 5]] })).is_equal(-1)
	_click(tool, Vector3(0, 0, -50))
	assert_bool((tool.get("drawing") as PackedVector2Array).is_empty()).is_true()
	assert_str(e._status.text).is_equal("16 lakes at most")
	e.queue_free()
	await get_tree().process_frame


func test_delete_takes_off_the_last_corner_drawn() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	for k in 3:
		_click(tool, SQUARE[k])
	assert_bool(tool.action("delete")).is_true()
	assert_int((tool.get("drawing") as PackedVector2Array).size()).is_equal(2)
	assert_str(e._status.text).is_equal("Corner 3 taken off")
	tool.action("delete")
	tool.action("delete")
	assert_str(e._status.text).is_equal("Outline cancelled")
	# A double click doesn't add a corner on top of the last.
	_click(tool, SQUARE[0])
	_click(tool, SQUARE[0] + Vector3(0.3, 0, 0))
	assert_int((tool.get("drawing") as PackedVector2Array).size()).is_equal(1)
	e.queue_free()
	await get_tree().process_frame


func test_a_corner_drag_is_one_undo_that_rebuilds_only_the_water() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	_draw_square(tool)
	await get_tree().process_frame
	var seg := e.view.preview._road.get_node(^"Seg_0")
	var lake_node := e.view.preview._water.get_node(^"Lake0")
	var version := d.history.version()
	# Crosshair: grab corner 3, carry it out, drop it.
	tool.pointer(_event("press", SQUARE[2], true))
	assert_str(e._status.text).is_equal("Corner 3 picked up")
	for k in 4:
		tool.pointer(_event("drag", SQUARE[2] + Vector3(2.0 * (k + 1), 0, 0), true))
		await get_tree().process_frame
	tool.pointer(_event("release", SQUARE[2] + Vector3(8, 0, 0), true))
	assert_int(d.history.version()).is_equal(version + 1)
	assert_array(d.lake(0).points[2]).is_equal([48.0, 20.0])
	await get_tree().process_frame
	assert_object(e.view.preview._water.get_node(^"Lake0")).is_not_same(lake_node)
	assert_object(e.view.preview._road.get_node(^"Seg_0")).is_same(seg)
	# A drag that crosses the outline is put back, unrecorded.
	tool.pointer(_event("press", Vector3(48, 0, 20), true))
	tool.pointer(_event("drag", Vector3(48, 0, -40), true))
	tool.pointer(_event("release", Vector3(48, 0, -40), true))
	assert_str(e._status.text).is_equal("Outline crosses itself")
	assert_array(d.lake(0).points[2]).is_equal([48.0, 20.0])
	assert_int(d.history.version()).is_equal(version + 1)
	assert_str(d.undo()).is_equal("Move corner")
	assert_array(d.lake(0).points[2]).is_equal([40.0, 20.0])
	e.queue_free()
	await get_tree().process_frame


func test_corners_are_inserted_and_deleted() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	d.add_lake({ "name": "Tri", "y": -0.5, "points": [[-40, -20], [40, -20], [0, 30]] })
	tool.call("_select", 0)
	tool.call("_select_point", 0)
	_press(e, "Insert corner after")
	assert_array(d.lake(0).points).is_equal([[-40.0, -20.0], [0.0, -20.0], [40.0, -20.0], [0.0, 30.0]])
	assert_int(int(tool.get("point"))).is_equal(1)
	tool.action("delete")
	assert_int((d.lake(0).points as Array).size()).is_equal(3)
	assert_str(e._status.text).is_equal("Corner 2 deleted")
	tool.action("delete")
	assert_str(e._status.text).is_equal("A lake keeps three corners")
	# A spike down into a square: without the square's corner (100, 0) the outline would cross it.
	d.add_lake({ "name": "Spike", "y": -0.5, "points": [[-50, -50], [50, -50], [50, 50], [0, 50], [0, -45], [-5, 50], [-50, 50]] })
	tool.call("_select", 1)
	tool.call("_select_point", 1)
	var version := d.history.version()
	tool.action("delete")
	assert_str(e._status.text).is_equal("That would cross the outline")
	assert_int(d.history.version()).is_equal(version)
	e.queue_free()
	await get_tree().process_frame


func test_level_name_and_pick_height() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	_draw_square(tool)
	await get_tree().process_frame
	for c in e._content.find_children("*", "HSlider", true, false):
		if String((c as HSlider).accessibility_name) == "Level":
			(c as HSlider).value = 3.3
			break
	assert_float(float(d.lake(0).y)).is_equal_approx(3.3, 0.001)
	assert_str(d.undo()).is_equal("Lake level")
	d.redo()
	tool.call("_set_name", "  Mill pond ")
	assert_str(String(d.lake(0).name)).is_equal("Mill pond")
	assert_str(String(tool.call("_line", 0))).is_equal("Mill pond · 3.3 m")
	var hit := e.view.pick(e.view.cursor())
	if hit.hit:
		_press(e, "Pick height")
		assert_float(float(d.lake(0).y)).is_equal_approx(d.terrain.height_at(hit.position.x, hit.position.z), 0.006)
	# [ ] step through the lakes, and the tool remembers the one picked (a test drive and back).
	d.add_lake({ "name": "", "y": -0.5, "points": [[-40, 40], [40, 40], [0, 70]] })
	tool.action("next")
	assert_int(int(tool.get("selected"))).is_equal(1)
	assert_str(e._status.text).is_equal("Lake 2 · -0.5 m")
	assert_dict(tool.call("selection_state")).is_equal({ "lake": 1 })
	e.queue_free()
	await get_tree().process_frame


func test_delete_lake_puts_the_hash_back() -> void:
	var d := TrackTemplates.make("oval")
	var hash := d.track().layout_hash
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	_draw_square(tool)
	assert_str(d.track().layout_hash).is_not_equal(hash)
	_press(e, "Delete lake")
	assert_bool(d.layout.has("water")).is_false()
	assert_str(d.track().layout_hash).is_equal(hash)
	assert_str(e._status.text).is_equal("Lake 1 deleted")
	assert_int(int(tool.get("selected"))).is_equal(-1)
	assert_str(d.undo()).is_equal("Delete lake")
	assert_int(d.lakes().size()).is_equal(1)
	e.queue_free()
	await get_tree().process_frame


func test_dig_bed_lowers_the_ground_under_it_in_one_undo() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	var tool := _water_tool(e)
	_draw_square(tool)
	var y := float(d.lake(0).y)
	var flat := d.terrain.base_at(-45.0, 0.0)
	var warnings := func() -> Array:
		return TrackValidator.check(d).filter(func(p: Dictionary) -> bool: return "Lake" in String(p.text)).map(func(p: Dictionary) -> String: return p.text)
	# Under the ground round it, the water doesn't show yet.
	assert_array(warnings.call()).is_equal(["Lake under the ground"])
	var version := d.history.version()
	_press(e, "Dig bed")
	assert_str(e._status.text).is_equal("Bed dug")
	assert_int(d.history.version()).is_equal(version + 1)
	assert_float(d.terrain.base_at(0.0, 0.0)).is_equal_approx(y - 2.5, 0.011) # the bed
	var shore := d.terrain.base_at(-38.0, 0.0) # 2 m in: on its way down
	assert_float(shore).is_less(y)
	assert_float(shore).is_greater(y - 2.5)
	assert_float(d.terrain.base_at(-40.0, 0.0)).is_equal_approx(y, 0.011) # level with the water at the outline
	assert_float(d.terrain.base_at(-45.0, 0.0)).is_equal(flat) # outside: as it was
	assert_array(warnings.call()).is_empty()
	_press(e, "Dig bed")
	assert_str(e._status.text).is_equal("Already dug")
	assert_int(d.history.version()).is_equal(version + 1)
	assert_str(d.undo()).is_equal("Dig lake bed")
	assert_float(d.terrain.base_at(0.0, 0.0)).is_equal(flat)
	e.queue_free()
	await get_tree().process_frame
