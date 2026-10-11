class_name ContentStore
extends RefCounted
## Downloaded content, addressed by hash (docs/NETWORKING.md §7, MP-05, D80):
##   cars/<hex>/       a car as an unpacked package; files arrive one by one, each checked
##                     against the manifest's hash before it lands (a partial car loads at a
##                     lower tier: data only, or its smallest LOD)
##   platforms/<hex>.json, tracks/<hex>.json
##   tmp/              files being written, and partial downloads (<hex>.part) to resume
## Files are written to tmp/ and renamed into place, so several games can share one cache.

const KINDS := ["cars", "platforms", "tracks"]
## Package files for each tier, beyond what lower tiers bring.
const DATA_FILES := ["manifest.json", "fit.json", "paint.json", "sound/profile.json"]

static var root := "user://cache/content/"
static var _hash_re: RegEx


static func valid_hash(h: String) -> bool:
	if _hash_re == null:
		_hash_re = RegEx.create_from_string("^sha256:[0-9a-f]{64}$")
	return _hash_re.search(h) != null


static func hex(h: String) -> String:
	return h.trim_prefix("sha256:")


static func car_dir(car_hash: String) -> String:
	return root.path_join("cars").path_join(hex(car_hash))


static func file_path(kind: String, h: String) -> String:
	return root.path_join(kind).path_join(hex(h) + ".json")


static func tmp_dir() -> String:
	return root.path_join("tmp")


static func part_path(h: String) -> String:
	return tmp_dir().path_join(hex(h) + ".part")


## The cached car's manifest, or {} if it isn't here (or doesn't hash right).
static func car_manifest(car_hash: String) -> Dictionary:
	var path := car_dir(car_hash).path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return {}
	var bytes := FileAccess.get_file_as_bytes(path)
	if "sha256:" + PlatformLoader.sha256_hex(bytes) != car_hash:
		return {}
	var m: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return m if m is Dictionary and m.get("files") is Dictionary else {}


## Which of `files` the cached car doesn't have yet.
static func car_missing(car_hash: String, files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := car_dir(car_hash)
	for rel in files:
		if not FileAccess.file_exists(dir.path_join(rel)):
			out.append(rel)
	return out


## A package's files by tier: data (manifest, fit, paint, sound profile), preview (the smallest
## LOD), full (the other models and the thumbnail) and audio (own recordings).
static func tiers(manifest: Dictionary) -> Dictionary:
	var listed: Dictionary = manifest.get("files", {})
	var out := { "data": PackedStringArray(), "preview": PackedStringArray(), "full": PackedStringArray(), "audio": PackedStringArray() }
	for rel in DATA_FILES:
		if rel == "manifest.json" or listed.has(rel):
			out.data.append(rel)
	var models := model_files(listed)
	if not models.is_empty():
		out.preview.append(models[-1])
	for rel: String in listed:
		if rel in out.data or rel in out.preview:
			continue
		if rel.begins_with("sound/") and rel.get_extension() in PackageLoader.AUDIO_TYPES:
			out.audio.append(rel)
		else:
			out.full.append(rel)
	return out


## model/body.glb, then lod1, lod2… as far as the manifest lists them.
static func model_files(listed: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if listed.has("model/body.glb"):
		out.append("model/body.glb")
	var n := 1
	while listed.has("model/lod%d.glb" % n):
		out.append("model/lod%d.glb" % n)
		n += 1
	return out


## Stores a car file after checking its hash: the manifest must hash to the car's hash, other
## files to what the cached manifest lists. Returns "" or why not.
static func put_car_file(car_hash: String, rel: String, bytes: PackedByteArray) -> String:
	if not valid_hash(car_hash) or not NossPackage.is_safe_path(rel):
		return "Bad name"
	var want := car_hash if rel == "manifest.json" else String(car_manifest(car_hash).get("files", {}).get(rel, ""))
	if want.is_empty():
		return "Not in the manifest"
	if "sha256:" + PlatformLoader.sha256_hex(bytes) != want:
		return "Hash mismatch"
	return _write(car_dir(car_hash).path_join(rel), bytes)


## Stores a platform or track file after checking its hash.
static func put_file(kind: String, h: String, bytes: PackedByteArray) -> String:
	if kind not in KINDS or kind == "cars" or not valid_hash(h):
		return "Bad name"
	if "sha256:" + PlatformLoader.sha256_hex(bytes) != h:
		return "Hash mismatch"
	return _write(file_path(kind, h), bytes)


static func has_file(kind: String, h: String) -> bool:
	return valid_hash(h) and FileAccess.file_exists(file_path(kind, h))


static func _write(path: String, bytes: PackedByteArray) -> String:
	if FileAccess.file_exists(path):
		return ""
	DirAccess.make_dir_recursive_absolute(tmp_dir())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := tmp_dir().path_join("%d_%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()])
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Can't write the cache"
	f.store_buffer(bytes)
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return "" if FileAccess.file_exists(path) else "Can't write the cache"
	return ""


## Deletes everything in the cache (Settings, "Clear downloads").
static func clear() -> void:
	_remove_tree(root)


static func size_bytes() -> int:
	return _tree_size(root)


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	DirAccess.remove_absolute(dir)


static func _tree_size(dir: String) -> int:
	var total := 0
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	for f in DirAccess.get_files_at(dir):
		var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
		if fa:
			total += fa.get_length()
	for d in DirAccess.get_directories_at(dir):
		total += _tree_size(dir.path_join(d))
	return total
