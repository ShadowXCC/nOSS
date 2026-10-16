extends GdUnitTestSuite
## The Road tool and templates (EDT-01): points go in by clicking, into the road when clicked
## on it; a drag is one undo; only the moved segments are rebuilt; the templates build, the
## figure 8 on a bridge.

const DIR := "user://tests/road_tool"


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


func _hit(p: Vector3) -> Dictionary:
	return { "hit": true, "position": p, "normal": Vector3.UP, "collider": null }


func _event(kind: String, p: Vector3, screen := Vector2(-100, -100)) -> Dictionary:
	return { "kind": kind, "screen": screen, "hit": _hit(p), "shift": false, "alt": false, "crosshair": false }


func test_clicks_add_points_and_a_drag_is_one_undo() -> void:
	var d := TrackDraft.blank("Clicked", Vector2i(2, 2))
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Road")
	var road: EditorTool = e.tool
	for p: Vector3 in [Vector3(-150, 0, -100), Vector3(150, 0, -100), Vector3(150, 0, 100), Vector3(-150, 0, 100)]:
		road.pointer(_event("press", p))
		road.pointer(_event("release", p))
	assert_int(d.points().size()).is_equal(4)
	assert_int(d.track().samples.size()).is_greater(100)
	# On the road (a square's road bulges out between its points): a point goes into it, between 0
	# and 1, not at the end.
	var on_road := d.track().point_at(d.track().distances[d.track().seg_first[0]] + 150.0)
	road.pointer(_event("press", on_road + Vector3(0, 0, 1)))
	road.pointer(_event("release", on_road))
	assert_int(d.points().size()).is_equal(5)
	assert_float(float(d.points()[1].p[0])).is_equal_approx(on_road.x, 1.0)
	# Grab point 2 (selected by its index) and drag it: one action.
	road.set("selected", 2)
	road.set("_dragging", 2)
	var version := d.history.version()
	for x in [160.0, 170.0, 180.0]:
		road.pointer(_event("drag", Vector3(x, 0, -100)))
	road.pointer(_event("release", Vector3(180, 0, -100)))
	assert_float(float(d.points()[2].p[0])).is_equal(180.0)
	assert_str(d.undo()).is_equal("Move point")
	assert_float(float(d.points()[2].p[0])).is_equal(150.0)
	assert_int(d.history.version()).is_equal(version) # back where it was: nothing to save
	# Every row of the point's panel is named.
	road.call("_select", 1)
	for c: Control in e._content.find_children("*", "Control", true, false) + e._content.get_children():
		if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).is_not_empty()
	e.queue_free()
	await get_tree().process_frame


func test_a_move_rebuilds_only_its_segments() -> void:
	var d := TrackTemplates.make("circuit")
	var preview := TrackPreview.new()
	add_child(preview)
	preview.setup(d)
	var road := preview.get_node("Road")
	var before := {}
	for n in road.get_children():
		before[String(n.name)] = n
	var p: Array = d.points()[6].p
	d.move_point(6, Vector3(p[0] + 15.0, p[1], p[2] + 10.0))
	await get_tree().process_frame
	var renewed := []
	for name: String in before:
		var now := road.get_node_or_null(name)
		if now != before[name]:
			renewed.append(name)
	renewed.sort()
	assert_array(renewed).contains_exactly_in_any_order(["Seg_4", "Seg_5", "Seg_6", "Seg_7"])
	preview.queue_free()
	await get_tree().process_frame


## While a point is dragged only the road follows; the ground's bed is cut on release, for the
## segments the drag touched (not the whole map).
func test_a_drag_cuts_the_ground_when_it_ends() -> void:
	var d := TrackTemplates.make("circuit")
	var preview := TrackPreview.new()
	add_child(preview)
	preview.setup(d)
	var p: Array = d.points()[6].p
	for k in 3:
		d.drag_point(6, Vector3(p[0] + 5.0 * (k + 1), p[1], p[2]))
		preview._flush()
	var waiting: Rect2i = preview._unconformed
	assert_bool(waiting.has_area()).is_true()
	assert_bool(waiting.size.x < d.terrain.field.get_size().x).is_true()
	d.end_move()
	await get_tree().process_frame
	assert_bool(preview._unconformed.has_area()).is_false()
	preview.queue_free()
	await get_tree().process_frame


func test_templates_build() -> void:
	for t: Array in TrackTemplates.list():
		var d := TrackTemplates.make(String(t[0]))
		var track := d.track()
		if t[0] == "empty":
			assert_int(track.samples.size()).is_equal(0)
			continue
		assert_bool(d.dirty()).is_false()
		if d.is_arena():
			assert_object(track.arena).is_not_null() # no laps (stunts_tool_test)
			continue
		assert_float(track.length).override_failure_message(String(t[0])).is_greater(800.0)
		if d.is_highway():
			continue # flat ground, no sectors (highway_draft_test)
		assert_int(track.sectors_m.size()).is_equal(2)
		if d.terrain: # the kart circuit is on flat ground
			assert_bool(d.terrain.area().encloses(Rect2(track.samples[0].x - 1, track.samples[0].z - 1, 2, 2))).is_true()
	var eight := TrackTemplates.make("figure8")
	var t8 := eight.track()
	eight.terrain.conform(t8)
	assert_int(Array(t8.lifted).count(1)).is_greater(20)
	var root := TrackBuilder.build(t8, eight.terrain)
	assert_object(root.get_node_or_null("Bridge")).is_not_null()
	root.free()
