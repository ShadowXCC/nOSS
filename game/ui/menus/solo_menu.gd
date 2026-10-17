class_name SoloMenu
extends Control
## Solo Drive (Changes.md): the ways to drive on this machine, alone or in splitscreen, under one
## title entry. Picking one hides this menu; backing out of that mode's first screen shows it
## again on the same entry (`focus`).

## `mode`: "free", "race", "time_trial", "highway", "kart" or "endless".
signal chosen(mode: String)
signal closed

const MODES := [
	["free", "Free Drive", "Drive any track"],
	["race", "Race", "Practice, qualifying and a race against AI"],
	["time_trial", "Time Trial", "Solo laps against your ghost"],
	["highway", "Highway", "Cruise, score attack, runs and laps through traffic"],
	["kart", "Kart", "Kart races with items, battles and cups"],
]

var _rows: Array = []


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Solo Drive", 560)
	for m: Array in MODES:
		var b := UiKit.button(m[1], func() -> void: chosen.emit(String(m[0])), m[2])
		b.set_meta(&"mode", m[0])
		list.add_child(b)
		_rows.append(b)
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(back)
	_rows.append(back)
	UiKit.chain_focus(_rows)


## Shows the menu again with `mode`'s entry focused (the first if it's not listed).
func focus(mode: String) -> void:
	for b: Button in _rows:
		if String(b.get_meta(&"mode", "")) == mode:
			UiKit.focus_later(b)
			return
	UiKit.focus_later(_rows[0])


func grab_focus_first() -> void:
	(_rows[0] as Control).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	# Hidden while a mode's menus are open: back belongs to those.
	if e.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		closed.emit()
