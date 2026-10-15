class_name AssistRules
extends RefCounted
## Which assists a player may use here, and which are on (docs/PHYSICS.md §8, PLATFORMS.md §3,
## ACCESSIBILITY.md §5.2, INP-07, ACC-07). An assist is allowed if the platform and the mode
## both allow it (servers narrow further in M5). Steer aid, auto gearbox and auto clutch can be
## "auto": on with a keyboard or controller, off with a wheel (INPUT.md §8).

## Every assist, in menu order.
const ALL := ["abs", "tcs", "stability", "auto_gearbox", "auto_clutch", "steer_aid", "racing_line",
	"auto_throttle", "brake_assist", "steering_assist", "autodrive", "item_assist"]
## Assists that follow the AI line (access assists, ACC-07).
const ACCESS := ["auto_throttle", "brake_assist", "steering_assist", "autodrive"]
## Settings that can be Auto (by device), On or Off.
const BY_DEVICE := ["auto_gearbox", "auto_clutch", "steer_aid"]


## Assists allowed for `platform` in `mode` ({} = any mode).
static func allowed(platform: Dictionary, mode: Dictionary) -> Array:
	var from_platform: Array = platform.get("assists_allowed", [])
	if mode.is_empty():
		return from_platform.duplicate()
	var from_mode: Array = mode.get("assists", {}).get("allowed", ALL)
	return from_platform.filter(func(a: String) -> bool: return a in from_mode)


## What's on for a player: {assist: bool, brake_assist and steering_assist: strength 0-1}.
## `wheel`: they drive with a wheel; `clutch_pedal`: they have one set up.
static func effective(profile: PlayerProfile, platform: Dictionary, mode: Dictionary, wheel: bool, clutch_pedal: bool) -> Dictionary:
	var ok := allowed(platform, mode)
	var a: Dictionary = profile.data.assists if profile else PlayerProfile.DEFAULTS.assists
	var on := {}
	for key: String in ["abs", "tcs", "stability", "racing_line", "auto_throttle", "autodrive", "item_assist"]:
		on[key] = bool(a.get(key, false)) and key in ok
	on.auto_gearbox = _by_device(a.get("auto_gearbox", "auto"), not wheel) and "auto_gearbox" in ok
	# Without a clutch pedal (or a button for it) the car can't be driven any other way.
	on.auto_clutch = (_by_device(a.get("auto_clutch", "auto"), not clutch_pedal) and "auto_clutch" in ok) or not clutch_pedal
	on.steer_aid = _by_device(a.get("steer_aid", "auto"), not wheel) and "steer_aid" in ok
	for key: String in ["brake_assist", "steering_assist"]:
		on[key] = clampf(float(a.get(key, 0.0)), 0.0, 1.0) if key in ok else 0.0
	return on


## "on", "off", or "auto" (then `auto_value`).
static func _by_device(setting: Variant, auto_value: bool) -> bool:
	match String(setting):
		"on":
			return true
		"off":
			return false
	return auto_value
