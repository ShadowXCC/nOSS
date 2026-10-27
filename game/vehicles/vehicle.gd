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
## A kart's is higher: the wheels hold it, and its body mustn't scrape inside loops and
## wall-rides (a 4.6 m model in a 9 m loop sags 0.2 m toward its ends, D133).
const KART_CLEARANCE := 0.3
## A knock that changes the car's speed this much in one tick (m/s) counts (knocked_at).
const KNOCK_DV := 0.5
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
## The mode's kart_arcade numbers (GameModes.arcade), or {} for the plain sim (D130).
var arcade := {}
## Kart: the drift button, held (its press also hops, or does a trick in the air).
var drift := false
## Whether the drift button does anything at all (sumo turns it off on a setting, D181): with it
## false the handbrake is left alone instead of suppressed, so the car brakes as any other does.
var drift_allowed := true
## Kart flags the game keeps (shield, magnet, towed, out); the sim adds its own (kart_flags()).
var kart_bits := 0

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := 0.0
var clutch := 0.0
## Lock-to-lock rotation of the in-car steering wheel, degrees.
var steering_wheel_lock_deg := 540.0
## Contact impulse this tick (N·s) with other cars and with anything else, and the car hit last.
var car_impulse := 0.0
## When this car last took a knock of KNOCK_DV or more (s, Time ticks): its states say so online.
var knocked_at := -INF
## Its horn (D119): two tones, made once for every car.
static var _horn_stream: AudioStreamWAV
var _horn_player: AudioStreamPlayer3D
var wall_impulse := 0.0
var last_hit: Vehicle
## Sumo's landing catch (D218): the fastest fall since a wheel or the body last touched the
## ground, and how long the catch after a hard landing still holds.
var _fall := 0.0
var _catch := 0.0
var _catch_flat := 0.0
## Each reset_to() counts up (network states flag the car as placed, not moved).
var reset_count := 0
## Flat tyres (a spike strip, D192): bit i for physics wheel i, for this much longer.
var flats := 0
var _flat_left := 0.0
## Contacts with remote cars this tick: [other Vehicle, impulse on this car, world point] (D86).
var remote_contacts: Array = []
## A package without a model shows as a box in this colour (an online car still arriving).
var placeholder_color := Color(0.6, 0.6, 0.62)
## A highway traffic car turned into a physics car (D110): its lane-sim index; -1 otherwise.
var traffic_id := -1
## Contact impulse this tick with traffic (traffic cars, their stand-in boxes), N·s.
var traffic_impulse := 0.0
## Indicators (1 left, 2 right, 3 hazards), head lights (0 off, 1 on), a flash of the head
## lights, the horn, and a police car's siren and light bar. Shown here; sent online (D119).
var indicators := 0
var head_lights := 0
var head_flash := false
var horn := false
var siren := false
var light_bar := false
## Update wheels and lights once a frame instead of every physics tick (traffic, D120).
var visual_every_frame := false
## Off on a dedicated server and on headless bots, where nobody sees the cars: no wheels, lights
## or horn are updated.
static var drawn := true
## Wheels turn and steer only on cars this near a camera (lights everywhere).
const WHEELS_NEAR_M := 80.0
static var _cams := PackedVector3Array()
static var _cams_frame := -1
## Indicators blink at 1.5 Hz (on half the time).
const BLINK_HZ := 1.5
var _blink := 0.0

## Another game drives this car (D84): a kinematic body moved to its states; no sim here, and the
## wheels, lights and sound follow the states.
var remote := false
var remote_state: CarState
var remote_velocity := Vector3.ZERO
var _remote_spin := PackedFloat32Array()
var _wheel_radius := PackedFloat32Array() # per physics wheel, for a remote car's spin
var _wheel_front := PackedByteArray()
var _lights_key := -1

var _collision: CollisionShape3D
var _road := Vector2.ZERO
var _beams: SpotLight3D
var _spray: GPUParticles3D
static var _puff: GradientTexture2D


## Drives with the kart_arcade layer (`numbers` from GameModes.arcade), or without it ({}).
## `allow_drift` false leaves the layer on but takes the drift button away (D181).
func set_arcade(numbers: Dictionary, allow_drift := true) -> void:
	arcade = numbers
	drift_allowed = allow_drift
	sim.set_layer(numbers)
	if fitted:
		_collision.shape = _hull(fitted, _clearance())


func _clearance() -> float:
	return KART_CLEARANCE if not arcade.is_empty() else BODY_CLEARANCE


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
	add_to_group(&"vehicles")
	add_to_group(&"origin_shift")


## The floating origin moved (D155): the car moves with the world, keeping its speed and spin.
## Not a reset (online it isn't a teleport).
func origin_shifted(delta: Vector3) -> void:
	global_position += delta
	reset_physics_interpolation()


## Water and snow on the road under this car (EnvDirector, D153); its grip follows.
func set_road(wetness: float, snow: float) -> void:
	var c := Vector2(wetness, snow)
	if not c.is_equal_approx(_road):
		_road = c
		sim.set_conditions(wetness, snow)


## Spray off its wheels on a wet road, 0..1 (EnvDirector, D153).
func set_spray(amount: float) -> void:
	if not drawn:
		return
	if amount <= 0.02:
		if _spray:
			_spray.emitting = false
		return
	if _spray == null:
		_spray = _make_spray()
		add_child(_spray)
	_spray.amount_ratio = clampf(amount, 0.0, 1.0)
	_spray.emitting = true


func _make_spray() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Spray"
	p.amount = 64
	p.lifetime = 0.7
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -5, -40), Vector3(40, 15, 60))
	var half_width := 0.8
	var rear := -2.0
	if fitted and fitted.envelope.size != Vector3.ZERO:
		half_width = fitted.envelope.size.x * 0.4
		rear = fitted.envelope.position.z + 0.2
	p.position = Vector3(0.0, 0.25, rear)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(half_width, 0.05, 0.15)
	m.direction = Vector3(0.0, 0.35, -1.0)
	m.spread = 18.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 5.0
	m.gravity = Vector3(0.0, -3.0, 0.0)
	m.scale_min = 0.6
	m.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.35))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var look := StandardMaterial3D.new()
	look.albedo_texture = _spray_puff()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color(0.85, 0.87, 0.9)
	look.roughness = 1.0
	look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	quad.material = look
	p.draw_pass_1 = quad
	return p


## A soft round puff for spray, made once.
static func _spray_puff() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_puff = GradientTexture2D.new()
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(0.5, 0.0)
		_puff.width = 32
		_puff.height = 32
	return _puff


## The water and snow on the road under it, as last set (x wetness, y snow).
func road_conditions() -> Vector2:
	return _road


## Its headlights light the road (players' cars and the nearest few, at night; D153).
func set_beams(on: bool) -> void:
	if on == (_beams != null) or not drawn:
		return
	if not on:
		_beams.queue_free()
		_beams = null
		return
	_beams = SpotLight3D.new()
	_beams.name = "Beams"
	_beams.light_color = Color(1.0, 0.95, 0.85)
	_beams.light_energy = 7.0
	_beams.spot_range = 95.0
	_beams.spot_angle = 40.0
	_beams.spot_attenuation = 0.55
	_beams.spot_angle_attenuation = 1.3
	_beams.shadow_enabled = false
	_beams.light_specular = 0.3
	var front := 2.0
	var height := 0.7
	if fitted and fitted.envelope.size != Vector3.ZERO:
		front = fitted.envelope.end.z
		height = fitted.envelope.position.y + fitted.envelope.size.y * 0.35
	# A little ahead of the nose and tilted down to light the road; the body faces +Z.
	_beams.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-2.5), PI, 0.0)), Vector3(0.0, height, front + 0.2))
	add_child(_beams)


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
	_collision.shape = _hull(fitted, _clearance())

	if visual:
		visual.queue_free()
	visual = CarVisual.create(pkg, fitted, placeholder_color)
	_lights_key = -1
	_remote_spin.clear()
	add_child(visual)
	Siren.fit(self) # police cars: their light bar and siren
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
	query.shape = _hull(f, _clearance())
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


## Puts the car with its wheels on the ground at `xform` (ground point, +Z forward): at rest, or
## going at `velocity` with its wheels already rolling (a car placed into moving traffic).
func reset_to(xform: Transform3D, velocity := Vector3.ZERO) -> void:
	var t := Transform3D(xform.basis.orthonormalized(), xform.origin - xform.basis.orthonormalized().y * fitted.ground_y)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = t
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	if velocity == Vector3.ZERO:
		sim.reset()
	else:
		sim.roll_at(velocity.dot(t.basis.z))
	reset_physics_interpolation()
	reset_count += 1
	_fall = 0.0
	_catch = 0.0


## Makes this a remote car (D84): kinematic, moved by move_remote().
## Wheels `mask` go flat for `seconds` (with any already flat), or until the car's reset.
func flatten(mask: int, seconds := 30.0) -> void:
	flats |= mask
	_flat_left = maxf(_flat_left, seconds)
	sim.set_flats(flats)


## Every tyre back up.
func repair() -> void:
	flats = 0
	_flat_left = 0.0
	sim.set_flats(0)


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
		return # its wheels and lights once a frame (_process)
	if flats:
		_flat_left -= delta
		if _flat_left <= 0.0:
			repair()
	sim.set_controls(steer, throttle, brake, handbrake, clutch)
	if not arcade.is_empty():
		sim.set_kart_input(drift)
	if drawn and not visual_every_frame:
		_update_visual(_near_camera())


func _process(delta: float) -> void:
	if not drawn:
		return
	_blink = fmod(_blink + delta * BLINK_HZ, 1.0)
	if remote:
		_update_remote_visual(delta, _near_camera())
	elif visual_every_frame:
		_update_visual(_near_camera())
	if visual:
		var on := _blink < 0.5
		var key := (1 if on and indicators & 1 != 0 else 0) | (2 if on and indicators & 2 != 0 else 0) | (4 if head_flash else 0) | (8 * head_lights)
		if key != _lights_key: # only when something changed
			_lights_key = key
			visual.set_indicators(key & 1 != 0, key & 2 != 0)
			visual.set_light("head", 2.0 if head_flash else float(head_lights))
			visual.set_tail_lights(head_lights > 0)
		_sound_horn()


## True if a player's camera is within WHEELS_NEAR_M (always with no camera, as in tests).
func _near_camera() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _cams_frame:
		_cams_frame = frame
		_cams = PackedVector3Array()
		for rig in CameraRig.rigs:
			if is_instance_valid(rig) and rig.camera.is_inside_tree():
				_cams.append(rig.camera.global_position)
	if _cams.is_empty():
		return true
	var at := global_position
	for c in _cams:
		if c.distance_squared_to(at) < WHEELS_NEAR_M * WHEELS_NEAR_M:
			return true
	return false


## The horn sounds while it's held (this car's, or a remote car's from its states).
func _sound_horn() -> void:
	if _horn_player == null:
		if not horn:
			return
		if _horn_stream == null:
			_horn_stream = EngineSound._wav(NossAudio.render_horn(420.0, 500.0))
		_horn_player = AudioStreamPlayer3D.new()
		_horn_player.name = "Horn"
		_horn_player.stream = _horn_stream
		_horn_player.bus = &"Effects"
		_horn_player.unit_size = 12.0
		_horn_player.max_distance = 400.0
		add_child(_horn_player)
	if horn and not _horn_player.playing:
		_horn_player.play()
	elif not horn and _horn_player.playing:
		_horn_player.stop()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if remote:
		return
	sim.integrate(state)
	car_impulse = 0.0
	wall_impulse = 0.0
	traffic_impulse = 0.0
	remote_contacts.clear()
	for i in state.get_contact_count():
		var j := state.get_contact_impulse(i)
		var impulse := j.length()
		var felt := j # what this car keeps of the knock
		var other := state.get_contact_collider_object(i)
		if other is Vehicle:
			car_impulse += impulse
			last_hit = other
			if (other as Vehicle).traffic_id >= 0:
				traffic_impulse += impulse
			if (other as Vehicle).remote and impulse > 0.0:
				# A remote car is kinematic, as heavy as a wall: this car took the whole knock. Two
				# cars share it by mass; its owner's game takes the other side (D86).
				var point := state.get_contact_local_position(i)
				var keep: float = other.mass / (mass + other.mass)
				state.apply_impulse(-j * (1.0 - keep), point - state.transform.origin)
				remote_contacts.append([other, j * keep, point])
				felt = j * keep
		elif other is Node and (other as Node).has_meta(&"noss_traffic"):
			traffic_impulse += impulse
			car_impulse += impulse
		else:
			wall_impulse += impulse
		if not arcade.is_empty() and impulse > 0.0:
			_kart_bounce(state, felt, other)
	if float(arcade.get("land", {}).get("min_fall", 0.0)) > 0.0:
		_land_catch(state)
	if (car_impulse + wall_impulse) / mass > KNOCK_DV:
		knocked_at = Time.get_ticks_msec() / 1000.0


## Kart walls and bumps bounce (D132). Jolt gives every contact a bounce of 0.1; a kart adds the
## rest of its mode's restitution from the knock's own impulse, so a wall it leans on stays still.
func _kart_bounce(state: PhysicsDirectBodyState3D, j: Vector3, other: Object) -> void:
	var b: Dictionary = arcade.bounce
	var e := 0.0
	if other is Vehicle:
		e = b.kart
	elif other is Node and (other as Node).has_meta(&"noss_tag"):
		return # stunt pieces are driven on
	elif absf(j.normalized().y) < 0.5:
		e = b.wall
	else:
		return # floors and slopes
	if j.length() / mass < float(b.min_dv) * 1.1 or e <= 0.1:
		return
	state.apply_central_impulse(j * ((e - 0.1) / 1.1))


## The platform below catches a falling car (sumo, D218). On the first touchdown after a fall
## faster than `min_fall` it keeps only `keep` of its speed across the ground, and for `settle_s`
## rises no faster than `rebound` and gathers no more speed across the ground: a few small hops,
## not a bounce off the far side as well. The kart layer's righting flip gets the same hold, as it
## would otherwise throw a car lying on its roof clean off the platform.
func _land_catch(state: PhysicsDirectBodyState3D) -> void:
	var c: Dictionary = arcade.land
	var v := state.linear_velocity
	var flat := Vector3(v.x, 0.0, v.z)
	var down := wall_impulse > 0.0 or sim.get_kart_flags() & VehicleSim.KART_FLAG_AIRBORNE == 0
	if not down:
		_fall = maxf(_fall, -v.y)
	elif _fall > 0.0:
		if _fall >= float(c.min_fall):
			_catch = float(c.settle_s)
			flat *= float(c.keep)
			_catch_flat = flat.length()
		_fall = 0.0
	if _catch <= 0.0 and state.transform.basis.y.y < 0.5 and float(sim.get_kart_state().righting) > 0.0:
		_catch = float(c.settle_s)
		_catch_flat = flat.length()
	if _catch > 0.0:
		_catch -= state.step
		v.y = minf(v.y, float(c.rebound))
		flat = flat.limit_length(_catch_flat)
	state.linear_velocity = Vector3(flat.x, v.y, flat.z)


## The kart's flags (CarState's kart word, D142): the sim's drift, tier, boost, spin, slow, trick
## and airborne, and the game's own bits.
func kart_flags() -> int:
	if remote:
		return kart_bits # as its own game sent them
	return (sim.get_kart_flags() if not arcade.is_empty() else 0) | kart_bits


func drifting() -> bool:
	return kart_flags() & (VehicleSim.KART_FLAG_DRIFT_LEFT | VehicleSim.KART_FLAG_DRIFT_RIGHT) != 0


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


func _update_visual(wheels := true) -> void:
	if visual == null:
		return
	visual.set_brake_lights(sim.get_brake() > 0.05)
	if not wheels:
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


## Wheels and lights of a remote car from its newest state; wheels spin with its speed (only
## `wheels` near a camera).
func _update_remote_visual(delta: float, wheels := true) -> void:
	if visual == null or fitted == null or remote_state == null:
		return
	var s := remote_state
	visual.set_brake_lights(s.flags & CarState.FLAG_BRAKE != 0)
	if not wheels:
		return
	var n := fitted.physics_wheels.size()
	if _remote_spin.size() != n:
		_remote_spin.resize(n)
		_remote_spin.fill(0.0)
		_wheel_radius.resize(n)
		_wheel_front.resize(n)
		for j in n:
			var w: Dictionary = fitted.physics_wheels[j]
			_wheel_radius[j] = maxf(float(w.get("visual_radius", w.radius)), 0.1)
			_wheel_front[j] = 1 if int(w.axle) == 1 else 0
	var fwd := remote_velocity.dot(global_basis.z)
	for j in n:
		_remote_spin[j] = fmod(_remote_spin[j] + fwd / _wheel_radius[j] * delta, TAU)
	for i in mini(visual.wheel_count(), fitted.wheel_map.size()):
		var mapped := fitted.wheel_map[i]
		if mapped.is_empty() or mapped[0] >= n:
			continue
		var j := mapped[0]
		visual.set_wheel(i, s.steer if _wheel_front[j] == 1 else 0.0, _remote_spin[j], s.lift[mini(j, 3)])
	visual.set_steering_angle(-s.steer * deg_to_rad(steering_wheel_lock_deg) / 2.0)


## Convex hull of the clamped envelope, with its floor raised and its lower ends chamfered.
static func _hull(f: Fitting.Result, clearance := BODY_CLEARANCE) -> ConvexPolygonShape3D:
	var e := f.envelope
	var hi := e.end
	# Never thinner than 0.25 m, however low the model.
	var lo := Vector3(e.position.x, minf(f.ground_y + clearance, hi.y - 0.25), e.position.z)
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
