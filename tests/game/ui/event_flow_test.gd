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
	Game.cup = null
	Settings.use_folder("user://")


func before_test() -> void:
	_requested.clear()
	for key in ["event_memory", "last_drive", "last_track", "last_platform", "last_highway", "last_endless"]:
		Settings.profile[key] = PlayerProfile.DEFAULTS[key].duplicate(true) if PlayerProfile.DEFAULTS[key] is Dictionary else PlayerProfile.DEFAULTS[key]
	for key in ["last_kart", "last_kart_platform", "last_sumo", "last_drag", "last_drag_class", "last_free"]:
		Settings.profile.erase(key)
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
	# Time trials have the race's steps, splitscreen players and all.
	var tt := EventFlow.racing("regular", true)
	assert_array(Array(tt.steps())).contains_exactly(["Event", "Settings", "Class", "Players"])
	assert_array(Array(tt.crumbs("Class"))).contains_exactly(["Local Drive", "Racing", "Regular Time Trial", "Class"])
	assert_str(tt.name()).is_equal("Regular time trial")
	assert_array(Array(EventFlow.racing("stock_car", true).steps())).contains_exactly(["Event", "Settings", "Players"])
	assert_str(EventFlow.racing("stock_car", true).next_hint()).is_equal("The players: each picks a car")
	var kart_tt := EventFlow.racing("kart", true)
	assert_array(Array(kart_tt.steps())).contains_exactly(["Event", "Settings", "Players"])
	assert_str(kart_tt.next_hint()).is_equal("The players: each picks a car and a class")
	assert_str(kart_tt.name()).is_equal("Kart time trial")
	# Karts pick their class on their cards; hosting starts at Host and ends at the lobby.
	assert_array(Array(EventFlow.steps_for("local", "racing", "kart"))).contains_exactly(["Event", "Settings", "Players"])
	assert_array(Array(EventFlow.steps_for("host", "racing", "regular"))).contains_exactly(["Host", "Event", "Settings", "Class", "Lobby"])
	assert_array(Array(EventFlow.steps_for("change", "racing", "stock_car"))).contains_exactly(["Event", "Settings", "Lobby"])
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


## Every other type's steps, crumbs and names (docs/UI_FLOW.md §6).
func test_the_other_types_steps_and_crumbs() -> void:
	var want := {
		"endless": [["endless", ""], "Endless", ["Event", "Settings", "Class", "Players"], ["Local Drive", "Endless", "Settings"]],
		"highway": [["highway", ""], "Highway", ["Event", "Settings", "Class", "Players"], ["Local Drive", "Highway", "Settings"]],
		"free": [["free", ""], "Free Drive", ["Event", "Settings", "Class", "Players"], ["Local Drive", "Free Drive", "Settings"]],
		"sumo": [["mini", "sumo"], "Sumo Wrestling", ["Event", "Settings", "Players"], ["Local Drive", "Mini Games", "Sumo Wrestling", "Settings"]],
		"drag": [["mini", "drag"], "Drag Strip", ["Event", "Settings", "Class", "Players"], ["Local Drive", "Mini Games", "Drag Strip", "Settings"]],
		"battle": [["mini", "kart_battle"], "Kart Battle", ["Event", "Settings", "Players"], ["Local Drive", "Mini Games", "Kart Battle", "Settings"]],
		"kart": [["racing", "kart"], "Kart race", ["Event", "Settings", "Players"], ["Local Drive", "Racing", "Kart", "Settings"]],
		"custom": [["racing", "custom"], "Custom race", ["Event", "Settings", "Class", "Players"], ["Local Drive", "Racing", "Custom", "Settings"]],
	}
	for key: String in want:
		var w: Array = want[key]
		var f := EventFlow.make(w[0][0], w[0][1])
		assert_str(f.name()).override_failure_message(key).is_equal(w[1])
		assert_array(Array(f.steps())).override_failure_message(key).contains_exactly(w[2])
		assert_array(Array(f.crumbs("Settings"))).override_failure_message(key).contains_exactly(w[3])
	var cup := EventFlow.racing("kart")
	cup.cup = CupRun.BUILTIN_DIR + "spark_cup.cup.json"
	assert_str(cup.name()).is_equal("Kart cup")
	assert_str(EventFlow.racing("custom", true).name()).is_equal("Custom time trial")
	assert_str(EventFlow.make("mini", "sumo").fixed_class()).is_equal(EventFlow.SUMO)
	assert_str(EventFlow.make("mini", "drag").memory_key()).is_equal("mini/drag")


## Kart lists the kart tracks first, Kart Battle the arenas, Highway the highways, Free Drive the
## circuits and the highways; none of them an arena but Kart Battle.
func test_the_other_types_tracks() -> void:
	var kart := EventFlow.racing("kart").tracks()
	var tagged := kart.map(func(e: Dictionary) -> bool: return "kart" in e.tags or "stunt" in e.tags)
	assert_bool(tagged[0]).is_true()
	assert_int(tagged.find(false)).is_greater(0)
	assert_bool(tagged.slice(tagged.find(false)).has(true)).is_false() # every kart track before the rest
	assert_int(kart.size()).is_equal(EventFlow.racing("regular").tracks().size())
	assert_bool(EventFlow.make("mini", "kart_battle").tracks().all(func(e: Dictionary) -> bool: return e.type == "arena")).is_true()
	assert_bool(EventFlow.make("highway").tracks().all(func(e: Dictionary) -> bool: return e.type == "highway")).is_true()
	var free := EventFlow.make("free").tracks().map(func(e: Dictionary) -> String: return e.type)
	assert_array(free).contains(["circuit", "highway"])
	assert_array(free).not_contains(["arena"])
	assert_bool(EventFlow.make("endless").has_track()).is_false()
	assert_bool(EventFlow.make("mini", "sumo").has_track()).is_false()
	# A new Kart setup starts on a kart track.
	var k := EventFlow.racing("kart")
	k.recall()
	assert_array(TrackLibrary.entry(k.track).tags).contains(["kart"])


## Custom offers every mode's classes; Endless, Highway and Drag Strip their own; Free Drive every
## mode's, but on a highway not Drag's (no automatic gearbox: the highway's autodrive can't drive
## them).
func test_the_other_types_classes() -> void:
	var modes := func(f: EventFlow) -> Array:
		var out := []
		for r in f.classes():
			var m := String(GameModes.mode_for(r.platform.id).id)
			if m not in out:
				out.append(m)
		return out
	assert_array(modes.call(EventFlow.racing("custom"))).contains_exactly(["track", "kart", "highway", "endless", "sumo", "drag"])
	assert_array(modes.call(EventFlow.make("endless"))).contains_exactly(["endless"])
	assert_array(modes.call(EventFlow.make("highway"))).contains_exactly(["highway"])
	assert_array(modes.call(EventFlow.make("mini", "drag"))).contains_exactly(["drag"])
	var free := EventFlow.make("free")
	free.track = TrackLibrary.DEFAULT
	assert_array(modes.call(free)).contains(["drag"])
	free.track = TrackLibrary.BUILTIN_DIR + "lumen_ring"
	assert_array(modes.call(free)).contains_exactly(["track", "kart", "highway", "endless", "sumo"])
	# Kart events pick per card, starting from Medium.
	var battle := EventFlow.make("mini", "kart_battle")
	battle.recall()
	assert_str(battle.class_id).is_equal(EventFlow.KART)
	assert_str(battle.event.kind).is_equal("battle")


## Before they have their own memory, the types read the old menus' keys.
func test_the_other_types_fall_back_to_the_old_keys() -> void:
	var race := RaceEvent.new()
	race.race_laps = 6
	race.ai_count = 4
	var battle := RaceEvent.battle("hits", 7)
	var cup_path := CupRun.BUILTIN_DIR + "spark_cup.cup.json"
	Settings.profile.last_kart = { "kind": "cup", "event": race.to_dict(), "track": "gearworks", "arena": "dust_bowl", "cup": cup_path }
	Settings.profile.last_kart_platform = "official.kart.light"
	var kart := EventFlow.racing("kart")
	kart.recall()
	assert_str(kart.cup).is_equal(cup_path)
	assert_int(kart.event.race_laps).is_equal(6)
	assert_int(kart.event.ai_count).is_equal(4)
	assert_str(kart.class_id).is_equal("official.kart.light")
	Settings.profile.last_kart = { "kind": "battle", "event": battle.to_dict(), "track": "gearworks", "arena": "dust_bowl", "cup": "" }
	var arena := EventFlow.make("mini", "kart_battle")
	arena.recall()
	assert_str(arena.event.battle_rule).is_equal("hits")
	assert_int(arena.event.battle_min).is_equal(7)
	assert_str(arena.track).is_equal(TrackLibrary.BUILTIN_DIR + "dust_bowl")
	var road := RaceEvent.endless(1234, 2)
	road.lanes = 4
	Settings.profile.last_endless = road.to_dict()
	var endless := EventFlow.make("endless")
	endless.recall()
	assert_int(endless.event.road_seed).is_equal(1234)
	assert_int(endless.event.lanes).is_equal(4)
	var cruise := RaceEvent.highway("loop", true, 250)
	Settings.profile.last_highway = cruise.to_dict()
	var highway := EventFlow.make("highway")
	highway.recall()
	assert_str(highway.event.sub).is_equal("loop")
	assert_int(highway.event.traffic).is_equal(250)
	assert_str(highway.track).is_equal(TrackLibrary.BUILTIN_DIR + "lumen_ring")
	Settings.profile.last_sumo = RaceEvent.sumo(4, "acid").to_dict()
	var sumo := EventFlow.make("mini", "sumo")
	sumo.recall()
	assert_int(sumo.event.sumo_tiers).is_equal(4)
	assert_str(sumo.event.sumo_hazard).is_equal("acid")
	var free := RaceEvent.free_drive()
	free.ai_count = 3
	Settings.profile.last_free = free.to_dict()
	Settings.profile.last_platform = "official.highway.super"
	var drive := EventFlow.make("free")
	drive.recall()
	assert_int(drive.event.ai_count).is_equal(3)
	assert_str(drive.class_id).is_equal("official.highway.super")


## Each type starts its own way: a cup's first race, Free Drive (a Cruise on a highway), Sumo in
## its class, an endless road with no track.
func test_the_other_types_start() -> void:
	var cup := EventFlow.racing("kart")
	cup.recall()
	cup.cup = CupRun.BUILTIN_DIR + "spark_cup.cup.json"
	cup.start()
	assert_object(Game.cup).is_not_null()
	assert_str(String((Game.cup as CupRun).cup.id)).is_equal("spark_cup")
	assert_str(String(Game.flow_return.variant)).is_equal("kart")
	Game.cup = null
	var free := EventFlow.make("free")
	free.recall()
	free.class_id = "official.track.gt"
	free.start()
	assert_str((_requested[-1][0] as RaceEvent).kind).is_equal("free")
	free.track = TrackLibrary.BUILTIN_DIR + "lumen_ring"
	free.event.traffic = 0
	free.start()
	assert_str((_requested[-1][0] as RaceEvent).kind).is_equal("highway")
	assert_int((_requested[-1][0] as RaceEvent).traffic).is_zero()
	var sumo := EventFlow.make("mini", "sumo")
	sumo.recall()
	sumo.start()
	assert_str((_requested[-1][0] as RaceEvent).kind).is_equal("sumo")
	assert_str(String(_requested[-1][1])).is_equal(EventFlow.SUMO)
	var endless := EventFlow.make("endless")
	endless.recall()
	endless.start()
	assert_str((_requested[-1][0] as RaceEvent).kind).is_equal("endless")
	assert_str(String(_requested[-1][1])).starts_with("official.endless.")
	# Drive again offers it, and says what it is.
	var again := EventFlow.last_drive()
	assert_object(again).is_not_null()
	assert_str(again.summary()).starts_with("Endless · ")
	assert_str(EventFlow.from_dict(cup.to_dict()).summary()).is_equal("Kart cup · Spark Cup")
	# Kart's time trial: a kart track first, Medium to start from (each player picks theirs), and
	# Drive again knows it.
	var kart_tt := EventFlow.racing("kart", true)
	kart_tt.recall()
	assert_bool(kart_tt.known()).is_true()
	assert_str(kart_tt.event.kind).is_equal("time_trial")
	assert_str(kart_tt.class_id).is_equal(EventFlow.KART)
	assert_bool(EventFlow._for_karts(TrackLibrary.entry(kart_tt.track))).is_true()
	kart_tt.start()
	assert_str((_requested[-1][0] as RaceEvent).kind).is_equal("time_trial")
	assert_str(String(_requested[-1][1])).is_equal(EventFlow.KART)
	assert_str(EventFlow.last_drive().summary()).starts_with("Kart time trial · ")
