extends EditorTool
## The Stunts tool (EDT-04, D136-D138; road circuits and arenas): put kart pieces where the
## cursor is (boost pad, item box row, jump, wall-ride, loop on a road; boost pad and jump
## anywhere in an arena), pick one and drag it along the road (or about an arena), set its size,
## or delete it; item boxes automatic, placed or none. In an arena, its spawns and box clusters.
## Keys and controller: the crosshair picks a piece, then grabs and drops it; [ ] (LB/RB) step
## through the pieces; Delete (X) removes the selected one.

## A click this close to a piece picks it.
const PICK_M := 8.0
const MOVE_M := 10.0
const KIND_NAMES := { "boost_pad": "Boost pad", "item_row": "Item boxes", "jump": "Jump", "wall_ride": "Wall-ride", "loop": "Loop" }

var selected := ""
var kind := "boost_pad"
var _dragging := false


func title() -> String:
	return "Stunts"


func available() -> bool:
	return not draft.is_highway() and draft.scene == null


func hint() -> String:
	if selected:
		return "Drag it · [ ] other pieces · Del deletes it · F5 drives"
	return "Click a piece to pick it · Add puts a new one at the cursor · [ ] step"


func activate() -> void:
	selected = String(draft.view.get("stunt", selected))
	if draft.stunt(selected) == null:
		selected = ""


func selection_state() -> Dictionary:
	return { "stunt": selected }


func _kinds() -> Array:
	var allowed: Array = KartLayout.ARENA_KINDS if draft.is_arena() else KartLayout.KINDS
	return allowed.map(func(k: String) -> Array: return [k, KIND_NAMES[k]])


# --- the view -----------------------------------------------------------------------------

func pointer(e: Dictionary) -> void:
	match String(e.kind):
		"press":
			var id := _piece_near(e.hit.position) if e.hit.hit else ""
			if id and id == selected:
				_dragging = true
				if e.crosshair:
					editor.say("Picked up")
				return
			view.grabbing = false
			if id:
				_select(id)
			elif selected:
				_select("")
			else:
				editor.say("No piece here")
		"drag":
			if not _dragging or not e.hit.hit:
				return
			_move_to(e.hit.position)
		"release":
			if _dragging:
				draft.end_stunt_move()
				_dragging = false
				if e.crosshair:
					editor.say("Put down")
				editor.refresh_panel()


func action(name: String) -> bool:
	match name:
		"delete":
			if selected:
				_delete()
			else:
				editor.say("Pick a piece first")
			return true
		"prev", "next":
			var ids := _ids()
			if ids.is_empty():
				editor.say("No pieces")
				return true
			var at := ids.find(selected)
			_select(ids[posmod(at + (1 if name == "next" else -1), ids.size()) if at >= 0 else 0], true)
			return true
	return false


func draft_changed(_what: StringName) -> void:
	if selected and draft.stunt(selected) == null:
		selected = ""
	if not _dragging and editor.tool == self and not typing():
		editor.refresh_panel()


func refresh_gizmos() -> void:
	view.gizmos.show_track(draft.track(), [])
	var points := PackedVector3Array()
	var at := -1
	for id: String in _ids():
		if id == selected:
			at = points.size()
		points.append(_where(id))
	if draft.is_arena():
		for s: Dictionary in draft.layout.get("arena", {}).get("spawns", []):
			points.append(Vector3(s.p[0], s.p[1], s.p[2]))
		for b: Dictionary in draft.layout.get("arena", {}).get("boxes", []):
			points.append(Vector3(b.p[0], b.p[1], b.p[2]) + Vector3.UP)
	view.gizmos.show_points(points, at, -1)


func _ids() -> Array:
	return (draft.kart().get("stunts", []) as Array).map(func(p: Dictionary) -> String: return p.id)


## Where piece `id` is, world.
func _where(id: String) -> Vector3:
	var p: Dictionary = draft.stunt(id)
	if p.has("p"):
		return Vector3(p.p[0], p.p[1], p.p[2])
	var t := draft.track()
	if t.samples.size() < 3:
		return Vector3.ZERO
	return t.transform_at(float(p.at_m), float(p.get("lateral_m", 0.0))).origin


func _piece_near(at: Vector3) -> String:
	var best := ""
	var best_d := PICK_M
	for id: String in _ids():
		var d := Vector2(at.x, at.z).distance_to(Vector2(_where(id).x, _where(id).z))
		if d < best_d:
			best_d = d
			best = id
	return best


func _move_to(at: Vector3) -> void:
	if draft.is_arena():
		draft.drag_stunt(selected, Vector3(at.x, 0.0, at.z))
		return
	var proj := draft.track().project(at)
	draft.drag_stunt(selected, float(proj.distance), float(proj.lateral))


func _select(id: String, look := false) -> void:
	selected = id
	editor.refresh_panel()
	refresh_gizmos()
	editor._hint.text = hint()
	if id.is_empty():
		editor.say("No piece selected")
		return
	editor.say(_label(draft.stunt(id)))
	if look:
		view.camera.focus(_where(id), 80.0)


func _delete() -> void:
	var was := _label(draft.stunt(selected))
	draft.delete_stunt(selected)
	_select("")
	editor.say(was + " deleted")


func _add_at(at: Vector3) -> void:
	var t := draft.track()
	if t.samples.size() < 3:
		editor.say("Add the road first")
		return
	var id := ""
	if draft.is_arena():
		id = draft.add_stunt(kind, Vector3(at.x, 0.0, at.z))
	else:
		var proj := t.project(at)
		var params := {}
		if kind in ["boost_pad", "jump"]:
			params.lateral_m = snappedf(float(proj.lateral), 0.5) if kind == "boost_pad" else 0.0
		if kind == "wall_ride":
			params.side = "left" if float(proj.lateral) > 0.0 else "right"
		id = draft.add_stunt(kind, float(proj.distance), params)
	if id.is_empty():
		editor.say("Can't put that here")
		return
	_select(id)


func _label(p: Dictionary) -> String:
	if p.has("at_m"):
		var t := draft.track()
		var at := t.from_start(float(p.at_m)) if t.length > 0.0 else 0.0
		return "%s · %d m" % [KIND_NAMES.get(p.kind, p.kind), roundi(at)]
	return "%s · %s" % [KIND_NAMES.get(p.kind, p.kind), String(p.id)]


# --- the panel ----------------------------------------------------------------------------

func panel() -> Array:
	var out := []
	out.append(UiKit.spinner("Add", _kinds(), kind if kind in (_kinds().map(func(k: Array) -> String: return k[0])) else "boost_pad",
		func(v: String) -> void: kind = v, "What Add puts at the cursor"))
	out.append(UiKit.button("Add at cursor", func() -> void:
		var hit := view.pick(view.cursor())
		if hit.hit:
			_add_at(hit.position), "On the road where the cursor is" if not draft.is_arena() else "Where the cursor is"))
	if not draft.is_arena():
		out.append(UiKit.spinner("Item boxes", [["auto", "Automatic"], ["placed", "Placed rows only"], ["none", "None"]], String(draft.kart().get("boxes", "auto")),
			func(v: String) -> void: draft.set_boxes(v), "Automatic: rows every third of a lap unless you place rows"))
	var ids := _ids()
	if selected.is_empty():
		if ids.is_empty():
			out.append(_text("No pieces yet. Put the cursor on the road and Add."))
		else:
			out.append(UiKit.label("%d pieces" % ids.size(), 26))
			for id: String in ids:
				out.append(UiKit.button(_label(draft.stunt(id)), _select.bind(id, true), "Pick it and look at it"))
		if draft.is_arena():
			out.append_array(_arena_panel())
		return out
	var p: Dictionary = draft.stunt(selected)
	var row := HBoxContainer.new()
	for b: Button in [UiKit.button("Previous", func() -> void: action("prev"), "[ or LB"), UiKit.button("Next", func() -> void: action("next"), "] or RB")]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	out.append(row)
	out.append(UiKit.label(_label(p), 26))
	var full := KartLayout.filled(p)
	var set := func(key: String) -> Callable: return func(v: Variant) -> void: draft.set_stunt(selected, key, v)
	match String(p.kind):
		"boost_pad":
			out.append(UiKit.number("Across", float(full.lateral_m), -20.0, 20.0, 0.5, "%.1f m", set.call("lateral_m"), "From the road's middle, + to the left"))
			out.append(UiKit.number("Length", float(full.length_m), 2.0, 20.0, 0.5, "%.1f m", set.call("length_m")))
			out.append(UiKit.number("Width", float(full.width_m), 1.0, 12.0, 0.5, "%.1f m", set.call("width_m")))
		"item_row":
			out.append(UiKit.spinner("Boxes", [[0, "Auto"], [3, "3"], [4, "4"], [5, "5"]], int(full.count), set.call("count"), "Auto: as many as the road's width takes"))
		"jump":
			out.append(UiKit.number("Height", float(full.height_m), 0.4, 4.0, 0.1, "%.1f m", set.call("height_m")))
			out.append(UiKit.number("Length", float(full.length_m), 3.0, 30.0, 0.5, "%.1f m", set.call("length_m")))
			out.append(UiKit.number("Width", float(full.width_m), 0.0, 30.0, 0.5, "%.1f m", set.call("width_m"), "0: the road's width"))
		"wall_ride":
			out.append(UiKit.spinner("Side", [["left", "Left"], ["right", "Right"]], String(full.side), set.call("side")))
			out.append(UiKit.number("Length", float(full.length_m), 30.0, 400.0, 5.0, "%.0f m", set.call("length_m")))
			out.append(UiKit.number("Height", float(full.height_m), 3.0, 12.0, 0.5, "%.1f m", set.call("height_m")))
		"loop":
			out.append(UiKit.number("Radius", float(full.radius_m), 7.0, 14.0, 0.5, "%.1f m", set.call("radius_m")))
			out.append(UiKit.number("Width", float(full.width_m), 4.0, 8.0, 0.5, "%.1f m", set.call("width_m"), "Each lane: the road must be twice this"))
	if p.has("p"):
		out.append(UiKit.number("Turn", float(p.get("yaw_deg", 0.0)), -180.0, 180.0, 15.0, "%.0f°", set.call("yaw_deg")))
	else:
		var move := HBoxContainer.new()
		for step: Array in [["Back %d m" % MOVE_M, -MOVE_M], ["On %d m" % MOVE_M, MOVE_M]]:
			var b := UiKit.button(step[0], func() -> void:
				draft.drag_stunt(selected, float(draft.stunt(selected).at_m) + step[1])
				draft.end_stunt_move()
				editor.say("Moved %+d m" % step[1]), "Along the road")
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			move.add_child(b)
		out.append(move)
	out.append(UiKit.button("Delete piece", _delete, "Delete or X"))
	out.append(UiKit.button("Deselect", func() -> void: _select(""), "Back to the list"))
	return out


## An arena's spawns and item box clusters (automatic while there are none).
func _arena_panel() -> Array:
	var out := []
	var a: Dictionary = draft.layout.get("arena", {})
	var spawns: Array = a.get("spawns", [])
	var boxes: Array = a.get("boxes", [])
	out.append(UiKit.label("Spawns: %s" % ("%d" % spawns.size() if not spawns.is_empty() else "automatic (12)"), 24))
	out.append(UiKit.button("Add spawn at cursor", func() -> void:
		var hit := view.pick(view.cursor())
		if hit.hit:
			var t := draft.track()
			var middle := t.arena.centre if t.arena else Vector2.ZERO
			var to := Vector2(middle.x - hit.position.x, middle.y - hit.position.z)
			draft.add_spawn(hit.position, rad_to_deg(atan2(to.x, to.y)))
			editor.say("Spawn %d added, facing the middle" % (spawns.size() + 1)), "Facing the arena's middle"))
	if not spawns.is_empty():
		out.append(UiKit.button("Delete the last spawn", func() -> void: draft.delete_spawn(spawns.size() - 1)))
	out.append(UiKit.label("Item boxes: %s" % ("%d clusters" % boxes.size() if not boxes.is_empty() else "automatic (5 clusters)"), 24))
	out.append(UiKit.button("Add item boxes at cursor", func() -> void:
		var hit := view.pick(view.cursor())
		if hit.hit:
			draft.add_box_cluster(hit.position)
			editor.say("Item boxes added"), "A cluster of four"))
	if not boxes.is_empty():
		out.append(UiKit.button("Delete the last item boxes", func() -> void: draft.delete_box_cluster(boxes.size() - 1)))
	return out


static func _text(t: String) -> Label:
	var l := UiKit.label(t, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
