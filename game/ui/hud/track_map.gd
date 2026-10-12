class_name TrackMap
extends Control
## Track map for the spare splitscreen quarter (docs/ARCHITECTURE.md §6): the track's
## centreline, the start line, and each player's car as a dot with their number on it, in
## their colour (never colour alone).

var track: TrackData:
	set(t):
		track = t
		_points = PackedVector2Array()
		queue_redraw()
## Returns the cars to show: [[number, colour, world position], ...].
var cars: Callable

var _points := PackedVector2Array()
var _bounds := Rect2()


func _init() -> void:
	name = "TrackMap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	if track == null or track.samples.is_empty():
		return
	if _points.is_empty():
		for p in track.samples:
			_points.append(Vector2(p.x, p.z))
		_bounds = Rect2(_points[0], Vector2.ZERO)
		for p in _points:
			_bounds = _bounds.expand(p)
	var margin := minf(size.x, size.y) * 0.1
	var fit := minf((size.x - 2.0 * margin) / maxf(_bounds.size.x, 1.0), (size.y - 2.0 * margin) / maxf(_bounds.size.y, 1.0))
	var offset := (size - _bounds.size * fit) / 2.0
	var to_map := func(p: Vector2) -> Vector2: return offset + (p - _bounds.position) * fit
	var line := PackedVector2Array()
	for p in _points:
		line.append(to_map.call(p))
	line.append(line[0])
	var width := maxf(size.y / 90.0, 2.0)
	draw_polyline(line, Color(0, 0, 0), width * 2.2, true)
	draw_polyline(line, Color(0.85, 0.85, 0.82), width, true)
	var start := track.transform_at(track.start_m)
	var s: Vector2 = to_map.call(Vector2(start.origin.x, start.origin.z))
	var across := Vector2(start.basis.x.x, start.basis.x.z).normalized() * width * 3.0
	draw_line(s - across, s + across, Color.WHITE, width * 0.8)
	if not cars.is_valid():
		return
	var font := get_theme_default_font()
	var radius := maxf(size.y / 28.0, 8.0)
	var list: Array = cars.call()
	list.reverse() # P1 on top
	for c: Array in list:
		var at: Vector2 = to_map.call(Vector2(c[2].x, c[2].z))
		draw_circle(at, radius + 2.0, Color.BLACK)
		draw_circle(at, radius, c[1])
		var text := str(c[0])
		var fs := int(radius * 1.4)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, at + Vector2(-tw.x / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
