class_name TabRow
extends ScrollContainer
## A row of tabs on a page (docs/UI_FLOW.md §4, §10.1): toggle buttons, the current one
## underlined in the accent colour. ui_tab_prev and ui_tab_next (LB/RB, Q/E; a player's own
## Previous and Next tab) switch from anywhere on the page while it shows, wrapping, but not while
## a text field is being typed in; left and right on the row switch too. The row scrolls sideways
## when the tabs don't fit (big text, a small view). A tab that's off (`off`: Join's Official,
## "Coming soon") shows, but is skipped.

## The tab is now `index`: picked by the row itself (a click, left or right on it) when
## `on_row`, by ui_tab_prev or ui_tab_next from elsewhere on the page when not.
signal changed(index: int, on_row: bool)

const HEIGHT := 64
const FONT_SIZE := 30

var tabs: PackedStringArray = []
var current := 0
## Tabs that are off: index -> what their button shows after the name, and says ("Coming soon").
var off := {}

var _buttons: Array[Button] = []
var _group := ButtonGroup.new()


func _init(names := PackedStringArray()) -> void:
	name = "Tabs"
	tabs = names
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size.y = HEIGHT
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	for i in tabs.size():
		var b := Button.new()
		b.name = tabs[i].validate_node_name()
		b.text = tabs[i]
		b.accessibility_name = tabs[i]
		b.toggle_mode = true
		b.button_group = _group
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(0, HEIGHT)
		b.add_theme_font_size_override(&"font_size", FONT_SIZE)
		_style(b)
		b.toggled.connect(func(on: bool) -> void:
			if on and i != current:
				_pick(i, true))
		b.gui_input.connect(_on_button_input.bind(b))
		row.add_child(b)
		_buttons.append(b)
		if off.has(i):
			_turn_off(b, String(off[i]))


## A tab that's off: dimmed, out of the focus, its name then why ("Official · Coming soon"; the
## name alone for screen readers, why as its description).
func _turn_off(b: Button, why: String) -> void:
	b.disabled = true
	b.focus_mode = Control.FOCUS_NONE
	b.accessibility_description = why
	b.tooltip_text = why
	var text := "%s · %s" % [b.text, why]
	UiKit.set_shown_text(b, text) # the shown text is a label, which doesn't size the button
	var shown := b.get_node(^"Shown") as Label
	shown.add_theme_color_override(&"font_color", UiKit.MUTED.darkened(0.3))
	shown.add_theme_font_size_override(&"font_size", FONT_SIZE)
	b.custom_minimum_size.x = b.get_theme_font(&"font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 64


## The current tab's button (or tab `i`'s).
func button(i := -1) -> Button:
	i = current if i < 0 else i
	return _buttons[i] if i >= 0 and i < _buttons.size() else null


## Makes tab `i` current, without `changed` (the page shows it itself).
func select(i: int) -> void:
	current = clampi(i, 0, maxi(tabs.size() - 1, 0))
	# Without a signal the group doesn't let go of the tab before: each one is set here.
	for j in _buttons.size():
		_buttons[j].set_pressed_no_signal(j == current)
	var b := button()
	if b:
		_show.call_deferred(b)


## The other tabs lead up and down where the current one does (UiKit.chain_focus links only it).
func link() -> void:
	var b := button()
	if b == null:
		return
	for other in _buttons:
		if other != b:
			other.focus_neighbor_top = b.focus_neighbor_top
			other.focus_neighbor_bottom = b.focus_neighbor_bottom
			other.focus_previous = b.focus_previous
			other.focus_next = b.focus_next


func _pick(i: int, on_row: bool) -> void:
	select(i)
	changed.emit(current, on_row)


func _unhandled_input(event: InputEvent) -> void:
	if tabs.size() < 2 or not is_visible_in_tree():
		return
	var d := -1 if event.is_action_pressed("ui_tab_prev") else 1 if event.is_action_pressed("ui_tab_next") else 0
	if d == 0:
		return
	var focus := UiKit.focus_owner(self)
	if focus is LineEdit and (focus as LineEdit).is_editing():
		return
	get_viewport().set_input_as_handled()
	_pick(_step(d), focus != null and is_ancestor_of(focus))


func _on_button_input(event: InputEvent, b: Button) -> void:
	var d := -1 if event.is_action_pressed("ui_left", true) else 1 if event.is_action_pressed("ui_right", true) else 0
	if d == 0:
		return
	b.accept_event()
	if tabs.size() > 1:
		_pick(_step(d), true)


## The next tab that's on, `d` (1 or -1) along, wrapping.
func _step(d: int) -> int:
	var i := current
	for n in tabs.size():
		i = posmod(i + d, tabs.size())
		if not off.has(i):
			return i
	return current


func _show(b: Button) -> void:
	if is_instance_valid(b) and b.is_inside_tree():
		ensure_control_visible(b)


## Flat tabs: the current one white and underlined, the others muted; the focus outlined as on
## every other control.
static func _style(b: Button) -> void:
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(14)
	flat.content_margin_left = 24
	flat.content_margin_right = 24
	var under := flat.duplicate() as StyleBoxFlat
	under.border_color = UiKit.ACCENT
	under.border_width_bottom = 4
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = UiKit.BUTTON
	var focus := flat.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = UiKit.ACCENT
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(4)
	b.add_theme_stylebox_override(&"normal", flat)
	b.add_theme_stylebox_override(&"disabled", flat)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", under)
	b.add_theme_stylebox_override(&"hover_pressed", under)
	b.add_theme_stylebox_override(&"focus", focus)
	b.add_theme_color_override(&"font_color", UiKit.MUTED)
	b.add_theme_color_override(&"font_hover_color", Color.WHITE)
	b.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override(&"font_focus_color", Color.WHITE)
