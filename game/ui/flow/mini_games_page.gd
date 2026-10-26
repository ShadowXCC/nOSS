class_name MiniGamesPage
extends MenuPage
## Mini Games (docs/UI_FLOW.md §5.4): the short matches that aren't races, Sumo Wrestling, Drag
## Strip and Kart Battle, each on to its Settings page. The step row follows the one in focus.

## [variant, button, description].
const TYPES := [
	["sumo", "Sumo Wrestling", "Shove the others off a shrinking platform"],
	["drag", "Drag Strip", "Time the lights, the shifts and the bottle"],
	["kart_battle", "Kart Battle", "Items in an arena"],
]

var context := "local"


func _init() -> void:
	back_hint = "Back to Local Drive"


func _ready() -> void:
	title = "Mini Games"
	crumbs = ["Local Drive", "Mini Games"]
	steps = EventFlow.steps_for(context, "mini", "sumo")
	step = 0
	super._ready()


func _build() -> void:
	for t: Array in TYPES:
		var b := UiKit.button(t[1], _pick.bind(String(t[0])), t[2])
		b.name = String(t[1]).validate_node_name()
		b.set_meta(&"variant", t[0])
		add_row(b)


## Focuses `variant`'s button now.
func focus_variant(variant: String) -> void:
	for b: Control in _rows:
		if b.get_meta(&"variant", "") == variant:
			b.grab_focus()
			return


func _focused(c: Control) -> void:
	if c and c.has_meta(&"variant") and is_ancestor_of(c):
		steps = EventFlow.steps_for(context, "mini", String(c.get_meta(&"variant")))
		refresh_header()


func _pick(variant: String) -> void:
	var flow := EventFlow.make("mini", variant, false, context)
	flow.recall()
	open_settings(flow)


func open_settings(flow: EventFlow) -> EventSettingsPage:
	var page := EventSettingsPage.new()
	page.flow = flow
	open_over(page)
	return page
