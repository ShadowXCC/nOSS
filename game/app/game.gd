extends Node
## Game flow (autoload "Game"): title, sessions, quitting. Also reads dev options passed
## after "--" on the command line:
##   --drive              start free-drive right away
##   --car=<path>         car package for --drive
##   --platform=<id>      platform class for --drive, e.g. official.highway.street
##   --autodrive          let the racing AI drive the players (tests, screenshots)
##   --speed-factor=<x>   highways: autodriven players go x times the lanes' limits (police checks)
##   --players=<n>        free drive (highway, time trial) with n players; the extra ones are driven by the racing AI
##   --ai=<n>             add n AI racers (no views); --ai-skill=<0-100>, --ai-builtin: built-in cars only
##   --race               start a race right away (the last race set up); --race-laps=<n>, --race-ai=<n>,
##                        --race-start=track|standing|rolling, --race-draft=track|off|on,
##                        --race-fuel=<-1-10>, --race-tyres=<-1-10> (-1: the track's; 0: off),
##                        --race-plate=track|off|light|medium|heavy
##   --quit-after-results quit when a session's results come up (timed runs, checks)
##   --auto-continue      go straight on to the next session when results come up; quit after the last
##   --voices             print the text-to-speech voices
##   --no-save            write no settings or profiles (checks that walk the menus)
##   --p1-profile=<json>  P1's options for this run, e.g. '{"assists": {"racing_line": true}}' (with --no-save)
##   --skip-first-boot    don't show the first-boot accessibility screen
##   --screen-reader      act as if a screen reader is running (with --accessibility always; checks)
##   --screens=0,0,1,1    monitor per player (multi-monitor)
##   --split=<s>          two players: stacked or side; --three=<s>: wide or map
##   --ai-car=<path>      car for the AI-driven players
##   --ai-profile=<json>  options for the AI-driven players' throwaway profiles
##   --perf               print frame, CPU, physics and per-view GPU times every second
##   --perf-log           a summary line (frame time average, p95, p99; physics; traffic cars driven)
##                        every 30 s and at exit (M7 acceptance runs)
##   --fullscreen         fullscreen for this run; --no-vsync: no vsync (measurements)
##   --pause-at=<s>       open the last player's pause menu; --pause-menu=setup or driving-settings[/<tab>]
##                        opens that over it
##   --menu=<m>           open a page from the main menu, the pages before it under it:
##                        local, racing, mini-games; an event type's Settings page: regular, stock-car, kart,
##                        custom, endless, highway, free, sumo, drag, kart-battle, with -tt for a Racing
##                        type's time trial (regular-tt) and /class or /players for the page after
##                        (regular/players; --join=<n>: n devices join there); online, host, host-event (its
##                        event types), host-<type> (hosting's Settings page, host-regular-tt), join;
##                        settings[/<tab>], driving-settings[/<tab>] (a tab: sound, vision-hearing,
##                        hud-display); access (the first-boot screen)
##   --camera=<mode>      chase_near, chase_far, hood, bumper or cockpit
##   --track=<ref>        the track for --drive, --race and --time-trial: an id, a path or a hash
##   --highway            a highway session right away (the first highway, or --track): --sub=cruise|score|run|loop,
##                        --traffic=<cars>, --traffic-seed=<n>, --police, --direction=-1|both, --run=<id>, --players=<n>
##   --kart               a kart race right away (the first kart track, or --track; --race-laps, --race-ai, --platform)
##   --battle[=hits]      a battle right away (the first arena, or --track; --battle-min, --battle-hits, --race-ai)
##   --cup[=<id>]         a cup right away (the Spark Cup, or <id>; --race-ai)
##   --sumo               a sumo match right away (--sumo-tiers=1-5, --sumo-hazard=lava|acid,
##                        --sumo-shrink=smooth|crumble|stepped, --sumo-secs=<s>, --sumo-pillar,
##                        --sumo-drift=off|drift, --sumo-garage-ai, --race-ai)
##   --drag               a drag match right away (--drag-length=201|402|805, --drag-boost=0-3,
##                        --drag-class=street|pro|top_fuel, --drag-seed=<n> the ladder's draw,
##                        --drag-no-timing, --drag-no-qtes, --drag-no-tree, --drag-no-two-step,
##                        --drag-no-burnout, --drag-no-shake, --drag-no-chain, --drag-no-money-shift,
##                        --drag-no-centreline, --race-ai)
##   --drag-debug         online: print what the pass is doing on this game, twice a second
##   --endless[=<code>]   an endless drive right away (a road code like FOREST-0000001, or a new road;
##                        --traffic=off|light|normal|heavy, --lanes=2|4, --side=right|left,
##                        --garage-traffic=on|off, --traps, --police, --platform;
##                        --endless-at=<m> starts that far along the road)
##   --heat=<1-5>         with --police: the players start with that much heat (police checks)
##   --kart-debug         online kart items: log every item more than 1 m off the server's
##   --time=<t>           any session's time of day (dawn, morning, noon, afternoon, dusk, night),
##                        --time-rate=<x> game minutes a minute, --weather=<w> (clear, cloudy, rain, storm,
##                        fog, snow, changing), --env-seed=<n> its fronts
##   --endless-selftest[=<seed>]  print checksums of 200 km of endless road and its ground (determinism)
##   --shot=<file.png>    save a screenshot at --shot-at=<s> (default 5; a list like 5,30,90 takes several), one per window
##   --quit-at=<s>        quit after this many seconds
##   --bay                open the Fitting Bay
##   --garage[=<car>]     open the garage (on that car's page: a package path, res://content/cars/noss_box;
##                        "traffic": in Traffic cars)
##   --import=<path>      Fitting Bay: import this model
##   --bay-auto           Fitting Bay: save and drive as soon as the import is in (timed runs)
##   --bay-step=<step>    Fitting Bay: show this step after the import (screenshots)
##   --bay-wheel=<id>     Fitting Bay: pick this wheel in the Wheels step (screenshots)
##   --editor             open the track editor; --editor-track=<ref>: on that track,
##                        --editor-template=<id>: on a new track from a template, --editor-tool=<t>,
##                        --editor-import=<file>: a new track on a 3D scene (Track Fitting)
## Online (also read before "--", so `noss_server --config server.json` works):
##   --server             run as a dedicated server (the "Linux Server" export always does)
##   --config=<file>      the dedicated server's config (data/server.example.json)
##   --port=<n>           the server's port, over the config's
##   --min-players=<n>    the dedicated server starts once n players are in and ready
##   --instance=<n>       keep settings, profiles and the identity in user://instances/<n>/, so two
##                        copies on one PC are two different players
##   --host               host at once with the last Host settings (--port, --password)
##   --no-upnp            hosting never asks the router to open the port (checks)
##   --connect=<address>  join at once (--password)
##   --bot                a load-test client (tools/net_check.py): throwaway keys, nothing saved,
##                        cars without models, AI drives, --players=<n> on one connection
##   --cheat=<kind>       bot: send false states (speed, teleport, time) to test the server's checks
##   --bot-full           bot: fetch every car whole, timing it (net_check --fresh)
##   --cache=<folder>     keep downloaded content there (an empty one: a fresh client)
##   --share-personal     server: send personal-use cars too (only to this PC's bots: net_check --fresh)
##   --auto-ready         lobby: ready each player here once their car is picked
##   --auto-start=<n>     hosting: the countdown waits for n players (everyone ready starts it)
##   --traffic-selftest[=<track>]  step a highway's traffic 1000 s, print its checksum and quit
##                        (compare builds: tools/traffic_determinism.sh)

const TITLE := "res://game/ui/title/title_screen.tscn"

## A race or time trial was asked for (tests listen with hold_events on, so no scene changes).
signal event_requested(event: RaceEvent, platform_id: String)
var hold_events := false
## A screen change was asked for: `scene` is the new screen ("TitleScreen" with no node). Tests
## turn hold_scenes on to see where a button leads without leaving the test (the node is freed
## after the signal).
signal scene_requested(name: String, scene: Node)
var hold_scenes := false

## Options also read before "--" (noss_server --config server.json); those that take a value.
const ENGINE_ARGS := ["server", "config", "port", "instance"]
const VALUE_ARGS := ["config", "port", "instance"]

var dev := {}
## No window or audio (tests, bots, the dedicated server).
var headless := false
## Running as the dedicated server.
var dedicated := false
## The Fitting Bay's draft, kept while the player test-drives it.
var bay_draft: Variant = null
## Where the Fitting Bay was opened from: "garage" (the grid) or "car" (a car's page) sends its Exit
## back there (docs/UI_FLOW.md §8).
var bay_from := ""
## The car whose page opened the bay ("car"): Exit goes back to its page, unless the bay saved
## another car.
var bay_car := ""
## The track editor's draft (TrackDraft), kept while the player test-drives it.
var track_draft: Variant = null
## A kart cup in progress (CupRun), kept between its races; null otherwise.
var cup: Variant = null
## The event pages' last start (EventFlow.to_dict(), docs/UI_FLOW.md §5.9): the results' "Event
## menu" opens its Settings page again. Empty when an event started any other way.
var flow_return := {}
## The results' "Event menu" was chosen: the main menu rebuilds the pages from flow_return.
var reopen_flow := false
var _time := 0.0
var _shots_taken := 0
var _dev_import_used := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dev = parse_args(OS.get_cmdline_args(), OS.get_cmdline_user_args())
	headless = DisplayServer.get_name() == "headless"
	dedicated = OS.has_feature("dedicated_server") or dev.has("server")
	if dedicated:
		Engine.max_fps = Engine.physics_ticks_per_second # one physics tick per frame, no busy loop
	Vehicle.drawn = not (dedicated or (dev.has("bot") and headless))
	if dev.has("instance"):
		Settings.use_folder("user://instances/%d" % clampi(int(dev.instance), 1, 99))
	Net.session_started.connect(start_online_session)
	Net.session_ended.connect(_on_online_session_ended)
	Net.disconnected.connect(_on_net_cut_off)
	if dev.has("cache"):
		ContentStore.root = String(dev.cache)
	if dev.has("bot"):
		dev["no-save"] = "true"
		dev["auto-ready"] = "true"
		dev["autodrive"] = "true"
		dev["skip-first-boot"] = "true"
		Engine.max_fps = int(dev.get("bot-fps", "60"))
		Settings.use_folder("user://tests/bots") # never this machine's player's profile or car
		Net.use_identity(NetIdentity.throwaway())
		add_child(NetBot.new())
	if dev.has("perf-log"):
		add_child(PerfLog.new())
	if dev.has("traffic-selftest"):
		print(TrafficTypes.selftest(String(dev["traffic-selftest"])))
		get_tree().quit.call_deferred()
		return
	if dev.has("endless-selftest"):
		print(EndlessGen.selftest(String(dev["endless-selftest"])))
		get_tree().quit.call_deferred()
		return
	PlayerProfile.read_only = dev.has("no-save")
	# Dev: --p1-profile='{"assists": {"racing_line": true}}' sets P1's options for this run (use
	# with --no-save to keep them out of the profile).
	var p1: Variant = JSON.parse_string(String(dev.get("p1-profile", "{}")))
	if p1 is Dictionary and not p1.is_empty():
		for key: String in p1:
			if Settings.primary.data.get(key) is Dictionary and p1[key] is Dictionary:
				Settings.primary.data[key].merge(p1[key], true)
			else:
				Settings.primary.data[key] = p1[key]
	if dev.has("fullscreen"): # this run only; not saved
		Settings.fullscreen = true
		Settings.apply_display()
	if dev.has("no-vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


## Dev options: --key=value (or --key) after "--", plus the ENGINE_ARGS before it, which may
## also be written "--key value".
static func parse_args(engine_args: PackedStringArray, user_args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < engine_args.size():
		var arg := engine_args[i]
		var kv := arg.substr(2).split("=", true, 1) if arg.begins_with("--") else PackedStringArray()
		if not kv.is_empty() and kv[0] in ENGINE_ARGS:
			if kv.size() > 1:
				out[kv[0]] = kv[1]
			elif kv[0] in VALUE_ARGS and i + 1 < engine_args.size() and not engine_args[i + 1].begins_with("-"):
				i += 1
				out[kv[0]] = engine_args[i]
			else:
				out[kv[0]] = "true"
		i += 1
	for arg in user_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


## First scene after boot.
func first_scene() -> String:
	return "" if dedicated or dev.has("drive") or dev.has("bay") or dev.has("garage") or dev.has("race") or dev.has("time-trial") or dev.has("highway") or dev.has("editor") or dev.has("endless") or dev.has("sumo") or dev.has("drag") or dev_kart() else TITLE


## Dev: a kart race, battle or cup asked for on the command line.
func dev_kart() -> bool:
	return dev.has("kart") or dev.has("battle") or dev.has("cup")


## Dev: --race starts the last race set up, with --race-laps, --race-ai, --race-practice,
## --race-quali (minutes), --race-start=rolling and --race-grid overrides; --time-trial a time trial.
func start_dev_event() -> void:
	if dev_kart():
		_start_dev_kart()
		return
	if dev.has("sumo"):
		var su := RaceEvent.sumo(int(dev.get("sumo-tiers", "2")), String(dev.get("sumo-hazard", "lava")))
		su.sumo_shrink = String(dev.get("sumo-shrink", "smooth"))
		su.sumo_secs = int(dev.get("sumo-secs", "90"))
		su.sumo_pillar = dev.has("sumo-pillar")
		su.sumo_drift = String(dev.get("sumo-drift", "drift"))
		su.ai_count = int(dev.get("race-ai", "7"))
		su.ai_skill = float(dev.get("ai-skill", "70"))
		su.ai_cars = "builtin" if not dev.has("sumo-garage-ai") else "garage"
		apply_dev_event(su)
		start_event(su, String(dev.get("platform", "official.sumo.standard")))
		return
	if dev.has("drag"):
		var dg := RaceEvent.drag(int(dev.get("drag-length", "402")), int(dev.get("drag-boost", "1")))
		for pair: Array in [["timing", "drag_timing"], ["qtes", "drag_qtes"], ["tree", "drag_tree"],
				["two-step", "drag_two_step"], ["burnout", "drag_burnout"], ["shake", "drag_shake"],
				["chain", "drag_chain"], ["money-shift", "drag_money_shift"], ["centreline", "drag_centreline"]]:
			if dev.has("drag-no-" + String(pair[0])):
				dg.set(String(pair[1]), false)
		dg.ai_count = int(dev.get("race-ai", "7"))
		dg.ai_skill = float(dev.get("ai-skill", "70"))
		dg.ai_cars = "builtin" if not dev.has("drag-garage-ai") else "garage"
		apply_dev_event(dg)
		start_event(dg, String(dev.get("platform", "official.drag." + String(dev.get("drag-class", "street")))))
		return
	if dev.has("endless"):
		var code := EndlessCode.decode(String(dev.endless))
		var e := RaceEvent.endless(int(code.get("seed", EndlessCode.random_seed())), int(code.get("biome", 1)))
		e.endless_traffic = String(dev.get("traffic", "light")) if String(dev.get("traffic", "light")) in RaceEvent.CHOICES.endless_traffic else "light"
		e.lanes = 4 if int(dev.get("lanes", "2")) >= 4 else 2
		e.drive_side = "left" if dev.get("side") == "left" else "right"
		e.garage_traffic = dev.get("garage-traffic", "on") != "off"
		e.speed_traps = dev.has("traps")
		e.police = dev.has("police")
		start_event(e, String(dev.get("platform", "official.endless.cruiser")))
		return
	if dev.has("highway"):
		var h := RaceEvent.highway(String(dev.get("sub", "cruise")), dev.has("police"), int(dev.get("traffic", "-1")))
		h.direction = 0 if dev.get("direction") == "both" else -1 if int(dev.get("direction", "1")) < 0 else 1
		h.run = String(dev.get("run", ""))
		start_event(h, String(dev.get("platform", "official.highway.street")))
		return
	var e := Settings.last_event() if dev.has("race") else RaceEvent.time_trial()
	start_event(e, String(dev.get("platform", Settings.profile.get("last_platform", "official.track.gt"))))


func _start_dev_kart() -> void:
	var platform := String(dev.get("platform", Settings.profile.get("last_kart_platform", "official.kart.medium")))
	var e := RaceEvent.new()
	e.kind = "race"
	e.practice_min = 0
	e.qualifying_min = 0
	e.race_laps = 3
	e.ai_count = 7
	e.ai_cars = "builtin"
	e.grid = "random"
	apply_dev_event(e)
	if dev.has("cup"):
		var id := String(dev.cup) if String(dev.cup) != "true" else "spark_cup"
		var path := CupRun.BUILTIN_DIR + id + ".cup.json"
		var c := CupRun.load_file(path if FileAccess.file_exists(path) else CupRun.user_dir + id + ".cup.json")
		if c.is_empty() or CupRun.missing_track(c) >= 0:
			push_error("No cup %s (or a track of it is missing)" % id)
			return
		start_cup_race(CupRun.start(c, platform, e))
		return
	if dev.has("battle"):
		var b := RaceEvent.battle("hits" if String(dev.battle) == "hits" else "standing", int(dev.get("battle-min", "5")))
		b.battle_hits = int(dev.get("battle-hits", "10"))
		b.ai_count = e.ai_count
		b.ai_skill = e.ai_skill
		b.ai_cars = "builtin"
		var arena := selected_track("arena")
		start_event(b, platform, arena)
		return
	var track := selected_track("circuit") if dev.has("track") else ""
	if track.is_empty():
		var karts := TrackLibrary.list(true, true, "circuit").filter(func(t: Dictionary) -> bool: return "kart" in t.get("tags", []))
		track = String(karts[0].path) if not karts.is_empty() else selected_track("circuit")
	start_event(e, platform, track)


## Dev overrides for a race (--race-laps, --race-ai, --race-practice, --race-quali, --race-start,
## --race-grid, --ai-skill), also used by the event pages so checks can walk the real menus.
func apply_dev_event(e: RaceEvent) -> void:
	if dev.has("race-laps"):
		e.race_laps = int(dev["race-laps"])
		e.race_min = 0
	for key: String in { "race-ai": "ai_count", "race-practice": "practice_min", "race-quali": "qualifying_min" }:
		if dev.has(key):
			e.set({ "race-ai": "ai_count", "race-practice": "practice_min", "race-quali": "qualifying_min" }[key], int(dev[key]))
	if dev.has("race-start"):
		e.start = dev["race-start"]
	if dev.has("race-grid"):
		e.grid = dev["race-grid"]
	if dev.has("ai-skill"):
		e.ai_skill = float(dev["ai-skill"])
	# Track-mode rules (D207): "track", "off" or "on"; the multipliers -1 (the track's), 0 (off) to 10.
	if dev.has("race-draft"):
		e.draft = String(dev["race-draft"])
	if dev.has("race-fuel"):
		e.fuel_x = clampi(int(dev["race-fuel"]), -1, RaceEvent.WEAR_X_MAX)
	if dev.has("race-tyres"):
		e.tyre_x = clampi(int(dev["race-tyres"]), -1, RaceEvent.WEAR_X_MAX)
	if dev.has("race-plate"):
		e.plate = String(dev["race-plate"]) if String(dev["race-plate"]) in RaceEvent.CHOICES.plate else "track"


## The track to drive: --track, else the last one picked, else the Proving Ground (or the first
## highway). With `type`, only a track of that type.
func selected_track(type := "") -> String:
	if dev.has("track"):
		var t := TrackLibrary.resolve(String(dev.track))
		if t and (type.is_empty() or TrackLibrary.type_of(t) == type):
			return t
		push_warning("No track " + String(dev.track))
	var last := String(Settings.profile.get("last_track", ""))
	var found := TrackLibrary.resolve(last) if last else ""
	if found and (type.is_empty() or TrackLibrary.type_of(found) == type):
		return found
	if type in ["highway", "arena"]:
		var of_type := TrackLibrary.list(true, true, type)
		return of_type[0].path if not of_type.is_empty() else ""
	return TrackLibrary.DEFAULT


## Starts `session`, its track loaded off the main thread first behind a loading screen (a
## preloaded track_package goes straight in).
func open_session(session: TrackSession) -> void:
	# Endless makes its own road; sumo its platforms (D162) and drag its strip (D168): none of
	# them loads a track file.
	if (session.track_package and session.track_package.ok()) or session.event.kind in ["endless", "sumo", "drag"]:
		_switch(session)
		return
	_switch(LoadingScreen.new())
	TrackLoader.load_async(self, session.track_path, func(pkg: TrackPackage) -> void:
		if pkg.ok():
			session.track_package = pkg
		_switch(session))


## `solo`: only P1 drives (garage and Fitting Bay); otherwise every joined player. `track`: a
## path; empty: selected_track(). `event`: the Free Drive setup (AI cars, collisions, track
## limits); the dev options --ai, --ai-skill and --ai-builtin go over it.
func start_free_drive(car_path := "", platform_id := "", bay_return := false, solo := true, track := "", event: RaceEvent = null) -> void:
	flow_return = {}
	if event:
		event_requested.emit(event, platform_id)
		if hold_events:
			return
	get_tree().paused = false
	var session := TrackSession.new()
	if event:
		session.event = event
	session.track_path = track if track else selected_track("circuit")
	session.bay_return = bay_return
	session.solo = solo and not dev.has("players")
	session.car_path = car_path if car_path else String(dev.get("car", ""))
	session.platform_id = platform_id if platform_id else String(dev.get("platform", Settings.profile.get("last_platform", "")))
	session.autodrive = dev.has("autodrive")
	session.ai_players = maxi(int(dev.get("players", "1")) - maxi(Players.count(), 1), 0)
	session.ai_racers = int(dev.get("ai", event.ai_count if event else 0))
	session.ai_skill = float(dev.get("ai-skill", event.ai_skill if event else 80.0))
	session.ai_builtin_cars = dev.has("ai-builtin") or (event != null and event.ai_cars == "builtin")
	if dev.has("camera"):
		Settings.profile.camera = dev.camera
	open_session(session)


## A race weekend or time trial with `event`; every joined player takes part. `track`: a path;
## empty: selected_track().
func start_event(event: RaceEvent, platform_id: String, track := "") -> void:
	flow_return = {} # EventFlow.start() sets it again after this
	event_requested.emit(event, platform_id)
	if hold_events:
		return
	get_tree().paused = false
	var session := TrackSession.new()
	if event.kind not in ["sumo", "drag"]: # both are generated, so there is no track to pick
		session.track_path = track if track else selected_track("highway" if event.kind == "highway" else "arena" if event.kind == "battle" else "circuit")
	session.event = event
	session.platform_id = platform_id
	session.autodrive = dev.has("autodrive")
	if event.kind in ["highway", "time_trial"]:
		session.ai_players = maxi(int(dev.get("players", "1")) - maxi(Players.count(), 1), 0)
	if dev.has("camera"):
		Settings.profile.camera = dev.camera
	open_session(session)


## Starts cup `run`'s next race (D145): its track, laps and the same AI field.
func start_cup_race(run: CupRun) -> void:
	if cup != run: # a new cup, not its next race
		flow_return = {}
	cup = run
	var e := run.event_for(run.index)
	event_requested.emit(e, run.platform_id)
	if hold_events:
		return
	get_tree().paused = false
	var session := TrackSession.new()
	session.track_path = run.track_for(run.index)
	session.event = e
	session.platform_id = run.platform_id
	session.cup = run
	session.autodrive = dev.has("autodrive")
	open_session(session)


## Why the last online game ended ("Server closed"), for Drive Online on the main menu; then "".
var net_status := ""


## An online session ({track, class, event, roster}, Net.session) on this game: its players drive
## their own cars, everyone else's are remote. The dedicated server builds its own (ServerMain).
func start_online_session(data: Dictionary) -> void:
	if dedicated or hold_events:
		return
	if not _session_platform(data).ok() and Net.content and Net.content.pending() > 0:
		# The server's own class is still on its way (PLT-09): start when it's here.
		Net.content.file_ready.connect(func(_h: String) -> void: start_online_session(data), CONNECT_ONE_SHOT)
		return
	var track := String(data.track)
	if session_track(track).is_empty() and Net.content and not Net.is_server():
		var why := Net.content.track_refusal(track)
		if why.is_empty():
			# The track is still coming (EDT-08): start when it's here.
			Net.content.fetch_track(track, 1, int(data.get("track_bytes", -1)))
			_track_wait = data
			if not Net.content.track_ready.is_connected(_on_session_track):
				Net.content.track_ready.connect(_on_session_track)
				Net.content.track_refused.connect(_on_session_track.unbind(1))
			return
	var session := online_session(data)
	if session == null:
		var why := Net.content.track_refusal(track) if Net.content else ""
		Net.leave()
		net_status = why if why else "Track or class not found"
		go_title()
		return
	get_tree().paused = false
	_switch(session)


## The session waiting for its track (start_online_session), or {}.
var _track_wait := {}


## A track came (or can't): start the session waiting for it, if it's still on.
func _on_session_track(h: String) -> void:
	if _track_wait.is_empty() or h != String(_track_wait.track):
		return
	var data := _track_wait
	_track_wait = {}
	if Net.session.get("track") == data.track:
		start_online_session(data)


## Where a session's track is here: the host's own, or by hash (built-in, library, download), or
## by id or path (built-in tracks, tests); "" while it isn't here.
func session_track(ref: String) -> String:
	if ref == ServerConfig.ENDLESS:
		return ref # an endless road: made from the event's seed
	if Net.host_logic:
		var info := Net.host_logic.track_info()
		if info.hash == ref or info.path == ref:
			return String(info.path)
	if ref.begins_with("sha256:"):
		return Net.content.track_path(ref) if Net.content else TrackLibrary.by_hash(ref)
	return TrackLibrary.resolve(ref)


## The session's platform: the server's own when hosting, else official or from the cache.
func _session_platform(data: Dictionary) -> PlatformLoader.Result:
	if Net.host_logic:
		return Net.host_logic.platform_result()
	return Net.platform_result(String(data["class"]), String(data.get("class_hash", "")))


## A TrackSession for an online session, or null if its track or class isn't here.
func online_session(data: Dictionary) -> TrackSession:
	var track := session_track(String(data.track))
	if track.is_empty():
		return null
	var platform := _session_platform(data)
	if not platform.ok():
		return null
	var session := TrackSession.new()
	if not platform.path.begins_with(PlatformLoader.OFFICIAL_DIR):
		session.platform_file = platform.path
	session.online = data
	session.dedicated = dedicated
	session.track_path = track
	session.platform_id = String(data["class"])
	session.event = RaceEvent.from_dict(data.event)
	session.autodrive = dev.has("autodrive")
	if Net.host_logic and not Net.host_logic.cup_item().is_empty():
		session.cup = Net.host_logic.cup # a cup's later races start in reverse order of its standings
	return session


## The dedicated server: no title, no players of its own.
func start_server() -> void:
	_switch(ServerMain.new())


func _on_online_session_ended() -> void:
	if not dedicated and get_tree().current_scene is TrackSession:
		go_title() # the title opens the lobby while online


## Cut off from the server mid-session: back to Drive Online with why.
func _on_net_cut_off(reason: String) -> void:
	if not dedicated and get_tree().current_scene is TrackSession and (get_tree().current_scene as TrackSession).is_online():
		net_status = reason
		go_title()


## The garage, with the car at `select` (a package path) picked if it's there; with `page` "car",
## on that car's page.
func open_garage(select := "", page := "") -> void:
	get_tree().paused = false
	var garage := Garage.new()
	garage.start_car = select
	garage.start_page = page
	_switch(garage)


## `from`: "garage" when the Garage's grid opened it, "car" when a car's page did (bay_car), so its
## Exit goes back there; else empty.
func open_fitting_bay(import_path := "", step := "", from := "") -> void:
	get_tree().paused = false
	bay_from = from
	var bay := FittingBay.new()
	bay.start_step = step
	if not _dev_import_used:
		_dev_import_used = true
		import_path = import_path if import_path else String(dev.get("import", ""))
		bay.auto = dev.has("bay-auto")
	bay.import_path = import_path
	_switch(bay)


## The track editor: on the draft being edited (back from a test drive), a track (a path), a
## new track from a template, or (none) an empty one.
func open_track_editor(track := "", template := "") -> void:
	get_tree().paused = false
	if track:
		var pkg := TrackLoader.load_package(track)
		if pkg.ok():
			track_draft = TrackDraft.from_package(pkg)
	elif template:
		track_draft = TrackTemplates.make(template)
	_switch(TrackEditor.new())


## Drives the editor's draft as it is: P1 alone in their last car and class, from `at` (a
## Transform3D) or the grid (null). The pause menu and editor_back lead back to the editor
## with its history (EDT-06). The draft is autosaved first.
func start_test_drive(draft: TrackDraft, at: Variant = null) -> void:
	if not PlayerProfile.read_only:
		draft.autosave_async(self)
	open_session(test_drive_session(draft, at))


func test_drive_session(draft: TrackDraft, at: Variant = null) -> TrackSession:
	get_tree().paused = false
	var session := TrackSession.new()
	session.track_package = draft.to_package()
	session.editor_return = true
	session.start_at = at
	session.solo = true
	session.platform_id = String(Settings.profile.get("last_platform", "")) if Settings.profile.get("last_platform", "") else TrackSession.DEFAULT_PLATFORM
	if draft.is_highway():
		# A highway drives as Cruise with its traffic, in a highway class.
		session.event = RaceEvent.highway("cruise", false, -1)
		if GameModes.mode_for(session.platform_id).get("id", "") != "highway":
			session.platform_id = "official.highway.street"
	elif draft.is_arena() or not (draft.kart().get("stunts", []) as Array).is_empty():
		# Kart pieces and arenas drive in a kart class: the last one, else Medium (D137).
		if GameModes.mode_for(session.platform_id).get("id", "") != "kart":
			session.platform_id = String(Settings.profile.get("last_kart_platform", "official.kart.medium"))
	session.autodrive = dev.has("autodrive")
	return session


## Back from a test drive: the editor on the same draft, as it was left.
func return_to_editor() -> void:
	get_tree().paused = false
	_switch(TrackEditor.new())


## Dev: --editor (--editor-track, --editor-template, --editor-import).
func open_dev_editor() -> void:
	var track := TrackLibrary.resolve(String(dev.get("editor-track", ""))) if dev.has("editor-track") else ""
	open_track_editor(track, String(dev.get("editor-template", "")))


## Changes the running scene once this frame's input and signals are done: a menu button that
## starts something mustn't pull its own screen out from under the press it's handling.
func _switch(scene: Node) -> void:
	if hold_scenes:
		scene_requested.emit(scene.get_script().get_global_name() if scene.get_script() else scene.get_class(), scene)
		scene.free()
		return
	_change_scene.call_deferred(scene)


## The new scene goes in here, not through change_scene_to_node(): a screen built inside Godot's
## own scene change (4.7.2) leaves the first control of a row under a scroll (the Garage's first
## tab and card, a Fitting Bay row's first button) out of the screen-reader tree (ARCHITECTURE.md
## §1). Nothing reads current_scene from a new scene's _ready.
func _change_scene(scene: Node) -> void:
	var tree := get_tree()
	tree.unload_current_scene()
	tree.root.add_child(scene)
	tree.current_scene = scene


## The results' "Event menu": the main menu, opened on that event's Settings page.
func go_event_menu() -> void:
	reopen_flow = not flow_return.is_empty()
	go_title()


func go_title() -> void:
	cup = null # leaving a cup ends it
	get_tree().paused = false
	if hold_scenes:
		scene_requested.emit("TitleScreen", null)
		return
	get_tree().change_scene_to_file.call_deferred(TITLE)


func _exit_tree() -> void:
	if bay_draft is FittingDraft:
		bay_draft.free_scene()


func quit() -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	_time += delta
	# --shot-at can list several times ("5,30,90"): then each file gets _<n> after its name.
	var times := String(dev.get("shot-at", "5")).split(",")
	if dev.has("shot") and _shots_taken < times.size() and _time >= float(times[_shots_taken]):
		var base := String(dev.shot) if times.size() == 1 else "%s_%d.png" % [String(dev.shot).get_basename(), _shots_taken + 1]
		_shots_taken += 1
		var img := get_viewport().get_texture().get_image()
		img.save_png(base)
		print("Screenshot: ", base)
		# Extra monitor windows: <shot>_<window name>.png
		for w: Window in get_tree().root.find_children("*", "Window", true, false):
			var path := base.get_basename() + "_" + w.name + ".png"
			w.get_texture().get_image().save_png(path)
			print("Screenshot: ", path)
	if dev.has("quit-at") and _time >= float(dev["quit-at"]):
		get_tree().quit()
