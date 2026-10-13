class_name TrackPicker
extends Control
## Picks a track (EDT-07): built-in ones, then the player's own (TrackLibrary), each as "Name ·
## 2.5 km · author", with a map of the one in focus. Directions and confirm are enough.

signal picked(path: String)
signal closed

## The track to start on (a path); else the last one picked.
var current := ""
var title := "Track"
## Only tracks of this type ("circuit", "highway").
var type := "circuit"
var _preview: TrackMap
var _buttons: Array = []
var _maps := {} # path -> TrackData (centreline only)


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if current.is_empty():
		current = Game.selected_track(type)
	var list := UiKit.panel(self, title, 1180)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	list.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	row.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_preview = TrackMap.new()
	_preview.custom_minimum_size = Vector2(420, 420)
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_preview)
	var first: Button
	for e in TrackLibrary.list(true, true, type):
		var path: String = e.path
		var b := UiKit.button(TrackLibrary.label(e), func() -> void: _pick(path), "Built in" if e.builtin else "Your track")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_entered.connect(_show.bind(path))
		rows.add_child(b)
		_buttons.append(b)
		if path == current or first == null:
			first = b
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_buttons.append(back)
	UiKit.chain_focus(_buttons, false)
	if first:
		UiKit.focus_later(first)


func grab_focus_first() -> void:
	if not _buttons.is_empty():
		(_buttons[0] as Control).grab_focus()


func _pick(path: String) -> void:
	Settings.profile.last_track = path
	picked.emit(path)


## The focused track's map (its centreline, loaded once).
func _show(path: String) -> void:
	if not _maps.has(path):
		var pkg := TrackLoader.load_package(path, {}, { "terrain": false })
		_maps[path] = pkg.track if pkg.ok() else null
	_preview.track = _maps[path]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
