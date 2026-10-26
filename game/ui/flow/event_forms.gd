class_name EventForms
extends RefCounted
## The rows of each event type's Settings page (docs/UI_FLOW.md §6.1), for Local Drive and for
## hosting alike. Every row is a spinner (left and right), and stepping one changes the page's
## flow.

const LAPS := [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50]


## Fills `page` with its flow's rows, the sky rows last.
static func build(page: EventSettingsPage) -> void:
	var flow := page.flow
	if flow.has_track():
		page.add_row(track_row(page))
	if flow.type == "racing" and flow.variant in ["regular", "stock_car"] and not flow.tt:
		for row in race_rows(flow.event):
			page.add_row(row)
	for row in SkyRows.rows(flow.event):
		page.add_row(row)


## "Track": steps through the type's tracks in place; the pane shows the one picked.
static func track_row(page: EventSettingsPage) -> Button:
	var flow := page.flow
	var items := flow.tracks().map(func(e: Dictionary) -> Array: return [e.path, TrackLibrary.label(e)])
	return UiKit.spinner("Track", items, flow.track, func(path: String) -> void:
		flow.track = path
		page.show_track())


## Regular's and Stock Car's: practice, qualifying, laps, the AI field, collisions.
static func race_rows(e: RaceEvent) -> Array[Control]:
	var out: Array[Control] = []
	out.append(UiKit.spinner("Practice", minutes([0, 5, 10, 15, 30], e.practice_min), e.practice_min,
		func(v: int) -> void: e.practice_min = v))
	out.append(UiKit.spinner("Qualifying", minutes([0, 5, 10, 15], e.qualifying_min), e.qualifying_min,
		func(v: int) -> void: e.qualifying_min = v, "Sets the grid"))
	var laps := LAPS.duplicate()
	if e.race_laps not in laps:
		laps.append(e.race_laps)
		laps.sort()
	out.append(UiKit.spinner("Laps", laps.map(func(n: int) -> Array: return [n, "%d lap%s" % [n, "" if n == 1 else "s"]]), e.race_laps,
		func(v: int) -> void: e.race_laps = v))
	var counts := []
	for n in 16:
		counts.append([n, "%d" % n])
	out.append(UiKit.spinner("AI cars", counts, e.ai_count, func(v: int) -> void: e.ai_count = v))
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	e.ai_skill = snappedf(e.ai_skill, 5.0)
	out.append(UiKit.spinner("AI skill", skills, e.ai_skill, func(v: float) -> void: e.ai_skill = v))
	out.append(UiKit.spinner("Collisions", [[true, "On"], [false, "Ghosted"]], e.collisions,
		func(v: bool) -> void: e.collisions = v, "Ghosted: cars pass through each other"))
	return out


## [minutes, "5 min"] for each of `values` ("Off" for 0), with `current` added if it's not there.
static func minutes(values: Array, current: int) -> Array:
	var list := values.duplicate()
	if current not in list:
		list.append(current)
		list.sort()
	return list.map(func(m: int) -> Array: return [m, "Off" if m == 0 else "%d min" % m])
