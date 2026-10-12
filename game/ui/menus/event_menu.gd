class_name EventMenu
extends Control
## Sets up a race weekend (docs/GAMEMODES.md §1): sessions, race length, the AI field and the
## rules. Every choice is a spinner (left and right), so directions and confirm are enough
## (docs/ACCESSIBILITY.md §5.1). The last setup is remembered.

signal picked(event: RaceEvent)
signal closed

var event: RaceEvent
var _rows: Array = []
var _length_row: Button


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if event == null:
		event = Settings.last_event()
	event.kind = "race"
	var list := UiKit.panel(self, "Race", 860)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	_add(rows, UiKit.spinner("Track", [["proving_ground", "Proving Ground"]], "proving_ground", func(_v: Variant) -> void: pass))
	_add(rows, UiKit.spinner("Practice", _minutes([0, 5, 10, 15, 30]), event.practice_min, func(v: int) -> void: event.practice_min = v))
	_add(rows, UiKit.spinner("Qualifying", _minutes([0, 5, 10, 15]), event.qualifying_min, func(v: int) -> void: event.qualifying_min = v))
	_add(rows, UiKit.spinner("Race length", [["laps", "Laps"], ["time", "Time"]], "time" if event.race_min > 0 else "laps", func(v: String) -> void:
		event.race_min = 10 if v == "time" else 0
		_rebuild_length()))
	_length_row = _length_spinner()
	_add(rows, _length_row)
	var counts := []
	for n in 16:
		counts.append([n, "%d" % n])
	_add(rows, UiKit.spinner("AI cars", counts, event.ai_count, func(v: int) -> void: event.ai_count = v))
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	_add(rows, UiKit.spinner("AI skill", skills, snappedf(event.ai_skill, 5.0), func(v: float) -> void: event.ai_skill = v))
	_add(rows, UiKit.spinner("AI cars look", [["garage", "Garage"], ["builtin", "Built-in"]], event.ai_cars, func(v: String) -> void: event.ai_cars = v))
	_add(rows, UiKit.spinner("Start", [["standing", "Standing"], ["rolling", "Rolling"]], event.start, func(v: String) -> void: event.start = v))
	_add(rows, UiKit.spinner("Grid", [["qualifying", "Qualifying"], ["reverse", "Reverse"], ["random", "Random"]], event.grid, func(v: String) -> void: event.grid = v))
	_add(rows, UiKit.spinner("Collisions", [[true, "On"], [false, "Ghosted"]], event.collisions, func(v: bool) -> void: event.collisions = v))
	_add(rows, UiKit.spinner("Track limits", [["off", "Off"], ["lenient", "Lenient"], ["strict", "Strict"]], event.track_limits, func(v: String) -> void: event.track_limits = v))

	var next := UiKit.button("Next", func() -> void:
		Settings.set_last_event(event)
		picked.emit(event), "Choose players and cars")
	list.add_child(next)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(next)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


func _length_spinner() -> Button:
	if event.race_min > 0:
		var items := []
		for m in [5, 10, 15, 20, 30, 45, 60]:
			items.append([m, "%d min" % m])
		return UiKit.spinner("Race", items, event.race_min, func(v: int) -> void: event.race_min = v)
	var laps := []
	for n in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50]:
		laps.append([n, "%d lap%s" % [n, "" if n == 1 else "s"]])
	return UiKit.spinner("Race", laps, event.race_laps, func(v: int) -> void: event.race_laps = v)


## Laps and time swap the length row in place.
func _rebuild_length() -> void:
	var at := _rows.find(_length_row)
	var fresh := _length_spinner()
	_length_row.add_sibling(fresh)
	_length_row.queue_free()
	_length_row = fresh
	_rows[at] = fresh
	UiKit.chain_focus(_rows)
	fresh.grab_focus.call_deferred()


## Focus back on the list after a submenu closes.
func grab_focus_first() -> void:
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus()


static func _minutes(values: Array) -> Array:
	return values.map(func(m: int) -> Array: return [m, "Off" if m == 0 else "%d min" % m])


func _unhandled_input(e: InputEvent) -> void:
	# Hidden behind the Players screen: back belongs to that one.
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
