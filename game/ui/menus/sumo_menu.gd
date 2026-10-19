class_name SumoMenu
extends Control
## Sumo Wrestling (docs/GAMEMODES.md §5, D162): the platforms, what's under them and how they
## shrink, then the players, who each pick their car. There is no track to choose — the arena is
## built from these settings. Every choice is a spinner or a button, named and in the focus
## order; the last setup is remembered.

signal picked(event: RaceEvent)
signal closed

const TIERS := [[1, "1"], [2, "2"], [3, "3"]]
const HAZARDS := [["lava", "Lava"], ["acid", "Acid"]]
const SHRINKS := [["smooth", "Smooth"], ["crumble", "Crumbling"], ["stepped", "Stepped"]]
const LENGTHS := [[60, "Short"], [90, "Normal"], [150, "Long"]]

var event := RaceEvent.sumo()
var _rows: Array = []
var _list: VBoxContainer


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var last: Variant = Settings.profile.get("last_sumo")
	if last is Dictionary:
		event = RaceEvent.from_dict(last)
		event.kind = "sumo"
	_list = UiKit.panel(self, "Sumo Wrestling", 860)
	_build()


func _build(focus := "") -> void:
	for c: Control in _rows:
		c.queue_free()
	_rows.clear()
	_add(UiKit.spinner("Platforms", TIERS, clampi(event.sumo_tiers, 1, 3), func(v: int) -> void:
		event.sumo_tiers = v, "Stacked, each wider than the one above: a fall is a second chance"))
	_add(UiKit.spinner("Underneath", HAZARDS, event.sumo_hazard, func(v: String) -> void:
		event.sumo_hazard = v, "Touch it and you're out"))
	_add(UiKit.spinner("Shrink", SHRINKS, event.sumo_shrink, func(v: String) -> void:
		event.sumo_shrink = v, "Smooth: the edge creeps in. Crumbling or Stepped: a ring at a time"))
	_add(UiKit.spinner("Length", LENGTHS, _nearest_length(), func(v: int) -> void:
		event.sumo_secs = v, "How long one platform takes to shrink away"))
	_add(UiKit.spinner("Sudden death", [[false, "Off"], [true, "On"]], event.sumo_pillar, func(v: bool) -> void:
		event.sumo_pillar = v, "The last platform stops at a pillar instead of going altogether"))
	_add(UiKit.spinner("AI cars", _range(0, 11), clampi(event.ai_count, 0, 11), func(v: int) -> void: event.ai_count = v))
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	_add(UiKit.spinner("AI skill", skills, snappedf(event.ai_skill, 5.0), func(v: float) -> void: event.ai_skill = v))
	_add(UiKit.spinner("AI models", [["garage", "Garage"], ["builtin", "Built-in"]], event.ai_cars, func(v: String) -> void:
		event.ai_cars = v, "Garage: bots bring your own cars too"))
	for row in SkyRows.rows(event):
		_add(row)
	_add(UiKit.button("Next", _next, "The players: each picks a car"))
	_add(UiKit.button("Back", func() -> void: closed.emit()))
	UiKit.chain_focus(_rows, focus.is_empty())
	for c: Control in _rows:
		if focus and String(c.accessibility_name).get_slice(":", 0) == focus:
			UiKit.focus_later(c)


## The offered length nearest the one saved, so an older setup still lands on a row.
func _nearest_length() -> int:
	var best: int = LENGTHS[0][0]
	for l: Array in LENGTHS:
		if absi(int(l[0]) - event.sumo_secs) < absi(best - event.sumo_secs):
			best = int(l[0])
	return best


func _add(c: Control) -> void:
	_list.add_child(c)
	_rows.append(c)


func _range(from: int, to: int) -> Array:
	var out := []
	for n in range(from, to + 1):
		out.append([n, "%d" % n])
	return out


func _next() -> void:
	var e := RaceEvent.sumo(event.sumo_tiers, event.sumo_hazard)
	e.sumo_shrink = event.sumo_shrink
	e.sumo_secs = event.sumo_secs
	e.sumo_pillar = event.sumo_pillar
	e.ai_count = event.ai_count
	e.ai_skill = event.ai_skill
	e.ai_cars = event.ai_cars
	e.time = event.time
	e.time_rate = event.time_rate
	e.weather = event.weather
	Settings.set_value("last_sumo", e.to_dict())
	picked.emit(e)


func grab_focus_first() -> void:
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
