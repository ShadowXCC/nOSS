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
## The platform before any setup (its official values).
var base_platform := {}
var platform_hash := ""
## "normal", or "strict" for physics on the platform's reference geometry (docs/PLATFORMS.md §4.2).
var fitting_mode := "normal"
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
## Contact impulse this tick (N·s) with other cars and with anything else, and the car hit last.
var car_impulse := 0.0
var wall_impulse := 0.0
var last_hit: Vehicle
## Each reset_to() counts up (network states flag the car as placed, not moved).
var reset_count := 0
## Contacts with remote cars this tick: [other Vehicle, impulse on this car, world point] (D86).
var remote_contacts: Array = []
## A package without a model shows as a box in this colour (an online car still arriving).
var placeholder_color := Color(0.6, 0.6, 0.62)

## Another game drives this car (D84): a kinematic body moved to its states; no sim here, and the
## wheels, lights and sound follow the states.
var remote := false
var remote_state: CarState
var remote_velocity := Vector3.ZERO
var _remote_spin := PackedFloat32Array()

var _collision: CollisionShape3D


## Builds a vehicle; add it to the tree, then place it with reset_to().
static func create(platform_result: PlatformLoader.Result, pkg: VehiclePackage, fitting := "normal") -> Vehicle:
	var v := Vehicle.new()
	v.name = "Vehicle"
	v.platform = platform_result.platform
	v.base_platform = platform_result.platform
	v.platform_hash = platform_result.hash
	v.fitting_mode = fitting
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
	v.contact_monitor = true
	v.max_contacts_reported = 4
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
	fitted = Fitting.fit(platform, pkg.fit, fitting_mode)
	var geometry := { "ground_y": fitted.ground_y, "wheels": fitted.physics_wheels }
	if not sim.configure(platform, geometry):
		push_error("Vehicle sim: " + sim.get_error())
	var body := sim.get_body_params()
	mass = body.mass
	center_of_mass = body.center_of_mass
	inertia = body.inertia
	_collision.shape = _hull(fitted)

	if visual:
		visual.queue_free()
	visual = CarVisual.create(pkg, fitted, placeholder_color)
	add_child(visual)
	var sw: Variant = pkg.fit.get("steering_wheel")
	steering_wheel_lock_deg = sw.visual_lock_deg if sw is Dictionary else 540.0

	# Keep the wheels on the ground when the new model's origin sits at another height.
	if not is_nan(old_ground) and is_inside_tree():
		global_position += global_basis.y * (old_ground - fitted.ground_y + 0.02)
	package_changed.emit(pkg)


## Drives with `setup`'s changes (null: the platform's own values). The car keeps moving; the
## platform's identity (`platform_hash`) stays the official one.
func apply_setup(setup: Setup) -> void:
	platform = setup.apply(base_platform) if setup else base_platform
	if fitted and not sim.configure(platform, { "ground_y": fitted.ground_y, "wheels": fitted.physics_wheels }):
		push_error("Vehicle sim: " + sim.get_error())


## False if `pkg`'s collision envelope would overlap the world where the car is now (a swap
## then waits; docs/VEHICLE_PACKAGE.md §8).
func fits_here(pkg: VehiclePackage) -> bool:
	if not is_inside_tree():
		return true
	var f := Fitting.fit(platform, pkg.fit, fitting_mode)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hull(f)
	var lift := global_basis.y * (fitted.ground_y - f.ground_y + 0.02) if fitted else Vector3.ZERO
	query.transform = Transform3D(global_basis, global_position + lift)
	query.collision_mask = LAYER_WORLD
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Where the car stands: its ground point under the model's origin, with the body's rotation
## (what reset_to takes; network states send this, D84).
func ground_reference() -> Transform3D:
	var b := global_basis.orthonormalized()
	return Transform3D(b, global_position + b.y * (fitted.ground_y if fitted else 0.0))


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
	reset_count += 1


## Makes this a remote car (D84): kinematic, moved by move_remote().
func set_remote(on: bool) -> void:
	remote = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	continuous_cd = not on
	sim.reset()


## A knock relayed from the other car's game (D86): `impulse` (N·s, world) at world `point`.
func apply_remote_impulse(impulse: Vector3, point: Vector3) -> void:
	apply_impulse(impulse, point - global_position)


## Moves a remote car to `ground` (its ground reference) going at `velocity`.
func move_remote(ground: Transform3D, velocity: Vector3, angular: Vector3, snap := false) -> void:
	var b := ground.basis.orthonormalized()
	global_transform = Transform3D(b, ground.origin - b.y * (fitted.ground_y if fitted else 0.0))
	remote_velocity = velocity
	linear_velocity = velocity
	angular_velocity = angular
	if snap:
		reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if remote:
		_update_remote_visual(delta)
		return
	sim.set_controls(steer, throttle, brake, handbrake, clutch)
	_update_visual()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if remote:
		return
	sim.integrate(state)
	car_impulse = 0.0
	wall_impulse = 0.0
	remote_contacts.clear()
	for i in state.get_contact_count():
		var j := state.get_contact_impulse(i)
		var impulse := j.length()
		var other := state.get_contact_collider_object(i)
		if other is Vehicle:
			car_impulse += impulse
			last_hit = other
			if (other as Vehicle).remote and impulse > 0.0:
				# A remote car is kinematic, as heavy as a wall: this car took the whole knock. Two
				# cars share it by mass; its owner's game takes the other side (D86).
				var point := state.get_contact_local_position(i)
				var keep: float = other.mass / (mass + other.mass)
				state.apply_impulse(-j * (1.0 - keep), point - state.transform.origin)
				remote_contacts.append([other, j * keep, point])
		else:
			wall_impulse += impulse


## No contact with other cars (a car rejoining, or a ghosted session), drawn see-through
## if `see_through`.
func set_ghost(on: bool, see_through := true) -> void:
	collision_layer = 0 if on else LAYER_VEHICLES
	collision_mask = LAYER_WORLD if on else LAYER_WORLD | LAYER_VEHICLES
	if visual:
		for mi: GeometryInstance3D in visual.find_children("*", "GeometryInstance3D", true, false):
			mi.transparency = 0.5 if on and see_through else 0.0


## Signed speed along the car's heading, m/s.
func speed() -> float:
	return remote_velocity.dot(global_basis.z) if remote else sim.get_speed()


## Eye point for the cockpit camera, body frame.
func eye_point() -> Vector3:
	return fitted.eye_point


func _update_visual() -> void:
	if visual == null:
		return
	var physics := []
	for j in sim.get_wheel_count():
		physics.append(sim.get_wheel_visual(j))
	# Each model wheel follows its physics wheel(s): steer and lift averaged, spin from the first.
	for i in mini(visual.wheel_count(), fitted.wheel_map.size()):
		var mapped := fitted.wheel_map[i]
		if mapped.is_empty() or mapped[0] >= physics.size():
			continue
		var steer := 0.0
		var lift := 0.0
		for j in mapped:
			steer += physics[j].x / mapped.size()
			lift += physics[j].z / mapped.size()
		visual.set_wheel(i, steer, physics[mapped[0]].y, lift)
	visual.set_steering_angle(-steer * deg_to_rad(steering_wheel_lock_deg) / 2.0)
	visual.set_brake_lights(sim.get_brake() > 0.05)


## Wheels and lights of a remote car from its newest state; wheels spin with its speed.
func _update_remote_visual(delta: float) -> void:
	if visual == null or fitted == null or remote_state == null:
		return
	var s := remote_state
	var n := fitted.physics_wheels.size()
	if _remote_spin.size() != n:
		_remote_spin.resize(n)
		_remote_spin.fill(0.0)
	var fwd := remote_velocity.dot(global_basis.z)
	for j in n:
		var radius := maxf(float(fitted.physics_wheels[j].get("visual_radius", fitted.physics_wheels[j].radius)), 0.1)
		_remote_spin[j] = fmod(_remote_spin[j] + fwd / radius * delta, TAU)
	for i in mini(visual.wheel_count(), fitted.wheel_map.size()):
		var mapped := fitted.wheel_map[i]
		if mapped.is_empty() or mapped[0] >= n:
			continue
		var j := mapped[0]
		var front := int(fitted.physics_wheels[j].axle) == 1
		visual.set_wheel(i, s.steer if front else 0.0, _remote_spin[j], s.lift[mini(j, 3)])
	visual.set_steering_angle(-s.steer * deg_to_rad(steering_wheel_lock_deg) / 2.0)
	visual.set_brake_lights(s.flags & CarState.FLAG_BRAKE != 0)


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
