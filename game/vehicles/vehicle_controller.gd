class_name VehicleController
extends Node
## Turns the local player's devices into vehicle controls (docs/INPUT.md §4-5, INP-01..03):
## keyboard steering smoothing, gamepad deadzones and curves, speed-sensitive steering
## (steer aid), wheel and pedal axes. When devices overlap, the larger value wins.

signal reset_requested
signal camera_next_requested

## Keyboard steering rates, full lock per second, at low and high speed.
const KEY_RATE_SLOW := 5.0
const KEY_RATE_FAST := 1.6
const KEY_RETURN_FACTOR := 1.6
const KEY_COUNTER_FACTOR := 2.2
const AID_REF_SPEED := 28.0 # m/s where steer aid halves the lock
const COUNTER_STEER_GAIN := 0.8

@export var vehicle: Vehicle
var wheel_input: WheelInput # set when a wheel is in use
## Which device steered last: "keyboard", "gamepad" or "wheel". Picks the filters and assists.
var active_device := "keyboard"

var _key_steer := 0.0


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	var speed := absf(vehicle.speed())
	var assists: Dictionary = Settings.profile.assists

	# Keyboard: digital steering with smoothing.
	var key_target := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var rate := lerpf(KEY_RATE_SLOW, KEY_RATE_FAST, clampf(speed / 50.0, 0.0, 1.0))
	if is_zero_approx(key_target):
		rate *= KEY_RETURN_FACTOR
	elif signf(key_target) != signf(_key_steer) and not is_zero_approx(_key_steer):
		rate *= KEY_COUNTER_FACTOR
	_key_steer = move_toward(_key_steer, key_target, rate * delta)
	var key_throttle := Input.get_action_strength("throttle")
	var key_brake := Input.get_action_strength("brake")

	# Gamepad: stick and triggers.
	var pad := Bindings.gamepad
	var pad_steer := 0.0
	var pad_throttle := 0.0
	var pad_brake := 0.0
	if pad >= 0:
		pad_steer = shape_axis(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Settings.profile.pad_deadzone, Settings.profile.pad_linearity)
		pad_throttle = shape_axis(Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT), 0.05, 1.0)
		pad_brake = shape_axis(Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT), 0.05, 1.0)

	# Wheel and pedals (noss_core).
	var wheel_steer := 0.0
	var wheel_throttle := 0.0
	var wheel_brake := 0.0
	var wheel_clutch := 0.0
	if wheel_input and wheel_input.is_active():
		wheel_steer = wheel_input.steer()
		wheel_throttle = wheel_input.throttle()
		wheel_brake = wheel_input.brake()
		wheel_clutch = wheel_input.clutch()

	var steer := _largest([_key_steer, pad_steer, wheel_steer])
	if absf(wheel_steer) > 0.02 and absf(wheel_steer) >= absf(steer) - 0.001:
		active_device = "wheel"
	elif absf(pad_steer) > 0.05 or pad_throttle > 0.05 or pad_brake > 0.05:
		active_device = "gamepad"
	elif not is_zero_approx(key_target) or key_throttle > 0.0 or key_brake > 0.0:
		active_device = "keyboard"

	# Steer aid for keyboard and gamepad: less lock at speed, help to catch slides.
	if assists.get("steer_aid", true) and active_device != "wheel":
		steer *= 1.0 / (1.0 + pow(speed / AID_REF_SPEED, 2.0))
		steer += _counter_steer(speed)
		steer = clampf(steer, -1.0, 1.0)

	vehicle.steer = steer
	vehicle.throttle = maxf(maxf(key_throttle, pad_throttle), wheel_throttle)
	vehicle.brake = maxf(maxf(key_brake, pad_brake), wheel_brake)
	vehicle.handbrake = Input.get_action_strength("handbrake")
	vehicle.clutch = wheel_clutch


func _unhandled_input(event: InputEvent) -> void:
	if vehicle == null or get_tree().paused:
		return
	if event.is_action_pressed("shift_up"):
		vehicle.sim.shift(1)
	elif event.is_action_pressed("shift_down"):
		vehicle.sim.shift(-1)
	elif event.is_action_pressed("reset_car"):
		reset_requested.emit()
	elif event.is_action_pressed("camera_next"):
		camera_next_requested.emit()


## Applies the profile's assists to the sim. Keyboard and gamepad always get auto-clutch.
func apply_assists() -> void:
	if vehicle == null:
		return
	var a: Dictionary = Settings.profile.assists
	var allowed: Array = vehicle.platform.get("assists_allowed", [])
	var has_clutch := wheel_input != null and wheel_input.has_clutch()
	vehicle.sim.set_assists(
		a.get("abs", true) and "abs" in allowed,
		a.get("tcs", true) and "tcs" in allowed,
		a.get("auto_gearbox", true) and "auto_gearbox" in allowed,
		not has_clutch)


## Deadzone, then a power curve (1 = linear), keeping the sign.
static func shape_axis(value: float, deadzone: float, linearity: float) -> float:
	var mag := absf(value)
	if mag <= deadzone:
		return 0.0
	var t := clampf((mag - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	return signf(value) * pow(t, linearity)


static func _largest(values: Array) -> float:
	var best := 0.0
	for v: float in values:
		if absf(v) > absf(best):
			best = v
	return best


## Steers into a slide: the body's slip angle, scaled down at low speed.
func _counter_steer(speed: float) -> float:
	if speed < 4.0:
		return 0.0
	var local_v := vehicle.global_basis.inverse() * vehicle.linear_velocity
	var slip := atan2(local_v.x, absf(local_v.z)) # + = sliding left
	var max_steer := deg_to_rad(float(vehicle.platform.get("steering", {}).get("max_road_angle_deg", 30.0)))
	# Steer toward the velocity: sliding left (rear out right) needs steering left (-input).
	return clampf(-slip * COUNTER_STEER_GAIN / max_steer, -0.5, 0.5) * clampf((speed - 4.0) / 6.0, 0.0, 1.0)
