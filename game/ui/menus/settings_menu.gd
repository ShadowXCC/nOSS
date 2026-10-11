class_name SettingsMenu
extends Control
## Game settings, shared by everyone on this machine: graphics, units, display, volume and
## splitscreen. Each player's own settings (assists, comfort, HUD, controls) live in their
## profile (PlayerSettingsMenu), reached from here, the Players screen and the pause menu.
## Changes apply and save immediately.

signal closed

## Opened in a player's view mid-session: no profile management (renaming needs a keyboard).
var in_session := false

var _rows: Array = []


func _ready() -> void:
	theme = UiKit.theme_for(self)
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

	_section(rows, "Game")
	_add(rows, UiKit.option("Graphics", [["low", "Low"], ["medium", "Medium"], ["high", "High"]], Settings.graphics,
		func(v: String) -> void: Settings.set_value("graphics", v)))
	_add(rows, UiKit.option("Units", [["metric", "km/h"], ["imperial", "mph"]], Settings.units,
		func(v: String) -> void: Settings.set_value("units", v)))
	_add(rows, UiKit.check("Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.set_value("fullscreen", on)))

	_section(rows, "Sound")
	_add(rows, UiKit.slider("Volume", Settings.master_volume, func(v: float) -> void: Settings.set_value("master_volume", v)))
	for item: Array in [["vol_own_engine", "Own engine"], ["vol_other_engines", "Other engines"], ["vol_tires", "Tires and wind"],
			["vol_effects", "Effects"], ["vol_ambience", "Ambience"], ["vol_music", "Music"], ["vol_ui", "Menus"],
			["vol_spotter", "Spotter voice"], ["vol_narration", "Narration"]]:
		var key: String = item[0]
		_add(rows, UiKit.slider(item[1], float(Settings.get(key)), func(v: float) -> void: Settings.set_value(key, v)))
	_add(rows, UiKit.check("Mono", Settings.mono, func(on: bool) -> void: Settings.set_value("mono", on), "Everything in both ears"))

	_section(rows, "Splitscreen")
	_add(rows, UiKit.spinner("2 players", [["stacked", "One above the other"], ["side", "Side by side"]], Settings.split_two,
		func(v: String) -> void: Settings.set_value("split_two", v)))
	_add(rows, UiKit.spinner("3 players", [["wide", "Wide top"], ["map", "With track map"]], Settings.split_three,
		func(v: String) -> void: Settings.set_value("split_three", v)))
	_add(rows, UiKit.spinner("Sound from", [["all", "Every player"], ["p1", "P1 only"]], Settings.split_audio,
		func(v: String) -> void: Settings.set_value("split_audio", v)))
	_add(rows, UiKit.check("Auto resolution", Settings.auto_resolution, func(on: bool) -> void: Settings.set_value("auto_resolution", on)))

	if not in_session:
		_section(rows, "Players")
		_add(rows, UiKit.button("Player settings", _open_player, "%s: controls, assists, HUD" % Settings.primary.display_name()))
		_add(rows, UiKit.button("Profiles", _open_profiles, "Rename, add or delete players"))

	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _open_player() -> void:
	var menu := PlayerSettingsMenu.new()
	menu.profile = Settings.primary
	menu.slot = Players.slots[0] if not Players.slots.is_empty() and Players.slots[0].profile == Settings.primary else null
	UiKit.open_sub(self, menu, func() -> void: UiKit.chain_focus(_rows))


func _open_profiles() -> void:
	UiKit.open_sub(self, ProfilesMenu.new(), func() -> void: UiKit.chain_focus(_rows))


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
