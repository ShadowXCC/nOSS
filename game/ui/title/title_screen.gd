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
var _solo: LocalDrivePage
var _online: DriveOnlinePage
var _lobby: LobbyPage


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
	_open_dev_menu(String(Game.dev.get("menu", "")))
	if Game.reopen_flow: # the results' "Event menu": that event's Settings page, Next focused
		Game.reopen_flow = false
		_open_solo(false).open_flow(EventFlow.from_dict(Game.flow_return))
	elif Net.online(): # back from an online session: its lobby
		_open_online()
		_open_lobby()
	elif Game.net_status: # cut off from a server: why
		_open_online()
		_online.show_status(Game.net_status)
		Game.net_status = ""
	elif Game.dev.has("host"): # dev: host with the last settings and event (--port, --password)
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
		_online.join_now(String(Game.dev.connect), String(Game.dev.get("password", "")))


## Local Drive: the event types on this machine (LocalDrivePage, docs/UI_FLOW.md §5). Not
## `autofocus` when pages go over it straight away (Drive again, back from an event).
func _open_solo(autofocus := true) -> LocalDrivePage:
	_solo = LocalDrivePage.new()
	_solo.name = "LocalDrive"
	_solo.autofocus = autofocus
	_stack.push(_solo)
	return _solo


## Dev --menu (game.gd lists the names): a page opened straight away, those before it under it.
## An event type's name opens its Settings page: "-tt" after it its time trial, "/class" or
## "/players" the page after, "host-" before it the hosting one ("host-regular-tt"). Settings and
## Driving Settings take a tab after "/" ("driving-settings/hud-display").
func _open_dev_menu(menu: String) -> void:
	const TYPES := {
		"regular": ["racing", "regular"], "stock-car": ["racing", "stock_car"], "kart": ["racing", "kart"],
		"custom": ["racing", "custom"], "endless": ["endless", ""], "highway": ["highway", ""], "free": ["free", ""],
		"sumo": ["mini", "sumo"], "drag": ["mini", "drag"], "kart-battle": ["mini", "kart_battle"],
	}
	var page := menu.get_slice("/", 0)
	var then := menu.get_slice("/", 1) if menu.contains("/") else ""
	match page:
		"", "access": pass # access: first boot's screen, opened in _ready
		"local": _open_solo()
		"racing": _open_solo().open_racing()
		"mini-games": _open_solo().open_mini_games()
		"settings":
			_open_settings().show_tab_slug.call_deferred(then) # once the page has its focus
		"driving-settings":
			_open_settings()._open_player().show_tab_slug.call_deferred(then)
		"online": _open_online()
		"host":
			_open_online()
			_online.open_host()
		"host-event":
			_open_online()
			_online.open_host().open_event()
		"join":
			_open_online()
			_online.open_join()
		_:
			var key := page.trim_prefix("host-").trim_suffix("-tt")
			if not TYPES.has(key):
				print("No such --menu: ", menu)
				return
			var type: String = TYPES[key][0]
			var variant: String = TYPES[key][1]
			var tt := page.ends_with("-tt")
			if page.begins_with("host-"):
				_open_online()
				var event := _online.open_host().open_event()
				match type:
					"racing": event.open_racing(tt)._pick(variant)
					"mini": event.open_mini_games()._pick(variant)
					_: event._pick(type)
				return
			var flow := EventFlow.make(type, variant, tt)
			flow.recall()
			_open_solo(false).open_flow(flow, then if then in ["class", "players"] else "settings")


## Drive Online (DriveOnlinePage, docs/UI_FLOW.md §7).
func _open_online() -> void:
	_online = DriveOnlinePage.new()
	_online.name = "DriveOnline"
	_online.entered_lobby.connect(_open_lobby)
	_stack.push(_online)


## The lobby, over Drive Online in place of the pages on the way (Host and the event pages, Join);
## leaving it comes back to Drive Online with the reason, if any.
func _open_lobby() -> void:
	if is_instance_valid(_lobby):
		return
	var above := _stack.index_of(_online) + 1
	if above > 0 and above < _stack.depth():
		_stack.close(_stack.pages()[above])
	_lobby = LobbyPage.new()
	_lobby.name = "Lobby"
	_lobby.left.connect(func(reason: String) -> void:
		_stack.close(_lobby)
		_online.show_status(reason))
	_stack.push(_lobby)


func _open_settings() -> SettingsMenu:
	var settings := SettingsMenu.new()
	_stack.push(settings)
	return settings


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
