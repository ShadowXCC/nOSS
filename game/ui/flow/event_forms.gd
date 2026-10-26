class_name EventForms
extends RefCounted
## The rows of each event type's Settings page (docs/UI_FLOW.md §6.1), for Local Drive and for
## hosting alike. Every row is a spinner (left and right), a button or a text field, and changing
## one changes the page's flow. A row that changes which rows there are (Kart's Play, a highway's
## Mode) builds them again (EventSettingsPage.rebuild()), the focus staying on it.

const LAPS := [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50]
const ON := [[true, "On"], [false, "Off"]]
const OFF := [[false, "Off"], [true, "On"]]
## Endless.
const ENDLESS_TRAFFIC := [["light", "Light"], ["normal", "Normal"], ["heavy", "Heavy"], ["off", "Off"]]
const SPREAD := [["bring", "Bring up the one behind"], ["hold", "Hold the leader back"]]
const LANES := [[2, "2"], [4, "4"]]
const SIDES := [["right", "Right"], ["left", "Left"]]
## Highway.
const HIGHWAY_MODES := [["cruise", "Cruise"], ["score", "Score attack"], ["run", "Run"], ["loop", "Loop"]]
const HIGHWAY_TRAFFIC := [[0, "Off"], [75, "75"], [150, "150"], [250, "250"], [400, "400"]]
## Kart and Kart Battle.
const KART_PLAY := [["race", "Race"], ["cup", "Cup"]]
const BATTLE_RULES := [["standing", "Last one standing"], ["hits", "Most hits"]]
const HITS_TO_WIN := [[5, "5"], [10, "10"], [15, "15"], [20, "20"], [0, "None"]]
const BATTLE_MINUTES := [[3, "3"], [5, "5"], [7, "7"], [10, "10"]]
## Sumo Wrestling.
const TIERS := [[1, "1"], [2, "2"], [3, "3"], [4, "4"], [5, "5"]]
const HAZARDS := [["lava", "Lava"], ["acid", "Acid"]]
const SHRINKS := [["smooth", "Smooth"], ["crumble", "Crumbling"], ["stepped", "Stepped"]]
const SUMO_LENGTHS := [[60, "Short"], [90, "Normal"], [150, "Long"]]
const DRIFTS := [["off", "Off"], ["drift", "Drift"], ["boost", "Drift + boost"]]
## Drag Strip: each length in metres, with its name in miles and in metres (Settings.units picks).
const DRAG_LENGTHS := [[201, "1/8 mile", "201 m"], [402, "1/4 mile", "402 m"], [805, "1/2 mile", "805 m"]]
const BOOSTS := [[0, "Off"], [1, "1"], [2, "2"], [3, "3"]]


## Fills `page` with its flow's rows, the sky rows last.
static func build(page: EventSettingsPage) -> void:
	var flow := page.flow
	match flow.id().trim_suffix("/tt"):
		"racing/regular", "racing/stock_car":
			page.add_row(track_row(page))
			if not flow.tt:
				for row in race_rows(flow.event):
					page.add_row(row)
		"racing/kart":
			kart(page)
		"racing/custom":
			custom(page)
		"endless":
			endless(page)
		"highway":
			highway(page)
		"mini/sumo":
			sumo(page)
		"mini/drag":
			drag(page)
		"mini/kart_battle":
			battle(page)
		"free":
			free_drive(page)
	for row in SkyRows.rows(flow.event):
		page.add_row(row)


## "Track" (or `label`: "Arena", "Highway"): steps through the type's tracks in place; the pane
## shows the one picked, then `then` gets it. Free Drive's list says which are highways.
static func track_row(page: EventSettingsPage, label := "Track", then := Callable(), description := "") -> Button:
	var flow := page.flow
	var mixed := flow.track_type().is_empty()
	var items := flow.tracks().map(func(e: Dictionary) -> Array:
		return [e.path, TrackLibrary.label(e) + (" · Highway" if mixed and e.get("type") == "highway" else "")])
	return UiKit.spinner(label, items, flow.track, func(path: String) -> void:
		flow.track = path
		page.show_track()
		if then.is_valid():
			then.call(path), description)


## Regular's and Stock Car's: practice, qualifying, laps, the AI field, collisions.
static func race_rows(e: RaceEvent) -> Array[Control]:
	var out: Array[Control] = []
	out.append(UiKit.spinner("Practice", minutes([0, 5, 10, 15, 30], e.practice_min), e.practice_min,
		func(v: int) -> void: e.practice_min = v))
	out.append(UiKit.spinner("Qualifying", minutes([0, 5, 10, 15], e.qualifying_min), e.qualifying_min,
		func(v: int) -> void: e.qualifying_min = v, "Sets the grid"))
	out.append(laps_row(e, "Laps"))
	out.append(UiKit.spinner("AI cars", numbers(0, 15), e.ai_count, func(v: int) -> void: e.ai_count = v))
	out.append(skill_row(e))
	out.append(UiKit.spinner("Collisions", [[true, "On"], [false, "Ghosted"]], e.collisions,
		func(v: bool) -> void: e.collisions = v, "Ghosted: cars pass through each other"))
	return out


## A race's laps ("5 laps"), `e.race_laps` added if it isn't one of LAPS.
static func laps_row(e: RaceEvent, label: String) -> Button:
	var laps := LAPS.duplicate()
	if e.race_laps not in laps:
		laps.append(e.race_laps)
		laps.sort()
	return UiKit.spinner(label, laps.map(func(n: int) -> Array: return [n, "%d lap%s" % [n, "" if n == 1 else "s"]]), e.race_laps,
		func(v: int) -> void: e.race_laps = v)


static func skill_row(e: RaceEvent) -> Button:
	var skills := []
	for n in range(0, 101, 5):
		skills.append([float(n), "%d" % n])
	e.ai_skill = snappedf(e.ai_skill, 5.0)
	return UiKit.spinner("AI skill", skills, e.ai_skill, func(v: float) -> void: e.ai_skill = v)


## How many AI cars (`label`: "AI karts"), at most `most`, and their skill.
static func ai_rows(page: EventSettingsPage, label: String, most: int, description := "") -> void:
	var e := page.flow.event
	page.add_row(UiKit.spinner(label, numbers(0, most), clampi(e.ai_count, 0, most), func(v: int) -> void: e.ai_count = v, description))
	page.add_row(skill_row(e))


## Kart (D144, D145): a race on any circuit (kart tracks first) or a cup, the AI karts, the items.
static func kart(page: EventSettingsPage) -> void:
	var flow := page.flow
	var e := flow.event
	if flow.tt:
		page.add_row(track_row(page))
		return
	page.add_row(UiKit.spinner("Play", KART_PLAY, "cup" if flow.cup else "race", func(v: String) -> void:
		if v == "cup":
			var cups := CupRun.list()
			flow.cup = String(page.stash.get("cup", cups[0].path if not cups.is_empty() else ""))
		else:
			page.stash.cup = flow.cup
			flow.cup = ""
		page.rebuild.call_deferred("Play"), "Race: one race. Cup: four races for points"))
	if flow.cup.is_empty():
		page.add_row(track_row(page))
		page.add_row(UiKit.spinner("Laps", numbers(1, 10), clampi(e.race_laps, 1, 10), func(v: int) -> void: e.race_laps = v))
	else:
		cup_rows(page)
	ai_rows(page, "AI karts", 11)
	page.add_row(UiKit.spinner("Items", ON, e.items, func(v: bool) -> void: e.items = v))


## A cup: which, its races, and changing, deleting or making one.
static func cup_rows(page: EventSettingsPage) -> void:
	var flow := page.flow
	var cups := CupRun.list()
	page.add_row(UiKit.spinner("Cup", cups.map(func(c: Dictionary) -> Array: return [c.path, String(c.name) + ("" if c.builtin else " (yours)")]),
		flow.cup, func(v: String) -> void:
			flow.cup = v
			page.rebuild.call_deferred("Cup")))
	var c := CupRun.load_file(flow.cup)
	var names := PackedStringArray()
	for r: Dictionary in c.get("races", []):
		var t := TrackLibrary.entry(TrackLibrary.resolve(String(r.track)))
		names.append("%s (%d)" % [String(t.get("name", "Track missing")), int(r.laps)])
	page.add_text(", ".join(names))
	var missing := CupRun.missing_track(c)
	if missing >= 0:
		page.add_text("Track missing: race %d" % (missing + 1), true)
	if not flow.cup.begins_with("res://"):
		page.add_row(UiKit.button("Change this cup", page.open_cup_builder.bind(c), "Its name, tracks and laps"))
		page.add_row(UiKit.button("Delete this cup", page.delete_cup.bind(c), "Asks first"))
	page.add_row(UiKit.button("New cup", page.open_cup_builder.bind({}), "Pick four tracks and their laps"))


## Kart Battle (D144): items in an arena, the last one standing or the most hits.
static func battle(page: EventSettingsPage) -> void:
	var flow := page.flow
	var e := flow.event
	if flow.tracks().is_empty():
		page.add_text("No arenas yet. Build one in the Track Editor.", true)
	else:
		page.add_row(track_row(page, "Arena"))
	page.add_row(UiKit.spinner("Rule", BATTLE_RULES, e.battle_rule, func(v: String) -> void:
		e.battle_rule = v
		page.rebuild.call_deferred("Rule"), "Last one standing: three lives each. Most hits: hits count, nobody goes out"))
	if e.battle_rule == "hits":
		page.add_row(UiKit.spinner("Hits to win", HITS_TO_WIN, e.battle_hits, func(v: int) -> void: e.battle_hits = v,
			"The first to this many wins; None: the most when time's up"))
	page.add_row(UiKit.spinner("Minutes", BATTLE_MINUTES, e.battle_min, func(v: int) -> void: e.battle_min = v))
	ai_rows(page, "AI karts", 11)


## Custom: the presets, then every setting of a race weekend (the old Race menu's), any circuit;
## its time trial only the track and its limits.
static func custom(page: EventSettingsPage) -> void:
	var flow := page.flow
	var e := flow.event
	preset_rows(page)
	# The rule rows show the track's own: a new track, new rows.
	page.add_row(track_row(page, "Track", func(_path: String) -> void: page.rebuild.call_deferred("Track")))
	if not flow.tt:
		page.add_row(UiKit.spinner("Practice", minutes([0, 5, 10, 15, 30], e.practice_min), e.practice_min,
			func(v: int) -> void: e.practice_min = v))
		page.add_row(UiKit.spinner("Qualifying", minutes([0, 5, 10, 15], e.qualifying_min), e.qualifying_min,
			func(v: int) -> void: e.qualifying_min = v))
		page.add_row(UiKit.spinner("Race length", [["laps", "Laps"], ["time", "Time"]], "time" if e.race_min > 0 else "laps",
			func(v: String) -> void:
				e.race_min = 10 if v == "time" else 0
				page.rebuild.call_deferred("Race length")))
		if e.race_min > 0:
			page.add_row(UiKit.spinner("Race", minutes([5, 10, 15, 20, 30, 45, 60], e.race_min), e.race_min,
				func(v: int) -> void: e.race_min = v))
		else:
			page.add_row(laps_row(e, "Race"))
		page.add_row(UiKit.spinner("AI cars", numbers(0, 15), e.ai_count, func(v: int) -> void: e.ai_count = v))
		page.add_row(skill_row(e))
		page.add_row(UiKit.spinner("AI cars look", [["garage", "Garage"], ["builtin", "Built-in"]], e.ai_cars,
			func(v: String) -> void: e.ai_cars = v))
		for row in rule_rows(e, flow.track):
			page.add_row(row)
		page.add_row(UiKit.spinner("Grid", [["qualifying", "Qualifying"], ["reverse", "Reverse"], ["random", "Random"]], e.grid,
			func(v: String) -> void: e.grid = v))
		page.add_row(UiKit.spinner("Collisions", [[true, "On"], [false, "Ghosted"]], e.collisions,
			func(v: bool) -> void: e.collisions = v))
	page.add_row(UiKit.spinner("Track limits", [["off", "Off"], ["lenient", "Lenient"], ["strict", "Strict"]], e.track_limits,
		func(v: String) -> void: e.track_limits = v, "Cutting the track spoils a timed lap" if flow.tt else ""))
	if not flow.tt:
		page.add_row(UiKit.spinner("Items", ON, e.items, func(v: bool) -> void: e.items = v, "Kart classes only"))


## "Preset" (None, then the saved ones; picking one fills the rows), "Save preset" and "Delete
## preset".
static func preset_rows(page: EventSettingsPage) -> void:
	var flow := page.flow
	var presets := EventPresets.list(flow.tt)
	if not presets.any(func(p: Dictionary) -> bool: return p.path == page.preset):
		page.preset = ""
	var items := [["", "None"]] + presets.map(func(p: Dictionary) -> Array: return [p.path, p.name])
	page.add_row(UiKit.spinner("Preset", items, page.preset, func(path: String) -> void:
		page.preset = path
		if path:
			EventPresets.apply(EventPresets.load_file(path), flow)
		page.rebuild.call_deferred("Preset"), "Picking one fills the rows"))
	page.add_row(UiKit.button("Save preset", page.save_preset, "Keep these settings under a name"))
	var delete := UiKit.button("Delete preset", page.delete_preset, "Asks first")
	delete.disabled = page.preset.is_empty()
	page.add_row(delete)


## Start, drafting, fuel use and tire wear (D207): each "Track's" or the event's own, `track`'s
## shown beside it.
static func rule_rows(e: RaceEvent, track: String) -> Array[Control]:
	var rules := RaceEvent.rules_of(TrackLibrary.rules(track))
	var times := func(x: int) -> String: return "Off" if x <= 0 else "%dx" % x
	var multipliers := func(track_x: int) -> Array:
		var out := [[-1, "Track's (%s)" % times.call(track_x)], [0, "Off"]]
		for x in range(1, RaceEvent.WEAR_X_MAX + 1):
			out.append([x, "%dx" % x])
		return out
	var out: Array[Control] = []
	out.append(UiKit.spinner("Start", [["track", "Track's (%s)" % String(rules.start).capitalize()], ["standing", "Standing"], ["rolling", "Rolling"]], e.start,
		func(v: String) -> void: e.start = v, "Rolling: the field follows at a steady pace and the green comes at the line"))
	out.append(UiKit.spinner("Drafting", [["track", "Track's (%s)" % ("On" if bool(rules.draft) else "Off")], ["off", "Off"], ["on", "On"]], e.draft,
		func(v: String) -> void: e.draft = v, "Close behind another car, less drag"))
	out.append(UiKit.spinner("Fuel use", multipliers.call(int(rules.fuel_x)), e.fuel_x, func(v: int) -> void: e.fuel_x = v,
		"Times the car's own: more means more pit stops"))
	out.append(UiKit.spinner("Tire wear", multipliers.call(int(rules.tyre_x)), e.tyre_x, func(v: int) -> void: e.tyre_x = v,
		"Times the car's own: worn tires grip less"))
	return out


## Endless (D157): the road (a code to share, or a new one), where it starts, its lanes and side,
## the traffic, the police, and what happens when players drift far apart.
static func endless(page: EventSettingsPage) -> void:
	var e := page.flow.event
	var code_row := UiKit.text_field("Road code", EndlessCode.encode(e.road_seed, e.biome), func(_t: String) -> void: pass, 24,
		"Type a friend's code to drive their road")
	var code := code_row.get_child(1) as LineEdit
	code.text_submitted.connect(func(_t: String) -> void: _enter_code(page, code))
	code.focus_exited.connect(func() -> void: _enter_code(page, code))
	page.add_row(code_row)
	page.add_row(UiKit.button("New road", func() -> void:
		e.road_seed = EndlessCode.random_seed()
		page.rebuild.call_deferred("New road"), "A road nobody has driven"))
	page.add_row(UiKit.spinner("Start in", EndlessBiomes.choices(), e.biome, func(v: int) -> void:
		e.biome = v
		code.text = EndlessCode.encode(e.road_seed, e.biome), "The biome the road starts in"))
	page.add_row(UiKit.spinner("Lanes", LANES, e.lanes, func(v: int) -> void: e.lanes = v, "One or two each way"))
	page.add_row(UiKit.spinner("Drive on", SIDES, e.drive_side, func(v: String) -> void: e.drive_side = v, "The side traffic keeps to"))
	page.add_row(UiKit.spinner("Traffic", ENDLESS_TRAFFIC, e.endless_traffic, func(v: String) -> void: e.endless_traffic = v,
		"Other cars on the road"))
	page.add_row(UiKit.spinner("Garage cars", ON, e.garage_traffic, func(v: bool) -> void: e.garage_traffic = v,
		"Your cars in the traffic"))
	page.add_row(UiKit.spinner("Oncoming", ON, e.oncoming, func(v: bool) -> void: e.oncoming = v, "Cars coming the other way"))
	page.add_row(UiKit.spinner("Speed traps", OFF, e.speed_traps, func(v: bool) -> void: e.speed_traps = v,
		"Cameras and parked patrols"))
	page.add_row(UiKit.spinner("Police", OFF, e.police, func(v: bool) -> void: e.police = v, "Speeding draws a chase"))
	page.add_row(UiKit.spinner("Far apart", SPREAD, e.spread, func(v: String) -> void: e.spread = v,
		"Players on this PC stay within 3 km: who moves when they don't"))


## A typed road code: that road and biome, or a note and the last one back if it isn't one. Not
## from a field of rows already gone (it loses the focus as they're built again).
static func _enter_code(page: EventSettingsPage, code: LineEdit) -> void:
	if not is_instance_valid(page) or not page.is_inside_tree() or not page.body.is_ancestor_of(code):
		return
	var e := page.flow.event
	var d := EndlessCode.decode(code.text)
	if d.is_empty():
		page.status.text = "Not a road code"
		code.text = EndlessCode.encode(e.road_seed, e.biome)
		return
	page.status.text = ""
	if int(d.seed) != e.road_seed or int(d.biome) != e.biome:
		e.road_seed = int(d.seed)
		e.biome = int(d.biome)
		page.rebuild.call_deferred("Road code")


## Highway (M7): the highway, what to do on it (Cruise, Score attack, Run, Loop), its traffic and
## police, and which way round to start (named from the track), or for a run, which one.
static func highway(page: EventSettingsPage) -> void:
	var flow := page.flow
	var e := flow.event
	if flow.tracks().is_empty():
		page.add_text("No highways yet. Build one in the Track Editor.", true)
		return
	page.add_row(track_row(page, "Highway", func(_path: String) -> void: page.rebuild.call_deferred("Highway")))
	var data := page.track_data(flow.track)
	var layout: Variant = data.highway if data else null
	if e.traffic < 0 and layout:
		e.traffic = int(layout.settings.traffic.count)
	page.add_row(UiKit.spinner("Mode", HIGHWAY_MODES, e.sub, func(v: String) -> void:
		var was := e.sub
		e.sub = v
		if (v == "run") != (was == "run"):
			page.rebuild.call_deferred("Mode"), "Cruise: no score. Score attack: near misses. Run: a sprint. Loop: lap times"))
	var counts := HIGHWAY_TRAFFIC.duplicate()
	if not counts.any(func(c: Array) -> bool: return c[0] == e.traffic):
		counts.append([e.traffic, str(e.traffic)])
	page.add_row(UiKit.spinner("Traffic", counts, e.traffic, func(v: int) -> void: e.traffic = v, "Cars on the road"))
	page.add_row(UiKit.spinner("Police", OFF, e.police, func(v: bool) -> void: e.police = v,
		"Speed traps; speed, near misses and crashes in their sight bring a chase"))
	if e.sub == "run":
		var runs := _runs(data)
		if runs.is_empty():
			page.add_text("This track has no runs.", true)
		else:
			if not runs.any(func(r: Array) -> bool: return r[0] == e.run):
				e.run = String(runs[0][0])
			page.add_row(UiKit.spinner("Run", runs, e.run, func(v: String) -> void: e.run = v, "Which stretch"))
	else:
		var ways := [[1, _way(data, 1)], [-1, _way(data, -1)], [0, "Both ways"]]
		page.add_row(UiKit.spinner("Way round", ways, e.direction, func(v: int) -> void: e.direction = v,
			"Which carriageway you start on; both ways: players take turns"))


## [[id, "Name · 2.1 km, clockwise"]] for the highway's runs.
static func _runs(data: TrackData) -> Array:
	var out := []
	if data == null or data.highway == null:
		return out
	for r: Dictionary in data.highway.runs:
		var length := fposmod(int(r.dir) * (float(r.to_m) - float(r.from_m)), data.length)
		out.append([String(r.id), "%s · %.1f km, %s" % [r.name, length / 1000.0, _way(data, int(r.dir)).to_lower()]])
	return out


static func _way(data: TrackData, dir: int) -> String:
	if data == null or data.highway == null:
		return "This way" if dir > 0 else "The other way"
	return "Clockwise" if data.highway.clockwise(dir) else "Anticlockwise"


## Sumo Wrestling (D162): the platforms, what's under them and how they shrink, the AI cars.
static func sumo(page: EventSettingsPage) -> void:
	var e := page.flow.event
	page.add_row(UiKit.spinner("Platforms", TIERS, clampi(e.sumo_tiers, 1, TIERS.size()), func(v: int) -> void:
		e.sumo_tiers = v, "Stacked, each wider than the one above: a fall is a second chance"))
	page.add_row(UiKit.spinner("Underneath", HAZARDS, e.sumo_hazard, func(v: String) -> void:
		e.sumo_hazard = v, "Touch it and you're out"))
	page.add_row(UiKit.spinner("Shrink", SHRINKS, e.sumo_shrink, func(v: String) -> void:
		e.sumo_shrink = v, "Smooth: the edge creeps in. Crumbling or Stepped: a ring at a time"))
	e.sumo_secs = nearest(SUMO_LENGTHS, e.sumo_secs)
	page.add_row(UiKit.spinner("Length", SUMO_LENGTHS, e.sumo_secs, func(v: int) -> void:
		e.sumo_secs = v, "How long one platform takes to shrink away"))
	page.add_row(UiKit.spinner("Sudden death", OFF, e.sumo_pillar, func(v: bool) -> void:
		e.sumo_pillar = v, "The last platform stops at a pillar instead of going altogether"))
	page.add_row(UiKit.spinner("Drift", DRIFTS, e.sumo_drift, func(v: String) -> void:
		e.sumo_drift = v, "Hop and slide like a kart; boost rewards a long drift"))
	ai_rows(page, "AI cars", 11)
	page.add_row(UiKit.spinner("AI models", [["garage", "Garage"], ["builtin", "Built-in"]], e.ai_cars, func(v: String) -> void:
		e.ai_cars = v, "Garage: bots bring your own cars too"))


## Drag Strip (D168): the strip's length, the bottles, which of its rules are on, the field. The
## class is the next step.
static func drag(page: EventSettingsPage) -> void:
	var e := page.flow.event
	var imperial := String(Settings.units) == "imperial"
	e.drag_length_m = nearest(DRAG_LENGTHS, e.drag_length_m)
	page.add_row(UiKit.spinner("Length", DRAG_LENGTHS.map(func(l: Array) -> Array: return [l[0], l[1] if imperial else l[2]]),
		e.drag_length_m, func(v: int) -> void: e.drag_length_m = v, "Start line to the lights; the shutdown is as long again"))
	page.add_row(UiKit.spinner("Boost", BOOSTS, clampi(e.drag_boost, 0, 3), func(v: int) -> void:
		e.drag_boost = v, "Bottles each driver gets, spent whenever they like"))
	page.add_row(UiKit.spinner("Timing shifts", ON, e.drag_timing, func(v: bool) -> void:
		e.drag_timing = v, "Shift in the window on the tach for a surge, miss it and bog"))
	page.add_row(UiKit.spinner("Quick time events", ON, e.drag_qtes, func(v: bool) -> void:
		e.drag_qtes = v, "The burnout, the two-step and catching a shake"))
	page.add_heading("Gimmicks")
	page.add_row(UiKit.spinner("Christmas tree", ON, e.drag_tree, func(v: bool) -> void:
		e.drag_tree = v, "Stage, three ambers, green: your reaction is timed, and leaving early is a red light"))
	page.add_row(UiKit.spinner("Two-step", ON, e.drag_two_step, func(v: bool) -> void:
		e.drag_two_step = v, "Hold the revs in the band on the line, and launch as the light goes green"))
	page.add_row(UiKit.spinner("Burnout", ON, e.drag_burnout, func(v: bool) -> void:
		e.drag_burnout = v, "Heat the tires before the pass; cook them and you lose the grip"))
	page.add_row(UiKit.spinner("Tire shake", ON, e.drag_shake, func(v: bool) -> void:
		e.drag_shake = v, "A spinning launch opens a moment to feather it"))
	page.add_row(UiKit.spinner("Shift chain", ON, e.drag_chain, func(v: bool) -> void:
		e.drag_chain = v, "Perfect shifts in a row build the surge; a bad one breaks it"))
	page.add_row(UiKit.spinner("Money shift", ON, e.drag_money_shift, func(v: bool) -> void:
		e.drag_money_shift = v, "Sitting on the limiter loses power, and in the end the engine"))
	page.add_row(UiKit.spinner("Centreline", [[true, "Foul"], [false, "Forgiving"]], e.drag_centreline, func(v: bool) -> void:
		e.drag_centreline = v, "Foul: cross it and the pass is lost"))
	page.add_heading("Field")
	ai_rows(page, "AI cars", 15, "The ladder draws everyone into pairs; two run each pass")
	page.add_row(UiKit.spinner("AI models", [["garage", "Garage"], ["builtin", "Built-in"]], e.ai_cars, func(v: String) -> void:
		e.ai_cars = v, "Garage: bots bring your own cars too"))


## Free Drive: any circuit or highway. On a circuit AI cars can drive laps beside the players; on a
## highway its traffic is on or off.
static func free_drive(page: EventSettingsPage) -> void:
	var flow := page.flow
	var e := flow.event
	var was := flow.on_highway()
	page.add_row(track_row(page, "Track", func(_path: String) -> void:
		if flow.on_highway() != was:
			page.rebuild.call_deferred("Track")))
	if was:
		page.add_row(UiKit.spinner("Traffic", [[-1, "On"], [0, "Off"]], 0 if e.traffic == 0 else -1,
			func(v: int) -> void: e.traffic = v, "Cars on the road"))
		return
	var counts := numbers(0, 15)
	counts[0] = [0, "Off"]
	page.add_row(UiKit.spinner("AI cars", counts, e.ai_count, func(v: int) -> void: e.ai_count = v, "They drive laps with you"))
	page.add_row(skill_row(e))
	page.add_row(UiKit.spinner("AI cars look", [["garage", "Garage"], ["builtin", "Built-in"]], e.ai_cars,
		func(v: String) -> void: e.ai_cars = v))
	page.add_row(UiKit.spinner("Collisions", [[true, "On"], [false, "Ghosted"]], e.collisions,
		func(v: bool) -> void: e.collisions = v))
	page.add_row(UiKit.spinner("Track limits", [["off", "Off"], ["lenient", "Lenient"], ["strict", "Strict"]], e.track_limits,
		func(v: String) -> void: e.track_limits = v, "Cutting the track spoils a timed lap"))


## [minutes, "5 min"] for each of `values` ("Off" for 0), with `current` added if it's not there.
static func minutes(values: Array, current: int) -> Array:
	var list := values.duplicate()
	if current not in list:
		list.append(current)
		list.sort()
	return list.map(func(m: int) -> Array: return [m, "Off" if m == 0 else "%d min" % m])


## [n, "n"] from `from` to `to`.
static func numbers(from: int, to: int) -> Array:
	var out := []
	for n in range(from, to + 1):
		out.append([n, "%d" % n])
	return out


## The value of `items` ([value, ...]) nearest `value`, so an older setup still lands on a row.
static func nearest(items: Array, value: int) -> int:
	var best: int = items[0][0]
	for i: Array in items:
		if absi(int(i[0]) - value) < absi(best - value):
			best = int(i[0])
	return best
