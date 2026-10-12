extends SceneTree
## Brings a built-in track folder up to date (docs/TRACK_EDITOR.md §5): a noss.track/0 track.json
## becomes noss.track/1 (its set pieces as props), and manifest.json is written with every
## file's hash. Run after editing a built-in track by hand:
##   tools/godot.sh --headless -s res://tools/track_manifest.gd -- content/tracks/proving_ground


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: -- content/tracks/<id>")
		quit(1)
		return
	var dir := "res://" + args[0].trim_prefix("res://").trim_suffix("/")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("track.json")))
	if not data is Dictionary:
		printerr("No track.json in " + dir)
		quit(1)
		return
	var old := TrackLoader.read_manifest(dir)
	var info := {
		"id": String(old.get("id", data.get("id", dir.get_file()))),
		"name": String(old.get("name", data.get("name", dir.get_file()))),
		"author": String(old.get("author", data.get("author", "nOSS contributors"))),
		"license": String(old.get("license", data.get("license", "CC-BY-SA-4.0"))),
		"source": "nOSS", "created": String(old.get("created", Time.get_date_string_from_system())),
		"version": int(old.get("version", 1)),
	}
	if data.get("schema") == TrackFormat.LEGACY:
		data = TrackFormat.upgrade_v0(data)
		print("Upgraded to noss.track/1")
	data.erase("author") # they live in the manifest
	data.erase("license")
	var err := TrackFormat.validate(data)
	if err:
		printerr(err)
		quit(1)
		return
	var files := PackageWriter.read_folder(ProjectSettings.globalize_path(dir))
	files["track.json"] = PackageWriter.canonical_json(data).to_utf8_buffer()
	err = TrackWriter.write_folder(ProjectSettings.globalize_path(dir), info, files)
	if err:
		printerr(err)
		quit(1)
		return
	print("%s: %d files, %s" % [dir, files.size(), TrackLibrary.manifest_hash(dir)])
	quit()
