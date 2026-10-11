class_name OnlineMenu
extends Control
## Online (MP-01, MP-04, docs/NETWORKING.md §3): host a game, join one by its address, or pick
## one found on the LAN. Everyone joined on this machine's Players screen comes along (LOC-05).

signal entered_lobby
signal closed

var _rows: Array = []
var _list_rows: Array = []
var _status: Label
var _players_label: Label
var _lan: VBoxContainer
var _password_edit: LineEdit
var _join_button: Button
var _scanner: NetDiscovery.Scanner
var _address := ""
var _password := ""


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_address = Settings.net_address
	var list := UiKit.panel(self, "Online", 900)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_players_label = UiKit.label("", 24)
	rows.add_child(_players_label)
	_add(rows, UiKit.button("Players", _open_players, "Who plays on this machine"))
	_add(rows, UiKit.button("Host", _open_host, "Start a game others can join"))
	var address := UiKit.text_field("Address", _address, func(t: String) -> void: _address = t, 80,
		"IP or name, and :port if not 47800", func(_t: String) -> void: _join(_address, _password))
	_add(rows, address)
	var password := UiKit.text_field("Password", "", func(t: String) -> void: _password = t, 128,
		"Only if the server has one", func(_t: String) -> void: _join(_address, _password), true)
	_password_edit = password.get_child(1)
	_add(rows, password)
	_join_button = UiKit.button("Join", func() -> void: _join(_address, _password), "Join the server at this address")
	_add(rows, _join_button)
	var heading := UiKit.label("On your network", 26)
	heading.modulate = UiKit.ACCENT
	rows.add_child(heading)
	_lan = VBoxContainer.new()
	rows.add_child(_lan)
	_status = UiKit.label("", 24)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_status)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	_scanner = NetDiscovery.Scanner.new()
	add_child(_scanner)
	_scanner.start()
	_scanner.changed.connect(_rebuild_lan)
	Net.joined.connect(_on_joined)
	Net.disconnected.connect(_on_failed)
	Players.slots_changed.connect(_show_players)
	_show_players()
	_rebuild_lan()
	(func() -> void: if is_inside_tree() and is_visible_in_tree(): grab_focus_first()).call_deferred()


func _exit_tree() -> void:
	Net.joined.disconnect(_on_joined)
	Net.disconnected.disconnect(_on_failed)
	Players.slots_changed.disconnect(_show_players)


## Back from the lobby: why it ended, if it did.
func show_status(text: String) -> void:
	_status.text = text


func grab_focus_first() -> void:
	(_rows[0] as Control).grab_focus()


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


func _show_players() -> void:
	var names := PackedStringArray()
	for p: Dictionary in Net.local_players():
		names.append(p.name)
	_players_label.text = "Playing: " + ", ".join(names)


func _rebuild_lan() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_key := String(focused.get_meta(&"server", "")) if focused else ""
	for c in _lan.get_children():
		c.queue_free()
	_list_rows.clear()
	var refocus: Button
	for key: String in _scanner.servers:
		var s: Dictionary = _scanner.servers[key]
		var text := "%s   %d/%d   %s, %s%s" % [s.name, s.players, s.max, s["class"], s.track, "   (password)" if s.password else ""]
		var b := UiKit.button("", _join.bind("%s:%d" % [s.ip, s.port], ""), "%s at %s:%d" % [s.state.capitalize(), s.ip, s.port])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiKit.set_shown_text(b, text)
		b.accessibility_name = "%s, %d of %d players, %s, %s%s" % [s.name, s.players, s.max, s["class"], s.track, ", password" if s.password else ""]
		b.set_meta(&"server", key)
		if s.version != NetProtocol.game_version():
			b.disabled = true
			b.accessibility_description = "Version %s" % s.version
		_lan.add_child(b)
		_list_rows.append(b)
		if key == focused_key:
			refocus = b
	if _list_rows.is_empty():
		_lan.add_child(UiKit.label("None found", 24))
	var all: Array = _rows.slice(0, _rows.size() - 1) + _list_rows + [_rows[-1]]
	UiKit.chain_focus(all, false)
	if refocus:
		UiKit.focus_later(refocus)
	elif focused_key and is_inside_tree():
		UiKit.focus_later(_join_button)
	elif focused == null and is_visible_in_tree():
		(func() -> void: if is_inside_tree() and is_visible_in_tree(): grab_focus_first()).call_deferred()


func _join(address: String, password: String) -> void:
	var at := NetProtocol.parse_address(address)
	if at.is_empty():
		_status.text = "Enter an address"
		return
	Settings.set_value("net_address", address.strip_edges())
	_status.text = "Joining %s" % address.strip_edges()
	if password.is_empty():
		password = _password
	if Net.join(at.host, at.port, Net.local_players(), password) != OK:
		_status.text = "Can't reach %s" % address


func _on_joined() -> void:
	_status.text = ""
	entered_lobby.emit()


func _on_failed(reason: String) -> void:
	_status.text = reason
	if reason == "Password needed" or reason == "Wrong password":
		_password_edit.grab_focus()


## Hosts at once with the last Host settings (dev --host; --port and --password apply).
func host_now() -> void:
	var cfg := ServerConfig.from_dict(Settings.net_host) if Settings.net_host is Dictionary and not Settings.net_host.is_empty() else null
	if cfg == null:
		cfg = ServerConfig.defaults()
	if Game.dev.has("port"):
		cfg.port = int(Game.dev.port)
	cfg.password = String(Game.dev.get("password", ""))
	if Net.host(cfg, Net.local_players()) != OK:
		_status.text = "Can't open UDP %d" % cfg.port


func _open_host() -> void:
	var host := HostMenu.new() # once hosting, Net.joined opens the lobby
	UiKit.open_sub(self, host, func() -> void: (_rows[1] as Control).grab_focus())


## The Players screen, for local players to join before going online; "Ready" brings them back.
func _open_players() -> void:
	var menu := PlayersMenu.new()
	menu.platform_id = String(Settings.profile.get("last_platform", "official.track.gt"))
	menu.started.connect(func() -> void: menu.closed.emit())
	UiKit.open_sub(self, menu, func() -> void:
		_show_players()
		(_rows[0] as Control).grab_focus())


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
