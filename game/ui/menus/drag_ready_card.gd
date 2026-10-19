class_name DragReadyCard
extends Control
## The card that locks a driver in before their own pass (D177): whose turn it is, on the controls
## they are holding, and what a pass asks of them. It has to be dismissed, so a pass never starts
## on somebody who was watching the last one.
##
## Every line names the input the driver actually has (DragPrompts, D169), and only the rules this
## match has turned on are listed. `pause` opens the pause menu rather than being swallowed, so a
## card is never a way to be stuck.

signal locked_in
signal paused

## The driver this card is for, and the pass it is about.
var player: SessionPlayer
var event: RaceEvent
var round_name := ""
var lane := 0
var boosts := 0
## What this driver lets go of to launch (DragControl.launch_action): "clutch", "brake" or
## "throttle".
var launch := "throttle"


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Your pass", 820)
	var who := UiKit.label("%s  ·  %s" % [player.display_name, player.slot.devices_text()], 34)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(who)
	var lane_name := "%s lane" % ("left" if lane == 0 else "right")
	var where := UiKit.label("%s  ·  %s" % [round_name, lane_name] if round_name else lane_name, 26)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.add_theme_color_override("font_color", Hud.DIM)
	list.add_child(where)
	var steps := _steps()
	for step: Array in steps:
		list.add_child(_row(String(step[0]), String(step[1])))
	# The steps are labels, and a screen reader follows the focus, so they are the button's
	# description too (docs/ACCESSIBILITY.md §2).
	var said := ". ".join(steps.map(func(step: Array) -> String: return "%s: %s" % [step[0], step[1]]))
	var button := UiKit.button("I'm ready", func() -> void: locked_in.emit(), "Your pass starts. " + said)
	list.add_child(button)
	accessibility_name = ". ".join([who.text, where.text, said])
	UiKit.chain_focus([button])


## What this pass asks of this driver, in the order it asks for it. A rule the match has turned
## off is not listed, and neither is a prompt the device has nothing bound for.
func _steps() -> Array:
	var qtes: bool = event.drag_qtes
	var out := []
	if event.drag_burnout and qtes:
		out.append(["Burnout", DragPrompts.burnout_text(player)])
	if event.drag_two_step and qtes:
		out.append(["On the line", DragPrompts.two_step_text(player, launch)])
	out.append(["Green", _green_text()])
	if event.drag_timing:
		var shift := DragPrompts.shift_text(player, 2)
		out.append(["Shifts", "%s on the needle's mark" % shift if shift else "On the needle's mark"])
	if boosts > 0:
		out.append(["Boost", "%s  ·  %d left" % [DragPrompts.boost_text(player), boosts]])
	if event.drag_centreline:
		out.append(["Your lane", "The centreline loses the pass"])
	out.append(["Winning", "First through the lights goes through"])
	return out.filter(func(step: Array) -> bool: return not String(step[1]).is_empty())


func _green_text() -> String:
	var go := DragPrompts.launch_text(player, launch)
	if not event.drag_tree:
		return go
	return "%s  ·  early is a red light" % go if go else "Early is a red light"


## One step: what it is, then what to do, so the two line up down the card.
func _row(what: String, how: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := UiKit.label(what, 26)
	name_label.custom_minimum_size = Vector2(220, 0)
	name_label.add_theme_color_override("font_color", Hud.DIM)
	row.add_child(name_label)
	row.add_child(UiKit.label(how, 26))
	return row


func _unhandled_input(event_in: InputEvent) -> void:
	# The card has to be dismissed, but it is not a way to be stuck: pause still opens the menu.
	if event_in.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		paused.emit()
