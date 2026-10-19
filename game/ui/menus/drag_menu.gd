class_name DragMenu
extends Control
## Drag Strip (docs/GAMEMODES.md §6, D168): the class, the strip's length, the bottles and which
## of the mini-game's rules are on, then the players, who each pick their car. There is no track
## to choose — the strip is built from these settings. Every choice is a spinner or a button,
## named and in the focus order; the last setup is remembered.

## `class_id` is the drag class the field drives: everyone in a match is in the same one.
signal picked(event: RaceEvent, class_id: String)
signal closed

const CLASSES := [
	["official.drag.street", "Street", "6 gears, 265 kW: five shifts to time"],
	["official.drag.pro", "Pro", "5 gears, 470 kW: four shifts, and it bites"],
	["official.drag.top_fuel", "Top Fuel", "4 gears, 620 kW: three shifts, no mistakes"],
]
const BOOSTS := [[0, "Off"], [1, "1"], [2, "2"], [3, "3"]]
const ON_OFF := [[true, "On"], [false, "Off"]]
## Each length in metres, with its name in miles and in metres (Settings.units picks).
const LENGTHS := [[201, "1/8 mile", "201 m"], [402, "1/4 mile", "402 m"], [805, "1/2 mile", "805 m"]]

var event := RaceEvent.drag()
var class_id := CLASSES[0][0]
var _rows: Array = []
var _list: VBoxContainer
## The settings scroll and the rows inside it. There are too many settings for one screen, so
## they scroll; `follow_focus` brings the focused row into view, which is how a controller or a
## keyboard scrolls it. Next and Back stay outside, always on screen.
var _scroll: ScrollContainer
var _box: VBoxContainer
## The section labels; not focusable, so they are kept apart from `_rows`.
var _headings: Array = []


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var last: Variant = Settings.profile.get("last_drag")
	if last is Dictionary:
		event = RaceEvent.from_dict(last)
		event.kind = "drag"
	var saved: Variant = Settings.profile.get("last_drag_class")
	if saved is String and _known_class(String(saved)):
		class_id = String(saved)
	_list = UiKit.panel(self, "Drag Strip", 880)
	_scroll = ScrollContainer.new()
	# UiKit.panel shrinks this to the room there is (a small splitscreen view, big text).
	_scroll.custom_minimum_size = Vector2(0, 620)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_list.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	_build()


func _build(focus := "") -> void:
	for c: Control in _rows + _headings:
		c.queue_free()
	_rows.clear()
	_headings.clear()
	_add(UiKit.spinner("Class", _class_items(), class_id, func(v: String) -> void:
		class_id = v, "Everyone runs the same class, whatever model they bring"))
	_add(UiKit.spinner("Length", _length_items(), _nearest_length(), func(v: int) -> void:
		event.drag_length_m = v, "Start line to the lights; the shutdown is as long again"))
	_add(UiKit.spinner("Boost", BOOSTS, clampi(event.drag_boost, 0, 3), func(v: int) -> void:
		event.drag_boost = v, "Bottles each driver gets, spent whenever they like"))
	_add(UiKit.spinner("Timing shifts", ON_OFF, event.drag_timing, func(v: bool) -> void:
		event.drag_timing = v, "Shift in the window on the tach for a surge, miss it and bog"))
	_add(UiKit.spinner("Quick time events", ON_OFF, event.drag_qtes, func(v: bool) -> void:
		event.drag_qtes = v, "The burnout, the two-step and catching a shake"))
	_section("Gimmicks")
	_add(UiKit.spinner("Christmas tree", ON_OFF, event.drag_tree, func(v: bool) -> void:
		event.drag_tree = v, "Stage, three ambers, green: your reaction is timed, and leaving early is a red light"))
	_add(UiKit.spinner("Two-step", ON_OFF, event.drag_two_step, func(v: bool) -> void:
		event.drag_two_step = v, "Hold the revs in the band on the line, and launch as the light goes green"))
	_add(UiKit.spinner("Burnout", ON_OFF, event.drag_burnout, func(v: bool) -> void:
		event.drag_burnout = v, "Heat the tires before the pass; cook them and you lose the grip"))
	_add(UiKit.spinner("Tire shake", ON_OFF, event.drag_shake, func(v: bool) -> void:
		event.drag_shake = v, "A spinning launch opens a moment to feather it"))
	_add(UiKit.spinner("Shift chain", ON_OFF, event.drag_chain, func(v: bool) -> void:
		event.drag_chain = v, "Perfect shifts in a row build the surge; a bad one breaks it"))
	_add(UiKit.spinner("Money shift", ON_OFF, event.drag_money_shift, func(v: bool) -> void:
		event.drag_money_shift = v, "Sitting on the limiter loses power, and in the end the engine"))
	_add(UiKit.spinner("Centreline", [[true, "Foul"], [false, "Forgiving"]], event.drag_centreline, func(v: bool) -> void:
		event.drag_centreline = v, "Foul: cross it and the pass is lost"))
	_section("Field")
	_add(UiKit.spinner("AI cars", _range(0, 15), clampi(event.ai_count, 0, 15), func(v: int) -> void: event.ai_count = v,
		"The ladder draws everyone into pairs; two run each pass"))
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	_add(UiKit.spinner("AI skill", skills, snappedf(event.ai_skill, 5.0), func(v: float) -> void: event.ai_skill = v))
	_add(UiKit.spinner("AI models", [["garage", "Garage"], ["builtin", "Built-in"]], event.ai_cars, func(v: String) -> void:
		event.ai_cars = v, "Garage: bots bring your own cars too"))
	for row in SkyRows.rows(event):
		_add(row)
	# Outside the scroll, so they are there whatever the settings are scrolled to.
	for b: Button in [UiKit.button("Next", _next, "The players: each picks a car"),
			UiKit.button("Back", func() -> void: closed.emit())]:
		_list.add_child(b)
		_rows.append(b)
	UiKit.chain_focus(_rows, focus.is_empty())
	for c: Control in _rows:
		if focus and String(c.accessibility_name).get_slice(":", 0) == focus:
			UiKit.focus_later(c)


func _class_items() -> Array:
	var out := []
	for c: Array in CLASSES:
		out.append([c[0], c[1]])
	return out


## The lengths named the way this player reads distances.
func _length_items() -> Array:
	var imperial := String(Settings.units) == "imperial"
	var out := []
	for l: Array in LENGTHS:
		out.append([l[0], l[1] if imperial else l[2]])
	return out


## The offered length nearest the one saved, so an older setup still lands on a row.
func _nearest_length() -> int:
	var best: int = LENGTHS[0][0]
	for l: Array in LENGTHS:
		if absi(int(l[0]) - event.drag_length_m) < absi(best - event.drag_length_m):
			best = int(l[0])
	return best


func _known_class(id: String) -> bool:
	for c: Array in CLASSES:
		if String(c[0]) == id:
			return true
	return false


## A heading over the rows that follow. Not focusable, so it stays out of the focus chain, and
## each row below it is named in full for a screen reader anyway.
func _section(title: String) -> void:
	var l := UiKit.label(title, 24)
	l.modulate = UiKit.ACCENT
	_box.add_child(l)
	_headings.append(l)


func _add(c: Control) -> void:
	_box.add_child(c)
	_rows.append(c)


func _range(from: int, to: int) -> Array:
	var out := []
	for n in range(from, to + 1):
		out.append([n, "%d" % n])
	return out


func _next() -> void:
	var e := RaceEvent.drag(_nearest_length(), event.drag_boost)
	for key: String in RaceEvent.DRAG_KEYS:
		e.set(key, event.get(key))
	e.ai_count = event.ai_count
	e.ai_skill = event.ai_skill
	e.ai_cars = event.ai_cars
	e.time = event.time
	e.time_rate = event.time_rate
	e.weather = event.weather
	Settings.set_value("last_drag", e.to_dict())
	Settings.set_value("last_drag_class", class_id)
	picked.emit(e, class_id)


func grab_focus_first() -> void:
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
