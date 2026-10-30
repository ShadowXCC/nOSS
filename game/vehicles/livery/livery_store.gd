class_name LiveryStore
extends RefCounted
## Where liveries are kept (docs/VEHICLE_PACKAGE.md §12): outside the car's package, so editing
## one never changes the car's hash. A garage car's are in user://liveries/<car id>/, one
## <livery id>.json each, with index.json naming the worn one ("" for plain paint) and their order.
## Built-in cars wear one stock livery each (content/liveries/<car>.json), with no base paint and
## colours linked to the car's own, so presets and AI paint show through.

const INDEX := "index.json"
const BUILTIN_DIR := "res://content/liveries/"

static var root := "user://liveries/"
static var _builtin_ids := {} # manifest id -> built-in folder name
static var _builtin_cache := {} # folder name -> livery


## A car's liveries, in their order.
static func list(car_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not LiveryData.valid_id(car_id):
		return out
	var dir := _dir(car_id)
	var order: Array = index(car_id).order
	var found := {}
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if f.ends_with(".json") and f != INDEX:
			var l := LiveryData.parse(FileAccess.get_file_as_bytes(dir + f))
			if not l.is_empty() and l.id == f.get_basename():
				found[l.id] = l
	for id: String in order:
		if found.has(id):
			out.append(found[id])
			found.erase(id)
	var rest := found.keys()
	rest.sort()
	for id: String in rest:
		out.append(found[id])
	return out.slice(0, LiveryData.MAX_PER_CAR)


## {worn: livery id or "", order: [ids]}.
static func index(car_id: String) -> Dictionary:
	var path := _dir(car_id) + INDEX
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if LiveryData.valid_id(car_id) and FileAccess.file_exists(path) else null
	var out := { "worn": "", "order": [] }
	if data is Dictionary:
		if LiveryData.valid_id(data.get("worn")):
			out.worn = data.worn
		if data.get("order") is Array:
			out.order = (data.order as Array).filter(func(id: Variant) -> bool: return LiveryData.valid_id(id))
	return out


## The livery the car wears, or {} for plain paint.
static func worn_stored(car_id: String) -> Dictionary:
	var id := String(index(car_id).worn)
	if id.is_empty():
		return {}
	for l in list(car_id):
		if l.id == id:
			return l
	return {}


## Writes a car's liveries (cleaned) and which it wears; files of liveries no longer listed go.
## Returns an error or "".
static func save_car(car_id: String, liveries: Array, worn: String) -> String:
	if not LiveryData.valid_id(car_id):
		return "Bad car id"
	var dir := _dir(car_id)
	if liveries.is_empty():
		delete_car(car_id)
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var keep := {}
	var order := []
	for l: Dictionary in liveries.slice(0, LiveryData.MAX_PER_CAR):
		var c := LiveryData.clean(l)
		if c.is_empty() or keep.has(c.id):
			continue
		keep[c.id + ".json"] = true
		order.append(c.id)
		var err := _write(dir + c.id + ".json", LiveryData.to_bytes(c))
		if err:
			return err
	for f in DirAccess.get_files_at(dir):
		if f != INDEX and not keep.has(f):
			DirAccess.remove_absolute(dir + f)
	var data := { "worn": worn if worn in order else "", "order": order }
	return _write(dir + INDEX, JSON.stringify(data, "  ", true).to_utf8_buffer())


## Gives car `to_id` copies of `from_id`'s liveries (a duplicated car), worn one included.
static func copy_car(from_id: String, to_id: String) -> String:
	var liveries := list(from_id)
	if liveries.is_empty() or not LiveryData.valid_id(to_id):
		return ""
	return save_car(to_id, liveries, String(index(from_id).worn))


static func delete_car(car_id: String) -> void:
	if not LiveryData.valid_id(car_id):
		return
	var dir := _dir(car_id)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)


## True if `car_id` is one of the built-in cars.
static func is_builtin(car_id: String) -> bool:
	return _builtins().has(car_id)


## A built-in car's stock livery, or {} (not a built-in, or none made for it).
static func builtin(car_id: String) -> Dictionary:
	var folder := String(_builtins().get(car_id, ""))
	if folder.is_empty():
		return {}
	if not _builtin_cache.has(folder):
		var path := BUILTIN_DIR + folder + ".json"
		_builtin_cache[folder] = LiveryData.parse(FileAccess.get_file_as_bytes(path)) if FileAccess.file_exists(path) else {}
	return _builtin_cache[folder]


## What a player's car wears: a built-in's stock livery, or the worn one from the store ({} for
## plain paint). During a test drive from the Fitting Bay, the draft's.
static func worn(pkg: VehiclePackage) -> Dictionary:
	var car_id := String(pkg.manifest.get("id", ""))
	if is_builtin(car_id):
		return builtin(car_id)
	var draft: Variant = Game.bay_draft
	if draft is FittingDraft and pkg.path.trim_suffix("/") == (draft as FittingDraft).draft_dir().trim_suffix("/"):
		return (draft as FittingDraft).worn_livery()
	return worn_stored(car_id)


## A livery for an AI driver in this car: one of its saved liveries at random, or a built-in's
## stock livery; {} for none (the AI's random paint, D128).
static func pick_for_ai(pkg: VehiclePackage, rng: RandomNumberGenerator = null) -> Dictionary:
	var car_id := String(pkg.manifest.get("id", ""))
	if is_builtin(car_id):
		return builtin(car_id)
	var saved := list(car_id)
	if saved.is_empty():
		return {}
	return saved[(rng.randi() if rng else randi()) % saved.size()]


## The bytes sent online for a livery, or empty when it's too big to send.
static func net_blob(livery: Dictionary) -> PackedByteArray:
	var bytes := LiveryData.to_bytes(LiveryData.clean(livery))
	return bytes if bytes.size() <= LiveryData.MAX_NET_BYTES else PackedByteArray()


static func _builtins() -> Dictionary:
	if _builtin_ids.is_empty():
		for folder in DirAccess.get_directories_at(PackageLoader.OFFICIAL_CARS_DIR):
			var id := String(PackageLoader.read_manifest(PackageLoader.OFFICIAL_CARS_DIR + folder).get("id", ""))
			if id:
				_builtin_ids[id] = folder
	return _builtin_ids


static func _dir(car_id: String) -> String:
	return root.path_join(car_id) + "/"


static func _write(path: String, bytes: PackedByteArray) -> String:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Can't write " + path.get_file()
	f.store_buffer(bytes)
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return "Can't write " + path.get_file()
	return ""
