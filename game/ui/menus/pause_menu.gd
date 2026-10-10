class_name PauseMenu
extends Control
## Pause menu for a session (docs/ACCESSIBILITY.md §6: pause any time offline).

signal resumed
signal reset_car
signal change_car
signal quit_to_title
signal back_to_bay

## Test-driving a Fitting Bay draft: offers the way back.
var bay_return := false
var _settings: SettingsMenu
var _buttons: Array = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Paused", 560)
	_buttons = [
		UiKit.button("Resume", func() -> void: resumed.emit()),
		UiKit.button("Reset car", func() -> void: reset_car.emit()),
		UiKit.button("Change car", func() -> void: change_car.emit()),
		UiKit.button("Settings", _open_settings),
		UiKit.button("Quit to title", func() -> void: quit_to_title.emit()),
	]
	if bay_return:
		_buttons.insert(1, UiKit.button("Back to Fitting Bay", func() -> void: back_to_bay.emit()))
	for b: Button in _buttons:
		list.add_child(b)
	UiKit.chain_focus(_buttons)


func _open_settings() -> void:
	_settings = SettingsMenu.new()
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings = null
		for child in get_children():
			if child is CanvasItem:
				child.visible = true
		_ready_focus())
	for child in get_children():
		if child is CanvasItem:
			child.visible = false
	add_child(_settings)


func _ready_focus() -> void:
	_buttons[0].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _settings == null and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		resumed.emit()
