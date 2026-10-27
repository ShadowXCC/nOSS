class_name GameModes
extends RefCounted
## Gamemodes and the platform classes they offer (data/modes/*.mode.json, docs/PLATFORMS.md §3).

const DIR := "res://data/modes/"
const ORDER := ["track", "kart", "highway", "endless", "sumo", "drag"]
## Built-in cars, tried in order when a platform needs a default.
const DEFAULT_CARS := ["res://content/cars/noss_box", "res://content/cars/noss_open"]
## The kart_arcade layer's numbers (docs/PHYSICS.md §9, D130-D133); a mode's "arcade" block
## overrides them key by key. The native layer reads the physics; the game reads steer_aid,
## bounce, slipstream and tow.
const ARCADE_DEFAULTS := {
	"grip": 1.25,
	"steer_aid": { "ref_speed": 20.0, "counter": 1.5 },
	"drift": { "min_speed": 8.0, "min_steer": 0.3, "turn_g": [0.15, 1.0], "slip": [0.25, 0.45], "side_grip": 0.35, "tire_slip": 0.3,
		"wheel_steer": 0.3, "yaw_accel": 12.0, "hop": 0.8, "exit_s": 0.4, "tiers_s": [0.6, 1.2, 2.0], "boost_s": [0.5, 0.9, 1.4] },
	"boost": { "accel": 6.0, "cap": 1.25, "pad_s": 0.8 },
	"air": { "pitch": 3.0, "roll": 3.0, "yaw": 2.0, "trick_window_s": 0.35, "trick_boost_s": 0.6 },
	"stick": { "min_speed": 7.0, "hold_s": 0.25 },
	"right_after_s": 1.5,
	"bounce": { "wall": 0.6, "kart": 0.3, "min_dv": 1.0 },
	"land": { "min_fall": 0.0, "rebound": 2.0, "keep": 1.0, "settle_s": 0.0 }, # off (sumo's, D218)
	"spin": { "s": 1.2, "grip": 0.35, "yaw_rate": 7.0, "brake": 10.0 },
	"slow": { "power": 0.0 },
	"slipstream": { "range_m": 30.0, "half_width_m": 1.5, "drag_cut": 0.3 },
	"tow": { "s": 1.5, "speed": 0.6 },
}


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


## The mode offering `platform_id` (its rules: tuning, assists), or {}.
static func mode_for(platform_id: String) -> Dictionary:
	for mode in list():
		if platform_id in mode.get("classes", []):
			return mode
	return {}


## The classes a kart racer may pick in a session of class `platform_id` (D149): its mode's, if
## that's a kart mode; else none.
static func kart_classes(platform_id: String) -> Array:
	var mode := mode_for(platform_id)
	return Array(mode.get("classes", [])) if mode.get("physics_layer", "none") == "kart_arcade" else []


## The mode's kart_arcade numbers with every default filled in, or {} for a mode without the
## layer. (Mode files are checked against their schema, so the numbers are in range.)
static func arcade(mode: Dictionary) -> Dictionary:
	if mode.get("physics_layer", "none") != "kart_arcade":
		return {}
	var out: Dictionary = ARCADE_DEFAULTS.duplicate(true)
	_merge(out, mode.get("arcade", {}))
	return out


static func _merge(into: Dictionary, from: Dictionary) -> void:
	for key: String in from:
		if into.get(key) is Dictionary and from[key] is Dictionary:
			_merge(into[key], from[key])
		else:
			into[key] = from[key]


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


## The platform's mode's own default car if it can mount it, else the first built-in car that
## can, else any compatible car.
static func default_car(platform: Dictionary) -> String:
	var own: String = mode_for(String(platform.get("id", ""))).get("default_car", "")
	for path in ([own] if own else []) + DEFAULT_CARS + Array(PackageLoader.list_available()):
		if Fitting.compatible(platform, PackageLoader.read_manifest(path).get("family", "")):
			return path
	return DEFAULT_CARS[0]
