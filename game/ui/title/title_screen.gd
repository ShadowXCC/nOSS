extends Control
## Title screen.

@onready var _version_label: Label = %VersionLabel
@onready var _drive_button: Button = %SoloDriveButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _buttons: ScrollContainer = %Buttons

var _classes: ClassPicker
var _tracks: TrackPicker
var _players: PlayersMenu
var _settings: SettingsMenu
var _event: EventMenu
var _free: FreeDriveMenu
var _online: OnlineMenu
var _lobby: LobbyMenu
var _kart_menu: KartMenu
var _solo: SoloMenu
var _mini: MiniGamesMenu
var _sumo_menu: SumoMenu
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
	_drive_button.accessibility_description = "Free drive, races, time trials, highway, kart and endless"
	_drive_button.pressed.connect(_open_solo)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(get_tree().quit)
	var bay_button := Button.new()
	bay_button.name = "FittingBayButton"
	bay_button.text = "Fitting Bay"
	bay_button.accessibility_description = "Import your own car"
	bay_button.custom_minimum_size = _drive_button.custom_minimum_size
	bay_button.pressed.connect(func() -> void: Game.open_fitting_bay())
	_drive_button.add_sibling(bay_button)
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
	garage_button.accessibility_description = "Your cars"
	garage_button.custom_minimum_size = _drive_button.custom_minimum_size
	garage_button.pressed.connect(func() -> void: Game.open_garage())
	_drive_button.add_sibling(garage_button)
	var online_button := Button.new()
	online_button.name = "OnlineButton"
	online_button.text = "Online"
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
	# First boot: the accessibility screen comes before anything else (ACC-09).
	if (not Settings.first_boot_done and DisplayServer.get_name() != "headless" and not Game.dev.has("skip-first-boot")) or Game.dev.get("menu", "") == "access":
		var first := FirstBootMenu.new()
		first.done.connect(func() -> void:
			first.queue_free()
			_drive_button.grab_focus())
		add_child(first)
		return
	match Game.dev.get("menu", ""): # dev: open a menu directly
		"solo": _open_solo()
		"classes": _open_classes("free")
		"event": _open_event(String(Settings.profile.get("last_platform", "official.track.gt")))
		"free": _open_free(String(Settings.profile.get("last_platform", "official.track.gt")))
		"players": _open_players(String(Settings.profile.get("last_platform", "official.track.gt")))
		"settings": _open_settings()
		"online": _open_online()
		"tracks": _open_tracks(func(_t: String) -> void: pass, true)
		"highway": _open_highway()
		"kart": _open_kart()
		"endless": _open_endless()
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


## Solo Drive: the drive modes on this machine (SoloMenu). Shown again on `focus` (a mode) when
## that mode's first screen is backed out of.
func _open_solo(focus := "") -> void:
	if is_instance_valid(_solo):
		_solo.visible = true
		_solo.focus(focus)
		return
	_solo = SoloMenu.new()
	_solo.name = "SoloMenu"
	_solo.chosen.connect(_on_solo_chosen)
	_solo.closed.connect(func() -> void:
		_solo.queue_free()
		_drive_button.grab_focus())
	add_child(_solo)
	if focus:
		_solo.focus(focus)


func _on_solo_chosen(mode: String) -> void:
	_solo.visible = false
	match mode:
		"highway": _open_highway()
		"kart": _open_kart()
		"endless": _open_endless()
		"mini_games": _open_mini_games()
		_: _open_classes(mode)


## Back out of a mode's first screen: Solo Drive, on that mode.
func _back_to_solo() -> void:
	_open_solo(_mode)


## Free Drive: class first (how it drives), then its setup (track, AI, rules), then the players,
## who each pick a car (how it looks). Race: class, then the event (track included), then the players. Time Trial:
## class, then the track, then P1 drives.
func _open_classes(mode: String) -> void:
	_mode = mode
	_classes = ClassPicker.new()
	_classes.current = String(Settings.profile.get("last_platform", ""))
	if mode != "free":
		_classes.mode_filter = "track"
	_classes.picked.connect(_on_class_picked)
	_classes.closed.connect(func() -> void:
		_classes.queue_free()
		_back_to_solo())
	add_child(_classes)


func _on_class_picked(id: String) -> void:
	_classes.visible = false
	if _mode == "race":
		_open_event(id)
	elif _mode == "time_trial":
		Settings.profile.last_platform = id
		_open_tracks(func(track: String) -> void: Game.start_event(RaceEvent.time_trial(), id, track))
	else:
		_open_free(id)


## Free Drive's setup: the track, AI cars and rules.
func _open_free(platform_id: String) -> void:
	_free = FreeDriveMenu.new()
	_free.picked.connect(func(e: RaceEvent, track: String) -> void:
		_free.visible = false
		_open_players(platform_id, e, track))
	_free.closed.connect(func() -> void:
		_free.queue_free()
		if is_instance_valid(_classes):
			_classes.visible = true
			_classes.grab_focus_first()
		else:
			_back_to_solo())
	add_child(_free)


## The track picker, then `then` (track path). With only one track, straight on (unless `always`).
func _open_tracks(then: Callable, always := false) -> void:
	if TrackLibrary.list(true, true, "circuit").size() <= 1 and not always:
		then.call(Game.selected_track("circuit"))
		return
	_tracks = TrackPicker.new()
	_tracks.picked.connect(func(path: String) -> void:
		_tracks.visible = false
		then.call(path))
	_tracks.closed.connect(func() -> void:
		_tracks.queue_free()
		if is_instance_valid(_classes):
			_classes.visible = true
			_classes.grab_focus_first()
		else:
			_back_to_solo())
	add_child(_tracks)


## Highway (M7): the highway first, then what to do on it (HighwayMenu), the class, the players.
func _open_highway() -> void:
	_mode = "highway"
	_tracks = TrackPicker.new()
	_tracks.type = "highway"
	_tracks.picked.connect(func(path: String) -> void:
		_tracks.visible = false
		_open_highway_menu(path))
	_tracks.closed.connect(func() -> void:
		_tracks.queue_free()
		_back_to_solo())
	add_child(_tracks)


func _open_highway_menu(track: String) -> void:
	var menu := HighwayMenu.new()
	menu.track_path = track
	menu.picked.connect(func(e: RaceEvent) -> void:
		menu.visible = false
		_classes = ClassPicker.new()
		_classes.mode_filter = "highway"
		_classes.current = String(Settings.profile.get("last_platform", ""))
		_classes.picked.connect(func(id: String) -> void:
			_classes.visible = false
			Settings.profile.last_platform = id
			_open_players(id, e, track))
		_classes.closed.connect(func() -> void:
			_classes.queue_free()
			menu.visible = true
			menu.grab_focus_first())
		add_child(_classes))
	menu.closed.connect(func() -> void:
		menu.queue_free()
		_tracks.visible = true
		_tracks.grab_focus_first())
	add_child(menu)


## Kart (M8): race, battle or cup and its setup (KartMenu), then the players, who each pick their
## kart's class on their card (D149).
func _open_kart() -> void:
	_mode = "kart"
	var menu := KartMenu.new()
	menu.name = "KartMenu"
	_kart_menu = menu
	menu.picked.connect(func(kind: String, e: RaceEvent, track: String, cup: String) -> void:
		menu.visible = false
		var id := String(Settings.profile.get("last_kart_platform", "official.kart.medium"))
		if kind == "cup":
			_open_players(id, e, "", func() -> void: Game.start_cup_race(CupRun.start(CupRun.load_file(cup), id, e)))
		else:
			_open_players(id, e, track))
	menu.closed.connect(func() -> void:
		menu.queue_free()
		_back_to_solo())
	add_child(menu)


## Endless (M9): the road and its setup (EndlessMenu), the class, the players.
func _open_endless() -> void:
	_mode = "endless"
	var menu := EndlessMenu.new()
	menu.name = "EndlessMenu"
	menu.picked.connect(func(e: RaceEvent) -> void:
		menu.visible = false
		_classes = ClassPicker.new()
		_classes.mode_filter = "endless"
		_classes.current = String(Settings.profile.get("last_platform", ""))
		_classes.picked.connect(func(id: String) -> void:
			_classes.visible = false
			Settings.profile.last_platform = id
			_open_players(id, e, ""))
		_classes.closed.connect(func() -> void:
			_classes.queue_free()
			menu.visible = true
			menu.grab_focus_first())
		add_child(_classes))
	menu.closed.connect(func() -> void:
		menu.queue_free()
		_back_to_solo())
	add_child(menu)


## Mini Games (Changes.md): the short matches that aren't races. Picking one opens its own
## screen; backing out of that shows this list again, and backing out of this shows Solo Drive.
func _open_mini_games() -> void:
	_mode = "mini_games"
	if is_instance_valid(_mini):
		_mini.visible = true
		_mini.grab_focus_first()
		return
	_mini = MiniGamesMenu.new()
	_mini.name = "MiniGamesMenu"
	_mini.chosen.connect(func(game: String) -> void:
		_mini.visible = false
		if game == "sumo":
			_open_sumo())
	_mini.closed.connect(func() -> void:
		_mini.queue_free()
		_back_to_solo())
	add_child(_mini)


## Sumo Wrestling (D162): its settings (SumoMenu), then the players. There is no class to pick:
## the mode has one, and no track: the arena is made from the settings.
func _open_sumo() -> void:
	var menu := SumoMenu.new()
	menu.name = "SumoMenu"
	_sumo_menu = menu
	menu.picked.connect(func(e: RaceEvent) -> void:
		menu.visible = false
		_open_players("official.sumo.standard", e))
	menu.closed.connect(func() -> void:
		menu.queue_free()
		_open_mini_games())
	add_child(menu)


func _open_event(platform_id: String) -> void:
	_event = EventMenu.new()
	_event.picked.connect(func(e: RaceEvent) -> void:
		_event.visible = false
		_open_players(platform_id, e))
	_event.closed.connect(func() -> void:
		_event.queue_free()
		if is_instance_valid(_classes):
			_classes.visible = true
			_classes.grab_focus_first()
		else:
			_back_to_solo())
	add_child(_event)


## The players, then the session (`start` instead, if given: a cup).
func _open_players(platform_id: String, event: RaceEvent = null, track := "", start := Callable()) -> void:
	_players = PlayersMenu.new()
	_players.platform_id = platform_id
	_players.started.connect(func() -> void:
		if start.is_valid():
			start.call()
		elif event and event.kind != "free":
			Game.start_event(event, platform_id, track)
		else:
			Game.start_free_drive("", platform_id, false, false, track, event))
	_players.closed.connect(func() -> void:
		_players.queue_free()
		if _mode == "kart" and is_instance_valid(_kart_menu): # kart: its menu, then the players
			_kart_menu.visible = true
			_kart_menu.grab_focus_first()
		elif _mode == "mini_games" and is_instance_valid(_sumo_menu): # sumo: its menu, then the players
			_sumo_menu.visible = true
			_sumo_menu.grab_focus_first()
		elif _mode in ["highway", "endless"] and is_instance_valid(_classes): # highway, endless: menu, class, players
			_classes.visible = true
			_classes.grab_focus_first()
		elif is_instance_valid(_event):
			_event.visible = true
			_event.grab_focus_first()
		elif is_instance_valid(_free):
			_free.visible = true
			_free.grab_focus_first()
		elif is_instance_valid(_tracks):
			_tracks.visible = true
			_tracks.grab_focus_first()
		elif is_instance_valid(_classes):
			_classes.visible = true
			_classes.grab_focus_first()
		else:
			_back_to_solo())
	add_child(_players)


func _open_online() -> void:
	_online = OnlineMenu.new()
	_online.entered_lobby.connect(_open_lobby)
	_online.closed.connect(func() -> void:
		_online.queue_free()
		_drive_button.get_parent().get_node(^"OnlineButton").grab_focus())
	add_child(_online)


## The lobby, over the Online menu; leaving it comes back there with the reason, if any.
func _open_lobby() -> void:
	if is_instance_valid(_lobby):
		return
	_online.visible = false
	_lobby = LobbyMenu.new()
	_lobby.left.connect(func(reason: String) -> void:
		_lobby.queue_free()
		_online.visible = true
		_online.show_status(reason)
		_online.grab_focus_first())
	add_child(_lobby)


func _open_settings() -> void:
	_settings = SettingsMenu.new()
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings_button.grab_focus())
	add_child(_settings)


## Menu text size (docs/ACCESSIBILITY.md §2): the whole menu screen scales.
func _apply_text_scale() -> void:
	get_tree().root.content_scale_factor = Players.menu_text_scale()
	theme = UiKit.theme()
	if is_node_ready():
		_fit_buttons.call_deferred()


## The buttons get the height left under the title; with big text they scroll (to the focus).
func _fit_buttons() -> void:
	var list := _buttons.get_child(0) as Control
	var others := (_buttons.get_parent() as Control).get_combined_minimum_size().y - _buttons.custom_minimum_size.y
	_buttons.custom_minimum_size.y = clampf(size.y - 48.0 - others, 120.0, list.get_combined_minimum_size().y)
	# Focus may have scrolled while the area was still small: show the focused button again.
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner()
	if is_inside_tree() and focused and _buttons.is_ancestor_of(focused):
		_buttons.ensure_control_visible(focused)


func _exit_tree() -> void:
	get_tree().root.content_scale_factor = 1.0
