class_name ContentIndex
extends RefCounted
## What this game can send to others, by file hash (D80): files of the packages in play (own
## cars from the garage or the built-ins, cached cars), plus single files (tracks, platforms).
## Only files added here are ever sent.

## file hash -> [path, rel]: a package (zip or folder) and the file in it, or a plain file ("").
var _files := {}
## car hash -> package path
var _cars := {}
## package path -> open PackageSource (a zip is read whole when opened, so keep it open)
var _sources := {}
var _mutex := Mutex.new()


## Adds a package's manifest and every file it has (a cached car may not have them all yet).
## Returns the car's hash, or "".
func add_package(path: String) -> String:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if source.error or not source.has("manifest.json"):
		source.close()
		return ""
	var bytes := source.read("manifest.json")
	var manifest: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	source.close()
	if not manifest is Dictionary or not manifest.get("files") is Dictionary:
		return ""
	var car_hash := "sha256:" + PlatformLoader.sha256_hex(bytes)
	_mutex.lock()
	_cars[car_hash] = path
	_files[car_hash] = [path, "manifest.json"]
	for rel: String in manifest.files:
		if source.has(rel):
			_files[String(manifest.files[rel])] = [path, rel]
	_mutex.unlock()
	return car_hash


## Adds a plain file (a track or a platform). Returns its hash.
func add_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var h := "sha256:" + PlatformLoader.sha256_hex(FileAccess.get_file_as_bytes(path))
	_mutex.lock()
	_files[h] = [path, ""]
	_mutex.unlock()
	return h


## Closes the open packages.
func close() -> void:
	_mutex.lock()
	for source: PackageSource in _sources.values():
		source.close()
	_sources.clear()
	_mutex.unlock()


func has(h: String) -> bool:
	_mutex.lock()
	var out := _files.has(h)
	_mutex.unlock()
	return out


func car_path(car_hash: String) -> String:
	_mutex.lock()
	var out := String(_cars.get(car_hash, ""))
	_mutex.unlock()
	return out


## The file's bytes (safe on any thread), or empty if it isn't here or doesn't hash right.
func read(h: String) -> PackedByteArray:
	_mutex.lock()
	var at: Array = _files.get(h, [])
	var bytes := PackedByteArray()
	if at.is_empty():
		pass
	elif at[1] == "":
		bytes = FileAccess.get_file_as_bytes(at[0])
	else:
		var source: PackageSource = _sources.get(at[0])
		if source == null:
			source = PackageSource.open(at[0], PackageLoader.DEFAULT_LIMITS)
			_sources[at[0]] = source
		if not source.error:
			bytes = source.read(at[1])
			if bytes.is_empty() and FileAccess.file_exists(String(at[0]).path_join(at[1])):
				bytes = FileAccess.get_file_as_bytes(String(at[0]).path_join(at[1])) # a cached car's new file
	_mutex.unlock()
	if bytes.is_empty() or "sha256:" + PlatformLoader.sha256_hex(bytes) != h:
		return PackedByteArray()
	return bytes


## A package's hash ("sha256:" + its manifest's), as PackageLoader computes it; "" if unreadable.
static func package_hash(path: String) -> String:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	if source.error or not source.has("manifest.json"):
		source.close()
		return ""
	var h := "sha256:" + PlatformLoader.sha256_hex(source.read("manifest.json"))
	source.close()
	return h


## Personal-use packages (the FM4 converter's) never leave this machine (Requirements §6):
## they can't be picked online, aren't AI cars and aren't sent. Dev: --share-personal lets a
## server on this PC send them to its own bots (tools/net_check.py --fresh).
const PERSONAL := "personal-use-only"


static func shareable(manifest: Dictionary) -> bool:
	return String(manifest.get("license", "")) != PERSONAL or Game.dev.has("share-personal")


## Every package available here (garage and built-ins), by car hash. Reads only manifests.
static func local_cars() -> Dictionary:
	var out := {}
	for path in PackageLoader.list_available():
		var h := package_hash(path)
		if h:
			out[h] = path
	return out
