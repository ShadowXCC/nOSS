extends EditorTool
## The Ramps tool (EDT-10, highways only): add ramps from templates where the cursor is (an exit
## and an entry, an exit, an entry, or a crossover to the other carriageway; the carriageway is
## the one the cursor is on), pick a ramp and drag its points (Alt+drag: height), move it along
## the road, set its name, lanes, speed limit and portal, or delete it.
## Keys and controller: the crosshair picks a ramp, then grabs and drops its points; [ ] (LB/RB)
## step through the ramps; Delete (X) removes the selected point.

## A point is under the cursor within this many pixels.
const PICK_PX := 22.0
## A click this close to a ramp picks it.
const PICK_M := 12.0
## "Move along road" steps.
const MOVE_M := 25.0

var selected := ""
var point := -1
var hover := -1
var template := "interchange"
var _dragging := -1
var _height_drag := false
var _drag_from := Vector2.ZERO
var _drag_height := 0.0
var _name_typed := ""


func title() -> String:
	return "Ramps"


func available() -> bool:
	return draft.is_highway() and draft.scene == null


func hint() -> String:
	if selected:
		return "Drag a point · Alt+drag: height · [ ] other ramps · Del removes a point · F5 drives"
	return "Click a ramp to pick it · Add puts a new one at the cursor · [ ] step"


func activate() -> void:
	selected = String(draft.view.get("ramp", selected))
	if draft.ramp(selected) == null:
		selected = ""
	point = -1


func deactivate() -> void:
	super()
	view.gizmos.selected_ramp = ""


func selection_state() -> Dictionary:
	return { "ramp": selected }


# --- the view -----------------------------------------------------------------------------


func pointer(e: Dictionary) -> void:
	match String(e.kind):
		"hover":
			var h := _point_at(e.screen) if selected else -1
			if h != hover:
				hover = h
				refresh_gizmos()
		"press":
			var i := -1
			if selected:
				i = _point_at(e.screen) if not e.crosshair else _point_near(e.hit.position)
			if i >= 0:
				_select_point(i)
				_dragging = i
				_height_drag = bool(e.alt)
				_drag_from = e.screen
				_drag_height = _points()[i].y
				if e.crosshair:
					editor.say("Point %d picked up" % (i + 1))
				return
			view.grabbing = false
			var id := _ramp_near(e.hit.position) if e.hit.hit else ""
			if id:
				_select(id)
			elif selected:
				_select("")
			else:
				editor.say("No ramp here")
		"drag":
			if _dragging < 0:
				return
			var p := _points()[_dragging]
			if _height_drag:
				var up := (_drag_from.y - float(e.screen.y)) * view.camera.distance / maxf(view.size.y, 1.0)
				p.y = snappedf(_drag_height + up, 0.1)
			elif e.hit.hit:
				p = Vector3(e.hit.position.x, p.y, e.hit.position.z)
			draft.drag_ramp_point(selected, _dragging, p)
		"release":
			if _dragging >= 0:
				draft.end_ramp_move("Ramp point height" if _height_drag else "Move ramp point")
				if e.crosshair:
					editor.say("Point %d put down" % (_dragging + 1))
				_dragging = -1
				_height_drag = false
				editor.refresh_panel()


func action(name: String) -> bool:
	match name:
		"delete":
			if selected and point >= 0:
				_delete_point()
			elif selected:
				editor.say("Pick a point, or use Delete ramp")
			else:
				editor.say("Pick a ramp first")
			return true
		"prev", "next":
			var ids := _ids()
			if ids.is_empty():
				editor.say("No ramps")
				return true
			var at := ids.find(selected)
			_select(ids[posmod(at + (1 if name == "next" else -1), ids.size()) if at >= 0 else 0], true)
			return true
	return false


func draft_changed(_what: StringName) -> void:
	if selected and draft.ramp(selected) == null:
		selected = ""
		point = -1
	if point >= _points().size():
		point = _points().size() - 1
	if _dragging < 0 and editor.tool == self and not typing():
		editor.refresh_panel()


func refresh_gizmos() -> void:
	view.gizmos.selected_ramp = selected
	view.gizmos.show_track(draft.track(), [])
	view.gizmos.show_points(_points(), point, hover)


func _ids() -> Array:
	return (draft.layout.highway.get("ramps", []) as Array).map(func(r: Dictionary) -> String: return r.id)


## The selected ramp's points (where they are: a point that follows the ground is on it).
func _points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var r: Variant = draft.ramp(selected) if selected else null
	if r == null:
		return out
	for pt: Dictionary in r.points:
		var p := Vector3(pt.p[0], pt.p[1], pt.p[2])
		if pt.get("height", "ground") != "set":
			p.y = _ground(p)
		out.append(p)
	return out


func _ground(p: Vector3) -> float:
	return float(draft.terrain.ground_height().call(p.x, p.z)) if draft.terrain else 0.0


func _point_at(screen: Vector2) -> int:
	var best := -1
	var best_d := PICK_PX
	var pts := _points()
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
	var reach := maxf(view.camera.distance * 0.04, 3.0)
	var pts := _points()
	for i in pts.size():
		var d := Vector2(at.x, at.z).distance_to(Vector2(pts[i].x, pts[i].z))
		if d < reach:
			reach = d
			best = i
	return best


## The ramp whose road is under `at` (or nearest within PICK_M), "" if none.
func _ramp_near(at: Vector3) -> String:
	var t := draft.track()
	if t.highway == null:
		return ""
	var best := ""
	var best_d := INF
	for r in t.highway.ramps:
		var proj := r.track.project(at)
		var off := Vector2(at.x - proj.point.x, at.z - proj.point.z).length() - r.width / 2.0
		if off < PICK_M and off < best_d:
			best_d = off
			best = r.id
	return best


func _select(id: String, look := false) -> void:
	selected = id
	point = -1
	hover = -1
	editor.refresh_panel()
	refresh_gizmos()
	editor._hint.text = hint()
	if id.is_empty():
		editor.say("No ramp selected")
		return
	var r := draft.track().highway.ramp(id)
	var stored: Dictionary = draft.ramp(id)
	editor.say("%s · %s" % [_label(stored), _kind_text(stored)])
	if look and r:
		view.camera.focus(r.track.samples[r.track.samples.size() / 2], 250.0)


func _select_point(i: int) -> void:
	point = i
	editor.refresh_panel()
	refresh_gizmos()
	if i >= 0:
		editor.say("Point %d of %d" % [i + 1, _points().size()])


func _delete_point() -> void:
	var n := _points().size()
	if n <= 1:
		editor.say("A ramp keeps one point")
		return
	var was := point
	draft.delete_ramp_point(selected, point)
	point = mini(was, n - 2)
	editor.say("Point %d deleted" % (was + 1))
	refresh_gizmos()


## Ramps from the chosen template at `at`: the carriageway under it (or nearest), leaving there.
func _add_at(at: Vector3) -> void:
	var t := draft.track()
	if t.samples.size() < 3:
		editor.say("Add the road first")
		return
	var proj := t.project(at)
	var dir := HighwayLayout.carriageway_at(float(proj.lateral))
	var ids := draft.add_ramp(template, dir, snappedf(float(proj.distance), 1.0))
	if ids.is_empty():
		editor.say("Can't add a ramp here")
		return
	var r := draft.track().highway.ramp(ids[0])
	_select(ids[0])
	if r == null:
		editor.say("Added, but it doesn't fit here: see Check")


# --- the panel ----------------------------------------------------------------------------


func panel() -> Array:
	var out := []
	out.append(UiKit.spinner("Add", TrackDraft.RAMP_TEMPLATES, template, func(v: String) -> void: template = v, "What Add puts at the cursor"))
	out.append(UiKit.button("Add at cursor", func() -> void:
		var hit := view.pick(view.cursor())
		if hit.hit:
			_add_at(hit.position), "On the carriageway the cursor is on, leaving there"))
	var ids := _ids()
	if ids.is_empty():
		out.append(_text("No ramps yet. Put the cursor on a carriageway and Add."))
		return out
	if selected.is_empty():
		out.append(UiKit.label("%d ramps" % ids.size(), 26))
		for id: String in ids:
			var r: Dictionary = draft.ramp(id)
			out.append(UiKit.button("%s · %s" % [_label(r), _kind_text(r)], _select.bind(id, true), "Pick it and look at it"))
		return out
	var r: Dictionary = draft.ramp(selected)
	var built := draft.track().highway.ramp(selected)
	var row := HBoxContainer.new()
	for b: Button in [UiKit.button("Previous", func() -> void: action("prev"), "[ or LB"), UiKit.button("Next", func() -> void: action("next"), "] or RB")]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	out.append(row)
	out.append(UiKit.label("%s · %s" % [_label(r), _kind_text(r)], 26))
	if built == null:
		out.append(_text("It doesn't build here: see Check."))
	var name_row := UiKit.text_field("Name", String(r.get("name", "")), func(v: String) -> void: _name_typed = v, 40, "Shown on the signs", _set_name)
	(name_row.get_child(1) as LineEdit).focus_exited.connect(func() -> void:
		if _name_typed:
			_set_name(_name_typed))
	out.append(name_row)
	var lanes := [[1, "1"], [2, "2"]]
	out.append(UiKit.spinner("Lanes", lanes, int(r.get("lanes", 1)), func(v: int) -> void: draft.set_ramp(selected, "lanes", v)))
	out.append(UiKit.number("Speed limit", float(r.get("speed_kmh", TrackFormat.RAMP_DEFAULTS.speed_kmh)), 30.0, 120.0, 10.0, "%.0f km/h",
		func(v: float) -> void: draft.set_ramp(selected, "speed_kmh", v)))
	out.append(UiKit.spinner("Traffic", [[true, "Uses it"], [false, "Keeps off"]], bool(r.get("traffic", r.kind != "link")),
		func(v: bool) -> void: draft.set_ramp(selected, "traffic", v)))
	for end: Dictionary in [r.from, r.to]:
		if end.has("portal"):
			var portal := _portal(String(end.portal))
			if not portal.is_empty():
				out.append(UiKit.text_field("Portal name", String(portal.get("name", "")), func(_v: String) -> void: pass, 40, "Shown when you come through it",
					func(v: String) -> void: draft.set_portal(String(end.portal), "name", v.strip_edges().left(40))))
	var move := HBoxContainer.new()
	for step: Array in [["Back %d m" % MOVE_M, -MOVE_M], ["On %d m" % MOVE_M, MOVE_M]]:
		var b := UiKit.button(step[0], func() -> void:
			draft.move_ramp(selected, step[1])
			editor.say("Moved %+d m" % step[1]), "Move the whole ramp along the road")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		move.add_child(b)
	out.append(move)
	var pts := _points()
	out.append(UiKit.label("Points", 24))
	for i in pts.size():
		out.append(UiKit.button(("▶ " if i == point else "") + "Point %d · %d m up" % [i + 1, roundi(pts[i].y)], _select_point.bind(i), "Select it"))
	if point >= 0 and point < pts.size():
		var p := pts[point]
		var i := point
		out.append(UiKit.number("X", p.x, -20000.0, 20000.0, 1.0, "%.0f m", func(v: float) -> void: _set_point(i, Vector3(v, p.y, p.z))))
		out.append(UiKit.number("Z", p.z, -20000.0, 20000.0, 1.0, "%.0f m", func(v: float) -> void: _set_point(i, Vector3(p.x, p.y, v))))
		out.append(UiKit.number("Height", p.y, -20.0, 40.0, 0.5, "%.1f m", func(v: float) -> void: _set_point(i, Vector3(p.x, v, p.z)), "Over 0; more than 4.5 m clears a road"))
		out.append(UiKit.button("Insert point after", func() -> void:
			var q := pts[i + 1] if i + 1 < pts.size() else p + (p - pts[i - 1] if i > 0 else Vector3(20, 0, 0)) * 0.5
			draft.add_ramp_point(selected, i + 1, (p + q) / 2.0)
			_select_point(i + 1), "Halfway to the next one"))
		out.append(UiKit.button("Delete point", _delete_point, "Delete or X"))
	out.append(UiKit.button("Delete ramp", func() -> void:
		var was := _label(r)
		draft.delete_ramp(selected)
		_select("")
		editor.say(was + " deleted"), "And its portal"))
	out.append(UiKit.button("Deselect", func() -> void: _select(""), "Back to the list"))
	return out


func _set_name(v: String) -> void:
	_name_typed = ""
	var name := v.strip_edges().left(40)
	if selected and name != String(draft.ramp(selected).get("name", "")):
		draft.set_ramp(selected, "name", name)


func _set_point(i: int, p: Vector3) -> void:
	draft.drag_ramp_point(selected, i, p)
	draft.end_ramp_move("Move ramp point")


func _portal(id: String) -> Dictionary:
	for p: Dictionary in draft.layout.highway.get("portals", []):
		if p.id == id:
			return p
	return {}


static func _label(r: Dictionary) -> String:
	return String(r.name) if r.get("name", "") else String(r.id)


## "Exit · direction 1 · 1.2 km" and the like.
func _kind_text(r: Dictionary) -> String:
	var kind := { "exit": "Exit", "entry": "Entry", "link": "Crossover" }.get(String(r.kind), String(r.kind)) as String
	var end: Dictionary = r.from if r.from.has("at_m") else r.to
	var t := draft.track()
	var at := t.from_start(float(end.get("at_m", 0.0))) if t.length > 0.0 else 0.0
	return "%s · %s · %s" % [kind, _side(int(end.get("dir", 1))), "%d m" % roundi(at) if at < 1000.0 else "%.1f km" % (at / 1000.0)]


## Which way a carriageway goes round, in words.
func _side(dir: int) -> String:
	return "clockwise" if draft.track().highway.clockwise(dir) else "anticlockwise"


static func _text(t: String) -> Label:
	var l := UiKit.label(t, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
