extends EditorTool
## The Road tool (EDT-01): place and drag the road's control points, set each point's widths,
## banking and height, and each segment's surface, lines, curbs, barriers and run-off.
## Mouse: click the ground to add a point (on the road: in it), drag a point, Alt+drag for its
## height. Keys and controller: the crosshair grabs and drops; [ and ] (LB/RB) step through the
## points; Delete (X) removes one. Every view action is also a button. On a fitted scene (Track
## Fitting) the points are the road's centreline: they go only on surfaces tagged to drive on,
## at the scene's height, and nothing is built from them. On a highway (EDT-10) the points are
## the median's line, and the widths come from the lanes, median and shoulders set here.

const BARRIERS := [["auto", "Auto"], ["none", "None"], ["tyres", "Tyres"], ["armco", "Armco"], ["concrete", "Concrete"], ["fence", "Fence"], ["sound_wall", "Sound wall"],
	["safer", "SAFER wall"]]
const HIGHWAY_BARRIERS := [["concrete", "Concrete"], ["armco", "Armco"], ["sound_wall", "Sound wall"], ["fence", "Fence"], ["none", "None"]]

## A point is under the cursor within this many pixels.
const PICK_PX := 22.0
## Clicking this close to the road inserts a point into it.
const INSERT_M := 6.0

var selected := -1
var hover := -1
var _dragging := -1
var _height_drag := false
var _drag_from := Vector2.ZERO
var _drag_height := 0.0


func title() -> String:
	return "Road"


func hint() -> String:
	if draft.scene:
		return "Click along the middle of the road · drag to move · [ ] step · Del removes · F5 drives"
	return "Click to add a point · drag to move · Alt+drag: height · [ ] step · Del removes · F5 drives"


func activate() -> void:
	selected = clampi(int(draft.view.get("selected", selected)), -1, draft.points().size() - 1)


func selection_state() -> Dictionary:
	return { "selected": selected }


# --- the view -----------------------------------------------------------------------------


func pointer(e: Dictionary) -> void:
	match String(e.kind):
		"hover":
			var h := _point_at(e.screen)
			if h != hover:
				hover = h
				refresh_gizmos()
		"press":
			var i := _point_at(e.screen) if not e.crosshair else _point_near(e.hit.position)
			if i >= 0:
				_select(i)
				_dragging = i
				_height_drag = bool(e.alt)
				_drag_from = e.screen
				_drag_height = _height_of(i)
				if e.crosshair:
					editor.say("Point %d picked up" % (i + 1))
			elif e.hit.hit:
				_add_at(e.hit.position)
				if e.crosshair:
					view.grabbing = false # a new point is placed, not carried
		"drag":
			if _dragging < 0:
				return
			if _height_drag:
				var up := (_drag_from.y - float(e.screen.y)) * view.camera.distance / maxf(view.size.y, 1.0)
				var p := _point_pos(_dragging)
				p.y = snappedf(_drag_height + up, 0.1)
				if TrackFormat.attr(draft.layout.road, _dragging, "height") != "set":
					draft.set_attr(PackedInt32Array([_dragging]), "height", "set")
				draft.drag_point(_dragging, p)
			elif e.hit.hit:
				var p := _point_pos(_dragging)
				var to := Vector3(e.hit.position.x, p.y, e.hit.position.z)
				if draft.scene:
					var on: Variant = _on_scene_road(e.hit.position)
					if on == null:
						return # not onto what isn't road
					to = on
				draft.drag_point(_dragging, to)
		"release":
			if _dragging >= 0:
				draft.end_move("Point height" if _height_drag else "Move point")
				if e.crosshair:
					editor.say("Point %d put down" % (_dragging + 1))
				_dragging = -1
				_height_drag = false
				editor.refresh_panel()


func action(name: String) -> bool:
	match name:
		"delete":
			_delete()
			return true
		"prev", "next":
			if draft.points().is_empty():
				return true
			_select(posmod(selected + (1 if name == "next" else -1), draft.points().size()))
			view.camera.focus(_point_pos(selected))
			return true
	return false


func draft_changed(_what: StringName) -> void:
	if selected >= draft.points().size():
		selected = draft.points().size() - 1
	if _dragging < 0 and editor.tool == self:
		editor.refresh_panel()


func refresh_gizmos() -> void:
	view.gizmos.show_track(draft.track(), draft.points(), selected, hover)


func _point_at(screen: Vector2) -> int:
	var best := -1
	var best_d := PICK_PX
	for i in draft.points().size():
		var s := view.screen_of(_point_pos(i))
		if s.x < 0.0:
			continue
		var d := s.distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	return best


## The point nearest a world spot, within reach of the crosshair at this zoom.
func _point_near(at: Vector3) -> int:
	var best := -1
	var reach := maxf(view.camera.distance * 0.04, 3.0)
	for i in draft.points().size():
		var d := Vector2(at.x, at.z).distance_to(Vector2(_point_pos(i).x, _point_pos(i).z))
		if d < reach:
			reach = d
			best = i
	return best


func _point_pos(i: int) -> Vector3:
	var p: Array = draft.points()[i].p
	return Vector3(p[0], p[1], p[2])


## The height shown for point `i`: its own if set, else where the road lies.
func _height_of(i: int) -> float:
	if TrackFormat.attr(draft.layout.road, i, "height") == "set":
		return _point_pos(i).y
	var t := draft.track()
	return t.samples[t.seg_first[i]].y if i < t.seg_first.size() else _point_pos(i).y


func _select(i: int) -> void:
	selected = i
	editor.refresh_panel()
	refresh_gizmos()
	if i >= 0:
		var t := draft.track()
		var at := " · %d m" % roundi(t.distances[t.seg_first[i]]) if i < t.seg_first.size() else ""
		editor.say("Point %d of %d%s" % [i + 1, draft.points().size(), at])


## A new point at `at`: into the road if it's on it, else after the selected point (or last).
## Where a click at `at` lands on a fitted scene's road, or null if it isn't a surface to drive on.
func _on_scene_road(at: Vector3) -> Variant:
	var hit := draft.scene.ray_down(at.x, at.z, at.y + 3.0)
	if not hit.hit or String(hit.tag) not in SceneTrack.DRIVABLE:
		return null
	return hit.position


func _add_at(at: Vector3) -> void:
	if draft.scene:
		var on: Variant = _on_scene_road(at)
		if on == null:
			editor.say("Not a road surface")
			return
		at = on
	var t := draft.track()
	var index := draft.points().size() if selected < 0 else selected + 1
	if t.samples.size() > 2:
		var proj := t.project(at)
		var i: int = proj.index
		var on: Vector3 = proj.point
		var reach := maxf(t.half_l[i], t.half_r[i]) + INSERT_M
		# On the road itself (not just in line with it, past its end): into it there. Near the
		# selected point, or on its own way on (the stretch back to the first point while the road
		# is being laid), the click carries the road on from it instead.
		var near_selected := false
		if selected >= 0 and selected < t.seg_first.size():
			var gap := absf(float(proj.distance) - t.distances[t.seg_first[selected]])
			near_selected = minf(gap, t.length - gap) < reach or t.sample_seg[i] == selected
		if Vector2(at.x - on.x, at.z - on.z).length() < reach and not near_selected:
			index = t.sample_seg[i] + 1
			at = proj.point
	var attrs := {}
	if draft.points().size() > 0:
		# A new point follows its neighbour's height mode.
		var near := clampi(index - 1, 0, draft.points().size() - 1)
		if TrackFormat.attr(draft.layout.road, near, "height") == "set" and draft.scene == null:
			attrs.height = "set"
			at.y = _height_of(near)
	draft.add_point(index, at, attrs)
	_select(index)


func _delete() -> void:
	if selected < 0 or selected >= draft.points().size():
		editor.say("No point selected")
		return
	var was := selected
	draft.delete_point(selected)
	selected = mini(was, draft.points().size() - 1)
	editor.say("Point %d deleted" % (was + 1))
	refresh_gizmos()


# --- the panel ----------------------------------------------------------------------------


func panel() -> Array:
	var out := []
	var n := draft.points().size()
	if n == 0:
		out.append(_text("Click the ground (or use the crosshair and Enter) to add the road's first point."))
	out.append(UiKit.button("Add point at cursor", func() -> void:
		var hit := view.pick(view.cursor())
		if hit.hit:
			_add_at(hit.position), "A point where the cursor is"))
	if n == 0:
		return out
	var i := clampi(selected, -1, n - 1)
	var row := HBoxContainer.new()
	var prev := UiKit.button("Previous", func() -> void: action("prev"), "[ or LB")
	var next := UiKit.button("Next", func() -> void: action("next"), "] or RB")
	for b: Button in [prev, next]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	out.append(row)
	if i < 0:
		out.append(_text("%d points. Select one to change it, or set the whole road below." % n))
		out.append_array(_defaults(draft.scene != null))
		out.append(UiKit.button("Flip direction", func() -> void:
			draft.flip_direction()
			editor.say("Direction flipped"), "Drive it the other way round"))
		return out
	var t := draft.track()
	var at := t.distances[t.seg_first[i]] if i < t.seg_first.size() else 0.0
	out.append(UiKit.label("Point %d of %d · %d m" % [i + 1, n, roundi(at)], 26))
	var road: Dictionary = draft.layout.road
	var p := _point_pos(i)
	var idx := PackedInt32Array([i])
	out.append(UiKit.number("X", p.x, -20000.0, 20000.0, 1.0, "%.0f m", func(v: float) -> void: draft.move_point(i, Vector3(v, p.y, p.z))))
	out.append(UiKit.number("Z", p.z, -20000.0, 20000.0, 1.0, "%.0f m", func(v: float) -> void: draft.move_point(i, Vector3(p.x, p.y, v))))
	if draft.scene:
		# A fitted scene: the scene is the road; the point only sets the line and its widths.
		out.append_array(_attr_rows(idx, i, true, true))
		out.append(UiKit.button("Delete point", _delete, "Delete or X"))
		out.append(UiKit.button("Deselect", func() -> void: _select(-1), "Set the whole road"))
		return out
	var height_mode := String(TrackFormat.attr(road, i, "height"))
	out.append(UiKit.spinner("Height", [["ground", "On the ground"], ["set", "Set"]], height_mode, func(v: String) -> void:
		if v == "set":
			var y := _height_of(i)
			draft.set_attr(idx, "height", "set")
			draft.move_point(i, Vector3(p.x, y, p.z))
		else:
			draft.set_attr(idx, "height", null if road.defaults.get("height", "ground") == "ground" else "ground")))
	if height_mode == "set":
		out.append(UiKit.number("Height above 0", p.y, -500.0, 500.0, 0.5, "%.1f m", func(v: float) -> void: draft.move_point(i, Vector3(p.x, v, p.z)),
			"Over 3 m above the ground it stands on supports"))
	if draft.is_highway():
		out.append(UiKit.number("Banking", float(TrackFormat.attr(road, i, "bank_deg")), -10.0, 10.0, 0.5, "%.1f°", func(v: float) -> void: draft.set_attr(idx, "bank_deg", v),
			"Positive raises the left edge"))
		out.append(UiKit.label("Segment to the next point", 24))
		out.append_array(_highway_segment_rows(idx, i))
	else:
		out.append_array(_attr_rows(idx, i, true))
		out.append(UiKit.label("Segment to the next point", 24))
		out.append_array(_attr_rows(idx, i, false))
	out.append(UiKit.button("Use these everywhere", func() -> void: _use_everywhere(i), "Every point takes this point's settings"))
	out.append(UiKit.button("Insert point after", func() -> void:
		var q := _point_pos((i + 1) % n)
		_add_at((p + q) / 2.0), "Halfway to the next point"))
	out.append(UiKit.button("Delete point", _delete, "Delete or X"))
	out.append(UiKit.button("Deselect", func() -> void: _select(-1), "Set the whole road"))
	out.append(UiKit.button("Flip direction", func() -> void:
		draft.flip_direction()
		editor.say("Direction flipped"), "Drive it the other way round"))
	return out


## The rows for one point (`point`: its widths and banking; `widths_only`: just the widths) or
## its segment (surface, lines, curbs, barriers, run-off).
func _attr_rows(idx: PackedInt32Array, i: int, point: bool, widths_only := false) -> Array:
	var road: Dictionary = draft.layout.road
	# Bound with its key: a control calls it with the value first, then the key.
	var set_attr := func(v: Variant, key: String) -> void: draft.set_attr(idx, key, v)
	var out := []
	if point:
		out.append(UiKit.number("Width left", float(TrackFormat.attr(road, i, "width_l")), 2.0, 30.0, 0.5, "%.1f m", set_attr.bind("width_l"), "Centreline to the left edge"))
		out.append(UiKit.number("Width right", float(TrackFormat.attr(road, i, "width_r")), 2.0, 30.0, 0.5, "%.1f m", set_attr.bind("width_r"), "Centreline to the right edge"))
		if widths_only:
			return out
		out.append(UiKit.number("Banking", float(TrackFormat.attr(road, i, "bank_deg")), -25.0, 25.0, 0.5, "%.1f°", set_attr.bind("bank_deg"), "Positive raises the left edge"))
		# An apron (D202): paved past the edge at its own slope, like an oval's flat inside.
		for side: Array in [["l", "left"], ["r", "right"]]:
			out.append(UiKit.number("Apron %s" % side[1], float(TrackFormat.attr(road, i, "apron_%s_m" % side[0])), 0.0, 30.0, 0.5, "%.1f m",
				set_attr.bind("apron_%s_m" % side[0]), "Paved, past the edge"))
			out.append(UiKit.number("Apron %s slope" % side[1], float(TrackFormat.attr(road, i, "apron_%s_deg" % side[0])), -25.0, 25.0, 0.5, "%.1f°",
				set_attr.bind("apron_%s_deg" % side[0]), "Positive raises the left side"))
		return out
	out.append(UiKit.spinner("Surface", _surfaces(["asphalt", "concrete", "dirt", "gravel", "sand", "snow", "ice", "grass"]), String(TrackFormat.attr(road, i, "surface")), set_attr.bind("surface")))
	var lanes := []
	for k in range(1, 5):
		lanes.append([k, str(k)])
	out.append(UiKit.spinner("Lanes", lanes, int(TrackFormat.attr(road, i, "lanes")), set_attr.bind("lanes")))
	out.append(UiKit.spinner("Lines", [["edges", "Edges"], ["lanes", "Lanes"], ["all", "Edges and lanes"], ["none", "None"]], String(TrackFormat.attr(road, i, "lines")), set_attr.bind("lines")))
	for side: Array in [["l", "left"], ["r", "right"]]:
		var s: String = side[0]
		var word: String = side[1]
		out.append(UiKit.spinner("Curb %s" % word, [["auto", "Auto"], ["on", "On"], ["off", "Off"]], String(TrackFormat.attr(road, i, "curb_" + s)), set_attr.bind("curb_" + s)))
		out.append(UiKit.spinner("Barrier %s" % word, BARRIERS, String(TrackFormat.attr(road, i, "barrier_" + s)), set_attr.bind("barrier_" + s)))
		out.append(UiKit.spinner("Run-off %s" % word, _surfaces(["grass", "gravel", "asphalt", "concrete", "sand", "dirt"]), String(TrackFormat.attr(road, i, "runoff_" + s)), set_attr.bind("runoff_" + s)))
		out.append(UiKit.number("Run-off %s width" % word, float(TrackFormat.attr(road, i, "runoff_%s_m" % s)), 0.0, 60.0, 1.0, "%.0f m", set_attr.bind("runoff_%s_m" % s)))
	return out


## A highway segment's own settings: its surface and the barrier on each outer edge.
func _highway_segment_rows(idx: PackedInt32Array, i: int) -> Array:
	var road: Dictionary = draft.layout.road
	var set_attr := func(v: Variant, key: String) -> void: draft.set_attr(idx, key, v)
	var out := []
	out.append(UiKit.spinner("Surface", _surfaces(["asphalt", "concrete"]), String(TrackFormat.attr(road, i, "surface")), set_attr.bind("surface")))
	# Left of the line is direction -1's outer edge, right is direction 1's.
	for side: Array in [["l", "Barrier left"], ["r", "Barrier right"]]:
		out.append(UiKit.spinner(side[1], HIGHWAY_BARRIERS, String(TrackFormat.attr(road, i, "barrier_" + side[0])), set_attr.bind("barrier_" + side[0]),
			"The outer edge's barrier"))
	return out


## A highway's lanes, median, shoulders and speed limit (the road's widths follow), and its outer
## barriers.
func _highway_defaults() -> Array:
	var h := draft.highway()
	var set_hw := func(v: Variant, key: String) -> void: draft.set_highway(key, v)
	var out := [UiKit.label("Highway", 26)]
	var lanes := []
	for k in range(2, 5):
		lanes.append([k, str(k)])
	out.append(UiKit.spinner("Lanes each way", lanes, int(h.lanes), set_hw.bind("lanes")))
	out.append(UiKit.number("Lane width", float(h.lane_m), 3.0, 4.0, 0.1, "%.1f m", set_hw.bind("lane_m")))
	out.append(UiKit.number("Median width", float(h.median_m), 0.6, 6.0, 0.2, "%.1f m", set_hw.bind("median_m"), "Between the carriageways"))
	out.append(UiKit.spinner("Median barrier", [["concrete", "Concrete"], ["armco", "Armco"], ["fence", "Fence"]], String(h.median_barrier), set_hw.bind("median_barrier")))
	out.append(UiKit.number("Inner shoulder", float(h.shoulder_in_m), 0.0, 2.5, 0.1, "%.1f m", set_hw.bind("shoulder_in_m"), "Beside the median"))
	out.append(UiKit.number("Outer shoulder", float(h.shoulder_out_m), 0.0, 4.0, 0.1, "%.1f m", set_hw.bind("shoulder_out_m"), "Hard shoulder on the outside"))
	out.append(UiKit.number("Speed limit", float(h.speed_kmh), 60.0, 160.0, 10.0, "%.0f km/h", set_hw.bind("speed_kmh"), "Traffic's speed"))
	var d: Dictionary = draft.layout.road.defaults
	out.append(UiKit.spinner("Surface", _surfaces(["asphalt", "concrete"]), String(d.get("surface", "asphalt")), func(v: String) -> void: draft.set_default("surface", v)))
	out.append(UiKit.spinner("Outer barriers", HIGHWAY_BARRIERS, String(d.get("barrier_l", "concrete")), func(v: String) -> void:
		draft.set_default("barrier_l", v)
		draft.set_default("barrier_r", v)))
	return out


## The whole road's settings (no point selected); `widths_only`: just the widths (a fitted scene).
func _defaults(widths_only := false) -> Array:
	var out := []
	if not widths_only:
		out.append(UiKit.spinner("Track type", [["circuit", "Circuit"], ["highway", "Highway"], ["arena", "Arena"]], String(draft.layout.get("type", "circuit")),
			func(v: String) -> void:
				draft.set_type(v)
				editor.say("Now an arena" if v == "arena" else "Now a " + v),
			"A highway has a carriageway each way and ramps; an arena is the floor inside the points, for kart battles"))
	if draft.is_highway():
		out.append_array(_highway_defaults())
		return out
	if draft.is_arena():
		var a: Dictionary = draft.layout.get("arena", {})
		out.append(UiKit.spinner("Floor", _surfaces(["asphalt", "concrete", "dirt", "sand", "snow", "ice"]), String(a.get("floor", ArenaLayout.DEFAULTS.floor)),
			func(v: String) -> void: draft.set_arena("floor", v)))
		out.append(UiKit.spinner("Wall", [["tyres", "Tyres"], ["armco", "Armco"], ["concrete", "Concrete"]], String(a.get("wall", ArenaLayout.DEFAULTS.wall)),
			func(v: String) -> void: draft.set_arena("wall", v)))
		out.append(UiKit.number("Wall height", float(a.get("wall_m", ArenaLayout.DEFAULTS.wall_m)), 0.5, 4.0, 0.1, "%.1f m",
			func(v: float) -> void: draft.set_arena("wall_m", v)))
		out.append(_text("The points are the arena's outline; spawns and item boxes are in Stunts."))
		return out
	var d: Dictionary = draft.layout.road.defaults
	var set_default := func(v: Variant, key: String) -> void: draft.set_default(key, v)
	out.append(UiKit.number("Width left", float(d.get("width_l", 6.0)), 2.0, 30.0, 0.5, "%.1f m", set_default.bind("width_l")))
	out.append(UiKit.number("Width right", float(d.get("width_r", 6.0)), 2.0, 30.0, 0.5, "%.1f m", set_default.bind("width_r")))
	if widths_only:
		return out
	out.append(UiKit.spinner("Surface", _surfaces(["asphalt", "concrete", "dirt", "gravel", "sand", "snow", "ice", "grass"]), String(d.get("surface", "asphalt")), set_default.bind("surface")))
	out.append(UiKit.spinner("Run-off", _surfaces(["grass", "gravel", "asphalt", "concrete", "sand", "dirt"]), String(d.get("runoff_l", "grass")), func(v: String) -> void:
		draft.set_default("runoff_l", v)
		draft.set_default("runoff_r", v)))
	out.append(UiKit.spinner("Barriers", BARRIERS, String(d.get("barrier_l", "auto")), func(v: String) -> void:
		draft.set_default("barrier_l", v)
		draft.set_default("barrier_r", v)))
	return out


func _use_everywhere(i: int) -> void:
	var p: Dictionary = draft.points()[i]
	var keys := p.keys().filter(func(k: String) -> bool: return k != "p" and k != "height")
	if keys.is_empty():
		editor.say("This point uses the road's settings already")
		return
	var values := {}
	for k: String in keys:
		values[k] = p[k]
	draft.use_everywhere(values)
	editor.say("Every point uses these now")


static func _surfaces(ids: Array) -> Array:
	return ids.map(func(id: String) -> Array: return [id, id.capitalize()])


static func _text(t: String) -> Label:
	var l := UiKit.label(t, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
