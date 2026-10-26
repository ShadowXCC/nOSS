extends GdUnitTestSuite
## Downloads (docs/NETWORKING.md §7): what a host sent, listed with what can be done with it. Cars
## are in the Fitting Bay's Import step, "From online games" (docs/UI_FLOW.md §8): save to the
## garage, export, or open in the bay. Tracks are in the track editor's Downloaded tracks. A
## part-finished download is shown but can't be used yet.

var dir := "user://tests/downloads/"
## Garage files made here (the garage is a fixed path), removed afterwards.
var _made: Array[String] = []
var _old_size: Vector2i


func before_test() -> void:
	ContentStore.root = dir.path_join("cache/")
	TrackLibrary.user_dir = dir.path_join("tracks/")
	_remove(dir)
	DirAccess.make_dir_recursive_absolute(TrackLibrary.user_dir)
	Game.bay_draft = null
	Game.bay_from = ""
	_old_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720) # headless windows start at 64 x 64


func after_test() -> void:
	ContentStore.root = "user://cache/content/"
	TrackLibrary.user_dir = "user://tracks/"
	for path in _made:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_made.clear()
	_remove(dir)
	Game.bay_from = ""
	get_tree().root.size = _old_size


func test_a_downloaded_car_is_listed_in_the_bay() -> void:
	_cached_car("Sent Car")
	var bay := await _bay()
	var labels := _labels(bay)
	assert_bool(labels.has("From online games")).is_true()
	assert_bool(labels.any(func(t: String) -> bool: return t.begins_with("Sent Car · by Host · "))).is_true()
	var save := _button(bay, "Save to garage")
	assert_bool(save.disabled).is_false()
	assert_str(save.accessibility_description).is_equal("Keep Sent Car in your garage")
	assert_str(_button(bay, "Open in bay").accessibility_description).is_equal("Fit Sent Car before saving it")
	# Down from the import folder's buttons goes through each of the car's.
	_button(bay, "Open import folder").grab_focus()
	for text in ["Save to garage", "Export…", "Open in bay"]:
		await _push("ui_down")
		assert_str((_focused() as Button).text).is_equal(text)
	await _leave(bay)


func test_a_part_download_cannot_be_used_yet() -> void:
	var at := _cached_car("Half Here")
	DirAccess.remove_absolute(at.path_join("model/body.glb"))
	var bay := await _bay()
	assert_bool(_labels(bay).has("Half Here · by Host · still downloading")).is_true()
	for text in ["Save to garage", "Export…", "Open in bay"]:
		var b := _button(bay, text)
		assert_bool(b.disabled).override_failure_message(text).is_true()
		assert_int(b.focus_mode).is_equal(Control.FOCUS_NONE)
	await _leave(bay)


func test_no_downloads_says_so() -> void:
	var bay := await _bay()
	assert_bool(_labels(bay).has("From online games")).is_true()
	assert_bool(_labels(bay).has("None yet. Cars from games you join land here.")).is_true()
	assert_object(_button(bay, "Save to garage")).is_null()
	await _leave(bay)


## Saved once it's simply kept; saved again the bay asks, and Keep both makes a copy with its own
## id. Exit then goes back to the Garage on the car just saved.
func test_a_downloaded_car_is_saved_to_the_garage() -> void:
	_cached_car("Kept Car")
	var id := String(ContentImport.list("cars")[0].manifest.id)
	var bay := await _bay()
	_button(bay, "Save to garage").pressed.emit()
	var saved := GarageFiles.with_id(id)
	_made.append(saved)
	assert_str(saved).is_not_empty()
	assert_str(bay._status.text).is_equal("Saved as " + saved.get_file())

	var save := _button(bay, "Save to garage")
	save.grab_focus()
	save.pressed.emit()
	await get_tree().process_frame
	assert_bool(is_instance_valid(bay._overlay)).is_true()
	assert_bool(_labels(bay._overlay).has("Kept Car is already in your garage.")).is_true()
	_button(bay._overlay, "Keep both").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(bay._overlay)).is_false()
	assert_object(_focused()).is_same(save) # back where the question came from
	_made.append(bay._saved_path)
	var copy := PackageLoader.read_manifest(bay._saved_path)
	assert_str(String(copy.name)).is_equal("Kept Car copy")
	assert_str(String(copy.id)).is_not_equal(id)

	var asked: Array[String] = []
	var picked: Array[String] = []
	var on_scene := func(scene_name: String, scene: Node) -> void:
		asked.append(scene_name)
		if scene is Garage:
			picked.append((scene as Garage).start_car)
	Game.scene_requested.connect(on_scene)
	Game.hold_scenes = true
	Game.bay_from = "garage"
	bay._exit()
	Game.hold_scenes = false
	Game.scene_requested.disconnect(on_scene)
	assert_array(asked).contains_exactly(["Garage"])
	assert_array(picked).contains_exactly([bay._saved_path])
	bay.free()


## Open in bay fits it like a .noss: the cache is never written to, saving makes a garage car.
func test_a_downloaded_car_opens_in_the_bay() -> void:
	_cached_car("Fit Me")
	var bay := await _bay()
	_button(bay, "Open in bay").pressed.emit()
	for i in 600:
		if bay.draft != null and not bay._busy:
			break
		await get_tree().process_frame
	assert_object(bay.draft).is_not_null()
	assert_str(bay.draft.car_name).is_equal("Fit Me")
	assert_str(bay.draft.edit_path).is_empty()
	assert_object(bay.draft.scene).is_not_null()
	assert_str(bay._status.text).is_equal("Imported Fit Me")
	await _leave(bay)


func test_a_downloaded_track_is_listed_with_what_it_can_do() -> void:
	_cached_track("Sent Track")
	var menu := await _tracks()
	assert_bool(_labels(menu).has("Downloaded tracks")).is_true()
	assert_bool(_labels(menu).any(func(t: String) -> bool: return t.begins_with("Sent Track · by Host · "))).is_true()
	assert_array(_buttons(menu, false)).contains_exactly(["Save to my tracks", "Export…", "Back"])
	menu.free()


func test_a_part_track_cannot_be_saved_yet() -> void:
	var at := _cached_track("Half Here")
	DirAccess.remove_absolute(at.path_join("track.json"))
	var menu := await _tracks()
	assert_bool(_labels(menu).any(func(t: String) -> bool: return t.contains("still downloading"))).is_true()
	assert_array(_buttons(menu, false)).contains_exactly(["Back"])
	assert_array(_buttons(menu, true)).contains_exactly(["Save to my tracks", "Export…"])
	menu.free()


func test_no_tracks_says_so() -> void:
	var menu := await _tracks()
	assert_bool(_labels(menu).any(func(t: String) -> bool: return t.contains("Nothing downloaded yet"))).is_true()
	assert_array(_buttons(menu, false)).contains_exactly(["Back"])
	menu.free()


func _bay() -> FittingBay:
	var bay := FittingBay.new()
	add_child(bay)
	await get_tree().process_frame
	await get_tree().process_frame
	return bay


## Throws the bay's draft away (it lives in user://fitting/) before the bay goes.
func _leave(bay: FittingBay) -> void:
	bay._leave()
	bay._discard_draft()
	bay.free()
	await get_tree().process_frame


func _tracks() -> DownloadsMenu:
	var menu := DownloadsMenu.new()
	add_child(menu)
	await get_tree().process_frame
	return menu


func _push(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		get_tree().root.push_input(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _focused() -> Control:
	return get_tree().root.gui_get_focus_owner()


## The button labelled `text` (not one waiting to be freed), or null.
static func _button(under: Node, text: String) -> Button:
	for b: Button in under.find_children("*", "Button", true, false):
		if b.text == text and not b.is_queued_for_deletion():
			return b
	return null


static func _labels(under: Node) -> Array:
	return under.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


static func _buttons(menu: Control, disabled: bool) -> Array:
	var found: Array = menu.find_children("*", "Button", true, false)
	return found.filter(func(b: Button) -> bool: return b.disabled == disabled).map(func(b: Button) -> String: return b.text)


## A car as a finished download: the built-in box unpacked under a cache hash.
func _cached_car(car_name: String) -> String:
	var at := ContentStore.root.path_join("cars").path_join("c".repeat(64))
	var err := PackageWriter.write_folder(at, { "name": car_name, "author": "Host", "license": "CC0-1.0", "family": "car" },
		PackageWriter.read_folder("res://content/cars/noss_box"))
	assert_str(err).is_empty()
	return at


## A track as a finished download: the Proving Ground unpacked under a cache hash.
func _cached_track(track_name: String) -> String:
	var at := ContentStore.root.path_join("tracks").path_join("b".repeat(64))
	var err := TrackWriter.write_folder(at, { "name": track_name, "author": "Host", "license": "CC0-1.0" },
		PackageWriter.read_folder("res://content/tracks/proving_ground"))
	assert_str(err).is_empty()
	return at


static func _remove(at: String) -> void:
	if not DirAccess.dir_exists_absolute(at):
		return
	for f in DirAccess.get_files_at(at):
		DirAccess.remove_absolute(at.path_join(f))
	for sub in DirAccess.get_directories_at(at):
		_remove(at.path_join(sub))
	DirAccess.remove_absolute(at)
