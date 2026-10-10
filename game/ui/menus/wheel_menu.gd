class_name WheelMenu
extends Control
## Wheel setup (docs/INPUT.md §5-6): pick the device, set its rotation range, detect the
## steering and pedal axes by moving them, tune force feedback and test it.

signal closed

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
var _snapshot := PackedFloat32Array()
var _extreme := PackedFloat32Array()


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cfg = WheelInput.DEFAULTS.duplicate()
	_cfg.merge(Settings.profile.get("wheel", {}), true)
	var list := UiKit.panel(self, "Wheel", 980)
	if not Devices.native_ok:
		list.add_child(UiKit.label("Wheel support off: SDL3 not found"))
	_devices = Devices.sim_devices()

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
			Devices.save_wheel(_cfg)))
	_add(list, UiKit.slider("FFB strength", _cfg.ffb_gain, func(v: float) -> void: _set_value("ffb_gain", v)))
	_add(list, UiKit.slider("FFB damping", _cfg.ffb_damper, func(v: float) -> void: _set_value("ffb_damper", v)))
	_add(list, UiKit.slider("FFB min force", _cfg.ffb_min / 0.3, func(v: float) -> void: _set_value("ffb_min", v * 0.3)))
	_add(list, UiKit.check("Invert FFB", _cfg.ffb_invert, func(on: bool) -> void: _set_value("ffb_invert", on)))
	_add(list, UiKit.button("Test FFB", func() -> void:
		if Devices.wheel.device_id >= 0:
			NossInput.ffb_test(Devices.wheel.device_id)))
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
	Devices.save_wheel(_cfg)


func _on_device(index: int) -> void:
	if index == 0:
		_cfg.erase("guid")
		_cfg.erase("steer")
	else:
		var d: Dictionary = _devices[index - 1]
		_cfg.guid = d.guid
		_cfg.name = d.name
		if not _cfg.get("steer") is Dictionary:
			_cfg.steer = { "axis": 0, "center": 0.0 }
	Devices.save_wheel(_cfg)


func _start_detect(which: String) -> void:
	var id := Devices.wheel.device_id
	if id < 0:
		_status.text = "Pick a device first"
		return
	_detecting = which
	_detect_time = 0.0
	var count := _axis_count(id)
	_snapshot.resize(count)
	_extreme.resize(count)
	for i in count:
		_snapshot[i] = NossInput.axis(id, i)
		_extreme[i] = _snapshot[i]
	_status.text = "Turn the wheel from centre to full lock" if which == "steer" else "Press %s fully, then release" % which


func _process(delta: float) -> void:
	var w := Devices.wheel
	if w.is_active():
		_live.text = "Steer %+.2f   Throttle %.2f   Brake %.2f   Clutch %.2f   FFB %d%%" % [w.steer(), w.throttle(), w.brake(), w.clutch(), roundi(NossInput.ffb_peak(w.device_id) * 100.0)]
	if _detecting.is_empty():
		return
	_detect_time += delta
	var id := w.device_id
	for i in _snapshot.size():
		var v := NossInput.axis(id, i)
		if absf(v - _snapshot[i]) > absf(_extreme[i] - _snapshot[i]):
			_extreme[i] = v
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
	elif _detecting == "steer":
		_cfg.steer = { "axis": best, "center": _snapshot[best], "invert": false }
		_status.text = "Steering: axis %d" % best
	else:
		_cfg[_detecting] = { "axis": best, "rest": _snapshot[best], "full": _extreme[best] }
		_status.text = "%s: axis %d" % [_detecting.capitalize(), best]
	_detecting = ""
	Devices.save_wheel(_cfg)


func _axis_count(id: int) -> int:
	for d: Dictionary in Devices.sim_devices():
		if d.id == id:
			return d.axes
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if _detecting.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
