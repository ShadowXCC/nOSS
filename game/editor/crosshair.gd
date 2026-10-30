class_name Crosshair
extends Control
## The cursor keys or a controller drive in an editor's 3D view (the track editor's, the Fitting
## Bay's Livery step): a cross at `at`, or in the middle of the view.

## Where it is (this control's coordinates); off the view (negative): the middle.
var at := Vector2(-1, -1):
	set(value):
		at = value
		queue_redraw()


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func spot() -> Vector2:
	return at if at.x >= 0.0 and at.y >= 0.0 else size / 2.0


func _draw() -> void:
	var c := spot()
	for w: Array in [[4.0, Color(0, 0, 0, 0.8)], [2.0, Color.WHITE]]:
		draw_line(c - Vector2(14, 0), c - Vector2(4, 0), w[1], w[0])
		draw_line(c + Vector2(4, 0), c + Vector2(14, 0), w[1], w[0])
		draw_line(c - Vector2(0, 14), c - Vector2(0, 4), w[1], w[0])
		draw_line(c + Vector2(0, 4), c + Vector2(0, 14), w[1], w[0])
