extends GdUnitTestSuite
## What builds carry of the built-in tracks (D200). Godot imports a PNG as a texture and leaves
## the PNG itself out of exports (an include filter doesn't change that), but a track package
## hashes and reads its own bytes: without them a hilly built-in track says "Missing file" in
## every build. So every file a built-in track lists is either not imported or kept as it is.


func test_built_in_tracks_files_are_exported_as_they_are() -> void:
	var checked := 0
	for dir in DirAccess.get_directories_at("res://content/tracks"):
		var root := "res://content/tracks".path_join(dir)
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("manifest.json")))
		for rel: String in manifest.files:
			var stub := root.path_join(rel) + ".import"
			if not FileAccess.file_exists(stub):
				continue # not imported: exported as it is
			checked += 1
			var cfg := ConfigFile.new()
			assert_int(cfg.load(stub)).is_equal(OK)
			assert_str(String(cfg.get_value("remap", "importer", ""))).override_failure_message("%s is imported, so builds leave it out" % stub.trim_prefix("res://")).is_equal("keep")
	assert_int(checked).is_greater(0)


func test_the_writer_keeps_a_built_in_tracks_images() -> void:
	var dir := "res://reports/track_writer_keep"
	var d := TrackDraft.blank("Keep check")
	assert_str(TrackWriter.write_folder(dir, d.manifest_info(), d.files())).is_empty()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(dir + "/terrain/height.png.import")).is_equal(OK)
	assert_str(String(cfg.get_value("remap", "importer", ""))).is_equal("keep")
	_remove(dir)


static func _remove(at: String) -> void:
	if not DirAccess.dir_exists_absolute(at):
		return
	for f in DirAccess.get_files_at(at):
		DirAccess.remove_absolute(at.path_join(f))
	for sub in DirAccess.get_directories_at(at):
		_remove(at.path_join(sub))
	DirAccess.remove_absolute(at)
