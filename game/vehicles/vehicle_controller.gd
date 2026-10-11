class_name VehicleController
extends Node
## Turns one player's devices into vehicle controls (docs/INPUT.md §4-5, INP-01..03):
## keyboard steering smoothing, gamepad deadzones and curves (in PlayerInput), speed-sensitive
## steering (steer aid), wheel and pedal axes. When devices overlap, the larger value wins.

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
var input: PlayerInput
## The racer this controls: held on the grid, pace-limited on a rolling start.
var racer: Racer
## The mode's rules (which assists are allowed), from the session.
var mode := {}
## What's on now (AssistRules.effective).
var assists := {}
## Follows the AI line for the access assists (ACC-07); null when none is on.
var _guide: RacingAI
## Which device steered last: "keyboard", "gamepad" or "wheel". Picks the filters and assists.
var active_device := "keyboard"

var _key_steer := 0.0
var _had_wheel := false
var _gear_held := INF # the H-shifter gate held last (INF: none seen yet)
var _clutch_in := false


func _ready() -> void:
	process_physics_priority = -50 # after the RaceField, before the vehicles


func _physics_process(delta: float) -> void:
	if vehicle == null or input == null:
		return
	# Steer aid "auto" and the auto gearbox follow the device; a wheel can come and go.
	if Engine.get_physics_frames() % 60 == 0 and input.wheel.is_active() != _had_wheel:
		_had_wheel = input.wheel.is_active()
		apply_assists()
	var speed := absf(vehicle.speed())

	# Keyboard: digital steering with smoothing.
	var key_target := input.value("steer_right", "keyboard") - input.value("steer_left", "keyboard")
	var rate := lerpf(KEY_RATE_SLOW, KEY_RATE_FAST, clampf(speed / 50.0, 0.0, 1.0))
	if is_zero_approx(key_target):
		rate *= KEY_RETURN_FACTOR
	elif signf(key_target) != signf(_key_steer) and not is_zero_approx(_key_steer):
		rate *= KEY_COUNTER_FACTOR
	_key_steer = move_toward(_key_steer, key_target, rate * delta)

	# Gamepad sticks and sim-device buttons or axes bound to steering.
	var pad_steer := input.value("steer_right", "gamepad") - input.value("steer_left", "gamepad")
	var sim_steer := input.value("steer_right", "sim") - input.value("steer_left", "sim")
	var wheel_steer := input.wheel.steer() if input.wheel.is_active() else 0.0

	var steer := _largest([_key_steer, pad_steer, sim_steer, wheel_steer])
	if absf(wheel_steer) > 0.02 and absf(wheel_steer) >= absf(steer) - 0.001:
		active_device = "wheel"
	elif absf(pad_steer) > 0.05 or input.value("throttle", "gamepad") > 0.05 or input.value("brake", "gamepad") > 0.05:
		active_device = "gamepad"
	elif not is_zero_approx(key_target) or input.value("throttle", "keyboard") > 0.0 or input.value("brake", "keyboard") > 0.0:
		active_device = "keyboard"

	# Steer aid for keyboard and gamepad: less lock at speed, help to catch slides. "Auto" turns
	# it off while a wheel steers.
	var aid_setting := String(input.profile.data.assists.get("steer_aid", "auto"))
	var aid := bool(assists.get("steer_aid", false)) and (aid_setting == "on" or active_device != "wheel")
	if aid:
		steer *= 1.0 / (1.0 + pow(speed / AID_REF_SPEED, 2.0))
		steer += _counter_steer(speed)
		steer = clampf(steer, -1.0, 1.0)

	vehicle.steer = steer
	vehicle.throttle = input.analog("throttle")
	vehicle.brake = input.analog("brake")
	vehicle.handbrake = input.analog("handbrake")
	vehicle.clutch = input.analog("clutch")
	_h_shifter()
	if racer and racer.held:
		# On the grid: the car waits on the handbrake (the brake would select reverse).
		vehicle.throttle = 0.0
		vehicle.brake = 0.0
		vehicle.handbrake = 1.0
	elif racer and racer.pace_limit > 0.0 and speed > racer.pace_limit:
		vehicle.throttle = 0.0
	elif _guide:
		_apply_access_assists(delta)

	if input.just_pressed("shift_up"):
		vehicle.sim.shift(1)
	elif input.just_pressed("shift_down"):
		vehicle.sim.shift(-1)
	if input.just_pressed("reset_car"):
		reset_requested.emit()
	if input.just_pressed("camera_next"):
		camera_next_requested.emit()


## H-shifter (INP-04, docs/INPUT.md §5): the gate held selects that gear, no gate is neutral.
## A refused change (H-pattern without the clutch) is tried again when the clutch goes in.
func _h_shifter() -> void:
	var has_shifter := false
	var want := 0
	for action: String in Bindings.GEARS:
		if input.has_binding(action):
			has_shifter = true
			if input.held(action):
				want = Bindings.GEARS[action]
	if not has_shifter:
		return
	var clutch_in := vehicle.clutch > 0.5
	if want != _gear_held or (clutch_in and not _clutch_in and vehicle.sim.get_gear() != want):
		vehicle.sim.select_gear(want)
	_gear_held = want
	_clutch_in = clutch_in


## Lets go of every control (the car coasts), e.g. while this player's menu is open.
func release() -> void:
	if vehicle:
		vehicle.throttle = 0.0
		vehicle.brake = 0.0
		vehicle.steer = 0.0
		vehicle.handbrake = 0.0
	_key_steer = 0.0
	if input:
		input.clear_toggles()


## Applies the player's assists (allowed by the platform and mode, AssistRules) to the sim, and
## starts or stops the line guide for the access assists.
func apply_assists() -> void:
	if vehicle == null:
		return
	var wheel := input != null and input.wheel.is_active()
	var clutch_pedal := input != null and (input.wheel.has_clutch() or input.has_binding("clutch"))
	assists = AssistRules.effective(input.profile if input else null, vehicle.platform, mode, wheel, clutch_pedal)
	vehicle.sim.set_assists(assists)
	if racer:
		racer.note_assists(assists.duplicate())
	var guided: bool = assists.auto_throttle or assists.autodrive or assists.brake_assist > 0.0 or assists.steering_assist > 0.0
	if guided and _guide == null and racer:
		_guide = RacingAI.new()
		_guide.racer = racer
		_guide.as_guide = true
		add_child(_guide)
	elif not guided and _guide:
		_guide.queue_free()
		_guide = null


## Access assists (docs/ACCESSIBILITY.md §5.2): the line guide's controls blended with the
## player's. Auto-throttle holds the line's speed (the brake still wins); brake assist brakes for
## corners and traffic; steering assist steers toward the line; autodrive does all of it.
func _apply_access_assists(delta: float) -> void:
	var g := _guide.controls(delta)
	if g.is_empty():
		return
	if assists.autodrive:
		vehicle.steer = g.steer
		vehicle.throttle = g.throttle
		vehicle.brake = g.brake
		return
	var steer_mix: float = assists.steering_assist
	vehicle.steer = lerpf(vehicle.steer, g.steer, steer_mix)
	if assists.auto_throttle and vehicle.brake < 0.1:
		vehicle.throttle = g.throttle
	if assists.brake_assist > 0.0 and g.brake > 0.0:
		vehicle.brake = maxf(vehicle.brake, g.brake * assists.brake_assist)
		vehicle.throttle = minf(vehicle.throttle, 1.0 - g.brake * assists.brake_assist)


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
