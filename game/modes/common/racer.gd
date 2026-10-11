class_name Racer
extends Node
## One car in a track session (docs/GAMEMODES.md §1): the vehicle, its driver, lap timer, engine
## sound, reset spot and where it is on the track. SessionPlayer (a local player, with a view)
## and AiRacer (a computer driver, no view) build on it. The session owns what's shared
## (track, platform, grid, RaceField) and asks this for spawns, swaps and resets.

const PENDING_SWAP_S := 2.0

var session: TrackSession
var track: TrackData
var platform: PlatformLoader.Result
var vehicle: Vehicle
## Drives the vehicle: a VehicleController (devices) or a RacingAI.
var driver: Node
var timer := LapTimer.new()
var sound: EngineSound
## The car this racer falls back to when theirs can't load.
var default_car := ""
## Where a spawn puts the car (set by the session before the car loads).
var spawn_at := Transform3D.IDENTITY
## Last on-track spot, for resets (along-track distance).
var last_valid := 0.0

## Shown on standings, the track map and results.
var display_name := ""
var number := 0
var color := Color.WHITE
var is_human := false

## Where the car is, set once per physics tick by the RaceField before anyone drives.
## Along-track distance from the spline's first point (not the start line).
var distance := 0.0
## Metres left (+) or right (-) of the centreline.
var lateral := 0.0
## Nearest centreline sample.
var track_index := -1
## Signed speed along the car's heading, m/s.
var speed := 0.0
var on_track := true

var _loading := false
var _pending_swap: VehiclePackage
var _pending_time := 0.0


## Sets up the lap timer. Subclasses add their view, HUD and camera.
func setup() -> void:
	timer.setup(track.length, track.sectors_m, track.checkpoint_spacing)
	timer.lap_completed.connect(_on_lap)
	timer.sector_completed.connect(_on_sector)
	timer.invalidated.connect(func(reason: String) -> void: notify(reason, 1.5))


## A short message for this racer ("Lap invalid"): players see it on their HUD.
func notify(_text: String, _seconds := 2.0) -> void:
	pass


func load_car(path: String) -> void:
	if _loading:
		return
	_loading = true
	PackageLoader.load_shared(path, _on_car_loaded)


func _on_car_loaded(pkg: VehiclePackage) -> void:
	_loading = false
	if not is_inside_tree():
		pkg.free_scenes()
		return
	if not pkg.ok():
		push_warning("%s: car failed to load: %s (%s)" % [display_name, pkg.path, pkg.error])
		notify("Car failed to load", 2.5)
		if vehicle == null and pkg.path != default_car:
			load_car(default_car)
		return
	_car_loaded(pkg)
	if vehicle == null:
		_spawn(pkg)
		notify("Go", 1.0)
	elif not vehicle.fits_here(pkg):
		_pending_swap = pkg # waits for room, then nudges
		_pending_time = 0.0
		notify("Waiting for room", 2.0)
		return
	else:
		_swap(pkg)
	_car_changed()


## A package arrived (before it's mounted).
func _car_loaded(_pkg: VehiclePackage) -> void:
	pass


## The mounted car changed (spawn or swap).
func _car_changed() -> void:
	pass


func _spawn(pkg: VehiclePackage) -> void:
	vehicle = Vehicle.create(platform, pkg)
	vehicle.name = "Vehicle%d" % number
	session.add_child(vehicle)
	vehicle.reset_to(spawn_at)
	var proj := track.project(spawn_at.origin)
	last_valid = proj.distance
	distance = proj.distance
	lateral = proj.lateral
	track_index = -1
	timer.teleported(track.from_start(last_valid))
	driver = _make_driver()
	add_child(driver)
	sound = EngineSound.new()
	sound.vehicle = vehicle
	vehicle.add_child(sound)
	sound.position = Vector3(0, 0.5, 0)
	vehicle.package_changed.connect(func(p: VehiclePackage) -> void: sound.set_profile(p.sound))
	_spawned()


## The node that drives the car.
func _make_driver() -> Node:
	var ai := RacingAI.new()
	ai.racer = self
	return ai


## The car is on the track and has its driver and sound.
func _spawned() -> void:
	pass


## Hotswap: the platform and the physics state carry on, so the car keeps moving.
func _swap(pkg: VehiclePackage, nudge := false) -> void:
	var before := vehicle.linear_velocity.length()
	vehicle.mount(pkg) # the old visual, which owns the old model, goes with it
	if nudge:
		vehicle.global_position += Vector3.UP * 0.6
	notify("Car loaded", 1.5)
	print("%s swapped to %s: %.1f -> %.1f km/h" % [display_name, pkg.display_name(), before * 3.6, vehicle.linear_velocity.length() * 3.6])


func _physics_process(delta: float) -> void:
	if vehicle == null or _pending_swap == null:
		return
	_pending_time += delta
	if vehicle.fits_here(_pending_swap) or _pending_time >= PENDING_SWAP_S:
		var pkg := _pending_swap
		_pending_swap = null
		_swap(pkg, _pending_time >= PENDING_SWAP_S)
		_car_changed()


## Called by the RaceField once per physics tick, before the drivers: projects the car's centre
## of mass onto the track and feeds the lap timer.
func update_track(delta: float) -> void:
	var com := vehicle.global_transform * vehicle.center_of_mass
	var proj := track.project(com, track_index)
	track_index = proj.index
	distance = proj.distance
	lateral = proj.lateral
	speed = vehicle.speed()
	timer.update(track.from_start(distance), delta, vehicle.linear_velocity.length())
	# Last valid spot for resets: on the road, upright.
	on_track = absf(lateral) < track.width / 2.0 + 1.0 and vehicle.global_basis.y.y > 0.8
	if on_track:
		last_valid = distance


## Back on the track at the last valid spot, at rest. The current lap stops counting. Steps
## back along the track while another car is in the way.
func reset_car() -> void:
	if vehicle == null:
		return
	timer.invalidate("Reset")
	var at := session.free_spot_near(last_valid, self)
	vehicle.reset_to(track.transform_at(at))
	timer.teleported(track.from_start(at))
	distance = at
	track_index = -1


## The centre of mass in world space.
func com() -> Vector3:
	return vehicle.global_transform * vehicle.center_of_mass


func _on_lap(_time: float, _valid: bool, _best: bool) -> void:
	pass


func _on_sector(_sector: int, _time: float, _delta: float) -> void:
	pass


## Frees the car with the racer (on drop out).
func remove() -> void:
	if vehicle:
		vehicle.queue_free()
	queue_free()
