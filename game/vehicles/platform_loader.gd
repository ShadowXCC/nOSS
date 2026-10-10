class_name PlatformLoader
extends RefCounted
## Loads and validates platform files (docs/PLATFORMS.md §2, PLT-02).
## official.* platforms load only from the game's own data/.

const OFFICIAL_DIR := "res://data/platforms/"
const DEFAULTS_DIR := "res://data/platforms/_defaults/"
const USER_DIR := "user://platforms/"
const SUFFIX := ".platform.json"


## Result of a load. `platform` has family defaults merged in; `hash` covers the file bytes.
class Result:
	var platform := {}
	var hash := ""
	var path := ""
	var errors := PackedStringArray()

	func ok() -> bool:
		return errors.is_empty()


## Loads an official platform by id, e.g. "official.track.gt".
static func load_official(id: String) -> Result:
	var parts := id.split(".")
	var path := OFFICIAL_DIR + "/".join(parts.slice(1)) + SUFFIX
	if parts.size() != 3 or parts[0] != "official" or not FileAccess.file_exists(path):
		var missing := Result.new()
		missing.errors.append("Unknown platform: " + id)
		return missing
	var result := load_file(path)
	if result.ok() and result.platform.id != id:
		result.errors.append("File id %s doesn't match %s" % [result.platform.id, id])
	return result


## Paths of every official platform file.
static func list_official() -> PackedStringArray:
	var paths := PackedStringArray()
	for mode_dir in DirAccess.get_directories_at(OFFICIAL_DIR):
		if mode_dir.begins_with("_"):
			continue
		for file in DirAccess.get_files_at(OFFICIAL_DIR + mode_dir):
			if file.ends_with(SUFFIX):
				paths.append(OFFICIAL_DIR + mode_dir + "/" + file)
	return paths


static func load_file(path: String) -> Result:
	var result := Result.new()
	result.path = path
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		result.errors.append("Can't read " + path)
		return result
	result.hash = "sha256:" + sha256_hex(bytes)
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary:
		result.errors.append("Not a JSON object")
		return result
	result.errors = validate(data, path.begins_with(OFFICIAL_DIR))
	if result.ok():
		result.platform = with_defaults(data)
	return result


## Schema plus the rules a schema can't express. Returns errors.
static func validate(data: Dictionary, is_official_source: bool) -> PackedStringArray:
	var errors := JsonSchema.validate(data, JsonSchema.load_schema("platform"))
	if not errors.is_empty():
		return errors
	if String(data.id).begins_with("official.") and not is_official_source:
		errors.append("official.* is reserved")
	for key: String in data.geometry:
		var r: Dictionary = data.geometry[key]
		if r.has("ref") and not (r.min <= r.ref and r.ref <= r.max):
			errors.append("geometry.%s: needs min <= ref <= max" % key)
	for key: String in data.geometry.envelope_m:
		var mm: Array = data.geometry.envelope_m[key]
		if mm[0] > mm[1]:
			errors.append("geometry.envelope_m.%s: min > max" % key)
	var curve: Array = data.engine.torque_curve_nm
	for i in range(1, curve.size()):
		if curve[i][0] <= curve[i - 1][0]:
			errors.append("engine.torque_curve_nm: rpm must ascend")
			break
	var e: Dictionary = data.engine
	if not (e.idle_rpm < e.redline_rpm and e.redline_rpm <= e.limiter_rpm):
		errors.append("engine: needs idle < redline <= limiter")
	var axles: Array = data.layout.axles
	if data.family == "car" and (axles.size() != 2 or axles.any(func(a: Dictionary) -> bool: return a.wheels != 2)):
		errors.append("layout: car needs 2 axles of 2 wheels")
	var driven: Array = axles.map(func(a: Dictionary) -> bool: return a.driven)
	var drive_ok: bool = {
		"fwd": driven == [true, false],
		"rwd": driven == [false, true],
		"awd": driven.all(func(d: bool) -> bool: return d),
	}.get(data.layout.drive, false) if axles.size() == 2 else true
	if not drive_ok:
		errors.append("layout: drive doesn't match driven axles")
	return errors


## Deep-merges the family defaults under the platform's own values.
static func with_defaults(data: Dictionary) -> Dictionary:
	var path: String = DEFAULTS_DIR + String(data.family) + ".json"
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return _merge(defaults if defaults is Dictionary else {}, data)


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: Variant in over:
		if out.get(key) is Dictionary and over[key] is Dictionary:
			out[key] = _merge(out[key], over[key])
		else:
			out[key] = over[key].duplicate(true) if over[key] is Dictionary or over[key] is Array else over[key]
	return out


static func sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
