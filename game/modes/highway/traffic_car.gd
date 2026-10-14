class_name TrafficCar
extends Node
## A traffic car turned into a physics car near a player (D110, D120): a Vehicle on its type's
## traffic platform, driven by the native lane driver after its lane-sim shadow (NossTraffic.drive),
## in lite mode (no engine sound, visuals once a frame). The TrafficManager makes and removes them.

## Stopped this long while its shadow drives on, or on its side: a wreck.
const STUCK_S := 4.0
const RESHADOW_M := 15.0
const OFF_LANE_S := 2.0

var manager: TrafficManager
var car := -1
var vehicle: Vehicle
## Where the driver last had it: lane, s (its front, m), m off the lane's line, heading error.
var lane := -1
var s := 0.0
var lateral := 0.0
var heading_error := 0.0
var blocked := false
var gap := INF
var wrecked := false
var stuck_time := 0.0
var _off_time := 0.0
var _wheelbase := 2.7
var _max_steer := 0.55
var _half := Vector2(2.25, 0.9)


func _ready() -> void:
	process_physics_priority = -50
	var p := vehicle.platform
	_wheelbase = float(p.geometry.wheelbase_m.ref)
	_max_steer = deg_to_rad(float(p.steering.max_road_angle_deg))
	var e := vehicle.fitted.envelope
	_half = Vector2(e.size.z / 2.0, e.size.x / 2.0)
	var assists := { "abs": true, "tcs": true, "stability": true, "auto_gearbox": true, "auto_clutch": true }
	vehicle.sim.set_assists(assists)


func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if wrecked:
		vehicle.throttle = 0.0
		vehicle.brake = 0.0
		vehicle.handbrake = 1.0
		vehicle.indicators = 3 # hazards
		return
	var out := manager.sim.drive(car, car, vehicle.global_position, vehicle.global_basis.z, vehicle.speed(), _wheelbase, _max_steer, _half, manager.members())
	vehicle.steer = out[0]
	vehicle.throttle = out[1]
	vehicle.brake = out[2]
	vehicle.handbrake = out[3]
	lane = int(out[4])
	s = out[5]
	lateral = out[6]
	heading_error = out[7]
	blocked = out[8] > 0.5
	vehicle.indicators = 1 if out[9] > 0.5 else (2 if out[9] < -0.5 else 0)
	gap = out[10]
	# Stuck: not moving while the lane sim's version of it is (a queue or a merge isn't stuck).
	var shadow_v := float(manager.sim.car(car).get("v", 0.0))
	stuck_time = stuck_time + delta if absf(vehicle.speed()) < 1.0 and shadow_v > 3.0 else 0.0


## Back on its lane's line, heading along it and the right way up: it can go back into the lane sim.
func lane_ok() -> bool:
	return lane >= 0 and absf(lateral) < 1.2 and absf(heading_error) < 0.2 and vehicle.global_basis.y.y > 0.95


## On its side or roof, or stopped where nothing holds it up: a wreck.
func crashed() -> bool:
	return vehicle.global_basis.y.y < 0.5 or stuck_time > STUCK_S


## Far enough from its shadow that the lane sim should be told where it really is (RESHADOW).
func drifted(delta: float) -> bool:
	var shadow := manager.sim.car(car)
	if shadow.is_empty() or lane < 0:
		return false
	if int(shadow.lane) == lane:
		_off_time = 0.0
		return absf(float(shadow.s) - s) > RESHADOW_M
	if int(shadow.lc_from) == lane:
		return false # its shadow is moving over and it isn't yet
	_off_time += delta
	return _off_time > OFF_LANE_S
