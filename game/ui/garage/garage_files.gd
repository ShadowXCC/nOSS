class_name GarageFiles
extends RefCounted
## Garage file operations (docs/VEHICLE_PACKAGE.md §8, PKG-05): list cars with their details,
## duplicate, change files (paint, sound) and delete. Changes go through PackageWriter, so a
## car's version goes up and a bad write never replaces it.

const INDEX := "user://cache/garage_index.json"


## Every car: {path, official, manifest, triangles, thumbnail (Texture2D or null)}.
static func list() -> Array[Dictionary]:
	var index := _load_index()
	var out: Array[Dictionary] = []
	var changed := false
	for path in PackageLoader.list_available():
		var manifest := PackageLoader.read_manifest(path)
		if manifest.is_empty():
			continue
		var key := "%s|%s|%s" % [path, manifest.get("id", ""), manifest.get("version", 0)]
		if not index.has(key):
			index[key] = { "triangles": _triangles(path) }
			changed = true
		out.append({
			"path": path, "official": path.begins_with("res://"), "manifest": manifest,
			"triangles": int(index[key].triangles), "thumbnail": thumbnail(path),
		})
	if changed:
		_save_index(index)
	return out


const THUMBS := "user://cache/thumbs/"


## The package's thumb.png, or one the garage rendered for it earlier, as a texture; or null.
static func thumbnail(path: String) -> Texture2D:
	var bytes := PackedByteArray()
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if not source.error and source.has("thumb.png"):
		bytes = source.read("thumb.png")
	source.close()
	if bytes.is_empty():
		var cached := _thumb_cache(path)
		bytes = FileAccess.get_file_as_bytes(cached) if FileAccess.file_exists(cached) else PackedByteArray()
	var image := Image.new()
	return ImageTexture.create_from_image(image) if not bytes.is_empty() and image.load_png_from_buffer(bytes) == OK else null


## Keeps a rendered thumbnail for a car that has none.
static func cache_thumbnail(path: String, png: PackedByteArray) -> void:
	if png.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(THUMBS)
	var f := FileAccess.open(_thumb_cache(path), FileAccess.WRITE)
	if f:
		f.store_buffer(png)
		f.close()


static func _thumb_cache(path: String) -> String:
	var m := PackageLoader.read_manifest(path)
	return THUMBS + "%s_%d.png" % [m.get("id", path.get_file()), int(m.get("version", 0))]


## Every file of a package except its manifest.
static func read_files(path: String) -> Dictionary:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	var out := {}
	if source.error:
		return out
	for rel in source.files():
		if rel != "manifest.json":
			out[rel] = source.read(rel)
	source.close()
	return out


static func info_of(manifest: Dictionary) -> Dictionary:
	return {
		"id": manifest.id, "name": manifest.name, "author": manifest.author, "license": manifest.license,
		"family": manifest.family, "tags": manifest.get("tags", []), "source": manifest.get("source", ""),
	}


## Replaces some of a garage car's files ({relative path: bytes}). Returns PackageWriter's result.
static func update(path: String, changes: Dictionary) -> Dictionary:
	var files := read_files(path)
	files.merge(changes, true)
	return PackageWriter.write(path, info_of(PackageLoader.read_manifest(path)), files)


## A copy with a new id in the garage. Returns PackageWriter's result.
static func copy_car(path: String) -> Dictionary:
	var manifest := PackageLoader.read_manifest(path)
	var info := info_of(manifest)
	info.id = PackageWriter.new_uuid()
	info.name = (String(manifest.name) + " copy").left(96)
	return PackageWriter.write(PackageWriter.garage_path(info.name, info.id), info, read_files(path))


## The garage file holding the car with this id, or "". Built-in cars don't count: editing or
## importing over one has always made a copy.
static func with_id(id: String) -> String:
	if id.is_empty():
		return ""
	for path in PackageLoader.list_available():
		if not path.begins_with("res://") and String(PackageLoader.read_manifest(path).get("id", "")) == id:
			return path
	return ""


## Writes a car out as a .noss at `dest`, exactly as it is: a garage file or a built-in folder
## both come out as the same package, keeping the manifest's own bytes (its content hash).
## Returns {ok, error, path}.
static func export_car(path: String, dest: String) -> Dictionary:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if source.error:
		var err := source.error
		source.close()
		return { "ok": false, "error": err, "path": dest }
	var manifest := source.read("manifest.json")
	var files := {}
	for rel in source.files():
		if rel != "manifest.json":
			files[rel] = source.read(rel)
	source.close()
	return PackageWriter.write_copy(dest, manifest, files, func(p: String) -> String:
		var check := PackageLoader.load_package(p)
		check.free_scenes()
		return check.error)


## Deletes a garage car. Official cars can't be deleted. Returns an error or "".
static func delete(path: String) -> String:
	if not path.begins_with(PackageLoader.GARAGE_DIR):
		return "Built-in cars can't be deleted"
	return "" if DirAccess.remove_absolute(path) == OK else "Can't delete " + path.get_file()


## Gives `target` the engine sound of `source`. Returns PackageWriter's result.
static func copy_sound(source: String, target: String) -> Dictionary:
	var files := read_files(source)
	var changes := {}
	for rel: String in files:
		if rel.begins_with("sound/"):
			changes[rel] = files[rel]
	if changes.is_empty():
		return { "ok": false, "error": "That car has no sound" }
	var old := read_files(target)
	for rel: String in old.keys():
		if rel.begins_with("sound/") and not changes.has(rel):
			old.erase(rel) # own recordings of the old sound go with it
	old.merge(changes, true)
	return PackageWriter.write(target, info_of(PackageLoader.read_manifest(target)), old)


static func _triangles(path: String) -> int:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if source.error or not source.has("model/body.glb"):
		source.close()
		return 0
	var check := PackageLoader.check_glb(source.read("model/body.glb"), PackageLoader.DEFAULT_LIMITS)
	source.close()
	return check.triangles


static func _load_index() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX)) if FileAccess.file_exists(INDEX) else null
	return data if data is Dictionary else {}


static func _save_index(index: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(INDEX.get_base_dir())
	var f := FileAccess.open(INDEX, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(index))
		f.close()
