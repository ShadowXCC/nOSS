class_name Racer
extends Node
## One car in a track session (docs/GAMEMODES.md §1): the vehicle, its driver, lap timer, engine
## sound, reset spot and where it is on the track. SessionPlayer (a local player, with a view)
## and AiRacer (a computer driver, no view) build on it. The session owns what's shared
## (track, platform, grid, RaceField) and asks this for spawns, swaps and resets.

signal cut_track(gained: bool)

const PENDING_SWAP_S := 2.0
## Wrong way for this long: back on the track the right way round.
const WRONG_WAY_RESPAWN_S := 5.0
## Safe rejoin: a reset car waits until nothing is coming within this many seconds...
const REJOIN_CLEAR_S := 4.0
const REJOIN_MAX_WAIT_S := 10.0
## ...then appears at the road's edge without collisions for this long.
const REJOIN_GHOST_S := 3.0

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

## Held on the grid: AI brakes, players' throttle is cut (race starts).
var held := false
## Past the checkered flag (AI drive a cool-down lap).
var finished := false
## Waiting off the track to rejoin after a reset (hidden, no collisions).
var waiting := false
## No collisions with other cars, drawn see-through (just rejoined, or ghosted sessions).
var ghosted := false
## Rolling start: held to this speed (m/s) until the green; 0 = no limit.
var pace_limit := 0.0
## The flag shown to this racer: "", "green", "yellow", "blue" or "checkered".
var flag := ""

## This session's race results (RaceControl): penalties in seconds, warnings, the race time at
## the finish, and whether the racer is out (dropped out).
var penalty_s := 0.0
var warnings := 0
var finish_time := -1.0
var dnf := false
## All four wheels are past the road and curbs.
var out_of_bounds := false

var _loading := false
var _rejoin_at := 0.0
var _wait_time := 0.0
var _ghost_time := 0.0
var _wrong_way_time := 0.0
var _out_since := 0.0 # race time when the wheels went out
var _out_from := 0.0 # along-track distance where they went out
var _clock := 0.0
var _pending_swap: VehiclePackage
var _pending_time := 0.0


## Sets up the lap timer. Subclasses add their view, HUD and camera.
func setup() -> void:
	_new_timer()


## A fresh timer and results for the next session (the car stays).
func new_session() -> void:
	_new_timer()
	finished = false
	penalty_s = 0.0
	warnings = 0
	finish_time = -1.0
	out_of_bounds = false
	pace_limit = 0.0
	_wrong_way_time = 0.0
	if vehicle:
		timer.teleported(track.from_start(distance))


func _new_timer() -> void:
	timer = LapTimer.new()
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
	if session.ghosted:
		set_ghost(true)
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
	if vehicle == null:
		return
	if waiting:
		_wait_time += delta
		if _wait_time >= REJOIN_MAX_WAIT_S or _rejoin_clear():
			_place_rejoin()
	elif _ghost_time > 0.0:
		_ghost_time -= delta
		if _ghost_time <= 0.0:
			if _overlapping_car():
				_ghost_time = 0.5
			else:
				set_ghost(session.ghosted)
	if _pending_swap == null:
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
	_clock += delta
	# Last valid spot for resets: on the road, upright.
	on_track = absf(lateral) < track.width / 2.0 + 1.0 and vehicle.global_basis.y.y > 0.8
	if on_track:
		last_valid = distance
	_check_track_limits()
	# Wrong way: a warning (the HUD shows it), then a respawn facing the right way.
	if timer.wrong_way and not waiting:
		_wrong_way_time += delta
		if _wrong_way_time >= WRONG_WAY_RESPAWN_S:
			_wrong_way_time = 0.0
			reset_car()
	else:
		_wrong_way_time = 0.0


## Track limits (docs/GAMEMODES.md §1): out when all four wheels are past the road's edge and
## any curb there. Coming back, the cut gained time if the car covered that stretch faster
## than the racing line's best for this platform (a car running wide never does).
func _check_track_limits() -> void:
	if waiting or vehicle.fitted == null:
		return
	var left := track.lefts[maxi(track_index, 0)]
	var com_world := com()
	var edge := track.width / 2.0 + track.curb_at(distance) + 0.1
	var out := true
	var side := 0.0
	for w: Dictionary in vehicle.fitted.physics_wheels:
		var lat := lateral + (vehicle.global_transform * (w.center as Vector3) - com_world).dot(left)
		if absf(lat) <= edge or (side != 0.0 and signf(lat) != side):
			out = false
			break
		side = signf(lat)
	if out and not out_of_bounds:
		out_of_bounds = true
		_out_since = _clock
		_out_from = distance
	elif not out and out_of_bounds:
		out_of_bounds = false
		var line := RacingLine.for_track(track)
		var best := line.time_between(line.speed_profile(vehicle.platform, 1.0), _out_from, distance)
		cut_track.emit(_clock - _out_since < best * 0.98)


## Back on the track at the last valid spot, at rest. The current lap stops counting. With
## traffic (AI or a race) the car rejoins safely; otherwise it steps back along the track while
## another car is in the way.
func reset_car() -> void:
	if vehicle == null or waiting:
		return
	timer.invalidate("Reset")
	if session.safe_rejoin:
		_start_rejoin()
		return
	var at := session.free_spot_near(last_valid, self)
	vehicle.reset_to(track.transform_at(at))
	timer.teleported(track.from_start(at))
	distance = at
	track_index = -1


## No collisions with other cars, and drawn see-through.
func set_ghost(on: bool) -> void:
	ghosted = on
	if vehicle:
		vehicle.set_ghost(on, on and not session.ghosted)


func _start_rejoin() -> void:
	waiting = true
	_wait_time = 0.0
	_rejoin_at = last_valid
	set_ghost(true)
	vehicle.freeze = true
	vehicle.visible = false
	notify("Rejoining", 2.0)


## Nothing is coming toward the rejoin spot within REJOIN_CLEAR_S.
func _rejoin_clear() -> bool:
	for r in session.racers:
		if r == self or r.vehicle == null or r.waiting:
			continue
		var to_spot := fposmod(_rejoin_at - r.distance, track.length)
		if to_spot < maxf(r.speed, 8.0) * REJOIN_CLEAR_S + 10.0:
			return false
		# Just past the spot.
		if track.length - to_spot < 12.0:
			return false
	return true


func _place_rejoin() -> void:
	waiting = false
	# At the road's edge, on the side away from the racing line.
	var line := RacingLine.for_track(track).offset_at(_rejoin_at)
	var side := -1.0 if line > 0.0 else 1.0
	var at := track.transform_at(_rejoin_at, side * (track.width / 2.0 - 1.8))
	vehicle.freeze = false
	vehicle.visible = true
	vehicle.reset_to(at)
	timer.teleported(track.from_start(_rejoin_at))
	distance = _rejoin_at
	lateral = side * (track.width / 2.0 - 1.8)
	track_index = -1
	_ghost_time = REJOIN_GHOST_S
	set_ghost(true)


func _overlapping_car() -> bool:
	for r in session.racers:
		if r != self and r.vehicle and not r.waiting and r.vehicle.global_position.distance_to(vehicle.global_position) < 5.0:
			return true
	return false


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
