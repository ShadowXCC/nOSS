extends GdUnitTestSuite
## The event pages' flow (docs/UI_FLOW.md §5, §6): the steps and crumbs of each type, the tracks
## and classes it offers, its memory (and the old menus' keys before it has any), Drive again's
## event, and the start.

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/event_flow")
	Game.hold_events = true
	Game.event_requested.connect(_on_event)


func after() -> void:
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	Game.flow_return = {}
	Settings.use_folder("user://")


func before_test() -> void:
	_requested.clear()
	for key in ["event_memory", "last_drive", "last_track", "last_platform"]:
		Settings.profile[key] = PlayerProfile.DEFAULTS[key].duplicate(true) if PlayerProfile.DEFAULTS[key] is Dictionary else PlayerProfile.DEFAULTS[key]
	Settings.race_event = {}


func _on_event(e: RaceEvent, platform_id: String) -> void:
	_requested.append([e, platform_id])


func test_steps_and_crumbs() -> void:
	var regular := EventFlow.racing("regular")
	assert_array(Array(regular.steps())).contains_exactly(["Event", "Settings", "Class", "Players"])
	assert_array(Array(regular.crumbs("Settings"))).contains_exactly(["Local Drive", "Racing", "Regular", "Settings"])
	assert_str(regular.name()).is_equal("Regular race")
	# Stock Car's class is fixed: no Class step.
	var stock := EventFlow.racing("stock_car")
	assert_array(Array(stock.steps())).contains_exactly(["Event", "Settings", "Players"])
	assert_bool(stock.has_class_step()).is_false()
	assert_str(stock.name()).is_equal("Stock Car race")
	# Time trials: P1 drives until P6 brings their Players step.
	var tt := EventFlow.racing("regular", true)
	assert_array(Array(tt.steps())).contains_exactly(["Event", "Settings", "Class"])
	assert_array(Array(tt.crumbs("Class"))).contains_exactly(["Local Drive", "Racing", "Regular Time Trial", "Class"])
	assert_str(tt.name()).is_equal("Regular time trial")
	assert_array(Array(EventFlow.racing("stock_car", true).steps())).contains_exactly(["Event", "Settings"])
	# Karts pick their class on their cards; hosting starts at Host and ends at the lobby.
	assert_array(Array(EventFlow.steps_for("local", "racing", "kart", false))).contains_exactly(["Event", "Settings", "Players"])
	assert_array(Array(EventFlow.steps_for("host", "racing", "regular", false))).contains_exactly(["Host", "Event", "Settings", "Class", "Lobby"])
	assert_array(Array(EventFlow.steps_for("change", "racing", "stock_car", false))).contains_exactly(["Event", "Settings", "Lobby"])
	var host := EventFlow.racing("regular", false, "host")
	assert_array(Array(host.crumbs("Settings"))).contains_exactly(["Drive Online", "Host", "Racing", "Regular", "Settings"])


## Regular lists every circuit (ovals, kart and real-world tracks too), Stock Car only ovals, and
## neither a highway or an arena.
func test_tracks_and_classes_of_each_type() -> void:
	var regular := EventFlow.racing("regular")
	var paths := regular.tracks().map(func(e: Dictionary) -> String: return e.path)
	for id in ["proving_ground", "piedmont_speedway", "gearworks", "eifel_gp"]:
		assert_array(paths).contains([TrackLibrary.BUILTIN_DIR + id])
	for id in ["lumen_ring", "crate_yard"]:
		assert_array(paths).not_contains([TrackLibrary.BUILTIN_DIR + id])
	var ovals := EventFlow.racing("stock_car").tracks()
	assert_bool(ovals.is_empty()).is_false()
	for e in ovals:
		assert_array(e.tags).contains(["oval"])
	var ids := regular.classes().map(func(r: PlatformLoader.Result) -> String: return r.platform.id)
	assert_array(ids).contains(["official.track.gt", "official.track.formula"])
	assert_bool(ids.all(func(id: String) -> bool: return id.begins_with("official.track."))).is_true()
	assert_str(EventFlow.racing("stock_car").fixed_class()).is_equal(EventFlow.STOCK_CAR)


## A new setup: Regular 5 laps and 7 AI cars, Stock Car 10 and 11 on an oval, in Stock Car.
func test_defaults() -> void:
	var regular := EventFlow.racing("regular")
	regular.recall()
	assert_str(regular.event.kind).is_equal("race")
	assert_int(regular.event.race_laps).is_equal(5)
	assert_int(regular.event.ai_count).is_equal(7)
	assert_str(regular.class_id).is_equal("official.track.gt")
	assert_str(regular.track).is_equal(TrackLibrary.DEFAULT)
	var stock := EventFlow.racing("stock_car")
	stock.recall()
	assert_int(stock.event.race_laps).is_equal(10)
	assert_int(stock.event.ai_count).is_equal(11)
	assert_str(stock.class_id).is_equal(EventFlow.STOCK_CAR)
	assert_array(TrackLibrary.entry(stock.track).tags).contains(["oval"])
	var tt := EventFlow.racing("regular", true)
	tt.recall()
	assert_str(tt.event.kind).is_equal("time_trial")
	assert_int(tt.event.ai_count).is_zero()


## Before a type has its own memory it reads the old menus' keys (docs/UI_FLOW.md §5.8):
## Settings.race_event, last_track and last_platform. What it has no rows for goes back to the
## plain defaults (Regular runs the track's rules).
func test_falls_back_to_the_old_keys() -> void:
	var old := RaceEvent.new()
	old.kind = "race"
	old.race_laps = 12
	old.ai_count = 4
	old.practice_min = 10
	old.grid = "reverse"
	old.track_limits = "strict"
	old.draft = "on"
	old.race_min = 20
	Settings.race_event = old.to_dict()
	Settings.profile.last_track = TrackLibrary.BUILTIN_DIR + "eifel_gp"
	Settings.profile.last_platform = "official.track.formula"
	var regular := EventFlow.racing("regular")
	regular.recall()
	assert_int(regular.event.race_laps).is_equal(12)
	assert_int(regular.event.ai_count).is_equal(4)
	assert_int(regular.event.practice_min).is_equal(10)
	assert_int(regular.event.race_min).is_zero() # Regular races laps
	assert_str(regular.event.grid).is_equal("qualifying")
	assert_str(regular.event.track_limits).is_equal("lenient")
	assert_str(regular.event.draft).is_equal("track")
	assert_str(regular.track).is_equal(TrackLibrary.BUILTIN_DIR + "eifel_gp")
	assert_str(regular.class_id).is_equal("official.track.formula")
	# Stock Car reads the race too, but keeps to an oval and its own class.
	var stock := EventFlow.racing("stock_car")
	stock.recall()
	assert_int(stock.event.race_laps).is_equal(12)
	assert_array(TrackLibrary.entry(stock.track).tags).contains(["oval"])
	assert_str(stock.class_id).is_equal(EventFlow.STOCK_CAR)
	# Once it has its own memory, that wins; and nothing writes the old keys.
	regular.event.race_laps = 3
	regular.remember()
	var again := EventFlow.racing("regular")
	again.recall()
	assert_int(again.event.race_laps).is_equal(3)
	assert_int(int(Settings.race_event.race_laps)).is_equal(12)
	assert_str(String(Settings.profile.last_platform)).is_equal("official.track.formula")
	# Each type has its own: Stock Car's isn't Regular's.
	var stock_again := EventFlow.racing("stock_car")
	stock_again.recall()
	assert_int(stock_again.event.race_laps).is_equal(12)
	assert_array(Settings.profile.event_memory.keys()).contains_exactly(["racing/regular"])


## Starting remembers the setup, keeps it for Drive again and the results' Event menu, and asks
## for the event; another start (an old menu, a dev flag) leaves no Event menu behind.
func test_start_remembers_for_drive_again() -> void:
	var flow := EventFlow.racing("stock_car")
	flow.recall()
	flow.event.race_laps = 20
	flow.start()
	assert_int(_requested.size()).is_equal(1)
	assert_str((_requested[0][0] as RaceEvent).kind).is_equal("race")
	assert_int((_requested[0][0] as RaceEvent).race_laps).is_equal(20)
	assert_str(String(_requested[0][1])).is_equal(EventFlow.STOCK_CAR)
	assert_str(String(Game.flow_return.variant)).is_equal("stock_car")
	var again := EventFlow.last_drive()
	assert_object(again).is_not_null()
	assert_str(again.variant).is_equal("stock_car")
	assert_int(again.event.race_laps).is_equal(20)
	assert_str(again.track).is_equal(flow.track)
	assert_str(again.summary()).is_equal("Stock Car race · Piedmont Speedway · Stock Car")
	Game.start_event(RaceEvent.time_trial(), "official.track.gt")
	assert_bool(Game.flow_return.is_empty()).is_true()


## Drive again is only offered while its track and class are still here.
func test_drive_again_needs_its_track_and_class() -> void:
	assert_object(EventFlow.last_drive()).is_null()
	var flow := EventFlow.racing("regular")
	flow.recall()
	var data := flow.to_dict()
	Settings.profile.last_drive = data
	assert_object(EventFlow.last_drive()).is_not_null()
	data.track = "res://content/tracks/no_such_track"
	Settings.profile.last_drive = data
	assert_object(EventFlow.last_drive()).is_null()
	data = flow.to_dict()
	data.class_id = "official.track.no_such_class"
	Settings.profile.last_drive = data
	assert_object(EventFlow.last_drive()).is_null()


## The setup survives a round trip through the profile's file.
func test_memory_is_saved_with_the_profile() -> void:
	var flow := EventFlow.racing("regular", true)
	flow.recall()
	flow.event.weather = "rain"
	flow.track = TrackLibrary.BUILTIN_DIR + "gearworks"
	flow.remember()
	var loaded := PlayerProfile.load_id(Settings.primary.id)
	var saved: Dictionary = loaded.data.event_memory["racing/regular/tt"]
	assert_str(String(saved.track)).is_equal(TrackLibrary.BUILTIN_DIR + "gearworks")
	assert_str(String(saved.event.weather)).is_equal("rain")
	assert_str(String(saved.event.kind)).is_equal("time_trial")
