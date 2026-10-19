class_name MiniGamesMenu
extends Control
## Mini Games (Changes.md): the short matches that aren't races or kart races, under one Solo
## Drive entry. Picking one hides this menu; backing out of that game's first screen shows it
## again on the same entry (`focus`), as Solo Drive itself does.

## `game`: "sumo" or "drag".
signal chosen(game: String)
signal closed

const GAMES := [
	["sumo", "Sumo Wrestling", "Shove the others off a shrinking platform"],
	["drag", "Drag Strip", "Time the lights, the shifts and the bottle"],
]

var _rows: Array = []


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Mini Games", 560)
	for g: Array in GAMES:
		var b := UiKit.button(g[1], func() -> void: chosen.emit(String(g[0])), g[2])
		b.set_meta(&"game", g[0])
		list.add_child(b)
		_rows.append(b)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


## Shows the menu again with `game`'s entry focused (the first if it's not listed).
func focus(game: String) -> void:
	for b: Button in _rows:
		if String(b.get_meta(&"game", "")) == game:
			UiKit.focus_later(b)
			return
	UiKit.focus_later(_rows[0])


func grab_focus_first() -> void:
	(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	# Hidden while a game's menus are open: back belongs to those.
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
