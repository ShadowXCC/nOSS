class_name UiKit
extends RefCounted
## Shared menu look and builders. Every control gets an accessible name, and focus order is
## set by hand (docs/ACCESSIBILITY.md §2 build rule, ACC-03 groundwork). Menus work with
## directions + confirm + cancel alone.

const ACCENT := Color("#E8B71A")
const PANEL := Color(0.07, 0.07, 0.09, 0.97)
const BUTTON := Color(0.16, 0.16, 0.19)
const FONT_SIZE := 30
## Pages (docs/UI_FLOW.md §2): bigger text and rows than the old panels, the same colours.
const PAGE_FONT_SIZE := 34
const ROW_HEIGHT := 72
const MUTED := Color(0.62, 0.62, 0.68)
const BACKGROUND := Color(0.07, 0.07, 0.09)

## Font choices (docs/ACCESSIBILITY.md §2): "retro" is the game's look, "clear" a plain
## high-legibility font.
const FONTS := { "clear": "res://content/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf" }

static var _themes := {}
static var _page_themes := {}


## The menu theme in P1's font (shared menus follow P1).
static func theme() -> Theme:
	return theme_with(String(Settings.primary.data.get("font", "retro")) if Settings.primary else "retro")


## The theme for a control: in a player's view, that player's font; elsewhere P1's. Themes
## don't reach into a view's viewport, so menus there set it themselves.
static func theme_for(node: Node) -> Theme:
	return theme_with(_font_for(node))


## The page theme for a control (docs/UI_FLOW.md §2), by the same rule as theme_for(): the menu
## theme with 34 px text, and the label types "PageTitle" (56 px) and "PageCrumb" (26 px, muted).
static func page_theme_for(node: Node) -> Theme:
	var font_id := _font_for(node)
	if not FONTS.has(font_id):
		font_id = "retro"
	if _page_themes.has(font_id):
		return _page_themes[font_id]
	var t := _base_theme()
	if FONTS.has(font_id):
		t.default_font = load(FONTS[font_id])
	t.default_font_size = PAGE_FONT_SIZE
	t.set_type_variation(&"PageTitle", &"Label")
	t.set_font_size(&"font_size", &"PageTitle", 56)
	t.set_type_variation(&"PageCrumb", &"Label")
	t.set_font_size(&"font_size", &"PageCrumb", 26)
	t.set_color(&"font_color", &"PageCrumb", MUTED)
	_page_themes[font_id] = t
	return t


static func _font_for(node: Node) -> String:
	var vp := node.get_viewport() if node.is_inside_tree() else null
	var view := vp.get_parent() as PlayerView if vp else null
	if view and view.slot:
		return String(view.slot.profile.data.get("font", "retro"))
	return String(Settings.primary.data.get("font", "retro")) if Settings.primary else "retro"


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
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.35), Color(0.3, 0.3, 0.34), 2, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, Color(0, 0, 0, 0), 0, 0))
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
		var flexible: Array[Control] = []
		for sc: ScrollContainer in list.find_children("*", "ScrollContainer", true, false):
			flexible.append(sc)
		# A row that scrolls on its own (the chat log) is tagged instead, so it gives up height
		# here rather than nesting a second scrollbar.
		for child in list.get_children():
			if child is Control and child.has_meta(&"fit_height"):
				flexible.append(child)
		for c: Control in flexible:
			if not c.has_meta(&"max_height"):
				c.set_meta(&"max_height", c.custom_minimum_size.y)
			var others := box.get_combined_minimum_size().y - c.custom_minimum_size.y
			c.custom_minimum_size.y = clampf(parent.size.y - 40.0 - others, 160.0, c.get_meta(&"max_height"))
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


## Labelled text field. `on_changed` gets the text as it's typed, `on_submit` when Enter is
## pressed. `secret` hides what's typed (passwords). Reached with the keyboard or a controller,
## it waits for confirm before taking typing, so up and down still move between rows.
static func text_field(text: String, value: String, on_changed: Callable, max_length := 96, description := "",
		on_submit := Callable(), secret := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.custom_minimum_size = Vector2(180, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.accessibility_name = text
	e.accessibility_description = (description + ". " if description else "") + "Enter to type"
	e.text = value
	e.max_length = max_length
	e.secret = secret
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 56)
	e.text_changed.connect(func(t: String) -> void: on_changed.call(t))
	if on_submit.is_valid():
		e.text_submitted.connect(func(t: String) -> void: on_submit.call(t))
	e.focus_entered.connect(func() -> void:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			e.unedit.call_deferred())
	row.add_child(e)
	return row


## Labelled colour: a picker button plus the hex value.
static func color(text: String, value: Color, on_changed: Callable, description := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := ColorPickerButton.new()
	b.accessibility_name = text.strip_edges() # an indented row's name without its indent
	b.accessibility_description = description
	b.color = value
	b.edit_alpha = false
	b.custom_minimum_size = Vector2(160, 56)
	# A compact picker, so its popup fits on screen under the menu's text size.
	var picker := b.get_picker()
	picker.presets_visible = false
	picker.color_modes_visible = false
	picker.sampler_visible = false
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
## The value sits at the right as "‹ value ›": a click on its left half steps back, anywhere
## else forward.
static func spinner(text: String, items: Array, value: Variant, on_changed: Callable, description := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta(&"spinner", true) # left and right change it (PromptBar says so)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.add_theme_constant_override("separation", 18)
	b.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.name = "Value"
	for l: Label in [name_label, value_label]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
	b.text = ""
	var state := { "i": 0 }
	for i in items.size():
		if items[i][0] == value:
			state.i = i
	var show := func() -> void:
		var shown := String(items[state.i][1]) if not items.is_empty() else "-"
		value_label.text = "‹ %s ›" % shown if items.size() > 1 else shown
		b.set_meta(&"shown_text", "%s   %s" % [text, value_label.text])
		b.accessibility_name = "%s: %s" % [text, shown]
	var step := func(d: int) -> void:
		if items.size() < 2:
			return
		state.i = posmod(state.i + d, items.size())
		show.call()
		on_changed.call(items[state.i][0])
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT:
			# Clicks step here, by side, rather than through `pressed` (always forward).
			if mb.pressed:
				if not b.has_focus():
					b.grab_focus()
				var left := row.position.x + value_label.position.x
				step.call(-1 if mb.position.x >= left and mb.position.x < left + value_label.size.x / 2.0 else 1)
			b.accept_event()
		elif e.is_action_pressed("ui_left", true):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right", true):
			step.call(1)
			b.accept_event())
	b.accessibility_description = (description + ". " if description else "") + "Left and right to change"
	show.call()
	return b


## A bar for work that takes a while (the Fitting Bay's import), with the phase under it and the
## percentage beside it. Move it with set_progress().
static func progress(phase := "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false # shown beside the phase instead
	bar.custom_minimum_size = Vector2(0, 20)
	bar.focus_mode = Control.FOCUS_NONE
	box.add_child(bar)
	var row := HBoxContainer.new()
	row.name = "Row"
	var text := label(phase, 22)
	text.name = "Phase"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	# Only the phase is spoken: a percentage changing every frame would flood a screen reader.
	text.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	var pct := label("", 22)
	pct.name = "Percent"
	pct.custom_minimum_size = Vector2(70, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(text)
	row.add_child(pct)
	box.add_child(row)
	set_progress(box, 0.0, phase)
	return box


## Moves a progress() bar. The phase is only written when it changes, so each one is spoken once.
static func set_progress(box: Control, fraction: float, phase := "") -> void:
	var bar := box.get_node_or_null(^"Bar") as ProgressBar
	if bar == null:
		return
	bar.value = clampf(fraction, 0.0, 1.0)
	var pct := box.get_node_or_null(^"Row/Percent") as Label
	if pct:
		pct.text = "%d%%" % roundi(bar.value * 100.0)
	var text := box.get_node_or_null(^"Row/Phase") as Label
	if text and phase and text.text != phase:
		text.text = phase
		bar.accessibility_name = phase


## A native "save as" dialog, kept on `host` and reused. `suggested` fills the name box and
## `extension` (with its dot) is added if it's left off. `on_picked` gets the chosen path.
static func save_dialog(host: Node, title: String, extension: String, suggested: String, on_picked: Callable) -> FileDialog:
	var d := host.get_node_or_null(^"SaveDialog") as FileDialog
	if d == null:
		d = FileDialog.new()
		d.name = "SaveDialog"
		d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.use_native_dialog = true
		host.add_child(d)
	for c in d.file_selected.get_connections():
		d.file_selected.disconnect(c.callable)
	d.title = title
	d.filters = PackedStringArray(["*%s ; %s files" % [extension, extension.trim_prefix(".").to_upper()]])
	var file_name := suggested.validate_filename().strip_edges()
	if file_name.is_empty():
		file_name = "untitled"
	d.current_file = file_name if file_name.ends_with(extension) else file_name + extension
	d.file_selected.connect(func(path: String) -> void:
		on_picked.call(path if path.ends_with(extension) else path + extension))
	d.popup_file_dialog()
	return d


## Shows `text` on a button through a child label, leaving the button's own text empty, so a
## screen reader hears only its accessible name (Godot reads "name: text" when both are set).
static func set_shown_text(b: Button, text: String) -> void:
	var l := b.get_node_or_null(^"Shown") as Label
	if l == null:
		l = Label.new()
		l.name = "Shown"
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.offset_left = 14
		l.offset_right = -14
		l.clip_text = true
		b.add_child(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if b.alignment == HORIZONTAL_ALIGNMENT_CENTER else HORIZONTAL_ALIGNMENT_LEFT
	l.text = text
	b.text = ""
	b.set_meta(&"shown_text", text)


## What a button shows (its own text, or set_shown_text's).
static func text_of(b: Button) -> String:
	return String(b.get_meta(&"shown_text", b.text))


## Opens `menu` in place of the rest of `host` (hidden meanwhile). When the menu emits
## `closed`, it goes and `host` comes back with `on_back` called (e.g. to refocus).
static func open_sub(host: Control, menu: Control, on_back := Callable()) -> void:
	var hidden: Array[CanvasItem] = []
	for child in host.get_children():
		if child is CanvasItem and child.visible:
			MenuStack.set_shown(child, false)
			hidden.append(child)
	menu.closed.connect(func() -> void:
		menu.queue_free()
		for c in hidden:
			if is_instance_valid(c):
				MenuStack.set_shown(c, true)
		if on_back.is_valid():
			on_back.call())
	host.add_child(menu)


## The focused control of `node`'s menu: a player view's own focus, else the window's.
static func focus_owner(node: Node) -> Control:
	var vp := node.get_viewport()
	var c := Players.focus_of(vp)
	return c if c else vp.gui_get_focus_owner()


## Links the focusable controls in `controls` top to bottom (wrapping) and focuses the first
## (unless `focus_first` is off: lists that refresh while the player is on them).
static func chain_focus(controls: Array, focus_first := true) -> void:
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
	if focus_first and not focusable.is_empty():
		focus_later(focusable[0])


## Focuses `c` at the end of the frame, if it's still in the tree then (a menu may close first).
static func focus_later(c: Control) -> void:
	var id := c.get_instance_id() # not `c` itself: a freed capture errors when the call comes
	(func() -> void:
		var target := instance_from_id(id) as Control
		if target and target.is_inside_tree():
			target.grab_focus()).call_deferred()


## A labelled row on a page (docs/UI_FLOW.md §2): its labels at the rows' text size (they're made
## at the menus' 30 px), and a slider's row outlined in the accent colour while the slider has the
## focus, as a button row is (Godot draws no focus on a slider; it only brightens).
static func page_row(row: HBoxContainer) -> void:
	var labels := row.get_children().filter(func(c: Node) -> bool: return c is Label)
	for l: Label in labels:
		if l.get_theme_font_size(&"font_size") == FONT_SIZE:
			l.add_theme_font_size_override(&"font_size", PAGE_FONT_SIZE)
	var slider := _focus_target(row) as Slider
	if slider == null:
		return
	var inset := StyleBoxEmpty.new() # inside the outline, as a button row's text is
	inset.content_margin_left = 10
	inset.content_margin_right = 10
	for l: Label in labels:
		l.add_theme_stylebox_override(&"normal", inset)
	var outline := _box(Color(0, 0, 0, 0), ACCENT, 4, 0)
	row.draw.connect(func() -> void:
		if slider.has_focus():
			row.draw_style_box(outline, Rect2(Vector2.ZERO, row.size)))
	slider.focus_entered.connect(row.queue_redraw)
	slider.focus_exited.connect(row.queue_redraw)


static func _focus_target(c: Control) -> Control:
	if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
		return c
	for child in c.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE and (child is BaseButton or child is Range or child is LineEdit):
			return child
	return null
