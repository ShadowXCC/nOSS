class_name WheelMenu
extends Control
## Wheel setup for one player (docs/INPUT.md §5-6): pick the device, set its rotation range,
## detect the steering and pedal axes by moving them (on any of the player's sim devices, so
## separate pedals work), tune force feedback and test it. Saved in the player's profile.

signal closed

## Whose wheel; default P1.
var slot: PlayerSlot

const ROTATIONS := [270, 360, 540, 720, 900, 1080]
const DETECT_S := 4.0

var _cfg := {}
var _rows: Array = []
var _status: Label
var _live: Label
var _device_option: OptionButton
var _devices: Array = []
var _detecting := ""
var _detect_time := 0.0
var _sims: Array = []
var _snapshot := PackedFloat32Array()
var _extreme := PackedFloat32Array()


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if slot == null:
		slot = Players.primary_slot()
	_cfg = slot.input.wheel.config.duplicate(true)
	var list := UiKit.panel(self, "Wheel", 980)
	if not Devices.native_ok:
		list.add_child(UiKit.label("Wheel support off: SDL3 not found"))
	_devices = _sim_devices()

	var row := HBoxContainer.new()
	var l := UiKit.label("Device")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_device_option = OptionButton.new()
	_device_option.accessibility_name = "Device"
	_device_option.custom_minimum_size = Vector2(460, 56)
	_device_option.add_item("None", 0)
	for i in _devices.size():
		var d: Dictionary = _devices[i]
		_device_option.add_item("%s%s" % [d.name, "  (FFB)" if d.ffb else ""], i + 1)
		if d.guid == _cfg.get("guid", ""):
			_device_option.select(i + 1)
	_device_option.item_selected.connect(_on_device)
	row.add_child(_device_option)
	_add(list, row)

	_add(list, UiKit.option("Rotation", ROTATIONS.map(func(r: int) -> Array: return [float(r), "%d°" % r]), float(_cfg.rotation_deg),
		func(v: float) -> void: _set_value("rotation_deg", v)))
	for item: Array in [["steer", "Detect steering"], ["throttle", "Detect throttle"], ["brake", "Detect brake"], ["clutch", "Detect clutch"]]:
		var which: String = item[0]
		_add(list, UiKit.button(item[1], func() -> void: _start_detect(which), "Move it fully, then let go"))
	_add(list, UiKit.check("Invert steering", _cfg.get("steer", {}).get("invert", false), func(on: bool) -> void:
		if _cfg.get("steer") is Dictionary:
			_cfg.steer.invert = on
			_save()))
	_add(list, UiKit.slider("FFB strength", _cfg.ffb_gain, func(v: float) -> void: _set_value("ffb_gain", v)))
	_add(list, UiKit.slider("FFB damping", _cfg.ffb_damper, func(v: float) -> void: _set_value("ffb_damper", v)))
	_add(list, UiKit.slider("FFB min force", _cfg.ffb_min / 0.3, func(v: float) -> void: _set_value("ffb_min", v * 0.3)))
	_add(list, UiKit.check("Invert FFB", _cfg.ffb_invert, func(on: bool) -> void: _set_value("ffb_invert", on)))
	_add(list, UiKit.button("Test FFB", func() -> void:
		if slot.input.wheel.device_id >= 0:
			NossInput.ffb_test(slot.input.wheel.device_id)))
	_status = UiKit.label("")
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	list.add_child(_status)
	_live = UiKit.label("", 24)
	list.add_child(_live)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _add(parent: Control, control: Control) -> void:
	parent.add_child(control)
	_rows.append(control)


func _set_value(key: String, value: Variant) -> void:
	_cfg[key] = value
	_save()


func _save() -> void:
	slot.profile.set_value("wheel", _cfg.duplicate(true))
	slot.refresh(Devices.list())


## The player's sim devices, then free ones (picking a free one claims it).
func _sim_devices() -> Array:
	var out := slot.input.devices.filter(func(d: Dictionary) -> bool: return d.kind == "sim")
	out.append_array(Players.free_devices().filter(func(d: Dictionary) -> bool: return d.kind == "sim"))
	return out


func _on_device(index: int) -> void:
	if index == 0:
		_cfg.erase("guid")
		_cfg.erase("steer")
	else:
		var d: Dictionary = _devices[index - 1]
		if Players.owner_of(d.key) == null:
			Players.add_device(slot, d)
		_cfg.guid = d.guid
		_cfg.name = d.name
		if not _cfg.get("steer") is Dictionary:
			_cfg.steer = { "axis": 0, "center": 0.0 }
	_save()


func _start_detect(which: String) -> void:
	_sims = slot.input.devices.filter(func(d: Dictionary) -> bool: return d.kind == "sim")
	if _sims.is_empty():
		_status.text = "Pick a device first"
		return
	_detecting = which
	_detect_time = 0.0
	_snapshot.clear()
	for d: Dictionary in _sims:
		for i in int(d.axes):
			_snapshot.append(NossInput.axis(d.id, i))
	_extreme = _snapshot.duplicate()
	_status.text = "Turn the wheel from centre to full lock" if which == "steer" else "Press %s fully, then release" % which


func _process(delta: float) -> void:
	var w := slot.input.wheel
	if w.is_active():
		_live.text = "Steer %+.2f   Throttle %.2f   Brake %.2f   Clutch %.2f   FFB %d%%" % [w.steer(), w.throttle(), w.brake(), w.clutch(), roundi(NossInput.ffb_peak(w.device_id) * 100.0)]
	if _detecting.is_empty():
		return
	_detect_time += delta
	var n := 0
	for d: Dictionary in _sims:
		for i in int(d.axes):
			var v := NossInput.axis(d.id, i)
			if absf(v - _snapshot[n]) > absf(_extreme[n] - _snapshot[n]):
				_extreme[n] = v
			n += 1
	if _detect_time < DETECT_S:
		return
	var best := -1
	var best_move := 0.15
	for i in _snapshot.size():
		var move := absf(_extreme[i] - _snapshot[i])
		if move > best_move:
			best_move = move
			best = i
	if best < 0:
		_status.text = "Nothing moved"
	else:
		# Which device and axis the best one was.
		var device: Dictionary = {}
		var axis := best
		for d: Dictionary in _sims:
			if axis < int(d.axes):
				device = d
				break
			axis -= int(d.axes)
		if _detecting == "steer":
			_cfg.guid = device.guid
			_cfg.name = device.name
			_cfg.steer = { "axis": axis, "center": _snapshot[best], "invert": false, "guid": device.guid }
			_status.text = "Steering: axis %d" % axis
		else:
			_cfg[_detecting] = { "axis": axis, "rest": _snapshot[best], "full": _extreme[best], "guid": device.guid }
			_status.text = "%s: axis %d%s" % [_detecting.capitalize(), axis, "" if device.guid == _cfg.get("guid", "") else " on " + String(device.name)]
	_detecting = ""
	_save()


func _unhandled_input(event: InputEvent) -> void:
	if _detecting.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
