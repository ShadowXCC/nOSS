class_name PlayerProfile
extends RefCounted
## One player's profile, user://profiles/<id>.json: everything that follows a player rather
## than the machine (docs/ACCESSIBILITY.md §1, ACC-01). Name, input presets and bindings,
## hold/toggle, assists, cameras, comfort and accessibility options, wheel calibration, last car.

signal changed

const VERSION := 2
const DEFAULTS := {
	"version": VERSION,
	"name": "Player 1",
	"input": {
		# Preset per device kind (data/input_presets/), and the player's overrides per preset:
		# {preset_id: {action: [ref, ...]}}.
		"presets": { "keyboard": "kb_full", "gamepad": "pad_standard" },
		"bindings": {},
		# Hold actions this player toggles instead (docs/ACCESSIBILITY.md §5.1).
		"toggles": [],
		# Menu navigation repeat: first repeat after `menu_delay` s, then `menu_rate` per s.
		"menu_delay": 0.45,
		"menu_rate": 10.0,
	},
	"assists": { "abs": true, "tcs": true, "stability": false, "auto_gearbox": true, "steer_aid": true },
	"camera": "chase_near",
	"camera_shake": 0.5,
	"head_movement": 0.5,
	"speed_fov": true,
	"horizon_lock": false,
	"pad_deadzone": 0.08,
	"pad_linearity": 1.6,
	"hud_scale": 1.0,
	"text_scale": 1.0,
	"high_contrast": false,
	"font": "retro",
	"brightness": 1.0,
	# Vision, hearing and pacing (docs/ACCESSIBILITY.md §2-§6).
	"palette": "default",
	"palette_custom": {},
	"hud_preset": "full",
	"hud_hidden": [],
	"reduce_flashing": false,
	"narration": "off",
	"narration_rate": 1.0,
	"spotter": "off",
	"captions": true,
	"shift_light": true,
	"slip_indicator": false,
	"sound_arrows": false,
	"game_speed": 1.0,
	# Wheel and pedals (WheelInput config). Each axis may name the device it's on ("guid").
	"wheel": {},
	"last_car": "",
	"last_platform": "official.track.gt",
}
## Dicts whose known keys are merged one by one; other dicts are taken whole.
const NESTED := ["input", "assists", "presets"]

## Where profiles live. Tests point this elsewhere.
static var dir := "user://profiles/"
## Dev (--no-save): nothing is written, for checks that walk the menus.
static var read_only := false

var id := ""
var data := {}


static func create(profile_id: String, saved: Variant = null) -> PlayerProfile:
	var p := PlayerProfile.new()
	p.id = profile_id
	p.data = merged(saved)
	# A new profile starts with Reduce flashing if the OS asks for less animation.
	if not saved is Dictionary or not saved.has("reduce_flashing"):
		p.data.reduce_flashing = DisplayServer.get_name() != "headless" and DisplayServer.accessibility_should_reduce_animation()
	return p


## Reads user://profiles/<id>.json, or defaults if there's none.
static func load_id(profile_id: String) -> PlayerProfile:
	var path := path_for(profile_id)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return create(profile_id, saved)


static func path_for(profile_id: String) -> String:
	return dir + profile_id + ".json"


## Ids of the saved profiles, sorted.
static func saved_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return ids
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids


func save() -> void:
	if read_only:
		changed.emit()
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path_for(id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  ", true) + "\n")
	changed.emit()


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save()


func set_assist(assist: String, on: bool) -> void:
	data.assists[assist] = on
	save()


func display_name() -> String:
	return String(data.get("name", id))


## Defaults overlaid with a saved profile, after migrating it. Unknown keys and keys of the
## wrong type are dropped.
static func merged(saved: Variant) -> Dictionary:
	var p: Dictionary = DEFAULTS.duplicate(true)
	if saved is Dictionary:
		_overlay(p, migrate(saved))
	p.version = VERSION
	for key: String in DEFAULTS.assists:
		p.assists[key] = bool(p.assists.get(key, DEFAULTS.assists[key]))
	return p


## v1 (M1/M2): keyboard overrides were {action: [keycode]} under "bindings".
static func migrate(saved: Dictionary) -> Dictionary:
	var s := saved.duplicate(true)
	if int(s.get("version", 1)) < 2:
		var old: Variant = s.get("bindings", {})
		s.erase("bindings")
		if old is Dictionary and not old.is_empty():
			var kb := {}
			for action: String in old:
				if old[action] is Array:
					kb[action] = old[action].map(func(k: Variant) -> Dictionary: return { "key": int(k) })
			s.input = { "bindings": { "kb_full": kb } }
		s.version = VERSION
	return s


static func _overlay(base: Dictionary, saved: Dictionary) -> void:
	for key: String in saved:
		if not base.has(key) or not _same_kind(base[key], saved[key]):
			continue
		if base[key] is Dictionary and key in NESTED:
			_overlay(base[key], saved[key])
		else:
			base[key] = saved[key]


static func _same_kind(a: Variant, b: Variant) -> bool:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numeric and typeof(b) in numeric:
		return true
	return typeof(a) == typeof(b)
