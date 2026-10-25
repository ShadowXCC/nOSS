class_name MenuStack
extends Control
## Pages over one another (docs/UI_FLOW.md §1, §4): push and pop, and only the top one shows, so
## a screen reader never reads the ones under it. When the top one goes, the one under comes back
## with the focus where it was. Anything with a `closed` signal (a MenuPage, the old menus) is
## taken off when it emits it.
##
## Godot 4.7 doesn't tell screen readers when a control is hidden or shown, so each change here
## asks for an accessibility update too (set_shown()); a hidden node's whole subtree then goes.
## The base is taken out of the tree instead: an update on one of the main menu's hidden parts
## (its version label) took every screen after it off as well, once a player's card was up.

## The last page went: `base` is back.
signal emptied

## Shown while no page is up (the main menu's logo and buttons), out of the tree under the first
## page.
var base: Array[CanvasItem] = []

## {page, refocus: Callable, focus: instance id of what had the focus when a page went over it}
var _entries: Array[Dictionary] = []
var _base_focus := 0
var _base_places: Array = [] # [node, parent, index] of the base while it's out


func _notification(what: int) -> void:
	# Gone with pages up (a session started from one): the base goes too.
	if what == NOTIFICATION_PREDELETE:
		for place: Array in _base_places:
			if is_instance_valid(place[0]) and not (place[0] as Node).is_inside_tree():
				(place[0] as Node).free()


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
		for c in base: # every place first: each removal moves the ones after it
			if is_instance_valid(c) and c.get_parent():
				_base_places.append([c, c.get_parent(), c.get_index()])
		_base_places.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
		for place: Array in _base_places:
			(place[1] as Node).remove_child(place[0])
	else:
		var below: Dictionary = _entries[-1]
		below.focus = id
		set_shown(below.page, false)
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


## Shows or hides `c`, for screen readers too.
static func set_shown(c: CanvasItem, on: bool) -> void:
	c.visible = on
	c.queue_accessibility_update()


func _show_top() -> void:
	if _entries.is_empty():
		for place: Array in _base_places:
			var parent := place[1] as Node
			if is_instance_valid(place[0]) and is_instance_valid(parent):
				parent.add_child(place[0])
				parent.move_child(place[0], mini(int(place[2]), parent.get_child_count() - 1))
		_base_places.clear()
		_restore(_base_focus, null)
		emptied.emit()
		return
	var e: Dictionary = _entries[-1]
	var page: Control = e.page
	set_shown(page, true)
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
