class_name ClassPicker
extends Control
## Lists the platform classes of every mode (docs/PLATFORMS.md §6). The class decides how the
## car drives; the car picked next only decides how it looks.

signal picked(platform_id: String)
signal closed

var current := ""
## Only classes that take this kind of car (empty: all).
var family := ""


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Choose class", 820)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var buttons: Array = []
	var first: Button
	for mode in GameModes.list():
		var heading := UiKit.label(mode.name, 26)
		heading.modulate = UiKit.ACCENT
		rows.add_child(heading)
		var classes := GameModes.classes(mode).filter(func(r: PlatformLoader.Result) -> bool: return family.is_empty() or Fitting.compatible(r.platform, family))
		if classes.is_empty():
			heading.queue_free()
			continue
		for result: PlatformLoader.Result in classes:
			var p := result.platform
			var info := GameModes.describe(p)
			var b := UiKit.button("%s   %s%s" % [p.name, info, "  •" if p.id == current else ""],
				func() -> void: picked.emit(p.id), "%s class: %s" % [mode.name, info])
			b.accessibility_name = "%s %s" % [mode.name, p.name]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rows.add_child(b)
			buttons.append(b)
			if p.id == current:
				first = b
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	buttons.append(back)
	UiKit.chain_focus(buttons)
	if first:
		first.grab_focus.call_deferred()


## Focus back on the list after a submenu closes.
func grab_focus_first() -> void:
	var buttons := find_children("*", "Button", true, false)
	if not buttons.is_empty():
		(buttons[0] as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
