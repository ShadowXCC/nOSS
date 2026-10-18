class_name BindingsMenu
extends Control
## Rebinding for one player (INP-06, docs/INPUT.md §7): every action on each of their devices,
## menus included. Pick an action, then press the new key or button on that device within a
## few seconds. Saved in the profile per preset (or per wheel/pedal device); the preset gives
## the rest. On a shared keyboard, the other player's keys can't be taken.

signal closed

const CAPTURE_S := 5.0

var profile: PlayerProfile
## Whose devices; null: every connected device (editing a profile from the shared settings).
var slot: PlayerSlot

var _devices_input: PlayerInput
var _device := 0
var _rows: Array = []
var _status: Label
var _capturing := ""
var _capture_time := 0.0
var _focus_index := 0


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if slot:
		_devices_input = slot.input
		profile = slot.profile
	else:
		_devices_input = PlayerInput.new()
		_devices_input.profile = profile
		for d in Devices.list():
			var e := d.duplicate()
			if e.kind == "keyboard":
				e.zone = "full"
			_devices_input.devices.append(e)
		_devices_input.rebuild()
	_build()


func _build() -> void:
	# Freed after this frame: the button that asked for the rebuild may still be signalling.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows.clear()
	var list := UiKit.panel(self, "Buttons and keys", 980)
	if _devices_input.devices.is_empty():
		list.add_child(UiKit.label("No device"))
		var back0 := UiKit.button("Back", func() -> void: closed.emit())
		list.add_child(back0)
		UiKit.chain_focus([back0])
		return
	_device = clampi(_device, 0, _devices_input.devices.size() - 1)
	var items := []
	for i in _devices_input.devices.size():
		var dev: Dictionary = _devices_input.devices[i]
		items.append([i, _device_name(dev)])
	_rows.append(UiKit.spinner("Device", items, _device, func(i: int) -> void:
		_device = i
		_focus_index = 0
		_build.call_deferred()))
	list.add_child(_rows[0])

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var d: Dictionary = _devices_input.devices[_device]
	var map := _map(d)
	var kind: String = d.kind
	for action: String in Bindings.DRIVING + Bindings.MENU:
		if action == Bindings.KART[0]:
			rows.add_child(UiKit.label("Kart", 24)) # its actions share inputs kart ignores (D135)
		if action == Bindings.SUMO[0]:
			rows.add_child(UiKit.label("Sumo", 24)) # a sumo match has no items, so Ram may share that
		var refs: Array = map.get(action, [])
		var label := Bindings.refs_label(refs, kind)
		var dupes := _also(map, action)
		var b := UiKit.button("%s     %s%s" % [Bindings.ACTIONS[action].name, label, ("   (also %s)" % dupes) if dupes else ""],
			_start_capture.bind(action), "Press, then press the new key or button")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.accessibility_name = "%s: %s" % [Bindings.ACTIONS[action].name, label]
		rows.add_child(b)
		_rows.append(b)
	_status = UiKit.label("Wheel and pedal axes: Wheel setup" if kind == "sim" else "", 24)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	list.add_child(_status)
	var reset := UiKit.button("Reset this device", func() -> void:
		profile.data.input.bindings.erase(_key(d))
		_save())
	list.add_child(reset)
	_rows.append(reset)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)
	if _focus_index > 0 and _focus_index < _rows.size():
		(_rows[_focus_index] as Control).grab_focus.call_deferred()


func _device_name(d: Dictionary) -> String:
	if d.kind == "keyboard":
		return "Keyboard" + ({ "left": " (left side)", "right": " (right side)" }.get(String(d.get("zone", "full")), ""))
	return String(d.name)


func _key(d: Dictionary) -> String:
	return PlayerInput.override_key(d, _devices_input.preset_of(d))


func _map(d: Dictionary) -> Dictionary:
	return Bindings.effective(_devices_input.preset_of(d), profile.data.input.bindings.get(_key(d), {}))


## Other actions on this device bound to the same input.
func _also(map: Dictionary, action: String) -> String:
	var names := PackedStringArray()
	for other: String in map:
		if other == action or (Bindings.MENU.has(other) != Bindings.MENU.has(action)):
			continue # driving and menu bindings live side by side
		for r: Dictionary in map[other]:
			if r in map.get(action, []):
				names.append(Bindings.ACTIONS[other].name)
				break
	return ", ".join(names)


func _start_capture(action: String) -> void:
	_capturing = action
	_capture_time = 0.0
	_focus_index = _rows.find(UiKit.focus_owner(self))
	_devices_input.capture_start()
	if slot:
		slot.menu_target = null # the press is the binding, not navigation
	get_viewport().gui_release_focus()
	_status.text = "Press the new input for %s" % String(Bindings.ACTIONS[action].name).to_lower()


func _process(delta: float) -> void:
	if _capturing.is_empty():
		return
	_capture_time += delta
	var d: Dictionary = _devices_input.devices[_device]
	var got := _devices_input.capture_poll()
	if not got.is_empty() and (got.kind != d.kind or (d.kind == "sim" and got.get("guid", "") != d.guid)):
		got = {} # another of the player's devices
	if got.is_empty():
		if _capture_time >= CAPTURE_S:
			_end_capture()
			_status.text = "Nothing pressed"
		return
	var overrides: Dictionary = profile.data.input.bindings.get(_key(d), {}).duplicate(true)
	overrides[_capturing] = [got.ref]
	profile.data.input.bindings[_key(d)] = overrides
	_end_capture()
	_save()


func _end_capture() -> void:
	_capturing = ""
	_devices_input.settle() # the key just pressed isn't also a menu press
	if slot:
		slot.menu_target = get_viewport()
	if _focus_index >= 0 and _focus_index < _rows.size():
		(_rows[_focus_index] as Control).grab_focus()


func _save() -> void:
	profile.save()
	Players.refresh_all()
	if slot == null:
		_devices_input.rebuild()
	_build()


func _input(event: InputEvent) -> void:
	if _capturing and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		get_viewport().set_input_as_handled() # shared menus: keys go to the capture only


func _unhandled_input(event: InputEvent) -> void:
	if _capturing.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
