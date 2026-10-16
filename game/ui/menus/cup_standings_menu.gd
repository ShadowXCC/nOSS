class_name CupStandingsMenu
extends Control
## A cup's table between its races (D145): place, driver, points, wins, and this race's place;
## then on to the next race, or after the last, the podium. Each row is one focusable line whose
## accessible name reads it whole. Any device can use it.

signal next_race
signal quit_to_title

var run: CupRun
var _rows: Array = []


func _ready() -> void:
	theme = UiKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var final := run.done()
	var title := "%s · %s" % [String(run.cup.name), "Final" if final else "After race %d of %d" % [run.index, run.races().size()]]
	var list := UiKit.panel(self, title, 1100)
	var table := run.standings()
	if final and not table.is_empty():
		var podium := PackedStringArray()
		for i in mini(3, table.size()):
			podium.append("%s %s" % [["1st", "2nd", "3rd"][i], String(table[i].name)])
		var top := UiKit.label("  ·  ".join(podium), 34)
		top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
		list.add_child(top)
	var head := _line(["Pos", "Driver", "Points", "Wins", "Last race"])
	head.modulate = UiKit.ACCENT
	list.add_child(head)
	for i in table.size():
		var t: Dictionary = table[i]
		var places: Array = t.places
		var last := "P%d" % int(places.back()) if not places.is_empty() else "-"
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, 48)
		b.add_child(_line(["%d" % (i + 1), String(t.name), str(t.points), str(t.wins), last]))
		b.accessibility_name = "%d, %s, %d points, %d %s, last race %s" % [i + 1, t.name, int(t.points), int(t.wins), "win" if int(t.wins) == 1 else "wins", last]
		list.add_child(b)
		_rows.append(b)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_child(buttons)
	var controls: Array = []
	if not final:
		var next_track := TrackLibrary.entry(run.track_for(run.index))
		controls.append(UiKit.button("Next race: %s" % String(next_track.get("name", "?")), func() -> void: next_race.emit(),
			"Race %d of %d, %d laps" % [run.index + 1, run.races().size(), int(run.races()[run.index].laps)]))
	controls.append(UiKit.button("Title", func() -> void: quit_to_title.emit(), "Leave the cup" if not final else "Back to the title screen"))
	for c: Button in controls:
		c.custom_minimum_size.x = 340
		buttons.add_child(c)
	UiKit.chain_focus(controls + _rows)


func row_text(i: int) -> String:
	return (_rows[i] as Button).accessibility_name if i < _rows.size() else ""


func _line(cells: Array) -> HBoxContainer:
	var widths := [90, 420, 160, 120, 200]
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in cells.size():
		var l := UiKit.label(String(cells[i]), 26)
		l.custom_minimum_size = Vector2(widths[i], 0)
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled() # stays up until a choice is made
