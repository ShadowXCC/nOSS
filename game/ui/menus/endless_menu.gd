class_name EndlessMenu
extends Control
## Sets up an endless drive (docs/GAMEMODES.md §4, MODE-06, D157): the road (a code to share, or a
## new one), the biome it starts in, traffic and oncoming traffic, what happens when local players
## drift far apart, and the sky (it runs on its own by default). Then the class and the players.
## Every choice is a spinner or a button, named and in the focus order; the last setup is
## remembered.

signal picked(event: RaceEvent)
signal closed

const TRAFFIC := [["light", "Light"], ["normal", "Normal"], ["off", "Off"]]
const SPREAD := [["bring", "Bring up the one behind"], ["hold", "Hold the leader back"]]

var event: RaceEvent
var _rows: Array = []
var _list: VBoxContainer
var _code: LineEdit
var _status: Label


## The last endless drive set up, or a new road in the forest.
static func last() -> RaceEvent:
	var d: Variant = Settings.profile.get("last_endless")
	if d is Dictionary and not d.is_empty():
		var e := RaceEvent.from_dict(d)
		e.kind = "endless"
		return e
	return RaceEvent.endless(EndlessCode.random_seed(), EndlessBiomes.index_of("forest"))


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if event == null:
		event = last()
	_list = UiKit.panel(self, "Endless", 860)
	_build()


func _build(focus := "") -> void:
	for c: Control in _rows:
		c.queue_free()
	_rows.clear()
	for c in _list.get_children():
		if c is ScrollContainer or c is Label and c != _list.get_child(0):
			c.queue_free()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var code := UiKit.text_field("Road code", EndlessCode.encode(event.road_seed, event.biome), func(_t: String) -> void: pass, 24,
		"Type a friend's code to drive their road", _enter_code)
	_code = code.get_child(1) as LineEdit
	_code.focus_exited.connect(func() -> void: _enter_code(_code.text))
	_add(rows, code)
	_add(rows, UiKit.button("New road", func() -> void:
		event.road_seed = EndlessCode.random_seed()
		_build.call_deferred("New road"), "A road nobody has driven"))
	_add(rows, UiKit.spinner("Start in", EndlessBiomes.choices(), event.biome, func(v: int) -> void:
		event.biome = v
		_code.text = EndlessCode.encode(event.road_seed, event.biome), "The biome the road starts in"))
	_add(rows, UiKit.spinner("Traffic", TRAFFIC, event.endless_traffic, func(v: String) -> void: event.endless_traffic = v, "Other cars on the road"))
	_add(rows, UiKit.spinner("Oncoming", [[true, "On"], [false, "Off"]], event.oncoming, func(v: bool) -> void: event.oncoming = v,
		"Cars coming the other way"))
	_add(rows, UiKit.spinner("Far apart", SPREAD, event.spread, func(v: String) -> void: event.spread = v,
		"Players on this PC stay within 3 km: who moves when they don't"))
	for row in SkyRows.rows(event):
		_add(rows, row)
	_status = UiKit.label("", 22)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	_list.add_child(_status)
	var next := UiKit.button("Next", _next, "Pick the class")
	_list.add_child(next)
	_rows.append(next)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	_list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows, focus.is_empty())
	for c: Control in _rows:
		if focus and String(c.accessibility_name).get_slice(":", 0) == focus:
			UiKit.focus_later(c)


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


## A typed code: that road and biome, or a note if it isn't one.
func _enter_code(text: String) -> void:
	var d := EndlessCode.decode(text)
	if d.is_empty():
		_status.text = "Not a road code"
		_code.text = EndlessCode.encode(event.road_seed, event.biome)
		return
	_status.text = ""
	if int(d.seed) != event.road_seed or int(d.biome) != event.biome:
		event.road_seed = int(d.seed)
		event.biome = int(d.biome)
		_build.call_deferred("Road code")


func _next() -> void:
	event.kind = "endless"
	Settings.set_value("last_endless", event.to_dict())
	picked.emit(event)


func grab_focus_first() -> void:
	for c: Control in _rows:
		var target := UiKit._focus_target(c)
		if target:
			target.grab_focus()
			return


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
