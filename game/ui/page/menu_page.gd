class_name MenuPage
extends Control
## A full-screen page (docs/UI_FLOW.md §1, §2, §4): the breadcrumb, the step row, the title, a
## scrolling body, an optional right pane, and a PromptBar at the bottom. Cancel goes back from
## anywhere on it (`closed`), and a "Back" row at the end of the body does the same for the mouse
## and screen readers.
##
## The body scrolls to the focused control itself, on its viewport's gui_focus_changed, in the
## scroll's own coordinates: so it follows the focus in a player's view too, where the menus are
## scaled and follow_focus misses.
##
## Build it in _build(), or from outside with add_row() and then chain(). Pages go on a
## MenuStack, which shows one at a time.

signal closed

## Room the right pane needs: below this width (big text, a small view) the body takes it all.
const PANE_MIN_WIDTH := 1100.0
## The body's widest without a pane, centred.
const BODY_MAX_WIDTH := 1100.0
const MARGIN := 64
## Space kept round the focused row when scrolling to it.
const REVEAL_MARGIN := 12

## The page's title.
var title := ""
## Where it is: every name on the way, this page's last ("Local Drive", "Racing"), shown joined
## by " › ".
var crumbs: PackedStringArray = []
## An event's steps ("Event", "Settings", "Class", "Players") and which this is (from 0). No
## step row without them.
var steps: PackedStringArray = []
var step := -1
## The Back row's text and description. Empty: no Back row (the page has its own ways out).
var back_text := "Back"
var back_hint := ""
## Prompt entries besides Select and Back: [what, label] (PromptBar).
var prompts: Array = []

## The rows go here.
var body: VBoxContainer
var back_button: Button
var prompt_bar: PromptBar

var _scroll: ScrollContainer
var _frame: MarginContainer
var _pane: VBoxContainer
var _title_label: Label
var _crumb_label: Label
var _step_label: RichTextLabel
var _rows: Array[Control] = []
var _reveal_id := 0 # the control to scroll to next frame


func _ready() -> void:
	theme = UiKit.page_theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiKit.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	margin.add_child(column)
	_crumb_label = Label.new()
	_crumb_label.name = "Crumbs"
	_crumb_label.theme_type_variation = &"PageCrumb"
	_crumb_label.clip_text = true
	column.add_child(_crumb_label)
	_step_label = RichTextLabel.new()
	_step_label.name = "Steps"
	_step_label.bbcode_enabled = true
	_step_label.fit_content = true
	_step_label.scroll_active = false
	_step_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_step_label.add_theme_font_size_override(&"normal_font_size", 26)
	_step_label.add_theme_color_override(&"default_color", UiKit.MUTED)
	_step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_step_label)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.theme_type_variation = &"PageTitle"
	_title_label.clip_text = true
	column.add_child(_title_label)
	var content := HBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 48)
	column.add_child(content)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = 55.0
	content.add_child(_scroll)
	# Side margins centre the body when it has the whole width (_fit()), and leave room for the
	# focus outline.
	_frame = MarginContainer.new()
	_frame.name = "Frame"
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_frame)
	var rows := VBoxContainer.new()
	_frame.add_child(rows)
	body = VBoxContainer.new()
	body.name = "Body"
	rows.add_child(body)
	_pane = VBoxContainer.new()
	_pane.name = "Pane"
	_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pane.size_flags_stretch_ratio = 45.0
	_pane.visible = false
	content.add_child(_pane)
	prompt_bar = PromptBar.new()
	prompt_bar.extra = prompts
	column.add_child(prompt_bar)
	refresh_header()
	_build()
	if back_text:
		back_button = UiKit.button(back_text, func() -> void: closed.emit(), back_hint)
		back_button.name = "Back"
		back_button.custom_minimum_size.y = UiKit.ROW_HEIGHT
		rows.add_child(back_button)
	chain()
	resized.connect(_fit)
	_scroll.resized.connect(_fit)
	_fit.call_deferred()


## Fills the body (pages override it).
func _build() -> void:
	pass


func _enter_tree() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _exit_tree() -> void:
	get_viewport().gui_focus_changed.disconnect(_on_focus_changed)


## Shows the title, crumbs and steps again (after they change).
func refresh_header() -> void:
	if _title_label == null:
		return
	_title_label.text = title
	_crumb_label.text = " › ".join(crumbs)
	_crumb_label.visible = not crumbs.is_empty()
	_step_label.visible = not steps.is_empty() and step >= 0
	if _step_label.visible:
		var names := PackedStringArray()
		for i in steps.size():
			names.append("[color=#%s]%s[/color]" % [UiKit.ACCENT.to_html(false), steps[i]] if i == step else steps[i])
		_step_label.text = "%s   %s" % [step_text(), " · ".join(names)]
		_step_label.accessibility_name = "%s: %s" % [step_text(), steps[step]]


## "Step 2 of 4" (empty without steps).
func step_text() -> String:
	return "Step %d of %d" % [step + 1, steps.size()] if not steps.is_empty() and step >= 0 else ""


## Adds a row to the body: a focusable row is made 72 tall (UiKit.ROW_HEIGHT).
func add_row(c: Control) -> Control:
	if c is BaseButton or c is HBoxContainer:
		c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, UiKit.ROW_HEIGHT)
	body.add_child(c)
	_rows.append(c)
	return c


## A line of text in the body (muted unless `strong`).
func add_text(text: String, strong := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not strong:
		l.theme_type_variation = &"PageCrumb"
	body.add_child(l)
	return l


## Puts `c` in the right pane (a track's map, a car). It shows when there's room for it.
func set_pane(c: Control) -> void:
	for old in _pane.get_children():
		_pane.remove_child(old)
		old.queue_free()
	if c:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_pane.add_child(c)
	_fit()


## The pane shows (it has something, and there's room).
func pane_shown() -> bool:
	return _pane.visible


## Links the rows top to bottom, the Back row last, and focuses the first (unless not
## `focus_first`: a list refreshed while the player is on it).
func chain(focus_first := true) -> void:
	var list: Array = _rows.duplicate()
	if back_button:
		list.append(back_button)
	UiKit.chain_focus(list, focus_first)


## Focuses the first row.
func focus_first() -> void:
	var list: Array = _rows.duplicate()
	if back_button:
		list.append(back_button)
	for c: Control in list:
		var target := UiKit._focus_target(c)
		if target and target.is_visible_in_tree():
			target.grab_focus()
			return


## The body's scroll (tests, and pages that keep their place).
func scroll() -> ScrollContainer:
	return _scroll


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()


func _fit() -> void:
	if _scroll == null:
		return
	_pane.visible = _pane.get_child_count() > 0 and size.x >= PANE_MIN_WIDTH
	var side := 8
	if not _pane.visible:
		side = maxi(8, floori((_scroll.size.x - BODY_MAX_WIDTH) / 2.0))
	_frame.add_theme_constant_override(&"margin_left", side)
	_frame.add_theme_constant_override(&"margin_right", side)
	var c := UiKit.focus_owner(self) if is_inside_tree() else null
	if c and _scroll.is_ancestor_of(c):
		_queue_reveal(c)


func _on_focus_changed(c: Control) -> void:
	if c and _scroll and _scroll.is_ancestor_of(c):
		_queue_reveal(c)


## Scrolls to `c` at the start of the next frame, once this one's layout is done: a row focused
## as the page opens has no place yet.
func _queue_reveal(c: Control) -> void:
	_reveal_id = c.get_instance_id()
	var tree := get_tree()
	if tree and not tree.process_frame.is_connected(_reveal):
		tree.process_frame.connect(_reveal, CONNECT_ONE_SHOT)


## Scrolls the body just enough to show the control queued (with REVEAL_MARGIN round it).
func _reveal() -> void:
	var c := instance_from_id(_reveal_id) as Control
	if c == null or not c.is_inside_tree() or not _scroll.is_ancestor_of(c):
		return
	var xf := _scroll.get_global_transform().affine_inverse() * c.get_global_transform()
	var top := xf.origin.y
	var bottom := top + c.size.y * xf.get_scale().y
	var room := _scroll.size.y
	if top < REVEAL_MARGIN:
		_scroll.scroll_vertical += floori(top) - REVEAL_MARGIN
	elif bottom > room - REVEAL_MARGIN:
		_scroll.scroll_vertical += ceili(bottom - room) + REVEAL_MARGIN
