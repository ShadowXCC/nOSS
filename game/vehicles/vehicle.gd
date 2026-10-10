class_name Vehicle
extends RigidBody3D
## A drivable vehicle: platform physics (VehicleSim) on a Jolt rigid body, with a package's
## model mounted on top (docs/ARCHITECTURE.md §4). Mass, inertia and CoG come from the
## platform, never from the model.

signal package_changed(pkg: VehiclePackage)

const LAYER_WORLD := 1
const LAYER_VEHICLES := 2
## Collision box floor above the model's ground, so curbs and crests don't snag it.
const BODY_CLEARANCE := 0.12
const CHAMFER := 0.18

var platform := {}
var platform_hash := ""
var package: VehiclePackage
var fitted: Fitting.Result
var sim := VehicleSim.new()
var visual: CarVisual

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := 0.0
var clutch := 0.0
## Lock-to-lock rotation of the in-car steering wheel, degrees.
var steering_wheel_lock_deg := 540.0

var _collision: CollisionShape3D


## Builds a vehicle; add it to the tree, then place it with reset_to().
static func create(platform_result: PlatformLoader.Result, pkg: VehiclePackage) -> Vehicle:
	var v := Vehicle.new()
	v.name = "Vehicle"
	v.platform = platform_result.platform
	v.platform_hash = platform_result.hash
	v.can_sleep = false
	v.continuous_cd = true
	v.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.linear_damp = 0.0
	v.angular_damp = 0.0
	v.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	v.collision_layer = LAYER_VEHICLES
	v.collision_mask = LAYER_WORLD | LAYER_VEHICLES
	var material := PhysicsMaterial.new()
	material.friction = 0.3
	material.bounce = 0.1
	v.physics_material_override = material
	v._collision = CollisionShape3D.new()
	v._collision.name = "Collision"
	v.add_child(v._collision)
	v.sim.set_collision_mask(LAYER_WORLD)
	v.mount(pkg)
	return v


func _ready() -> void:
	sim.set_exclude([get_rid()])


## Mounts a package: fit, visuals, collision envelope. Mid-drive this is the hotswap:
## the platform and the physics state carry on (docs/VEHICLE_PACKAGE.md §8).
func mount(pkg: VehiclePackage) -> void:
	var old_ground := fitted.ground_y if fitted else NAN
	package = pkg
	fitted = Fitting.fit(platform, pkg.fit)
	var geometry := { "ground_y": fitted.ground_y, "wheels": fitted.wheels }
	if not sim.configure(platform, geometry):
		push_error("Vehicle sim: " + sim.get_error())
	var body := sim.get_body_params()
	mass = body.mass
	center_of_mass = body.center_of_mass
	inertia = body.inertia
	_collision.shape = _hull(fitted)

	if visual:
		visual.queue_free()
	visual = CarVisual.create(pkg, fitted)
	add_child(visual)
	var sw: Variant = pkg.fit.get("steering_wheel")
	steering_wheel_lock_deg = sw.visual_lock_deg if sw is Dictionary else 540.0

	# Keep the wheels on the ground when the new model's origin sits at another height.
	if not is_nan(old_ground) and is_inside_tree():
		global_position += global_basis.y * (old_ground - fitted.ground_y + 0.02)
	package_changed.emit(pkg)


## Puts the car at rest with its wheels on the ground at `xform` (ground point, +Z forward).
func reset_to(xform: Transform3D) -> void:
	var t := Transform3D(xform.basis.orthonormalized(), xform.origin - xform.basis.orthonormalized().y * fitted.ground_y)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sim.reset()
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	sim.set_controls(steer, throttle, brake, handbrake, clutch)
	_update_visual()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	sim.integrate(state)


func speed() -> float:
	return sim.get_speed()


## Eye point for the cockpit camera, body frame.
func eye_point() -> Vector3:
	return fitted.eye_point


func _update_visual() -> void:
	if visual == null:
		return
	for i in mini(visual.wheel_count(), sim.get_wheel_count()):
		var w := sim.get_wheel_visual(i)
		visual.set_wheel(i, w.x, w.y, w.z)
	visual.set_steering_angle(-steer * deg_to_rad(steering_wheel_lock_deg) / 2.0)
	visual.set_brake_lights(sim.get_brake() > 0.05)


## Convex hull of the clamped envelope, with its floor raised and its lower ends chamfered.
static func _hull(f: Fitting.Result) -> ConvexPolygonShape3D:
	var e := f.envelope
	var lo := Vector3(e.position.x, f.ground_y + BODY_CLEARANCE, e.position.z)
	var hi := e.end
	var chamfer := minf(CHAMFER, (hi.y - lo.y) * 0.4)
	var points := PackedVector3Array()
	for x in [lo.x, hi.x]:
		points.append_array([
			Vector3(x, hi.y, lo.z), Vector3(x, hi.y, hi.z),
			Vector3(x, lo.y + chamfer, lo.z), Vector3(x, lo.y + chamfer, hi.z),
			Vector3(x, lo.y, lo.z + chamfer), Vector3(x, lo.y, hi.z - chamfer),
		])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape
