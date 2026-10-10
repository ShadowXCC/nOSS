class_name PlayerSettingsMenu
extends Control
## One player's settings, saved in their profile and following them (docs/ACCESSIBILITY.md,
## ACC-01, ACC-02, ACC-04, ACC-06): assists, comfort, HUD and text, and controls (presets, hold
## or toggle, menu repeat, stick deadzone, rebinding, wheel). Changes apply right away.

signal closed

const KEYBOARD := [["kb_full", "Whole"], ["kb_left", "Left side"], ["kb_right", "Right side"]]
const FONTS := [["retro", "Game"], ["clear", "Clear"]]

var profile: PlayerProfile
## The player whose devices rebinding and wheel setup use; null: every device.
var slot: PlayerSlot

var _rows: Array = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if profile == null:
		profile = slot.profile if slot else Settings.primary
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	var list := UiKit.panel(self, "Settings  ·  " + profile.display_name(), 980)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var d: Dictionary = profile.data

	_section(rows, "Assists")
	for item: Array in [["abs", "ABS"], ["tcs", "Traction control"], ["auto_gearbox", "Auto gearbox"], ["steer_aid", "Steer aid"]]:
		var key: String = item[0]
		_add(rows, UiKit.check(item[1], d.assists.get(key, true), func(on: bool) -> void: profile.set_assist(key, on)))

	_section(rows, "Comfort")
	_add(rows, UiKit.slider("Camera shake", d.camera_shake, func(v: float) -> void: profile.set_value("camera_shake", v)))
	_add(rows, UiKit.slider("Head movement", d.head_movement, func(v: float) -> void: profile.set_value("head_movement", v)))
	_add(rows, UiKit.check("Speed FOV", d.speed_fov, func(on: bool) -> void: profile.set_value("speed_fov", on)))
	_add(rows, UiKit.check("Horizon lock", d.horizon_lock, func(on: bool) -> void: profile.set_value("horizon_lock", on)))

	_section(rows, "Display")
	_add(rows, UiKit.number("HUD size", d.hud_scale * 100.0, 50, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("hud_scale", v / 100.0)))
	_add(rows, UiKit.number("Menu text", d.text_scale * 100.0, 100, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("text_scale", v / 100.0)))
	_add(rows, UiKit.check("High-contrast HUD", d.high_contrast, func(on: bool) -> void: profile.set_value("high_contrast", on)))
	_add(rows, UiKit.spinner("Font", FONTS, d.font, func(v: String) -> void: profile.set_value("font", v)))
	_add(rows, UiKit.number("Brightness", d.brightness * 100.0, 50, 150, 5, "%d%%", func(v: float) -> void: profile.set_value("brightness", v / 100.0)))

	_section(rows, "Controls")
	if slot == null or slot.keyboard_zone() in ["", "full"]:
		_add(rows, UiKit.spinner("Keyboard", KEYBOARD, d.input.presets.keyboard, func(v: String) -> void: _set_input("presets", "keyboard", v)))
	_add(rows, UiKit.spinner("Controller", Bindings.presets_for("gamepad"), d.input.presets.gamepad, func(v: String) -> void: _set_input("presets", "gamepad", v)))
	_add(rows, UiKit.slider("Stick deadzone", d.pad_deadzone / 0.4, func(v: float) -> void:
		profile.set_value("pad_deadzone", v * 0.4)
		Players.refresh_all()))
	for action: String in Bindings.HOLD:
		_add(rows, UiKit.check("Toggle " + String(Bindings.ACTIONS[action].name).to_lower(), action in d.input.toggles, func(on: bool) -> void:
			var toggles: Array = profile.data.input.toggles
			toggles.erase(action)
			if on:
				toggles.append(action)
			profile.save()))
	_add(rows, UiKit.number("Menu repeat after", d.input.menu_delay, 0.2, 1.0, 0.05, "%.2f s", func(v: float) -> void: _set_input("", "menu_delay", v)))
	_add(rows, UiKit.number("Menu repeat speed", d.input.menu_rate, 4, 20, 1, "%d / s", func(v: float) -> void: _set_input("", "menu_rate", v)))
	_add(rows, UiKit.button("Buttons and keys", _open_bindings, "Rebind every action"))
	if slot:
		_add(rows, UiKit.button("Wheel setup", _open_wheel, "Device, axes, rotation and force feedback"))

	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _set_input(group: String, key: String, value: Variant) -> void:
	if group:
		profile.data.input[group][key] = value
	else:
		profile.data.input[key] = value
	profile.save()
	Players.refresh_all()


func _open_bindings() -> void:
	var menu := BindingsMenu.new()
	menu.profile = profile
	menu.slot = slot
	UiKit.open_sub(self, menu, func() -> void: UiKit.chain_focus(_rows))


func _open_wheel() -> void:
	var menu := WheelMenu.new()
	menu.slot = slot
	UiKit.open_sub(self, menu, func() -> void: UiKit.chain_focus(_rows))


func _section(parent: Control, text: String) -> void:
	var l := UiKit.label(text, 34)
	l.add_theme_color_override("font_color", UiKit.ACCENT)
	parent.add_child(l)


func _add(parent: Control, control: Control) -> void:
	parent.add_child(control)
	_rows.append(control)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and get_child_count() > 0 and get_child(0).visible:
		get_viewport().set_input_as_handled()
		closed.emit()
