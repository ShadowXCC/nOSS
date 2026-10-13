class_name HostMenu
extends Control
## Hosting a game (MP-01, MP-06): the server's name, password and size, the class, track and
## event, LAN discovery and the router port. This game runs the server and plays at the same
## time; players who don't have the track get it from here (EDT-08). The last settings are
## remembered (the password isn't).

signal closed

var config := ServerConfig.defaults()
var _kind := "free"
var _track := TrackLibrary.DEFAULT
var _rows: Array = []
var _status: Label
var _race_settings: Button


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved := ServerConfig.from_dict(Settings.net_host) if Settings.net_host is Dictionary and not Settings.net_host.is_empty() else null
	if saved:
		config = saved
		config.password = ""
	if config.name == ServerConfig.new().name:
		config.name = "%s's game" % Settings.primary.display_name()
	config.upnp = (config.upnp if saved else true) and not Game.dev.has("no-upnp") # dev: never ask the router
	if Game.dev.has("port"):
		config.port = int(Game.dev.port)
	_kind = config.event(0).kind
	var tracks := TrackLibrary.list(true, false, "circuit") # personal-use tracks stay offline
	var last := TrackLibrary.resolve(String(config.rotation[0].get("track", "")))
	if tracks.any(func(e: Dictionary) -> bool: return e.path == last):
		_track = last
	var list := UiKit.panel(self, "Host", 860)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_add(rows, UiKit.text_field("Name", config.name, func(t: String) -> void:
		config.name = NetChat.clean(t).left(48) if NetChat.clean(t) else "nOSS server", 48, "Shown to players"))
	_add(rows, UiKit.text_field("Password", "", func(t: String) -> void: config.password = t, 128, "Leave empty for none", Callable(), true))
	var sizes := []
	for n in range(2, NetProtocol.MAX_PLAYERS + 1):
		sizes.append([n, "%d" % n])
	_add(rows, UiKit.spinner("Players", sizes, clampi(config.max_players, 2, 16), func(n: int) -> void: config.max_players = n, "Most players, splitscreen included"))
	var classes := []
	for mode in GameModes.list():
		for r: PlatformLoader.Result in GameModes.classes(mode):
			classes.append([r.platform.id, "%s %s" % [mode.name, r.platform.name]])
	_add(rows, UiKit.spinner("Class", classes, config.rotation[0].get("class", "official.track.gt"),
		func(id: String) -> void: config.rotation[0]["class"] = id, "How every car drives"))
	_add(rows, UiKit.spinner("Track", tracks.map(func(e: Dictionary) -> Array: return [e.path, TrackLibrary.label(e)]), _track,
		func(path: String) -> void: _track = path, "Players without it get it from you"))
	_add(rows, UiKit.spinner("Event", [["free", "Free drive"], ["race", "Race weekend"]], _kind,
		func(k: String) -> void: _kind = k))
	_race_settings = UiKit.button("Race settings", _open_event, "Sessions, laps, AI and rules")
	_add(rows, _race_settings)
	var ports := []
	for i in NetDiscovery.PORTS:
		ports.append([NetProtocol.DEFAULT_PORT + i, "UDP %d" % (NetProtocol.DEFAULT_PORT + i)])
	_add(rows, UiKit.spinner("Port", ports, config.port, func(p: int) -> void: config.port = p, "Two servers on one PC need two ports"))
	_add(rows, UiKit.check("LAN discovery", config.lan, func(on: bool) -> void: config.lan = on, "Players on your network see this game"))
	_add(rows, UiKit.check("Open port", config.upnp, func(on: bool) -> void: config.upnp = on, "Ask your router to let players in (UPnP)"))
	_status = UiKit.label("", 24)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	list.add_child(_status)
	var host := UiKit.button("Start hosting", _host, "Start the server and open the lobby")
	list.add_child(host)
	_rows.append(host)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


func _open_event() -> void:
	var menu := EventMenu.new()
	menu.picked.connect(func(_e: RaceEvent) -> void:
		_kind = "race"
		menu.closed.emit())
	UiKit.open_sub(self, menu, func() -> void: _race_settings.grab_focus())


func _host() -> void:
	var e := Settings.last_event() if _kind == "race" else RaceEvent.free_drive()
	config.rotation[0]["track"] = _track
	config.rotation[0]["event"] = e.to_dict()
	var saved := config.to_dict()
	saved.password = ""
	Settings.set_value("net_host", saved)
	if Net.host(config, Net.local_players()) != OK:
		_status.text = "Can't open UDP %d" % config.port
		return
	closed.emit()


func grab_focus_first() -> void:
	(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
