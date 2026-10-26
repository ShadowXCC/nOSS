class_name PlayersMenu
extends Control
## Players screen (docs/INPUT.md §3, LOC-01…LOC-04): press any button on a device to join, up to
## four players. Each player sets up their own card with their own device (profile, car, a kart
## session's class, keyboard side, monitor, more devices, settings), then Ready. Once everyone is ready a
## countdown runs in the hint line (docs/UI_FLOW.md §5.7) and the drive starts; anyone un-readying,
## joining or leaving stops it. Each card is its own small view, so every player has their own focus.

signal started
signal closed

## A card's content is laid out at this size, then scaled to fit.
const CARD_REF := Vector2(520, 1000)

## Seconds from everyone Ready to the start (tests set it near 0).
static var countdown_s := 3.0

var platform_id := ""

var _platform := {}
## Kart: the classes each player picks from (D149); [] otherwise.
var kart_classes: Array = []
var _holders: Array[Control] = []
var _cards := {} # PlayerSlot -> PlayerView
var _preview: LayoutPreview
var _expanded: PlayerView
var _expand_layer := Control.new()
var _hint: Label
var _join_text := ""
## Seconds left before the start; below 0: not counting down.
var _countdown := -1.0


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_platform = PlatformLoader.load_official(platform_id).platform
	var mode := GameModes.mode_for(platform_id)
	if not GameModes.arcade(mode).is_empty():
		kart_classes = GameModes.classes(mode).map(func(r: PlatformLoader.Result) -> Array: return [r.platform.id, String(r.platform.name)])
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := UiKit.label("Players", 48)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.label(String(mode.get("name", "Kart")) if not kart_classes.is_empty() else String(_platform.get("name", "")), 34))
	_join_text = "Press any button to join. To share the keyboard, set a player's keyboard to one side."
	_hint = UiKit.label(_join_text, 24)
	_hint.name = "Hint"
	_hint.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	column.add_child(_hint)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	for i in Players.MAX:
		var holder := PanelContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(holder)
		var join := UiKit.label("Press to join", 28)
		join.name = "JoinHint"
		join.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		join.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		join.modulate = Color(1, 1, 1, 0.6)
		holder.add_child(join)
		_holders.append(holder)
	var foot := HBoxContainer.new()
	column.add_child(foot)
	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE # keyboards and pads belong to the cards; mouse only
	back.custom_minimum_size = Vector2(200, 56)
	back.pressed.connect(func() -> void: closed.emit())
	foot.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	_preview = LayoutPreview.new()
	_preview.custom_minimum_size = Vector2(520, 150)
	foot.add_child(_preview)
	_expand_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_expand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_expand_layer)

	for slot in Players.slots:
		_add_card(slot)
	# Dev: --join=<n> joins the first n free devices (screenshots).
	for i in int(Game.dev.get("join", "0")):
		var free := Players.free_devices()
		if not free.is_empty() and Players.count() < Players.MAX:
			_add_card(Players.join(free[0]))
	Players.joined.connect(_on_joined)
	Players.left.connect(_on_left)
	Players.slots_changed.connect(_refresh)
	Players.joining = true
	_refresh()


func _exit_tree() -> void:
	Players.joining = false
	Players.adding = null
	Players.joined.disconnect(_on_joined)
	Players.left.disconnect(_on_left)
	Players.slots_changed.disconnect(_refresh)
	for slot in Players.slots:
		slot.menu_target = null


func _on_joined(slot: PlayerSlot) -> void:
	_add_card(slot)
	_refresh()


func _on_left(slot: PlayerSlot) -> void:
	stop_countdown() # the rest, all ready, count again from the top
	var v: PlayerView = _cards.get(slot)
	if v:
		_cards.erase(slot)
		v.queue_free()
	if _expanded == v:
		_expanded = null
	_refresh()


func _add_card(slot: PlayerSlot) -> void:
	slot.ready = false
	var v := PlayerView.new()
	v.slot = slot
	v.reference = CARD_REF
	v.viewport.disable_3d = true
	v.viewport.transparent_bg = true
	v.set_listener(false)
	_cards[slot] = v
	var card := PlayerCard.new()
	card.slot = slot
	card.menu = self
	v.overlay_root.add_child(card)
	_holders[slot.index].add_child(v)
	slot.input.settle()
	slot.menu_target = v.viewport


## Cards follow their player's number; a player can open their settings full screen.
func _refresh() -> void:
	for slot: PlayerSlot in _cards:
		var v: PlayerView = _cards[slot]
		if v != _expanded and v.get_parent() != _holders[slot.index]:
			v.reparent(_holders[slot.index], false)
		var card: PlayerCard = v.overlay_root.get_child(0) if v.overlay_root.get_child_count() > 0 else null
		if card and card.visible:
			card.rebuild()
	for holder in _holders:
		holder.get_node(^"JoinHint").visible = not holder.get_children().any(func(c: Node) -> bool: return c is PlayerView)
	_preview.queue_redraw()
	_check_start()


## Everyone ready: the countdown starts (it stops when someone isn't).
func _check_start() -> void:
	if Players.count() == 0 or not Players.slots.all(func(s: PlayerSlot) -> bool: return s.ready):
		stop_countdown()
		return
	if _countdown >= 0.0:
		return
	_countdown = countdown_s
	if _countdown <= 0.0:
		_start()
	else:
		_show_countdown()


func counting_down() -> bool:
	return _countdown >= 0.0


## The hint back to how to join.
func stop_countdown() -> void:
	if _countdown >= 0.0:
		_countdown = -1.0
		_hint.text = _join_text


func _process(delta: float) -> void:
	if _countdown < 0.0:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		_start()
	else:
		_show_countdown()


func _show_countdown() -> void:
	var text := "Starting in %d" % ceili(_countdown)
	if _hint.text != text: # once a second, for the screen reader
		_hint.text = text


func _start() -> void:
	_countdown = -1.0
	_hint.text = _join_text
	Players.joining = false
	for slot in Players.slots:
		slot.menu_target = null
	started.emit()


func compatible_cars() -> Array:
	var out := []
	for path in PackageLoader.list_available():
		var m := PackageLoader.read_manifest(path)
		if Fitting.compatible(_platform, m.get("family", "")):
			out.append([path, String(m.get("name", path.get_file()))])
	return out


func default_car() -> String:
	return GameModes.default_car(_platform)


## A player's settings (or their accessibility screen), full screen; their card comes back when
## they close it.
func open_settings(slot: PlayerSlot, access := false) -> void:
	var v: PlayerView = _cards[slot]
	var card: PlayerCard = v.overlay_root.get_child(0)
	_expanded = v
	v.reparent(_expand_layer, false)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.reference = PlayerView.REF
	card.visible = false
	var menu: Control
	if access:
		var first := FirstBootMenu.new()
		first.slot = slot
		menu = first
	else:
		var settings := PlayerSettingsMenu.new()
		settings.slot = slot
		settings.crumbs = ["Players", "Driving Settings"]
		menu = settings
	var back := func() -> void:
		menu.queue_free()
		_expanded = null
		v.reference = CARD_REF
		card.visible = true
		_refresh()
		card.focus_row("Access" if access else "Driving Settings")
	if access:
		menu.done.connect(back)
	else:
		menu.closed.connect(back)
	v.overlay_root.add_child(menu)


func _unhandled_input(event: InputEvent) -> void:
	# Nobody joined: Esc or B goes back (pressing them never joins).
	if Players.count() == 0 and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## One player's card: their rows, driven by their own devices.
class PlayerCard:
	extends PanelContainer

	var slot: PlayerSlot
	var menu: PlayersMenu
	var _rows: Array = []
	var _status: Label

	func _ready() -> void:
		theme = UiKit.theme_with(String(slot.profile.data.font)) # themes don't reach into a view's viewport
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var box := StyleBoxFlat.new()
		box.bg_color = UiKit.PANEL
		box.border_color = slot.color()
		box.set_border_width_all(4)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(18)
		add_theme_stylebox_override("panel", box)
		rebuild()

	func rebuild() -> void:
		var focus_text := ""
		var owner := UiKit.focus_owner(self) if is_inside_tree() else null
		if owner is Button:
			focus_text = UiKit.text_of(owner).get_slice(" ", 0)
		theme = UiKit.theme_with(String(slot.profile.data.font))
		# Off the card now, freed after this frame: the control that asked for the rebuild may
		# still be sending its signal.
		for c in get_children():
			remove_child(c)
			c.queue_free()
		_rows.clear()
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 10)
		add_child(list)
		var head := HBoxContainer.new()
		list.add_child(head)
		var tag := UiKit.label(slot.tag(), 40)
		tag.add_theme_color_override("font_color", slot.color())
		head.add_child(tag)
		var name_label := UiKit.label(slot.display_name(), 34)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		var devices := UiKit.label(slot.devices_text(), 22)
		devices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(devices)

		var used := Players.slots.filter(func(s: PlayerSlot) -> bool: return s != slot).map(func(s: PlayerSlot) -> String: return s.profile.id)
		var profiles := []
		for id in Settings.profile_ids():
			if id not in used:
				profiles.append([id, Settings.get_profile(id).display_name()])
		profiles.append(["+new", "New profile"])
		_add(list, UiKit.spinner("Profile", profiles, slot.profile.id, func(id: String) -> void:
			var p := Settings.new_profile() if id == "+new" else Settings.get_profile(id)
			Players.set_profile(slot, p)))

		_add_car_row(list)
		if not menu.kart_classes.is_empty():
			var mine := String(slot.profile.data.get("kart_class", menu.platform_id))
			if not menu.kart_classes.any(func(c: Array) -> bool: return c[0] == mine):
				mine = menu.platform_id
			_add(list, UiKit.spinner("Class", menu.kart_classes, mine, func(id: String) -> void:
				slot.profile.set_value("kart_class", id), "Light pulls hardest, Heavy wins the bumps"))

		var zone := slot.keyboard_zone()
		if zone:
			_add(list, UiKit.spinner("Keyboard", [["full", "Whole"], ["left", "Left side"], ["right", "Right side"]], zone, func(z: String) -> void:
				if not Players.set_keyboard_zone(slot, z):
					_status.text = "Another player has a side"
					rebuild.call_deferred()))
		var screens := DisplayServer.get_screen_count() if DisplayServer.get_name() != "headless" else 1
		if screens > 1:
			var main := DisplayServer.window_get_current_screen()
			var items := []
			for i in screens:
				items.append([i, "%d%s" % [i + 1, " (this one)" if i == main else ""]])
			_add(list, UiKit.spinner("Screen", items, slot.screen if slot.screen >= 0 else main, func(s: int) -> void: Players.set_screen(slot, s)))
		_add(list, UiKit.button("Add device", func() -> void:
			Players.adding = slot
			_status.text = "Press a button on it", "Wheel, pedals or a second controller"))
		_add(list, UiKit.button("Access", func() -> void: menu.open_settings(slot, true), "Accessibility presets for this player"))
		_add(list, UiKit.button("Driving Settings", func() -> void: menu.open_settings(slot), "Assists, comfort, HUD and controls"))
		var ready_button := UiKit.button("Ready ✓" if slot.ready else "Ready", func() -> void:
			slot.ready = not slot.ready
			rebuild()
			menu._check_start())
		_add(list, ready_button)
		_add(list, UiKit.button("Leave", func() -> void: Players.leave(slot)))
		_status = UiKit.label("Ready. Waiting for the others" if slot.ready else "", 22)
		_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(_status)
		UiKit.chain_focus(_rows)
		if focus_text:
			focus_row(focus_text)

	func _add_car_row(list: VBoxContainer) -> void:
		var cars := menu.compatible_cars()
		var car := String(slot.profile.data.get("last_car", ""))
		if not cars.any(func(c: Array) -> bool: return c[0] == car):
			car = menu.default_car()
		var thumb := TextureRect.new()
		thumb.custom_minimum_size = Vector2(0, 160)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.texture = GarageFiles.thumbnail(car)
		thumb.visible = thumb.texture != null
		list.add_child(thumb)
		_add(list, UiKit.spinner("Car", cars, car, func(path: String) -> void:
			slot.profile.set_value("last_car", path)
			thumb.texture = GarageFiles.thumbnail(path)
			thumb.visible = thumb.texture != null))

	func focus_row(prefix: String) -> void:
		for r: Control in _rows:
			var b := r as Button
			if b and UiKit.text_of(b).begins_with(prefix):
				b.grab_focus.call_deferred()
				return

	func _add(parent: Control, c: Control) -> void:
		parent.add_child(c)
		_rows.append(c)

	func _unhandled_input(event: InputEvent) -> void:
		if not visible or not event.is_action_pressed("ui_cancel"):
			return
		get_viewport().set_input_as_handled()
		if Players.adding == slot:
			Players.adding = null
			_status.text = ""
		elif slot.ready:
			slot.ready = false
			rebuild()
			menu._check_start()
		else:
			Players.leave(slot)


## The monitors with each player's place on them.
class LayoutPreview:
	extends Control

	func _draw() -> void:
		var headless := DisplayServer.get_name() == "headless"
		var count := 1 if headless else DisplayServer.get_screen_count()
		var main := 0 if headless else DisplayServer.window_get_current_screen()
		var screens := []
		var bounds := Rect2()
		for i in count:
			var r := Rect2(Vector2(DisplayServer.screen_get_position(i)), Vector2(DisplayServer.screen_get_size(i))) if not headless else Rect2(0, 0, 1920, 1080)
			screens.append(r)
			bounds = r if i == 0 else bounds.merge(r)
		var fit := minf(size.x / bounds.size.x, size.y / bounds.size.y) * 0.95
		var groups := SplitLayout.by_screen(Players.slots.map(func(s: PlayerSlot) -> int: return s.screen), main, count)
		var font := get_theme_default_font()
		for i in count:
			var r: Rect2 = screens[i]
			var at := Rect2((r.position - bounds.position) * fit, r.size * fit).grow(-3.0)
			draw_rect(at, Color(0.12, 0.12, 0.14))
			draw_rect(at, Color(0.5, 0.5, 0.55), false, 2.0)
			var members: Array = groups.get(i, [])
			var rects := SplitLayout.rects(members.size(), Settings.split_two, Settings.split_three)
			for k in members.size():
				var slot: PlayerSlot = Players.slots[members[k]]
				var v := Rect2(at.position + rects[k].position * at.size, rects[k].size * at.size).grow(-2.0)
				draw_rect(v, slot.color().darkened(0.35))
				var fs := int(clampf(v.size.y * 0.4, 12, 28))
				var t := font.get_string_size(slot.tag(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(font, v.get_center() + Vector2(-t.x / 2.0, fs * 0.35), slot.tag(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
