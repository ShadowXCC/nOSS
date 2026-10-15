extends GdUnitTestSuite
## The track editor screen (EDT-06): it opens on a draft, every tool's controls are named and in
## the focus order, undo goes through the history, and the history outlives the screen (test
## drives).

const DIR := "user://tests/track_editor"


func before() -> void:
	Settings.use_folder(DIR)
	Game.track_draft = null


func after() -> void:
	Game.track_draft = null
	Settings.use_folder("user://")


func _editor(d: TrackDraft) -> TrackEditor:
	Game.track_draft = d
	var e := TrackEditor.new()
	add_child(e)
	return e


func test_every_tool_is_named_and_in_order() -> void:
	var d := TrackDraft.blank("Named", Vector2i(2, 2))
	var e := _editor(d)
	await get_tree().process_frame
	for title: String in e.tools:
		e.show_tool(title)
		await get_tree().process_frame
		for c: Control in e._content.find_children("*", "Control", true, false) + e._content.get_children():
			if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() and (c is BaseButton or c is Range or c is LineEdit):
				assert_str(String(c.accessibility_name)).override_failure_message("%s: unnamed %s" % [title, c]).is_not_empty()
	assert_str(String(e.view.accessibility_name)).is_equal("Track view")
	e.queue_free()
	await get_tree().process_frame


func test_undo_goes_through_the_history_and_outlives_the_screen() -> void:
	var d := TrackDraft.blank("Kept", Vector2i(2, 2))
	var e := _editor(d)
	await get_tree().process_frame
	d.add_point(0, Vector3(0, 0, 0))
	d.add_point(1, Vector3(100, 0, 0))
	e.undo()
	assert_int(d.points().size()).is_equal(1)
	assert_str(e._status.text).is_equal("Undone: Add point")
	e.redo()
	assert_int(d.points().size()).is_equal(2)
	e.remember_view()
	var version := d.history.version()
	e.queue_free()
	await get_tree().process_frame
	# As if back from a test drive: the same draft, its history and camera.
	var again := _editor(d)
	await get_tree().process_frame
	assert_int(d.history.version()).is_equal(version)
	assert_str(d.undo()).is_equal("Add point")
	again.queue_free()
	await get_tree().process_frame


## Every slider and spinner on every tool's panel can be changed (a point and a prop selected):
## a callback that takes its arguments the wrong way round fails here as a script error.
func test_every_value_control_works() -> void:
	var d := TrackTemplates.make("oval")
	d.add_prop({ "prop": "tent", "p": [0.0, 0.0, 0.0], "yaw_deg": 0.0, "scale": 1.0, "ground": true })
	var e := _editor(d)
	await get_tree().process_frame
	for title: String in e.tools:
		e.show_tool(title)
		if title == "Road":
			e.tool.call("_select", 0)
		elif title == "Props":
			e.tool.call("_select", 0)
		await get_tree().process_frame
		var controls: Array = e._content.find_children("*", "Control", true, false)
		for c: Control in controls:
			if not is_instance_valid(c) or not c.is_inside_tree():
				continue # the panel came again after an earlier change
			if c is Range:
				var r := c as Range
				r.value = r.min_value + (r.max_value - r.min_value) * 0.6
			elif c is Button and c.has_node(^"Row"):
				(c as Button).pressed.emit()
		await get_tree().process_frame
	# A road width set from its field reaches the point.
	e.show_tool("Road")
	e.tool.call("_select", 0)
	await get_tree().process_frame
	for c in e._content.find_children("*", "HSlider", true, false):
		if String((c as HSlider).accessibility_name) == "Width left":
			(c as HSlider).value = 8.0
			break
	assert_float(float(TrackFormat.attr(d.layout.road, 0, "width_l"))).is_equal(8.0)
	e.queue_free()
	await get_tree().process_frame


## The File tool's Name and Author take whole words (Changes.md: they lost the focus after one
## letter, as each letter rebuilt the panel), and each edit is one undo step.
func test_name_and_author_take_typing() -> void:
	var d := TrackDraft.blank("Typed", Vector2i(2, 2))
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("File")
	await get_tree().process_frame
	var steps := d.history.version()
	for field_name: String in ["Name", "Author"]:
		var field := _field(e, field_name)
		field.grab_focus() # as with the keyboard: then Enter to type
		await get_tree().process_frame
		field.edit()
		field.select_all()
		for ch in "Test Track":
			_key(e, KEY_NONE, ch.unicode_at(0))
			await get_tree().process_frame
		field = _field(e, field_name)
		assert_bool(field.has_focus() and field.is_editing()).override_failure_message("%s lost the typing" % field_name).is_true()
		assert_str(field.text).is_equal("Test Track")
		_key(e, KEY_ENTER)
		await get_tree().process_frame
		await get_tree().process_frame
	assert_str(String(d.info.name)).is_equal("Test Track")
	assert_str(String(d.info.author)).is_equal("Test Track")
	assert_int(d.history.version() - steps).is_equal(2)
	# Leaving a field keeps what was typed too; an empty one goes back to what it was.
	var author := _field(e, "Author")
	author.grab_focus()
	author.edit()
	author.text = "Someone"
	_field(e, "Name").grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(String(d.info.author)).is_equal("Someone")
	var name := _field(e, "Name")
	name.grab_focus()
	name.edit()
	name.text = "  "
	_field(e, "Author").grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(String(d.info.name)).is_equal("Test Track")
	assert_str(_field(e, "Name").text).is_equal("Test Track")
	e.queue_free()
	await get_tree().process_frame


func _field(e: TrackEditor, field_name: String) -> LineEdit:
	for c in e._content.find_children("*", "LineEdit", true, false):
		if String((c as LineEdit).accessibility_name) == field_name:
			return c
	return null


func _key(e: TrackEditor, keycode: Key, unicode := 0) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = keycode
		k.physical_keycode = keycode
		k.unicode = unicode
		k.pressed = pressed
		e.get_viewport().push_input(k)
