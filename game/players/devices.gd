extends Node
## Input devices (autoload "Devices", docs/INPUT.md §2): starts the native wheel layer, polls it
## every physics tick, and lists every device a player can claim: the keyboard, Godot's
## gamepads, and the sim devices (wheels, pedals, shifters...) that noss_core reads.
##
## Entries: {kind: "keyboard"|"gamepad"|"sim", key, name, id, guid, vendor, product, preset}
## plus {wheel, axes, buttons, ffb} for sim devices. `key` is stable across reconnects:
## "kb", "pad:<guid>#<n>", "sim:<guid>#<n>" (n tells identical devices apart).

signal devices_changed

var native_ok := false
## Extra devices for tests (fake gamepads fed with Input.parse_input_event).
var test_devices: Array[Dictionary] = []:
	set(devices):
		test_devices = devices
		_dirty = true

var _last_sim := []
var _list: Array[Dictionary] = []
var _dirty := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100 # before players and vehicles read their inputs
	if ClassDB.class_exists(&"NossInput") and DisplayServer.get_name() != "headless":
		native_ok = NossInput.start()
		if native_ok:
			print("Wheel support: SDL %s" % NossInput.sdl_version())
		else:
			print("Wheel support off: %s" % NossInput.get_error())
	devices_changed.connect(func() -> void: _dirty = true)
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: devices_changed.emit())
	if not Game.dedicated:
		for pad in gamepads():
			print("Gamepad: %s" % pad.name)


func _exit_tree() -> void:
	if native_ok:
		NossInput.stop()


func _physics_process(_delta: float) -> void:
	if not native_ok:
		return
	NossInput.poll()
	var ids := sim_devices().map(func(d: Dictionary) -> int: return d.id)
	if ids != _last_sim:
		_last_sim = ids
		devices_changed.emit()


## Every claimable device: the keyboard first, then gamepads, then sim devices.
func list() -> Array[Dictionary]:
	if _dirty:
		_dirty = false
		_list = [{ "kind": "keyboard", "key": "kb", "name": "Keyboard", "id": -1, "guid": "kb", "preset": "kb_full" }]
		_list.append_array(gamepads())
		_list.append_array(sim_devices())
		_list.append_array(test_devices)
	return _list


func find(key: String) -> Dictionary:
	for d: Dictionary in list():
		if d.key == key:
			return d
	return {}


## Non-gamepad devices (wheels, pedals, shifters...), from noss_core.
func sim_devices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not native_ok:
		return out
	var seen := {}
	for d: Dictionary in NossInput.devices():
		if d.gamepad and not d.wheel:
			continue
		var e := d.duplicate()
		e.kind = "sim"
		e.key = "sim:%s#%d" % [d.guid, seen.get(d.guid, 0)]
		seen[d.guid] = seen.get(d.guid, 0) + 1
		e.preset = Bindings.preset_for_device("sim", int(d.vendor), int(d.product))
		out.append(e)
	return out


## Godot joypads with a known gamepad mapping that aren't sim devices.
func gamepads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sim := sim_devices().map(func(d: Dictionary) -> String: return "%d:%d" % [d.vendor, d.product])
	var seen := {}
	for pad in Input.get_connected_joypads():
		var info := Input.get_joy_info(pad)
		var vendor := int(info.get("vendor_id", -1))
		var product := int(info.get("product_id", -2))
		if not Input.is_joy_known(pad) or "%d:%d" % [vendor, product] in sim:
			continue
		var guid := Input.get_joy_guid(pad)
		out.append({
			"kind": "gamepad", "key": "pad:%s#%d" % [guid, seen.get(guid, 0)], "name": Input.get_joy_name(pad),
			"id": pad, "guid": guid, "vendor": vendor, "product": product,
			"preset": Bindings.preset_for_device("gamepad", vendor, product),
		})
		seen[guid] = seen.get(guid, 0) + 1
	return out
