class_name EventSettingsPage
extends MenuPage
## An event's settings (docs/UI_FLOW.md §5.5, §6.1): the type's rows (EventForms), the track's map
## on the right (TrackPane), and "Next" under them (beside Back, always on screen), on to the
## class or the players. Next is off until the event can go (a kart race needs a track, a battle
## an arena, a cup all its tracks). Hosting with no Class step, it's "Start hosting" (§7.2).

var flow: EventFlow
var next_button: Button
var pane: TrackPane
## A line under the rows for what a row has to say ("Not a road code").
var status: Label
## What the rows keep between rebuilds (Kart's cup while a race is shown).
var stash := {}
## Custom: the preset picked (its path; "" for None).
var preset := ""


func _ready() -> void:
	title = flow.name()
	crumbs = flow.crumbs("Settings")
	steps = flow.steps()
	step = steps.find("Settings")
	super._ready()


func _build() -> void:
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)
	if flow.has_track():
		pane = TrackPane.new()
	EventForms.build(self)
	next_button = UiKit.button(flow.next_text(), go_on, flow.next_hint())
	next_button.name = "Next"
	add_action(next_button)
	if pane:
		set_pane(pane)
		show_track()
	refresh_next()


## The rows again (a row changed which rows there are), the focus on the row named `focus` (its
## label: "Play" finds "Play: Cup").
func rebuild(focus := "") -> void:
	if not is_inside_tree():
		return
	title = flow.name() # "Kart race" or "Kart cup"
	refresh_header()
	rebuild_rows(func() -> void: EventForms.build(self), row_named.bind(focus))
	show_track()
	refresh_next()


## The row labelled `label`, or null.
func row_named(label: String) -> Control:
	for c: Control in _rows:
		var target := UiKit._focus_target(c)
		var n := String(target.accessibility_name) if target else ""
		if label and (n == label or n.begins_with(label + ":")):
			return target
	return null


## Next is on once the event can go.
func refresh_next() -> void:
	if next_button:
		next_button.disabled = not flow.ready_to_go()


## The track row moved: the pane follows (a cup: its first race's track).
func show_track() -> void:
	if not pane:
		return
	var path := flow.track
	if not flow.cup.is_empty():
		var races: Array = CupRun.load_file(flow.cup).get("races", [])
		path = TrackLibrary.resolve(String(races[0].track)) if not races.is_empty() else ""
	pane.show_track(path)


## The track at `path`, loaded once (the highway rows read its runs and its way round).
func track_data(path: String) -> TrackData:
	return pane.data(path) if pane else null


func focus_next() -> void:
	next_button.grab_focus()


## Next: the class, else the players (hosting: the server, then its lobby; from the lobby, back
## to it with this event).
func go_on() -> void:
	if not flow.ready_to_go():
		return
	flow.remember()
	if flow.has_class_step():
		open_class()
	elif flow.context == "host":
		status.text = flow.host()
	elif flow.context == "change":
		flow.start()
	else:
		open_players()


func open_class() -> ClassPage:
	var page := ClassPage.new()
	page.flow = flow
	open_over(page)
	return page


func open_players() -> PlayersMenu:
	var players := flow.players_page()
	open_over(players)
	return players


## Kart's cup builder (`c`: the cup to change, {} for a new one); saved, it's the cup picked.
func open_cup_builder(c: Dictionary) -> CupBuilderPage:
	var builder := CupBuilderPage.new()
	builder.cup = c.duplicate(true)
	builder.crumbs = flow.crumbs("Cup builder")
	var saved := [""]
	builder.saved.connect(func(path: String) -> void:
		saved[0] = path
		builder.closed.emit())
	open_over(builder, func() -> void:
		if saved[0]:
			flow.cup = saved[0]
			rebuild("Cup"))
	return builder


## Kart: "Delete this cup", after asking.
func delete_cup(c: Dictionary) -> void:
	var confirm := _confirm("Delete %s?" % String(c.get("name", "this cup")), "Delete this cup", "It goes from your cups")
	confirm.confirmed.connect(func() -> void:
		CupRun.delete(String(c.id))
		flow.cup = String(CupRun.list()[0].path) if not CupRun.list().is_empty() else ""
		confirm.closed.emit()
		rebuild("Cup"))
	open_over(confirm)


## Custom: "Save preset" asks for a name, then keeps the rows (and the class) under it.
func save_preset() -> NamePage:
	var ask := NamePage.new()
	ask.title = "Save preset"
	ask.crumbs = flow.crumbs("Save preset")
	ask.value = String(EventPresets.load_file(preset).get("name", "")) if preset else ""
	ask.save_hint = "Keep these settings under this name"
	var saved := [""]
	ask.named.connect(func(text: String) -> void:
		saved[0] = EventPresets.save(text, flow)
		if saved[0].is_empty():
			ask.status.text = "Can't save"
			return
		ask.closed.emit())
	open_over(ask, func() -> void:
		if saved[0]:
			preset = saved[0]
			rebuild("Preset"))
	return ask


## Custom: "Delete preset", after asking.
func delete_preset() -> void:
	if preset.is_empty():
		return
	var confirm := _confirm("Delete %s?" % String(EventPresets.load_file(preset).get("name", "this preset")), "Delete preset",
		"It goes for good")
	confirm.confirmed.connect(func() -> void:
		EventPresets.delete(preset)
		preset = ""
		confirm.closed.emit()
		rebuild("Preset"))
	open_over(confirm)


func _confirm(question: String, crumb: String, yes_hint: String) -> ConfirmPage:
	var confirm := ConfirmPage.new()
	confirm.title = question
	confirm.crumbs = flow.crumbs(crumb)
	confirm.no_text = "Keep"
	confirm.no_hint = "Leave it"
	confirm.yes_text = "Delete"
	confirm.yes_hint = yes_hint
	return confirm
