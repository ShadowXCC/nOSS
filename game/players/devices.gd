extends Node
## Input devices (autoload "Devices", docs/INPUT.md §2): starts the native wheel layer,
## polls it every physics tick, and picks which gamepad drives the actions. Gamepads go
## through Godot; wheels, pedals and other sim devices through noss_core.

signal devices_changed

var wheel := WheelInput.new()
var native_ok := false

var _last_ids := []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100 # before vehicles read their inputs
	if ClassDB.class_exists(&"NossInput") and DisplayServer.get_name() != "headless":
		native_ok = NossInput.start()
		if native_ok:
			print("Wheel support: SDL %s" % NossInput.sdl_version())
		else:
			print("Wheel support off: %s" % NossInput.get_error())
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _pick_gamepad())
	_pick_gamepad()
	_setup_wheel()


func _exit_tree() -> void:
	wheel.stop_ffb()
	if native_ok:
		NossInput.stop()


func _physics_process(_delta: float) -> void:
	if not native_ok:
		return
	NossInput.poll()
	var ids := sim_devices().map(func(d: Dictionary) -> int: return d.id)
	if ids != _last_ids:
		_last_ids = ids
		_setup_wheel()
		_pick_gamepad()
		devices_changed.emit()


## Non-gamepad devices (wheels, pedals, shifters...), from noss_core.
func sim_devices() -> Array:
	if not native_ok:
		return []
	return NossInput.devices().filter(func(d: Dictionary) -> bool: return not d.gamepad or d.wheel)


## Uses the saved wheel if it's connected, else the first device SDL calls a wheel.
func _setup_wheel() -> void:
	var cfg: Dictionary = Settings.profile.get("wheel", {})
	var found := -1
	for d: Dictionary in sim_devices():
		if cfg.get("guid", "") == d.guid:
			found = d.id
			break
	if found < 0:
		for d: Dictionary in sim_devices():
			if d.wheel:
				found = d.id
				if cfg.get("guid", "") != d.guid:
					cfg = { "guid": d.guid, "name": d.name, "steer": { "axis": 0, "center": 0.0 } }
				break
	wheel.configure(found, cfg if found >= 0 else {})


func save_wheel(cfg: Dictionary) -> void:
	Settings.set_value("wheel", cfg)
	_setup_wheel()


## First Godot joypad with a known gamepad mapping that isn't one of our sim devices.
func _pick_gamepad() -> void:
	var sim := sim_devices().map(func(d: Dictionary) -> String: return "%d:%d" % [d.vendor, d.product])
	var chosen := -1
	for pad in Input.get_connected_joypads():
		var info := Input.get_joy_info(pad)
		var key := "%d:%d" % [int(info.get("vendor_id", -1)), int(info.get("product_id", -2))]
		if Input.is_joy_known(pad) and key not in sim:
			chosen = pad
			break
	if chosen != Bindings.gamepad:
		print("Gamepad: %s" % (Input.get_joy_name(chosen) if chosen >= 0 else "none"))
	Bindings.use_gamepad(chosen, Settings.profile.bindings)
