class_name LobbyMenu
extends Control
## An online lobby (docs/NETWORKING.md §5, MP-03, MP-07): the event, everyone in it with their
## car, chat, and Ready. Your own players' rows pick their car; other players' rows mute them,
## and admins can kick or ban from there. The host (or an admin) starts the session.

## Back to the Online menu; `reason` says why if the server ended it.
signal left(reason: String)

var _rows: Array = []
var _players_box: VBoxContainer
var _player_rows: Array = []
var _title: Label
var _event_label: Label
var _host_label: Label
var _status: Label
var _ready_button: Button
var _start_button: Button
var _chat: ChatPanel
var _is_ready := false
var _picked := {} # local index -> package path
var _sub: Control
var _focused_once := false


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, String(Net.lobby.get("name", "Lobby")), 1400)
	_title = list.get_child(0)
	_event_label = UiKit.label("", 26)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(_event_label)
	_host_label = UiKit.label("", 22)
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_label.visible = Net.is_server()
	list.add_child(_host_label)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	list.add_child(columns)
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_col)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	left_col.add_child(scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players_box)
	_ready_button = UiKit.button("Ready", _toggle_ready, "Tell the others you're ready")
	left_col.add_child(_ready_button)
	_start_button = UiKit.button("Start", func() -> void: Net.admin("start"), "Start the session now")
	left_col.add_child(_start_button)
	var leave := UiKit.button("Leave", _leave, "Leave this game" if not Net.is_server() else "Close the server")
	left_col.add_child(leave)
	_chat = ChatPanel.new()
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat.custom_minimum_size = Vector2(560, 0)
	columns.add_child(_chat)
	_status = UiKit.label("", 24)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_status)
	_rows = [_ready_button, _start_button, leave]
	Net.lobby_changed.connect(_refresh)
	Net.notice.connect(_on_notice)
	Net.disconnected.connect(_on_disconnected)
	if Net.host_logic:
		Net.host_logic.port_checked.connect(func(_ok: bool, message: String) -> void: _show_host_info(message))
		_show_host_info("Opening port" if Net.host_logic.config.upnp else "")
	_refresh()
	_rechain(true)


func _exit_tree() -> void:
	Net.lobby_changed.disconnect(_refresh)
	Net.notice.disconnect(_on_notice)
	Net.disconnected.disconnect(_on_disconnected)


func grab_focus_first() -> void:
	(_player_rows[0] if not _player_rows.is_empty() else _ready_button).grab_focus()


func _refresh() -> void:
	var lobby := Net.lobby
	if lobby.is_empty():
		return
	_title.text = String(lobby.get("name", "Lobby"))
	var e := RaceEvent.from_dict(lobby.get("event", {}))
	var what := "Free drive" if e.kind == "free" else "Race, " + e.race_length_text()
	_event_label.text = "%s   %s   %s   %d/%d players" % [what, lobby.get("track_name", ""), lobby.get("class_name", ""), Net.roster.size(), lobby.get("max", 16)]
	_auto_pick()
	var focused := get_viewport().gui_get_focus_owner()
	var focused_id := int(focused.get_meta(&"player", 0)) if focused else 0
	for c in _players_box.get_children():
		c.queue_free()
	_player_rows.clear()
	var refocus: Button
	for p in Net.roster:
		var mine := p.id in Net.my_ids
		var bits := PackedStringArray([p.name, p.car_name if p.car_name else "No car yet"])
		if p.ready:
			bits.append("Ready")
		if p.admin:
			bits.append("Admin")
		if Net.muted.has(p.id):
			bits.append("Muted")
		var b := UiKit.button("", _on_player.bind(p.id), "Pick your car" if mine else "Mute%s" % (", kick or ban" if Net.is_admin() else ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiKit.set_shown_text(b, "●  " + "   ".join(bits))
		var dot := b.get_node(^"Shown") as Label
		dot.add_theme_color_override("font_color", p.color.lerp(Color.WHITE, 0.2))
		b.accessibility_name = ", ".join(bits) + (", you" if mine else "")
		b.set_meta(&"player", p.id)
		_players_box.add_child(b)
		_player_rows.append(b)
		if p.id == focused_id:
			refocus = b
	_start_button.visible = Net.is_admin()
	_rechain(false)
	if refocus:
		refocus.grab_focus.call_deferred()
	elif not _focused_once and not _player_rows.is_empty() and _sub == null:
		_focused_once = true # the list arrived after the menu opened: start on it
		grab_focus_first.call_deferred()


func _rechain(focus_first: bool) -> void:
	UiKit.chain_focus(_player_rows + _rows.slice(0, 2).filter(func(c: Control) -> bool: return c.visible) \
		+ _chat.focusables + [_rows[2]], focus_first)


## Each of this game's players starts with their last car (if this class takes it), else the
## class's default.
func _auto_pick() -> void:
	var platform := PlatformLoader.load_official(String(Net.lobby.get("class", "")))
	for i in Net.my_ids.size():
		if _picked.has(i):
			continue
		var profile := Players.slots[i].profile if i < Players.slots.size() else Settings.primary
		var path := String(profile.data.get("last_car", ""))
		var ok := path and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)) \
			and platform.ok() and Fitting.compatible(platform.platform, PackageLoader.read_manifest(path).get("family", ""))
		if not ok and platform.ok():
			path = GameModes.default_car(platform.platform)
		_picked[i] = path
		Net.pick_car(i, path)


func _on_player(id: int) -> void:
	var local := Array(Net.my_ids).find(id)
	if local >= 0:
		_pick_car(local)
	else:
		_player_actions(id)


func _pick_car(local: int) -> void:
	var picker := CarPicker.new()
	picker.current = String(_picked.get(local, ""))
	var platform := PlatformLoader.load_official(String(Net.lobby.get("class", "")))
	picker.platform = platform.platform if platform.ok() else {}
	picker.picked.connect(func(path: String) -> void:
		_picked[local] = path
		Net.pick_car(local, path)
		var profile := Players.slots[local].profile if local < Players.slots.size() else Settings.primary
		profile.set_value("last_car", path)
		picker.closed.emit())
	_open_sub(picker)


func _player_actions(id: int) -> void:
	var p := Net.player(id)
	if p == null:
		return
	var menu := PlayerActions.new()
	menu.player = p
	_open_sub(menu)


func _open_sub(menu: Control) -> void:
	_sub = menu
	UiKit.open_sub(self, menu, func() -> void:
		_sub = null
		_refresh()
		grab_focus_first())


func _toggle_ready() -> void:
	_is_ready = not _is_ready
	Net.set_ready(_is_ready)
	UiKit.set_shown_text(_ready_button, "Ready ✓" if _is_ready else "Ready")
	_ready_button.accessibility_name = "Ready, on" if _is_ready else "Ready"


func _show_host_info(port_message: String) -> void:
	var port := int(Net.host_logic.config.port) if Net.host_logic else NetProtocol.DEFAULT_PORT
	var addrs := PackedStringArray()
	for ip in UpnpMapper.local_addresses():
		addrs.append(("[%s]:%d" if ip.contains(":") else "%s:%d") % [ip, port])
	_host_label.text = "Join at %s%s" % [", ".join(addrs.slice(0, 3)), ("   " + port_message) if port_message else ""]


func _on_notice(text: String) -> void:
	_status.text = text


func _on_disconnected(reason: String) -> void:
	left.emit(reason)


func _leave() -> void:
	Net.leave()
	left.emit("")


func _unhandled_input(e: InputEvent) -> void:
	if _sub == null and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


## What can be done about another player: mute them, and for admins kick or ban.
class PlayerActions:
	extends Control

	signal closed

	var player: NetPlayer

	func _ready() -> void:
		theme = UiKit.theme_for(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var list := UiKit.panel(self, player.name, 600)
		var rows: Array = []
		var muted := Net.muted.has(player.id)
		rows.append(UiKit.button("Unmute" if muted else "Mute", func() -> void:
			Net.mute(player.id, not muted)
			closed.emit(), "Hide their chat" if not muted else "Show their chat again"))
		if Net.is_admin():
			rows.append(UiKit.button("Kick", func() -> void:
				Net.admin("kick", str(player.id))
				closed.emit(), "They can join again"))
			rows.append(UiKit.button("Ban", func() -> void:
				Net.admin("ban", str(player.id))
				closed.emit(), "They can't come back"))
		rows.append(UiKit.button("Back", func() -> void: closed.emit()))
		for r: Control in rows:
			list.add_child(r)
		UiKit.chain_focus(rows)

	func _unhandled_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			closed.emit()
