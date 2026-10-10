class_name PackageWriter
extends RefCounted
## Writes .noss packages (docs/VEHICLE_PACKAGE.md §1-2, PKG-04): canonical JSON, a manifest
## with every file's SHA-256, the manifest first in the zip. The new file is loaded back with
## PackageLoader before it replaces anything, so a bad save never reaches the garage.

const SKIP_EXTENSIONS := ["import", "uid"]


## Writes `files` ({relative path: PackedByteArray}, without manifest.json) to `path`.
## `info`: name, author, license, family, and optionally id, tags, source. Without an id a new
## one is made. Saving the same car again bumps its version; saving it unchanged keeps the file.
## Returns {ok, error, path, manifest, unchanged}.
static func write(path: String, info: Dictionary, files: Dictionary, limits := {}) -> Dictionary:
	var result := { "ok": false, "error": "", "path": path, "manifest": {}, "unchanged": false }
	for required in ["fit.json", "paint.json", "model/body.glb"]:
		if not files.has(required):
			result.error = "Missing " + required
			return result
	for check: Array in [["fit.json", "fit"], ["paint.json", "paint"], ["sound/profile.json", "sound"]]:
		if not files.has(check[0]):
			continue
		var data: Variant = JSON.parse_string((files[check[0]] as PackedByteArray).get_string_from_utf8())
		var errors := JsonSchema.validate(data, JsonSchema.load_schema(check[1])) if data is Dictionary else PackedStringArray(["not JSON"])
		if not errors.is_empty():
			result.error = "%s: %s" % [check[0], errors[0]]
			return result

	var hashes := {}
	for rel: String in files:
		hashes[rel] = "sha256:" + PlatformLoader.sha256_hex(files[rel])
	var manifest := {
		"schema": "noss.package/1",
		"id": info.get("id", new_uuid()),
		"version": 1,
		"name": info.name,
		"author": info.author,
		"license": info.license,
		"family": info.family,
		"tags": info.get("tags", []),
		"source": info.get("source", "nOSS Fitting Bay"),
		"created": Time.get_date_string_from_system(),
		"game_min_version": ProjectSettings.get_setting("application/config/version"),
		"files": hashes,
	}
	var old := PackageLoader.read_manifest(path) if FileAccess.file_exists(path) else {}
	if not old.is_empty():
		if old.get("id") != manifest.id:
			result.error = "Another car uses that file"
			return result
		if _same_content(old, manifest):
			result.ok = true
			result.unchanged = true
			result.manifest = old
			return result
		manifest.version = int(old.get("version", 0)) + 1
	var errors := JsonSchema.validate(manifest, JsonSchema.load_schema("package"))
	if not errors.is_empty():
		result.error = "manifest.json: " + errors[0]
		return result

	var tmp := path + ".tmp"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var zip := ZIPPacker.new()
	if zip.open(tmp) != OK:
		result.error = "Can't write " + tmp
		return result
	_add(zip, "manifest.json", canonical_json(manifest).to_utf8_buffer())
	var names := files.keys()
	names.sort()
	for rel: String in names:
		_add(zip, rel, files[rel])
	zip.close()

	var lim := PackageLoader.DEFAULT_LIMITS.merged(limits, true)
	if FileAccess.get_file_as_bytes(tmp).size() > int(lim.max_zip_bytes):
		DirAccess.remove_absolute(tmp)
		result.error = "Package over %d MB" % (int(lim.max_zip_bytes) >> 20)
		return result
	var check := PackageLoader.load_package(tmp, limits)
	check.free_scenes()
	if not check.ok():
		DirAccess.remove_absolute(tmp)
		result.error = "Saved car doesn't load: " + check.error
		return result
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		result.error = "Can't replace " + path
		return result
	result.ok = true
	result.manifest = manifest
	return result


## Writes `files` and their manifest into a folder: an unpacked package the loader can open
## (Fitting Bay drafts and test drives). No checks; write() does those. Returns an error or "".
static func write_folder(dir: String, info: Dictionary, files: Dictionary) -> String:
	var hashes := {}
	for rel: String in files:
		var target := dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			return "Can't write " + target
		f.store_buffer(files[rel])
		f.close()
		hashes[rel] = "sha256:" + PlatformLoader.sha256_hex(files[rel])
	var manifest := {
		"schema": "noss.package/1", "id": info.get("id", new_uuid()), "version": 1, "name": info.name,
		"author": info.author, "license": info.license, "family": info.family, "tags": info.get("tags", []),
		"source": info.get("source", "nOSS Fitting Bay"), "files": hashes,
	}
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	if f == null:
		return "Can't write the manifest"
	f.store_string(canonical_json(manifest))
	f.close()
	return ""


## Unpacks a package (zip or folder) into `dir` for editing. Returns an error or "".
static func unpack(path: String, dir: String) -> String:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if source.error:
		return source.error
	for rel in source.files():
		var target := dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			source.close()
			return "Can't write " + target
		f.store_buffer(source.read(rel))
		f.close()
	source.close()
	return ""


## The files of an unpacked package folder, without its manifest: {relative path: bytes}.
static func read_folder(dir: String, prefix := "") -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(dir.path_join(prefix)):
		var rel := prefix.path_join(file) if prefix else file
		if rel == "manifest.json" or file.get_extension() in SKIP_EXTENSIONS or file.begins_with("."):
			continue
		out[rel] = FileAccess.get_file_as_bytes(dir.path_join(rel))
	for sub in DirAccess.get_directories_at(dir.path_join(prefix)):
		if not sub.begins_with("."):
			out.merge(read_folder(dir, prefix.path_join(sub) if prefix else sub))
	return out


## Sorted keys, two-space indent, UTF-8, trailing newline (docs/VEHICLE_PACKAGE.md §2).
static func canonical_json(data: Variant) -> String:
	return JSON.stringify(data, "  ", true) + "\n"


## A random (version 4) UUID.
static func new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var hex := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## A garage file name for `car_name`; another car's file is never reused.
static func garage_path(car_name: String, id: String) -> String:
	var slug := ""
	for c in car_name.to_lower():
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while slug.contains("__"):
		slug = slug.replace("__", "_")
	slug = slug.strip_edges().trim_prefix("_").trim_suffix("_").left(48)
	if slug.is_empty():
		slug = "car"
	var path := PackageLoader.GARAGE_DIR + slug + ".noss"
	var n := 2
	while FileAccess.file_exists(path) and PackageLoader.read_manifest(path).get("id") != id:
		path = PackageLoader.GARAGE_DIR + "%s_%d.noss" % [slug, n]
		n += 1
	return path


static func _same_content(old: Dictionary, new: Dictionary) -> bool:
	for key in ["name", "author", "license", "family", "tags", "files"]:
		if JSON.stringify(old.get(key)) != JSON.stringify(new.get(key)):
			return false
	return true


static func _add(zip: ZIPPacker, rel: String, bytes: PackedByteArray) -> void:
	zip.start_file(rel)
	zip.write_file(bytes)
	zip.close_file()
