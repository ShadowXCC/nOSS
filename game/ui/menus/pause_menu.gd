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
signal back_to_editor
signal end_session
signal restart
## The setup menu closed (apply and save its changes).
signal setup_closed
## Time trial: another ghost was picked.
signal ghost_picked(id: String)
## Online host: everyone back to the lobby.
signal to_lobby

## Who paused.
var slot: PlayerSlot
## Test-driving a Fitting Bay draft: offers the way back.
var bay_return := false
## Test-driving the track editor's draft: offers the way back.
var editor_return := false
## Players other than P1 can drop out.
var can_leave := false
## Hotswap is allowed (not in a race).
var can_change_car := true
## Practice and qualifying can be ended early; sessions can be restarted.
var can_end_session := false
var can_restart := false
## The car's setup can be changed (not during a race).
var can_setup := false
var setup: Setup
## Time trial: ghosts to race ([[id, label]]), the one shown, and the leaderboard's entries
## (highways too: a score, run or loop board; `leaderboard_scores` for points).
var ghost_items: Array = []
var ghost_current := ""
var leaderboard: Array = []
var leaderboard_title := ""
var leaderboard_scores := false
## The mode's own items, after Reset car: [[text, callable, description]] (highways: Change
## direction).
var extra_items: Array = []
## Online (D85): chat is offered, quitting leaves the game; `is_host` can send everyone to the lobby.
var online := false
var is_host := false
var _buttons: Array = []


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Paused" if slot == null else "Paused  ·  %s" % slot.tag(), 560)
	_buttons = [
		UiKit.button("Resume", func() -> void: resumed.emit()),
		UiKit.button("Reset car", func() -> void: reset_car.emit()),
	]
	for item: Array in extra_items:
		_buttons.append(UiKit.button(String(item[0]), item[1], String(item[2]) if item.size() > 2 else ""))
	if can_change_car:
		_buttons.append(UiKit.button("Change car", func() -> void: change_car.emit()))
	if can_setup:
		_buttons.append(UiKit.button("Setup", _open_setup, "Gearing, brakes, suspension, aero"))
	if not ghost_items.is_empty():
		_buttons.append(UiKit.spinner("Ghost", ghost_items, ghost_current, func(id: String) -> void: ghost_picked.emit(id)))
	if not ghost_items.is_empty() or leaderboard_title:
		_buttons.append(UiKit.button("Leaderboard", _open_leaderboard, "Your best scores here" if leaderboard_scores else "Your fastest laps here"))
	if can_end_session:
		_buttons.append(UiKit.button("End session", func() -> void: end_session.emit(), "Results now"))
	if can_restart:
		_buttons.append(UiKit.button("Restart", func() -> void: restart.emit(), "Start this session again"))
	if online:
		_buttons.append(UiKit.button("Chat", _open_chat, "Read and send messages"))
	if is_host:
		_buttons.append(UiKit.button("Lobby", func() -> void: to_lobby.emit(), "Everyone back to the lobby"))
	_buttons.append_array([
		UiKit.button("Settings", _open_settings, "Your controls, assists and HUD"),
		UiKit.button("Game settings", _open_game_settings, "Graphics, sound, splitscreen"),
		UiKit.button("Leave game" if online else "Quit to title", func() -> void: quit_to_title.emit(),
			("Close the server" if is_host else "Leave the server") if online else ""),
	])
	if bay_return:
		_buttons.insert(1, UiKit.button("Back to Fitting Bay", func() -> void: back_to_bay.emit()))
	if editor_return:
		_buttons.insert(1, UiKit.button("Back to editor", func() -> void: back_to_editor.emit(), "Keep editing the track"))
	if can_leave:
		_buttons.insert(_buttons.size() - 1, UiKit.button("Leave", func() -> void: leave.emit(), "Drop out; the others keep driving"))
	for b: Button in _buttons:
		list.add_child(b)
	UiKit.chain_focus(_buttons)


## Assists allowed in this session (shown in the player's settings).
var allowed_assists: Array = []


func _open_settings() -> void:
	var menu := PlayerSettingsMenu.new()
	menu.slot = slot
	menu.allowed_assists = allowed_assists
	UiKit.open_sub(self, menu, _ready_focus)


func _open_setup() -> void:
	var menu := SetupMenu.new()
	menu.setup = setup
	UiKit.open_sub(self, menu, func() -> void:
		setup_closed.emit()
		_ready_focus())


func _open_leaderboard() -> void:
	var menu := LeaderboardMenu.new()
	menu.entries = leaderboard
	menu.title = leaderboard_title
	menu.scores = leaderboard_scores
	UiKit.open_sub(self, menu, _ready_focus)


func _open_game_settings() -> void:
	var menu := SettingsMenu.new()
	menu.in_session = true
	UiKit.open_sub(self, menu, _ready_focus)


func _open_chat() -> void:
	var menu := ChatMenu.new()
	menu.local_index = slot.index if slot else 0
	UiKit.open_sub(self, menu, _ready_focus)


func _ready_focus() -> void:
	_buttons[0].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _buttons[0].is_visible_in_tree() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		resumed.emit()


## Chat in a session: the recent lines and the message field (the game keeps running).
class ChatMenu:
	extends Control

	signal closed

	var local_index := 0

	func _ready() -> void:
		theme = UiKit.theme_for(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS
		var list := UiKit.panel(self, "Chat", 900)
		var chat := ChatPanel.new()
		chat.local_index = local_index
		chat.custom_minimum_size = Vector2(0, 420)
		list.add_child(chat)
		var back := UiKit.button("Back", func() -> void: closed.emit())
		list.add_child(back)
		UiKit.chain_focus(chat.focusables + [back])

	func _unhandled_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			closed.emit()
