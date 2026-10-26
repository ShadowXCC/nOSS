class_name LocalDrivePage
extends MenuPage
## Local Drive (docs/UI_FLOW.md §5.2): the event types on this PC. "Drive again" repeats the last
## event: its Players page, with the pages before it under it. Racing opens its page; Endless,
## Highway, Mini Games and Free Drive (and Racing's Kart and Custom) still open their old menus
## until P5 (`chosen`).

## A type still on the old menus: "endless", "highway", "mini_games", "free", "kart", "custom" or
## "custom_tt".
signal chosen(what: String)

## [type, button, description].
const TYPES := [
	["racing", "Racing", "Races and time trials: Regular, Stock Car, Kart and Custom"],
	["endless", "Endless", "A calm drive down a road that never ends"],
	["highway", "Highway", "Cruise, score attack, runs and laps through traffic"],
	["mini_games", "Mini Games", "Sumo Wrestling, Drag Strip and Kart Battle"],
	["free", "Free Drive", "Any class on any track"],
]


func _init() -> void:
	back_hint = "Back to the main menu"


func _ready() -> void:
	title = "Local Drive"
	crumbs = ["Local Drive"]
	steps = EventFlow.steps_for("local", "racing", "regular", false)
	step = 0
	super._ready()


func _build() -> void:
	var again := EventFlow.last_drive()
	if again:
		var b := UiKit.button("Drive again", _drive_again, again.summary())
		b.name = "DriveAgain"
		b.set_meta(&"type", "again")
		b.set_meta(&"steps", again.steps())
		add_row(b)
	for t: Array in TYPES:
		var b := UiKit.button(t[1], _pick.bind(String(t[0])), t[2])
		b.name = String(t[1]).validate_node_name()
		b.set_meta(&"type", t[0])
		add_row(b)


func _pick(type: String) -> void:
	if type == "racing":
		open_racing()
	else:
		chosen.emit(type)


func open_racing(tt := false) -> RacingPage:
	var racing := RacingPage.new()
	racing.tt = tt
	racing.chosen.connect(func(what: String) -> void: chosen.emit(what))
	open_over(racing)
	return racing


## Repeats the last event: straight to its Players page (a time trial: the drive), Back from
## there leading to its Settings page.
func _drive_again() -> void:
	var flow := EventFlow.last_drive()
	if flow:
		open_flow(flow, "players")


## Opens `flow`'s pages over this one as if picked one by one (Racing, its switch set; the
## Settings page), each with the focus on what was picked, then `then`: "settings" (Next focused),
## "class" or "players" (a time trial before P6: the drive starts).
func open_flow(flow: EventFlow, then := "settings") -> void:
	if not get_parent() is MenuStack:
		return
	_focus_type(flow.type)
	if flow.type == "racing":
		var racing := RacingPage.new()
		racing.tt = flow.tt
		racing.autofocus = false
		racing.chosen.connect(func(what: String) -> void: chosen.emit(what))
		open_over(racing)
		racing.focus_variant(flow.variant)
	var settings := EventSettingsPage.new()
	settings.flow = flow
	settings.autofocus = false
	open_over(settings)
	settings.focus_next()
	match then:
		"class":
			settings.open_class()
		"players":
			if flow.tt and not flow.steps().has("Players"):
				flow.start()
			else:
				settings.open_players()


func _focus_type(type: String) -> void:
	for b: Control in _rows:
		if b.get_meta(&"type", "") == type:
			b.grab_focus()
			return


## The step row follows the type in focus (docs/UI_FLOW.md §5.1).
func _focused(c: Control) -> void:
	if c and c.has_meta(&"type") and is_ancestor_of(c):
		steps = c.get_meta(&"steps", EventFlow.steps_for("local", "racing", "regular", false))
		refresh_header()
