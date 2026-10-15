class_name FreeDriveMenu
extends Control
## Sets up a free drive (docs/GAMEMODES.md §1, MODE-01): the track, AI cars driving laps beside
## the players (how many, their skill, which cars), collisions and track limits. Every choice is
## a spinner (left and right), so directions and confirm are enough (docs/ACCESSIBILITY.md §5.1).
## The last setup is remembered.

signal picked(event: RaceEvent, track: String)
signal closed

var event: RaceEvent
var _rows: Array = []
var _track := ""


## The last free drive set up, or the defaults (no AI).
static func last() -> RaceEvent:
	var d: Variant = Settings.profile.get("last_free")
	var e := RaceEvent.from_dict(d) if d is Dictionary else RaceEvent.free_drive()
	e.kind = "free"
	return e


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if event == null:
		event = last()
	var list := UiKit.panel(self, "Free Drive", 860)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	_track = Game.selected_track("circuit")
	var tracks := TrackLibrary.list(true, true, "circuit").map(func(e: Dictionary) -> Array: return [e.path, TrackLibrary.label(e)])
	_add(rows, UiKit.spinner("Track", tracks, _track, func(path: String) -> void:
		_track = path
		Settings.profile.last_track = path))
	var counts := []
	for n in 16:
		counts.append([n, "Off" if n == 0 else "%d" % n])
	_add(rows, UiKit.spinner("AI cars", counts, event.ai_count, func(v: int) -> void: event.ai_count = v, "They drive laps with you"))
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	_add(rows, UiKit.spinner("AI skill", skills, snappedf(event.ai_skill, 5.0), func(v: float) -> void: event.ai_skill = v))
	_add(rows, UiKit.spinner("AI cars look", [["garage", "Garage"], ["builtin", "Built-in"]], event.ai_cars, func(v: String) -> void: event.ai_cars = v))
	_add(rows, UiKit.spinner("Collisions", [[true, "On"], [false, "Ghosted"]], event.collisions, func(v: bool) -> void: event.collisions = v))
	_add(rows, UiKit.spinner("Track limits", [["off", "Off"], ["lenient", "Lenient"], ["strict", "Strict"]], event.track_limits,
		func(v: String) -> void: event.track_limits = v, "Cutting the track spoils a timed lap"))

	var next := UiKit.button("Next", func() -> void:
		event.kind = "free"
		Settings.set_value("last_free", event.to_dict())
		picked.emit(event, _track), "Choose players and cars")
	list.add_child(next)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(next)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


## Focus back on the list after a submenu closes.
func grab_focus_first() -> void:
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	# Hidden behind the Players screen: back belongs to that one.
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
