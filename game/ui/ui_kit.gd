class_name UiKit
extends RefCounted
## Shared menu look and builders. Every control gets an accessible name, and focus order is
## set by hand (docs/ACCESSIBILITY.md §2 build rule, ACC-03 groundwork). Menus work with
## directions + confirm + cancel alone.

const ACCENT := Color("#E8B71A")
const PANEL := Color(0.07, 0.07, 0.09, 0.97)
const BUTTON := Color(0.16, 0.16, 0.19)
const FONT_SIZE := 30

## Font choices (docs/ACCESSIBILITY.md §2): "retro" is the game's look, "clear" a plain
## high-legibility font.
const FONTS := { "clear": "res://content/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf" }

static var _themes := {}


## The menu theme in P1's font (shared menus follow P1).
static func theme() -> Theme:
	return theme_with(String(Settings.primary.data.get("font", "retro")) if Settings.primary else "retro")


## The theme for a control: in a player's view, that player's font; elsewhere P1's. Themes
## don't reach into a view's viewport, so menus there set it themselves.
static func theme_for(node: Node) -> Theme:
	var vp := node.get_viewport() if node.is_inside_tree() else null
	var view := vp.get_parent() as PlayerView if vp else null
	if view and view.slot:
		return theme_with(String(view.slot.profile.data.get("font", "retro")))
	return theme()


static func theme_with(font_id: String) -> Theme:
	if not FONTS.has(font_id):
		font_id = "retro"
	if _themes.has(font_id):
		return _themes[font_id]
	var t := _base_theme()
	if FONTS.has(font_id):
		t.default_font = load(FONTS[font_id])
	_themes[font_id] = t
	return t


static func _base_theme() -> Theme:
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
	# A check's state shows in its switch, not as a pressed button.
	for state in ["normal", "pressed", "hover", "hover_pressed"]:
		t.set_stylebox(state, "CheckButton", _box(BUTTON if state.begins_with("hover") else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10))
	t.set_color("font_color", "Button", Color(0.95, 0.95, 0.93))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", Color(0.95, 0.95, 0.93))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 16)
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
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	# Fit the room there is (a small splitscreen view, big text): narrower panel, shorter
	# scroll areas. A scroll area's starting height is its largest.
	var fit := func() -> void:
		if parent.size.x <= 0.0:
			return
		box.custom_minimum_size.x = minf(width, parent.size.x - 40.0)
		for sc: ScrollContainer in list.find_children("*", "ScrollContainer", true, false):
			if not sc.has_meta(&"max_height"):
				sc.set_meta(&"max_height", sc.custom_minimum_size.y)
			var others := box.get_combined_minimum_size().y - sc.custom_minimum_size.y
			sc.custom_minimum_size.y = clampf(parent.size.y - 40.0 - others, 160.0, sc.get_meta(&"max_height"))
	parent.resized.connect(fit)
	fit.call_deferred()
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


static func check(text: String, value: bool, on_toggled: Callable, description := "") -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.accessibility_name = text
	c.accessibility_description = description
	c.button_pressed = value
	c.toggled.connect(on_toggled)
	return c


## Option list: `items` are [value, label] pairs.
static func option(text: String, items: Array, value: Variant, on_selected: Callable, description := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.accessibility_name = text
	o.accessibility_description = description
	o.custom_minimum_size = Vector2(260, 56)
	for i in items.size():
		o.add_item(items[i][1], i)
		if items[i][0] == value:
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: on_selected.call(items[i][0]))
	row.add_child(o)
	return row


## 0..100% slider.
static func slider(text: String, value: float, on_changed: Callable, description := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.accessibility_name = text
	s.accessibility_description = description
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


## Slider over any range, with its value shown as `format` (e.g. "%.2f m").
static func number(text: String, value: float, min_value: float, max_value: float, step: float, format: String, on_changed: Callable, description := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.accessibility_name = text
	s.accessibility_description = description
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 48)
	var shown := label(format % value)
	shown.custom_minimum_size = Vector2(130, 0)
	s.value_changed.connect(func(v: float) -> void:
		shown.text = format % v
		on_changed.call(v))
	row.add_child(s)
	row.add_child(shown)
	return row


## Labelled text field. `on_changed` gets the text when editing ends.
static func text_field(text: String, value: String, on_changed: Callable, max_length := 96) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.custom_minimum_size = Vector2(180, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.accessibility_name = text
	e.text = value
	e.max_length = max_length
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 56)
	e.text_changed.connect(func(t: String) -> void: on_changed.call(t))
	row.add_child(e)
	return row


## Labelled colour: a picker button plus the hex value.
static func color(text: String, value: Color, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := ColorPickerButton.new()
	b.accessibility_name = text
	b.color = value
	b.edit_alpha = false
	b.custom_minimum_size = Vector2(160, 56)
	var hex := label("#" + value.to_html(false).to_upper(), 24)
	hex.custom_minimum_size = Vector2(130, 0)
	b.color_changed.connect(func(c: Color) -> void:
		hex.text = "#" + c.to_html(false).to_upper()
		on_changed.call(c))
	row.add_child(b)
	row.add_child(hex)
	return row


## A choice stepped with left and right (confirm steps forward), so it works with directions,
## confirm and cancel alone (docs/ACCESSIBILITY.md §5.1). `items` are [value, label] pairs.
static func spinner(text: String, items: Array, value: Variant, on_changed: Callable, description := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var state := { "i": 0 }
	for i in items.size():
		if items[i][0] == value:
			state.i = i
	var show := func() -> void:
		var shown := String(items[state.i][1]) if not items.is_empty() else "-"
		b.text = "%s   ‹ %s ›" % [text, shown] if items.size() > 1 else "%s   %s" % [text, shown]
		b.accessibility_name = "%s: %s" % [text, shown]
	var step := func(d: int) -> void:
		if items.size() < 2:
			return
		state.i = posmod(state.i + d, items.size())
		show.call()
		on_changed.call(items[state.i][0])
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left", true):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right", true):
			step.call(1)
			b.accept_event())
	b.accessibility_description = (description + ". " if description else "") + "Left and right to change"
	show.call()
	return b


## Opens `menu` in place of the rest of `host` (hidden meanwhile). When the menu emits
## `closed`, it goes and `host` comes back with `on_back` called (e.g. to refocus).
static func open_sub(host: Control, menu: Control, on_back := Callable()) -> void:
	var hidden: Array[CanvasItem] = []
	for child in host.get_children():
		if child is CanvasItem and child.visible:
			child.visible = false
			hidden.append(child)
	menu.closed.connect(func() -> void:
		menu.queue_free()
		for c in hidden:
			if is_instance_valid(c):
				c.visible = true
		if on_back.is_valid():
			on_back.call())
	host.add_child(menu)


## The focused control of `node`'s menu: a player view's own focus, else the window's.
static func focus_owner(node: Node) -> Control:
	var vp := node.get_viewport()
	var c := Players.focus_of(vp)
	return c if c else vp.gui_get_focus_owner()


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
	if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
		return c
	for child in c.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE and (child is BaseButton or child is Range or child is LineEdit):
			return child
	return null
