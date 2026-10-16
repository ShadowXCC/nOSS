class_name KartMenu
extends Control
## Kart (docs/GAMEMODES.md §2, MODE-05, D144, D145): a race (track, laps, AI, items), a battle
## (arena, rule, minutes, AI) or a cup (pick one, or make, change or delete your own; AI, items).
## Then the class (kart classes) and the players. Every choice is a spinner or a button, named and
## in the focus order; the last setup is remembered.

## `kind`: "race", "battle" or "cup"; `track`: the track or arena (races and battles); `cup`: the
## cup's file (cups).
signal picked(kind: String, event: RaceEvent, track: String, cup: String)
signal closed

const KINDS := [["race", "Race"], ["battle", "Battle"], ["cup", "Cup"]]
const RULES := [["standing", "Last one standing"], ["hits", "Most hits"]]

var kind := "race"
var event := RaceEvent.new()
var track := ""
var arena := ""
var cup_path := ""
var _rows: Array = []
var _list: VBoxContainer
var _builder: CupBuilder


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	event.kind = "race"
	event.race_laps = 3
	event.ai_count = 7
	event.ai_cars = "builtin"
	var last: Variant = Settings.profile.get("last_kart")
	if last is Dictionary:
		kind = String(last.get("kind", kind)) if String(last.get("kind", "")) in ["race", "battle", "cup"] else "race"
		event = RaceEvent.from_dict(last.get("event", {}))
		track = TrackLibrary.resolve(String(last.get("track", "")))
		arena = TrackLibrary.resolve(String(last.get("arena", "")))
		cup_path = String(last.get("cup", ""))
	if Game.dev.has("battle"):
		kind = "battle"
	elif Game.dev.has("cup"):
		kind = "cup"
	_list = UiKit.panel(self, "Kart", 860)
	_build()


func _build(focus := "") -> void:
	for c: Control in _rows:
		c.queue_free()
	_rows.clear()
	_add(UiKit.spinner("Play", KINDS, kind, func(v: String) -> void:
		kind = v
		_build.call_deferred("Play"), "Race: one race. Battle: items in an arena. Cup: four races for points"))
	match kind:
		"race":
			var tracks := _tracks("circuit")
			if track not in tracks.map(func(t: Array) -> String: return t[0]):
				track = _kart_first(tracks)
			_add(UiKit.spinner("Track", tracks, track, func(v: String) -> void: track = v))
			_add(UiKit.spinner("Laps", _range(1, 10), clampi(event.race_laps, 1, 10), func(v: int) -> void: event.race_laps = v))
			_add_ai()
			_add(UiKit.spinner("Items", [[true, "On"], [false, "Off"]], event.items, func(v: bool) -> void: event.items = v))
		"battle":
			var arenas := _tracks("arena")
			if arena not in arenas.map(func(t: Array) -> String: return t[0]):
				arena = String(arenas[0][0]) if not arenas.is_empty() else ""
			if arenas.is_empty():
				_add(UiKit.label("No arenas yet. Build one in the Track Editor.", 24))
			else:
				_add(UiKit.spinner("Arena", arenas, arena, func(v: String) -> void: arena = v))
			_add(UiKit.spinner("Rule", RULES, event.battle_rule, func(v: String) -> void: event.battle_rule = v,
				"Last one standing: three lives each. Most hits: hits count, nobody goes out"))
			_add(UiKit.spinner("Minutes", [[3, "3"], [5, "5"], [7, "7"], [10, "10"]], event.battle_min if event.battle_min in [3, 5, 7, 10] else 5,
				func(v: int) -> void: event.battle_min = v))
			_add_ai()
		"cup":
			var cups := CupRun.list()
			if cup_path not in cups.map(func(c: Dictionary) -> String: return c.path):
				cup_path = String(cups[0].path) if not cups.is_empty() else ""
			if not cups.is_empty():
				_add(UiKit.spinner("Cup", cups.map(func(c: Dictionary) -> Array: return [c.path, c.name + ("" if c.builtin else " (yours)")]), cup_path,
					func(v: String) -> void:
						cup_path = v
						_build.call_deferred("Cup")))
				var c := CupRun.load_file(cup_path)
				var missing := CupRun.missing_track(c)
				var names := PackedStringArray()
				for r: Dictionary in c.get("races", []):
					var e := TrackLibrary.entry(TrackLibrary.resolve(String(r.track)))
					names.append("%s (%d)" % [String(e.get("name", "Track missing")), int(r.laps)])
				var races := UiKit.label(", ".join(names), 22)
				races.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_list.add_child(races)
				_rows.append(races)
				if missing >= 0:
					_add(UiKit.label("Track missing: race %d" % (missing + 1), 24))
				if not cup_path.begins_with("res://"):
					_add(UiKit.button("Change this cup", func() -> void: _open_builder(c), "Its name, tracks and laps"))
					_add(UiKit.button("Delete this cup", func() -> void:
						CupRun.delete(String(c.id))
						cup_path = ""
						_build.call_deferred()))
			_add(UiKit.button("New cup", func() -> void: _open_builder({}), "Pick four tracks and their laps"))
			_add_ai()
			_add(UiKit.spinner("Items", [[true, "On"], [false, "Off"]], event.items, func(v: bool) -> void: event.items = v))
	var next := UiKit.button("Next", _next, "Pick the class")
	next.disabled = not _ready_to_go()
	_add(next)
	_add(UiKit.button("Back", func() -> void: closed.emit()))
	UiKit.chain_focus(_rows, focus.is_empty())
	for c: Control in _rows:
		if focus and String(c.accessibility_name).get_slice(":", 0) == focus:
			UiKit.focus_later(c)


func _add_ai() -> void:
	_add(UiKit.spinner("AI karts", _range(0, 11), clampi(event.ai_count, 0, 11), func(v: int) -> void: event.ai_count = v))
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	_add(UiKit.spinner("AI skill", skills, snappedf(event.ai_skill, 5.0), func(v: float) -> void: event.ai_skill = v))


func _add(c: Control) -> void:
	_list.add_child(c)
	_rows.append(c)


func _range(from: int, to: int) -> Array:
	var out := []
	for n in range(from, to + 1):
		out.append([n, "%d" % n])
	return out


func _tracks(type: String) -> Array:
	return TrackLibrary.list(true, true, type).map(func(e: Dictionary) -> Array: return [e.path, TrackLibrary.label(e)])


## The first track made for karts, else the first.
func _kart_first(tracks: Array) -> String:
	for t: Array in tracks:
		if String(t[1]).ends_with("· Kart"):
			return t[0]
	return String(tracks[0][0]) if not tracks.is_empty() else ""


func _ready_to_go() -> bool:
	match kind:
		"race":
			return not track.is_empty()
		"battle":
			return not arena.is_empty()
		"cup":
			return not cup_path.is_empty() and CupRun.missing_track(CupRun.load_file(cup_path)) < 0
	return false


func _next() -> void:
	if not _ready_to_go():
		return
	var e := RaceEvent.from_dict(event.to_dict())
	match kind:
		"race":
			e.kind = "race"
			e.practice_min = 0
			e.qualifying_min = 0
			e.race_min = 0
			e.grid = "random"
			e.ai_cars = "builtin"
		"battle":
			e = RaceEvent.battle(event.battle_rule, event.battle_min)
			e.ai_count = event.ai_count
			e.ai_skill = event.ai_skill
			e.ai_cars = "builtin"
	Settings.set_value("last_kart", { "kind": kind, "event": event.to_dict(), "track": track, "arena": arena, "cup": cup_path })
	picked.emit(kind, e, arena if kind == "battle" else track, cup_path)


func _open_builder(c: Dictionary) -> void:
	_builder = CupBuilder.new()
	_builder.cup = c.duplicate(true)
	_builder.saved.connect(func(path: String) -> void:
		cup_path = path
		_builder.queue_free()
		visible = true
		_build("Cup"))
	_builder.closed.connect(func() -> void:
		_builder.queue_free()
		visible = true
		_build("Cup"))
	visible = false
	get_parent().add_child(_builder)


func grab_focus_first() -> void:
	if not _rows.is_empty():
		(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
