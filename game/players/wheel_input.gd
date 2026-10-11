class_name WheelInput
extends RefCounted
## A player's wheel and pedals through noss_core (docs/INPUT.md §5-6): calibrated axes, the
## wheel's rotation range with a soft lock at the platform's lock, and force feedback from the
## sim's rack force (docs/PHYSICS.md §11). Each axis can be on any of the player's sim devices
## (a wheel plus separate pedals); force feedback goes to the steering device.
##
## Config (profile "wheel"): {guid, name, rotation_deg, steer: {axis, center, invert, guid?},
## throttle/brake/clutch: {axis, rest, full, guid?}, ffb_gain, ffb_damper, ffb_min, ffb_invert}.
## An axis without its own guid is on the device named by the top-level guid.

const DEFAULTS := {
	"rotation_deg": 900.0,
	"ffb_gain": 0.7,
	"ffb_damper": 0.12,
	"ffb_min": 0.0,
	"ffb_invert": false,
}
const SOFT_LOCK_RAMP_DEG := 8.0

## The steering device (gets force feedback), -1 without one.
var device_id := -1
var config := {}
## Lock-to-lock of the platform being driven; the wheel stops here (soft lock).
var platform_lock_deg := 540.0
var _ids := {} # guid -> SDL id, for the player's sim devices


## `devices`: the player's sim devices (Devices.list() entries). With no saved calibration for
## them, the first wheel gets its device preset's calibration, or steering on axis 0.
func configure(devices: Array, cfg: Dictionary) -> void:
	_ids.clear()
	var first_wheel := {}
	for d: Dictionary in devices:
		if d.kind == "sim":
			_ids[d.guid] = d.id
			if d.wheel and first_wheel.is_empty():
				first_wheel = d
	config = DEFAULTS.duplicate(true)
	config.merge(cfg.duplicate(true), true)
	if not _ids.has(String(config.get("guid", ""))) and not first_wheel.is_empty():
		config = DEFAULTS.duplicate(true)
		config.guid = first_wheel.guid
		config.name = first_wheel.name
		config.steer = { "axis": 0, "center": 0.0 }
		config.merge(Bindings.preset(String(first_wheel.get("preset", ""))).get("wheel", {}).duplicate(true), true)
	device_id = device_for("steer")
	if device_id >= 0:
		NossInput.set_ffb_options(device_id, config.ffb_gain, config.ffb_min, config.ffb_invert)


## SDL id of the device an axis is on, -1 if that device isn't the player's.
func device_for(role: String) -> int:
	var c: Variant = config.get(role)
	var guid := String(c.get("guid", config.get("guid", ""))) if c is Dictionary else String(config.get("guid", ""))
	return int(_ids.get(guid, -1))


func is_active() -> bool:
	return device_id >= 0 and config.get("steer") is Dictionary


func has_clutch() -> bool:
	return config.get("clutch") is Dictionary and config.clutch.has("axis") and device_for("clutch") >= 0


## Wheel angle in degrees, + = right.
func angle_deg() -> float:
	var s: Variant = config.get("steer")
	if device_id < 0 or not s is Dictionary:
		return 0.0
	var raw := NossInput.axis(device_id, int(s.axis)) - float(s.get("center", 0.0))
	if s.get("invert", false):
		raw = -raw
	return raw * float(config.rotation_deg) / 2.0


## -1..1 over the platform's lock, + = right.
func steer() -> float:
	return clampf(angle_deg() / (platform_lock_deg / 2.0), -1.0, 1.0)


func throttle() -> float:
	return pedal("throttle")


func brake() -> float:
	return pedal("brake")


func clutch() -> float:
	return pedal("clutch")


## A handbrake lever set up in Wheel setup (any of the player's devices).
func handbrake() -> float:
	return pedal("handbrake")


## 0..1 between the calibrated rest and full positions (handles inverted pedals).
func pedal(which: String) -> float:
	var p: Variant = config.get(which)
	var id := device_for(which)
	if id < 0 or not p is Dictionary or not p.has("axis"):
		return 0.0
	var rest := float(p.rest)
	var full := float(p.full)
	if is_equal_approx(rest, full):
		return 0.0
	return clampf((NossInput.axis(id, int(p.axis)) - rest) / (full - rest), 0.0, 1.0)


## Sends this tick's force: rack force, soft lock at the platform's lock, damper.
## rack: the sim's normalized rack force (+ = pulls left).
func update_ffb(rack: float) -> void:
	if not is_active():
		return
	var force := rack
	var half := platform_lock_deg / 2.0
	var angle := angle_deg()
	if absf(angle) > half:
		var push := clampf((absf(angle) - half) / SOFT_LOCK_RAMP_DEG, 0.0, 1.0)
		force = -signf(angle) * maxf(push, absf(force)) # + angle (right) pushes left
	NossInput.set_ffb(device_id, force, float(config.ffb_damper))


func stop_ffb() -> void:
	if device_id >= 0:
		NossInput.set_ffb(device_id, 0.0, 0.0)
