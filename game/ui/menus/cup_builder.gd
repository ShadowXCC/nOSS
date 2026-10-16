class_name CupBuilder
extends Control
## Make or change a cup (D145): its name, four tracks (any circuit) and the laps of each. Saved to
## user://cups/; the built-in ones can't be changed here. Every control is named and in the focus
## order.

## The cup was saved (its file).
signal saved(path: String)
signal closed

## The cup being made ({} for a new one).
var cup := {}
var _rows: Array = []
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if cup.is_empty():
		cup = { "schema": CupRun.SCHEMA, "id": "", "name": "My cup", "races": [] }
	var tracks := TrackLibrary.list(true, true, "circuit")
	var races: Array = cup.races
	while races.size() < 4:
		races.append({ "track": String(tracks[races.size() % maxi(tracks.size(), 1)].id) if not tracks.is_empty() else "", "laps": 3 })
	_list = UiKit.panel(self, "Cup", 900)
	_add(UiKit.text_field("Name", String(cup.name), func(t: String) -> void: cup.name = t.strip_edges(), 40))
	# By id (it survives the track being changed), or by its content when the id won't do.
	var plain := RegEx.create_from_string("^[a-z0-9_]{1,64}$")
	var choices := tracks.map(func(e: Dictionary) -> Array:
		return [String(e.id) if plain.search(String(e.id)) else String(e.hash), TrackLibrary.label(e)])
	var laps := []
	for n in range(1, 11):
		laps.append([n, "%d" % n])
	for i in 4:
		var race: Dictionary = races[i]
		var known := choices.any(func(c: Array) -> bool: return c[0] == race.track)
		var these := choices if known else [[String(race.track), "Track missing"]] + choices
		_add(UiKit.spinner("Race %d" % (i + 1), these, String(race.track), func(v: String) -> void: race.track = v))
		_add(UiKit.spinner("Race %d laps" % (i + 1), laps, clampi(int(race.laps), 1, 10), func(v: int) -> void: race.laps = v))
	_status = UiKit.label("", 24)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	_list.add_child(_status)
	_add(UiKit.button("Save", _save, "Keep it in your cups"))
	_add(UiKit.button("Back", func() -> void: closed.emit(), "Without saving"))
	UiKit.chain_focus(_rows)


func _add(c: Control) -> void:
	_list.add_child(c)
	_rows.append(c)


func _save() -> void:
	var why := CupRun.save(cup)
	if why:
		_status.text = why
		return
	saved.emit(CupRun.user_dir + String(cup.id) + ".cup.json")


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
