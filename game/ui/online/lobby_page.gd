class_name LobbyPage
extends MenuPage
## An online lobby (docs/UI_FLOW.md §7.5, §7.6; docs/NETWORKING.md §5; MP-03, MP-07, LOC-05): the
## event, everyone in the game on the left (colour, car, device, assists, ping, ready), chat on
## the right, and "This PC" under the roster: P1's own rows on the page, and a card for each other
## player here in their own view, driven by their own devices, with a "Press to join" place for
## one more. Each player readies on their own; once everyone has, the server counts down and
## starts (NetHost). The host can change the event, keep a playlist and force a start. A track that
## isn't here yet comes first: Ready waits for it ("Getting track 40%", EDT-08).
##
## The main window is P1's, as on every page: the keys and pads of this PC's other players, and
## pads nobody has yet (pressed to join), don't move its focus.

## Back to Drive Online; `reason` says why if the server ended it ("" when left).
signal left(reason: String)

## Another player's card is laid out at this size, then scaled to its place.
const CARD_REF := Vector2(520, 560)
## The cards' height: this share of the page's, at most CARD_MAX.
const CARD_SHARE := 0.34
const CARD_MAX := 380.0
## A roster row's car thumbnail.
const THUMB := Vector2(96, 54)
## What the roster says for each device (NetPlayer.device), and the glyph that stands for it.
const DEVICE_WORDS := { "keyboard": "keyboard", "xbox": "controller", "playstation": "controller", "wheel": "wheel" }
const DEVICE_GLYPHS := { "keyboard": "arrows", "xbox": "left_stick", "playstation": "left_stick" }

var event_label: Label
var host_label: Label
var status: Label
var chat: ChatPanel
## Host: Change event and Playlist; admins: Force start.
var change_button: Button
var playlist_button: Button
var start_button: Button
var leave_button: Button

var _roster_box: VBoxContainer
var _roster_rows: Array[Button] = []
var _p1_box: VBoxContainer
var _p1_rows: Array[Control] = []
var _chat_place: VBoxContainer # in the body, for chat when there's no room for the pane
var _chat_pane: VBoxContainer
var _strip: HBoxContainer
var _join_holder: PanelContainer
var _cards := {} # PlayerSlot -> PlayerView (P2-P4)
var _expand_layer := Control.new()
var _expanded: PlayerView
var _car_buttons := {} # PlayerSlot -> its Car row
var _ready_buttons := {} # PlayerSlot -> its Ready row
var _picked := {} # PlayerSlot -> the package path picked for them
var _picked_for := {} # PlayerSlot -> the profile id their pick was for
var _picked_class := "?" # the lobby's class the picks were made for
var _sent := {} # PlayerSlot -> the PLAYER_INFO last sent
var _thumbs := {} # car hash -> Texture2D (null: not here yet)
var _auto_ready := {} # dev: player id -> when it was last asked to ready (ms)
var _track_check := 0.0
var _track_text := "?" # what Ready says about the track ("": it's here; "?": not checked yet)
var _was_starting := 0
var _roster_seen := false
var _classes: Array = []
var _classes_for := "?"


func _init() -> void:
	back_text = "" # Leave is in the action bar
	autofocus = false # the roster's first row, once it's here (_show_roster)


func _ready() -> void:
	Players.primary_slot()
	title = String(Net.lobby.get("name", "Lobby"))
	crumbs = ["Drive Online", "Lobby"]
	_show_steps()
	super._ready()
	_expand_layer.name = "Expanded"
	_expand_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_expand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_expand_layer)
	Net.lobby_changed.connect(_refresh)
	Net.notice.connect(_on_notice)
	Net.disconnected.connect(_on_disconnected)
	Players.joined.connect(_on_joined)
	Players.left.connect(_on_left)
	Players.slots_changed.connect(_on_slots_changed)
	if Net.content:
		Net.content.car_changed.connect(_on_car_changed)
	visibility_changed.connect(_route_input)
	resized.connect(_place_chat)
	resized.connect(_place_cards)
	if Net.host_logic:
		Net.host_logic.port_checked.connect(func(_ok: bool, message: String) -> void: _show_host_info(message))
		_show_host_info("Opening port" if Net.host_logic.config.upnp else "")
		if Game.dev.has("auto-start"): # dev: the countdown waits for this many players
			Net.host_logic.min_players = maxi(int(Game.dev["auto-start"]), 1)
	_build_cards()
	_route_input()
	_place_chat.call_deferred()
	_refresh()
	(func() -> void: # no list yet: the first row until it comes
		if is_inside_tree() and UiKit.focus_owner(self) == null:
			focus_first()).call_deferred()


func _exit_tree() -> void:
	super._exit_tree()
	Net.lobby_changed.disconnect(_refresh)
	Net.notice.disconnect(_on_notice)
	Net.disconnected.disconnect(_on_disconnected)
	Players.joined.disconnect(_on_joined)
	Players.left.disconnect(_on_left)
	Players.slots_changed.disconnect(_on_slots_changed)
	if Net.content and Net.content.car_changed.is_connected(_on_car_changed):
		Net.content.car_changed.disconnect(_on_car_changed)
	Players.joining = false
	Players.adding = null
	for slot in Players.slots:
		slot.menu_target = null


func _build() -> void:
	event_label = add_text("")
	event_label.name = "Event"
	host_label = add_text("")
	host_label.name = "HostInfo"
	host_label.visible = Net.is_server()
	add_heading("Players")
	_roster_box = VBoxContainer.new()
	_roster_box.name = "Roster"
	body.add_child(_roster_box)
	change_button = UiKit.button("Change event", change_event, "Pick another event to run next")
	change_button.name = "ChangeEvent"
	playlist_button = UiKit.button("Playlist", open_playlist, "Events to run one after another")
	playlist_button.name = "Playlist"
	start_button = UiKit.button("Force start", func() -> void: Net.admin("start"), "Start now, ready or not")
	start_button.name = "ForceStart"
	for b: Button in [change_button, playlist_button, start_button]:
		b.custom_minimum_size.y = UiKit.ROW_HEIGHT
		body.add_child(b)
	change_button.visible = Net.is_server()
	playlist_button.visible = Net.is_server()
	start_button.visible = Net.is_admin()
	add_heading("This PC")
	_p1_box = VBoxContainer.new()
	_p1_box.name = "ThisPC"
	body.add_child(_p1_box)
	_chat_place = VBoxContainer.new()
	_chat_place.name = "ChatPlace"
	body.add_child(_chat_place)
	chat = ChatPanel.new()
	chat.name = "Chat"
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_pane = VBoxContainer.new()
	_chat_pane.name = "ChatPane"
	_chat_pane.add_child(chat)
	set_pane(_chat_pane)
	_strip = HBoxContainer.new()
	_strip.name = "Strip"
	_strip.add_theme_constant_override(&"separation", 16)
	add_footer(_strip)
	_join_holder = PanelContainer.new()
	_join_holder.name = "JoinSlot"
	_join_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join := UiKit.label("Press to join", 28)
	join.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	join.modulate = Color(1, 1, 1, 0.6)
	_join_holder.add_child(join)
	_strip.add_child(_join_holder)
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)
	leave_button = UiKit.button("Leave", leave, "Close the server" if Net.is_server() else "Leave this game")
	leave_button.name = "Leave"
	add_action(leave_button)
	_build_p1()


## The roster, the host's buttons, P1's rows, chat, then Leave.
func _focus_list() -> Array:
	var list: Array = []
	list.append_array(_roster_rows)
	for b: Button in [change_button, playlist_button, start_button]:
		if b.visible:
			list.append(b)
	list.append_array(_p1_rows)
	list.append_array(chat.focusables)
	list.append_array(_action_list)
	return list


## "Step 5 of 5" when hosting (the event's own count: Stock Car has no Class step).
func _show_steps() -> void:
	if not Net.is_server():
		return
	var class_id := String(Net.lobby.get("class", Net.host_logic.platform_id() if Net.host_logic else ""))
	var picked_here := not (class_id in [EventFlow.STOCK_CAR, EventFlow.SUMO] or not GameModes.kart_classes(class_id).is_empty())
	steps = PackedStringArray(["Host", "Event", "Settings"] + (["Class"] if picked_here else []) + ["Lobby"])
	step = steps.size() - 1


func _process(delta: float) -> void:
	_track_check -= delta
	if _track_check > 0.0:
		return
	_track_check = 0.25
	_show_track()
	_send_infos() # a player's device is the one they used last
	_route_input()


## Ready waits for the track: its rows say how far it is.
func _show_track() -> void:
	var text := ""
	if not Net.track_here():
		var h := String(Net.lobby.get("track", ""))
		var progress := Net.content.track_progress(h) if Net.content else 0.0
		text = Net.content.track_refusal(h) if progress < 0.0 else "Getting track %d%%" % roundi(progress * 100.0)
	if text != _track_text:
		var was_waiting := _track_text not in ["", "?"]
		_track_text = text
		for slot: PlayerSlot in _ready_buttons:
			_show_ready(slot)
		if text.is_empty() and was_waiting:
			status.text = "Track here"
	if text.is_empty():
		_dev_auto() # the track may have come between lobby updates


## Everything from the lobby the server last sent.
func _refresh() -> void:
	var lobby := Net.lobby
	if lobby.is_empty():
		return
	title = String(lobby.get("name", "Lobby"))
	_show_steps()
	refresh_header()
	var e := RaceEvent.from_dict(lobby.get("event", {}))
	var about := PackedStringArray([event_text(e, String(lobby.get("class", "")))])
	if e.kind not in ["sumo", "drag"]: # their ground is made from the settings: no track
		about.append(String(lobby.get("track_name", "")))
	about.append_array([String(lobby.get("class_name", "")), "%d/%d players" % [Net.roster.size(), lobby.get("max", 16)]])
	event_label.text = "   ".join(Array(about).filter(func(b: String) -> bool: return not b.is_empty()))
	if String(lobby.get("class", "")) != _picked_class:
		_picked_class = String(lobby.get("class", ""))
		_picked.clear() # another class: each player's car again, and a kart lobby's Class rows
		_build_p1()
		for v: PlayerView in _cards.values():
			_card_of(v).rebuild()
	_auto_pick()
	_send_infos()
	_show_roster()
	change_button.visible = Net.is_server()
	playlist_button.visible = Net.is_server()
	start_button.visible = Net.is_admin()
	for slot: PlayerSlot in _car_buttons:
		_show_car(slot)
	for slot: PlayerSlot in _ready_buttons:
		_show_ready(slot)
	var starting := int(lobby.get("starting", 0))
	if starting > 0:
		status.text = "Starting in %d" % starting
	elif _was_starting > 0 and String(lobby.get("state", "lobby")) == "lobby":
		status.text = "Start held: not everyone's ready"
	_was_starting = starting
	chain(false)
	_dev_auto()


## What the lobby's event is: "Stock Car race, 10 laps", "Kart Battle, most hits", "Highway
## cruise", "Drag Strip, 1/4 mile". Endless says nothing: its track's name does ("Endless
## FOREST-0000001").
static func event_text(e: RaceEvent, class_id: String) -> String:
	match e.kind:
		"race":
			var what := "Kart race" if not GameModes.kart_classes(class_id).is_empty() else "Stock Car race" if class_id == EventFlow.STOCK_CAR else "Race"
			return "%s, %s" % [what, e.race_length_text()]
		"battle":
			return "Kart Battle, " + ("most hits" if e.battle_rule == "hits" else "last one standing")
		"highway":
			for m: Array in EventForms.HIGHWAY_MODES:
				if m[0] == e.sub:
					return "Highway " + String(m[1]).to_lower()
			return "Highway"
		"endless":
			return ""
		"sumo":
			return "Sumo Wrestling"
		"drag":
			var length := EventForms.nearest(EventForms.DRAG_LENGTHS, e.drag_length_m)
			for l: Array in EventForms.DRAG_LENGTHS:
				if l[0] == length:
					return "Drag Strip, " + String(l[1] if Settings.units == "imperial" else l[2])
	return "Free Drive"


# --- The roster ---


## A row per player: built again when someone comes or goes, else brought up to date in place
## (a screen reader on a row isn't sent back to the top every ping).
func _show_roster() -> void:
	var ids := Net.roster.map(func(p: NetPlayer) -> int: return p.id)
	var shown := _roster_rows.map(func(b: Button) -> int: return int(b.get_meta(&"player")))
	if ids == shown:
		for i in ids.size():
			_fill_row(_roster_rows[i], Net.roster[i])
		return
	var focus := UiKit.focus_owner(self)
	var focused_id := int(focus.get_meta(&"player", 0)) if focus and _roster_box.is_ancestor_of(focus) else 0
	var was_in_roster := focus != null and _roster_box.is_ancestor_of(focus)
	var old := _roster_rows.duplicate()
	_roster_rows.clear()
	var refocus: Button
	for p in Net.roster:
		var b := _roster_row(p)
		_roster_box.add_child(b)
		_roster_rows.append(b)
		if p.id == focused_id:
			refocus = b
	chain(false)
	if refocus:
		refocus.grab_focus()
	elif was_in_roster and not _roster_rows.is_empty():
		_roster_rows[0].grab_focus()
	elif not _roster_seen and not _roster_rows.is_empty() and is_visible_in_tree() and _expanded == null:
		_roster_rows[0].grab_focus() # the list came after the page opened: start on it
	_roster_seen = _roster_seen or not _roster_rows.is_empty()
	for b: Button in old:
		_roster_box.remove_child(b)
		b.queue_free()


func _roster_row(p: NetPlayer) -> Button:
	var b := Button.new()
	b.name = "Player%d" % p.id
	b.custom_minimum_size.y = UiKit.ROW_HEIGHT
	b.set_meta(&"player", p.id)
	b.pressed.connect(_on_player.bind(p.id))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.add_theme_constant_override(&"separation", 16)
	b.add_child(row)
	var dot := _row_label("Dot", "●")
	row.add_child(dot)
	var frame := PanelContainer.new()
	frame.name = "Thumb"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.3) # the placeholder until the car's picture is here
	box.set_corner_radius_all(6)
	frame.add_theme_stylebox_override(&"panel", box)
	var thumb := TextureRect.new()
	thumb.name = "Picture"
	thumb.custom_minimum_size = THUMB
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(thumb)
	row.add_child(frame)
	var who := _row_label("Who", "")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(who)
	for part in ["Device", "Assists"]:
		var icons := HBoxContainer.new()
		icons.name = part
		icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		icons.add_theme_constant_override(&"separation", 6)
		row.add_child(icons)
	row.add_child(_row_label("Ping", ""))
	var ready := _row_label("Ready", "")
	ready.add_theme_color_override(&"font_color", UiKit.ACCENT)
	row.add_child(ready)
	_fill_row(b, p)
	return b


func _row_label(node_name: String, text: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A roster row as `p` is now. Its accessible name says it all: "Ana, Saleen S7, controller, ABS,
## 42 ms, ready".
func _fill_row(b: Button, p: NetPlayer) -> void:
	var row := b.get_node(^"Row")
	(row.get_node(^"Dot") as Label).add_theme_color_override(&"font_color", p.color.lerp(Color.WHITE, 0.2))
	(row.get_node(^"Thumb/Picture") as TextureRect).texture = _thumb(p)
	var car := p.car_name if p.car_name else "No car yet"
	if not kart_classes().is_empty():
		car += " · " + class_label(p.kart_class)
	(row.get_node(^"Who") as Label).text = "%s   %s" % [p.name, car]
	var device := String(DEVICE_WORDS.get(p.device, ""))
	_set_icons(row.get_node(^"Device"), [{ "id": DEVICE_GLYPHS.get(p.device, ""), "text": device.capitalize() }] if device else [],
		p.device if p.device in Glyphs.FAMILIES else "keyboard")
	var assists := PackedStringArray()
	for a in p.assists:
		if ResultsMenu.ASSIST_NAMES.has(a):
			assists.append(ResultsMenu.ASSIST_NAMES[a])
	_set_icons(row.get_node(^"Assists"), Array(assists).map(func(n: String) -> Dictionary: return { "id": "", "text": n }), "keyboard")
	var ping := "host" if p.peer == 1 else "%d ms" % p.ping
	(row.get_node(^"Ping") as Label).text = ping
	(row.get_node(^"Ready") as Label).text = "Ready" if p.ready else ""
	var bits := PackedStringArray([p.name, car])
	if device:
		bits.append(device)
	bits.append_array(assists)
	bits.append(ping)
	if p.ready:
		bits.append("ready")
	if p.admin:
		bits.append("admin")
	if Net.muted.has(p.id):
		bits.append("muted")
	b.accessibility_name = ", ".join(bits)
	var local := Net.local_of(p.id)
	b.accessibility_description = "Your car and Ready are under This PC" if local == 0 else "On this PC" if local > 0 \
		else "Mute%s" % (", kick or ban" if Net.is_admin() else "")


## `box`'s icons: a glyph or a text chip each (`inputs`: [{id, text}]), made again only when they
## change.
func _set_icons(box: Control, inputs: Array, family: String) -> void:
	var key := JSON.stringify([inputs, family])
	if box.get_meta(&"shown", "") == key:
		return
	box.set_meta(&"shown", key)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for input: Dictionary in inputs:
		var icon := Glyphs.icon(input, family, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)


## A player's car picture: their package's own for this PC's, the downloaded car's for others'
## (null, the placeholder, until it's here).
func _thumb(p: NetPlayer) -> Texture2D:
	if p.car.is_empty():
		return null
	if not _thumbs.has(p.car): # again once more of the car is here (_on_car_changed)
		var path := ""
		var local := Net.local_of(p.id)
		if local >= 0 and local < Players.slots.size():
			path = String(_picked.get(Players.slots[local], ""))
		if path.is_empty() and Net.content:
			path = String(Net.content.car(p.car).get("path", ""))
		_thumbs[p.car] = GarageFiles.thumbnail(path) if path else null
	return _thumbs[p.car]


func _on_car_changed(car_hash: String) -> void:
	if _thumbs.has(car_hash) and _thumbs[car_hash] == null:
		_thumbs.erase(car_hash)
		_show_roster.call_deferred()


func _on_player(id: int) -> void:
	var local := Net.local_of(id)
	if local == 0 and _car_buttons.has(Players.slots[0]):
		(_car_buttons[Players.slots[0]] as Button).grab_focus()
	elif local < 0:
		var p := Net.player(id)
		if p:
			var page := PlayerActions.new()
			page.player = p
			open_over(page)


# --- This PC ---


## P1's rows, under "This PC" (again after a change of profile or class, the focus kept).
func _build_p1() -> void:
	var slot := Players.slots[0] if not Players.slots.is_empty() else null
	if slot == null:
		return
	var focus := UiKit.focus_owner(self) if is_inside_tree() else null
	var keep := UiKit.text_of(focus).get_slice(" ", 0) if focus is Button and _p1_box.is_ancestor_of(focus) else ""
	var old := _p1_box.get_children()
	_p1_rows.clear()
	var head := HBoxContainer.new()
	head.name = "Head"
	var tag := UiKit.label(slot.tag(), 34)
	tag.add_theme_color_override(&"font_color", slot.color())
	head.add_child(tag)
	head.add_child(UiKit.label(slot.display_name(), 34))
	_p1_box.add_child(head)
	for c: Control in card_rows(slot):
		c.custom_minimum_size.y = UiKit.ROW_HEIGHT
		_p1_box.add_child(c)
		_p1_rows.append(c)
	chain(false)
	if keep:
		for c: Control in _p1_rows:
			if c is Button and UiKit.text_of(c).begins_with(keep):
				c.grab_focus()
				break
	for c in old:
		_p1_box.remove_child(c)
		c.queue_free()


## A local player's rows: Profile, Car, (a kart lobby's Class), Controls, Driving Settings, Ready,
## and for P2-P4, Leave.
func card_rows(slot: PlayerSlot) -> Array[Control]:
	var rows: Array[Control] = []
	var used := Players.slots.filter(func(s: PlayerSlot) -> bool: return s != slot).map(func(s: PlayerSlot) -> String: return s.profile.id)
	var profiles := []
	for id in Settings.profile_ids():
		if id not in used:
			profiles.append([id, Settings.get_profile(id).display_name()])
	profiles.append(["+new", "New profile"])
	rows.append(UiKit.spinner("Profile", profiles, slot.profile.id, func(id: String) -> void:
		Players.set_profile(slot, Settings.new_profile() if id == "+new" else Settings.get_profile(id)), "Who's playing"))
	var car := UiKit.button("Car", _pick_car.bind(slot), "Pick your car")
	car.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_car_buttons[slot] = car
	_show_car(slot)
	rows.append(car)
	if not kart_classes().is_empty():
		var mine := String(slot.profile.data.get("kart_class", ""))
		if not kart_classes().any(func(c: Array) -> bool: return c[0] == mine):
			mine = String(Net.lobby.get("class", ""))
		rows.append(UiKit.spinner("Class", kart_classes(), mine, func(id: String) -> void: pick_class(slot, id),
			"Light pulls hardest, Heavy wins the bumps"))
	rows.append(_controls_row(slot))
	rows.append(UiKit.button("Driving Settings", _open_settings.bind(slot), "Assists, comfort, HUD and controls"))
	var ready := UiKit.button("Ready", _toggle_ready.bind(slot), "Tell the others you're ready")
	_ready_buttons[slot] = ready
	_show_ready(slot)
	rows.append(ready)
	if slot.index > 0:
		rows.append(UiKit.button("Leave", func() -> void: Players.leave(slot), "Stop playing on this PC"))
	return rows


## How a player plays: with a controller, its layout; on the keyboard, which side of it (so two
## can share it).
func _controls_row(slot: PlayerSlot) -> Button:
	var pad := slot.input.devices.any(func(d: Dictionary) -> bool: return d.kind == "gamepad")
	var on_keys := String(slot.input.menu_device().get("kind", "keyboard")) == "keyboard"
	if slot.keyboard_zone() and (not pad or on_keys):
		return UiKit.spinner("Controls", [["full", "Whole keyboard"], ["left", "Left side"], ["right", "Right side"]], slot.keyboard_zone(),
			func(zone: String) -> void:
				if not Players.set_keyboard_zone(slot, zone):
					status.text = "Another player has a side"
					_on_slots_changed.call_deferred(), "Share the keyboard: each player takes a side")
	var presets: Dictionary = slot.profile.data.input.presets
	return UiKit.spinner("Controls", Bindings.presets_for("gamepad"), String(presets.gamepad), func(id: String) -> void:
		presets.gamepad = id
		slot.profile.save()
		Players.refresh_all(), "Your controller's layout")


func _show_car(slot: PlayerSlot) -> void:
	var b: Button = _car_buttons.get(slot)
	if b == null or not is_instance_valid(b):
		return
	var p := _player_of(slot)
	var car := p.car_name if p and p.car_name else "None"
	UiKit.set_shown_text(b, "Car: " + car)
	b.accessibility_name = "Car: " + car


func _show_ready(slot: PlayerSlot) -> void:
	var b: Button = _ready_buttons.get(slot)
	if b == null or not is_instance_valid(b):
		return
	var waiting := _track_text not in ["", "?"]
	var on := _player_of(slot) != null and _player_of(slot).ready
	var text := _track_text if waiting else "Ready ✓" if on else "Ready"
	b.disabled = waiting
	UiKit.set_shown_text(b, text)
	b.accessibility_name = text if waiting else "Ready, on" if on else "Ready"


## This PC's player on `slot`, as the server has them; null until it does.
func _player_of(slot: PlayerSlot) -> NetPlayer:
	return Net.player(Net.id_of(slot.index)) if _in_step() else null


## The server has this PC's players as Players has them (a join or a leave has been answered).
func _in_step() -> bool:
	return Net.my_ids.size() == Players.count()


func _toggle_ready(slot: PlayerSlot) -> void:
	if _track_text not in ["", "?"] or _player_of(slot) == null:
		return
	var on := not _player_of(slot).ready
	Net.set_ready(on, slot.index)
	var b: Button = _ready_buttons[slot]
	UiKit.set_shown_text(b, "Ready ✓" if on else "Ready") # the server's word follows
	b.accessibility_name = "Ready, on" if on else "Ready"


## Each of this PC's players starts with their last car (if this class takes it), else the
## class's default.
func _auto_pick() -> void:
	if not _in_step():
		return
	var platform := Net.platform_result(String(Net.lobby.get("class", "")), String(Net.lobby.get("class_hash", "")))
	if not platform.ok():
		return
	for slot in Players.slots:
		if _picked.has(slot):
			continue
		var path := String(slot.profile.data.get("last_car", ""))
		var m := PackageLoader.read_manifest(path) if path else {}
		if not (path and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path))
				and Fitting.compatible(platform.platform, m.get("family", "")) and ContentIndex.shareable(m)):
			path = GameModes.default_car(platform.platform)
		_picked[slot] = path
		_picked_for[slot] = slot.profile.id
		Net.pick_car(slot.index, path)


func _pick_car(slot: PlayerSlot) -> void:
	var picker := CarPicker.new()
	picker.current = String(_picked.get(slot, ""))
	var platform := Net.platform_result(String(Net.lobby.get("class", "")), String(Net.lobby.get("class_hash", "")))
	picker.platform = platform.platform if platform.ok() else {}
	picker.online = true
	picker.picked.connect(func(path: String) -> void:
		_picked[slot] = path
		_picked_for[slot] = slot.profile.id
		Net.pick_car(slot.index, path)
		slot.profile.set_value("last_car", path)
		picker.closed.emit())
	_open_for(slot, picker, "Car")


func _open_settings(slot: PlayerSlot) -> void:
	var settings := PlayerSettingsMenu.new()
	settings.slot = slot
	settings.crumbs = ["Drive Online", "Lobby", "Driving Settings"]
	_open_for(slot, settings, "Driving Settings")


## Opens `menu` for `slot`: P1's over this page; another player's in their own view, full screen
## until it closes. The focus comes back to the row starting `row`.
func _open_for(slot: PlayerSlot, menu: Control, row: String) -> void:
	if slot.index == 0:
		open_over(menu, func() -> void: _send_infos())
		return
	var v: PlayerView = _cards.get(slot)
	if v == null:
		return
	var card := _card_of(v)
	_expanded = v
	v.reparent(_expand_layer, false)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.reference = PlayerView.REF
	card.visible = false
	menu.closed.connect(func() -> void:
		menu.queue_free()
		_expanded = null
		_place_cards()
		card.visible = true
		card.focus_row(row)
		_send_infos())
	v.overlay_root.add_child(menu)


## The kart classes the players pick from ([[id, name]]); none outside karts (D149).
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


## `slot`'s kart class: sent with their car.
func pick_class(slot: PlayerSlot, id: String) -> void:
	slot.profile.set_value("kart_class", id)
	if _picked.has(slot):
		Net.pick_car(slot.index, String(_picked[slot]))


## What each of this PC's players drives with and the assists they have on (for the roster), with
## their name and colour; sent when it changes.
func _send_infos() -> void:
	if not _in_step() or Net.lobby.is_empty():
		return
	var platform := Net.platform_result(String(Net.lobby.get("class", "")), String(Net.lobby.get("class_hash", "")))
	var mode := GameModes.mode_for(String(Net.lobby.get("class", "")))
	for slot in Players.slots:
		var device := device_of(slot)
		var on := AssistRules.effective(slot.profile, platform.platform if platform.ok() else {}, mode, device == "wheel", true)
		var assists := []
		for a: String in AssistRules.ALL:
			var v: Variant = on.get(a, false)
			if ResultsMenu.ASSIST_NAMES.has(a) and (v is bool and v or v is float and v > 0.0):
				assists.append(a)
		var info := { "device": device, "assists": assists, "name": slot.display_name(), "color": slot.color().to_html(false) }
		if _sent.get(slot) != info:
			_sent[slot] = info
			Net.send_info(slot.index, info)


## What `slot` drives with, as the roster shows it: "wheel", their controller's family ("xbox",
## "playstation"), "keyboard", or "".
static func device_of(slot: PlayerSlot) -> String:
	if slot.input.devices.any(func(d: Dictionary) -> bool: return d.kind == "sim" and d.get("wheel", false)):
		return "wheel"
	var d := slot.input.menu_device()
	if d.get("kind") == "gamepad":
		return Devices.family_of_joy(int(d.id))
	if slot.keyboard_zone():
		return "keyboard"
	for pad: Dictionary in slot.input.devices:
		if pad.kind == "gamepad":
			return Devices.family_of_joy(int(pad.id))
	return ""


# --- The other players' cards ---


## A card for each player here but P1, in their own view, and the "Press to join" place for one
## more.
func _build_cards() -> void:
	for slot: PlayerSlot in _cards.keys():
		if slot not in Players.slots or slot.index == 0:
			var v: PlayerView = _cards[slot]
			_cards.erase(slot)
			if _expanded == v:
				_expanded = null
			slot.menu_target = null
			v.queue_free()
	for slot in Players.slots:
		if slot.index > 0 and not _cards.has(slot):
			var v := PlayerView.new()
			v.slot = slot
			v.reference = CARD_REF
			v.viewport.disable_3d = true
			v.viewport.transparent_bg = true
			v.set_listener(false)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var card := LobbyCard.new()
			card.slot = slot
			card.lobby = self
			v.overlay_root.add_child(card)
			_cards[slot] = v
			_strip.add_child(v)
			slot.input.settle()
	_place_cards()
	_route_input()


## The cards in their players' order, then the join place; as tall as cards need while there are
## any, a line otherwise.
func _place_cards() -> void:
	var tall := not _cards.is_empty()
	var height := minf(size.y * CARD_SHARE, CARD_MAX) if tall else 56.0
	var order := Players.slots.filter(func(s: PlayerSlot) -> bool: return _cards.has(s))
	for i in order.size():
		var v: PlayerView = _cards[order[i]]
		if v != _expanded:
			if v.get_parent() != _strip:
				v.reparent(_strip, false)
			v.reference = CARD_REF
			v.custom_minimum_size = Vector2(0, height)
			_strip.move_child(v, i)
	_join_holder.custom_minimum_size = Vector2(0, height)
	_join_holder.visible = Players.count() < Players.MAX
	_strip.move_child(_join_holder, -1)


static func _card_of(v: PlayerView) -> LobbyCard:
	for c in v.overlay_root.get_children():
		if c is LobbyCard:
			return c
	return null


func _on_joined(slot: PlayerSlot) -> void:
	Net.add_local({ "name": slot.display_name(), "color": slot.color().to_html(false) })
	_build_cards()


## A player here left: the server takes them off (the others close up, as the slots did).
func _on_left(slot: PlayerSlot) -> void:
	Net.remove_local(slot.index)
	_picked.erase(slot)
	_picked_for.erase(slot)
	_sent.erase(slot)
	_car_buttons.erase(slot)
	_ready_buttons.erase(slot)
	_build_cards()


## A profile, a keyboard side or a device changed: the rows again, and what the server has.
func _on_slots_changed() -> void:
	if not is_inside_tree():
		return
	for slot: PlayerSlot in _picked.keys():
		if _picked_for.get(slot) != slot.profile.id: # another profile: their own last car
			_picked.erase(slot)
	_build_p1()
	for v: PlayerView in _cards.values():
		if _card_of(v):
			_card_of(v).rebuild()
	_auto_pick()
	_send_infos()


## Who gets which input: P1 the window (no pushed actions: the window's own), each other player
## their card; joining is open while this page is up and there's room.
func _route_input() -> void:
	var up := is_visible_in_tree()
	for slot in Players.slots:
		var v: PlayerView = _cards.get(slot)
		slot.menu_target = v.viewport if v and up and slot.index > 0 else null
	var room := Players.count() < Players.MAX and Net.roster.size() < int(Net.lobby.get("max", NetProtocol.MAX_PLAYERS)) \
		and String(Net.lobby.get("state", "lobby")) == "lobby"
	var joining := up and room and _expanded == null
	if Players.joining != joining:
		Players.joining = joining


## The window's keys and pads are P1's: another player's here (or a pad nobody has: it's pressed
## to join) don't move this page's focus. Their presses reach their own card through Players.
func _input(event: InputEvent) -> void:
	if not Players.slots.is_empty() and not_p1s(event, Players.slots[0]):
		get_viewport().set_input_as_handled()


## Whether `event` came from a device that isn't `p1`'s (keys, while `p1` has no keyboard and isn't
## typing; a pad that's someone else's or nobody's).
static func not_p1s(event: InputEvent, p1: PlayerSlot) -> bool:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		for d: Dictionary in Devices.list():
			if d.kind == "gamepad" and int(d.id) == event.device:
				return not d.key in p1.device_keys
		return false
	if event is InputEventKey and p1.keyboard_zone().is_empty():
		var focus := (Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner()
		return not (focus is LineEdit and (focus as LineEdit).is_editing())
	return false


# --- Host ---


## Change event (docs/UI_FLOW.md §7.5): the event pages over this one, back here with the event.
func change_event() -> LocalDrivePage:
	var page := LocalDrivePage.new()
	page.context = "change"
	page.done = func(flow: EventFlow) -> void:
		if Net.host_logic:
			Net.host_logic.set_event(flow.rotation_item())
		close_over(page)
	open_over(page)
	return page


func open_playlist() -> PlaylistPage:
	var page := PlaylistPage.new()
	open_over(page)
	return page


## Takes `page` (opened over this one) and any over it off.
func close_over(page: Control) -> void:
	var stack := get_parent() as MenuStack
	if stack:
		stack.close(page)
	elif is_instance_valid(page):
		page.closed.emit()


func _show_host_info(port_message: String) -> void:
	var port := int(Net.host_logic.config.port) if Net.host_logic else NetProtocol.DEFAULT_PORT
	var addrs := PackedStringArray()
	for ip in UpnpMapper.local_addresses():
		addrs.append(("[%s]:%d" if ip.contains(":") else "%s:%d") % [ip, port])
	host_label.text = "Join at %s%s" % [", ".join(addrs.slice(0, 3)), ("   " + port_message) if port_message else ""]


# --- Chat's place, leaving ---


## Chat on the right while there's room for the pane, else under This PC.
func _place_chat() -> void:
	var where := _chat_pane if size.x >= PANE_MIN_WIDTH else _chat_place
	if chat.get_parent() != where:
		var focus := UiKit.focus_owner(self)
		chat.reparent(where, false)
		if focus and chat.is_ancestor_of(focus):
			focus.grab_focus.call_deferred()


func _on_notice(text: String) -> void:
	status.text = text
	if text == "Server full" and Players.count() > Net.my_ids.size(): # a join that didn't fit
		Players.leave(Players.slots[-1])


func _on_disconnected(reason: String) -> void:
	left.emit(reason)


## Leaves the game (closes the server when hosting).
func leave() -> void:
	Net.leave()
	left.emit("")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and scroll().is_visible_in_tree() and _expanded == null:
		var focus := UiKit.focus_owner(self)
		if focus is LineEdit and (focus as LineEdit).is_editing():
			return
		get_viewport().set_input_as_handled()
		leave()


## Dev: --auto-ready readies this PC's players once their cars are in (bots, checks).
func _dev_auto() -> void:
	if not Game.dev.has("auto-ready") or not Net.track_here() or not _in_step():
		return
	var now := Time.get_ticks_msec()
	for slot in Players.slots:
		var p := _player_of(slot)
		if p and p.car and not p.ready and now - int(_auto_ready.get(p.id, -10000)) > 1000:
			_auto_ready[p.id] = now
			Net.set_ready(true, slot.index)


## Another player's card on this PC, in their own view: their rows, driven by their own devices.
## Cancel un-readies them, then leaves.
class LobbyCard:
	extends PanelContainer

	var slot: PlayerSlot
	var lobby: LobbyPage
	var _rows: Array[Control] = []

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var box := StyleBoxFlat.new()
		box.bg_color = UiKit.PANEL
		box.border_color = slot.color()
		box.set_border_width_all(4)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(16)
		add_theme_stylebox_override(&"panel", box)
		rebuild()

	func rebuild() -> void:
		var owner := UiKit.focus_owner(self) if is_inside_tree() else null
		var keep := UiKit.text_of(owner).get_slice(" ", 0) if owner is Button else ""
		theme = UiKit.theme_with(String(slot.profile.data.font)) # themes don't reach into a view's viewport
		for c in get_children():
			remove_child(c)
			c.queue_free()
		_rows.clear()
		var list := VBoxContainer.new()
		list.add_theme_constant_override(&"separation", 8)
		add_child(list)
		var head := HBoxContainer.new()
		var tag := UiKit.label(slot.tag(), 34)
		tag.add_theme_color_override(&"font_color", slot.color())
		head.add_child(tag)
		var name_label := UiKit.label(slot.display_name(), 30)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		list.add_child(head)
		for c: Control in lobby.card_rows(slot):
			c.custom_minimum_size.y = 56
			list.add_child(c)
			_rows.append(c)
		UiKit.chain_focus(_rows, keep.is_empty() and is_inside_tree())
		if keep:
			focus_row(keep)

	func focus_row(prefix: String) -> void:
		for r: Control in _rows:
			if (r is Button and UiKit.text_of(r).begins_with(prefix)) or String(r.accessibility_name).begins_with(prefix):
				UiKit.focus_later(r) # a rebuild this frame may take it off again
				return

	func _unhandled_input(event: InputEvent) -> void:
		if not visible or not event.is_action_pressed("ui_cancel"):
			return
		get_viewport().set_input_as_handled()
		var p := lobby._player_of(slot)
		if p and p.ready:
			lobby._toggle_ready(slot)
		else:
			Players.leave(slot)


## What can be done about another player: mute them, and for admins kick or ban.
class PlayerActions:
	extends MenuPage

	var player: NetPlayer

	func _init() -> void:
		back_hint = "Back to the lobby"

	func _ready() -> void:
		title = player.name
		crumbs = ["Drive Online", "Lobby", player.name]
		super._ready()

	func _build() -> void:
		var muted := Net.muted.has(player.id)
		add_row(UiKit.button("Unmute" if muted else "Mute", func() -> void:
			Net.mute(player.id, not muted)
			closed.emit(), "Hide their chat" if not muted else "Show their chat again"))
		if Net.is_admin():
			add_row(UiKit.button("Kick", func() -> void:
				Net.admin("kick", str(player.id))
				closed.emit(), "They can join again"))
			add_row(UiKit.button("Ban", func() -> void:
				Net.admin("ban", str(player.id))
				closed.emit(), "They can't come back"))
