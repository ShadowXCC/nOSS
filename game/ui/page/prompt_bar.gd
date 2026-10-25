class_name PromptBar
extends HBoxContainer
## What the buttons do on a page (docs/UI_FLOW.md §4): each entry the glyphs of its inputs, then
## its label. The glyphs are the last-used device's: the main window's (Devices.last_family), or
## in a player's view that player's own (PlayerSlot.glyph_family(), their bindings). Confirm and
## cancel are always there; on a spinner or slider left/right "Change" joins them, and on a text
## field confirm reads "Type".

const GLYPH_SIZE := 40
const LABEL_SIZE := 26

## Entries besides those: [what, label], `what` a key of Glyphs.ACTIONS ("tabs").
var extra: Array = []

var _shown := ""


func _init() -> void:
	name = "PromptBar"
	alignment = BoxContainer.ALIGNMENT_END
	custom_minimum_size = Vector2(0, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override(&"separation", 32)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var slot := _slot()
	var family := slot.glyph_family() if slot else Devices.last_family
	var list := entries()
	# Rebuilt only when what it shows changes: a family, a focus kind, a player's last device.
	var key := "%s|%s|%s" % [family, list, _device_key(slot)]
	if key != _shown:
		_shown = key
		_rebuild(list, family, slot)


## What the bar shows for the focus now: [[what, label]].
func entries() -> Array:
	var focus := UiKit.focus_owner(self) if is_inside_tree() else null
	var out := [["confirm", "Type" if focus is LineEdit else "Select"]]
	if focus and (focus.has_meta(&"spinner") or focus is Range):
		out.append(["change", "Change"])
	out.append_array(extra)
	out.append(["cancel", "Back"])
	return out


func _rebuild(list: Array, family: String, slot: PlayerSlot) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for entry: Array in list:
		var inputs := Glyphs.inputs(String(entry[0]), family, slot)
		if inputs.is_empty():
			continue
		var group := HBoxContainer.new()
		group.name = String(entry[0]).capitalize()
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_theme_constant_override(&"separation", 10)
		for input in inputs:
			var icon := Glyphs.icon(input, family, GLYPH_SIZE)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			group.add_child(icon)
		var l := UiKit.label(String(entry[1]), LABEL_SIZE)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(l)
		add_child(group)


## The player whose view this is in (null: the main window).
func _slot() -> PlayerSlot:
	var vp := get_viewport() if is_inside_tree() else null
	var view := vp.get_parent() as PlayerView if vp else null
	return view.slot if view else null


static func _device_key(slot: PlayerSlot) -> String:
	if slot == null:
		return ""
	var d := slot.input.menu_device()
	return "%s:%s:%s" % [d.get("kind", ""), d.get("id", ""), slot.input.preset_of(d) if not d.is_empty() else ""]
