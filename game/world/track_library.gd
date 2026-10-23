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


## [{path, id, name, author, license, length_m, kind, type, builtin, hash}], built-ins first, then
## the player's by name. Without `include_user`: built-ins only (bots). With `type`, only tracks of
## that type ("circuit", "highway").
static func list(include_user := true, include_personal := true, type := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in DirAccess.get_directories_at(BUILTIN_DIR):
		var e := entry(BUILTIN_DIR + dir)
		if not e.is_empty() and (type.is_empty() or e.type == type):
			out.append(e)
	if include_user and DirAccess.dir_exists_absolute(user_dir):
		var mine: Array[Dictionary] = []
		for file in DirAccess.get_files_at(user_dir):
			if file.ends_with(".nosstrack"):
				var e := entry(user_dir.path_join(file))
				if not e.is_empty() and (include_personal or e.license != PERSONAL) and (type.is_empty() or e.type == type):
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
		"length_m": float(m.get("length_m", 0.0)), "kind": String(m.get("kind", "road")), "type": String(m.get("type", "circuit")),
		"builtin": path.begins_with("res://"), "hash": manifest_hash(path), "tags": m.get("tags", []),
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


## The track here with this content hash: built-in, the library (unless not `include_user`), or a
## complete download.
static func by_hash(h: String, include_user := true) -> String:
	for e in list(include_user):
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


## The rules a track suggests (its track.json's `rules`, D207); {} if none (or no track).
static func rules(path: String) -> Dictionary:
	var text := ""
	if path.ends_with(".json"):
		text = FileAccess.get_file_as_string(path)
	elif path:
		var source := PackageSource.open(path, TrackLoader.LIMITS)
		if not source.error and source.has("track.json"):
			text = source.read("track.json").get_string_from_utf8()
		source.close()
	var d: Variant = JSON.parse_string(text) if text else null
	var own: Variant = (d as Dictionary).get("rules", {}) if d is Dictionary else {}
	return own if own is Dictionary else {}


## A track's type ("circuit", "highway") by its manifest, or a bare track.json's own; "" if it's
## not a track.
static func type_of(path: String) -> String:
	if path.ends_with(".json"):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		return String(d.get("type", "circuit")) if d is Dictionary else ""
	var m := TrackLoader.read_manifest(path)
	return String(m.get("type", "circuit")) if not m.is_empty() else ""


## "Name · 2.5 km · author" for lists: "Gearworks · 1.5 km · Kart", "Crate Yard" (arenas have no
## length).
static func label(e: Dictionary) -> String:
	var km := float(e.get("length_m", 0.0)) / 1000.0
	var bits := [String(e.name)]
	if km > 0.0 and String(e.get("type", "circuit")) != "arena":
		bits.append("%.1f km" % km)
	if "kart" in e.get("tags", []) and String(e.get("type", "circuit")) == "circuit":
		bits.append("Kart") # made for karts (any class may race it)
	if not e.get("builtin", false) and String(e.author):
		bits.append(String(e.author))
	return " · ".join(bits)
