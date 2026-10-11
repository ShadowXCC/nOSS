class_name Bindings
extends RefCounted
## Input actions, presets and binding refs (docs/INPUT.md §1, §7). Each local player reads only
## their own devices, through PlayerInput. Presets (data/input_presets/) give each kind of
## device its default bindings; a profile overrides them per preset.
##
## A ref is one input: {"key": physical keycode}, {"button": index} or {"axis": index, "dir": ±1}
## (one direction of an axis, 0..1). Preset files may name keys ("W"), gamepad buttons ("a")
## and axes ("left_x"); refs are numbers once loaded.

const PRESET_DIR := "res://data/input_presets/"
const ACTIONS := {
	"steer_left": { "name": "Steer left" },
	"steer_right": { "name": "Steer right" },
	"throttle": { "name": "Throttle" },
	"brake": { "name": "Brake" },
	"handbrake": { "name": "Handbrake" },
	"shift_up": { "name": "Shift up" },
	"shift_down": { "name": "Shift down" },
	"camera_next": { "name": "Camera" },
	"look_back": { "name": "Look back" },
	"reset_car": { "name": "Reset car" },
	"hotswap_menu": { "name": "Change car" },
	"pause": { "name": "Pause" },
	"menu_up": { "name": "Menu up", "repeat": true },
	"menu_down": { "name": "Menu down", "repeat": true },
	"menu_left": { "name": "Menu left", "repeat": true },
	"menu_right": { "name": "Menu right", "repeat": true },
	"menu_confirm": { "name": "Menu confirm" },
	"menu_cancel": { "name": "Menu back" },
}
const DRIVING := ["steer_left", "steer_right", "throttle", "brake", "handbrake", "shift_up", "shift_down", "camera_next", "look_back", "reset_car", "hotswap_menu", "pause"]
const MENU := ["menu_up", "menu_down", "menu_left", "menu_right", "menu_confirm", "menu_cancel"]
## Hold actions that can be toggles instead (docs/ACCESSIBILITY.md §5.1).
const HOLD := ["throttle", "brake", "handbrake", "look_back"]
## What a player's menu gets, as InputEventAction: navigation, plus pause and change car,
## which close the menus they open.
const MENU_EVENTS := {
	"menu_up": "ui_up", "menu_down": "ui_down", "menu_left": "ui_left", "menu_right": "ui_right",
	"menu_confirm": "ui_accept", "menu_cancel": "ui_cancel", "pause": "pause", "hotswap_menu": "hotswap_menu",
}
const DEFAULT_PRESET := { "keyboard": "kb_full", "gamepad": "pad_standard", "sim": "sim_generic" }

const PAD_BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "guide": JOY_BUTTON_GUIDE, "start": JOY_BUTTON_START,
	"left_stick": JOY_BUTTON_LEFT_STICK, "right_stick": JOY_BUTTON_RIGHT_STICK,
	"left_shoulder": JOY_BUTTON_LEFT_SHOULDER, "right_shoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
const PAD_AXES := {
	"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y, "right_x": JOY_AXIS_RIGHT_X,
	"right_y": JOY_AXIS_RIGHT_Y, "trigger_left": JOY_AXIS_TRIGGER_LEFT, "trigger_right": JOY_AXIS_TRIGGER_RIGHT,
}
const PAD_BUTTON_LABELS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const PAD_AXIS_LABELS := {
	JOY_AXIS_LEFT_X: ["Left stick left", "Left stick right"], JOY_AXIS_LEFT_Y: ["Left stick up", "Left stick down"],
	JOY_AXIS_RIGHT_X: ["Right stick left", "Right stick right"], JOY_AXIS_RIGHT_Y: ["Right stick up", "Right stick down"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}

static var _presets := {}


## Registers the actions, with no events: devices are read per player, and menus get the
## actions as InputEventAction (which needs the action to exist).
static func apply() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
	# Shared menus (title, results) by controller too: Godot's defaults have no confirm or back
	# button for pads (docs/ACCESSIBILITY.md §5.1: directions, confirm and cancel are enough).
	for pair: Array in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var e := InputEventJoypadButton.new()
		e.device = -1
		e.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], e):
			InputMap.action_add_event(pair[0], e)


## A preset by id, refs normalized: {id, name, device, bindings: {action: [ref]}, match, wheel}.
## Empty if there's no such preset.
static func preset(id: String) -> Dictionary:
	if _presets.is_empty():
		_load_presets()
	return _presets.get(id, {})


## [id, name] of the presets for a kind of device, without device-matched ones.
static func presets_for(device: String) -> Array:
	if _presets.is_empty():
		_load_presets()
	var out := []
	for id: String in _presets:
		var p: Dictionary = _presets[id]
		if p.device == device and p.get("match", []).is_empty():
			out.append([id, p.name])
	return out


## The preset made for this device (by USB ids), else the default for its kind.
static func preset_for_device(device: String, vendor: int, product: int) -> String:
	if _presets.is_empty():
		_load_presets()
	for id: String in _presets:
		var p: Dictionary = _presets[id]
		if p.device != device:
			continue
		for m: Dictionary in p.get("match", []):
			if int(m.vendor) == vendor and int(m.product) == product:
				return id
	return DEFAULT_PRESET.get(device, "")


## The preset's bindings with a profile's overrides ({action: [ref]}) on top.
static func effective(preset_id: String, overrides := {}) -> Dictionary:
	var out: Dictionary = preset(preset_id).get("bindings", {}).duplicate(true)
	for action: String in overrides:
		if ACTIONS.has(action) and overrides[action] is Array:
			out[action] = overrides[action].map(func(r: Variant) -> Dictionary: return normalize_ref(r)).filter(func(r: Dictionary) -> bool: return not r.is_empty())
	return out


## Physical keycodes a keyboard preset binds (for the shared keyboard halves).
static func keys_of(preset_id: String) -> Array:
	var keys := []
	for refs: Array in preset(preset_id).get("bindings", {}).values():
		for r: Dictionary in refs:
			if r.has("key") and r.key not in keys:
				keys.append(r.key)
	return keys


## A ref with names turned into numbers; {} if it isn't one.
static func normalize_ref(r: Variant) -> Dictionary:
	if not r is Dictionary:
		return {}
	if r.has("key"):
		var k: int = OS.find_keycode_from_string(r.key) if r.key is String else int(r.key)
		return { "key": k } if k != KEY_NONE else {}
	if r.has("button"):
		return { "button": int(PAD_BUTTONS.get(r.button, -1)) if r.button is String else int(r.button) }
	if r.has("axis"):
		var a: int = int(PAD_AXES.get(r.axis, -1)) if r.axis is String else int(r.axis)
		return { "axis": a, "dir": 1 if float(r.get("dir", 1)) >= 0.0 else -1 }
	return {}


## Short label for a ref on a kind of device: "W", "RB", "Left stick left", "Button 4".
static func ref_label(r: Dictionary, device: String) -> String:
	if r.has("key"):
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(r.key))
	if r.has("button"):
		return PAD_BUTTON_LABELS.get(r.button, "Button %d" % r.button) if device == "gamepad" else "Button %d" % (r.button + 1)
	if r.has("axis"):
		if device == "gamepad" and PAD_AXIS_LABELS.has(r.axis):
			return PAD_AXIS_LABELS[r.axis][0 if r.dir < 0 else 1]
		return "Axis %d %s" % [r.axis + 1, "−" if r.dir < 0 else "+"]
	return "-"


static func refs_label(refs: Array, device: String) -> String:
	var names := refs.map(func(r: Dictionary) -> String: return ref_label(r, device))
	return " / ".join(names) if not names.is_empty() else "-"


static func _load_presets() -> void:
	for file in DirAccess.get_files_at(PRESET_DIR):
		if not file.ends_with(".json"):
			continue
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESET_DIR + file))
		if not p is Dictionary or p.get("schema") != "noss.input_preset/1":
			push_warning("Input preset skipped: " + file)
			continue
		var bindings := {}
		for action: String in p.get("bindings", {}):
			bindings[action] = p.bindings[action].map(func(r: Variant) -> Dictionary: return normalize_ref(r)).filter(func(r: Dictionary) -> bool: return not r.is_empty())
		p.bindings = bindings
		_presets[p.id] = p
