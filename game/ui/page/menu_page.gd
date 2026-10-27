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
##
## A page's main action ("Next") goes in the action bar under the body with add_action(), Back
## beside it: always on screen, however long the body. (Godot 4.7.2 leaves a row that starts out
## of the scroll's view out of the screen-reader tree until it has the focus, so the checks, which
## can't send keys, couldn't reach a Next at the end of a long body; ARCHITECTURE §1.)

signal closed

## Room the right pane needs: below this width (big text, a small view) the body takes it all.
const PANE_MIN_WIDTH := 1100.0
## The body's widest without a pane, centred.
const BODY_MAX_WIDTH := 1100.0
const MARGIN := 64
## A page shorter than this (text 1.5 and up, a small view) is short: margins of SHORT_MARGIN above
## and below, and the header scrolls with the rows, so they get the room (docs/UI_FLOW.md §2).
const SHORT_HEIGHT := 800.0
const SHORT_MARGIN := 24
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
## Crumbs Back's description names otherwise ("Back to the pause menu").
const PLACES := { "Pause": "the pause menu", "Players": "the players", "Lobby": "the lobby" }

## The Back row's text and description. Empty: no Back row (the page has its own ways out). No
## description: the page before, by its crumb ("Back to Settings"; PLACES).
var back_text := "Back"
var back_hint := ""
## Prompt entries besides Select and Back: [what, label] (PromptBar).
var prompts: Array = []
## The first row takes the focus as the page opens. Off for pages stacked under another in one go
## (Drive again, back from an event), whose focus is set by hand.
var autofocus := true

## The rows go here.
var body: VBoxContainer
var back_button: Button
var prompt_bar: PromptBar

var _scroll: ScrollContainer
var _frame: MarginContainer
var _footer: MarginContainer
var _actions: HBoxContainer
var _action_list: Array[Control] = []
var _pane: VBoxContainer
var _margin: MarginContainer
var _column: VBoxContainer
## The crumbs, the step row, the title and what add_header() adds: over the content, or at the top
## of the scroll on a short page.
var _head: VBoxContainer
var _rows_box: VBoxContainer
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
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(_margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	_column = column
	_margin.add_child(column)
	_head = VBoxContainer.new()
	_head.name = "Head"
	column.add_child(_head)
	_crumb_label = Label.new()
	_crumb_label.name = "Crumbs"
	_crumb_label.theme_type_variation = &"PageCrumb"
	_crumb_label.clip_text = true
	_head.add_child(_crumb_label)
	_step_label = RichTextLabel.new()
	_step_label.name = "Steps"
	_step_label.bbcode_enabled = true
	_step_label.fit_content = true
	_step_label.scroll_active = false
	_step_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_step_label.add_theme_font_size_override(&"normal_font_size", 26)
	_step_label.add_theme_color_override(&"default_color", UiKit.MUTED)
	_step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(_step_label)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.theme_type_variation = &"PageTitle"
	_title_label.clip_text = true
	_head.add_child(_title_label)
	var content := HBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 48)
	column.add_child(content)
	var main := VBoxContainer.new()
	main.name = "Main"
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_stretch_ratio = 55.0
	content.add_child(main)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_scroll)
	_footer = MarginContainer.new()
	_footer.name = "Footer"
	_footer.visible = false
	main.add_child(_footer)
	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override(&"separation", 12)
	_footer.add_child(_actions)
	# Side margins centre the body when it has the whole width (_fit()), and leave room for the
	# focus outline.
	_frame = MarginContainer.new()
	_frame.name = "Frame"
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_frame)
	var rows := VBoxContainer.new()
	_rows_box = rows
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
		if back_hint.is_empty() and crumbs.size() >= 2:
			back_hint = "Back to " + String(PLACES.get(crumbs[-2], crumbs[-2]))
		back_button = UiKit.button(back_text, func() -> void: closed.emit(), back_hint)
		back_button.name = "Back"
		back_button.custom_minimum_size.y = UiKit.ROW_HEIGHT
		if _action_list.is_empty():
			rows.add_child(back_button)
		else: # beside the actions, on their left
			back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_actions.add_child(back_button)
			_actions.move_child(back_button, 0)
	chain(autofocus)
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


## Adds a row to the body: a focusable row is made 72 tall (UiKit.ROW_HEIGHT); a labelled one (a
## slider, a text field) gets the rows' text size too (UiKit.page_row()).
func add_row(c: Control) -> Control:
	if c is BaseButton or c is HBoxContainer:
		c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, UiKit.ROW_HEIGHT)
	if c is HBoxContainer:
		UiKit.page_row(c)
	body.add_child(c)
	_rows.append(c)
	return c


## The rows again (another tab, another device): `build` adds them, the focus goes to what `pick`
## returns (null: the first row), and only then do the old ones go, so the focus never drops on
## the way (a screen reader would find nothing focused). Freed after this frame: the control that
## asked for it may still be sending its signal.
func rebuild_rows(build: Callable, pick := Callable()) -> void:
	# A new body beside the old one, so the new rows keep their names.
	var old := body
	old.name = &"OldBody"
	body = VBoxContainer.new()
	body.name = &"Body"
	old.add_sibling(body)
	_rows.clear()
	build.call()
	chain(false)
	var target: Control = pick.call() if pick.is_valid() else null
	if target:
		target.grab_focus()
	else:
		focus_first()
	old.get_parent().remove_child(old)
	old.queue_free()


## Adds `c` to the action bar under the body (a page's "Next"), after the rows in the focus order.
func add_action(c: Control) -> Control:
	c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, UiKit.ROW_HEIGHT)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(c)
	_action_list.append(c)
	_footer.visible = true
	return c


## A group's heading in the body, in the accent colour ("Access assists").
func add_heading(text: String) -> Label:
	var l := UiKit.label(text, 30)
	l.add_theme_color_override(&"font_color", UiKit.ACCENT)
	body.add_child(l)
	return l


## Puts `c` under the title, above the body (a TabRow).
func add_header(c: Control) -> void:
	_title_label.add_sibling(c)


## Puts `c` under the body, above the prompt bar (a help line).
func add_footer(c: Control) -> void:
	prompt_bar.add_sibling(c)
	prompt_bar.get_parent().move_child(c, prompt_bar.get_index())


## Opens `page` over this one: on the MenuStack this is on, or else in its place (UiKit.open_sub:
## in a player's view, the pause menu). Either way the focus comes back where it was when it
## closes, then `on_back` is called.
func open_over(page: Control, on_back := Callable()) -> void:
	var stack := get_parent() as MenuStack
	if stack:
		stack.push(page)
		if on_back.is_valid():
			page.connect(&"closed", on_back)
		return
	var focus := UiKit.focus_owner(self)
	var id := focus.get_instance_id() if focus else 0
	UiKit.open_sub(self, page, func() -> void:
		var c := instance_from_id(id) as Control if id else null
		if c and c.is_inside_tree() and c.is_visible_in_tree():
			c.grab_focus()
		else:
			focus_first()
		if on_back.is_valid():
			on_back.call())


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


## Links the rows top to bottom, then the actions, the Back row last, and focuses the first (unless
## not `focus_first`: a list refreshed while the player is on it). Left and right go along the
## action bar.
func chain(focus_first := true) -> void:
	UiKit.chain_focus(_focus_list(), focus_first)
	_link_actions()


## Focuses the first row.
func focus_first() -> void:
	var list := _focus_list()
	for c: Control in list:
		var target := UiKit._focus_target(c)
		if target and target.is_visible_in_tree():
			target.grab_focus()
			return


## The rows, the actions and Back, in the focus order.
func _focus_list() -> Array:
	var list: Array = _rows.duplicate()
	list.append_array(_action_list)
	if back_button:
		list.append(back_button)
	return list


## Left and right along the action bar (Back first, as shown).
func _link_actions() -> void:
	if _action_list.is_empty():
		return
	var bar := _actions.get_children().filter(func(c: Node) -> bool: return c is Control and UiKit._focus_target(c) != null)
	for i in bar.size():
		var c := UiKit._focus_target(bar[i])
		c.focus_neighbor_left = c.get_path_to(UiKit._focus_target(bar[maxi(i - 1, 0)]))
		c.focus_neighbor_right = c.get_path_to(UiKit._focus_target(bar[mini(i + 1, bar.size() - 1)]))


## The body's scroll (tests, and pages that keep their place).
func scroll() -> ScrollContainer:
	return _scroll


func _unhandled_input(event: InputEvent) -> void:
	# Not while a page opened over this one in its place (open_over()) has it, nor mid-typing.
	if event.is_action_pressed("ui_cancel") and _scroll.is_visible_in_tree():
		var focus := UiKit.focus_owner(self)
		if focus is LineEdit and (focus as LineEdit).is_editing():
			return
		get_viewport().set_input_as_handled()
		closed.emit()


func _fit() -> void:
	if _scroll == null:
		return
	var short := size.y < SHORT_HEIGHT
	_margin.add_theme_constant_override(&"margin_top", SHORT_MARGIN if short else MARGIN)
	_margin.add_theme_constant_override(&"margin_bottom", SHORT_MARGIN if short else MARGIN)
	var head_in := _rows_box if short else _column
	if _head.get_parent() != head_in:
		var had := UiKit.focus_owner(self) if is_inside_tree() else null # a tab
		_head.reparent(head_in, false)
		head_in.move_child(_head, 0)
		if had and is_instance_valid(had) and had.is_inside_tree() and _head.is_ancestor_of(had):
			had.grab_focus()
	_pane.visible = _pane.get_child_count() > 0 and size.x >= PANE_MIN_WIDTH
	var side := 8
	if not _pane.visible:
		side = maxi(8, floori((_scroll.size.x - BODY_MAX_WIDTH) / 2.0))
	for frame: MarginContainer in [_frame, _footer]:
		frame.add_theme_constant_override(&"margin_left", side)
		frame.add_theme_constant_override(&"margin_right", side)
	var c := UiKit.focus_owner(self) if is_inside_tree() else null
	if c and _scroll.is_ancestor_of(c):
		_queue_reveal(c)


func _on_focus_changed(c: Control) -> void:
	if c and _scroll and _scroll.is_ancestor_of(c):
		_queue_reveal(c)
	_focused(c)


## The focus moved (anywhere in this page's viewport). Pages that follow it override this.
func _focused(_c: Control) -> void:
	pass


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
