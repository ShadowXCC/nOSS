extends EditorTool
## The Water tool (D240): the track's lakes (D224). Click corner by corner to draw a lake's
## outline (the first corner again, or Finish, closes it; its level starts just under the lowest
## ground round it); click a lake to pick it, then drag its corners, set its name and level, dig
## its bed into the ground (the water shows only where the ground is under its level), or delete
## it. Not on fitted scenes (their water is a surface tag) or tracks with no terrain.
## Keys and controller: the crosshair places corners (Enter or A), picks a lake, then grabs and
## drops its corners; [ ] (LB/RB) step through the lakes; Delete (X) takes off the last corner
## drawn, or the picked corner.

## A corner is under the cursor within this many pixels.
const PICK_PX := 22.0
## A new lake's level is this far under the lowest ground round it.
const BELOW_SHORE_M := 0.2
## A corner this close to the last one isn't added (a double click); this close to the first, it
## closes the outline.
const MIN_SIDE_M := 1.0

var selected := -1
var point := -1
var hover := -1
## Dig bed: this far under the level, reached this far in from the outline.
var depth := 2.5
var shore := 8.0
## The outline being drawn (x, z): not in the draft until it's closed.
var drawing := PackedVector2Array()
var _cursor := Vector3.ZERO
var _dragging := -1
var _name_typed := ""


func title() -> String:
	return "Water"


func available() -> bool:
	return draft.terrain != null and draft.scene == null


func hint() -> String:
	if not drawing.is_empty():
		return "Click the next corner · the first one (or Finish) closes it · Del takes off the last"
	if selected >= 0:
		return "Drag a corner · [ ] other lakes · Del removes a corner · F5 drives"
	return "Click the ground to start a lake · click a lake to pick it · [ ] step"


func activate() -> void:
	selected = int(draft.view.get("lake", selected))
	if draft.lake(selected) == null:
		selected = -1
	point = -1
	hover = -1


func selection_state() -> Dictionary:
	return { "lake": selected }


# --- the view -----------------------------------------------------------------------------


func pointer(e: Dictionary) -> void:
	if e.hit.hit:
		_cursor = e.hit.position
	match String(e.kind):
		"hover":
			var h := -1
			if drawing.size() >= 3 and _near_first(e):
				h = 0
			elif drawing.is_empty() and selected >= 0:
				h = _point_near(_cursor) if e.crosshair else _point_at(e.screen)
			if h != hover:
				hover = h
				refresh_gizmos()
			else:
				_cursor_line()
		"press":
			if not drawing.is_empty():
				view.grabbing = false
				if drawing.size() >= 3 and _near_first(e):
					_finish()
				elif e.hit.hit:
					_add_corner(Vector2(_cursor.x, _cursor.z))
				return
			if selected >= 0:
				var i := _point_near(_cursor) if e.crosshair else _point_at(e.screen)
				if i >= 0:
					_select_point(i)
					_dragging = i
					if e.crosshair:
						editor.say("Corner %d picked up" % (i + 1))
					return
			view.grabbing = false
			if not e.hit.hit:
				return
			var at := _lake_at(_cursor)
			if at >= 0:
				if at != selected:
					_select(at)
			elif selected >= 0:
				_select(-1)
			else:
				_add_corner(Vector2(_cursor.x, _cursor.z))
		"drag":
			if _dragging >= 0 and e.hit.hit:
				draft.drag_lake_point(selected, _dragging, Vector2(_cursor.x, _cursor.z))
		"release":
			if _dragging >= 0:
				var k := _dragging
				_dragging = -1
				_end_move(k, bool(e.crosshair))


func action(name: String) -> bool:
	match name:
		"delete":
			if not drawing.is_empty():
				_take_off_last()
			elif selected >= 0 and point >= 0:
				_delete_point()
			elif selected >= 0:
				editor.say("Pick a corner, or use Delete lake")
			else:
				editor.say("Pick a lake first")
			return true
		"prev", "next":
			if not drawing.is_empty():
				editor.say("Finish or cancel the outline first")
				return true
			var n := draft.lakes().size()
			if n == 0:
				editor.say("No lakes")
				return true
			_select(posmod(selected + (1 if name == "next" else -1), n) if selected >= 0 else 0, true)
			return true
	return false


func draft_changed(_what: StringName) -> void:
	if selected >= 0 and draft.lake(selected) == null:
		selected = -1
		point = -1
	if point >= _corners().size():
		point = _corners().size() - 1
	if _dragging < 0 and editor.tool == self and not typing():
		editor.refresh_panel()


func refresh_gizmos() -> void:
	var g := view.gizmos
	g.show_track(draft.track(), [])
	var lakes := draft.lakes()
	for i in lakes.size():
		var w: Dictionary = lakes[i]
		g.show_outline(_at_level(TrackDraft.lake_outline(w), float(w.y)), true,
			g.colors.get("p1", Color.WHITE) if i == selected else Color(0.6, 0.85, 1.0, 0.7), _name(i))
	if drawing.is_empty():
		g.show_points(_corners(), point, hover)
		g.show_brush(Vector3.ZERO, 0.0, Callable())
		return
	var pts := _on_ground(drawing)
	g.show_outline(pts, false, g.colors.get("warn", Color.WHITE))
	g.show_points(pts, -1, hover)
	_cursor_line()


## The outline's next side, from the last corner to the cursor.
func _cursor_line() -> void:
	if drawing.is_empty():
		return
	var last := drawing[drawing.size() - 1]
	view.gizmos.show_line(Vector3(last.x, _ground(last), last.y), _cursor, view.gizmos.colors.get("warn", Color.WHITE))


## The picked lake's corners, at its level.
func _corners() -> PackedVector3Array:
	var w: Variant = draft.lake(selected)
	return _at_level(TrackDraft.lake_outline(w), float(w.y)) if w != null else PackedVector3Array()


static func _at_level(outline: PackedVector2Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in outline:
		out.append(Vector3(p.x, y, p.y))
	return out


func _on_ground(outline: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in outline:
		out.append(Vector3(p.x, _ground(p), p.y))
	return out


func _ground(p: Vector2) -> float:
	return draft.terrain.height_at(p.x, p.y) if draft.terrain else 0.0


func _reach() -> float:
	return maxf(view.camera.distance * 0.04, 3.0)


func _point_at(screen: Vector2) -> int:
	var best := -1
	var best_d := PICK_PX
	var pts := _corners()
	for i in pts.size():
		var s := view.screen_of(pts[i])
		if s.x < 0.0:
			continue
		var d := s.distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	return best


func _point_near(at: Vector3) -> int:
	var best := -1
	var reach := _reach()
	var pts := _corners()
	for i in pts.size():
		var d := Vector2(at.x, at.z).distance_to(Vector2(pts[i].x, pts[i].z))
		if d < reach:
			reach = d
			best = i
	return best


## The cursor is on the outline's first corner (a click there closes it).
func _near_first(e: Dictionary) -> bool:
	var first := drawing[0]
	var d := Vector2(_cursor.x, _cursor.z).distance_to(first)
	if e.crosshair:
		return d < _reach()
	var s := view.screen_of(Vector3(first.x, _ground(first), first.y))
	return d < MIN_SIDE_M or (s.x >= 0.0 and s.distance_to(e.screen) < PICK_PX)


## The lake `at` is in (the picked one first), -1 if none.
func _lake_at(at: Vector3) -> int:
	var lakes := draft.lakes()
	var p := Vector2(at.x, at.z)
	for i in [selected] + range(lakes.size()):
		if i >= 0 and i < lakes.size() and Geometry2D.is_point_in_polygon(p, TrackDraft.lake_outline(lakes[i])):
			return i
	return -1


func _select(i: int, look := false) -> void:
	selected = i
	point = -1
	hover = -1
	editor.refresh_panel()
	refresh_gizmos()
	editor._hint.text = hint()
	if i < 0:
		editor.say("No lake picked")
		return
	editor.say(_line(i))
	if look:
		var outline := TrackDraft.lake_outline(draft.lake(i))
		var box := Rect2(outline[0], Vector2.ZERO)
		for p in outline:
			box = box.expand(p)
		view.camera.focus(Vector3(box.get_center().x, float(draft.lake(i).y), box.get_center().y), clampf(box.size.length() * 1.2, 120.0, 3000.0))


func _select_point(i: int) -> void:
	point = i
	editor.refresh_panel()
	refresh_gizmos()
	if i >= 0:
		editor.say("Corner %d of %d" % [i + 1, _corners().size()])


func _step_point(by: int) -> void:
	var n := _corners().size()
	if n == 0:
		return
	_select_point(posmod(point + by, n) if point >= 0 else 0)
	view.camera.focus(_corners()[point])


## A dragged corner put down: kept, or put back if the outline would cross itself.
func _end_move(k: int, crosshair: bool) -> void:
	if Geometry2D.triangulate_polygon(TrackDraft.lake_outline(draft.lake(selected))).is_empty():
		draft.cancel_lake_move()
		editor.say("Outline crosses itself")
	else:
		draft.end_lake_move()
		if crosshair:
			editor.say("Corner %d put down" % (k + 1))
	editor.refresh_panel()
	refresh_gizmos()


func _set_point(i: int, p: Vector2) -> void:
	draft.drag_lake_point(selected, i, p)
	_end_move(i, false)


func _delete_point() -> void:
	var outline := TrackDraft.lake_outline(draft.lake(selected))
	if outline.size() <= 3:
		editor.say("A lake keeps three corners")
		return
	var rest := outline.duplicate()
	rest.remove_at(point)
	if Geometry2D.triangulate_polygon(rest).is_empty():
		editor.say("That would cross the outline")
		return
	var was := point
	draft.delete_lake_point(selected, point)
	point = mini(was, outline.size() - 2)
	editor.say("Corner %d deleted" % (was + 1))
	refresh_gizmos()


# --- drawing ------------------------------------------------------------------------------


func _add_at_cursor() -> void:
	var hit := view.pick(view.cursor())
	if not hit.hit:
		editor.say("Point the view at the ground")
		return
	_cursor = hit.position
	if drawing.size() >= 3 and Vector2(_cursor.x, _cursor.z).distance_to(drawing[0]) < _reach():
		_finish()
	else:
		_add_corner(Vector2(_cursor.x, _cursor.z))


func _add_corner(p: Vector2) -> void:
	if drawing.is_empty() and draft.lakes().size() >= TrackDraft.MAX_LAKES:
		editor.say("%d lakes at most" % TrackDraft.MAX_LAKES)
		return
	if drawing.size() >= TrackDraft.MAX_LAKE_POINTS:
		editor.say("%d corners at most" % TrackDraft.MAX_LAKE_POINTS)
		return
	if not drawing.is_empty() and p.distance_to(drawing[drawing.size() - 1]) < MIN_SIDE_M:
		return
	if drawing.is_empty():
		selected = -1
		point = -1
	drawing.append(Vector2(snappedf(p.x, 0.01), snappedf(p.y, 0.01)))
	hover = -1
	_drawn("Corner %d" % drawing.size())


func _take_off_last() -> void:
	drawing.remove_at(drawing.size() - 1)
	hover = -1
	_drawn("Corner %d taken off" % (drawing.size() + 1) if not drawing.is_empty() else "Outline cancelled")


func _cancel() -> void:
	drawing.clear()
	hover = -1
	_drawn("Outline cancelled")


## The outline changed: say `text`, show it.
func _drawn(text: String) -> void:
	editor.say(text)
	editor.refresh_panel()
	refresh_gizmos()
	editor._hint.text = hint()


## Closes the outline into a lake, just under the lowest ground round it.
func _finish() -> void:
	if drawing.size() < 3:
		editor.say("A lake needs three corners")
		return
	if Geometry2D.triangulate_polygon(drawing).is_empty():
		editor.say("Outline crosses itself")
		return
	var low := draft.terrain.shore_low(drawing)
	var y := snappedf((low.y if is_finite(low.y) else 0.0) - BELOW_SHORE_M, 0.01)
	var points := []
	for p in drawing:
		points.append([p.x, p.y])
	var i := draft.add_lake({ "name": _free_name(), "y": y, "points": points })
	if i < 0:
		editor.say("%d lakes at most" % TrackDraft.MAX_LAKES)
		return
	drawing.clear()
	_select(i)
	editor.say("%s added · %.1f m" % [_name(i), y])


# --- the panel ----------------------------------------------------------------------------


func panel() -> Array:
	var out := []
	if not drawing.is_empty():
		out.append(UiKit.label("New lake · %d corners" % drawing.size(), 26))
		out.append(_text("Click each corner in turn. Click the first one again to close it."))
		out.append(UiKit.button("Add corner at cursor", _add_at_cursor, "Enter or A in the view"))
		out.append(UiKit.button("Finish lake", _finish, "Close it: three corners or more"))
		out.append(UiKit.button("Take off last corner", func() -> void: action("delete"), "Delete or X"))
		out.append(UiKit.button("Cancel", _cancel, "Throw the outline away"))
		return out
	var lakes := draft.lakes()
	if selected < 0:
		out.append(UiKit.button("New lake at cursor", _add_at_cursor, "Its first corner; click the rest in the view"))
		if lakes.is_empty():
			out.append(_text("No lakes yet. Click the ground to start one."))
			return out
		out.append(UiKit.label("%d of %d lakes" % [lakes.size(), TrackDraft.MAX_LAKES], 26))
		for i in lakes.size():
			out.append(UiKit.button(_line(i), _select.bind(i, true), "Pick it and look at it"))
		return out
	var w: Dictionary = lakes[selected]
	var row := HBoxContainer.new()
	for b: Button in [UiKit.button("Previous", func() -> void: action("prev"), "[ or LB"), UiKit.button("Next", func() -> void: action("next"), "] or RB")]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	out.append(row)
	out.append(UiKit.label(_line(selected), 26))
	var name_row := UiKit.text_field("Name", String(w.get("name", "")), func(v: String) -> void: _name_typed = v, 64, "Shown in the editor", _set_name)
	(name_row.get_child(1) as LineEdit).focus_exited.connect(func() -> void:
		if _name_typed:
			_set_name(_name_typed))
	out.append(name_row)
	out.append(UiKit.number("Level", float(w.y), -100.0, 500.0, 0.1, "%.2f m", func(v: float) -> void: draft.set_lake(selected, "y", v), "The water's height"))
	out.append(UiKit.button("Pick height", _pick_height, "The ground's height at the cursor"))
	out.append(UiKit.number("Bed depth", depth, 0.5, 20.0, 0.5, "%.1f m", func(v: float) -> void: depth = v, "How far Dig bed goes under the level"))
	out.append(UiKit.number("Shore", shore, 0.0, 50.0, 1.0, "%.0f m", func(v: float) -> void: shore = v, "How far in from the edge it gets that deep"))
	out.append(UiKit.button("Dig bed", _dig, "Lower the ground under the lake so the water shows"))
	var corners := _corners()
	out.append(UiKit.label("Corner %d of %d" % [point + 1, corners.size()] if point >= 0 else "%d corners" % corners.size(), 24))
	var step := HBoxContainer.new()
	for b: Button in [UiKit.button("Previous corner", _step_point.bind(-1), "Pick it"), UiKit.button("Next corner", _step_point.bind(1), "Pick it")]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.add_child(b)
	out.append(step)
	if point >= 0 and point < corners.size():
		var i := point
		var p := Vector2(corners[i].x, corners[i].z)
		var q := Vector2(corners[(i + 1) % corners.size()].x, corners[(i + 1) % corners.size()].z)
		out.append(UiKit.number("X", p.x, -20000.0, 20000.0, 1.0, "%.0f m", func(v: float) -> void: _set_point(i, Vector2(v, p.y))))
		out.append(UiKit.number("Z", p.y, -20000.0, 20000.0, 1.0, "%.0f m", func(v: float) -> void: _set_point(i, Vector2(p.x, v))))
		out.append(UiKit.button("Insert corner after", func() -> void:
			draft.add_lake_point(selected, i + 1, (p + q) / 2.0)
			_select_point(i + 1), "Halfway to the next one"))
		out.append(UiKit.button("Delete corner", _delete_point, "Delete or X"))
	out.append(UiKit.button("Delete lake", func() -> void:
		var was := _name(selected)
		draft.delete_lake(selected)
		_select(-1)
		editor.say(was + " deleted"), "Ctrl+Z brings it back"))
	out.append(UiKit.button("Deselect", func() -> void: _select(-1), "Back to the list"))
	return out


func _set_name(v: String) -> void:
	_name_typed = ""
	var name := v.strip_edges().left(64)
	if selected >= 0 and name != String(draft.lake(selected).get("name", "")):
		draft.set_lake(selected, "name", name)


func _pick_height() -> void:
	var hit := view.pick(view.cursor())
	if not hit.hit:
		editor.say("Point the view at the ground")
		return
	var y := snappedf(_ground(Vector2(hit.position.x, hit.position.z)), 0.01)
	draft.set_lake(selected, "y", y)
	editor.say("Level %.2f m" % y)


func _dig() -> void:
	editor.say("Bed dug" if draft.dig_lake_bed(selected, depth, shore) else "Already dug")


## "Lake 1 · 4.3 m".
func _line(i: int) -> String:
	return "%s · %.1f m" % [_name(i), float(draft.lake(i).y)]


func _name(i: int) -> String:
	var n := String(draft.lake(i).get("name", ""))
	return n if n else "Lake %d" % (i + 1)


## "Lake N", the first N no lake has.
func _free_name() -> String:
	var names := draft.lakes().map(func(w: Dictionary) -> String: return String(w.get("name", "")))
	var n := 1
	while ("Lake %d" % n) in names:
		n += 1
	return "Lake %d" % n


static func _text(t: String) -> Label:
	var l := UiKit.label(t, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
