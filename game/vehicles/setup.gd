class_name Setup
extends RefCounted
## A car setup (PLT-04, docs/PLATFORMS.md §3): changes to the values a platform lets players
## tune, narrowed by the mode (servers narrow further in M5). Saved as
## user://setups/<platform>/<track>.json with only the changes from the defaults; values are
## clamped to their ranges and snapped to their steps when loaded, so a shared or edited file
## can never go outside what the platform allows. Gear ratios stay in order (1st the shortest).

const SCHEMA := "noss.setup/1"
## Where setups are saved (tests point it elsewhere with Settings.use_folder).
static var dir := "user://setups/"
## Gears keep at least this much between neighbouring ratios.
const GEAR_GAP := 0.05

## The platform's own values (the defaults).
var platform := {}
## path -> {min, max, step, mode?}: what may be tuned here.
var allowed := {}
## path -> value (float, or Array of floats for per-gear ratios). Only changed values.
var values := {}


## The tunable values a mode allows for a platform: platform `tunable` ∩ mode `tuning.allow`.
static func allowed_for(p: Dictionary, mode: Dictionary) -> Dictionary:
	var tunable: Dictionary = p.get("tunable", {})
	var allow: Array = mode.get("tuning", {}).get("allow", ["*"]) if not mode.is_empty() else ["*"]
	var out := {}
	for path: String in tunable:
		if "*" in allow or path in allow:
			out[path] = tunable[path]
	return out


static func create(p: Dictionary, mode: Dictionary) -> Setup:
	var s := Setup.new()
	s.platform = p
	s.allowed = allowed_for(p, mode)
	return s


## Paths in a sensible menu order: gearing, brakes, suspension, aero, differential.
func paths() -> PackedStringArray:
	var order := ["gearbox", "brakes", "suspension", "aero", "differential"]
	var out := PackedStringArray(allowed.keys())
	out.sort()
	var ranked := Array(out)
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var ia := order.find(a.get_slice(".", 0))
		var ib := order.find(b.get_slice(".", 0))
		return ia < ib if ia != ib else a < b)
	return PackedStringArray(ranked)


func is_per_gear(path: String) -> bool:
	return String(allowed.get(path, {}).get("mode", "")) == "per_gear"


func default_value(path: String) -> Variant:
	return Setup.read(platform, path)


func get_value(path: String) -> Variant:
	if values.has(path):
		return values[path]
	var v: Variant = default_value(path)
	return v.duplicate() if v is Array else v


## Sets a value, clamped and snapped; back at the default it's dropped from the changes.
func set_value(path: String, value: float) -> void:
	if not allowed.has(path) or is_per_gear(path):
		return
	var v := _fit(path, value)
	if is_equal_approx(v, float(default_value(path))):
		values.erase(path)
	else:
		values[path] = v


## Sets one gear's ratio (0 = 1st), kept between its neighbours.
func set_gear(path: String, gear: int, value: float) -> void:
	if not allowed.has(path) or not is_per_gear(path):
		return
	var ratios: Array = get_value(path)
	if gear < 0 or gear >= ratios.size():
		return
	var v := _fit(path, value)
	if gear > 0:
		v = minf(v, float(ratios[gear - 1]) - GEAR_GAP)
	if gear + 1 < ratios.size():
		v = maxf(v, float(ratios[gear + 1]) + GEAR_GAP)
	ratios[gear] = snappedf(v, float(allowed[path].step))
	if Setup._same(ratios, default_value(path)):
		values.erase(path)
	else:
		values[path] = ratios


func reset() -> void:
	values.clear()


func is_default() -> bool:
	return values.is_empty()


## The platform with this setup's changes, as the sim reads it.
func apply(p: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	for path: String in values:
		Setup.write(out, path, values[path] if not values[path] is Array else values[path].duplicate())
	return out


func to_dict(track_id: String) -> Dictionary:
	return { "schema": SCHEMA, "platform": platform.get("id", ""), "track": track_id, "values": values.duplicate(true) }


## Takes the values from a saved setup: unknown paths, wrong types and other platforms' files
## are ignored; numbers are clamped and snapped.
func load_dict(d: Dictionary) -> void:
	values.clear()
	if d.get("schema") != SCHEMA or d.get("platform") != platform.get("id"):
		return
	var saved: Variant = d.get("values")
	if not saved is Dictionary:
		return
	for path: String in saved:
		if not allowed.has(path):
			continue
		var v: Variant = saved[path]
		if is_per_gear(path):
			var defaults: Array = default_value(path)
			if v is Array and v.size() == defaults.size():
				values[path] = defaults.duplicate()
				for i in range(v.size() - 1, -1, -1): # top gear first, so each keeps below the last
					if typeof(v[i]) in [TYPE_INT, TYPE_FLOAT]:
						set_gear(path, i, float(v[i]))
				if values.has(path) and Setup._same(values[path], defaults):
					values.erase(path)
		elif typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			set_value(path, float(v))


static func path_for(platform_id: String, track_id: String) -> String:
	return dir.path_join(platform_id).path_join(track_id + ".json")


func save(track_id: String) -> Error:
	var file := Setup.path_for(platform.get("id", ""), track_id)
	if is_default():
		if FileAccess.file_exists(file):
			return DirAccess.remove_absolute(file)
		return OK
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(track_id), "  "))
	return OK


## The saved setup for this platform and track, or the defaults.
static func load_for(p: Dictionary, mode: Dictionary, track_id: String) -> Setup:
	var s := Setup.create(p, mode)
	var file := Setup.path_for(p.get("id", ""), track_id)
	if FileAccess.file_exists(file):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if data is Dictionary:
			s.load_dict(data)
	return s


static func read(d: Dictionary, path: String) -> Variant:
	var node: Variant = d
	for key in path.split("."):
		if not node is Dictionary or not node.has(key):
			return null
		node = node[key]
	return node


static func write(d: Dictionary, path: String, value: Variant) -> void:
	var keys := path.split(".")
	var node: Dictionary = d
	for i in keys.size() - 1:
		if not node.get(keys[i]) is Dictionary:
			return
		node = node[keys[i]]
	if node.has(keys[-1]):
		node[keys[-1]] = value


static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


func _fit(path: String, value: float) -> float:
	var r: Dictionary = allowed[path]
	var step := float(r.step)
	var lo := float(r.min)
	var v := clampf(value, lo, float(r.max))
	return clampf(lo + roundf((v - lo) / step) * step, lo, float(r.max))
