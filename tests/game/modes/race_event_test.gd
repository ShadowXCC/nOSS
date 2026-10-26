extends GdUnitTestSuite
## Track-suggested rules (D207): an event's start, drafting, fuel use and tire wear keep "Track's"
## or are its own; resolved against a track they take its `rules` (none: as tracks always raced);
## older saved setups move to "Track's" once; Custom's page shows the track's choice.

const DIR := "user://tests/race_event"
const OVAL := "res://content/tracks/piedmont_speedway"
const PLAIN := "res://content/tracks/proving_ground"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Settings.race_event = {}
	Settings.profile.last_track = ""
	Settings.use_folder("user://")


func test_the_rules_round_trip_and_clamp() -> void:
	var e := RaceEvent.new()
	e.kind = "race"
	assert_str(e.start).is_equal("track")
	assert_str(e.draft).is_equal("track")
	assert_int(e.fuel_x).is_equal(-1)
	e.start = "rolling"
	e.draft = "on"
	e.fuel_x = 7
	e.tyre_x = 0
	var back := RaceEvent.from_dict(e.to_dict())
	assert_str(back.start).is_equal("rolling")
	assert_str(back.draft).is_equal("on")
	assert_int(back.fuel_x).is_equal(7)
	assert_int(back.tyre_x).is_equal(0)
	var wild := RaceEvent.from_dict({ "kind": "race", "draft": "maybe", "fuel_x": 99, "tyre_x": -8, "start": "flying" })
	assert_str(wild.draft).is_equal("track")
	assert_int(wild.fuel_x).is_equal(RaceEvent.WEAR_X_MAX)
	assert_int(wild.tyre_x).is_equal(-1)
	assert_str(wild.start).is_equal("track")
	# Only circuit events carry them.
	assert_bool(RaceEvent.highway().to_dict().has("draft")).is_false()


func test_track_rules_resolve_the_track_choices() -> void:
	var oval := TrackLoader.load_package(OVAL).track
	var plain := TrackLoader.load_package(PLAIN).track
	var e := RaceEvent.new()
	e.kind = "race"
	var on_oval := e.resolved(oval)
	assert_str(on_oval.start).is_equal("rolling")
	assert_str(on_oval.draft).is_equal("on")
	assert_int(on_oval.fuel_x).is_equal(5)
	assert_int(on_oval.tyre_x).is_equal(5)
	assert_bool(on_oval.pack).is_true()
	# A track without rules races as tracks always have.
	var on_plain := e.resolved(plain)
	assert_str(on_plain.start).is_equal("standing")
	assert_str(on_plain.draft).is_equal("off")
	assert_int(on_plain.fuel_x).is_equal(0)
	assert_int(on_plain.tyre_x).is_equal(0)
	assert_bool(on_plain.pack).is_false()
	# The event's own choices stand; the event itself keeps "Track's".
	e.start = "standing"
	e.draft = "off"
	e.fuel_x = 2
	var own := e.resolved(oval)
	assert_str(own.start).is_equal("standing")
	assert_str(own.draft).is_equal("off")
	assert_int(own.fuel_x).is_equal(2)
	assert_int(own.tyre_x).is_equal(5)
	assert_bool(own.pack).is_false() # no packs without drafting
	assert_int(e.tyre_x).is_equal(-1)


func test_an_older_setup_moves_to_the_tracks_start_once() -> void:
	Settings.race_event = { "kind": "race", "race_laps": 3, "start": "standing" }
	assert_str(Settings.last_event().start).is_equal("track")
	var picked := RaceEvent.new()
	picked.kind = "race"
	picked.start = "standing"
	Settings.set_last_event(picked)
	assert_str(Settings.last_event().start).is_equal("standing") # chosen since: kept


## Custom's Settings page (docs/UI_FLOW.md §6.1) shows the track's own choice beside "Track's",
## and another track brings its own.
func test_the_custom_page_shows_the_tracks_choices() -> void:
	Settings.race_event = {}
	Settings.profile.event_memory = {}
	Settings.profile.last_track = PLAIN
	var flow := EventFlow.racing("custom")
	flow.recall()
	var holder := Control.new()
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var stack := MenuStack.new()
	holder.add_child(stack)
	var page := EventSettingsPage.new()
	page.flow = flow
	stack.push(page)
	await get_tree().process_frame
	var names := func() -> Array:
		return page.body.get_children().map(func(c: Control) -> String:
			var t := UiKit._focus_target(c)
			return String(t.accessibility_name) if t else "")
	for row in ["Start: Track's (Standing)", "Drafting: Track's (Off)", "Fuel use: Track's (Off)", "Tire wear: Track's (Off)"]:
		assert_bool((names.call() as Array).any(func(n: String) -> bool: return n.begins_with(row))).override_failure_message(row).is_true()
	# Another track: its choices.
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	for i in 12:
		if flow.track == OVAL:
			break
		page.row_named("Track").gui_input.emit(right)
		await get_tree().process_frame
	assert_str(flow.track).is_equal(OVAL)
	await get_tree().process_frame
	for row in ["Start: Track's (Rolling)", "Drafting: Track's (On)", "Fuel use: Track's (5x)", "Tire wear: Track's (5x)"]:
		assert_bool((names.call() as Array).any(func(n: String) -> bool: return n.begins_with(row))).override_failure_message(row).is_true()
	holder.free()