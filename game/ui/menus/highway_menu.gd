class_name HighwayMenu
extends Control
## A highway event (docs/GAMEMODES.md §3, MODE-03, MODE-04): the sub-mode (Cruise, Score attack,
## Run, Loop), the traffic, the police, which way round to start (named from the track: clockwise
## or anticlockwise, or both ways in turn), and for a run, which one. Every control is named and in
## the focus order; the last settings are remembered.

signal picked(event: RaceEvent)
signal closed

const SUBS := [["cruise", "Cruise"], ["score", "Score attack"], ["run", "Run"], ["loop", "Loop"]]
const TRAFFIC := [[0, "Off"], [75, "75"], [150, "150"], [250, "250"], [400, "400"]]

## The highway track it's for.
var track_path := ""
var event := RaceEvent.highway("cruise", false, -1)
var _rows: Array = []
var _list: VBoxContainer
var _track: TrackData


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var pkg := TrackLoader.load_package(track_path, {}, { "terrain": false })
	_track = pkg.track if pkg.ok() else null
	var last: Variant = Settings.profile.get("last_highway")
	if last is Dictionary:
		event = RaceEvent.from_dict(last)
		event.kind = "highway"
	if event.traffic < 0 and _track and _track.highway:
		event.traffic = int(_track.highway.settings.traffic.count)
	_list = UiKit.panel(self, "Highway", 820)
	if _track:
		var sub := UiKit.label(_track.display_name, 26)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(sub)
	_build()


func _build(focus := "") -> void:
	for c: Control in _rows:
		c.queue_free()
	_rows.clear()
	_add(UiKit.spinner("Mode", SUBS, event.sub, func(v: String) -> void:
		var was := event.sub
		event.sub = v
		if (v == "run") != (was == "run"):
			_build.call_deferred("Mode"), "Cruise: no score. Score attack: near misses. Run: a sprint. Loop: lap times"))
	var counts := TRAFFIC.duplicate()
	if not counts.any(func(c: Array) -> bool: return c[0] == event.traffic):
		counts.append([event.traffic, str(event.traffic)])
	_add(UiKit.spinner("Traffic", counts, event.traffic, func(v: int) -> void: event.traffic = v, "Cars on the road"))
	_add(UiKit.spinner("Police", [[false, "Off"], [true, "On"]], event.police, func(v: bool) -> void: event.police = v,
		"Speed traps; speed, near misses and crashes in their sight bring a chase"))
	if event.sub == "run":
		var runs := _runs()
		if runs.is_empty():
			_add(UiKit.label("This track has no runs.", 24))
		else:
			if not runs.any(func(r: Array) -> bool: return r[0] == event.run):
				event.run = String(runs[0][0])
			_add(UiKit.spinner("Run", runs, event.run, func(v: String) -> void: event.run = v, "Which stretch"))
	else:
		_add(UiKit.spinner("Way round", _ways(), event.direction, func(v: int) -> void: event.direction = v,
			"Which carriageway you start on; both ways: players take turns"))
	_add(UiKit.button("Next", _next, "Pick the class"))
	_add(UiKit.button("Back", func() -> void: closed.emit()))
	UiKit.chain_focus(_rows, focus.is_empty())
	for c: Control in _rows:
		if focus and String(c.accessibility_name).get_slice(":", 0) == focus:
			UiKit.focus_later(c)


func _add(c: Control) -> void:
	_list.add_child(c)
	_rows.append(c)


## [[id, "Name · 2.1 km, clockwise"]] for the track's runs.
func _runs() -> Array:
	var out := []
	if _track == null or _track.highway == null:
		return out
	for r: Dictionary in _track.highway.runs:
		var length := fposmod(int(r.dir) * (float(r.to_m) - float(r.from_m)), _track.length)
		out.append([String(r.id), "%s · %.1f km, %s" % [r.name, length / 1000.0, _way(int(r.dir)).to_lower()]])
	return out


func _ways() -> Array:
	return [[1, _way(1)], [-1, _way(-1)], [0, "Both ways"]]


func _way(dir: int) -> String:
	if _track == null or _track.highway == null:
		return "This way" if dir > 0 else "The other way"
	return "Clockwise" if _track.highway.clockwise(dir) else "Anticlockwise"


func _next() -> void:
	event.kind = "highway"
	Settings.set_value("last_highway", event.to_dict())
	picked.emit(event)


func grab_focus_first() -> void:
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
