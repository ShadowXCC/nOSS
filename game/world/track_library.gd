class_name TrackLibrary
extends RefCounted
## Every track this game can drive (EDT-07): the built-in ones (folders in res://content/tracks/),
## the player's (user://tracks/*.nosstrack) and downloaded ones (the content cache, by hash).
## A track is referred to by id, path or content hash ("sha256:…").

const BUILTIN_DIR := "res://content/tracks/"
## The player's tracks (tests point it elsewhere).
static var user_dir := "user://tracks/"
const DEFAULT := "res://content/tracks/proving_ground"
const PERSONAL := "personal-use-only"


## [{path, id, name, author, license, length_m, kind, builtin, hash}], built-ins first, then the
## player's by name. Without `include_user`: built-ins only (bots).
static func list(include_user := true, include_personal := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in DirAccess.get_directories_at(BUILTIN_DIR):
		var e := entry(BUILTIN_DIR + dir)
		if not e.is_empty():
			out.append(e)
	if include_user and DirAccess.dir_exists_absolute(user_dir):
		var mine: Array[Dictionary] = []
		for file in DirAccess.get_files_at(user_dir):
			if file.ends_with(".nosstrack"):
				var e := entry(user_dir.path_join(file))
				if not e.is_empty() and (include_personal or e.license != PERSONAL):
					mine.append(e)
		mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		out.append_array(mine)
	return out


## One track's listing from its manifest; {} if it has none.
static func entry(path: String) -> Dictionary:
	var m := TrackLoader.read_manifest(path)
	if m.is_empty():
		return {}
	return {
		"path": path, "id": String(m.get("id", "")), "name": String(m.get("name", path.get_file())),
		"author": String(m.get("author", "")), "license": String(m.get("license", "")),
		"length_m": float(m.get("length_m", 0.0)), "kind": String(m.get("kind", "road")),
		"builtin": path.begins_with("res://"), "hash": manifest_hash(path),
	}


## A track by id (built-in folder name, or a library track's id), path, or content hash; "" if
## there's no such track here.
static func resolve(ref: String) -> String:
	if ref.is_empty():
		return ""
	if ref.begins_with("sha256:"):
		return by_hash(ref)
	if ref.begins_with("res://") or ref.begins_with("user://") or ref.is_absolute_path():
		return ref if FileAccess.file_exists(ref) or DirAccess.dir_exists_absolute(ref) else ""
	if DirAccess.dir_exists_absolute(BUILTIN_DIR + ref):
		return BUILTIN_DIR + ref
	for e in list():
		if e.id == ref:
			return e.path
	return ""


## The track here with this content hash: built-in, the library, or a complete download.
static func by_hash(h: String) -> String:
	for e in list():
		if e.hash == h:
			return e.path
	var cached := ContentStore.pkg_dir("tracks", h) if ContentStore.valid_hash(h) else ""
	if cached and ContentStore.pkg_complete("tracks", h):
		return cached
	return ""


## sha256 of a package's manifest.json (its content hash); "" without one.
static func manifest_hash(path: String) -> String:
	if path.ends_with(".json"):
		return ""
	var source := PackageSource.open(path, TrackLoader.LIMITS)
	var h := ""
	if not source.error and source.has("manifest.json"):
		h = "sha256:" + PlatformLoader.sha256_hex(source.read("manifest.json"))
	source.close()
	return h


## "Name · 2.5 km · author" (lists).
static func label(e: Dictionary) -> String:
	var km := float(e.get("length_m", 0.0)) / 1000.0
	var bits := [String(e.name)]
	if km > 0.0:
		bits.append("%.1f km" % km)
	if not e.get("builtin", false) and String(e.author):
		bits.append(String(e.author))
	return " · ".join(bits)
