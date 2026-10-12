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
	Settings.use_folder("user://")


func test_both_tracks_are_offered_and_the_pick_is_kept() -> void:
	var picker := TrackPicker.new()
	add_child(picker)
	await get_tree().process_frame
	await get_tree().process_frame
	var names := picker._buttons.map(func(b: Button) -> String: return UiKit.text_of(b))
	assert_str(String(names[0])).starts_with("Proving Ground · 2.5 km")
	assert_str(String(names[1])).starts_with("Hills · 1.")
	assert_str(String(names[1])).ends_with("Tester")
	assert_str(String(names[-1])).is_equal("Back")
	(picker._buttons[1] as Button).grab_focus()
	await get_tree().process_frame
	assert_object(picker._preview.track).is_not_null()
	var got := [""]
	picker.picked.connect(func(p: String) -> void: got[0] = p)
	(picker._buttons[1] as Button).pressed.emit()
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
	track_row.gui_input.emit(right)
	assert_str(String(Settings.profile.last_track)).ends_with("hills.nosstrack")
	menu.queue_free()
	Settings.profile.last_track = ""
