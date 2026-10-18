extends GdUnitTestSuite
## Keeping downloads (docs/NETWORKING.md §7, MP-05): a car and a track that arrived over the
## network are listed, saved into the garage and the track library, and written out as files.
## A part-finished download, and anything outside the cache, are refused.

var dir := "user://tests/content_import/"
## Files made outside the test folder (the garage is a fixed path), removed afterwards.
var _made: Array[String] = []


func before_test() -> void:
	ContentStore.root = dir.path_join("cache/")
	TrackLibrary.user_dir = dir.path_join("tracks/")
	_remove(dir)
	DirAccess.make_dir_recursive_absolute(TrackLibrary.user_dir)


func after_test() -> void:
	ContentStore.root = "user://cache/content/"
	TrackLibrary.user_dir = "user://tracks/"
	for path in _made:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_made.clear()
	_remove(dir)


func test_a_downloaded_car_is_listed_and_kept() -> void:
	var cached := _cached_car("Sent Car")
	var listed := ContentImport.list("cars")
	assert_int(listed.size()).is_equal(1)
	assert_bool(listed[0].complete).is_true()
	assert_str(ContentImport.label(listed[0])).contains("Sent Car")
	assert_str(ContentImport.label(listed[0])).contains("by Host")

	var saved := ContentImport.save_car(cached)
	assert_str(String(saved.error)).is_empty()
	_made.append(String(saved.path))
	var pkg := PackageLoader.load_package(String(saved.path))
	assert_str(pkg.error).is_empty()
	assert_str(String(pkg.manifest.name)).is_equal("Sent Car")
	pkg.free_scenes()


func test_keeping_both_gives_the_copy_a_new_id() -> void:
	var cached := _cached_car("Twin")
	var first := ContentImport.save_car(cached)
	assert_str(String(first.error)).is_empty()
	_made.append(String(first.path))
	var copy := ContentImport.save_car(cached, true)
	assert_str(String(copy.error)).is_empty()
	_made.append(String(copy.path))
	assert_str(String(copy.path)).is_not_equal(String(first.path))
	assert_str(String(copy.manifest.id)).is_not_equal(String(first.manifest.id))
	assert_str(String(copy.manifest.name)).is_equal("Twin copy")


func test_a_part_download_is_refused() -> void:
	var cached := _cached_car("Half Here")
	DirAccess.remove_absolute(cached.path_join("model/body.glb"))
	assert_bool(ContentImport.list("cars")[0].complete).is_false()
	assert_str(ContentImport.label(ContentImport.list("cars")[0])).contains("still downloading")
	var saved := ContentImport.save_car(cached)
	assert_bool(saved.ok).is_false()
	assert_str(String(saved.error)).is_equal("Only part of this was downloaded")


func test_only_the_cache_can_be_kept() -> void:
	assert_str(String(ContentImport.save_car("res://content/cars/noss_box").error)).is_equal("Not a download")


func test_a_downloaded_track_is_kept_and_exported() -> void:
	var cached := _cached_track("Sent Track")
	assert_int(ContentImport.list("tracks").size()).is_equal(1)
	var saved := ContentImport.save_track(cached)
	assert_str(String(saved.error)).is_empty()
	assert_str(String(saved.path)).starts_with(TrackLibrary.user_dir)
	assert_str(TrackLoader.load_package(String(saved.path)).error).is_empty()
	assert_str(ContentImport.owned_track(String(saved.manifest.id))).is_equal(String(saved.path))

	var dest := dir.path_join("out.nosstrack")
	assert_str(String(ContentImport.export_package("tracks", cached, dest).error)).is_empty()
	assert_str(TrackLoader.load_package(dest).error).is_empty()


func test_an_export_is_the_same_package() -> void:
	var cached := _cached_car("Exported")
	var dest := dir.path_join("out.noss")
	assert_str(String(ContentImport.export_package("cars", cached, dest).error)).is_empty()
	var pkg := PackageLoader.load_package(dest)
	assert_str(pkg.error).is_empty()
	pkg.free_scenes()
	# The manifest's own bytes are the package's content hash, so a copy keeps them.
	var source := PackageSource.open(dest, PackageLoader.DEFAULT_LIMITS)
	assert_bool(source.read("manifest.json") == FileAccess.get_file_as_bytes(cached.path_join("manifest.json"))).is_true()
	source.close()


## A car as a finished download: the built-in box unpacked under a cache hash.
func _cached_car(car_name: String) -> String:
	var at := ContentStore.root.path_join("cars").path_join("a".repeat(64))
	var err := PackageWriter.write_folder(at, { "name": car_name, "author": "Host", "license": "CC0-1.0", "family": "car" },
		PackageWriter.read_folder("res://content/cars/noss_box"))
	assert_str(err).is_empty()
	return at


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
