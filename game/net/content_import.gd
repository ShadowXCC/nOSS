class_name ContentImport
extends RefCounted
## Keeping content that came over the network (docs/NETWORKING.md §7, MP-05). Cars and tracks a
## host sent sit unpacked in the content cache, addressed by hash, and go when it's cleared.
## This lists them and writes them out: a .noss in the garage, a .nosstrack in the track library,
## or a file anywhere the player picks. PackageWriter and TrackWriter read back what they write
## before it replaces anything, so a half-finished download never reaches the library.

## Where a host's bare track.json was turned into a package (NetHost._package_json).
const HOSTED := "hosted"
const CAR_KEYS := ["id", "name", "author", "license", "family"]
const TRACK_KEYS := ["id", "name", "author", "license"]


## Downloads of `kind` ("cars" or "tracks") by name: [{kind, dir, manifest, complete, bytes}].
## Tracks take in the ones hosts sent as a bare track.json. A part-downloaded package is listed
## too, marked not `complete`, so it's clear it's still coming rather than missing.
static func list(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var roots := [ContentStore.root.path_join(kind)]
	if kind == "tracks":
		roots.append(ContentStore.root.path_join(HOSTED))
	for root: String in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for folder in DirAccess.get_directories_at(root):
			var e := _entry(kind, root.path_join(folder))
			if not e.is_empty():
				out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.manifest.get("name", "")).naturalnocasecmp_to(String(b.manifest.get("name", ""))) < 0)
	return out


## "Skyline R34 · by Kaz · 14 MB", or what's holding it up instead of the size.
static func label(e: Dictionary) -> String:
	var m: Dictionary = e.manifest
	var bits := [String(m.get("name", "Unnamed"))]
	if String(m.get("author", "")):
		bits.append("by " + String(m.author))
	bits.append(size_text(int(e.bytes)) if e.complete else "still downloading")
	return " · ".join(bits)


static func size_text(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0) if bytes >= 1048576 else "%d KB" % maxi(1, bytes >> 10)


## Saves a downloaded car into the garage. With `as_copy` it takes a new id and " copy" in its
## name, for when the garage already has that car; without one, it writes over that car and
## counts its version up. Returns PackageWriter.write()'s result.
static func save_car(dir: String, as_copy := false) -> Dictionary:
	var ready := _ready(dir, CAR_KEYS)
	if ready.error:
		return _refused(ready.error)
	var info := GarageFiles.info_of(ready.manifest)
	if as_copy:
		info.id = PackageWriter.new_uuid()
		info.name = (String(info.name) + " copy").left(96)
	return PackageWriter.write(PackageWriter.garage_path(String(info.name), String(info.id)), info, PackageWriter.read_folder(dir))


## Saves a downloaded track into the player's tracks. `as_copy` as save_car's.
## Returns TrackWriter.write()'s result.
static func save_track(dir: String, as_copy := false) -> Dictionary:
	var ready := _ready(dir, TRACK_KEYS)
	if ready.error:
		return _refused(ready.error)
	var m: Dictionary = ready.manifest
	var info := {
		"id": String(m.id), "name": String(m.name), "author": String(m.author), "license": String(m.license),
		"attributions": m.get("attributions", []), "tags": m.get("tags", []),
		"source": m.get("source", TrackWriter.SOURCE), "created": m.get("created", Time.get_date_string_from_system()),
	}
	if as_copy:
		info.id = PackageWriter.new_uuid()
		info.name = (String(info.name) + " copy").left(64)
	return TrackWriter.write(TrackWriter.library_path(String(info.name), String(info.id)), info, PackageWriter.read_folder(dir))


## Writes a download out as a file at `dest`, exactly as it arrived. Returns {ok, error, path}.
static func export_package(kind: String, dir: String, dest: String) -> Dictionary:
	var ready := _ready(dir, [])
	if ready.error:
		return { "ok": false, "error": ready.error, "path": dest }
	var manifest := FileAccess.get_file_as_bytes(dir.path_join("manifest.json"))
	return PackageWriter.write_copy(dest, manifest, PackageWriter.read_folder(dir), func(p: String) -> String:
		if kind == "cars":
			var check := PackageLoader.load_package(p)
			check.free_scenes()
			return check.error
		return TrackLoader.load_package(p).error)


## The library file holding the track with this id, or "" (built-in tracks don't count).
static func owned_track(id: String) -> String:
	if id.is_empty():
		return ""
	for e in TrackLibrary.list():
		if not e.builtin and String(e.id) == id:
			return String(e.path)
	return ""


## One cache folder as a listing entry, or {} without a manifest we can read.
static func _entry(kind: String, dir: String) -> Dictionary:
	var manifest_path := dir.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return {}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_bytes(manifest_path).get_string_from_utf8())
	if not m is Dictionary or not (m as Dictionary).get("files") is Dictionary:
		return {}
	var complete := true
	var bytes := 0
	for rel: String in (m.files as Dictionary):
		var f := FileAccess.open(dir.path_join(rel), FileAccess.READ)
		if f == null:
			complete = false
		else:
			bytes += f.get_length()
			f.close()
	return { "kind": kind, "dir": dir, "manifest": m, "complete": complete, "bytes": bytes }


## A cache folder that may be written out: inside the cache, whole, and with the details the
## manifest needs. Returns {error, manifest}.
static func _ready(dir: String, required: Array) -> Dictionary:
	if not dir.begins_with(ContentStore.root):
		return { "error": "Not a download", "manifest": {} }
	var e := _entry("", dir)
	if e.is_empty():
		return { "error": "Nothing downloaded here", "manifest": {} }
	if not e.complete:
		return { "error": "Only part of this was downloaded", "manifest": {} }
	for key: String in required:
		if not (e.manifest as Dictionary).has(key):
			return { "error": "This download is missing its details", "manifest": {} }
	return { "error": "", "manifest": e.manifest }


static func _refused(error: String) -> Dictionary:
	return { "ok": false, "error": error, "path": "", "manifest": {}, "unchanged": false }
