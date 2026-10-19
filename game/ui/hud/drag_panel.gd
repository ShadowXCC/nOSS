class_name DragPanel
extends Control
## A drag pass's HUD (D169, docs/ACCESSIBILITY.md): the fake tachometer with its shift window, the
## gear, the perfect-shift chain, the bottles left, the prompt for whatever the driver is holding,
## and the numbers of the pass — reaction, elapsed time and trap speed.
##
## Nothing relies on colour alone: the window is a band on the bar and also a word ("Shift now"),
## a shake says "Ease off" rather than flashing, and every line is in `accessibility_name`.

const BAR := Vector2(420, 18)
const BAR_AT := Vector2(0, 84)
## The needle runs 0..1 over the bar; over-revving carries on past its end, to here.
const BAR_MAX := 1.2

var palette: Dictionary = Palette.PRESETS.default
var calm := false

var _state := Label.new()
var _gear := Label.new()
var _prompt := Label.new()
var _numbers := Label.new()
var _extras := Label.new()
var _bar_back := ColorRect.new()
var _bar_window := ColorRect.new()
var _bar_fill := ColorRect.new()
var _bar_needle := ColorRect.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	offset_left = 40
	offset_top = 200
	offset_right = 620
	offset_bottom = 470
	for row: Array in [[_state, 40, Vector2(0, 0)], [_gear, 30, Vector2(0, 48)],
			[_extras, 26, Vector2(0, 112)], [_prompt, 32, Vector2(0, 150)], [_numbers, 26, Vector2(0, 194)]]:
		var l: Label = row[0]
		l.add_theme_font_size_override("font_size", row[1])
		l.add_theme_color_override("font_color", Hud.TEXT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 8)
		l.position = row[2]
		l.size = Vector2(540, row[1] + 10)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	for r: ColorRect in [_bar_back, _bar_window, _bar_fill, _bar_needle]:
		r.position = BAR_AT
		r.size = BAR
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
	_bar_back.color = Color(1, 1, 1, 0.18)
	_bar_window.color = Color(1, 1, 1, 0.38)
	_bar_needle.size = Vector2(4, BAR.y + 8)


## `d` carries the pass as DragHud read it:
## state (a word), gear, needle, window ([centre, width] or []), chain, boosts, prompt,
## reaction, et, trap, shake (the QTE is open), over_rev, blown, foul, units.
func show_drag(d: Dictionary) -> void:
	_state.text = String(d.get("state", ""))
	var gear := int(d.get("gear", 0))
	_gear.text = "R" if gear < 0 else "N" if gear == 0 else "Gear %d" % gear
	var window: Array = d.get("window", [])
	var needle := clampf(float(d.get("needle", 0.0)), 0.0, BAR_MAX)
	var show_bar := not window.is_empty() or needle > 0.0
	for r: ColorRect in [_bar_back, _bar_window, _bar_fill, _bar_needle]:
		r.visible = show_bar
	_bar_fill.size.x = BAR.x * clampf(needle / BAR_MAX, 0.0, 1.0)
	_bar_fill.color = palette.get("item_speed", Color.ORANGE) if not bool(d.get("over_rev", false)) else Color(1.0, 0.35, 0.3)
	_bar_needle.position.x = BAR_AT.x + BAR.x * clampf(needle / BAR_MAX, 0.0, 1.0)
	_bar_needle.position.y = BAR_AT.y - 4
	_bar_needle.color = Hud.TEXT
	if window.is_empty():
		_bar_window.visible = false
	else:
		var centre := float(window[0])
		var width := maxf(float(window[1]), 0.02)
		_bar_window.position.x = BAR_AT.x + BAR.x * clampf((centre - width * 0.5) / BAR_MAX, 0.0, 1.0)
		_bar_window.size.x = BAR.x * clampf(width / BAR_MAX, 0.0, 1.0)
	# The words that carry what the colours show, for anyone who cannot use them (ACC-04).
	var extras: Array[String] = []
	var chain := int(d.get("chain", 0))
	if chain > 0:
		extras.append("Chain x%d" % (chain + 1))
	var boosts := int(d.get("boosts", 0))
	if boosts > 0:
		extras.append("%s x%d" % [String(d.get("boost_name", "Boost")), boosts])
	if bool(d.get("blown", false)):
		extras.append("Engine gone")
	elif bool(d.get("over_rev", false)):
		extras.append("Over-revving")
	elif not window.is_empty() and _in_window(needle, window):
		extras.append("Shift now")
	_extras.text = "  ·  ".join(extras)
	_prompt.text = String(d.get("prompt", ""))
	_prompt.add_theme_color_override("font_color", Hud.TEXT if not bool(d.get("shake", false)) else Color(1.0, 0.8, 0.3))
	var numbers: Array[String] = []
	if float(d.get("reaction", -1.0)) >= 0.0:
		numbers.append("RT %.3f" % float(d.reaction))
	if float(d.get("et", -1.0)) >= 0.0:
		numbers.append("ET %.3f" % float(d.et))
		numbers.append(_speed_text(float(d.get("trap", 0.0)), String(d.get("units", "metric"))))
	var foul := String(d.get("foul", ""))
	if foul:
		numbers.append(foul)
	_numbers.text = "  ·  ".join(numbers)
	accessibility_name = ". ".join([_state.text, _gear.text, _extras.text, _prompt.text, _numbers.text].filter(
		func(t: String) -> bool: return not t.is_empty()))


static func _in_window(needle: float, window: Array) -> bool:
	return absf(needle - float(window[0])) <= float(window[1]) * 0.5


static func _speed_text(speed: float, units: String) -> String:
	return "%d mph" % roundi(speed * 2.23694) if units == "imperial" else "%d km/h" % roundi(speed * 3.6)


func state_text() -> String:
	return _state.text


func prompt_text() -> String:
	return _prompt.text


func extras_text() -> String:
	return _extras.text


func numbers_text() -> String:
	return _numbers.text
