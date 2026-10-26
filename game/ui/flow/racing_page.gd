class_name RacingPage
extends MenuPage
## Racing (docs/UI_FLOW.md §5.3): a Race | Time Trial switch over Regular, Stock Car, Kart and
## Custom. LB/RB (Q/E) flip it from anywhere on the page, left and right on the switch itself, and
## the descriptions follow it. Each type goes on to its Settings page. Kart's time trial comes
## with P6.

## [variant, button, race description, time trial description].
const TYPES := [
	["regular", "Regular", "Laps against AI, simple settings", "Laps against your ghost"],
	["stock_car", "Stock Car", "Pack racing on ovals: drafting, fuel and tires", "Hot laps of an oval"],
	["kart", "Kart", "Kart races and cups with items", "Kart laps against your ghost"],
	["custom", "Custom", "Every setting, any class, saved presets", "Any class, any circuit, your ghost"],
]

## The switch is on Time Trial.
var tt := false
var context := "local"
var switch: TabRow


func _init() -> void:
	prompts = [["tabs", "Race / Time Trial"]]
	back_hint = "Back to Local Drive"


func _ready() -> void:
	title = "Racing"
	crumbs = ["Local Drive", "Racing"]
	steps = EventFlow.steps_for(context, "racing", "regular", tt)
	step = 0
	super._ready()


func _build() -> void:
	switch = TabRow.new(["Race", "Time Trial"])
	switch.name = "Switch"
	switch.current = 1 if tt else 0
	switch.changed.connect(_on_switch)
	add_header(switch)
	_fill()


func _fill() -> void:
	for t: Array in TYPES:
		var b := UiKit.button(t[1], _pick.bind(String(t[0])), t[3] if tt else t[2])
		b.name = String(t[1]).validate_node_name()
		b.set_meta(&"variant", t[0])
		if tt and t[0] == "kart": # P6
			b.disabled = true
			b.accessibility_description = "Coming soon"
		add_row(b)


## The switch, the four types, Back; up from Regular reaches the switch.
func chain(focus_first := true) -> void:
	var list: Array = [switch.button()] if switch and switch.button() else []
	list.append_array(_rows)
	if back_button:
		list.append(back_button)
	UiKit.chain_focus(list, false)
	if switch:
		switch.link()
	if focus_first and not _rows.is_empty():
		UiKit.focus_later(_rows[0])


## Focuses `variant`'s button now.
func focus_variant(variant: String) -> void:
	for b: Control in _rows:
		if b.get_meta(&"variant", "") == variant:
			b.grab_focus()
			return


## The switch flipped: the types again, with their descriptions; the focus stays on the switch,
## or on the same type (a new button, so a screen reader reads its new description).
func _on_switch(i: int, on_row: bool) -> void:
	tt = i == 1
	var focus := UiKit.focus_owner(self)
	var was := String(focus.get_meta(&"variant", "regular")) if focus else "regular"
	rebuild_rows(_fill, func() -> Control:
		if on_row:
			return switch.button()
		for b: Control in _rows:
			if b.get_meta(&"variant", "") == was:
				return b
		return null)
	_show_steps(was)


func _focused(c: Control) -> void:
	if c and c.has_meta(&"variant") and is_ancestor_of(c):
		_show_steps(String(c.get_meta(&"variant")))


func _show_steps(variant: String) -> void:
	steps = EventFlow.steps_for(context, "racing", variant, tt)
	refresh_header()


func _pick(variant: String) -> void:
	var flow := EventFlow.racing(variant, tt, context)
	flow.recall()
	open_settings(flow)


func open_settings(flow: EventFlow) -> EventSettingsPage:
	var page := EventSettingsPage.new()
	page.flow = flow
	open_over(page)
	return page
