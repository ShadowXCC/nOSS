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
##   --menu=<m>           title: open classes, players or settings (--join=<n>: n devices join)
##   --camera=<mode>      chase_near, chase_far, hood, bumper or cockpit
##   --shot=<file.png>    save a screenshot at --shot-at=<s> (default 5; a list like 5,30,90 takes several), one per window
##   --quit-at=<s>        quit after this many seconds
##   --bay                open the Fitting Bay
##   --garage             open the garage
##   --import=<path>      Fitting Bay: import this model
##   --bay-auto           Fitting Bay: save and drive as soon as the import is in (timed runs)
##   --bay-step=<step>    Fitting Bay: show this step after the import (screenshots)

const TITLE := "res://game/ui/title/title_screen.tscn"

## A race or time trial was asked for (tests listen with hold_events on, so no scene changes).
signal event_requested(event: RaceEvent, platform_id: String)
var hold_events := false

var dev := {}
## The Fitting Bay's draft, kept while the player test-drives it.
var bay_draft: Variant = null
var _time := 0.0
var _shots_taken := 0
var _dev_import_used := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			dev[kv[0]] = kv[1] if kv.size() > 1 else "true"
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


## First scene after boot.
func first_scene() -> String:
	return "" if dev.has("drive") or dev.has("bay") or dev.has("garage") or dev.has("race") or dev.has("time-trial") else TITLE


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


## `solo`: only P1 drives (garage and Fitting Bay); otherwise every joined player.
func start_free_drive(car_path := "", platform_id := "", bay_return := false, solo := true) -> void:
	get_tree().paused = false
	var session := TrackSession.new()
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
	get_tree().change_scene_to_node(session)


## A race weekend or time trial with `event`; every joined player takes part (time trial: P1).
func start_event(event: RaceEvent, platform_id: String) -> void:
	event_requested.emit(event, platform_id)
	if hold_events:
		return
	get_tree().paused = false
	var session := TrackSession.new()
	session.event = event
	session.solo = event.kind == "time_trial"
	session.platform_id = platform_id
	session.autodrive = dev.has("autodrive")
	if dev.has("camera"):
		Settings.profile.camera = dev.camera
	get_tree().change_scene_to_node(session)


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
