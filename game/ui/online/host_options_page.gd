class_name HostOptionsPage
extends MenuPage
## Host (docs/UI_FLOW.md §7.2, MP-01, MP-06): the server's name, password and size, its port, LAN
## discovery and the router port. Next goes on to the event pages (LocalDrivePage, "host"), whose
## last one starts the server: this game runs it and plays at the same time. The options are
## remembered (the password isn't).

var config := ServerConfig.defaults()


func _init() -> void:
	back_hint = "Back to Drive Online"


func _ready() -> void:
	var saved := ServerConfig.from_dict(Settings.net_host) if Settings.net_host is Dictionary and not Settings.net_host.is_empty() else null
	if saved:
		config = saved
		config.password = ""
	if config.name == ServerConfig.new().name:
		config.name = "%s's game" % Settings.primary.display_name()
	config.upnp = (config.upnp if saved else true) and not Game.dev.has("no-upnp") # dev: never ask the router
	if Game.dev.has("port"):
		config.port = int(Game.dev.port)
	title = "Host"
	crumbs = ["Drive Online", "Host"]
	steps = EventFlow.steps_for("host", "racing", "regular")
	step = 0
	super._ready()


func _build() -> void:
	add_row(UiKit.text_field("Name", config.name, func(t: String) -> void:
		config.name = NetChat.clean(t).left(48) if NetChat.clean(t) else "nOSS server", 48, "Shown to players"))
	add_row(UiKit.text_field("Password", "", func(t: String) -> void: config.password = t, 128, "Leave empty for none", Callable(), true))
	var sizes := []
	for n in range(2, NetProtocol.MAX_PLAYERS + 1):
		sizes.append([n, "%d" % n])
	add_row(UiKit.spinner("Players", sizes, clampi(config.max_players, 2, NetProtocol.MAX_PLAYERS), func(n: int) -> void: config.max_players = n,
		"Most players, splitscreen included"))
	var ports := []
	for i in NetDiscovery.PORTS:
		ports.append([NetProtocol.DEFAULT_PORT + i, "UDP %d" % (NetProtocol.DEFAULT_PORT + i)])
	if not ports.any(func(p: Array) -> bool: return p[0] == config.port): # --port
		ports.append([config.port, "UDP %d" % config.port])
	add_row(UiKit.spinner("Port", ports, config.port, func(p: int) -> void: config.port = p, "Two servers on one PC need two ports"))
	add_row(UiKit.spinner("LAN discovery", EventForms.ON, config.lan, func(on: bool) -> void: config.lan = on,
		"Players on your network see this game"))
	add_row(UiKit.spinner("Open port", EventForms.ON, config.upnp, func(on: bool) -> void: config.upnp = on,
		"Ask your router to let players in (UPnP)"))
	var next := UiKit.button("Next", open_event, "Choose the event")
	next.name = "Next"
	add_action(next)


## Next: the event types, these options going with them to the server.
func open_event() -> LocalDrivePage:
	var page := LocalDrivePage.new()
	page.context = "host"
	page.server = config
	open_over(page)
	return page
