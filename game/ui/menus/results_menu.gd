class_name ResultsMenu
extends Control
## Session results (docs/GAMEMODES.md §1 "Results"; ACC-07): position, driver, car, time or gap,
## best lap, laps, penalties and the assists each player drove with. Each row is one focusable
## line whose accessible name reads the whole row, so a screen reader can step through them.
## Shown on the main window; any device can use it.

signal continued
signal restarted
signal quit_to_title

## "race", "qualifying" or "practice".
var kind := "race"
## RaceControl.results rows.
var results: Array = []
var has_next := false
## "Qualifying", "Race"... for the Continue button.
var next_name := ""

var _rows: Array = []

## Short names for results, in this order.
const ASSIST_NAMES := { "abs": "ABS", "tcs": "TCS", "stability": "SC", "auto_gearbox": "Auto",
	"steer_aid": "Aid", "auto_throttle": "AT", "brake_assist": "BA", "steering_assist": "SA", "autodrive": "Auto drive" }


func _ready() -> void:
	theme = UiKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var title: String = { "race": "Race results", "qualifying": "Qualifying", "practice": "Practice" }.get(kind, "Results")
	var list := UiKit.panel(self, title, 1500)
	var head := _line(["Pos", "Driver", "Car", "Time" if kind == "race" else "Best", "Gap", "Laps", "Pen", "Assists"])
	head.modulate = UiKit.ACCENT
	list.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for row: Dictionary in results:
		var b := _row_button(row)
		rows.add_child(b)
		_rows.append(b)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_child(buttons)
	var controls: Array = []
	if has_next:
		controls.append(UiKit.button("Continue: %s" % next_name, func() -> void: continued.emit()))
	controls.append(UiKit.button("Restart", func() -> void: restarted.emit(), "Run this session again"))
	controls.append(UiKit.button("Title", func() -> void: quit_to_title.emit(), "Back to the title screen"))
	for c: Button in controls:
		c.custom_minimum_size.x = 280
		buttons.add_child(c)
	# Focus starts on the first button; the rows come after it, so a screen reader hears the
	# winner straight after the choices.
	UiKit.chain_focus(controls + _rows)
	_link_buttons(controls)


## The driver's own row, for screen readers and tests.
func row_text(i: int) -> String:
	return (_rows[i] as Button).accessibility_name if i < _rows.size() else ""


func _row_button(row: Dictionary) -> Button:
	var r: Racer = row.racer
	var time := Hud.format_time(row.time) if kind == "race" else Hud.format_time(row.best)
	if kind == "race" and row.dnf:
		time = "DNF"
	var assists := assists_text(r)
	var cells := ["P%d" % row.position, "%s%s" % ["#%d " % row.number if not r.is_human else "", row.name], row.car,
		time, row.gap, str(row.laps), "+%ds" % roundi(row.penalty) if row.penalty > 0.0 else "", assists]
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 52)
	b.add_child(_line(cells))
	var spoken := "P%d, %s, %s, %s%s, best %s, %d laps%s%s" % [
		row.position, row.name, row.car, time, (", " + String(row.gap)) if row.gap != "" else "",
		Hud.format_time(row.best), row.laps,
		", penalty %d seconds" % roundi(row.penalty) if row.penalty > 0.0 else "",
		", assists: " + assists if assists != "" else ""]
	b.accessibility_name = spoken
	if r.is_human:
		b.add_theme_stylebox_override("normal", UiKit._box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 6))
	return b


## Short list of the driving assists a player used ("ABS TCS Auto"); AI shows "AI".
static func assists_text(r: Racer) -> String:
	if not r.is_human:
		return "AI"
	var used := PackedStringArray()
	for key: String in ASSIST_NAMES:
		if r.assists_used.get(key, false):
			used.append(ASSIST_NAMES[key])
	return " ".join(used)


func _line(cells: Array) -> HBoxContainer:
	var widths := [90, 330, 360, 170, 150, 80, 80, 200]
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


## The buttons sit side by side: left and right move between them too.
func _link_buttons(controls: Array) -> void:
	for i in controls.size():
		var c: Control = controls[i]
		c.focus_neighbor_left = c.get_path_to(controls[(i - 1 + controls.size()) % controls.size()])
		c.focus_neighbor_right = c.get_path_to(controls[(i + 1) % controls.size()])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled() # results stay up until a choice is made
