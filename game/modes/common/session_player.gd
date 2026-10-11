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
## This player's setup for the class and track (PLT-04).
var car_setup: Setup

## Spotter (docs/ACCESSIBILITY.md §2): who's alongside ("", "left", "right", "three").
const SPOTTER_HZ := 10.0
const SPOTTER_RANGE_M := 5.0
var _spot_state := ""
var _spot_time := 0.0
var _spot_said := 0.0
## Race callouts: what was said last.
var _said_position := 0
var _position_since := 0.0
var _said_flag := ""
var _said_final := false


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
	hud.camera = cameras.camera
	hud.show_message("Loading", 30.0)
	update_badge(1)
	cameras.camera.global_transform = Transform3D(Basis.looking_at(spawn_at.basis.z), spawn_at.origin + Vector3(0, 3, 0) - spawn_at.basis.z * 8.0)


func notify(text: String, seconds := 2.0) -> void:
	hud.show_message(text, seconds)
	speak(text)


## A race event out loud (with this player's narration) and as a caption, never voice-only.
## `kind`: "race" (narration) or "spotter".
func speak(text: String, kind := "race") -> void:
	var profile := slot.profile
	var voice := false
	if kind == "spotter":
		voice = String(profile.data.get("spotter", "off")) == "voice" and _has_spotter_voice()
	else:
		voice = Narrator.race_on(profile) and not slot.ai
	if not voice and not (kind == "spotter" and String(profile.data.get("spotter", "off")) != "off"):
		return
	if voice:
		# Several players share one speaker: say whose it is.
		var said := text if session.players.size() == 1 else "%s %s" % [slot.tag(), text]
		Narrator.say(said, "vol_spotter" if kind == "spotter" else "vol_narration", float(profile.data.get("narration_rate", 1.0)))
	if bool(profile.data.get("captions", true)):
		hud.caption(text)


## Only one player has the spotter's voice: the first with it set to voice.
func _has_spotter_voice() -> bool:
	for p in session.players:
		if String(p.slot.profile.data.get("spotter", "off")) == "voice" and not p.slot.ai:
			return p == self
	return false


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
	if not slot.ai:
		car_setup = Setup.load_for(vehicle.base_platform, session.mode, track.id)
		if not car_setup.is_default():
			vehicle.apply_setup(car_setup)
			custom_setup = true
	if controller:
		controller.apply_assists()
	cameras.set_vehicle(vehicle)
	cameras.set_mode(String(slot.profile.data.get("camera", "chase_near")))
	hud.vehicle = vehicle


func _physics_process(delta: float) -> void:
	super(delta)
	if vehicle == null:
		return
	_spot_time -= delta
	if _spot_time <= 0.0:
		_spot_time = 1.0 / SPOTTER_HZ
		_update_spotter()
		_race_callouts()
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
	_said_position = 0
	_said_flag = ""
	_said_final = false
	hud.timer = timer
	if _cool_down:
		_cool_down.queue_free()
		_cool_down = null
		if controller and overlay == null:
			controller.set_physics_process(true)


## Cars alongside: "Car left", "Car right", "Three wide", "Clear" (spoken with voice, always
## as markers and captions while the spotter is on).
func _update_spotter() -> void:
	var mode := String(slot.profile.data.get("spotter", "off"))
	if mode == "off" or slot.ai or waiting:
		hud.set_spotter(false, false)
		return
	var left := false
	var right := false
	var inv := vehicle.global_basis.inverse()
	for r in session.racers:
		if r == self or r.vehicle == null or r.waiting:
			continue
		if absf(session.field.gap(self, r)) > RacingAI.CAR_LENGTH + 1.0:
			continue
		var rel := inv * (r.vehicle.global_position - vehicle.global_position)
		if absf(rel.x) > SPOTTER_RANGE_M or absf(rel.x) < 1.0:
			continue
		if rel.x > 0.0:
			left = true # +X is the car's left
		else:
			right = true
	hud.set_spotter(left, right)
	var state := "three" if left and right else ("left" if left else ("right" if right else ""))
	if state == _spot_state:
		return
	var was := _spot_state
	_spot_state = state
	# Don't chatter: a new call at most every 0.6 s (Clear always comes).
	if state != "" and _clock - _spot_said < 0.6:
		return
	_spot_said = _clock
	var words := { "left": "Car left", "right": "Car right", "three": "Three wide", "": "Clear" }
	if state != "" or was != "":
		speak(words[state], "spotter")


## Race events: position changes (once settled), the final lap, flags.
func _race_callouts() -> void:
	var race := session.race
	if slot.ai or race.kind != "race" or race.phase not in [RaceControl.Phase.RUNNING, RaceControl.Phase.CHECKERED] or finished:
		return
	var pos := race.position_of(self)
	if pos != _said_position:
		if _position_since <= 0.0:
			_position_since = _clock
		elif _clock - _position_since >= 1.5:
			_said_position = pos
			_position_since = 0.0
			speak("P%d" % pos)
	else:
		_position_since = 0.0
	if not _said_final and race.event.race_min <= 0 and race.event.race_laps > 1 and timer.lap == race.event.race_laps:
		_said_final = true
		speak("Final lap")
	if flag != _said_flag:
		_said_flag = flag
		match flag:
			"yellow": speak("Yellow flag")
			"blue": speak("Blue flag")


## The setup menu closed: drive with the changes from now on, and keep them for next time.
func setup_changed() -> void:
	if vehicle == null or car_setup == null:
		return
	vehicle.apply_setup(car_setup)
	custom_setup = not car_setup.is_default()
	if custom_setup:
		assists_used["setup"] = true
	car_setup.save(track.id)
	notify("Setup saved" if custom_setup else "Default setup", 1.5)


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
	session.apply_game_speed()


func _on_lap(time: float, valid: bool, best: bool) -> void:
	print("%s lap %d: %s%s%s" % [slot.tag(), timer.lap, Hud.format_time(time), "" if valid else " (invalid)", " best" if best else ""])
	if not valid:
		hud.show_message("Lap invalid", 2.0)
		speak("Lap invalid")
	elif best:
		hud.show_message("Best lap  " + Hud.format_time(time), 3.0)
		speak("Best lap")
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
