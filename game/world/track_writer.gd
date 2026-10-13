class_name TrackWriter
extends RefCounted
## Writes .nosstrack packages (docs/TRACK_EDITOR.md §5, EDT-07): canonical JSON, a manifest with
## every file's SHA-256, the manifest first in the zip, as cars are (PackageWriter). The new file
## is loaded back with TrackLoader before it replaces anything.

const SOURCE := "nOSS Track Editor"


## Writes `files` ({relative path: bytes}, track.json among them, without manifest.json) to
## `path`. `info`: name, author, license, and optionally id, attributions, tags, source. Saving
## the same track again bumps its version; saving it unchanged keeps the file.
## Returns {ok, error, path, manifest, unchanged}.
static func write(path: String, info: Dictionary, files: Dictionary, limits := {}) -> Dictionary:
	var result := { "ok": false, "error": "", "path": path, "manifest": {}, "unchanged": false }
	if not files.has("track.json"):
		result.error = "Missing track.json"
		return result
	var layout: Variant = JSON.parse_string((files["track.json"] as PackedByteArray).get_string_from_utf8())
	if not layout is Dictionary:
		result.error = "track.json isn't valid JSON"
		return result
	var err := TrackFormat.validate(layout)
	if err:
		result.error = "track.json: " + err
		return result
	var manifest := manifest_for(info, files, layout)
	var old := TrackLoader.read_manifest(path) if FileAccess.file_exists(path) else {}
	if not old.is_empty():
		if old.get("id") != manifest.id:
			result.error = "Another track uses that file"
			return result
		if PackageWriter.same_content(old, manifest, ["name", "author", "license", "attributions", "tags", "files"]):
			result.ok = true
			result.unchanged = true
			result.manifest = old
			return result
		manifest.version = int(old.get("version", 0)) + 1
	var errors := JsonSchema.validate(manifest, JsonSchema.load_schema("track_package"))
	if not errors.is_empty():
		result.error = "manifest.json: " + errors[0]
		return result
	var tmp := path + ".tmp"
	result.error = PackageWriter.write_zip(tmp, manifest, files)
	if result.error:
		return result
	var lim := TrackLoader._limits(limits)
	if FileAccess.get_file_as_bytes(tmp).size() > int(lim.max_zip_bytes):
		DirAccess.remove_absolute(tmp)
		result.error = "Track over %d MB" % (int(lim.max_zip_bytes) >> 20)
		return result
	var check := TrackLoader.load_package(tmp, limits)
	if not check.ok():
		DirAccess.remove_absolute(tmp)
		result.error = "Saved track doesn't load: " + check.error
		return result
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		result.error = "Can't replace " + path
		return result
	result.ok = true
	result.manifest = manifest
	return result


## Writes `files` and their manifest into a folder: an unpacked track the loader opens (built-in
## tracks, editor drafts). Returns an error or "".
static func write_folder(dir: String, info: Dictionary, files: Dictionary) -> String:
	var layout: Variant = JSON.parse_string((files.get("track.json", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not layout is Dictionary:
		return "Missing track.json"
	for rel: String in files:
		var target := dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			return "Can't write " + target
		f.store_buffer(files[rel])
		f.close()
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	if f == null:
		return "Can't write the manifest"
	f.store_string(PackageWriter.canonical_json(manifest_for(info, files, layout)))
	f.close()
	return ""


static func manifest_for(info: Dictionary, files: Dictionary, layout: Dictionary) -> Dictionary:
	var t := TrackData.from_dict(layout)
	return {
		"schema": "noss.track_package/1",
		"id": info.get("id", PackageWriter.new_uuid()),
		"version": int(info.get("version", 1)),
		"name": info.name,
		"author": info.author,
		"license": info.license,
		"type": String(layout.get("type", "circuit")),
		"kind": "scene" if layout.get("scene") is Dictionary else "road",
		"length_m": snappedf(t.length, 0.1),
		"layout": TrackFormat.layout_hash(layout),
		"attributions": info.get("attributions", []),
		"tags": info.get("tags", []),
		"source": info.get("source", SOURCE),
		"created": info.get("created", Time.get_date_string_from_system()),
		"game_min_version": ProjectSettings.get_setting("application/config/version"),
		"files": PackageWriter.hash_files(files),
	}


## A file in the track library for `track_name`; another track's file is never reused.
static func library_path(track_name: String, id: String) -> String:
	var slug := ""
	for c in track_name.to_lower():
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while slug.contains("__"):
		slug = slug.replace("__", "_")
	slug = slug.strip_edges().trim_prefix("_").trim_suffix("_").left(48)
	if slug.is_empty():
		slug = "track"
	var dir := TrackLibrary.user_dir
	var path := dir.path_join(slug + ".nosstrack")
	var n := 2
	while FileAccess.file_exists(path) and TrackLoader.read_manifest(path).get("id") != id:
		path = dir.path_join("%s_%d.nosstrack" % [slug, n])
		n += 1
	return path
