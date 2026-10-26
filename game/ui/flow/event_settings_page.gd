class_name EventSettingsPage
extends MenuPage
## An event's settings (docs/UI_FLOW.md §5.5, §6.1): the type's rows (EventForms), the track's map
## on the right (TrackPane), and "Next", on to the class, the players, or (a time trial before P6)
## the drive.

var flow: EventFlow
var next_button: Button
var pane: TrackPane


func _ready() -> void:
	title = flow.name()
	crumbs = flow.crumbs("Settings")
	steps = flow.steps()
	step = steps.find("Settings")
	super._ready()


func _build() -> void:
	EventForms.build(self)
	next_button = UiKit.button("Next", go_on, flow.next_hint())
	next_button.name = "Next"
	add_row(next_button)
	if flow.has_track():
		pane = TrackPane.new()
		set_pane(pane)
		show_track()


## The track row moved: the pane follows.
func show_track() -> void:
	if pane:
		pane.show_track(flow.track)


func focus_next() -> void:
	next_button.grab_focus()


## Next: the class, else the players, else (a time trial) the drive.
func go_on() -> void:
	flow.remember()
	if flow.has_class_step():
		open_class()
	elif flow.tt:
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
