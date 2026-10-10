extends Node
## Settings (autoload "Settings"). Machine settings live in user://settings.cfg; everything
## that follows a player (bindings, assists, cameras, comfort options) lives in their
## profile, user://profiles/<id>.json (docs/ACCESSIBILITY.md §1, ACC-01).

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const PROFILE_DIR := "user://profiles/"
const PRESETS := ["low", "medium", "high"]

const DEFAULT_PROFILE := {
	"name": "Player 1",
	"bindings": {},
	"assists": { "abs": true, "tcs": true, "auto_gearbox": true, "steer_aid": true },
	"camera": "chase_near",
	"camera_shake": 0.5,
	"head_movement": 0.5,
	"speed_fov": true,
	"horizon_lock": false,
	"pad_deadzone": 0.08,
	"pad_linearity": 1.6,
	"wheel": {},
	"last_car": "",
}

var graphics := "medium"
var units := "metric"
var fullscreen := false
var master_volume := 0.8
var profile := {}
var profile_id := "player1"


func _ready() -> void:
	load_all()
	apply_display()
	Bindings.apply(profile.bindings)


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		graphics = cfg.get_value("graphics", "preset", graphics)
		units = cfg.get_value("game", "units", units)
		fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
		master_volume = cfg.get_value("audio", "master", master_volume)
	if graphics not in PRESETS:
		graphics = "medium"
	profile = DEFAULT_PROFILE.duplicate(true)
	var path := PROFILE_DIR + profile_id + ".json"
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if saved is Dictionary:
		for key: String in saved:
			if profile.has(key) and typeof(profile[key]) == typeof(saved[key]):
				profile[key] = saved[key]
		for key: String in DEFAULT_PROFILE.assists:
			profile.assists[key] = bool(profile.assists.get(key, DEFAULT_PROFILE.assists[key]))
	# JSON numbers come back as floats; key codes must be ints.
	for action: String in profile.bindings.keys():
		profile.bindings[action] = profile.bindings[action].map(func(k: Variant) -> int: return int(k))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", graphics)
	cfg.set_value("game", "units", units)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "master", master_volume)
	cfg.save(SETTINGS_PATH)
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	var f := FileAccess.open(PROFILE_DIR + profile_id + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "  ", true) + "\n")
	changed.emit()


func set_value(key: String, value: Variant) -> void:
	match key:
		"graphics":
			graphics = value
			apply_display()
		"units":
			units = value
		"fullscreen":
			fullscreen = value
			apply_display()
		"master_volume":
			master_volume = value
			apply_display()
		_:
			profile[key] = value
	save()


func set_assist(assist: String, on: bool) -> void:
	profile.assists[assist] = on
	save()


func set_binding(action: String, keys: Array) -> void:
	profile.bindings[action] = keys
	Bindings.apply(profile.bindings)
	save()


func reset_bindings() -> void:
	profile.bindings = {}
	Bindings.apply({})
	save()


## Speed in the player's units, with its label.
func speed_text(mps: float) -> String:
	return "%d" % roundi(absf(mps) * (2.23694 if units == "imperial" else 3.6))


func speed_unit() -> String:
	return "mph" if units == "imperial" else "km/h"


func apply_display() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	match graphics:
		"low":
			viewport.scaling_3d_scale = 0.75
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		"medium":
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_2X
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		"high":
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_4X
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X if graphics == "high" else Viewport.ANISOTROPY_4X
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
