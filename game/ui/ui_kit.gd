class_name UiKit
extends RefCounted
## Shared menu look and builders. Every control gets an accessible name, and focus order is
## set by hand (docs/ACCESSIBILITY.md §2 build rule, ACC-03 groundwork). Menus work with
## directions + confirm + cancel alone.

const ACCENT := Color("#E8B71A")
const PANEL := Color(0.07, 0.07, 0.09, 0.92)
const BUTTON := Color(0.16, 0.16, 0.19)
const FONT_SIZE := 30

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(0, 0, 0, 0), 0, 24))
	t.set_stylebox("normal", "Button", _box(BUTTON, Color(0.3, 0.3, 0.34), 2, 14))
	t.set_stylebox("hover", "Button", _box(BUTTON.lightened(0.1), ACCENT.darkened(0.3), 2, 14))
	t.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.5), ACCENT, 3, 14))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 4, 14))
	t.set_stylebox("disabled", "Button", _box(BUTTON.darkened(0.3), Color(0.2, 0.2, 0.22), 2, 14))
	for cls in ["CheckButton", "OptionButton", "HSlider"]:
		t.set_stylebox("focus", cls, _box(Color(0, 0, 0, 0), ACCENT, 4, 8))
	t.set_color("font_color", "Button", Color(0.95, 0.95, 0.93))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", Color(0.95, 0.95, 0.93))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 16)
	_theme = t
	return t


static func _box(bg: Color, border: Color, border_w: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(pad)
	return s


## A centred panel holding a vertical list, on a dimmed backdrop. Returns the list.
static func panel(parent: Control, title: String, width := 760.0) -> VBoxContainer:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	center.add_child(box)
	var list := VBoxContainer.new()
	box.add_child(list)
	if title:
		var heading := label(title, 44)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(heading)
	return list


static func label(text: String, size := FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


static func button(text: String, on_pressed: Callable, description := "") -> Button:
	var b := Button.new()
	b.text = text
	b.accessibility_name = text
	b.accessibility_description = description
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(on_pressed)
	return b


static func check(text: String, value: bool, on_toggled: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.accessibility_name = text
	c.button_pressed = value
	c.toggled.connect(on_toggled)
	return c


## Option list: `items` are [value, label] pairs.
static func option(text: String, items: Array, value: Variant, on_selected: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.accessibility_name = text
	o.custom_minimum_size = Vector2(260, 56)
	for i in items.size():
		o.add_item(items[i][1], i)
		if items[i][0] == value:
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: on_selected.call(items[i][0]))
	row.add_child(o)
	return row


## 0..100% slider.
static func slider(text: String, value: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.accessibility_name = text
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = value * 100.0
	s.custom_minimum_size = Vector2(260, 48)
	var pct := label("%d%%" % roundi(value * 100.0))
	pct.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v)
		on_changed.call(v / 100.0))
	row.add_child(s)
	row.add_child(pct)
	return row


## Links the focusable controls in `controls` top to bottom (wrapping) and focuses the first.
static func chain_focus(controls: Array) -> void:
	var focusable: Array[Control] = []
	for c: Control in controls:
		var target := _focus_target(c)
		if target:
			focusable.append(target)
	for i in focusable.size():
		var c := focusable[i]
		var prev := focusable[(i - 1 + focusable.size()) % focusable.size()]
		var next := focusable[(i + 1) % focusable.size()]
		c.focus_neighbor_top = c.get_path_to(prev)
		c.focus_neighbor_bottom = c.get_path_to(next)
		c.focus_previous = c.get_path_to(prev)
		c.focus_next = c.get_path_to(next)
	if not focusable.is_empty():
		focusable[0].grab_focus.call_deferred()


static func _focus_target(c: Control) -> Control:
	if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range):
		return c
	for child in c.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE and (child is BaseButton or child is Range):
			return child
	return null
