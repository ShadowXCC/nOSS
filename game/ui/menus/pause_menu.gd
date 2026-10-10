class_name PauseMenu
extends Control
## Pause menu for a session (docs/ACCESSIBILITY.md §6: pause any time offline). It opens in the
## view of the player who paused, and only they control it.

signal resumed
signal reset_car
signal change_car
signal leave
signal quit_to_title
signal back_to_bay

## Who paused.
var slot: PlayerSlot
## Test-driving a Fitting Bay draft: offers the way back.
var bay_return := false
## Players other than P1 can drop out.
var can_leave := false
var _buttons: Array = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Paused" if slot == null else "Paused  ·  %s" % slot.tag(), 560)
	_buttons = [
		UiKit.button("Resume", func() -> void: resumed.emit()),
		UiKit.button("Reset car", func() -> void: reset_car.emit()),
		UiKit.button("Change car", func() -> void: change_car.emit()),
		UiKit.button("Settings", _open_settings, "Your controls, assists and HUD"),
		UiKit.button("Game settings", _open_game_settings, "Graphics, sound, splitscreen"),
		UiKit.button("Quit to title", func() -> void: quit_to_title.emit()),
	]
	if bay_return:
		_buttons.insert(1, UiKit.button("Back to Fitting Bay", func() -> void: back_to_bay.emit()))
	if can_leave:
		_buttons.insert(_buttons.size() - 1, UiKit.button("Leave", func() -> void: leave.emit(), "Drop out; the others keep driving"))
	for b: Button in _buttons:
		list.add_child(b)
	UiKit.chain_focus(_buttons)


func _open_settings() -> void:
	var menu := PlayerSettingsMenu.new()
	menu.slot = slot
	UiKit.open_sub(self, menu, _ready_focus)


func _open_game_settings() -> void:
	var menu := SettingsMenu.new()
	menu.in_session = true
	UiKit.open_sub(self, menu, _ready_focus)


func _ready_focus() -> void:
	_buttons[0].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _buttons[0].is_visible_in_tree() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		resumed.emit()
