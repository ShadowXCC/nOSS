class_name CameraRig
extends Node3D
## Chase (near, far), hood, bumper and cockpit cameras for one player (docs/ART_AUDIO.md §4,
## AV-04), with that player's comfort options (docs/ACCESSIBILITY.md §4): camera shake, head
## movement, speed FOV and horizon lock. Free look (the right stick, docs/INPUT.md §1) turns the
## view while it's held and swings back to the camera when it's let go. The camera is current in the viewport the rig is in,
## so in splitscreen each player's view has its own.

const MODES := ["chase_near", "chase_far", "hood", "bumper", "cockpit"]
const MOUNTED_FOV := { "hood": 70.0, "bumper": 76.0 }
const CHASE := {
	"chase_near": { "distance": 5.6, "height": 1.7, "look_height": 0.9, "fov": 68.0 },
	"chase_far": { "distance": 8.5, "height": 2.6, "look_height": 1.0, "fov": 62.0 },
}
const COCKPIT_FOV := 72.0
const SPEED_FOV_EXTRA := 10.0
const SPEED_FOV_AT := 70.0 # m/s
## Free look at full deflection, degrees: [sideways, up, down]. Chase cameras orbit the car (up
## brings the camera lower, so it's kept small); the others turn the head.
const LOOK_CHASE := [120.0, 10.0, 25.0]
const LOOK_MOUNTED := [100.0, 30.0, 30.0]
## How quickly the view follows the stick, and comes back.
const LOOK_RATE := 14.0

var vehicle: Vehicle
## Whose settings and look-back control this camera follows; null: P1's settings, no look-back.
var input: PlayerInput
var mode := "chase_near"
var camera := Camera3D.new()
## Every player's rig in the scene (cars far from them all skip wheel animation).
static var rigs: Array[CameraRig] = []

var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw_dir := Vector3.FORWARD
var _head := Vector3.ZERO
## Free look now, radians: x turns right, y looks up.
var _look := Vector2.ZERO
var _shake_time := 0.0
var _initialized := false


func _ready() -> void:
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()
	top_level = true
	# The rig follows the car's interpolated transform itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _enter_tree() -> void:
	rigs.append(self)


func _exit_tree() -> void:
	rigs.erase(self)


func set_vehicle(v: Vehicle) -> void:
	vehicle = v
	_initialized = false


func next_mode() -> void:
	set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])


func set_mode(new_mode: String) -> void:
	mode = new_mode if new_mode in MODES else "chase_near"
	_initialized = false


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var xf := vehicle.get_global_transform_interpolated()
	var speed := vehicle.linear_velocity.length()
	var look_back := input != null and input.held("look_back")
	var profile: Dictionary = input.profile.data if input else Settings.profile
	var fov_extra := SPEED_FOV_EXTRA * clampf(speed / SPEED_FOV_AT, 0.0, 1.0) if profile.get("speed_fov", true) else 0.0
	update_look(delta)
	if mode == "cockpit":
		_cockpit(xf, delta, look_back, fov_extra, profile)
	elif mode in MOUNTED_FOV:
		_mounted(xf, delta, look_back, fov_extra, profile)
	else:
		_chase(xf, delta, look_back, fov_extra, profile)


## Eases the free look toward where the stick points (nothing held: back to the camera).
func update_look(delta: float) -> void:
	var target := Vector2.ZERO
	if input:
		var limits: Array = LOOK_CHASE if mode in CHASE else LOOK_MOUNTED
		var x := input.value("look_right") - input.value("look_left")
		var y := input.value("look_up") - input.value("look_down")
		target = Vector2(deg_to_rad(limits[0]) * x, deg_to_rad(limits[1] if y > 0.0 else limits[2]) * y)
	_look = _look.lerp(target, 1.0 - exp(-delta * LOOK_RATE))


## A fixed camera's view turned by the free look.
func _looked(look: Basis) -> Basis:
	return look * Basis(Vector3.UP, -_look.x) * Basis(Vector3.RIGHT, _look.y)


func _chase(xf: Transform3D, delta: float, look_back: bool, fov_extra: float, profile: Dictionary) -> void:
	var c: Dictionary = CHASE[mode]
	# Follow the direction of travel when moving, the car's nose when slow.
	var fwd := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	var vel := Vector3(vehicle.linear_velocity.x, 0.0, vehicle.linear_velocity.z)
	if vel.length() > 3.0 and vel.normalized().dot(fwd) > 0.0:
		fwd = fwd.lerp(vel.normalized(), 0.35).normalized()
	var same := _yaw_dir.dot(fwd)
	if not _initialized or same < -0.99 or same > 0.99999:
		_yaw_dir = fwd # turned right round (a reset), or there already: slerp's axis is unsteady
	else:
		_yaw_dir = _yaw_dir.slerp(fwd, 1.0 - exp(-delta * 6.0)).normalized()
	var dir := -_yaw_dir if look_back else _yaw_dir
	if Game.dev.has("cam-yaw"):
		dir = dir.rotated(Vector3.UP, deg_to_rad(float(Game.dev["cam-yaw"])))
	dir = dir.rotated(Vector3.UP, -_look.x)
	# Pinned to the car; only the heading and the height are smoothed. Pulls back a little
	# with speed.
	var speed := vehicle.linear_velocity.length()
	var distance: float = c.distance + clampf(speed / 80.0, 0.0, 1.0) * 0.8
	if not _initialized:
		_vel = Vector3(0, xf.origin.y, 0)
		_initialized = true
	_vel.y = lerpf(_vel.y, xf.origin.y, 1.0 - exp(-delta * 10.0))
	var base := Vector3(xf.origin.x, _vel.y, xf.origin.z)
	# Looking up brings the camera lower behind the car, looking down raises it.
	_pos = base - dir * distance * cos(_look.y) + Vector3.UP * (c.height - distance * sin(_look.y))
	var look_at: Vector3 = base + Vector3.UP * c.look_height + dir * 2.0
	var shake := _shake(delta, profile)
	camera.global_transform = Transform3D(Basis.looking_at(look_at - (_pos + shake), Vector3.UP), _pos + shake)
	camera.fov = c.fov + fov_extra


func _cockpit(xf: Transform3D, delta: float, look_back: bool, fov_extra: float, profile: Dictionary) -> void:
	# Head movement: the head lags behind the car's accelerations.
	var a := vehicle.sim.get_acceleration()
	var amount: float = profile.get("head_movement", 0.5)
	var target := Vector3(-a.x * 0.004, -a.y * 0.002, -a.z * 0.005) * amount
	target = target.limit_length(0.08)
	_head = _head.lerp(target, 1.0 - exp(-delta * 8.0))
	var eye := vehicle.eye_point() + _head
	var basis := xf.basis
	if profile.get("horizon_lock", false):
		var flat := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
		basis = Basis(Vector3.UP.cross(flat).normalized(), Vector3.UP, flat)
	var look := _looked(basis.rotated(basis.y, PI if not look_back else 0.0))
	var shake := _shake(delta, profile) * 0.3
	camera.global_transform = Transform3D(look.orthonormalized(), xf * eye + shake)
	camera.fov = COCKPIT_FOV + fov_extra * 0.6
	_initialized = true


## Hood and bumper: fixed to the car, looking ahead.
func _mounted(xf: Transform3D, delta: float, look_back: bool, fov_extra: float, profile: Dictionary) -> void:
	var at: Vector3 = vehicle.fitted.hood if mode == "hood" else vehicle.fitted.bumper
	var basis := xf.basis
	if profile.get("horizon_lock", false):
		var flat := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
		basis = Basis(Vector3.UP.cross(flat).normalized(), Vector3.UP, flat)
	var look := _looked(basis.rotated(basis.y, PI if not look_back else 0.0))
	var shake := _shake(delta, profile) * 0.5
	camera.global_transform = Transform3D(look.orthonormalized(), xf * at + shake)
	camera.fov = MOUNTED_FOV[mode] + fov_extra * 0.6
	_initialized = true


## Small speed rumble, scaled by the player's camera shake setting.
func _shake(delta: float, profile: Dictionary) -> Vector3:
	var amount: float = profile.get("camera_shake", 0.5)
	if amount <= 0.0:
		return Vector3.ZERO
	_shake_time += delta
	var speed := vehicle.linear_velocity.length()
	var s := clampf((speed - 20.0) / 60.0, 0.0, 1.0) * 0.012 * amount
	return Vector3(sin(_shake_time * 37.0) * s, sin(_shake_time * 53.0 + 1.3) * s, 0.0)
