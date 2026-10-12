class_name BrushTool
extends EditorTool
## A brush over the terrain (the Terrain and Paint tools, EDT-02): dabs while the mouse button is
## down, or (keys and controller) while "Brush on" is toggled, as the view moves. A stroke is one
## undo: before it changes a 32-sample tile for the first time, the tile is kept, and at the end
## they make up what the stroke's rectangle held before.

const TILE := 32
const DAB_S := 1.0 / 30.0

var radius := 20.0
var strength := 1.0
var falloff := 0.5
## Brush on (keys and controller): dabs as the crosshair moves.
var toggled := false
var _stroking := false
var _cursor := { "hit": false, "position": Vector3.ZERO }
var _since := 0.0
var _tiles := {} # Vector2i -> data before the stroke
var _stroke_rect := Rect2i()


## Changes the terrain round `at` (x, z) for `dt` seconds of brushing; returns the samples changed.
func _apply(_at: Vector2, _dt: float) -> Rect2i:
	return Rect2i()


## The region's data (heights or paint weights) and how many entries a sample has.
func _region(_rect: Rect2i) -> Variant:
	return null


func _stride() -> int:
	return 1


## Records the stroke as one action.
func _commit(_rect: Rect2i, _before: Variant, _after: Variant) -> void:
	pass


## Shows the change while the stroke goes on.
func _live(_rect: Rect2i) -> void:
	pass


func activate() -> void:
	if draft.terrain == null:
		editor.say("This track has no terrain")


func deactivate() -> void:
	_end_stroke()
	super()


func pointer(e: Dictionary) -> void:
	_cursor = e.hit
	match String(e.kind):
		"press":
			if e.crosshair:
				toggled = not toggled
				view.grabbing = false
				editor.say("Brush on" if toggled else "Brush off")
				if toggled:
					_begin_stroke()
				else:
					_end_stroke()
			else:
				_begin_stroke()
		"release":
			if not e.crosshair:
				_end_stroke()
	_show_ring()


func tick(delta: float) -> void:
	if not _stroking or draft.terrain == null:
		return
	if toggled and view.crosshair:
		_cursor = view.pick(view.center())
		_show_ring()
	_since += delta
	if _since < DAB_S or not _cursor.hit:
		return
	var dt := _since
	_since = 0.0
	var at := Vector2(_cursor.position.x, _cursor.position.z)
	var rect := draft.terrain.field.rect_around(at, radius)
	_keep_tiles(rect)
	var changed := _apply(at, dt)
	if changed.has_area():
		_stroke_rect = changed if not _stroke_rect.has_area() else _stroke_rect.merge(changed)
		_live(changed)


func _begin_stroke() -> void:
	if draft.terrain == null:
		return
	_stroking = true
	_since = DAB_S
	_tiles.clear()
	_stroke_rect = Rect2i()


func _end_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	toggled = false
	if _tiles.is_empty() or not _stroke_rect.has_area():
		return
	# The stroke's area: every tile it touched.
	var area := Rect2i()
	for t: Vector2i in _tiles:
		var r := _tile_rect(t)
		area = r if not area.has_area() else area.merge(r)
	var after: Variant = _region(area)
	var before: Variant = after.duplicate()
	var stride := _stride()
	for t: Vector2i in _tiles:
		var r := _tile_rect(t)
		var data: Variant = _tiles[t]
		for z in r.size.y:
			for x in r.size.x * stride:
				before[((r.position.y - area.position.y + z) * area.size.x + (r.position.x - area.position.x)) * stride + x] = data[z * r.size.x * stride + x]
	_tiles.clear()
	_commit(area, before, after)


func _keep_tiles(rect: Rect2i) -> void:
	var size := draft.terrain.field.get_size()
	for tz in range(rect.position.y / TILE, (rect.end.y - 1) / TILE + 1):
		for tx in range(rect.position.x / TILE, (rect.end.x - 1) / TILE + 1):
			var t := Vector2i(tx, tz)
			if not _tiles.has(t) and _tile_rect(t).intersects(Rect2i(Vector2i.ZERO, size)):
				_tiles[t] = _region(_tile_rect(t))


func _tile_rect(t: Vector2i) -> Rect2i:
	var size := draft.terrain.field.get_size()
	return Rect2i(t * TILE, Vector2i(TILE, TILE)).intersection(Rect2i(Vector2i.ZERO, size))


func _show_ring() -> void:
	if draft.terrain and _cursor.hit:
		view.gizmos.show_brush(_cursor.position, radius, draft.terrain.height_at, view.gizmos.colors.get("p1", Color.WHITE) if _stroking else Color.WHITE)


func _size_rows() -> Array:
	return [
		UiKit.number("Size", radius, 2.0, 200.0, 1.0, "%.0f m", func(v: float) -> void:
			radius = v
			_show_ring(), "Brush radius"),
		UiKit.number("Falloff", falloff, 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void: falloff = v, "The soft outer part of the brush"),
		UiKit.button("Brush on" if not toggled else "Brush off", func() -> void:
			toggled = not toggled
			if toggled:
				_begin_stroke()
			else:
				_end_stroke()
			editor.say("Brush on" if toggled else "Brush off")
			editor.refresh_panel(), "Keys and controller: brush as the view moves"),
	]
