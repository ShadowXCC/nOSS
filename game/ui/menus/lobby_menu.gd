class_name LobbyMenu
extends Control
## An online lobby (docs/NETWORKING.md §5, MP-03, MP-07): the event, everyone in it with their
## car, chat, and Ready. Your own players' rows pick their car (and kart class, D149); other players' rows mute them,
## and admins can kick or ban from there. The host (or an admin) starts the session. A track
## that isn't here yet comes first: Ready waits for it ("Getting track 40%", EDT-08).

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
var _track_check := 0.0
## What the Ready button says about the track ("": it's here; "?": not checked yet).
var _track_shown := "?"
## A kart lobby's classes ([[id, name]]) for the server's class, which they're for.
var _classes: Array = []
var _classes_for := "?"


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


## Ready waits for the track: the button says how far it is.
func _process(delta: float) -> void:
	_track_check -= delta
	if _track_check > 0.0:
		return
	_track_check = 0.25
	var text := ""
	if not Net.track_here():
		var h := String(Net.lobby.get("track", ""))
		var progress := Net.content.track_progress(h) if Net.content else 0.0
		text = Net.content.track_refusal(h) if progress < 0.0 else "Getting track %d%%" % roundi(progress * 100.0)
	if text != _track_shown:
		var was_waiting := _track_shown not in ["", "?"]
		_track_shown = text
		_ready_button.disabled = not text.is_empty()
		if text:
			UiKit.set_shown_text(_ready_button, text)
			_ready_button.accessibility_name = text
		else:
			UiKit.set_shown_text(_ready_button, "Ready ✓" if _is_ready else "Ready")
			_ready_button.accessibility_name = "Ready, on" if _is_ready else "Ready"
			if was_waiting:
				_status.text = "Track here"
	if text.is_empty():
		_dev_auto() # the track may have come between lobby updates


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
	var what := "Free drive" if e.kind == "free" else "Battle, " + ("most hits" if e.battle_rule == "hits" else "last one standing") \
		if e.kind == "battle" else "Race, " + e.race_length_text()
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
		if not kart_classes().is_empty():
			bits.append(class_label(p.kart_class))
		if p.ready:
			bits.append("Ready")
		if p.admin:
			bits.append("Admin")
		if Net.muted.has(p.id):
			bits.append("Muted")
		var b := UiKit.button("", _on_player.bind(p.id), ("Pick your car and class" if not kart_classes().is_empty() else "Pick your car") if mine else "Mute%s" % (", kick or ban" if Net.is_admin() else ""))
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
		UiKit.focus_later(refocus)
	elif not _focused_once and not _player_rows.is_empty() and _sub == null:
		_focused_once = true # the list arrived after the menu opened: start on it
		(func() -> void: if is_inside_tree() and is_visible_in_tree(): grab_focus_first()).call_deferred()
	_dev_auto()


## Dev: --auto-ready readies once this game's cars are in; --auto-start (hosting) starts once
## everyone is ready (bots, checks).
func _dev_auto() -> void:
	if Game.dev.has("auto-ready") and not _is_ready and not Net.my_ids.is_empty() and Net.track_here() \
			and Net.roster.filter(func(p: NetPlayer) -> bool: return p.id in Net.my_ids and p.car != "").size() == Net.my_ids.size():
		_toggle_ready()
	if Game.dev.has("auto-start") and Net.host_logic and Net.host_logic.state == "lobby" and Net.host_logic.all_ready() \
			and Net.server.player_count() >= int(Game.dev.get("auto-start", "1")):
		Net.admin("start")


func _rechain(focus_first: bool) -> void:
	UiKit.chain_focus(_player_rows + _rows.slice(0, 2).filter(func(c: Control) -> bool: return c.visible) \
		+ _chat.focusables + [_rows[2]], focus_first)


## Each of this game's players starts with their last car (if this class takes it), else the
## class's default.
func _auto_pick() -> void:
	var platform := Net.platform_result(String(Net.lobby.get("class", "")), String(Net.lobby.get("class_hash", "")))
	for i in Net.my_ids.size():
		if _picked.has(i):
			continue
		var profile := Players.slots[i].profile if i < Players.slots.size() else Settings.primary
		var path := String(profile.data.get("last_car", ""))
		var m := PackageLoader.read_manifest(path) if path else {}
		var ok := path and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)) \
			and platform.ok() and Fitting.compatible(platform.platform, m.get("family", "")) and ContentIndex.shareable(m)
		if not ok and platform.ok():
			path = GameModes.default_car(platform.platform)
		_picked[i] = path
		Net.pick_car(i, path)


func _on_player(id: int) -> void:
	var local := Array(Net.my_ids).find(id)
	if local >= 0 and not kart_classes().is_empty():
		var menu := OwnPick.new()
		menu.lobby = self
		menu.local = local
		menu.player = Net.player(id)
		_open_sub(menu)
	elif local >= 0:
		_pick_car(local)
	else:
		_player_actions(id)


## The classes this lobby's karts pick from ([[id, name]]), none outside karts.
func kart_classes() -> Array:
	var id := String(Net.lobby.get("class", ""))
	if id != _classes_for:
		_classes_for = id
		_classes = GameModes.classes(GameModes.mode_for(id)).map(func(r: PlatformLoader.Result) -> Array: return [r.platform.id, String(r.platform.name)]) \
			if not GameModes.kart_classes(id).is_empty() else []
	return _classes


## A kart class's name ("" is the server's own).
func class_label(id: String) -> String:
	for c: Array in kart_classes():
		if c[0] == id:
			return c[1]
	return String(Net.lobby.get("class_name", ""))


## Player `local`'s kart class: sent with their car.
func pick_class(local: int, id: String) -> void:
	var profile := Players.slots[local].profile if local < Players.slots.size() else Settings.primary
	profile.set_value("kart_class", id)
	if _picked.has(local):
		Net.pick_car(local, String(_picked[local]))


func _pick_car(local: int) -> void:
	var picker := CarPicker.new()
	picker.current = String(_picked.get(local, ""))
	var platform := Net.platform_result(String(Net.lobby.get("class", "")), String(Net.lobby.get("class_hash", "")))
	picker.platform = platform.platform if platform.ok() else {}
	picker.online = true
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
	if not Net.track_here():
		return
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


## Your own player in a kart lobby: their car and class.
class OwnPick:
	extends Control

	signal closed

	var lobby: LobbyMenu
	var local := 0
	var player: NetPlayer

	func _ready() -> void:
		theme = UiKit.theme_for(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var list := UiKit.panel(self, player.name if player else "Player", 600)
		var classes := lobby.kart_classes()
		var mine := player.kart_class if player and player.kart_class else String(Net.lobby.get("class", ""))
		var rows: Array = [
			UiKit.button("Car: " + (player.car_name if player and player.car_name else "None"), func() -> void:
				closed.emit()
				lobby._pick_car(local), "Pick your car"),
			UiKit.spinner("Class", classes, mine, func(id: String) -> void: lobby.pick_class(local, id), "Light pulls hardest, Heavy wins the bumps"),
			UiKit.button("Back", func() -> void: closed.emit()),
		]
		for r: Control in rows:
			list.add_child(r)
		UiKit.chain_focus(rows)

	func _unhandled_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			closed.emit()


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
