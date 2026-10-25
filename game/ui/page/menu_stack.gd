class_name MenuStack
extends Control
## Pages over one another (docs/UI_FLOW.md §1, §4): push and pop, and only the top one shows, so
## a screen reader never reads the ones under it. When the top one goes, the one under comes back
## with the focus where it was. Anything with a `closed` signal (a MenuPage, the old menus) is
## taken off when it emits it.

## The last page went: `base` is back.
signal emptied

## Shown while no page is up (the main menu's logo and buttons), hidden under the first page.
var base: Array[CanvasItem] = []

## {page, refocus: Callable, focus: instance id of what had the focus when a page went over it}
var _entries: Array[Dictionary] = []
var _base_focus := 0


func _init() -> void:
	name = "MenuStack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Puts `page` on top, hiding the one under it. When `page` is on top again (the one over it
## went), `refocus` is called if given (an old menu that focuses itself); otherwise the focus
## goes back where it was.
func push(page: Control, refocus := Callable()) -> Control:
	var focus := UiKit.focus_owner(self) if is_inside_tree() else null
	var id := focus.get_instance_id() if focus else 0
	if _entries.is_empty():
		_base_focus = id
		for c in base:
			if is_instance_valid(c):
				c.visible = false
	else:
		var below: Dictionary = _entries[-1]
		below.focus = id
		(below.page as Control).visible = false
	_entries.append({ "page": page, "refocus": refocus, "focus": 0 })
	if page.has_signal(&"closed"):
		page.connect(&"closed", close.bind(page))
	add_child(page)
	return page


## Takes the top page off.
func pop() -> void:
	if not _entries.is_empty():
		close(_entries[-1].page)


## Takes `page` off, and any over it; the one under comes back.
func close(page: Control) -> void:
	var i := index_of(page)
	if i < 0:
		return
	while _entries.size() > i:
		var gone: Control = _entries.pop_back().page
		if is_instance_valid(gone):
			gone.visible = false
			gone.queue_free()
	_show_top()


## Every page off (base back).
func clear() -> void:
	if not _entries.is_empty():
		close(_entries[0].page)


func top() -> Control:
	return _entries[-1].page if not _entries.is_empty() else null


func pages() -> Array[Control]:
	var out: Array[Control] = []
	for e in _entries:
		out.append(e.page)
	return out


func depth() -> int:
	return _entries.size()


func index_of(page: Control) -> int:
	for i in _entries.size():
		if _entries[i].page == page:
			return i
	return -1


func _show_top() -> void:
	if _entries.is_empty():
		for c in base:
			if is_instance_valid(c):
				c.visible = true
		_restore(_base_focus, null)
		emptied.emit()
		return
	var e: Dictionary = _entries[-1]
	var page: Control = e.page
	page.visible = true
	if (e.refocus as Callable).is_valid():
		(e.refocus as Callable).call()
	else:
		_restore(e.focus, page)


## Focus back on the control `id`, if it's still there; else `page`'s first row.
func _restore(id: int, page: Control) -> void:
	var c := instance_from_id(id) as Control if id else null
	if c and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()
	elif page is MenuPage:
		(page as MenuPage).focus_first()
