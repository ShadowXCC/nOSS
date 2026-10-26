extends GdUnitTestSuite
## The Track rows of the Settings pages (EDT-07, docs/UI_FLOW.md §5.5): the built-in and the
## player's own tracks, labelled, the pane showing the one picked; circuits and highways listed
## apart, and Free Drive offering both.

const DIR := "user://tests/track_picker"

var _holder: Control


func before() -> void:
	Settings.use_folder(DIR)
	var files := TrackPackageTest.terrain_track()
	var r := TrackWriter.write(TrackLibrary.user_dir.path_join("hills.nosstrack"), { "name": "Hills", "author": "Tester", "license": "CC0-1.0" }, files)
	assert_str(String(r.error)).is_empty()


func after() -> void:
	DirAccess.remove_absolute(TrackLibrary.user_dir.path_join("hills.nosstrack"))
	DirAccess.remove_absolute(TrackLibrary.user_dir.path_join("ring.nosstrack"))
	Settings.use_folder("user://")


func before_test() -> void:
	Settings.profile.event_memory = {}
	Settings.profile.last_track = ""


func after_test() -> void:
	if is_instance_valid(_holder):
		_holder.free()


func _page(flow: EventFlow) -> EventSettingsPage:
	_holder = Control.new()
	_holder.size = Vector2(1920, 1080)
	add_child(_holder)
	var stack := MenuStack.new()
	_holder.add_child(stack)
	flow.recall()
	var page := EventSettingsPage.new()
	page.flow = flow
	stack.push(page)
	return page


func _right(b: Control) -> void:
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	b.gui_input.emit(right)


## Regular's Track row: the built-in circuits (the kart ones too), then the player's own, which
## the pane shows (its map, "Your track") once picked.
func test_both_tracks_are_offered_and_the_pane_follows() -> void:
	var flow := EventFlow.racing("regular")
	var labels := flow.tracks().map(func(e: Dictionary) -> String: return TrackLibrary.label(e))
	var builtin := TrackLibrary.list(false, false, "circuit").size()
	assert_bool(labels.slice(0, builtin).any(func(n: String) -> bool: return n.begins_with("Proving Ground · 2.5 km"))).is_true()
	assert_str(String(labels[builtin])).starts_with("Hills · 1.")
	assert_str(String(labels[builtin])).ends_with("Tester")
	var page := _page(flow)
	await get_tree().process_frame
	var row := page.row_named("Track")
	assert_str(String(row.accessibility_name)).starts_with("Track: Proving Ground")
	for i in 12: # on past the built-in ones to the player's own
		if flow.track.ends_with("hills.nosstrack"):
			break
		_right(row)
	assert_str(flow.track).ends_with("hills.nosstrack")
	assert_str(String(row.accessibility_name)).starts_with("Track: Hills")
	assert_str(page.pane.path).is_equal(flow.track)
	assert_object(page.pane.map.track).is_not_null()
	assert_str(page.pane.text()).contains("Your track")


## Highway lists only highways (the built-in Lumen Ring, then the player's), Regular only circuits,
## Free Drive both (the highways saying so); a circuit page never starts on a highway, even if it
## was picked last.
func test_highways_and_circuits_are_listed_apart() -> void:
	var ring: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tracks/highway_ring_small.json"))
	var files := { "track.json": JSON.stringify(ring).to_utf8_buffer() }
	var r := TrackWriter.write(TrackLibrary.user_dir.path_join("ring.nosstrack"), { "name": "Ring", "author": "Tester", "license": "CC0-1.0" }, files)
	assert_str(String(r.error)).is_empty()
	var highways := EventFlow.make("highway").tracks()
	assert_int(highways.size()).is_equal(2)
	assert_str(String(highways[0].id)).is_equal("lumen_ring")
	assert_bool(highways.all(func(e: Dictionary) -> bool: return e.type == "highway")).is_true()
	assert_bool(EventFlow.racing("regular").tracks().any(func(e: Dictionary) -> bool: return e.type == "highway")).is_false()
	var page := _page(EventFlow.make("highway"))
	await get_tree().process_frame
	assert_str(String(page.row_named("Highway").accessibility_name)).starts_with("Highway: Lumen Ring · 8.3 km")
	_right(page.row_named("Highway"))
	await get_tree().process_frame
	assert_str(String(page.row_named("Highway").accessibility_name)).starts_with("Highway: Ring · 4.4 km")
	_holder.free()
	var free := EventFlow.make("free")
	var both := free.tracks()
	assert_bool(both.any(func(e: Dictionary) -> bool: return e.type == "highway")).is_true()
	assert_bool(both.any(func(e: Dictionary) -> bool: return e.type == "circuit")).is_true()
	page = _page(free)
	await get_tree().process_frame
	for i in 20:
		if free.on_highway():
			break
		_right(page.row_named("Track"))
	assert_str(String(page.row_named("Track").accessibility_name)).ends_with("· Highway")
	# A circuit page never starts on a highway.
	Settings.profile.last_track = String(highways[1].path)
	var regular := EventFlow.racing("regular")
	regular.recall()
	assert_str(regular.track).is_equal(TrackLibrary.DEFAULT)
	var highway := EventFlow.make("highway")
	highway.recall()
	assert_str(highway.track).is_equal(String(highways[1].path))
