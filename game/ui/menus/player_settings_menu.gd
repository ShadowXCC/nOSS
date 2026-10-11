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
	theme = UiKit.theme_for(self)
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
	for item: Array in [["abs", "ABS", "Brakes without locking"], ["tcs", "Traction control", "No wheelspin"],
			["stability", "Stability control", "Brakes single wheels to stop slides"], ["auto_gearbox", "Auto gearbox", ""],
			["steer_aid", "Steer aid", "Keyboard and controller: less lock at speed, help to catch slides"]]:
		var key: String = item[0]
		_add(rows, UiKit.check(item[1], d.assists.get(key, key != "stability"), func(on: bool) -> void: profile.set_assist(key, on), item[2]))

	_section(rows, "Comfort")
	_add(rows, UiKit.slider("Camera shake", d.camera_shake, func(v: float) -> void: profile.set_value("camera_shake", v)))
	_add(rows, UiKit.slider("Head movement", d.head_movement, func(v: float) -> void: profile.set_value("head_movement", v)))
	_add(rows, UiKit.check("Speed FOV", d.speed_fov, func(on: bool) -> void: profile.set_value("speed_fov", on)))
	_add(rows, UiKit.check("Horizon lock", d.horizon_lock, func(on: bool) -> void: profile.set_value("horizon_lock", on)))

	_section(rows, "Display")
	_add(rows, UiKit.number("HUD size", d.hud_scale * 100.0, 50, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("hud_scale", v / 100.0)))
	_add(rows, UiKit.number("Menu text", d.text_scale * 100.0, 100, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("text_scale", v / 100.0)))
	_add(rows, UiKit.check("High-contrast HUD", d.high_contrast, func(on: bool) -> void: profile.set_value("high_contrast", on)))
	_add(rows, UiKit.spinner("Font", FONTS, d.font, func(v: String) -> void: profile.set_value("font", v), "Clear: an easy-to-read font"))
	_add(rows, UiKit.number("Brightness", d.brightness * 100.0, 50, 150, 5, "%d%%", func(v: float) -> void: profile.set_value("brightness", v / 100.0)))

	_section(rows, "Vision")
	_add(rows, UiKit.spinner("Colours", Palette.PRESET_NAMES, d.palette, func(v: String) -> void:
		var was := String(profile.data.palette)
		profile.set_value("palette", v)
		if v == "custom" or was == "custom":
			_rebuild_at.call_deferred("Colours"), "Colourblind palettes"))
	if d.palette == "custom":
		for role: Array in [["good", "Good"], ["bad", "Bad"], ["line_fast", "Line: fast"], ["line_brake", "Line: brake"]]:
			var key: String = role[0]
			_add(rows, UiKit.color("  " + role[1], Palette.color(profile, key), func(c: Color) -> void:
				var custom: Dictionary = profile.data.palette_custom
				custom[key] = "#" + c.to_html(false)
				profile.save()))
	_add(rows, UiKit.check("Reduce flashing", d.reduce_flashing, func(on: bool) -> void: profile.set_value("reduce_flashing", on), "At most 3 flashes a second, lower contrast"))
	_add(rows, UiKit.spinner("Narration", [["off", "Off"], ["menus", "Menus"], ["race", "Menus and race"]], d.narration,
		func(v: String) -> void: profile.set_value("narration", v), "Reads menus and race events aloud"))
	_add(rows, UiKit.number("Speech rate", d.narration_rate * 100.0, 50, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("narration_rate", v / 100.0)))
	_add(rows, UiKit.spinner("Spotter", [["off", "Off"], ["markers", "Markers"], ["voice", "Voice"]], d.spotter,
		func(v: String) -> void: profile.set_value("spotter", v), "Car left, car right, clear"))

	_section(rows, "Hearing")
	_add(rows, UiKit.check("Captions", d.captions, func(on: bool) -> void: profile.set_value("captions", on), "Spoken lines as text"))
	_add(rows, UiKit.check("Shift light", d.shift_light, func(on: bool) -> void: profile.set_value("shift_light", on)))
	_add(rows, UiKit.check("Slip indicator", d.slip_indicator, func(on: bool) -> void: profile.set_value("slip_indicator", on), "Tire icons light up when sliding"))
	_add(rows, UiKit.check("Close-car arrows", d.sound_arrows, func(on: bool) -> void: profile.set_value("sound_arrows", on), "Arrows at the screen edge"))

	_section(rows, "HUD")
	_add(rows, UiKit.spinner("HUD", [["full", "Full"], ["minimal", "Minimal"], ["off", "Off"]], d.hud_preset,
		func(v: String) -> void: profile.set_value("hud_preset", v)))
	for element: Array in Hud.ELEMENTS:
		var id: String = element[0]
		_add(rows, UiKit.check("Show " + String(element[1]).to_lower(), id not in d.hud_hidden, func(on: bool) -> void:
			var hidden: Array = profile.data.hud_hidden
			hidden.erase(id)
			if not on:
				hidden.append(id)
			profile.save()))

	_section(rows, "Pacing")
	_add(rows, UiKit.number("Game speed", d.game_speed * 100.0, 50, 100, 5, "%d%%", func(v: float) -> void: profile.set_value("game_speed", v / 100.0),
		"One player only. Slower laps don't go on leaderboards"))

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


## Builds the menu again (rows came or went) with focus back on the row named `prefix`.
func _rebuild_at(prefix: String) -> void:
	_build()
	await get_tree().process_frame
	for c: Control in _rows:
		var target := UiKit._focus_target(c)
		if target and String(target.accessibility_name).begins_with(prefix):
			target.grab_focus()
			return


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
