class_name WheelInput
extends RefCounted
## One wheel (plus pedals on the same device) through noss_core (docs/INPUT.md §5-6):
## calibrated axes, the wheel's rotation range with a soft lock at the platform's lock, and
## force feedback from the sim's rack force (docs/PHYSICS.md §11).
##
## Config (profile "wheel"): {guid, name, rotation_deg, steer: {axis, center, invert},
## throttle/brake/clutch: {axis, rest, full}, ffb_gain, ffb_damper, ffb_min, ffb_invert}.

const DEFAULTS := {
	"rotation_deg": 900.0,
	"ffb_gain": 0.7,
	"ffb_damper": 0.12,
	"ffb_min": 0.0,
	"ffb_invert": false,
}
const SOFT_LOCK_RAMP_DEG := 8.0

var device_id := -1
var config := {}
## Lock-to-lock of the platform being driven; the wheel stops here (soft lock).
var platform_lock_deg := 540.0


func configure(id: int, cfg: Dictionary) -> void:
	device_id = id
	config = DEFAULTS.duplicate()
	config.merge(cfg, true)
	if device_id >= 0:
		NossInput.set_ffb_options(device_id, config.ffb_gain, config.ffb_min, config.ffb_invert)


func is_active() -> bool:
	return device_id >= 0 and config.get("steer") is Dictionary


func has_clutch() -> bool:
	return device_id >= 0 and config.get("clutch") is Dictionary and config.clutch.has("axis")


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


## 0..1 between the calibrated rest and full positions (handles inverted pedals).
func pedal(which: String) -> float:
	var p: Variant = config.get(which)
	if device_id < 0 or not p is Dictionary or not p.has("axis"):
		return 0.0
	var rest := float(p.rest)
	var full := float(p.full)
	if is_equal_approx(rest, full):
		return 0.0
	return clampf((NossInput.axis(device_id, int(p.axis)) - rest) / (full - rest), 0.0, 1.0)


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
