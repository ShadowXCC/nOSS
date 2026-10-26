class_name TabbedPage
extends MenuPage
## A page in tabs (docs/UI_FLOW.md §4, §9): a TabRow under the title, the current tab's rows in
## the body, and a help line above the prompt bar with the focused control's description. Each
## tab with settings ends in "Reset to defaults", which asks first.
##
## Subclasses set `tabs` and build one tab at a time in _build_tab(); show_tab() builds it again
## (after a reset, or a row that comes or goes).

## Suffixes the help line leaves off: the prompt bar shows them.
const HINTS := ["Left and right to change", "Enter to type"]

var tabs: PackedStringArray = []
## Tabs that show but are off: index -> why ("Coming soon"; TabRow.off).
var tabs_off := {}
## The current tab (an index into `tabs`).
var tab := 0

var tab_row: TabRow
var help: Label


func _init() -> void:
	prompts = [["tabs", "Tabs"]]


func _build() -> void:
	tab_row = TabRow.new(tabs)
	tab_row.off = tabs_off
	tab_row.current = tab
	tab_row.changed.connect(func(i: int, on_row: bool) -> void: show_tab(i, "" if on_row else "first"))
	add_header(tab_row)
	help = Label.new()
	help.name = "Help"
	help.theme_type_variation = &"PageCrumb"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.max_lines_visible = 2
	help.custom_minimum_size.y = 64 # two lines, so the body doesn't jump as it changes
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_footer(help)
	_fill()


## Builds tab `i`'s rows and focuses: its first row ("first"), the row whose name starts with
## `focus`, or the current tab's button ("").
func show_tab(i: int, focus := "first") -> void:
	tab = clampi(i, 0, tabs.size() - 1)
	tab_row.select(tab)
	rebuild_rows(_fill, func() -> Control:
		if focus.is_empty():
			return tab_row.button()
		for c: Control in _rows:
			var t := UiKit._focus_target(c)
			if t and focus != "first" and String(t.accessibility_name).begins_with(focus):
				return t
		return _first_row())
	scroll().scroll_vertical = 0


## The current tab's name.
func tab_name() -> String:
	return tabs[tab] if tab < tabs.size() else ""


## Fills the body with tab `name`'s rows (add_row(), add_heading()).
func _build_tab(_name: String) -> void:
	pass


## Whether tab `name` has settings to reset.
func _can_reset(_name: String) -> bool:
	return true


## Puts tab `name`'s settings back to their defaults.
func _reset(_name: String) -> void:
	pass


## A line on the reset question saying what else goes ("Custom buttons and keys go too.").
func _reset_detail(_name: String) -> String:
	return ""


## The tab row, the rows, Back; the tabs not shown lead where the current one does.
func chain(focus_first := true) -> void:
	var list: Array = [tab_row.button()] if tab_row and tab_row.button() else []
	list.append_array(_rows)
	if back_button:
		list.append(back_button)
	UiKit.chain_focus(list, false)
	if tab_row:
		tab_row.link()
	var first := _first_row()
	if focus_first and first:
		UiKit.focus_later(first)


func focus_first() -> void:
	var first := _first_row()
	if first:
		first.grab_focus()


func _fill() -> void:
	var which := tab_name()
	_build_tab(which)
	if _can_reset(which):
		var reset := UiKit.button("Reset to defaults", _ask_reset, "%s settings back to their defaults" % which)
		reset.name = "Reset"
		add_row(reset)


func _first_row() -> Control:
	for c: Control in _rows:
		var t := UiKit._focus_target(c)
		if t and t.is_visible_in_tree():
			return t
	return back_button if back_button and back_button.is_visible_in_tree() else null


func _ask_reset() -> void:
	var which := tab_name()
	var confirm := ConfirmPage.new()
	confirm.title = "Reset %s?" % which
	confirm.crumbs = crumbs + PackedStringArray(["Reset %s" % which])
	confirm.detail = _reset_detail(which)
	confirm.no_text = "Keep"
	confirm.no_hint = "Leave them as they are"
	confirm.yes_text = "Reset"
	confirm.yes_hint = "%s settings back to their defaults" % which
	confirm.confirmed.connect(func() -> void:
		_reset(which)
		confirm.closed.emit()
		show_tab(tab, "Reset to defaults"))
	open_over(confirm)


## The help line: the focused control's description, on this page's rows only.
func _focused(c: Control) -> void:
	if help == null:
		return
	help.text = help_for(c) if c and is_ancestor_of(c) else ""


## `c`'s description without what the prompt bar says already.
static func help_for(c: Control) -> String:
	var text := String(c.accessibility_description)
	for hint: String in HINTS:
		if text == hint:
			return ""
		text = text.trim_suffix(". " + hint)
	return text
