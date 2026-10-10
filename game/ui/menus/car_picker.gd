class_name CarPicker
extends Control
## Lists the cars the player can drive: official content and the garage
## (docs/VEHICLE_PACKAGE.md §8). Used before a session and for hotswap mid-drive.

signal picked(path: String)
signal closed

var current := ""
## Only cars that can mount this platform are listed (empty: all).
var platform := {}


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Choose car", 820)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var buttons: Array = []
	for path in PackageLoader.list_available():
		var m := PackageLoader.read_manifest(path)
		if not platform.is_empty() and not Fitting.compatible(platform, m.get("family", "")):
			continue
		var title: String = m.get("name", path.get_file())
		var license: String = m.get("license", "")
		var b := UiKit.button(title + ("  •" if path == current else ""), func() -> void: picked.emit(path),
			"%s, by %s" % [license, m.get("author", "unknown")])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rows.add_child(b)
		buttons.append(b)
	if buttons.is_empty():
		rows.add_child(UiKit.label("No cars found"))
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	buttons.append(back)
	UiKit.chain_focus(buttons)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("hotswap_menu"):
		get_viewport().set_input_as_handled()
		closed.emit()
