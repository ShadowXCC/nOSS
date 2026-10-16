extends GdUnitTestSuite
## Picking a track (EDT-07): the built-in and the player's own tracks, labelled; the pick is
## remembered and used by free drive, races and time trials; the race menu offers them too.

const DIR := "user://tests/track_picker"


func before() -> void:
	Settings.use_folder(DIR)
	var files := TrackPackageTest.terrain_track()
	var r := TrackWriter.write(TrackLibrary.user_dir.path_join("hills.nosstrack"), { "name": "Hills", "author": "Tester", "license": "CC0-1.0" }, files)
	assert_str(String(r.error)).is_empty()


func after() -> void:
	DirAccess.remove_absolute(TrackLibrary.user_dir.path_join("hills.nosstrack"))
	DirAccess.remove_absolute(TrackLibrary.user_dir.path_join("ring.nosstrack"))
	Settings.use_folder("user://")


func test_both_tracks_are_offered_and_the_pick_is_kept() -> void:
	var picker := TrackPicker.new()
	add_child(picker)
	await get_tree().process_frame
	await get_tree().process_frame
	var names := picker._buttons.map(func(b: Button) -> String: return UiKit.text_of(b))
	# The built-in circuits (the kart ones too), then the player's own.
	var builtin := TrackLibrary.list(false, false, "circuit").size()
	assert_bool(names.slice(0, builtin).any(func(n: String) -> bool: return n.begins_with("Proving Ground · 2.5 km"))).is_true()
	var mine := builtin
	assert_str(String(names[mine])).starts_with("Hills · 1.")
	assert_str(String(names[mine])).ends_with("Tester")
	assert_str(String(names[-1])).is_equal("Back")
	(picker._buttons[mine] as Button).grab_focus()
	await get_tree().process_frame
	assert_object(picker._preview.track).is_not_null()
	var got := [""]
	picker.picked.connect(func(p: String) -> void: got[0] = p)
	(picker._buttons[mine] as Button).pressed.emit()
	assert_str(got[0]).ends_with("hills.nosstrack")
	assert_str(Game.selected_track()).is_equal(got[0])
	picker.queue_free()
	Settings.profile.last_track = ""
	assert_str(Game.selected_track()).is_equal(TrackLibrary.DEFAULT)


func test_the_race_menu_offers_the_tracks() -> void:
	var menu := EventMenu.new()
	add_child(menu)
	await get_tree().process_frame
	var track_row := menu._rows[0] as Button
	assert_str(String(track_row.accessibility_name)).starts_with("Track: Proving Ground")
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	for i in 10: # on past the built-in ones to the player's own
		track_row.gui_input.emit(right)
		if String(Settings.profile.last_track).ends_with("hills.nosstrack"):
			break
	assert_str(String(Settings.profile.last_track)).ends_with("hills.nosstrack")
	menu.queue_free()
	Settings.profile.last_track = ""


func test_highways_and_circuits_are_listed_apart() -> void:
	var ring: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tracks/highway_ring_small.json"))
	var files := { "track.json": JSON.stringify(ring).to_utf8_buffer() }
	var r := TrackWriter.write(TrackLibrary.user_dir.path_join("ring.nosstrack"), { "name": "Ring", "author": "Tester", "license": "CC0-1.0" }, files)
	assert_str(String(r.error)).is_empty()
	var highways := TrackLibrary.list(true, true, "highway")
	# The built-in Lumen Ring, then this one.
	assert_int(highways.size()).is_equal(2)
	assert_str(String(highways[0].id)).is_equal("lumen_ring")
	assert_bool(highways.all(func(e: Dictionary) -> bool: return e.type == "highway")).is_true()
	assert_bool(TrackLibrary.list(true, true, "circuit").any(func(e: Dictionary) -> bool: return e.type == "highway")).is_false()
	var picker := TrackPicker.new()
	picker.type = "highway"
	add_child(picker)
	await get_tree().process_frame
	var names := picker._buttons.map(func(b: Button) -> String: return UiKit.text_of(b))
	assert_int(names.size()).is_equal(3)
	assert_str(String(names[0])).starts_with("Lumen Ring · 8.3 km")
	assert_str(String(names[1])).starts_with("Ring · 4.4 km")
	picker.queue_free()
	# A circuit menu never starts on a highway, even if it was picked last.
	Settings.profile.last_track = String(highways[1].path)
	assert_str(Game.selected_track("circuit")).is_equal(TrackLibrary.DEFAULT)
	assert_str(Game.selected_track("highway")).is_equal(String(highways[1].path))
	Settings.profile.last_track = ""
