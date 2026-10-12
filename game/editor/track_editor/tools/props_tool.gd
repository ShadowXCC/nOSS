extends EditorTool
## The Props tool (EDT-03): place props and move them, or scatter and erase them with a brush.
## Place: click to put the chosen prop down; click a prop to select it, drag to move it, and set
## its turn, scale and size in the panel. Scatter: drag to spread the chosen kind (kept off the
## road, spaced, at random turns and sizes). Erase: drag to clear scattered props.

const MODES := [["place", "Place"], ["scatter", "Scatter"], ["erase", "Erase"]]
const PICK_PX := 30.0
const LIVE_S := 0.2

var mode := "place"
var category := "trackside"
var prop := "cone"
var scatter_prop := "tree_pine"
var radius := 25.0
var density := 1.0
var scale_range := Vector2(0.8, 1.2)
var selected := -1
var _moving := false
var _stroking := false
var _stroke_before := []
var _cursor := { "hit": false, "position": Vector3.ZERO }
var _since := 0.0
var _live_since := 0.0
var _seed := 1


func title() -> String:
	return "Props"


func hint() -> String:
	match mode:
		"scatter":
			return "Drag to scatter · keys or controller: Enter turns the brush on"
		"erase":
			return "Drag to clear scattered props"
	return "Click to place · click a prop to select it, drag to move · [ ] step · Del removes"


func selection_state() -> Dictionary:
	return { "prop_selected": selected }


func pointer(e: Dictionary) -> void:
	_cursor = e.hit
	if mode != "place":
		_brush_pointer(e)
		return
	match String(e.kind):
		"press":
			var i := _item_at(e)
			if i >= 0:
				_select(i)
				_moving = true
				if e.crosshair:
					editor.say("Prop picked up")
			elif e.hit.hit:
				var item := { "prop": prop, "p": TrackDraft._vec(e.hit.position), "yaw_deg": 0.0, "scale": 1.0, "ground": true }
				var size := PropLibrary.size_of(prop)
				if size != Vector3.ZERO:
					item.size = [size.x, size.y, size.z]
				draft.add_prop(item)
				_select(draft.layout.props.items.size() - 1)
				view.grabbing = false
				editor.say("%s placed" % PropLibrary.TYPES[prop].name)
		"drag":
			if _moving and selected >= 0 and e.hit.hit:
				var item: Dictionary = (draft.layout.props.items[selected] as Dictionary).duplicate(true)
				item.p = TrackDraft._vec(e.hit.position)
				draft.set_prop_live(selected, item)
		"release":
			if _moving:
				_moving = false
				draft.end_prop_move()
				editor.refresh_panel()


func action(name: String) -> bool:
	match name:
		"delete":
			if selected >= 0:
				draft.delete_prop(selected)
				selected = -1
				editor.say("Prop deleted")
				refresh_gizmos()
			return true
		"prev", "next":
			var n: int = draft.layout.props.items.size()
			if n > 0:
				_select(posmod(selected + (1 if name == "next" else -1), n))
				var p: Array = draft.layout.props.items[selected].p
				view.camera.focus(Vector3(p[0], p[1], p[2]))
			return true
	return false


func tick(delta: float) -> void:
	if not _stroking:
		return
	if view.crosshair:
		_cursor = view.pick(view.center())
	_since += delta
	_live_since += delta
	if _since >= 1.0 / 15.0 and _cursor.hit:
		_since = 0.0
		_dab(Vector2(_cursor.position.x, _cursor.position.z))
	if _live_since >= LIVE_S:
		_live_since = 0.0
		draft.set_scatter_live(_brush_prop(), draft.scatter_of(_brush_prop()))
		view.preview._on_changed(&"scatter", { "live": true })
	_ring()


func deactivate() -> void:
	_end_stroke()
	super()


func refresh_gizmos() -> void:
	super()
	_ring()


func _brush_pointer(e: Dictionary) -> void:
	match String(e.kind):
		"press":
			if e.crosshair:
				view.grabbing = false
				if _stroking:
					_end_stroke()
				else:
					_begin_stroke()
				editor.say("Brush on" if _stroking else "Brush off")
			else:
				_begin_stroke()
		"release":
			if not e.crosshair:
				_end_stroke()
	_ring()


func _brush_prop() -> String:
	return scatter_prop


func _begin_stroke() -> void:
	_stroking = true
	_since = 1.0
	_stroke_before = draft.scatter_of(_brush_prop()).duplicate()


func _end_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	var after := draft.scatter_of(_brush_prop()).duplicate()
	if after != _stroke_before:
		draft.scatter_stroke(_brush_prop(), _stroke_before, after, "Scatter" if mode == "scatter" else "Erase")
		editor.say("%d %s" % [after.size() / 4, String(PropLibrary.TYPES[_brush_prop()].name).to_lower()])


func _dab(at: Vector2) -> void:
	var xf := draft.scatter_of(_brush_prop())
	if mode == "erase":
		var kept := []
		for k in range(0, xf.size() - 3, 4):
			if Vector2(xf[k], xf[k + 1]).distance_to(at) > radius:
				kept.append_array([xf[k], xf[k + 1], xf[k + 2], xf[k + 3]])
		draft.set_scatter_live(_brush_prop(), kept)
		return
	_seed += 1
	var builder := PropBuilder.new(draft.track(), draft.terrain)
	var added := builder.scatter_points(_brush_prop(), at, radius, density * 0.15, _seed, scale_range, PackedFloat32Array(xf))
	if added.is_empty():
		return
	var all := xf.duplicate()
	all.append_array(Array(added).map(func(v: float) -> float: return snappedf(v, 0.01)))
	draft.set_scatter_live(_brush_prop(), all)


func _ring() -> void:
	if mode != "place" and _cursor.hit:
		var h := draft.terrain.height_at if draft.terrain else Callable()
		view.gizmos.show_brush(_cursor.position, radius, h, view.gizmos.colors.get("p1", Color.WHITE) if _stroking else Color.WHITE)
	else:
		view.gizmos.show_brush(Vector3.ZERO, 0.0, Callable())


## The item under the cursor: by its collision, else the nearest on screen.
func _item_at(e: Dictionary) -> int:
	var collider: Object = e.hit.get("collider")
	if collider is Node:
		var n := collider as Node
		while n and n != view.preview:
			if n.has_meta(&"item"):
				return int(n.get_meta(&"item"))
			n = n.get_parent()
	var best := -1
	var best_d := PICK_PX
	var items: Array = draft.layout.props.items
	for i in items.size():
		var p: Array = items[i].p
		var s := view.screen_of(Vector3(p[0], p[1], p[2]))
		if s.x >= 0.0 and s.distance_to(e.screen) < best_d:
			best_d = s.distance_to(e.screen)
			best = i
	return best


func _select(i: int) -> void:
	selected = i
	editor.refresh_panel()
	if i >= 0:
		editor.say("%s %d of %d" % [PropLibrary.TYPES[draft.layout.props.items[i].prop].name, i + 1, draft.layout.props.items.size()])


func draft_changed(_what: StringName) -> void:
	if selected >= draft.layout.props.items.size():
		selected = -1
	if not _moving and not _stroking and editor.tool == self:
		editor.refresh_panel()


func panel() -> Array:
	var out := [UiKit.spinner("Mode", MODES, mode, func(v: String) -> void:
		_end_stroke()
		mode = v
		editor.refresh_panel()
		editor._hint.text = hint())]
	if mode == "place":
		var cats := PropLibrary.CATEGORIES.map(func(c: String) -> Array: return [c, c.capitalize()])
		out.append(UiKit.spinner("Kind", cats, category, func(v: String) -> void:
			category = v
			prop = String(PropLibrary.list(v)[0][0])
			editor.refresh_panel()))
		out.append(UiKit.spinner("Prop", PropLibrary.list(category), prop, func(v: String) -> void: prop = v))
		out.append(UiKit.button("Place at cursor", func() -> void:
			var hit := view.pick(view.cursor())
			if hit.hit:
				pointer({ "kind": "press", "screen": view.cursor(), "hit": hit, "shift": false, "alt": false, "crosshair": true }), "The chosen prop where the cursor is"))
		out.append_array(_item_rows())
	else:
		out.append(UiKit.spinner("Prop", PropLibrary.list("", true), scatter_prop, func(v: String) -> void: scatter_prop = v))
		out.append(UiKit.number("Size", radius, 5.0, 200.0, 1.0, "%.0f m", func(v: float) -> void: radius = v, "Brush radius"))
		if mode == "scatter":
			out.append(UiKit.number("Density", density, 0.1, 5.0, 0.1, "%.1f", func(v: float) -> void: density = v, "How close they stand"))
			out.append(UiKit.number("Smallest", scale_range.x, 0.3, 3.0, 0.1, "%.1f×", func(v: float) -> void: scale_range.x = minf(v, scale_range.y)))
			out.append(UiKit.number("Largest", scale_range.y, 0.3, 3.0, 0.1, "%.1f×", func(v: float) -> void: scale_range.y = maxf(v, scale_range.x)))
		out.append(UiKit.button("Brush off" if _stroking else "Brush on", func() -> void:
			if _stroking:
				_end_stroke()
			else:
				_begin_stroke()
			editor.refresh_panel(), "Keys and controller: brush as the view moves"))
		out.append(UiKit.label("%d placed" % (draft.scatter_of(scatter_prop).size() / 4), 22))
	return out


func _item_rows() -> Array:
	var items: Array = draft.layout.props.items
	if selected < 0 or selected >= items.size():
		return [UiKit.label("%d props. Click one to select it." % items.size(), 22)]
	var i := selected
	var item: Dictionary = items[i].duplicate(true)
	var t: Dictionary = PropLibrary.TYPES.get(item.prop, {})
	var change := func(key: String, v: Variant) -> void:
		var changed: Dictionary = draft.layout.props.items[i].duplicate(true)
		changed[key] = v
		draft.set_prop(i, changed, "Change prop")
	var out := [UiKit.label("%s %d of %d" % [t.get("name", item.prop), i + 1, items.size()], 26)]
	var p: Array = item.p
	out.append(UiKit.number("X", float(p[0]), -20000.0, 20000.0, 0.5, "%.1f m", func(v: float) -> void: change.call("p", [v, p[1], p[2]])))
	out.append(UiKit.number("Z", float(p[2]), -20000.0, 20000.0, 0.5, "%.1f m", func(v: float) -> void: change.call("p", [p[0], p[1], v])))
	out.append(UiKit.number("Turn", float(item.get("yaw_deg", 0.0)), -180.0, 180.0, 5.0, "%.0f°", change.bind("yaw_deg")))
	out.append(UiKit.number("Scale", float(item.get("scale", 1.0)), 0.25, 5.0, 0.05, "%.2f×", change.bind("scale")))
	if t.has("size"):
		var size: Array = item.get("size", t.size)
		out.append(UiKit.number("Size", float(size[2]), 4.0, 400.0, 1.0, "%.0f m", func(v: float) -> void: change.call("size", [size[0], size[1], v]),
			"A grandstand's or building's length, a skidpad's circle"))
	out.append(UiKit.button("Delete prop", func() -> void: action("delete"), "Delete or X"))
	out.append(UiKit.button("Deselect", func() -> void: _select(-1)))
	return out
