extends EditorTool
## The Race tool (EDT-05, EDT-06): the start line and direction, sector lines, checkpoints, the
## grid, the rolling start and the AI. The AI's line is solved by itself (minimum curvature) and
## drawn on the road; drag it sideways to pin it there, and it bends through the pin.
## Mouse: click the road to put the chosen thing there; drag a pin. Keys and controller: the
## crosshair places, or grabs a pin and drops it; [ ] (LB/RB) step through the pins; Delete (X)
## removes one.

const CLICKS := [["start", "Start line"], ["sector", "Sector line"], ["pin", "AI line pin"]]
## A click this close (along the road) to a pin takes that pin.
const PIN_NEAR_M := 15.0
## Clicks further than this past the road's edge aren't on it.
const OFF_ROAD_M := 8.0

var click := "start"
var selected_pin := -1
var _dragging := false


func title() -> String:
	return "Race"


func hint() -> String:
	match click:
		"sector":
			return "Click the road to add a sector line"
		"pin":
			return "Drag the AI line sideways to pin it · [ ] step · Del removes"
	return "Click the road to put the start line there · F5 drives"


func selection_state() -> Dictionary:
	return { "pin": selected_pin }


func activate() -> void:
	selected_pin = clampi(int(draft.view.get("pin", selected_pin)), -1, _pins().size() - 1)


func pointer(e: Dictionary) -> void:
	var t := draft.track()
	if t.samples.size() < 3:
		if e.kind == "press":
			editor.say("Add the road first")
		return
	match String(e.kind):
		"press":
			var on := _on_road(e.hit)
			if on.is_empty():
				editor.say("Not on the road")
				view.grabbing = false
				return
			var d := snappedf(float(on.distance), 0.1)
			match click:
				"start":
					view.grabbing = false
					draft.set_race("start_m", d, "Move start")
					editor.say("Start line moved")
				"sector":
					view.grabbing = false
					_add_sector(d)
				"pin":
					_press_pin(d, float(on.lateral), e.crosshair)
		"drag":
			if _dragging and selected_pin >= 0 and e.hit.hit:
				var on := _on_road(e.hit, true)
				if not on.is_empty():
					_set_pin_offset(float(on.lateral), true)
		"release":
			if _dragging:
				_dragging = false
				draft.end_race_live("Pin AI line")
				if e.crosshair:
					editor.say("Pin put down")
				editor.refresh_panel()


func action(name: String) -> bool:
	match name:
		"delete":
			if selected_pin >= 0:
				_remove_pin(selected_pin)
			else:
				editor.say("Select a pin first")
			return true
		"prev", "next":
			var n := _pins().size()
			if n == 0:
				editor.say("No pins")
			else:
				_select_pin(posmod(selected_pin + (1 if name == "next" else -1), n), true)
			return true
	return false


func draft_changed(_what: StringName) -> void:
	if selected_pin >= _pins().size():
		selected_pin = -1
	if not _dragging and editor.tool == self:
		editor.refresh_panel()


func analysed() -> void:
	if editor.tool == self:
		refresh_gizmos()
		var lap := _lap_label()
		if lap:
			lap.text = _lap_text()


func refresh_gizmos() -> void:
	super()
	var t := draft.track()
	if t.samples.size() < 3:
		return
	var line: RacingLine = editor.analysis.get("line")
	var at := PackedVector3Array()
	if line and line.points.size() == t.samples.size():
		at = line.points
	var marks := []
	for pin: Dictionary in _pins():
		marks.append(t.transform_at(float(pin.at_m), float(pin.offset_m)).origin)
	view.gizmos.show_ai_line(at, t.lefts, marks, selected_pin)


# --- the panel ----------------------------------------------------------------------------


func panel() -> Array:
	var t := draft.track()
	var out := [UiKit.spinner("Click sets", CLICKS, click, func(v: String) -> void:
		click = v
		editor._hint.text = hint(), "What a click on the road puts there")]
	if t.samples.size() < 3:
		out.append(UiKit.label("Add the road first.", 22))
		return out
	var race: Dictionary = draft.layout.race
	var length := t.length
	out.append(UiKit.label("Start and direction", 26))
	out.append(UiKit.number("Start", t.start_m, 0.0, length, 1.0, "%.0f m", func(v: float) -> void: draft.set_race("start_m", v, "Move start"),
		"From point 1, along the road"))
	out.append(UiKit.button("Start at cursor", _start_at_cursor, "Put the start line where the cursor is"))
	out.append(UiKit.button("Reverse direction", func() -> void:
		draft.flip_direction()
		editor.say("Direction reversed"), "Drive the track the other way"))
	out.append(UiKit.label("Timing", 26))
	var counts := []
	for n in range(1, 7):
		counts.append([n, "%d sector%s" % [n, "" if n == 1 else "s"]])
	out.append(UiKit.spinner("Sectors", counts, t.sectors_m.size() + 1, _even_sectors, "Splits the lap evenly"))
	for k in t.sectors_m.size():
		out.append(UiKit.number("Sector line %d" % (k + 1), t.sectors_m[k], 0.0, length, 5.0, "%.0f m", _move_sector.bind(k), "From the start line"))
	if not t.sectors_m.is_empty():
		out.append(UiKit.button("Remove last sector line", func() -> void:
			var lines: Array = race.get("sectors_m", []).duplicate()
			lines.pop_back()
			draft.set_race("sectors_m", lines, "Remove sector line")))
	out.append(UiKit.number("Checkpoints every", t.checkpoint_spacing, 25.0, 500.0, 5.0, "%.0f m",
		func(v: float) -> void: draft.set_race("checkpoint_spacing_m", v, "Checkpoint spacing"), "Missing one doesn't count the lap"))
	out.append(UiKit.label("Grid", 26))
	var g := t.grid
	out.append(UiKit.number("Grid slots", float(g.slots), 2.0, 40.0, 1.0, "%.0f", func(v: float) -> void: draft.set_race("grid/slots", int(v), "Grid slots")))
	out.append(UiKit.number("First row back", float(g.front_m), 2.0, 60.0, 0.5, "%.1f m", func(v: float) -> void: draft.set_race("grid/front_m", v, "Grid front"),
		"Start line to the pole car"))
	out.append(UiKit.number("Row spacing", float(g.row_m), 6.0, 30.0, 0.5, "%.1f m", func(v: float) -> void: draft.set_race("grid/row_m", v, "Grid rows")))
	out.append(UiKit.number("Stagger", float(g.stagger), 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void: draft.set_race("grid/stagger", v, "Grid stagger"),
		"How far back the second column sits, in rows"))
	out.append(UiKit.spinner("Pole", [["left", "Left"], ["right", "Right"]], g.pole, func(v: String) -> void: draft.set_race("grid/pole", v, "Pole side")))
	out.append(UiKit.number("Rolling start from", t.rolling_back_m, 50.0, 1000.0, 10.0, "%.0f m",
		func(v: float) -> void: draft.set_race("rolling_back_m", v, "Rolling start"), "Before the line"))
	out.append(UiKit.spinner("Start gantry", [[true, "On"], [false, "Off"]], t.gantry, func(v: bool) -> void: draft.set_race("gantry", v, "Start gantry")))
	out.append_array(_ai_rows(t))
	return out


func _ai_rows(t: TrackData) -> Array:
	var out := [UiKit.label("AI", 26)]
	var ai: Dictionary = draft.layout.race.get("ai", {})
	var auto := float(ai.get("caution_until_m", TrackFormat.CAUTION_AUTO)) < 0.0
	out.append(UiKit.spinner("AI caution", [["auto", "Auto"], ["set", "Set"]], "auto" if auto else "set", func(v: String) -> void:
		draft.set_race("ai/caution_until_m", TrackFormat.CAUTION_AUTO if v == "auto" else snappedf(t.caution_until_m, 10.0), "AI caution"),
		"How far the AI drives carefully on lap 1"))
	if not auto:
		out.append(UiKit.number("Careful until", t.caution_until_m, 0.0, t.length, 10.0, "%.0f m", func(v: float) -> void: draft.set_race("ai/caution_until_m", v, "AI caution")))
	var lap := UiKit.label(_lap_text(), 24)
	lap.name = "AiLap"
	out.append(lap)
	var pins := _pins()
	for k in pins.size():
		var pin: Dictionary = pins[k]
		var o := float(pin.offset_m)
		var text := "Pin %d · %s · %.1f m %s" % [k + 1, _where(t, float(pin.at_m)), absf(o), "left" if o >= 0.0 else "right"]
		var b := UiKit.button(("▶ " if k == selected_pin else "") + text, _select_pin.bind(k, true), "Select it and look at it")
		out.append(b)
	if selected_pin >= 0 and selected_pin < pins.size():
		var c := RacingLine.corridor_at(t, float(pins[selected_pin].at_m))
		out.append(UiKit.number("Pin offset", float(pins[selected_pin].offset_m), c.y, c.x, 0.1, "%.1f m", func(v: float) -> void: _set_pin_offset(v, false),
			"Left of the centre (+) or right (-)"))
		out.append(UiKit.button("Remove pin", func() -> void: _remove_pin(selected_pin), "Delete or X"))
	if pins.is_empty():
		var note := UiKit.label("Choose \"AI line pin\", then drag the line to pin it.", 20)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		out.append(note)
	else:
		out.append(UiKit.button("Reset AI line", func() -> void:
			selected_pin = -1
			draft.set_race("ai/pins", [], "Reset AI line")
			editor.say("AI line reset"), "Remove every pin"))
	return out


func _lap_label() -> Label:
	for c in editor._content.get_children():
		if c.name == &"AiLap":
			return c
	return null


func _lap_text() -> String:
	var a: Dictionary = editor.analysis
	if a.get("stamp", -1) != editor._changes or not a.has("lap_s"):
		return "AI lap …"
	return "AI lap %s" % Hud.format_time(float(a.lap_s)).left(-2)


# --- doing it -----------------------------------------------------------------------------


## Where a pick lands on the road: {distance, lateral}, or {} off it. `any`: anywhere near.
func _on_road(hit: Dictionary, any := false) -> Dictionary:
	if not hit.get("hit", false):
		return {}
	var t := draft.track()
	var proj := t.project(hit.position)
	var i: int = proj.index
	var reach: float = (t.half_l[i] if proj.lateral >= 0.0 else t.half_r[i]) + OFF_ROAD_M
	if not any and absf(proj.lateral) > reach:
		return {}
	return proj


func _start_at_cursor() -> void:
	var on := _on_road(view.pick(view.cursor()))
	if on.is_empty():
		editor.say("The cursor isn't on the road")
		return
	draft.set_race("start_m", snappedf(float(on.distance), 0.1), "Move start")
	editor.say("Start line moved")


func _add_sector(d: float) -> void:
	var t := draft.track()
	var lines: Array = draft.layout.race.get("sectors_m", []).duplicate()
	lines.append(d)
	lines.sort_custom(func(a: float, b: float) -> bool: return t.from_start(a) < t.from_start(b))
	draft.set_race("sectors_m", lines, "Add sector line")
	editor.say("%d sectors" % (lines.size() + 1))


## `n` sectors of equal length.
func _even_sectors(n: int) -> void:
	var t := draft.track()
	var lines := []
	for k in range(1, n):
		lines.append(snappedf(fposmod(t.start_m + t.length * k / n, t.length), 0.1))
	draft.set_race("sectors_m", lines, "Even sectors")
	editor.say("%d sectors" % n)


func _move_sector(from_start: float, k: int) -> void:
	var t := draft.track()
	var lines: Array = draft.layout.race.get("sectors_m", []).duplicate()
	if k < lines.size():
		lines[k] = snappedf(fposmod(t.start_m + from_start, t.length), 0.1)
		draft.set_race("sectors_m", lines, "Move sector line")


func _pins() -> Array:
	return draft.layout.race.get("ai", {}).get("pins", [])


## Takes the pin near `d`, or pins the line there; then it follows the pointer.
func _press_pin(d: float, lateral: float, crosshair: bool) -> void:
	var t := draft.track()
	var pins := _pins()
	var near := -1
	for k in pins.size():
		var gap := absf(float(pins[k].at_m) - d)
		if minf(gap, t.length - gap) < PIN_NEAR_M:
			near = k
	if near < 0:
		var c := RacingLine.corridor_at(t, d)
		var added := pins.duplicate(true)
		added.append({ "at_m": d, "offset_m": snappedf(clampf(lateral, c.y, c.x), 0.1) })
		draft.set_race_live("ai/pins", added)
		near = added.size() - 1
		editor.say("AI line pinned")
	elif crosshair:
		editor.say("Pin picked up")
	selected_pin = near
	_dragging = true


## The selected pin `offset` m left of the centre (held inside the corridor).
func _set_pin_offset(offset: float, live: bool) -> void:
	var pins := _pins().duplicate(true)
	if selected_pin < 0 or selected_pin >= pins.size():
		return
	var c := RacingLine.corridor_at(draft.track(), float(pins[selected_pin].at_m))
	pins[selected_pin].offset_m = snappedf(clampf(offset, c.y, c.x), 0.1)
	if live:
		draft.set_race_live("ai/pins", pins)
	else:
		draft.set_race("ai/pins", pins, "Pin AI line")


func _remove_pin(k: int) -> void:
	var pins := _pins().duplicate(true)
	if k < 0 or k >= pins.size():
		return
	pins.remove_at(k)
	selected_pin = -1
	draft.set_race("ai/pins", pins, "Remove pin")
	editor.say("Pin removed")


func _select_pin(k: int, look: bool) -> void:
	selected_pin = k
	var pins := _pins()
	if look and k >= 0 and k < pins.size():
		var t := draft.track()
		view.camera.focus(t.transform_at(float(pins[k].at_m), float(pins[k].offset_m)).origin)
		editor.say("Pin %d of %d" % [k + 1, pins.size()])
	editor.refresh_panel()
	refresh_gizmos()


static func _where(t: TrackData, d: float) -> String:
	var from := t.from_start(d)
	return "%d m" % roundi(from) if from < 1000.0 else "%.2f km" % (from / 1000.0)
