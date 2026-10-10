class_name SettingsMenu
extends Control
## Settings (M1): graphics preset, units, display, volume, comfort options (ACC-04),
## assists and keyboard bindings. Changes apply and save immediately.

signal closed

var _rows: Array = []
var _rebinding := ""
var _rebind_button: Button


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Settings", 980)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var p: Dictionary = Settings.profile

	_section(rows, "Game")
	_add(rows, UiKit.option("Graphics", [["low", "Low"], ["medium", "Medium"], ["high", "High"]], Settings.graphics,
		func(v: String) -> void: Settings.set_value("graphics", v)))
	_add(rows, UiKit.option("Units", [["metric", "km/h"], ["imperial", "mph"]], Settings.units,
		func(v: String) -> void: Settings.set_value("units", v)))
	_add(rows, UiKit.check("Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.set_value("fullscreen", on)))
	_add(rows, UiKit.slider("Volume", Settings.master_volume, func(v: float) -> void: Settings.set_value("master_volume", v)))

	_section(rows, "Comfort")
	_add(rows, UiKit.slider("Camera shake", p.camera_shake, func(v: float) -> void: Settings.set_value("camera_shake", v)))
	_add(rows, UiKit.slider("Head movement", p.head_movement, func(v: float) -> void: Settings.set_value("head_movement", v)))
	_add(rows, UiKit.check("Speed FOV", p.speed_fov, func(on: bool) -> void: Settings.set_value("speed_fov", on)))
	_add(rows, UiKit.check("Horizon lock", p.horizon_lock, func(on: bool) -> void: Settings.set_value("horizon_lock", on)))

	_section(rows, "Assists")
	for item: Array in [["abs", "ABS"], ["tcs", "Traction control"], ["auto_gearbox", "Auto gearbox"], ["steer_aid", "Steer aid"]]:
		var key: String = item[0]
		_add(rows, UiKit.check(item[1], p.assists.get(key, true), func(on: bool) -> void: Settings.set_assist(key, on)))

	_section(rows, "Wheel")
	_add(rows, UiKit.button("Wheel setup", _open_wheel, "Device, axes, rotation and force feedback"))

	_section(rows, "Controller")
	_add(rows, UiKit.slider("Stick deadzone", p.pad_deadzone / 0.4, func(v: float) -> void: Settings.set_value("pad_deadzone", v * 0.4)))

	_section(rows, "Keyboard")
	for action: String in Bindings.DRIVING:
		var row := HBoxContainer.new()
		var l := UiKit.label(Bindings.ACTIONS[action].name)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = _key_label(action)
		b.accessibility_name = "%s: %s" % [Bindings.ACTIONS[action].name, b.text]
		b.accessibility_description = "Press, then press a key"
		b.custom_minimum_size = Vector2(300, 56)
		b.pressed.connect(_start_rebind.bind(action, b))
		row.add_child(b)
		_add(rows, row)
	_add(rows, UiKit.button("Reset keys", func() -> void:
		Settings.primary.data.input.bindings.erase("kb_full")
		_save_keys()))

	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _open_wheel() -> void:
	var menu := WheelMenu.new()
	var panel_nodes := get_children()
	for child in panel_nodes:
		if child is CanvasItem:
			child.visible = false
	menu.closed.connect(func() -> void:
		menu.queue_free()
		for child in panel_nodes:
			if child is CanvasItem:
				child.visible = true
		UiKit.chain_focus(_rows))
	add_child(menu)


func _section(parent: Control, text: String) -> void:
	var l := UiKit.label(text, 34)
	l.add_theme_color_override("font_color", UiKit.ACCENT)
	parent.add_child(l)


func _add(parent: Control, control: Control) -> void:
	parent.add_child(control)
	_rows.append(control)


func _start_rebind(action: String, b: Button) -> void:
	_rebinding = action
	_rebind_button = b
	b.text = "Press a key"


func _refresh_bindings() -> void:
	for row in _rows:
		if row is HBoxContainer and row.get_child_count() == 2 and row.get_child(1) is Button:
			var b: Button = row.get_child(1)
			for action: String in Bindings.DRIVING:
				if row.get_child(0).text == Bindings.ACTIONS[action].name:
					b.text = _key_label(action)
					b.accessibility_name = "%s: %s" % [Bindings.ACTIONS[action].name, b.text]


func _input(event: InputEvent) -> void:
	if _rebinding.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode != KEY_ESCAPE:
		var overrides: Dictionary = Settings.primary.data.input.bindings.get("kb_full", {}).duplicate(true)
		overrides[_rebinding] = [{ "key": event.physical_keycode }]
		Settings.primary.data.input.bindings["kb_full"] = overrides
		_save_keys()
	_rebinding = ""
	_refresh_bindings()


## P1's keys on the whole keyboard (kb_full).
func _key_label(action: String) -> String:
	var map := Bindings.effective("kb_full", Settings.primary.data.input.bindings.get("kb_full", {}))
	return Bindings.refs_label(map.get(action, []), "keyboard")


func _save_keys() -> void:
	Settings.primary.save()
	Players.refresh_all()
	_refresh_bindings()


func _unhandled_input(event: InputEvent) -> void:
	if _rebinding.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
