extends Control
## Title screen.

@onready var _version_label: Label = %VersionLabel
@onready var _drive_button: Button = %LocalDriveButton
@onready var _settings_button: Button = %SettingsButton
@onready var _exit_button: Button = %ExitButton
@onready var _buttons: ScrollContainer = %Buttons

## Every screen opened from here, one over another (docs/UI_FLOW.md §4). The logo and buttons
## hide while one is up.
var _stack := MenuStack.new()
var _solo: SoloMenu
var _online: OnlineMenu
var _lobby: LobbyMenu
## What the class picker leads to: "free", "race", "time_trial", "highway", "kart" or
## "mini_games".
var _mode := "free"


func _ready() -> void:
	theme = UiKit.theme()
	_apply_text_scale()
	resized.connect(_fit_buttons)
	Settings.changed.connect(_apply_text_scale)
	Players.slots_changed.connect(_apply_text_scale)
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	# docs/UI_FLOW.md §3: Local Drive, Drive Online, Garage, Track Editor, Settings, Exit Game.
	_drive_button.accessibility_description = "Races, time trials, endless, highway, mini games and free drive on this PC"
	_drive_button.pressed.connect(_open_solo)
	_settings_button.accessibility_description = "Display, sound, splitscreen and players"
	_settings_button.pressed.connect(_open_settings)
	_exit_button.accessibility_description = "Close nOSS"
	_exit_button.pressed.connect(get_tree().quit)
	var editor_button := Button.new()
	editor_button.name = "TrackEditorButton"
	editor_button.text = "Track Editor"
	editor_button.accessibility_description = "Build tracks"
	editor_button.custom_minimum_size = _drive_button.custom_minimum_size
	editor_button.pressed.connect(func() -> void: Game.open_track_editor())
	_drive_button.add_sibling(editor_button)
	var garage_button := Button.new()
	garage_button.name = "GarageButton"
	garage_button.text = "Garage"
	garage_button.accessibility_description = "Your cars and the Fitting Bay"
	garage_button.custom_minimum_size = _drive_button.custom_minimum_size
	garage_button.pressed.connect(func() -> void: Game.open_garage())
	_drive_button.add_sibling(garage_button)
	var online_button := Button.new()
	online_button.name = "DriveOnlineButton"
	online_button.text = "Drive Online"
	online_button.accessibility_description = "Host or join a game over the network"
	online_button.custom_minimum_size = _drive_button.custom_minimum_size
	online_button.pressed.connect(_open_online)
	_drive_button.add_sibling(online_button)
	# Focus goes down the buttons as they're shown (one list, so the two can't differ).
	var order := _drive_button.get_parent().get_children()
	for b: Button in order:
		b.accessibility_name = b.text
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", _drive_button.get_theme_font_size("font_size"))
	UiKit.chain_focus(order)
	_fit_buttons.call_deferred()
	add_child(_stack)
	for part: NodePath in [^"Logo", ^"TaglineLabel", ^"Menu", ^"VersionLabel"]:
		_stack.base.append(get_node(part))
	_stack.emptied.connect(func() -> void:
		if UiKit.focus_owner(self) == null:
			_drive_button.grab_focus())
	# First boot: the accessibility screen comes before anything else (ACC-09).
	if (not Settings.first_boot_done and DisplayServer.get_name() != "headless" and not Game.dev.has("skip-first-boot")) or Game.dev.get("menu", "") == "access":
		var first := FirstBootMenu.new()
		first.done.connect(func() -> void:
			_stack.close(first)
			_drive_button.grab_focus())
		_stack.push(first)
		return
	match Game.dev.get("menu", ""): # dev: open a menu directly
		"solo": _open_solo()
		"classes":
			_open_solo()
			_open_classes("free")
		"event":
			_open_solo()
			_open_event(String(Settings.profile.get("last_platform", "official.track.gt")))
		"free":
			_open_solo()
			_open_free(String(Settings.profile.get("last_platform", "official.track.gt")))
		"players":
			_open_solo()
			_open_players(String(Settings.profile.get("last_platform", "official.track.gt")))
		"settings": _open_settings()
		"driving-settings":
			_open_settings()
			(_stack.top() as SettingsMenu)._open_player()
		"online": _open_online()
		"tracks":
			_open_solo()
			_open_tracks(func(_t: String) -> void: pass, true)
		"highway":
			_open_solo()
			_open_highway()
		"kart":
			_open_solo()
			_open_kart()
		"endless":
			_open_solo()
			_open_endless()
		"mini-games":
			_open_solo()
			_open_mini_games()
		"sumo":
			_open_solo()
			_open_mini_games()
			_open_sumo()
		"drag":
			_open_solo()
			_open_mini_games()
			_open_drag()
		"online-players":
			_open_online()
			_online._open_players()
	if Net.online(): # back from an online session: its lobby
		_open_online()
		_open_lobby()
	elif Game.net_status: # cut off from a server: why
		_open_online()
		_online.show_status(Game.net_status)
		Game.net_status = ""
	elif Game.dev.has("host"): # dev: host with the last settings (--port, --password)
		_open_online()
		_online.host_now()
	elif Game.dev.has("connect"): # dev: --connect=<address> (--password)
		if Game.dev.has("bot"): # its players: P1 and AI slots
			Players.primary_slot()
			for i in clampi(int(Game.dev.get("players", "1")) - 1, 0, 3):
				Players.add_ai()
			for slot in Players.slots:
				slot.profile.data.name = "Bot%s %s" % [OS.get_process_id() % 1000, slot.tag()]
		_open_online()
		_online._join(String(Game.dev.connect), String(Game.dev.get("password", "")))


## Local Drive: the drive modes on this machine (SoloMenu). Back on it from a mode's first screen,
## the focus is on that mode.
func _open_solo() -> void:
	_solo = SoloMenu.new()
	_solo.name = "SoloMenu"
	_solo.chosen.connect(_on_solo_chosen)
	_stack.push(_solo, func() -> void: _solo.focus(_mode))


func _on_solo_chosen(mode: String) -> void:
	match mode:
		"highway": _open_highway()
		"kart": _open_kart()
		"endless": _open_endless()
		"mini_games": _open_mini_games()
		_: _open_classes(mode)


## Free Drive: class first (how it drives), then its setup (track, AI, rules), then the players,
## who each pick a car (how it looks). Race: class, then the event (track included), then the players. Time Trial:
## class, then the track, then P1 drives.
func _open_classes(mode: String) -> void:
	_mode = mode
	var classes := ClassPicker.new()
	classes.current = String(Settings.profile.get("last_platform", ""))
	if mode != "free":
		classes.mode_filter = "track"
	classes.picked.connect(_on_class_picked)
	_stack.push(classes, classes.grab_focus_first)


func _on_class_picked(id: String) -> void:
	if _mode == "race":
		_open_event(id)
	elif _mode == "time_trial":
		Settings.profile.last_platform = id
		_open_tracks(func(track: String) -> void: Game.start_event(RaceEvent.time_trial(), id, track))
	else:
		_open_free(id)


## Free Drive's setup: the track, AI cars and rules.
func _open_free(platform_id: String) -> void:
	var free := FreeDriveMenu.new()
	free.picked.connect(func(e: RaceEvent, track: String) -> void: _open_players(platform_id, e, track))
	_stack.push(free, free.grab_focus_first)


## The track picker, then `then` (track path). With only one track, straight on (unless `always`).
func _open_tracks(then: Callable, always := false) -> void:
	if TrackLibrary.list(true, true, "circuit").size() <= 1 and not always:
		then.call(Game.selected_track("circuit"))
		return
	var tracks := TrackPicker.new()
	tracks.picked.connect(func(path: String) -> void: then.call(path))
	_stack.push(tracks, tracks.grab_focus_first)


## Highway (M7): the highway first, then what to do on it (HighwayMenu), the class, the players.
func _open_highway() -> void:
	_mode = "highway"
	var tracks := TrackPicker.new()
	tracks.type = "highway"
	tracks.picked.connect(_open_highway_menu)
	_stack.push(tracks, tracks.grab_focus_first)


func _open_highway_menu(track: String) -> void:
	var menu := HighwayMenu.new()
	menu.track_path = track
	menu.picked.connect(func(e: RaceEvent) -> void:
		var classes := ClassPicker.new()
		classes.mode_filter = "highway"
		classes.current = String(Settings.profile.get("last_platform", ""))
		classes.picked.connect(func(id: String) -> void:
			Settings.profile.last_platform = id
			_open_players(id, e, track))
		_stack.push(classes, classes.grab_focus_first))
	_stack.push(menu, menu.grab_focus_first)


## Kart (M8): race, battle or cup and its setup (KartMenu), then the players, who each pick their
## kart's class on their card (D149).
func _open_kart() -> void:
	_mode = "kart"
	var menu := KartMenu.new()
	menu.name = "KartMenu"
	menu.picked.connect(func(kind: String, e: RaceEvent, track: String, cup: String) -> void:
		var id := String(Settings.profile.get("last_kart_platform", "official.kart.medium"))
		if kind == "cup":
			_open_players(id, e, "", func() -> void: Game.start_cup_race(CupRun.start(CupRun.load_file(cup), id, e)))
		else:
			_open_players(id, e, track))
	_stack.push(menu, menu.grab_focus_first)


## Endless (M9): the road and its setup (EndlessMenu), the class, the players.
func _open_endless() -> void:
	_mode = "endless"
	var menu := EndlessMenu.new()
	menu.name = "EndlessMenu"
	menu.picked.connect(func(e: RaceEvent) -> void:
		var classes := ClassPicker.new()
		classes.mode_filter = "endless"
		classes.current = String(Settings.profile.get("last_platform", ""))
		classes.picked.connect(func(id: String) -> void:
			Settings.profile.last_platform = id
			_open_players(id, e, ""))
		_stack.push(classes, classes.grab_focus_first))
	_stack.push(menu, menu.grab_focus_first)


## Mini Games (Changes.md): the short matches that aren't races. Picking one opens its own
## screen; backing out of that shows this list again, and backing out of this shows Local Drive.
func _open_mini_games() -> void:
	_mode = "mini_games"
	var mini := MiniGamesMenu.new()
	mini.name = "MiniGamesMenu"
	mini.chosen.connect(func(game: String) -> void:
		if game == "sumo":
			_open_sumo()
		elif game == "drag":
			_open_drag())
	_stack.push(mini, mini.grab_focus_first)


## Sumo Wrestling (D162): its settings (SumoMenu), then the players. There is no class to pick:
## the mode has one, and no track: the arena is made from the settings.
func _open_sumo() -> void:
	var menu := SumoMenu.new()
	menu.name = "SumoMenu"
	menu.picked.connect(func(e: RaceEvent) -> void: _open_players("official.sumo.standard", e))
	_stack.push(menu, menu.grab_focus_first)


## Drag Strip (D168): its settings (DragMenu), then the players. The class is one of its own
## rows rather than the class picker, and there is no track: the strip is made from the settings.
func _open_drag() -> void:
	var menu := DragMenu.new()
	menu.name = "DragMenu"
	menu.picked.connect(func(e: RaceEvent, class_id: String) -> void: _open_players(class_id, e))
	_stack.push(menu, menu.grab_focus_first)


func _open_event(platform_id: String) -> void:
	var menu := EventMenu.new()
	menu.picked.connect(func(e: RaceEvent) -> void: _open_players(platform_id, e))
	_stack.push(menu, menu.grab_focus_first)


## The players, then the session (`start` instead, if given: a cup). Back goes to the screen
## before (the stack's).
func _open_players(platform_id: String, event: RaceEvent = null, track := "", start := Callable()) -> void:
	var players := PlayersMenu.new()
	players.platform_id = platform_id
	players.started.connect(func() -> void:
		if start.is_valid():
			start.call()
		elif event and event.kind != "free":
			Game.start_event(event, platform_id, track)
		else:
			Game.start_free_drive("", platform_id, false, false, track, event))
	_stack.push(players)


func _open_online() -> void:
	_online = OnlineMenu.new()
	_online.entered_lobby.connect(_open_lobby)
	_stack.push(_online, _online.grab_focus_first)


## The lobby, over the Online menu; leaving it comes back there with the reason, if any.
func _open_lobby() -> void:
	if is_instance_valid(_lobby):
		return
	_lobby = LobbyMenu.new()
	_lobby.left.connect(func(reason: String) -> void:
		_stack.close(_lobby)
		_online.show_status(reason))
	_stack.push(_lobby)


func _open_settings() -> void:
	_stack.push(SettingsMenu.new())


## Menu text size (docs/ACCESSIBILITY.md §2): the whole menu screen scales.
func _apply_text_scale() -> void:
	get_tree().root.content_scale_factor = Players.menu_text_scale()
	theme = UiKit.theme()
	if is_node_ready():
		_fit_buttons.call_deferred()


## The buttons get the screen's height (the logo has the other half); with big text they scroll
## (to the focus).
func _fit_buttons() -> void:
	var list := _buttons.get_child(0) as Control
	_buttons.custom_minimum_size.y = clampf(size.y - 48.0, 120.0, list.get_combined_minimum_size().y)
	# Focus may have scrolled while the area was still small: show the focused button again.
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner()
	if is_inside_tree() and focused and _buttons.is_ancestor_of(focused):
		_buttons.ensure_control_visible(focused)


func _exit_tree() -> void:
	get_tree().root.content_scale_factor = 1.0
