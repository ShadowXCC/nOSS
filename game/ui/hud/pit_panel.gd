class_name PitPanel
extends Control
## A player's pit stop on the HUD (D210): the service asked for ("Pit: Full · 4 tires"), then in
## the lane "Locked · Box 120 m", "Service 8.1" and "Go". Words only; read out by the screen
## reader as it changes (the stop's news is also spoken, PitControl).

var _label := Label.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	offset_left = 40
	offset_right = 560
	offset_top = 232
	offset_bottom = 276
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 8)
	_label.size = Vector2(520, 40)
	_label.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_child(_label)
	visible = false


func show_text(text: String) -> void:
	if text == _label.text and visible == not text.is_empty():
		return
	_label.text = text
	visible = not text.is_empty()


func text() -> String:
	return _label.text if visible else ""
