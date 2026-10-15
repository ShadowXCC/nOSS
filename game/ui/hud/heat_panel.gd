class_name HeatPanel
extends Control
## The police heat meter on the HUD (D115, docs/ACCESSIBILITY.md): five pips filled up to the
## level and the word ("Heat 3"), and while the police lose track, a bar filling towards
## "evaded". Shape and words carry it, colour only adds; it's hidden with no heat.

const PIPS := 5
const PIP := Vector2(30, 18)
const GAP := 8.0

var _level := 0
var _evading := 0.0
var _label := Label.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -170
	offset_right = 170
	offset_top = 230
	offset_bottom = 300
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(340, 36)
	_label.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_child(_label)
	visible = false


func show_heat(level: int, evading: float) -> void:
	if level == _level and is_equal_approx(evading, _evading):
		return
	_level = level
	_evading = evading
	visible = level > 0
	_label.text = "Heat %d" % level + ("  ·  losing them" if evading > 0.05 else "")
	queue_redraw()


func _draw() -> void:
	if _level <= 0:
		return
	var width := PIPS * PIP.x + (PIPS - 1) * GAP
	var x0 := (size.x - width) / 2.0
	for i in PIPS:
		var r := Rect2(Vector2(x0 + i * (PIP.x + GAP), 40.0), PIP)
		if i < _level:
			draw_rect(r, Hud.BAD)
		draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
	if _evading > 0.0:
		draw_rect(Rect2(Vector2(x0, 64.0), Vector2(width * _evading, 5.0)), Hud.GOOD)
