class_name SessionPlayer
extends Node
## One player in a session (docs/GAMEMODES.md §1, LOC-01): their car, controls, camera, HUD,
## lap timer, engine sound and reset spot, shown in their own view (PlayerView). The session
## owns what's shared (track, platform, views, pause) and asks this for spawns and swaps.

signal pause_requested(player: SessionPlayer)

const PENDING_SWAP_S := 2.0

var slot: PlayerSlot
var session: FreeDrive
var view: PlayerView
var track: TrackData
var platform: PlatformLoader.Result
var vehicle: Vehicle
var controller: VehicleController
var ai: LineFollower
var cameras := CameraRig.new()
var hud := Hud.new()
var timer := LapTimer.new()
var sound: EngineSound
## Fitting Bay test drive: the car isn't remembered.
var bay_return := false
## The car this player falls back to when theirs can't load.
var default_car := ""
## Where a spawn puts the car (set by the session before the car loads).
var spawn_at := Transform3D.IDENTITY
## Last on-track spot, for resets (along-track distance).
var last_valid := 0.0
## This player's own menu (pause, car picker), or null.
var overlay: Control

var _hint := -1
var _loading := false
var _paused_tree := false
var _pending_swap: VehiclePackage
var _pending_time := 0.0


func _init() -> void:
	name = "Player"


## Puts the camera and HUD into the player's view.
func setup(world_env: Environment) -> void:
	name = "Player%d" % slot.number()
	cameras.input = null if slot.ai else slot.input
	view.add_3d(cameras)
	view.set_camera(cameras.camera, world_env)
	hud.theme = UiKit.theme()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS # shows "Paused by P2" while paused
	view.hud_root.add_child(hud)
	hud.timer = timer
	hud.show_message("Loading", 30.0)
	update_badge(1)
	timer.setup(track.length, track.sectors_m, track.checkpoint_spacing)
	timer.lap_completed.connect(_on_lap)
	timer.sector_completed.connect(func(_s: int, _t: float, d: float) -> void: hud.show_delta(d))
	timer.invalidated.connect(func(reason: String) -> void: hud.show_message(reason, 1.5))
	cameras.camera.global_transform = Transform3D(Basis.looking_at(spawn_at.basis.z), spawn_at.origin + Vector3(0, 3, 0) - spawn_at.basis.z * 8.0)


func update_badge(player_count: int) -> void:
	hud.set_player(slot.tag(), slot.color(), player_count > 1)


func load_car(path: String) -> void:
	if _loading:
		return
	_loading = true
	PackageLoader.load_async(path, _on_car_loaded)


func _on_car_loaded(pkg: VehiclePackage) -> void:
	_loading = false
	if not is_inside_tree():
		pkg.free_scenes()
		return
	if not pkg.ok():
		push_warning("%s: car failed to load: %s (%s)" % [slot.tag(), pkg.path, pkg.error])
		hud.show_message("Car failed to load", 2.5)
		if vehicle == null and pkg.path != default_car:
			load_car(default_car)
		return
	print("%s loaded %s in %d ms (%d tris)" % [slot.tag(), pkg.display_name(), pkg.load_ms, pkg.triangles])
	if not bay_return and not slot.ai:
		slot.profile.set_value("last_car", pkg.path)
	if vehicle == null:
		_spawn(pkg)
		hud.show_message("Go", 1.0)
	elif not vehicle.fits_here(pkg):
		_pending_swap = pkg # waits for room, then nudges
		_pending_time = 0.0
		hud.show_message("Waiting for room", 2.0)
		return
	else:
		_swap(pkg)
	hud.set_car_name("%s · %s%s" % [platform.platform.name, pkg.display_name(), _fit_notes()])


func _spawn(pkg: VehiclePackage) -> void:
	vehicle = Vehicle.create(platform, pkg)
	vehicle.name = "Vehicle%s" % slot.tag()
	session.add_child(vehicle)
	vehicle.reset_to(spawn_at)
	last_valid = track.project(spawn_at.origin).distance
	timer.teleported(track.from_start(last_valid))

	if slot.ai:
		ai = LineFollower.new()
		ai.vehicle = vehicle
		ai.track = track
		ai.lateral = track.project(spawn_at.origin).lateral
		ai.pace = 0.8 - 0.03 * slot.index
		add_child(ai)
	else:
		controller = VehicleController.new()
		controller.vehicle = vehicle
		controller.input = slot.input
		slot.input.wheel.platform_lock_deg = float(platform.platform.steering.wheel_rotation_deg)
		controller.reset_requested.connect(reset_car)
		controller.camera_next_requested.connect(_next_camera)
		add_child(controller)
		controller.apply_assists()
		slot.profile.changed.connect(_on_profile_changed)
	sound = EngineSound.new()
	sound.vehicle = vehicle
	vehicle.add_child(sound)
	sound.position = Vector3(0, 0.5, 0)
	vehicle.package_changed.connect(func(p: VehiclePackage) -> void: sound.set_profile(p.sound))
	cameras.set_vehicle(vehicle)
	cameras.set_mode(String(slot.profile.data.get("camera", "chase_near")))
	hud.vehicle = vehicle


## Hotswap: the platform and the physics state carry on, so the car keeps moving.
func _swap(pkg: VehiclePackage, nudge := false) -> void:
	var before := vehicle.linear_velocity.length()
	vehicle.mount(pkg) # the old visual, which owns the old model, goes with it
	if nudge:
		vehicle.global_position += Vector3.UP * 0.6
	hud.show_message("Car loaded", 1.5)
	hud.set_car_name("%s · %s%s" % [platform.platform.name, pkg.display_name(), _fit_notes()])
	print("%s swapped to %s: %.1f -> %.1f km/h" % [slot.tag(), pkg.display_name(), before * 3.6, vehicle.linear_velocity.length() * 3.6])


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	if _pending_swap:
		_pending_time += delta
		if vehicle.fits_here(_pending_swap) or _pending_time >= PENDING_SWAP_S:
			var pkg := _pending_swap
			_pending_swap = null
			_swap(pkg, _pending_time >= PENDING_SWAP_S)
	if controller and overlay == null:
		if slot.input.wheel.is_active():
			slot.input.wheel.update_ffb(vehicle.sim.get_rack_force())
			# The in-car wheel turns with the real one.
			vehicle.steering_wheel_lock_deg = slot.input.wheel.platform_lock_deg
		if slot.input.just_pressed("pause"):
			pause_requested.emit(self)
		elif slot.input.just_pressed("hotswap_menu") and session.hotswap_allowed:
			open_picker(false)
	var proj := track.project(vehicle.global_position, _hint)
	_hint = proj.index
	timer.update(track.from_start(proj.distance), delta, vehicle.linear_velocity.length())
	if Game.dev.has("log-drive") and Engine.get_physics_frames() % 60 == 0:
		print("%s d %.0f lat %.1f v %.0f gear %d" % [slot.tag(), track.from_start(proj.distance), proj.lateral, vehicle.speed() * 3.6, vehicle.sim.get_gear()])
	# Last valid spot for resets: on the road, upright.
	if absf(proj.lateral) < track.width / 2.0 + 1.0 and vehicle.global_basis.y.y > 0.8:
		last_valid = proj.distance


## Back on the track at the last valid spot, at rest. The current lap stops counting. Steps
## back along the track while another car is in the way.
func reset_car() -> void:
	if vehicle == null:
		return
	timer.invalidate("Reset")
	var at := session.free_spot_near(last_valid, self)
	vehicle.reset_to(track.transform_at(at))
	timer.teleported(track.from_start(at))
	_hint = -1


func _next_camera() -> void:
	cameras.next_mode()
	slot.profile.set_value("camera", cameras.mode)


func _on_profile_changed() -> void:
	if controller:
		controller.apply_assists()
	view.apply_profile()
	hud.apply_profile(slot.profile)


func _on_lap(time: float, valid: bool, best: bool) -> void:
	print("%s lap %d: %s%s%s" % [slot.tag(), timer.lap, Hud.format_time(time), "" if valid else " (invalid)", " best" if best else ""])
	if not valid:
		hud.show_message("Lap invalid", 2.0)
	elif best:
		hud.show_message("Best lap  " + Hud.format_time(time), 3.0)
	else:
		hud.show_message(Hud.format_time(time), 2.0)


## Car picker in this player's view. Mid-drive (not paused) the car keeps rolling while
## they choose.
func open_picker(pause: bool) -> void:
	var picker := CarPicker.new()
	picker.current = vehicle.package.path if vehicle else ""
	picker.platform = platform.platform
	picker.picked.connect(func(path: String) -> void:
		close_overlay()
		if vehicle == null or path != vehicle.package.path:
			hud.show_message("Loading", 10.0)
			load_car(path))
	picker.closed.connect(close_overlay)
	show_overlay(picker, pause)


## Shows one of this player's menus; their navigation goes there and their car coasts.
func show_overlay(control: Control, pause := false) -> void:
	close_overlay()
	if pause:
		get_tree().paused = true
		_paused_tree = true
	overlay = control
	if controller:
		controller.set_physics_process(false)
		controller.release()
	slot.input.wheel.stop_ffb()
	view.overlay_root.add_child(control)
	slot.input.settle()
	slot.menu_target = view.viewport


func close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	if _paused_tree:
		_paused_tree = false
		get_tree().paused = false
	slot.menu_target = null
	slot.input.settle() # the press that closed the menu doesn't drive
	if controller:
		controller.set_physics_process(true)


func _exit_tree() -> void:
	slot.menu_target = null
	if not slot.ai:
		slot.input.wheel.stop_ffb()


## Frees the car with the player (on drop out).
func remove() -> void:
	close_overlay()
	if vehicle:
		vehicle.queue_free()
	queue_free()


func _fit_notes() -> String:
	return ("  (" + ", ".join(vehicle.fitted.notes) + ")") if vehicle and not vehicle.fitted.notes.is_empty() else ""
