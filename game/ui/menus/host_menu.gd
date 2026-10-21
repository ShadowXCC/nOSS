class_name HostMenu
extends Control
## Hosting a game (MP-01, MP-06): the server's name, password and size, the class, track and
## event, LAN discovery and the router port. This game runs the server and plays at the same
## time; players who don't have the track get it from here (EDT-08). A highway cruise (M7)
## takes a highway track, a highway class and its traffic; an endless road (M9) a road code, an
## endless class and its traffic, and no track. The last settings are remembered (the password
## isn't).

signal closed

const TRAFFIC := [[0, "Off"], [75, "75"], [150, "150"], [250, "250"], [400, "400"]]

var config := ServerConfig.defaults()
var _kind := "free"
var _battle_rule := "standing"
var _battle_min := 5
var _battle_hits := 10
var _track := TrackLibrary.DEFAULT
var _traffic := 150
var _police := false
## The sky of an event other than a race weekend (a race's is in Race settings).
var _sky := RaceEvent.new()
## An endless road's settings (its seed, start biome, traffic).
var _endless := EndlessMenu.last()
var _code: LineEdit
var _rows: Array = []
var _status: Label
var _race_settings: Button
var _list: VBoxContainer


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
	if _kind == "highway" and config.event(0).traffic >= 0:
		_traffic = config.event(0).traffic
	_police = _kind == "highway" and config.event(0).police
	if _kind == "battle":
		_battle_rule = config.event(0).battle_rule
		_battle_min = config.event(0).battle_min if config.event(0).battle_min in [3, 5, 7, 10] else 5
		_battle_hits = config.event(0).battle_hits if config.event(0).battle_hits in [5, 10, 15, 20, 0] else 10
	_sky = config.event(0)
	if _kind == "endless":
		_endless = config.event(0)
	_track = TrackLibrary.resolve(String(config.rotation[0].get("track", "")))
	_list = UiKit.panel(self, "Host", 860)
	_build()


## The rows again (the event changed what the track and class lists offer); the focus stays on
## the control named `focus`.
func _build(focus := "") -> void:
	var fitted := Vector2(0, 600)
	for child in _list.get_children():
		if child is ScrollContainer:
			fitted = (child as ScrollContainer).custom_minimum_size # the panel fitted it to the screen
		if child is ScrollContainer or child is Button or child == _status:
			_list.remove_child(child)
			child.queue_free()
	_rows.clear()
	var type := "highway" if _kind == "highway" else "arena" if _kind == "battle" else "circuit"
	var tracks := TrackLibrary.list(true, false, type) # personal-use tracks stay offline
	if not tracks.any(func(e: Dictionary) -> bool: return e.path == _track):
		_track = tracks[0].path if not tracks.is_empty() else TrackLibrary.DEFAULT
	var list := _list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = fitted
	scroll.set_meta(&"max_height", 600.0)
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
		if (mode.id == "highway") != (_kind == "highway") or (_kind == "battle" and mode.id != "kart") or (_kind == "endless" and mode.id != "endless"):
			continue
		for r: PlatformLoader.Result in GameModes.classes(mode):
			classes.append([r.platform.id, "%s %s" % [mode.name, r.platform.name]])
	if not classes.any(func(c: Array) -> bool: return c[0] == config.rotation[0].get("class", "")) and not classes.is_empty():
		config.rotation[0]["class"] = classes[0][0]
	_add(rows, UiKit.spinner("Event", [["free", "Free drive"], ["race", "Race weekend"], ["highway", "Highway cruise"], ["battle", "Kart battle"],
		["endless", "Endless road"]], _kind,
		func(k: String) -> void:
			var was := _kind
			_kind = k
			if (k in ["highway", "battle", "endless"]) or (was in ["highway", "battle", "endless"]):
				_build.call_deferred("Event"), "Highways, kart battles and endless roads have their own tracks and classes"))
	_add(rows, UiKit.spinner("Class", classes, config.rotation[0].get("class", "official.track.gt"),
		func(id: String) -> void: config.rotation[0]["class"] = id, "How every car drives"))
	if _kind != "endless":
		_add(rows, UiKit.spinner("Track", tracks.map(func(e: Dictionary) -> Array: return [e.path, TrackLibrary.label(e)]), _track,
			func(path: String) -> void: _track = path, "Players without it get it from you"))
	if _kind == "endless":
		var code := UiKit.text_field("Road code", EndlessCode.encode(_endless.road_seed, _endless.biome), func(_t: String) -> void: pass, 24,
			"Type a road code to drive that road", _enter_code)
		_code = code.get_child(1) as LineEdit
		_code.focus_exited.connect(func() -> void: _enter_code(_code.text))
		_add(rows, code)
		_add(rows, UiKit.button("New road", func() -> void:
			_endless.road_seed = EndlessCode.random_seed()
			_build.call_deferred("New road"), "A road nobody has driven"))
		_add(rows, UiKit.spinner("Start in", EndlessBiomes.choices(), _endless.biome, func(v: int) -> void:
			_endless.biome = v
			_code.text = EndlessCode.encode(_endless.road_seed, _endless.biome), "The biome the road starts in"))
		_add(rows, UiKit.spinner("Lanes", EndlessMenu.LANES, _endless.lanes, func(v: int) -> void: _endless.lanes = v, "One or two each way"))
		_add(rows, UiKit.spinner("Drive on", EndlessMenu.SIDES, _endless.drive_side, func(v: String) -> void: _endless.drive_side = v,
			"The side traffic keeps to"))
		_add(rows, UiKit.spinner("Traffic", EndlessMenu.TRAFFIC, _endless.endless_traffic, func(v: String) -> void: _endless.endless_traffic = v,
			"Other cars on the road"))
		_add(rows, UiKit.spinner("Oncoming", [[true, "On"], [false, "Off"]], _endless.oncoming, func(v: bool) -> void: _endless.oncoming = v,
			"Cars coming the other way"))
	elif _kind == "battle":
		_add(rows, UiKit.spinner("Rule", [["standing", "Last one standing"], ["hits", "Most hits"]], _battle_rule,
			func(v: String) -> void:
				_battle_rule = v
				_build.call_deferred("Rule"), "Three lives each, or the most hits"))
		if _battle_rule == "hits":
			_add(rows, UiKit.spinner("Hits to win", KartMenu.HITS_TO_WIN, _battle_hits, func(v: int) -> void: _battle_hits = v,
				"The first to this many wins; None: the most when time's up"))
		_add(rows, UiKit.spinner("Minutes", [[3, "3"], [5, "5"], [7, "7"], [10, "10"]], _battle_min, func(v: int) -> void: _battle_min = v))
	elif _kind == "highway":
		_add(rows, UiKit.spinner("Traffic", TRAFFIC, _traffic, func(n: int) -> void: _traffic = n, "Cars on the road"))
		_add(rows, UiKit.spinner("Police", [[false, "Off"], [true, "On"]], _police, func(v: bool) -> void: _police = v, "Speed traps and chases"))
	else:
		_race_settings = UiKit.button("Race settings", _open_event, "Sessions, laps, AI and rules, the sky")
		_add(rows, _race_settings)
	if _kind != "race":
		for row in SkyRows.rows(_sky):
			_add(rows, row)
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
	UiKit.chain_focus(_rows, focus.is_empty())
	for c: Control in _rows:
		if focus and String(c.accessibility_name).get_slice(":", 0) == focus: # a spinner's is "Event: Free drive"
			UiKit.focus_later(c)


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


## A typed road code: that road, or the last one back if it isn't one.
func _enter_code(text: String) -> void:
	var d := EndlessCode.decode(text)
	if d.is_empty():
		_status.text = "Not a road code"
		_code.text = EndlessCode.encode(_endless.road_seed, _endless.biome)
		return
	_status.text = ""
	if int(d.seed) != _endless.road_seed or int(d.biome) != _endless.biome:
		_endless.road_seed = int(d.seed)
		_endless.biome = int(d.biome)
		_build.call_deferred("Road code")


func _open_event() -> void:
	var menu := EventMenu.new()
	menu.picked.connect(func(_e: RaceEvent) -> void:
		_kind = "race"
		menu.closed.emit())
	UiKit.open_sub(self, menu, func() -> void: _race_settings.grab_focus())


func _host() -> void:
	var e := Settings.last_event() if _kind == "race" else RaceEvent.highway("cruise", _police, _traffic) if _kind == "highway" \
		else RaceEvent.battle(_battle_rule, _battle_min) if _kind == "battle" else RaceEvent.from_dict(_endless.to_dict()) if _kind == "endless" \
		else RaceEvent.free_drive()
	if _kind == "battle":
		e.battle_hits = _battle_hits
	if _kind != "race":
		e.time = _sky.time
		e.time_rate = _sky.time_rate
		e.weather = _sky.weather
	config.rotation[0]["track"] = ServerConfig.ENDLESS if _kind == "endless" else _track
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
