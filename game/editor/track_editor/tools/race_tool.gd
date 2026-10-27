extends EditorTool
## The Race tool (EDT-05, EDT-06): the start line and direction, sector lines, checkpoints, the
## grid, the rolling start and the AI. The AI's line is solved by itself (minimum curvature) and
## drawn on the road; drag it sideways to pin it there, and it bends through the pin.
## Mouse: click the road to put the chosen thing there; drag a pin. Keys and controller: the
## crosshair places, or grabs a pin and drops it; [ ] (LB/RB) step through the pins; Delete (X)
## removes one. On a highway (EDT-10): the lap line, runs, speed traps, speed limit and tunnel
## zones, and the traffic; no grid or AI line (traffic keeps to its lanes).

const CLICKS := [["start", "Start line"], ["sector", "Sector line"], ["pin", "AI line pin"], ["pit_entry", "Pit entry"], ["pit_exit", "Pit exit"]]
const HIGHWAY_CLICKS := [["start", "Lap line"], ["run_start", "Run start"], ["run_end", "Run end"], ["trap", "Speed trap"],
	["zone_start", "Zone start"], ["zone_end", "Zone end"]]
## A new run or zone reaches this far until its end is set.
const NEW_RUN_M := 1500.0
const NEW_ZONE_M := 500.0
## A click this close (along the road) to a pin takes that pin.
const PIN_NEAR_M := 15.0
## Clicks further than this past the road's edge aren't on it.
const OFF_ROAD_M := 8.0

var click := "start"
var selected_pin := -1
var _dragging := false
## The run and zone the end clicks set (highways).
var _run := -1
var _zone := -1


func available() -> bool:
	return not draft.is_arena() # an arena has no laps (D138)


func title() -> String:
	return "Race"


func hint() -> String:
	match click:
		"sector":
			return "Click the road to add a sector line"
		"pin":
			return "Drag the AI line sideways to pin it · [ ] step · Del removes"
		"run_start":
			return "Click a carriageway where a run starts"
		"run_end", "zone_end":
			return "Click the road where it ends"
		"trap":
			return "Click a carriageway to put a speed trap there"
		"zone_start":
			return "Click the road where a speed limit or tunnel starts"
		"pit_entry":
			return "Click the road where the pit lane leaves it"
		"pit_exit":
			return "Click the road where the pit lane has joined it"
	return "Click the road to put the %s there · F5 drives" % ("lap line" if draft.is_highway() else "start line")


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
				"pit_entry", "pit_exit":
					view.grabbing = false
					_pit_click(click == "pit_entry", d)
				_:
					view.grabbing = false
					_highway_click(click, d, HighwayLayout.carriageway_at(float(on.lateral)))
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
	if t.samples.size() < 3 or t.highway:
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
	var clicks := HIGHWAY_CLICKS if draft.is_highway() else CLICKS
	if not clicks.any(func(c: Array) -> bool: return c[0] == click):
		click = "start"
	var out := [UiKit.spinner("Click sets", clicks, click, func(v: String) -> void:
		click = v
		editor._hint.text = hint(), "What a click on the road puts there")]
	if t.samples.size() < 3:
		out.append(UiKit.label("Add the road first.", 22))
		return out
	if t.highway:
		out.append_array(_highway_rows(t))
		out.append_array(_sky_rows())
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
	out.append_array(_pit_rows(t))
	out.append_array(_rule_rows())
	out.append_array(_ai_rows(t))
	out.append_array(_sky_rows())
	return out


## A pit lane (D203): where it leaves and joins the road (or "Pit entry" and "Pit exit" clicks),
## its side, width, speed limit, boxes and wall.
func _pit_rows(t: TrackData) -> Array:
	var out := [UiKit.label("Pit lane", 26)]
	var pit: Dictionary = draft.layout.get("pit", {})
	if pit.is_empty():
		out.append(UiKit.button("Add pit lane", func() -> void:
			draft.add_pit(fposmod(t.start_m - 400.0, t.length), fposmod(t.start_m + 300.0, t.length))
			editor.say(_pit_state()), "Along the start straight, on the right"))
		return out
	var length := t.length
	out.append(UiKit.number("Pit entry", float(pit.from_m), 0.0, length, 5.0, "%.0f m", func(v: float) -> void: draft.set_pit("from_m", v, "Move pit entry"),
		"Where it leaves the road, from point 1"))
	out.append(UiKit.number("Pit exit", float(pit.to_m), 0.0, length, 5.0, "%.0f m", func(v: float) -> void: draft.set_pit("to_m", v, "Move pit exit"),
		"Where it has joined the road"))
	out.append(UiKit.spinner("Pit side", [["right", "Right"], ["left", "Left"]], String(pit.get("side", "right")), func(v: String) -> void: draft.set_pit("side", v)))
	out.append(UiKit.number("Pit width", float(pit.get("width_m", PitLane.DEFAULTS.width_m)), 6.0, 20.0, 0.5, "%.1f m", func(v: float) -> void: draft.set_pit("width_m", v)))
	out.append(UiKit.number("Pit speed limit", float(pit.get("speed_kmh", PitLane.DEFAULTS.speed_kmh)), 30.0, 120.0, 5.0, "%.0f km/h",
		func(v: float) -> void: draft.set_pit("speed_kmh", v)))
	out.append(UiKit.number("Pit boxes", float(pit.get("boxes", PitLane.DEFAULTS.boxes)), 1.0, 40.0, 1.0, "%.0f", func(v: float) -> void: draft.set_pit("boxes", int(v))))
	out.append(UiKit.spinner("Pit wall", [[true, "On"], [false, "Off"]], bool(pit.get("wall", true)), func(v: bool) -> void: draft.set_pit("wall", v)))
	out.append(_note(_pit_state()))
	out.append(UiKit.button("Remove pit lane", func() -> void:
		draft.remove_pit()
		editor.say("Pit lane removed")))
	return out


## The rules the track suggests to events that keep "Track's" (D207).
func _rule_rows() -> Array:
	var rules := RaceEvent.rules_of(draft.layout.get("rules", {}))
	var out := [UiKit.label("Suggested rules", 26)]
	var times := []
	for x in range(0, RaceEvent.WEAR_X_MAX + 1):
		times.append([x, "Off" if x == 0 else "%dx" % x])
	out.append(UiKit.spinner("Start", [["standing", "Standing"], ["rolling", "Rolling"]], String(rules.start), func(v: String) -> void: draft.set_rule("start", v),
		"For events that keep the track's"))
	out.append(UiKit.spinner("Drafting", [[false, "Off"], [true, "On"]], bool(rules.draft), func(v: bool) -> void: draft.set_rule("draft", v)))
	out.append(UiKit.spinner("Fuel use", times, int(rules.fuel_x), func(v: int) -> void: draft.set_rule("fuel_x", v)))
	out.append(UiKit.spinner("Tire wear", times, int(rules.tyre_x), func(v: int) -> void: draft.set_rule("tyre_x", v)))
	out.append(UiKit.spinner("Pack racing", [[false, "Off"], [true, "On"]], bool(rules.pack), func(v: bool) -> void: draft.set_rule("pack", v),
		"With drafting on, the AI run in grooves and draft each other"))
	return out


func _pit_click(entry: bool, d: float) -> void:
	var t := draft.track()
	if not draft.layout.has("pit"):
		draft.add_pit(d if entry else fposmod(d - 700.0, t.length), fposmod(d + 700.0, t.length) if entry else d)
	else:
		draft.set_pit("from_m" if entry else "to_m", d, "Move pit entry" if entry else "Move pit exit")
	editor.say(_pit_state())


## How the pit lane came out: its length and boxes, or why it didn't build.
func _pit_state() -> String:
	var t := draft.track()
	if t.pit_error:
		return t.pit_error
	if t.pit == null:
		return "No pit lane"
	return "Pit lane %.0f m, %d boxes%s" % [t.pit.track.length, t.pit.boxes.size(), " (too many to fit)" if t.pit.crowded else ""]


## The track's own time and weather (D153): what events get when they keep "Track's".
func _sky_rows() -> Array:
	var env: Dictionary = draft.layout.get("environment", {})
	var times := [["", "Fixed sun"]] + SkyRows.TIMES.slice(1)
	var weathers := [["", "Clear"]] + SkyRows.WEATHERS.slice(2)
	var settings := [["", "None"]]
	for id: String in NossRoadGen.biome_ids():
		settings.append([id, String(EndlessBiomes.find(id).get("name", id.capitalize()))])
	return [
		UiKit.label("Sky", 26),
		UiKit.spinner("Time", times, String(env.get("time", "")), func(v: String) -> void: draft.set_env("time", v),
			"The track's own time of day; events can pick another"),
		UiKit.spinner("Weather", weathers, String(env.get("weather", "")), func(v: String) -> void: draft.set_env("weather", v),
			"The track's own weather; events can pick another"),
		UiKit.spinner("Setting", settings, String(env.get("biome", "")), func(v: String) -> void: draft.set_env("biome", v),
			"A biome's sky and sounds: Haunted is always a misty night"),
	]


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


# --- highways -----------------------------------------------------------------------------


func _highway_rows(t: TrackData) -> Array:
	var h := draft.highway()
	var out := [UiKit.label("Lap", 26)]
	out.append(UiKit.number("Lap line", t.start_m, 0.0, t.length, 1.0, "%.0f m", func(v: float) -> void: draft.set_race("start_m", v, "Move lap line"),
		"From point 1, along the road"))
	out.append(UiKit.button("Lap line at cursor", _start_at_cursor, "Put the lap line where the cursor is"))
	out.append(UiKit.button("Reverse direction", func() -> void:
		draft.flip_direction()
		editor.say("Direction reversed"), "Each carriageway becomes the other way"))
	out.append(UiKit.label("Runs", 26))
	var runs: Array = h.runs
	if runs.is_empty():
		out.append(_note("Choose \"Run start\" and click a carriageway."))
	for k in runs.size():
		var run: Dictionary = runs[k]
		var length := fposmod(int(run.dir) * (float(run.to_m) - float(run.from_m)), t.length)
		out.append(UiKit.button("%s%s · %s · %.1f km" % ["▶ " if k == _run else "", run.name, _from_lap(t, float(run.from_m)), length / 1000.0],
			func() -> void: _pick_run(k, true), "Select it and look at its start"))
	if _run >= 0 and _run < runs.size():
		var run: Dictionary = runs[_run]
		var k := _run
		out.append(UiKit.text_field("Run name", String(run.name), func(_v: String) -> void: pass, 32, "Enter to rename",
			func(v: String) -> void: _set_item("runs", k, "name", v.strip_edges().left(32) if v.strip_edges() else String(run.name), "Rename run")))
		out.append(UiKit.number("Starts at", float(run.from_m), 0.0, t.length, 5.0, "%.0f m", func(v: float) -> void: _set_item("runs", k, "from_m", v, "Move run start")))
		out.append(UiKit.number("Ends at", float(run.to_m), 0.0, t.length, 5.0, "%.0f m", func(v: float) -> void: _set_item("runs", k, "to_m", v, "Move run end")))
		out.append(UiKit.button("Delete run", func() -> void: _delete_item("runs", k, "Delete run"), "Remove it"))
	out.append(UiKit.label("Speed traps", 26))
	var traps: Array = h.traps
	for k in traps.size():
		var trap: Dictionary = traps[k]
		out.append(UiKit.button("Delete trap %d · %s · %s" % [k + 1, _way(int(trap.dir)), _from_lap(t, float(trap.at_m))], func() -> void: _delete_item("traps", k, "Delete speed trap"),
			"Remove it"))
	if traps.is_empty():
		out.append(_note("Choose \"Speed trap\" and click a carriageway."))
	out.append(UiKit.label("Speed limits and tunnels", 26))
	out.append(UiKit.number("Speed limit", float(h.speed_kmh), 60.0, 160.0, 10.0, "%.0f km/h", func(v: float) -> void: draft.set_highway("speed_kmh", v), "Everywhere else"))
	var zones: Array = h.zones
	for k in zones.size():
		var z: Dictionary = zones[k]
		var what := ("Tunnel, " if z.get("tunnel", false) else "") + "%d km/h" % roundi(float(z.get("speed_kmh", h.speed_kmh)))
		out.append(UiKit.button("%sZone %d · %s · %s" % ["▶ " if k == _zone else "", k + 1, what, _from_lap(t, float(z.from_m))], func() -> void: _pick_zone(k, true),
			"Select it and look at it"))
	if _zone >= 0 and _zone < zones.size():
		var z: Dictionary = zones[_zone]
		var k := _zone
		out.append(UiKit.number("Zone speed", float(z.get("speed_kmh", h.speed_kmh)), 30.0, 160.0, 10.0, "%.0f km/h", func(v: float) -> void: _set_item("zones", k, "speed_kmh", v, "Zone speed")))
		out.append(UiKit.spinner("Tunnel", [[true, "Yes"], [false, "No"]], bool(z.get("tunnel", false)), func(v: bool) -> void: _set_item("zones", k, "tunnel", v, "Zone tunnel")))
		out.append(UiKit.spinner("Which way", [[0, "Both"], [1, _way(1)], [-1, _way(-1)]], int(z.get("dir", 0)), func(v: int) -> void: _set_item("zones", k, "dir", v, "Zone direction")))
		out.append(UiKit.number("Zone from", float(z.from_m), 0.0, t.length, 5.0, "%.0f m", func(v: float) -> void: _set_item("zones", k, "from_m", v, "Move zone")))
		out.append(UiKit.number("Zone to", float(z.to_m), 0.0, t.length, 5.0, "%.0f m", func(v: float) -> void: _set_item("zones", k, "to_m", v, "Move zone")))
		out.append(UiKit.button("Delete zone", func() -> void: _delete_item("zones", k, "Delete zone"), "Remove it"))
	out.append(UiKit.label("Traffic", 26))
	var counts := []
	for n in [0, 50, 75, 100, 150, 200, 250, 300, 400]:
		counts.append([n, "Off" if n == 0 else str(n)])
	out.append(UiKit.spinner("Cars", counts, int(h.traffic.count), func(v: int) -> void: draft.set_highway("traffic/count", v, "Traffic cars"), "The track's own; events can change it"))
	out.append(UiKit.number("Taking exits", float(h.traffic.exit_share) * 100.0, 0.0, 40.0, 5.0, "%.0f%%", func(v: float) -> void: draft.set_highway("traffic/exit_share", v / 100.0, "Traffic exits"),
		"Cars leaving at each exit"))
	return out


## A click with a highway item chosen: at main-road distance `d`, on direction `dir`'s side.
func _highway_click(kind: String, d: float, dir: int) -> void:
	var h := draft.highway()
	var t := draft.track()
	match kind:
		"run_start":
			var runs: Array = h.runs.duplicate(true)
			var n := runs.size() + 1
			var ids := runs.map(func(r: Dictionary) -> String: return r.id)
			while "run_%d" % n in ids:
				n += 1
			runs.append({ "id": "run_%d" % n, "name": "Run %d" % n, "dir": dir, "from_m": d, "to_m": snappedf(fposmod(d + dir * NEW_RUN_M, t.length), 0.1) })
			draft.set_runs(runs, "Add run")
			_run = runs.size() - 1
			click = "run_end"
			editor.say("Run %d starts here, %s. Now click where it ends" % [n, _way(dir)])
		"run_end":
			if _run < 0 or _run >= h.runs.size():
				editor.say("Start a run first")
				return
			_set_item("runs", _run, "to_m", d, "Move run end")
			editor.say("Run ends here")
		"trap":
			var traps: Array = h.traps.duplicate(true)
			traps.append({ "dir": dir, "at_m": d })
			draft.set_traps(traps, "Add speed trap")
			editor.say("Speed trap, " + _way(dir))
		"zone_start":
			var zones: Array = h.zones.duplicate(true)
			zones.append({ "dir": 0, "from_m": d, "to_m": snappedf(fposmod(d + NEW_ZONE_M, t.length), 0.1), "speed_kmh": 80.0, "tunnel": false })
			draft.set_zones(zones, "Add zone")
			_zone = zones.size() - 1
			click = "zone_end"
			editor.say("Zone starts here. Now click where it ends")
		"zone_end":
			if _zone < 0 or _zone >= h.zones.size():
				editor.say("Start a zone first")
				return
			_set_item("zones", _zone, "to_m", d, "Move zone")
			editor.say("Zone ends here")
	editor._hint.text = hint()
	editor.refresh_panel()


## Sets `key` of item `k` of the highway's `list` (runs, traps, zones).
func _set_item(list: String, k: int, key: String, value: Variant, name: String) -> void:
	var items: Array = draft.highway()[list].duplicate(true)
	if k < 0 or k >= items.size():
		return
	items[k][key] = snappedf(value, 0.1) if value is float else value
	_set_list(list, items, name)


func _delete_item(list: String, k: int, name: String) -> void:
	var items: Array = draft.highway()[list].duplicate(true)
	if k < 0 or k >= items.size():
		return
	items.remove_at(k)
	_run = -1
	_zone = -1
	_set_list(list, items, name)
	editor.say(name.trim_prefix("Delete ").capitalize() + " deleted")


func _set_list(list: String, items: Array, name: String) -> void:
	match list:
		"runs":
			draft.set_runs(items, name)
		"traps":
			draft.set_traps(items, name)
		"zones":
			draft.set_zones(items, name)


func _pick_run(k: int, look: bool) -> void:
	_run = k
	var runs: Array = draft.highway().runs
	if look and k < runs.size():
		view.camera.focus(draft.track().point_at(float(runs[k].from_m)))
		editor.say("%s, %s" % [runs[k].name, _way(int(runs[k].dir))])
	editor.refresh_panel()


func _pick_zone(k: int, look: bool) -> void:
	_zone = k
	var zones: Array = draft.highway().zones
	if look and k < zones.size():
		view.camera.focus(draft.track().point_at(float(zones[k].from_m)))
		editor.say("Zone %d" % (k + 1))
	editor.refresh_panel()


## "Clockwise" or "Anticlockwise": the way direction `dir` goes round.
func _way(dir: int) -> String:
	return "Clockwise" if draft.track().highway.clockwise(dir) else "Anticlockwise"


static func _from_lap(t: TrackData, d: float) -> String:
	return _where(t, d)


static func _note(text: String) -> Label:
	var l := UiKit.label(text, 20)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _where(t: TrackData, d: float) -> String:
	var from := t.from_start(d)
	return "%d m" % roundi(from) if from < 1000.0 else "%.2f km" % (from / 1000.0)
