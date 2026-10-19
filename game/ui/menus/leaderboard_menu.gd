class_name LeaderboardMenu
extends Control
## A local leaderboard for this track and class (docs/GAMEMODES.md §8): fastest laps (or runs)
## with driver, car and assists, or the most points (score attack). Each line is focusable and
## reads in full to a screen reader.

signal closed

var entries: Array = []
var title := ""
## Points, not times (a score attack board).
var scores := false


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Leaderboard", 1000)
	if title:
		var sub := UiKit.label(title, 26)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var focusable: Array = []
	if entries.is_empty():
		rows.add_child(UiKit.label("No scores yet" if scores else "No laps yet"))
	for i in entries.size():
		var e: Dictionary = entries[i]
		var assists := " ".join(PackedStringArray(e.get("assists", [])))
		var road := String(e.get("road", "dry")) # a wet or snowy lap is tagged (D153)
		var value := "%d points" % int(e.score) if scores else Hud.format_time(float(e.time))
		var text := "%d   %s   %s   %s%s%s" % [i + 1, value, e.get("name", "?"), e.get("car", ""), "   " + road.capitalize() if road != "dry" else "",
			"   " + assists if assists else ""]
		var b := UiKit.button(text, func() -> void: pass)
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.accessibility_name = "%d, %s, %s, %s%s%s" % [i + 1, value, e.get("name", "?"), e.get("car", ""), ", %s road" % road if road != "dry" else "",
			", assists: " + assists if assists else ""]
		rows.add_child(b)
		focusable.append(b)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	UiKit.chain_focus([back] + focusable)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
