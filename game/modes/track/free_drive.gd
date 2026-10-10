class_name FreeDrive
extends Node3D
## Track free-drive (MODE-01): one player on a track, lap timer with sectors and best lap,
## car reset, pause, and car hotswap (docs/GAMEMODES.md §1).

const DEFAULT_TRACK := "res://content/tracks/proving_ground/track.json"
const DEFAULT_CAR := "res://content/cars/noss_box"
const PLATFORM := "official.track.gt"
const GRID_BEHIND_LINE := 40.0

var track_path := DEFAULT_TRACK
var car_path := ""
var autodrive := false

var track: TrackData
var platform: PlatformLoader.Result
var vehicle: Vehicle
var controller: VehicleController
var cameras: CameraRig
var hud: Hud
var timer := LapTimer.new()
var sound: EngineSound

var _ui := CanvasLayer.new()
var _overlay: Control
var _hint := -1
var _last_valid := 0.0
var _loading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	track = TrackData.load_file(track_path)
	var style := StyleProfile.load_profile(track.style)
	style.apply_globals()
	add_child(style.create_environment())
	add_child(style.create_sun())
	add_child(TrackBuilder.build(track))
	platform = PlatformLoader.load_official(PLATFORM)
	if not platform.ok():
		push_error("Platform: %s" % platform.errors)

	cameras = CameraRig.new()
	add_child(cameras)
	var start := track.transform_at(track.start_m - GRID_BEHIND_LINE)
	cameras.camera.global_transform = Transform3D(Basis.looking_at(start.basis.z), start.origin + Vector3(0, 3, 0) - start.basis.z * 8.0)

	timer.setup(track.length, track.sectors_m, track.checkpoint_spacing)
	timer.lap_completed.connect(_on_lap)
	timer.sector_completed.connect(func(_s: int, _t: float, d: float) -> void: hud.show_delta(d))
	timer.invalidated.connect(func(reason: String) -> void: hud.show_message(reason, 1.5))

	_ui.layer = 10
	add_child(_ui)
	hud = Hud.new()
	hud.theme = UiKit.theme()
	_ui.add_child(hud)
	hud.timer = timer
	hud.show_message("Loading", 30.0)

	var path := car_path if car_path else String(Settings.profile.get("last_car", ""))
	if path.is_empty() or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		path = DEFAULT_CAR
	load_car(path)


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
		push_warning("Car failed to load: %s (%s)" % [pkg.path, pkg.error])
		hud.show_message("Car failed to load", 2.5)
		if vehicle == null and pkg.path != DEFAULT_CAR:
			load_car(DEFAULT_CAR)
		return
	print("Loaded %s in %d ms (%d tris)" % [pkg.display_name(), pkg.load_ms, pkg.triangles])
	Settings.profile.last_car = pkg.path
	Settings.save()
	if vehicle == null:
		_spawn(pkg)
		hud.show_message("Go", 1.0)
	else:
		vehicle.mount(pkg) # hotswap: platform and physics state carry on
		hud.show_message("Car loaded", 1.5)
	hud.set_car_name(pkg.display_name() + _fit_notes())


func _spawn(pkg: VehiclePackage) -> void:
	vehicle = Vehicle.create(platform, pkg)
	add_child(vehicle)
	_last_valid = track.start_m - GRID_BEHIND_LINE
	vehicle.reset_to(track.transform_at(_last_valid))
	timer.teleported(track.from_start(_last_valid))

	if autodrive:
		var ai := LineFollower.new()
		ai.vehicle = vehicle
		ai.track = track
		add_child(ai)
	else:
		controller = VehicleController.new()
		controller.vehicle = vehicle
		controller.wheel_input = Devices.wheel
		Devices.wheel.platform_lock_deg = float(platform.platform.steering.wheel_rotation_deg)
		controller.reset_requested.connect(reset_car)
		controller.camera_next_requested.connect(_next_camera)
		add_child(controller)
		controller.apply_assists()
		Settings.changed.connect(controller.apply_assists)
	sound = EngineSound.new()
	sound.vehicle = vehicle
	vehicle.add_child(sound)
	sound.position = Vector3(0, 0.5, 0)
	cameras.set_vehicle(vehicle)
	cameras.set_mode(Settings.profile.get("camera", "chase_near"))
	hud.vehicle = vehicle


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	if controller and Devices.wheel.is_active():
		Devices.wheel.update_ffb(vehicle.sim.get_rack_force())
		# The in-car wheel turns with the real one.
		vehicle.steering_wheel_lock_deg = Devices.wheel.platform_lock_deg
	var proj := track.project(vehicle.global_position, _hint)
	_hint = proj.index
	timer.update(track.from_start(proj.distance), delta, vehicle.linear_velocity.length())
	# Last valid spot for resets: on the road, upright.
	if absf(proj.lateral) < track.width / 2.0 + 1.0 and vehicle.global_basis.y.y > 0.8:
		_last_valid = proj.distance


## Back on the track at the last valid spot, at rest. The current lap stops counting.
func reset_car() -> void:
	if vehicle == null:
		return
	timer.invalidate("Reset")
	var at := _last_valid
	vehicle.reset_to(track.transform_at(at))
	timer.teleported(track.from_start(at))
	_hint = -1


func _next_camera() -> void:
	cameras.next_mode()
	Settings.set_value("camera", cameras.mode)


func _on_lap(time: float, valid: bool, best: bool) -> void:
	print("Lap %d: %s%s%s" % [timer.lap, Hud.format_time(time), "" if valid else " (invalid)", " best" if best else ""])
	if not valid:
		hud.show_message("Lap invalid", 2.0)
	elif best:
		hud.show_message("Best lap  " + Hud.format_time(time), 3.0)
	else:
		hud.show_message(Hud.format_time(time), 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if _overlay:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_open_pause()
	elif event.is_action_pressed("hotswap_menu"):
		get_viewport().set_input_as_handled()
		_open_picker(false)


func _exit_tree() -> void:
	Devices.wheel.stop_ffb()


func _open_pause() -> void:
	get_tree().paused = true
	Devices.wheel.stop_ffb()
	var menu := PauseMenu.new()
	menu.resumed.connect(_close_overlay)
	menu.reset_car.connect(func() -> void:
		_close_overlay()
		reset_car())
	menu.change_car.connect(func() -> void:
		_close_overlay()
		_open_picker(true))
	menu.quit_to_title.connect(func() -> void: Game.go_title())
	_show_overlay(menu)


## Car picker. Mid-drive (not paused) the car keeps rolling while you choose.
func _open_picker(pause: bool) -> void:
	get_tree().paused = pause
	var picker := CarPicker.new()
	picker.current = vehicle.package.path if vehicle else ""
	picker.picked.connect(func(path: String) -> void:
		_close_overlay()
		if vehicle == null or path != vehicle.package.path:
			hud.show_message("Loading", 10.0)
			load_car(path))
	picker.closed.connect(_close_overlay)
	_show_overlay(picker)


func _show_overlay(control: Control) -> void:
	_overlay = control
	if controller:
		controller.set_physics_process(false) # menu keys don't drive; the car coasts
		vehicle.throttle = 0.0
		vehicle.brake = 0.0
		vehicle.steer = 0.0
	_ui.add_child(control)


func _close_overlay() -> void:
	get_tree().paused = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	if controller:
		controller.set_physics_process(true)


func _fit_notes() -> String:
	return ("  (" + ", ".join(vehicle.fitted.notes) + ")") if vehicle and not vehicle.fitted.notes.is_empty() else ""
