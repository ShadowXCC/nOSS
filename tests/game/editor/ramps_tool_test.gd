extends GdUnitTestSuite
## Editing a highway in the editor (EDT-10): the Ramps tool comes after Road on highways only,
## its controls and the highway panels are named and work; Add puts a ramp that fits on the
## carriageway under the cursor; clicking a ramp picks it and a point's drag is one undo that
## rebuilds only that ramp; the Race tool puts runs, speed traps and zones.

const DIR := "user://tests/ramps_tool"


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


func _event(kind: String, p: Vector3, screen := Vector2(-100, -100), crosshair := false) -> Dictionary:
	return { "kind": kind, "screen": screen, "hit": { "hit": true, "position": p, "normal": Vector3.UP, "collider": null }, "shift": false,
		"alt": false, "crosshair": crosshair }


func _ramp_node(e: TrackEditor, id: String) -> Node:
	return e.view.preview._road.get_node_or_null(NodePath("Ramp_" + id))


func test_the_ramps_tool_is_for_highways_and_everything_is_named() -> void:
	var e := _editor(TrackTemplates.make("oval"))
	await get_tree().process_frame
	assert_bool(e.tools.has("Ramps")).is_false()
	# The Road tool makes it a highway: the Ramps tool comes, after Road.
	e.show_tool("Road")
	e.tool.call("_select", -1)
	e.draft.set_type("highway")
	await get_tree().process_frame
	assert_bool(e.tools.has("Ramps")).is_true()
	var order := e._tool_bar.get_children().map(func(b: Button) -> String: return b.text)
	assert_int(order.find("Ramps")).is_equal(order.find("Road") + 1)
	e.queue_free()
	await get_tree().process_frame
	var h := _editor(TrackTemplates.make("highway"))
	await get_tree().process_frame
	for title: String in ["Road", "Ramps", "Race"]:
		h.show_tool(title)
		if title == "Ramps":
			h.tool.call("_select", "interchange_1_off")
			h.tool.call("_select_point", 0)
		elif title == "Race":
			h.tool.set("_run", 0)
			h.draft.set_runs([{ "id": "r", "name": "Sprint", "dir": 1, "from_m": 100.0, "to_m": 1500.0 }])
			h.draft.set_zones([{ "dir": 0, "from_m": 2000.0, "to_m": 2300.0, "speed_kmh": 80.0, "tunnel": true }])
			h.tool.set("_zone", 0)
			h.refresh_panel()
		await get_tree().process_frame
		for c: Control in h._content.find_children("*", "Control", true, false) + h._content.get_children():
			if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() and (c is BaseButton or c is Range or c is LineEdit):
				assert_str(String(c.accessibility_name)).override_failure_message("%s: unnamed %s" % [title, c]).is_not_empty()
	h.queue_free()
	await get_tree().process_frame


## Every slider and spinner on the highway panels can be changed (script errors fail here).
func test_every_highway_value_control_works() -> void:
	var d := TrackTemplates.make("highway")
	d.set_runs([{ "id": "r", "name": "Sprint", "dir": 1, "from_m": 100.0, "to_m": 1500.0 }])
	d.set_zones([{ "dir": 0, "from_m": 2000.0, "to_m": 2300.0, "speed_kmh": 80.0, "tunnel": false }])
	var e := _editor(d)
	await get_tree().process_frame
	for title: String in ["Road", "Ramps", "Race"]:
		e.show_tool(title)
		match title:
			"Road":
				e.tool.call("_select", 3)
			"Ramps":
				e.tool.call("_select", "interchange_1_off")
				e.tool.call("_select_point", 0)
			"Race":
				e.tool.set("_run", 0)
				e.tool.set("_zone", 0)
				e.refresh_panel()
		await get_tree().process_frame
		for c: Control in e._content.find_children("*", "Control", true, false):
			if not is_instance_valid(c) or not c.is_inside_tree():
				continue
			if c is Range:
				var r := c as Range
				r.value = r.min_value + (r.max_value - r.min_value) * 0.6
			elif c is Button and c.has_node(^"Row"):
				(c as Button).pressed.emit()
		await get_tree().process_frame
	assert_bool(d.history.can_undo()).is_true()
	e.queue_free()
	await get_tree().process_frame


func test_add_puts_a_ramp_on_the_carriageway_under_the_cursor() -> void:
	var d := TrackTemplates.make("highway")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Ramps")
	var tool: EditorTool = e.tool
	tool.set("template", "exit")
	# The east straight, on the carriageway left of the road's line: direction -1.
	var t := d.track()
	var at := t.transform_at(float(t.project(Vector3(800, 0, -150)).distance), 8.0).origin
	tool.call("_add_at", at)
	var r: Variant = d.ramp("exit_1")
	assert_object(r).is_not_null()
	assert_int(int(r.from.dir)).is_equal(-1)
	assert_str(String(tool.get("selected"))).is_equal("exit_1")
	assert_object(d.track().highway.ramp("exit_1")).is_not_null()
	await get_tree().process_frame
	assert_object(_ramp_node(e, "exit_1")).is_not_null()
	var errors := TrackValidator.errors(TrackValidator.check(d))
	assert_array(errors).override_failure_message(str(errors)).is_empty()
	e.queue_free()
	await get_tree().process_frame


func test_a_ramp_is_picked_and_its_drag_is_one_undo_that_rebuilds_only_it() -> void:
	var d := TrackTemplates.make("highway")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Ramps")
	var tool: EditorTool = e.tool
	var id := "interchange_1_off"
	var rt := d.track().highway.ramp(id).track
	tool.pointer(_event("press", rt.samples[rt.samples.size() / 2]))
	tool.pointer(_event("release", rt.samples[rt.samples.size() / 2]))
	assert_str(String(tool.get("selected"))).is_equal(id)
	await get_tree().process_frame
	var others := {}
	for r in d.track().highway.ramps:
		if r.id != id:
			others[r.id] = _ramp_node(e, r.id)
	var seg := e.view.preview._road.get_node(^"Seg_0")
	var before := _ramp_node(e, id)
	# Crosshair: grab point 1, carry it, drop it.
	var pts: PackedVector3Array = tool.call("_points")
	var version := d.history.version()
	tool.pointer(_event("press", pts[0], Vector2(-100, -100), true))
	for k in 4:
		tool.pointer(_event("drag", pts[0] + Vector3(0, 0, -3.0 * (k + 1)), Vector2(-100, -100), true))
		await get_tree().process_frame
	assert_object(_ramp_node(e, id)).is_not_same(before)
	for other: String in others:
		assert_object(_ramp_node(e, other)).override_failure_message(other).is_same(others[other])
	assert_object(e.view.preview._road.get_node(^"Seg_0")).is_same(seg)
	tool.pointer(_event("release", pts[0] + Vector3(0, 0, -12.0), Vector2(-100, -100), true))
	assert_int(d.history.version()).is_equal(version + 1)
	assert_float(float(d.ramp(id).points[0].p[2])).is_equal_approx(pts[0].z - 12.0, 0.05)
	e.undo()
	assert_float(float(d.ramp(id).points[0].p[2])).is_equal_approx(pts[0].z, 0.05)
	e.queue_free()
	await get_tree().process_frame


func test_the_race_tool_puts_runs_traps_and_zones() -> void:
	var d := TrackTemplates.make("highway")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Race")
	var tool: EditorTool = e.tool
	var t := d.track()
	# The north straight, direction 1's side (right of the line: heading west there, that's north).
	var a := float(t.project(Vector3(300, 0, 400)).distance)
	var on_1 := func(at: float) -> Vector3: return t.transform_at(at, -8.0).origin
	tool.set("click", "run_start")
	tool.pointer(_event("press", on_1.call(a)))
	assert_str(String(tool.get("click"))).is_equal("run_end")
	tool.pointer(_event("press", on_1.call(a + 600.0)))
	var run: Dictionary = d.highway().runs[0]
	assert_int(int(run.dir)).is_equal(1)
	assert_float(float(run.from_m)).is_equal_approx(a, 1.0)
	assert_float(float(run.to_m)).is_equal_approx(a + 600.0, 1.0)
	tool.set("click", "trap")
	tool.pointer(_event("press", t.transform_at(a, 8.0).origin))
	assert_int(int(d.highway().traps[0].dir)).is_equal(-1)
	tool.set("click", "zone_start")
	tool.pointer(_event("press", on_1.call(a)))
	tool.pointer(_event("press", on_1.call(a + 200.0)))
	var z: Dictionary = d.highway().zones[0]
	assert_float(float(z.to_m) - float(z.from_m)).is_equal_approx(200.0, 1.0)
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	e.queue_free()
	await get_tree().process_frame
