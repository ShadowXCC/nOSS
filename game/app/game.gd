extends Node
## Game flow (autoload "Game"): title, sessions, quitting. Also reads dev options passed
## after "--" on the command line:
##   --drive              start free-drive right away
##   --car=<path>         car package for --drive
##   --platform=<id>      platform class for --drive, e.g. official.highway.street
##   --autodrive          let the racing AI drive the players (tests, screenshots)
##   --players=<n>        free drive with n players; the extra ones are driven by the racing AI
##   --ai=<n>             add n AI racers (no views); --ai-skill=<0-100>, --ai-builtin: built-in cars only
##   --race               start a race right away (the last race set up); --race-laps=<n>, --race-ai=<n>
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
##   --fullscreen         fullscreen for this run; --no-vsync: no vsync (measurements)
##   --pause-at=<s>       open the last player's pause menu
##   --menu=<m>           title: open classes, event, players, settings, online, online-players or tracks
##                        (--join=<n>: n devices join)
##   --camera=<mode>      chase_near, chase_far, hood, bumper or cockpit
##   --track=<ref>        the track for --drive, --race and --time-trial: an id, a path or a hash
##   --shot=<file.png>    save a screenshot at --shot-at=<s> (default 5; a list like 5,30,90 takes several), one per window
##   --quit-at=<s>        quit after this many seconds
##   --bay                open the Fitting Bay
##   --garage             open the garage
##   --import=<path>      Fitting Bay: import this model
##   --bay-auto           Fitting Bay: save and drive as soon as the import is in (timed runs)
##   --bay-step=<step>    Fitting Bay: show this step after the import (screenshots)
##   --editor             open the track editor; --editor-track=<ref>: on that track,
##                        --editor-template=<id>: on a new track from a template, --editor-tool=<t>
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
##   --auto-ready         lobby: ready once the cars are picked
##   --auto-start=<n>     hosting: start once n players are in and everyone's ready

const TITLE := "res://game/ui/title/title_screen.tscn"

## A race or time trial was asked for (tests listen with hold_events on, so no scene changes).
signal event_requested(event: RaceEvent, platform_id: String)
var hold_events := false

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
## The track editor's draft (TrackDraft), kept while the player test-drives it.
var track_draft: Variant = null
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
	return "" if dedicated or dev.has("drive") or dev.has("bay") or dev.has("garage") or dev.has("race") or dev.has("time-trial") or dev.has("editor") else TITLE


## Dev: --race starts the last race set up, with --race-laps, --race-ai, --race-practice,
## --race-quali (minutes), --race-start=rolling and --race-grid overrides; --time-trial a time trial.
func start_dev_event() -> void:
	var e := Settings.last_event() if dev.has("race") else RaceEvent.time_trial()
	start_event(e, String(dev.get("platform", Settings.profile.get("last_platform", "official.track.gt"))))


## Dev overrides for a race (--race-laps, --race-ai, --race-practice, --race-quali, --race-start,
## --race-grid, --ai-skill), also used by the Race menu so checks can walk the real menus.
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


## The track to drive: --track, else the last one picked, else the Proving Ground.
func selected_track() -> String:
	if dev.has("track"):
		var t := TrackLibrary.resolve(String(dev.track))
		if t:
			return t
		push_warning("No track " + String(dev.track))
	var last := String(Settings.profile.get("last_track", ""))
	var found := TrackLibrary.resolve(last) if last else ""
	return found if found else TrackLibrary.DEFAULT


## Starts `session`, its track loaded off the main thread first behind a loading screen (a
## preloaded track_package goes straight in).
func open_session(session: TrackSession) -> void:
	if session.track_package and session.track_package.ok():
		get_tree().change_scene_to_node(session)
		return
	get_tree().change_scene_to_node(LoadingScreen.new())
	TrackLoader.load_async(self, session.track_path, func(pkg: TrackPackage) -> void:
		if pkg.ok():
			session.track_package = pkg
		get_tree().change_scene_to_node(session))


## `solo`: only P1 drives (garage and Fitting Bay); otherwise every joined player. `track`: a
## path; empty: selected_track().
func start_free_drive(car_path := "", platform_id := "", bay_return := false, solo := true, track := "") -> void:
	get_tree().paused = false
	var session := TrackSession.new()
	session.track_path = track if track else selected_track()
	session.bay_return = bay_return
	session.solo = solo and not dev.has("players")
	session.car_path = car_path if car_path else String(dev.get("car", ""))
	session.platform_id = platform_id if platform_id else String(dev.get("platform", Settings.profile.get("last_platform", "")))
	session.autodrive = dev.has("autodrive")
	session.ai_players = maxi(int(dev.get("players", "1")) - maxi(Players.count(), 1), 0)
	session.ai_racers = int(dev.get("ai", "0"))
	session.ai_skill = float(dev.get("ai-skill", "80"))
	session.ai_builtin_cars = dev.has("ai-builtin")
	if dev.has("camera"):
		Settings.profile.camera = dev.camera
	open_session(session)


## A race weekend or time trial with `event`; every joined player takes part (time trial: P1).
## `track`: a path; empty: selected_track().
func start_event(event: RaceEvent, platform_id: String, track := "") -> void:
	event_requested.emit(event, platform_id)
	if hold_events:
		return
	get_tree().paused = false
	var session := TrackSession.new()
	session.track_path = track if track else selected_track()
	session.event = event
	session.solo = event.kind == "time_trial"
	session.platform_id = platform_id
	session.autodrive = dev.has("autodrive")
	if dev.has("camera"):
		Settings.profile.camera = dev.camera
	open_session(session)


## Why the last online game ended ("Server closed"), for the title's Online menu; then "".
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
	get_tree().change_scene_to_node(session)


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
	return session


## The dedicated server: no title, no players of its own.
func start_server() -> void:
	get_tree().change_scene_to_node(ServerMain.new())


func _on_online_session_ended() -> void:
	if not dedicated and get_tree().current_scene is TrackSession:
		go_title() # the title opens the lobby while online


## Cut off from the server mid-session: back to the Online menu with why.
func _on_net_cut_off(reason: String) -> void:
	if not dedicated and get_tree().current_scene is TrackSession and (get_tree().current_scene as TrackSession).is_online():
		net_status = reason
		go_title()


func open_garage() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_node(Garage.new())


func open_fitting_bay(import_path := "", step := "") -> void:
	get_tree().paused = false
	var bay := FittingBay.new()
	bay.start_step = step
	if not _dev_import_used:
		_dev_import_used = true
		import_path = import_path if import_path else String(dev.get("import", ""))
		bay.auto = dev.has("bay-auto")
	bay.import_path = import_path
	get_tree().change_scene_to_node(bay)


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
	get_tree().change_scene_to_node(TrackEditor.new())


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
	session.autodrive = dev.has("autodrive")
	return session


## Back from a test drive: the editor on the same draft, as it was left.
func return_to_editor() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_node(TrackEditor.new())


## Dev: --editor (--editor-track, --editor-template).
func open_dev_editor() -> void:
	var track := TrackLibrary.resolve(String(dev.get("editor-track", ""))) if dev.has("editor-track") else ""
	open_track_editor(track, String(dev.get("editor-template", "")))


func go_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE)


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
