class_name ViewManager
extends Node
## Lays out the players' views (docs/ARCHITECTURE.md §6, LOC-02, LOC-03): in the main window,
## or in a borderless fullscreen window on each other monitor a player picked. Each window is
## split on its own by SplitLayout, so 1+3 and 2+2 across two monitors work. Re-flows when
## players join, leave or move monitor. A `map` control fills the spare quarter of the
## 3-player "map" layout.

signal views_changed

var map: Control:
	set(m):
		map = m
		if map:
			map.visible = false
			_main.add_child(map)
		layout()

var _layer := CanvasLayer.new()
var _main := Control.new()
var _views := {} # PlayerSlot -> PlayerView
var _windows := {} # screen -> Window
var _root_embedded := true


func _init() -> void:
	name = "Views"
	_layer.layer = 0
	add_child(_layer)
	_main.name = "Main"
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_main)


func _ready() -> void:
	_root_embedded = get_tree().root.gui_embed_subwindows


func _exit_tree() -> void:
	get_tree().root.gui_embed_subwindows = _root_embedded


func add(slot: PlayerSlot) -> PlayerView:
	var v := PlayerView.new()
	v.slot = slot
	v.name = "View%s" % slot.tag()
	_views[slot] = v
	_main.add_child(v)
	layout()
	return v


func remove(slot: PlayerSlot) -> void:
	var v: PlayerView = _views.get(slot)
	if v == null:
		return
	_views.erase(slot)
	v.queue_free()
	layout()


func view(slot: PlayerSlot) -> PlayerView:
	return _views.get(slot)


## Views in player order.
func views() -> Array[PlayerView]:
	var out: Array[PlayerView] = []
	for slot in _ordered():
		out.append(_views[slot])
	return out


## The extra windows, by monitor.
func windows() -> Dictionary:
	return _windows


func layout() -> void:
	if not is_inside_tree():
		return
	var slots := _ordered()
	var headless := DisplayServer.get_name() == "headless"
	var main_screen := 0 if headless else DisplayServer.window_get_current_screen()
	var screen_count := 1 if headless else DisplayServer.get_screen_count()
	var groups := SplitLayout.by_screen(slots.map(func(s: PlayerSlot) -> int: return s.screen), main_screen, screen_count)
	var map_area: Control = null
	var map_rect := Rect2()
	for screen: int in groups:
		var area := _main if screen == main_screen else _window_area(screen)
		var members: Array = groups[screen]
		var rects := SplitLayout.rects(members.size(), Settings.split_two, Settings.split_three)
		for i in members.size():
			var v: PlayerView = _views[slots[members[i]]]
			if v.get_parent() != area:
				v.reparent(area, false)
			_anchor(v, rects[i])
		var spare := SplitLayout.spare(members.size(), Settings.split_three)
		if spare.has_area() and map_area == null:
			map_area = area
			map_rect = spare
	for screen: int in _windows.keys():
		if not groups.has(screen):
			_windows[screen].queue_free()
			_windows.erase(screen)
	if map:
		map.visible = map_area != null
		if map_area:
			if map.get_parent() != map_area:
				map.reparent(map_area, false)
			_anchor(map, map_rect)
	_apply_listeners()
	views_changed.emit()


## Which views listen: everyone's, or only P1's ("P1 focus", docs/ARCHITECTURE.md §6).
func _apply_listeners() -> void:
	for slot: PlayerSlot in _views:
		_views[slot].set_listener(Settings.split_audio != "p1" or slot.index == 0)


## How many views listen; the session scales engine volume by 1/√n, since each player's own
## engine is loud in their own view.
func listener_count() -> int:
	return 1 if Settings.split_audio == "p1" else maxi(_views.size(), 1)


func _ordered() -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	slots.assign(_views.keys())
	slots.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	return slots


func _window_area(screen: int) -> Control:
	if _windows.has(screen):
		return _windows[screen].get_node("Area")
	# A native window, not one drawn inside the main window. force_native alone doesn't do it
	# (Godot 4.7, X11), so the root stops embedding while the session runs. Player menus embed
	# their popups in their own views.
	get_tree().root.gui_embed_subwindows = false
	var w := Window.new()
	w.name = "Screen%d" % screen
	w.title = "nOSS"
	w.force_native = true
	w.borderless = true
	w.transient = false
	w.current_screen = screen
	w.position = DisplayServer.screen_get_position(screen)
	w.size = DisplayServer.screen_get_size(screen)
	w.close_requested.connect(func() -> void: pass) # closes with the session
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)
	var area := Control.new()
	area.name = "Area"
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(area)
	add_child(w)
	w.mode = Window.MODE_FULLSCREEN
	_windows[screen] = w
	return area


static func _anchor(c: Control, r: Rect2) -> void:
	c.anchor_left = r.position.x
	c.anchor_top = r.position.y
	c.anchor_right = r.end.x
	c.anchor_bottom = r.end.y
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
