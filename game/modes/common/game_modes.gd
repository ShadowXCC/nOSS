class_name GameModes
extends RefCounted
## Gamemodes and the platform classes they offer (data/modes/*.mode.json, docs/PLATFORMS.md §3).

const DIR := "res://data/modes/"
const ORDER := ["track", "kart", "highway", "endless"]
## Built-in cars, tried in order when a platform needs a default.
const DEFAULT_CARS := ["res://content/cars/noss_box", "res://content/cars/noss_open"]


## Valid mode files, in display order.
static func list() -> Array[Dictionary]:
	var modes: Array[Dictionary] = []
	for id: String in ORDER:
		var path := DIR + id + ".mode.json"
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and JsonSchema.validate(data, JsonSchema.load_schema("mode")).is_empty():
			modes.append(data)
		else:
			push_warning("Invalid mode file: " + path)
	return modes


## The platforms a mode offers that load and validate.
static func classes(mode: Dictionary) -> Array[PlatformLoader.Result]:
	var out: Array[PlatformLoader.Result] = []
	for id: String in mode.classes:
		var result := PlatformLoader.load_official(id)
		if result.ok():
			out.append(result)
	return out


## "RWD · 380 kW · 1300 kg"
static func describe(platform: Dictionary) -> String:
	return "%s · %d kW · %d kg" % [String(platform.layout.drive).to_upper(), roundi(peak_power_kw(platform)), roundi(float(platform.mass.kg))]


static func peak_power_kw(platform: Dictionary) -> float:
	var best := 0.0
	for point: Array in platform.engine.torque_curve_nm:
		best = maxf(best, float(point[0]) * float(point[1]) * TAU / 60.0 / 1000.0)
	return best


## The first built-in car that can mount `platform`, or any compatible car.
static func default_car(platform: Dictionary) -> String:
	for path in DEFAULT_CARS + Array(PackageLoader.list_available()):
		if Fitting.compatible(platform, PackageLoader.read_manifest(path).get("family", "")):
			return path
	return DEFAULT_CARS[0]
