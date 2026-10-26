extends GdUnitTestSuite
## The lobby page (docs/UI_FLOW.md §7.5, §7.6; LOC-05, D149): P1's rows under This PC and the
## roster's names, Ready per player and the countdown it starts, a local player joining in the
## lobby on their own card (and only their own: the window stays P1's) and leaving, the host's
## Change event and Playlist through the event pages, and a kart lobby's classes.

const PAD := 7
const PAD2 := 8


func before() -> void:
	Settings.use_folder("user://tests/lobby_page")


func after() -> void:
	Net.leave()
	Players.clear()
	Devices.test_devices = []
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	Devices.test_devices = []
	NetHost.countdown_s = 30.0 # never runs out here: a session would change the scene
	Settings.profile.event_memory = {}
	Settings.primary.set_value("kart_class", "")


func after_test() -> void:
	Net.leave()
	for slot in Players.slots.duplicate():
		if slot.index > 0: # P2 first: clearing P1 first makes P2's profile the main one
			Players.leave(slot)
	Players.clear()
	NetHost.countdown_s = -1.0


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


## Hosts with this PC's players (P1), on `class_id`, and opens the lobby on a page stack.
func _lobby(class_id := "official.track.gt") -> LobbyPage:
	var cfg := ServerConfig.defaults()
	cfg.port = 47940 + randi() % 50
	cfg.lan = false
	cfg.upnp = false
	cfg.rotation[0]["class"] = class_id
	assert_int(Net.host(cfg, Net.local_players())).is_equal(OK)
	var stack: MenuStack = auto_free(MenuStack.new())
	add_child(stack)
	var page := LobbyPage.new()
	stack.push(page)
	await _frames(6)
	return page


func _control(root: Node, accessible: String) -> Control:
	for c: Control in root.find_children("*", "Control", true, false):
		if String(c.accessibility_name).get_slice(":", 0) == accessible and c.is_inside_tree() and not c.is_queued_for_deletion():
			return c
	return null


## Every control that can take focus has a name.
func _assert_named(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c.get_path()).is_not_empty()


static func _pad(id: int) -> Dictionary:
	return { "kind": "gamepad", "key": "pad:test#%d" % id, "name": "Test pad %d" % id, "id": id, "guid": "test%d" % id, "preset": "pad_standard" }


## A card's own focus (Godot's real focus is one per window).
func _card_focus(v: Viewport) -> String:
	var c := Players.focus_of(v)
	return String(c.accessibility_name) if c else "<none>"


## P1's rows sit under This PC; the roster names everyone with their car, device, assists and ping;
## Ready is P1's own, and everyone ready starts the countdown in the status line, which un-readying
## holds.
func test_this_pc_and_ready() -> void:
	var lobby := await _lobby()
	_assert_named(lobby)
	for row in ["Profile", "Car", "Controls", "Driving Settings"]:
		assert_object(_control(lobby._p1_box, row)).override_failure_message("No " + row).is_not_null()
	for row in ["Ready", "Leave"]: # P1's: in the action bar, always on screen
		assert_object(_control(lobby._p1_box, row)).is_null()
	assert_object(lobby.ready_button).is_same(lobby._ready_buttons[Players.slots[0]])
	var me: int = Net.my_ids[0]
	var car := _control(lobby._p1_box, "Car") as Button
	assert_str(String(car.accessibility_name)).is_equal("Car: " + Net.player(me).car_name)
	assert_str(Net.player(me).car_name).is_not_empty() # picked for them: their last car or the class's own
	var row: Button = lobby._roster_rows[0]
	assert_str(String(row.accessibility_name)).starts_with("%s, %s" % [Players.slots[0].display_name(), Net.player(me).car_name])
	assert_str(String(row.accessibility_name)).contains(", host")
	assert_str(String(row.accessibility_name)).not_contains(", ready")
	assert_str(Net.player(me).device).is_equal("keyboard")
	assert_str(String(row.accessibility_name)).contains("keyboard")
	# P1's own row takes them to their rows, This PC scrolled into view.
	row.pressed.emit()
	await _frames(3)
	assert_str(String(UiKit.focus_owner(lobby).accessibility_name)).starts_with("Profile")
	var to_scroll := lobby.scroll().get_global_transform().affine_inverse()
	var last: Control = lobby._p1_rows[-1]
	assert_float((to_scroll * lobby._this_pc.get_global_transform()).origin.y).is_greater_equal(0.0)
	assert_float((to_scroll * last.get_global_transform()).origin.y + last.size.y).is_less_equal(lobby.scroll().size.y)
	# Ready: the server's, then the count.
	var ready: Button = lobby._ready_buttons[Players.slots[0]]
	ready.pressed.emit()
	await _frames(4)
	assert_bool(Net.player(me).ready).is_true()
	assert_str(String(lobby._roster_rows[0].accessibility_name)).contains(", host, ready, admin")
	assert_str(String(ready.accessibility_name)).is_equal("Ready, on")
	assert_str(lobby.status.text).is_equal("Starting in 30")
	ready.pressed.emit()
	await _frames(4)
	assert_bool(Net.player(me).ready).is_false()
	assert_str(lobby.status.text).is_equal("Start held: not everyone's ready")
	assert_str(Net.host_logic.state).is_equal("lobby")


## Another player joins in the lobby with a pad: their own card (in their own view, their own
## focus), on the server as this PC's second player. Their pad doesn't move the window's focus; a
## pad nobody has doesn't either (it's pressed to join). They ready on their card, then leave.
func test_a_local_player_joins_and_leaves() -> void:
	var lobby := await _lobby() # P1: the keyboard
	Devices.test_devices = [_pad(PAD), _pad(PAD2)]
	assert_bool(Players.joining).is_true()
	assert_bool(lobby._join_holder.visible).is_true()
	var p2 := Players.join(_pad(PAD))
	await _frames(6)
	assert_int(Net.my_ids.size()).is_equal(2)
	assert_int(Net.roster.size()).is_equal(2)
	assert_object(p2.menu_target).is_not_null()
	assert_object(Players.slots[0].menu_target).is_null() # P1 has the window
	var v := p2.menu_target
	for row in ["Profile", "Car", "Controls", "Driving Settings", "Ready", "Leave"]:
		assert_object(_control(v, row)).override_failure_message("No " + row).is_not_null()
	_assert_named(v)
	var p2_id := Net.id_of(1)
	assert_str(Net.player(p2_id).car_name).is_not_empty()
	assert_str(Net.player(p2_id).device).is_equal("xbox")
	# The window is P1's.
	var press := InputEventJoypadButton.new()
	press.device = PAD
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	assert_bool(LobbyPage.not_p1s(press, Players.slots[0])).is_true()
	press.device = PAD2 # nobody's yet
	assert_bool(LobbyPage.not_p1s(press, Players.slots[0])).is_true()
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	assert_bool(LobbyPage.not_p1s(key, Players.slots[0])).is_false()
	Players.add_device(Players.slots[0], _pad(PAD2)) # P1's own pad is P1's
	assert_bool(LobbyPage.not_p1s(press, Players.slots[0])).is_false()
	Players.remove_device(Players.slots[0], _pad(PAD2).key)
	await _frames(2)
	# P2 readies on their card; P1 isn't, so nothing starts.
	assert_str(_card_focus(v)).starts_with("Profile")
	for i in 4:
		Players.push_action(v, "ui_down")
	assert_str(_card_focus(v)).starts_with("Ready")
	Players.push_action(v, "ui_accept")
	await _frames(4)
	assert_bool(Net.player(p2_id).ready).is_true()
	assert_bool(Net.player(Net.id_of(0)).ready).is_false()
	assert_int(Net.host_logic.starting).is_equal(0)
	# Leave: off the server, the card gone, the others closed up.
	Players.push_action(v, "ui_down")
	assert_str(_card_focus(v)).is_equal("Leave")
	Players.push_action(v, "ui_accept")
	await _frames(4)
	assert_int(Players.count()).is_equal(1)
	assert_int(Net.my_ids.size()).is_equal(1)
	assert_bool(lobby._cards.is_empty()).is_true()
	assert_int(Net.server.players[Net.my_ids[0]].local_index).is_equal(0)


## Change event (host only): the event pages over the lobby in the "change" context, the last one's
## Done (or the class) back to the lobby with the new event, remembered for hosting.
func test_change_event() -> void:
	var lobby := await _lobby()
	var stack := lobby.get_parent() as MenuStack
	lobby.change_button.grab_focus()
	var event := lobby.change_event()
	await _frames(2)
	assert_str(event.title).is_equal("Event")
	assert_array(Array(event.crumbs)).contains_exactly(["Drive Online", "Lobby", "Event"])
	assert_str(event.back_hint).is_equal("Back to the lobby")
	assert_array(Array(event.steps)).contains_exactly(["Event", "Settings", "Class", "Lobby"])
	event.open_mini_games()._pick("sumo")
	await _frames(3)
	var settings := stack.top() as EventSettingsPage
	assert_array(Array(settings.crumbs)).contains_exactly(["Drive Online", "Lobby", "Mini Games", "Sumo Wrestling", "Settings"])
	assert_array(Array(settings.steps)).contains_exactly(["Event", "Settings", "Lobby"])
	assert_str(UiKit.text_of(settings.next_button)).is_equal("Done")
	assert_str(settings.next_button.accessibility_description).is_equal("Back to the lobby with this event")
	settings.go_on()
	await _frames(4)
	assert_object(stack.top()).is_same(lobby)
	assert_bool(lobby.visible).is_true()
	assert_str(Net.host_logic.event().kind).is_equal("sumo")
	assert_str(Net.host_logic.platform_id()).is_equal(EventFlow.SUMO)
	assert_str(lobby.event_label.text).starts_with("Sumo Wrestling")
	assert_bool((Settings.profile.event_memory as Dictionary).has("online/mini/sumo")).is_true()
	assert_str(UiKit.focus_owner(lobby).name).is_equal("ChangeEvent") # back where it was
	# One with a class: picked on the Class page.
	event = lobby.change_event()
	await _frames(2)
	event.open_racing()._pick("regular")
	await _frames(3)
	(stack.top() as EventSettingsPage).go_on()
	await _frames(3)
	var classes := stack.top() as ClassPage
	assert_array(Array(classes.crumbs)).contains_exactly(["Drive Online", "Lobby", "Racing", "Regular", "Class"])
	classes._pick("official.track.touring")
	await _frames(4)
	assert_object(stack.top()).is_same(lobby)
	assert_str(Net.host_logic.platform_id()).is_equal("official.track.touring")
	assert_str(Net.host_logic.event().kind).is_equal("race")
	assert_str(String(Net.host_logic.config.rotation[0].name)).is_equal("Regular race")


## The Playlist: the events in order, the one up now marked; Add event through the event pages
## puts one at the end; Move up and Remove act on the one picked, the one up now staying up.
func test_playlist() -> void:
	var lobby := await _lobby()
	var stack := lobby.get_parent() as MenuStack
	var page := lobby.open_playlist()
	await _frames(2)
	assert_str(page.title).is_equal("Playlist")
	assert_array(Array(page.crumbs)).contains_exactly(["Drive Online", "Lobby", "Playlist"])
	var first := page.body.get_node(^"Event1") as Button
	assert_str(String(first.accessibility_name)).is_equal("1. Free Drive · Proving Ground · GT, up now")
	assert_bool(page.remove_button.disabled).is_true() # the last one stays
	_assert_named(page)
	var event := page.add_event()
	await _frames(2)
	event.open_mini_games()._pick("sumo")
	await _frames(3)
	(stack.top() as EventSettingsPage).go_on()
	await _frames(4)
	assert_object(stack.top()).is_same(page)
	assert_int(Net.host_logic.config.rotation.size()).is_equal(2)
	assert_int(Net.host_logic.rotation_index).is_equal(0)
	var second := page.body.get_node(^"Event2") as Button
	assert_str(String(second.accessibility_name)).starts_with("2. Sumo Wrestling")
	assert_bool(second.button_pressed).is_true() # the new one is picked
	assert_str(Net.host_logic.event().kind).is_equal("free") # the one up now is still up
	page.move(-1)
	await _frames(2)
	assert_str(String(Net.host_logic.config.rotation[0].name)).is_equal("Sumo Wrestling")
	assert_int(Net.host_logic.rotation_index).is_equal(1) # Free Drive moved, and it's still up
	assert_str(String((page.body.get_node(^"Event2") as Button).accessibility_name)).ends_with(", up now")
	assert_bool(page.up_button.disabled).is_true()
	page.remove()
	await _frames(2)
	assert_int(Net.host_logic.config.rotation.size()).is_equal(1)
	assert_str(Net.host_logic.event().kind).is_equal("free")
	assert_int(Net.host_logic.rotation_index).is_equal(0)
	page.closed.emit()
	await _frames(2)
	assert_object(stack.top()).is_same(lobby)


## A kart lobby (D149): P1's rows have a Class; the pick goes to the server with the car, and the
## roster shows it.
func test_a_kart_lobby_picks_your_class() -> void:
	var lobby := await _lobby("official.kart.medium")
	var me: int = Net.my_ids[0]
	var klass := _control(lobby._p1_box, "Class") as Button
	assert_object(klass).is_not_null()
	for i in 3:
		if UiKit.text_of(klass).contains("Heavy"):
			break
		klass.pressed.emit()
		await _frames(2)
	assert_str(String(Settings.primary.data.get("kart_class", ""))).is_equal("official.kart.heavy")
	await _frames(4)
	assert_str(Net.server.players[me].kart_class).is_equal("official.kart.heavy")
	assert_str(String(lobby._roster_rows[0].accessibility_name)).contains("Heavy")
	Settings.primary.set_value("kart_class", "")
