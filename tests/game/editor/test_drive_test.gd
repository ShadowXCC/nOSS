extends GdUnitTestSuite
## Test drives from the track editor (EDT-06): the car starts at the cursor (on the road, along
## it; off it, facing the camera's way), the pause menu leads back to the editor, and every
## keyboard and the standard pad have a key for it that clashes with nothing.

const DIR := "user://tests/test_drive"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Players.clear()
	Game.track_draft = null
	Settings.use_folder("user://")


func after_test() -> void:
	get_tree().paused = false


func test_spawn_on_the_road_runs_along_it() -> void:
	var d := TrackTemplates.make("oval")
	var t := d.track()
	var i := 100
	var on := TrackEditor.spawn_at(t, t.samples[i] + t.lefts[i] * 2.0, Vector3.RIGHT)
	var want := t.transform_at(t.distances[i], 2.0)
	assert_float(on.origin.distance_to(want.origin)).is_less(0.5)
	assert_float(on.basis.z.dot(t.tangents[i])).is_greater(0.99)
	# Near the edge: kept on the road.
	var edge := TrackEditor.spawn_at(t, t.samples[i] + t.lefts[i] * 7.0, Vector3.RIGHT)
	assert_float(t.project(edge.origin).lateral).is_less_equal(t.half_l[i] - 1.5 + 0.01)
	# In the infield: where clicked, facing the camera's way.
	var off := TrackEditor.spawn_at(t, Vector3(0, 0, 0), Vector3(1, -0.5, 0))
	assert_vector(off.origin).is_equal(Vector3.ZERO)
	assert_float(off.basis.z.dot(Vector3.RIGHT)).is_greater(0.99)
	assert_float(off.basis.x.dot(Vector3.UP.cross(Vector3.RIGHT))).is_greater(0.99)


func test_the_drive_starts_there_and_offers_the_way_back() -> void:
	Players.clear()
	var d := TrackTemplates.make("oval")
	var t := d.track()
	var at := TrackEditor.spawn_at(t, t.samples[300], Vector3.RIGHT)
	var s := Game.test_drive_session(d, at)
	s.autodrive = true
	add_child(s)
	for k in 300:
		await get_tree().process_frame
		if not s.players.is_empty() and s.players[0].vehicle:
			break
	var p := s.players[0]
	assert_float(p.spawn_at.origin.distance_to(at.origin)).is_less(0.01)
	assert_bool(s.solo).is_true()
	assert_str(s.track.id).is_equal(d.id)
	s._open_pause(p)
	var menu := p.overlay as PauseMenu
	assert_str(UiKit.text_of(menu._buttons[1])).is_equal("Back to editor")
	assert_bool(menu.back_to_editor.get_connections().size() > 0).is_true()
	s._resume(p)
	s.queue_free()
	await get_tree().process_frame


func test_presets_have_a_key_back_to_the_editor() -> void:
	var keys := {}
	for id in ["kb_full", "kb_left", "kb_right", "pad_standard"]:
		var preset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Bindings.PRESET_DIR + id + ".json"))
		var b: Dictionary = preset.bindings
		assert_bool(b.has("editor_back")).override_failure_message(id).is_true()
		# Nothing else while driving uses the same input (kart actions share only what karts
		# ignore, D135).
		var seen := {}
		for action: String in Bindings.DRIVING:
			for input: Dictionary in b.get(action, []):
				var name := str(input)
				var other: String = seen.get(name, "")
				var shared: bool = action in Bindings.KART and other in Bindings.KART_SHARES[action]
				assert_bool(other.is_empty() or shared).override_failure_message("%s: %s and %s share %s" % [id, other, action, name]).is_true()
				if other.is_empty():
					seen[name] = action
		keys[id] = seen
	# Two players on one keyboard (left and right halves) never share a key.
	for name: String in keys.kb_left:
		assert_bool(keys.kb_right.has(name)).override_failure_message("kb_left and kb_right share " + name).is_false()
