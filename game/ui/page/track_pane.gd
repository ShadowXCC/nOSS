class_name TrackPane
extends VBoxContainer
## The right pane of an event's Settings page (docs/UI_FLOW.md §4): the track's map, its name, its
## length in the player's units ("2.44 km", "1.52 mi") and what kind of track it is ("Oval ·
## Real-world"). The maps are the tracks' centrelines, each loaded once.

## Tags shown on the kind line, in this order.
const TAGS := [["oval", "Oval"], ["real-world", "Real-world"], ["kart", "Kart"], ["stunt", "Stunts"], ["city", "City"]]

var map: TrackMap
## The track shown (a path).
var path := ""
var _name: Label
var _length: Label
var _kind: Label
var _maps := {} # path -> TrackData (centreline only)


func _init() -> void:
	name = "TrackPane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 8)
	map = TrackMap.new()
	map.custom_minimum_size = Vector2(0, 240)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(map)
	_name = Label.new()
	_name.name = "TrackName"
	_name.clip_text = true
	add_child(_name)
	for l: Label in [Label.new(), Label.new()]:
		l.theme_type_variation = &"PageCrumb"
		l.clip_text = true
		add_child(l)
	_length = get_child(2)
	_length.name = "Length"
	_kind = get_child(3)
	_kind.name = "Kind"


## Shows the track at `track_path` (its map, name, length and kind).
func show_track(track_path: String) -> void:
	path = track_path
	var e := TrackLibrary.entry(track_path) if track_path else {}
	_name.text = String(e.get("name", ""))
	_length.text = length_text(float(e.get("length_m", 0.0))) if float(e.get("length_m", 0.0)) > 0.0 and e.get("type") != "arena" else ""
	_kind.text = kind_text(e)
	map.track = data(track_path)


## The track at `track_path` (its centreline, a highway's runs), loaded once; null if it won't load.
func data(track_path: String) -> TrackData:
	if track_path and not _maps.has(track_path):
		var pkg := TrackLoader.load_package(track_path, {}, { "terrain": false })
		_maps[track_path] = pkg.track if pkg.ok() else null
	return _maps.get(track_path)


## The name, length and kind as one line (tests, screen readers).
func text() -> String:
	return ", ".join(PackedStringArray([_name.text, _length.text, _kind.text].filter(func(t: String) -> bool: return not t.is_empty())))


## "2.44 km", or "1.52 mi" in imperial units.
static func length_text(metres: float) -> String:
	return "%.2f mi" % (metres / 1609.344) if Settings.units == "imperial" else "%.2f km" % (metres / 1000.0)


## "Oval · Real-world", "Kart", "Highway", "Circuit" (a plain one); "Your track" on the player's own.
static func kind_text(e: Dictionary) -> String:
	if e.is_empty():
		return ""
	var bits := PackedStringArray()
	var type := String(e.get("type", "circuit"))
	if type != "circuit":
		bits.append(type.capitalize())
	var tags: Array = e.get("tags", [])
	for tag: Array in TAGS:
		if tag[0] in tags:
			bits.append(tag[1])
	if bits.is_empty():
		bits.append("Circuit")
	if not e.get("builtin", true):
		bits.append("Your track")
	return " · ".join(bits)
