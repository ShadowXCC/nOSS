class_name SessionPlayer
extends Racer
## One local player in a session (docs/GAMEMODES.md §1, LOC-01): a Racer with their own view,
## controls, camera and HUD. Dev players (`slot.ai`) are driven by the RacingAI but keep their
## view.

signal pause_requested(player: SessionPlayer)

var slot: PlayerSlot
var view: PlayerView
var controller: VehicleController
var cameras := CameraRig.new()
var hud := Hud.new()
## Fitting Bay test drive: the car isn't remembered.
var bay_return := false
## This player's own menu (pause, car picker), or null.
var overlay: Control

var _paused_tree := false
## Drives the car home after the flag (players' cars take a cool-down lap too).
var _cool_down: RacingAI


func _init() -> void:
	name = "Player"


## Puts the camera and HUD into the player's view.
func setup() -> void:
	name = "Player%d" % slot.number()
	number = slot.number()
	color = slot.color()
	display_name = slot.display_name()
	is_human = not slot.ai
	super()
	cameras.input = null if slot.ai else slot.input
	view.add_3d(cameras)
	view.set_camera(cameras.camera, session.world_env)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS # shows "Paused by P2" while paused
	view.hud_root.add_child(hud)
	hud.apply_profile(slot.profile)
	hud.timer = timer
	hud.racer = self
	hud.race = session.race
	hud.show_message("Loading", 30.0)
	update_badge(1)
	cameras.camera.global_transform = Transform3D(Basis.looking_at(spawn_at.basis.z), spawn_at.origin + Vector3(0, 3, 0) - spawn_at.basis.z * 8.0)


func notify(text: String, seconds := 2.0) -> void:
	hud.show_message(text, seconds)


func update_badge(player_count: int) -> void:
	hud.set_player(slot.tag(), slot.color(), player_count > 1)


func _car_loaded(pkg: VehiclePackage) -> void:
	print("%s loaded %s in %d ms (%d tris)" % [slot.tag(), pkg.display_name(), pkg.load_ms, pkg.triangles])
	if not bay_return and not slot.ai:
		slot.profile.set_value("last_car", pkg.path)


func _car_changed() -> void:
	hud.set_car_name("%s · %s%s" % [platform.platform.name, vehicle.package.display_name(), _fit_notes()])


func _make_driver() -> Node:
	if slot.ai:
		return super()
	controller = VehicleController.new()
	controller.vehicle = vehicle
	controller.input = slot.input
	controller.racer = self
	slot.input.wheel.platform_lock_deg = float(platform.platform.steering.wheel_rotation_deg)
	controller.reset_requested.connect(reset_car)
	controller.camera_next_requested.connect(_next_camera)
	slot.profile.changed.connect(_on_profile_changed)
	return controller


func _spawned() -> void:
	vehicle.name = "Vehicle%s" % slot.tag()
	if controller:
		controller.apply_assists()
	cameras.set_vehicle(vehicle)
	cameras.set_mode(String(slot.profile.data.get("camera", "chase_near")))
	hud.vehicle = vehicle


func _physics_process(delta: float) -> void:
	super(delta)
	if vehicle == null:
		return
	if finished and controller and _cool_down == null:
		_start_cool_down()
	if controller and overlay == null:
		if slot.input.wheel.is_active():
			slot.input.wheel.update_ffb(vehicle.sim.get_rack_force())
			# The in-car wheel turns with the real one.
			vehicle.steering_wheel_lock_deg = slot.input.wheel.platform_lock_deg
		if slot.input.just_pressed("pause"):
			pause_requested.emit(self)
		elif slot.input.just_pressed("hotswap_menu") and session.hotswap_allowed:
			open_picker(false)


func new_session() -> void:
	super()
	hud.timer = timer
	if _cool_down:
		_cool_down.queue_free()
		_cool_down = null
		if controller and overlay == null:
			controller.set_physics_process(true)


## After the flag the RacingAI brings the car round at an easy pace.
func _start_cool_down() -> void:
	controller.set_physics_process(false)
	controller.release()
	_cool_down = RacingAI.new()
	_cool_down.racer = self
	add_child(_cool_down)


func update_track(delta: float) -> void:
	super(delta)
	if Game.dev.has("log-drive") and Engine.get_physics_frames() % 60 == 0:
		print("%s d %.0f lat %.1f v %.0f gear %d" % [slot.tag(), track.from_start(distance), lateral, vehicle.speed() * 3.6, vehicle.sim.get_gear()])


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


func _on_sector(_sector: int, _time: float, delta: float) -> void:
	hud.show_delta(delta)


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
	if controller and _cool_down == null:
		controller.set_physics_process(true)


func _exit_tree() -> void:
	slot.menu_target = null
	if not slot.ai:
		slot.input.wheel.stop_ffb()


## Frees the car with the player (on drop out).
func remove() -> void:
	close_overlay()
	super()


func _fit_notes() -> String:
	return ("  (" + ", ".join(vehicle.fitted.notes) + ")") if vehicle and not vehicle.fitted.notes.is_empty() else ""
