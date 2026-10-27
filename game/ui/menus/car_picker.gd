class_name CarPicker
extends Control
## Lists the cars the player can drive: official content and the garage
## (docs/VEHICLE_PACKAGE.md §8). Used before a session and for hotswap mid-drive. It opens on the
## current car, and the list scrolls to follow the focus.

signal picked(path: String)
signal closed

var current := ""
## Only cars that can mount this platform are listed (empty: all).
var platform := {}
## Online: personal-use cars aren't listed (they never leave this machine).
var online := false


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Choose car", 820)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	UiKit.keep_in_view(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var buttons: Array = []
	var on_current: Button
	var hidden := 0
	for path in PackageLoader.list_available():
		var m := PackageLoader.read_manifest(path)
		if not platform.is_empty() and not Fitting.compatible(platform, m.get("family", "")):
			continue
		if online and not ContentIndex.shareable(m):
			hidden += 1
			continue
		var title: String = m.get("name", path.get_file())
		var license: String = m.get("license", "")
		var b := UiKit.button(title + ("  •" if path == current else ""), func() -> void: picked.emit(path),
			"%s, by %s" % [license, m.get("author", "unknown")])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = GarageFiles.thumbnail(path)
		if b.icon:
			b.expand_icon = true
			b.custom_minimum_size = Vector2(0, 96)
		rows.add_child(b)
		buttons.append(b)
		if path == current:
			on_current = b
	if buttons.is_empty():
		rows.add_child(UiKit.label("No cars found"))
	if hidden:
		list.add_child(UiKit.label("Personal-use cars stay offline (%d)" % hidden, 22))
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	buttons.append(back)
	UiKit.chain_focus(buttons, false)
	UiKit.focus_later(on_current if on_current else buttons[0])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("hotswap_menu"):
		get_viewport().set_input_as_handled()
		closed.emit()
