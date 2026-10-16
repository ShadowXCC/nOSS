extends GdUnitTestSuite
## Kart pieces and arenas in the editor (EDT-04, D136-D138): each command undoes and redoes, a
## turned-round track keeps its pieces where they were, a piece changes the layout; the Stunts
## tool comes after Ramps on road circuits and arenas, everything on it is named, Add puts a piece
## at the cursor and a drag is one undo that rebuilds only that piece; both templates check
## clean; and the checks catch each kind of mistake.

const DIR := "user://tests/stunts_tool"


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


func _event(kind: String, p: Vector3) -> Dictionary:
	return { "kind": kind, "screen": Vector2(-100, -100), "hit": { "hit": true, "position": p, "normal": Vector3.UP, "collider": null },
		"shift": false, "alt": false, "crosshair": false }


func _errors(d: TrackDraft) -> Array:
	return TrackValidator.errors(TrackValidator.check(d))


func _texts(d: TrackDraft) -> Array:
	return TrackValidator.check(d).map(func(p: Dictionary) -> String: return p.text)


func test_each_command_undoes_and_redoes() -> void:
	var d := TrackTemplates.make("oval")
	var hash0 := TrackFormat.layout_hash(d.layout)
	var id := d.add_stunt("jump", 300.0)
	assert_str(id).is_equal("jump_1")
	var hash1 := TrackFormat.layout_hash(d.layout)
	assert_str(hash1).is_not_equal(hash0)
	d.set_stunt(id, "height_m", 2.0)
	d.drag_stunt(id, 320.0, 1.0)
	d.end_stunt_move()
	d.set_boxes("none")
	assert_float(float(d.stunt(id).at_m)).is_equal(320.0)
	d.undo()
	assert_str(String(d.kart().get("boxes", "auto"))).is_equal("auto")
	d.undo()
	assert_float(float(d.stunt(id).at_m)).is_equal(300.0)
	d.undo()
	assert_float(float(d.stunt(id).get("height_m", 0.0))).is_not_equal(2.0)
	d.undo()
	assert_object(d.stunt(id)).is_null()
	assert_str(TrackFormat.layout_hash(d.layout)).is_equal(hash0)
	d.redo()
	assert_object(d.stunt(id)).is_not_null()
	d.delete_stunt(id)
	assert_object(d.stunt(id)).is_null()
	d.undo()
	assert_object(d.stunt(id)).is_not_null()
	# Arenas: their type, settings, spawns and boxes.
	var a := TrackTemplates.make("arena")
	assert_bool(a.is_arena()).is_true()
	a.set_arena("wall", "concrete")
	a.add_spawn(Vector3(10, 0, 0), 90.0)
	a.add_box_cluster(Vector3(0, 0, 10))
	assert_int((a.layout.arena.spawns as Array).size()).is_equal(1)
	a.undo()
	a.undo()
	assert_bool(a.layout.arena.has("spawns") and not (a.layout.arena.spawns as Array).is_empty()).is_false()
	a.undo()
	assert_str(String(a.layout.arena.get("wall", "tyres"))).is_equal("tyres")
	var c := TrackTemplates.make("oval")
	c.set_type("arena")
	assert_bool(c.layout.has("arena")).is_true()
	c.undo()
	assert_bool(c.layout.has("arena")).is_false()
	assert_str(String(c.layout.get("type", "circuit"))).is_equal("circuit")


func test_turning_the_track_round_keeps_the_pieces_where_they_were() -> void:
	var d := TrackTemplates.make("oval")
	var t := d.track()
	d.add_stunt("boost_pad", 300.0, { "lateral_m": 2.0 })
	d.add_stunt("wall_ride", 600.0, { "length_m": 80.0, "side": "left" })
	var pad_at := t.transform_at(300.0, 2.0).origin
	var wall_mid := t.transform_at(640.0, t.half_l[t.index_at(640.0)]).origin
	d.flip_direction()
	var u := d.track()
	var pad: Dictionary = d.stunt("boost_pad_1")
	assert_vector(u.transform_at(float(pad.at_m), float(pad.lateral_m)).origin).is_equal_approx(pad_at, Vector3.ONE * 1.0)
	var wall: Dictionary = d.stunt("wall_ride_1")
	assert_str(String(wall.side)).is_equal("right")
	var mid := float(wall.at_m) + 40.0
	assert_vector(u.transform_at(mid, -u.half_r[u.index_at(mid)]).origin).is_equal_approx(wall_mid, Vector3.ONE * 2.5)


func test_both_templates_check_clean() -> void:
	for id in ["kart", "arena"]:
		var d := TrackTemplates.make(id)
		var errors := _errors(d)
		assert_array(errors).override_failure_message("%s: %s" % [id, errors]).is_empty()
	var k := TrackTemplates.make("kart")
	assert_int(k.track().kart.pieces.filter(func(p: Dictionary) -> bool: return not p.get("auto", false)).size()).is_equal(6)


func test_the_checks_catch_each_mistake() -> void:
	var d := TrackTemplates.make("kart")
	var t := d.track()
	var loop: Dictionary = d.stunt("loop_1")
	# A loop round a corner, on a road too narrow, a piece off the road and two on one spot.
	d.set_stunt("loop_1", "at_m", float(t.project(Vector3(203.9, 0, -83.9)).distance)) # round the first corner
	d.set_stunt("boost_pad_1", "lateral_m", 7.0)
	d.add_stunt("jump", float(d.stunt("jump_1").at_m) + 2.0)
	d.add_stunt("wall_ride", 20.0, { "length_m": 20.0 })
	d.add_stunt("item_row", float(t.project(Vector3(-203.9, 0, 83.9)).distance))
	var texts := _texts(d)
	for want in ["Loop needs a straight", "Piece off the road", "Pieces overlap", "Wall-ride too short", "Item row on a tight corner"]:
		assert_bool(texts.any(func(x: String) -> bool: return x.begins_with(want))).override_failure_message("%s not in %s" % [want, texts]).is_true()
	var narrow := TrackTemplates.make("kart")
	narrow.set_default("width_l", 3.5)
	narrow.set_default("width_r", 3.5)
	texts = _texts(narrow)
	assert_bool(texts.any(func(x: String) -> bool: return x.begins_with("Loop needs a road twice its width"))).override_failure_message(str(texts)).is_true()
	assert_bool(texts.any(func(x: String) -> bool: return x.begins_with("Narrow for karts"))).is_true()
	# Arenas: too small, too few spawns, things outside.
	var a := TrackTemplates.make("arena")
	for i in 3:
		a.add_spawn(Vector3(5.0 * i, 0, 0), 0.0)
	a.add_box_cluster(Vector3(200, 0, 0))
	texts = _texts(a)
	assert_bool(texts.any(func(x: String) -> bool: return x.begins_with("Fewer than 8 clear spawns"))).override_failure_message(str(texts)).is_true()
	assert_bool(texts.any(func(x: String) -> bool: return x.begins_with("Item boxes outside"))).is_true()
	var small := TrackDraft.blank("Small")
	small.terrain = null
	small.set_type("arena")
	small.layout.road.points = TrackTemplates.rounded_rect(15.0, 15.0, 5.0, 10.0, 30.0).map(func(p: Vector3) -> Dictionary: return { "p": TrackDraft._vec(p) })
	small._track = null
	assert_bool(_texts(small).any(func(x: String) -> bool: return x.begins_with("Arena too small"))).is_true()


func test_the_stunts_tool_adds_and_drags_a_piece() -> void:
	var d := TrackTemplates.make("kart")
	var e := _editor(d)
	await get_tree().process_frame
	assert_bool(e.tools.has("Stunts")).is_true()
	var order := e._tool_bar.get_children().map(func(b: Button) -> String: return b.text)
	assert_int(order.find("Stunts")).is_equal(order.find("Road") + 1) # no Ramps on a circuit
	e.show_tool("Stunts")
	var tool: EditorTool = e.tool
	for selected: String in ["", "loop_1", "wall_ride_1", "jump_1", "item_row_1", "boost_pad_1"]:
		tool.call("_select", selected)
		await get_tree().process_frame
		for c: Control in e._content.find_children("*", "Control", true, false) + e._content.get_children():
			if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() and (c is BaseButton or c is Range or c is LineEdit):
				assert_str(String(c.accessibility_name)).override_failure_message("%s: unnamed %s" % [selected, c]).is_not_empty()
	tool.call("_select", "")
	# Add at the cursor puts a pad on the road there.
	var t := d.track()
	tool.set("kind", "boost_pad")
	tool.call("_add_at", t.transform_at(t.from_start(0.0) + 200.0, -2.0).origin)
	assert_str(String(tool.get("selected"))).is_equal("boost_pad_2")
	await get_tree().process_frame
	var stunts: Node = e.view.preview._stunts
	assert_object(stunts.get_node_or_null("Stunt_boost_pad_2")).is_not_null()
	# A drag rebuilds that piece alone, and is one undo.
	var loop_node := stunts.get_node("Stunt_loop_1")
	var pad := tool.call("_where", "boost_pad_2") as Vector3
	tool.pointer(_event("press", pad))
	tool.pointer(_event("drag", pad + t.tangents[t.index_at(float(d.stunt("boost_pad_2").at_m))] * 10.0))
	tool.pointer(_event("release", pad))
	await get_tree().process_frame
	assert_bool(is_instance_valid(loop_node) and loop_node.is_inside_tree()).is_true()
	var moved := float(d.stunt("boost_pad_2").at_m)
	d.undo()
	assert_float(float(d.stunt("boost_pad_2").at_m)).is_not_equal(moved)
	e.queue_free()
	await get_tree().process_frame


func test_arenas_drop_the_race_tool_and_list_spawns() -> void:
	var e := _editor(TrackTemplates.make("arena"))
	await get_tree().process_frame
	assert_bool(e.tools.has("Race")).is_false()
	assert_bool(e.tools.has("Stunts")).is_true()
	e.show_tool("Stunts")
	await get_tree().process_frame
	var texts := e._content.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	assert_bool(texts.any(func(x: String) -> bool: return x.begins_with("Add spawn"))).is_true()
	e.queue_free()
	await get_tree().process_frame
