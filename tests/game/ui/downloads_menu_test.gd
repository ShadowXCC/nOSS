extends GdUnitTestSuite
## The Downloads screen (docs/NETWORKING.md §7): what a host sent, listed with what can be done
## with it. A part-finished download is shown but can't be saved yet.

var dir := "user://tests/downloads_menu/"


func before_test() -> void:
	ContentStore.root = dir.path_join("cache/")
	_remove(dir)


func after_test() -> void:
	ContentStore.root = "user://cache/content/"
	_remove(dir)


func test_a_download_is_listed_with_what_it_can_do() -> void:
	_cached_car("Sent Car")
	var menu := await _open("cars")
	assert_bool(_labels(menu).any(func(t: String) -> bool: return t.contains("Sent Car"))).is_true()
	assert_array(_buttons(menu, false)).contains(["Save to garage", "Export…", "Back"])
	menu.free()


func test_a_part_download_cannot_be_saved_yet() -> void:
	var at := _cached_car("Half Here")
	DirAccess.remove_absolute(at.path_join("model/body.glb"))
	var menu := await _open("cars")
	assert_bool(_labels(menu).any(func(t: String) -> bool: return t.contains("still downloading"))).is_true()
	assert_array(_buttons(menu, false)).contains_exactly(["Back"])
	assert_array(_buttons(menu, true)).contains_exactly(["Save to garage", "Export…"])
	menu.free()


func test_an_empty_cache_says_so() -> void:
	var menu := await _open("tracks")
	assert_bool(_labels(menu).any(func(t: String) -> bool: return t.contains("Nothing downloaded yet"))).is_true()
	assert_array(_buttons(menu, false)).contains_exactly(["Back"])
	menu.free()


func _open(kind: String) -> DownloadsMenu:
	var menu := DownloadsMenu.new()
	menu.kind = kind
	add_child(menu)
	await get_tree().process_frame
	return menu


static func _labels(menu: Control) -> Array:
	return menu.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


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


static func _remove(at: String) -> void:
	if not DirAccess.dir_exists_absolute(at):
		return
	for f in DirAccess.get_files_at(at):
		DirAccess.remove_absolute(at.path_join(f))
	for sub in DirAccess.get_directories_at(at):
		_remove(at.path_join(sub))
	DirAccess.remove_absolute(at)
