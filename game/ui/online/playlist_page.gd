class_name PlaylistPage
extends MenuPage
## The host's playlist (docs/UI_FLOW.md §7.5): events run one after another, moving on after each
## session (NetHost). Pick one, then Remove, Move up or Move down it; Add event runs the event pages
## (the "change" context) and puts the new one at the end. The one up now is marked.

var host: NetHost
## The event picked (an index into the rotation).
var selected := 0
var add_button: Button
var remove_button: Button
var up_button: Button
var down_button: Button

var _group := ButtonGroup.new()
var _changing := false # this page is changing the playlist (it shows it again itself)


func _init() -> void:
	back_hint = "Back to the lobby"


func _ready() -> void:
	if host == null:
		host = Net.host_logic
	title = "Playlist"
	crumbs = ["Drive Online", "Lobby", "Playlist"]
	selected = host.rotation_index
	super._ready()
	host.rotation_changed.connect(_on_rotation_changed)


func _exit_tree() -> void:
	super._exit_tree()
	if host and host.rotation_changed.is_connected(_on_rotation_changed):
		host.rotation_changed.disconnect(_on_rotation_changed)


func _build() -> void:
	_fill()


func _fill() -> void:
	_group = ButtonGroup.new()
	var items := host.config.rotation
	selected = clampi(selected, 0, items.size() - 1)
	for i in items.size():
		var text := "%d. %s" % [i + 1, summary(host.config, i)]
		var now := i == host.rotation_index
		var b := UiKit.button("", _select.bind(i), "Up now" if now else "Pick it to move or remove it")
		b.name = "Event%d" % (i + 1)
		b.toggle_mode = true
		b.button_group = _group
		b.button_pressed = i == selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiKit.set_shown_text(b, text + ("  •" if now else ""))
		b.accessibility_name = text + (", up now" if now else "")
		b.set_meta(&"event", i)
		add_row(b)
	add_button = UiKit.button("Add event", add_event, "Another event at the end")
	add_button.name = "AddEvent"
	add_row(add_button)
	remove_button = UiKit.button("Remove", remove, "Take the picked event off")
	remove_button.name = "Remove"
	remove_button.disabled = items.size() < 2
	add_row(remove_button)
	up_button = UiKit.button("Move up", move.bind(-1), "The picked event goes sooner")
	up_button.name = "MoveUp"
	up_button.disabled = selected == 0
	add_row(up_button)
	down_button = UiKit.button("Move down", move.bind(1), "The picked event goes later")
	down_button.name = "MoveDown"
	down_button.disabled = selected >= items.size() - 1
	add_row(down_button)


## Rotation item `i` as listed: "Regular race · Piedmont Speedway · GT" (no track for events
## that make their own ground, no class where each kart picks its own).
static func summary(cfg: ServerConfig, i: int) -> String:
	var item: Dictionary = cfg.rotation[i]
	var e := cfg.event(i)
	var class_id := String(item.get("class", ""))
	var named := String(item.get("name", "")) if item.get("name") is String else ""
	var bits := PackedStringArray([named if named else LobbyPage.event_text(e, class_id)])
	if e.kind not in ["sumo", "drag", "endless"]:
		var path := cfg.track_path(i)
		bits.append(String(TrackLibrary.entry(path).get("name", path.get_file())))
	if GameModes.kart_classes(class_id).is_empty():
		var r := cfg.platform(i)
		bits.append(String(r.platform.get("name", class_id)) if r.ok() else class_id)
	return " · ".join(Array(bits).filter(func(b: String) -> bool: return not b.is_empty()))


func _on_rotation_changed() -> void:
	if not _changing and is_visible_in_tree():
		_show()


## The playlist becomes `items`, `now` up.
func _apply(items: Array, now: int) -> void:
	_changing = true
	host.set_rotation(items, now)
	_changing = false


func _select(i: int) -> void:
	selected = i
	up_button.disabled = i == 0
	down_button.disabled = i >= host.config.rotation.size() - 1


## The list again (it changed), the focus on the picked event, or on `keep` (a button's name).
func _show(keep := "") -> void:
	if not is_inside_tree():
		return
	rebuild_rows(_fill, func() -> Control:
		for c: Control in _rows:
			if (keep and c.name == keep) or (not keep and c.get_meta(&"event", -1) == selected):
				return c if not (c as BaseButton).disabled else add_button
		return null)


## Add event: the event pages over this one; the event they set up goes at the end.
func add_event() -> LocalDrivePage:
	var page := LocalDrivePage.new()
	page.context = "change"
	page.done = func(flow: EventFlow) -> void:
		var stack := get_parent() as MenuStack
		if stack:
			stack.close(page)
		else:
			page.closed.emit()
		var items := host.config.rotation.duplicate()
		items.append(flow.rotation_item())
		selected = items.size() - 1
		_apply(items, host.rotation_index)
		_show()
	open_over(page)
	return page


## Takes the picked event off (not the last one). The one after it is up if it was.
func remove() -> void:
	var items := host.config.rotation.duplicate()
	if items.size() < 2:
		return
	items.remove_at(selected)
	var now := host.rotation_index
	if selected < now:
		now -= 1
	now = mini(now, items.size() - 1)
	selected = mini(selected, items.size() - 1)
	_apply(items, now)
	_show("Remove" if items.size() > 1 else "AddEvent")


## The picked event a place sooner (-1) or later (1); the one up now stays up.
func move(by: int) -> void:
	var items := host.config.rotation.duplicate()
	var to := selected + by
	if to < 0 or to >= items.size():
		return
	var item: Dictionary = items[selected]
	items[selected] = items[to]
	items[to] = item
	var now := host.rotation_index
	if now == selected:
		now = to
	elif now == to:
		now = selected
	selected = to
	_apply(items, now)
	_show("MoveUp" if by < 0 else "MoveDown")
