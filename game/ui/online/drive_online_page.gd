class_name DriveOnlinePage
extends MenuPage
## Drive Online (docs/UI_FLOW.md §7.1, MP-01, MP-04): Host or Join, and a line saying why the last
## game ended. Hosting goes through the Host page and the event pages; joining through the Join
## page (and a password, when the server has one). Either way the lobby follows (`entered_lobby`),
## and the main menu puts it over this page in place of the pages on the way.
##
## Until the lobby takes local players (P9), "Players" sets who plays on this PC first (LOC-05).

signal entered_lobby

var status: Label
var _players_row: Button


func _init() -> void:
	back_hint = "Back to the main menu"


func _ready() -> void:
	title = "Drive Online"
	crumbs = ["Drive Online"]
	super._ready()
	# Deferred: the page that joined records it first (JoinPage's recent servers).
	Net.joined.connect(_on_joined, CONNECT_DEFERRED)
	Players.slots_changed.connect(_show_players)


func _exit_tree() -> void:
	super._exit_tree()
	Net.joined.disconnect(_on_joined)
	Players.slots_changed.disconnect(_show_players)


func _build() -> void:
	var host := UiKit.button("Host", open_host, "Start a game others can join")
	host.name = "Host"
	add_row(host)
	var join := UiKit.button("Join", open_join, "Find a game on your network or by address")
	join.name = "Join"
	add_row(join)
	_players_row = UiKit.button("Players", open_players, "")
	_players_row.name = "Players"
	add_row(_players_row)
	_show_players()
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)


## Why the last game ended ("Kicked", "Server closed").
func show_status(text: String) -> void:
	status.text = text


func _show_players() -> void:
	var names := PackedStringArray()
	for p: Dictionary in Net.local_players():
		names.append(p.name)
	_players_row.accessibility_description = "Who plays on this PC: " + ", ".join(names)


func open_host() -> HostOptionsPage:
	status.text = ""
	var page := HostOptionsPage.new()
	open_over(page)
	return page


## The Join page, on its tab `which` (an index into JoinPage.TABS).
func open_join(which := 0) -> JoinPage:
	status.text = ""
	var page := JoinPage.new()
	page.tab = which
	open_over(page)
	return page


## The Players screen, for local players to join before going online; "Done" brings them back.
func open_players() -> PlayersMenu:
	var menu := PlayersMenu.new()
	menu.online = true
	menu.platform_id = String(Settings.profile.get("last_platform", "official.track.gt"))
	menu.started.connect(func() -> void: menu.closed.emit())
	open_over(menu, _show_players)
	return menu


## Hosts at once with the last Host settings and event (dev --host; --port and --password apply).
func host_now() -> void:
	var cfg := ServerConfig.from_dict(Settings.net_host) if Settings.net_host is Dictionary and not Settings.net_host.is_empty() else null
	if cfg == null:
		cfg = ServerConfig.defaults()
	if Game.dev.has("port"):
		cfg.port = int(Game.dev.port)
	cfg.password = String(Game.dev.get("password", ""))
	if Net.host(cfg, Net.local_players()) != OK:
		status.text = "Can't open UDP %d" % cfg.port


## Joins `address` at once from the Join page's Direct tab (dev --connect; --password).
func join_now(address: String, password := "") -> void:
	open_join(JoinPage.TABS.find("Direct")).join(address, password)


func _on_joined() -> void:
	if is_inside_tree():
		status.text = ""
		entered_lobby.emit()
