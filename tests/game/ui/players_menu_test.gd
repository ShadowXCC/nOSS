extends GdUnitTestSuite
## The Players screen (LOC-04, docs/INPUT.md §3): each card has its own focus, driven only by its
## player; when everyone is ready a countdown runs (docs/UI_FLOW.md §5.7), then the drive starts.

const PAD := 7
const PAD2 := 8


func before() -> void:
	Settings.use_folder("user://tests/players_menu_suite")


func after() -> void:
	Devices.test_devices = []
	Players.clear()
	Settings.use_folder("user://")


func test_each_card_has_its_own_focus_and_ready_starts() -> void:
	Players.clear()
	Devices.test_devices = [_pad(PAD), _pad(PAD2)]
	var menu := PlayersMenu.new()
	menu.platform_id = "official.track.gt"
	add_child(menu)
	var p1 := Players.join(_pad(PAD))
	var p2 := Players.join(_pad(PAD2))
	for i in 3:
		await get_tree().process_frame
	var v1 := p1.menu_target
	var v2 := p2.menu_target
	assert_object(v1).is_not_null()
	assert_object(v2).is_not_same(v1)
	assert_str(_focus(v1)).starts_with("Profile")
	assert_str(_focus(v2)).starts_with("Profile")
	# P1 moves down; P2's focus stays.
	Players.push_action(v1, "ui_down")
	await get_tree().process_frame
	assert_str(_focus(v1)).starts_with("Car")
	assert_str(_focus(v2)).starts_with("Profile")
	var started := [false]
	menu.started.connect(func() -> void: started[0] = true)
	PlayersMenu.countdown_s = 0.0
	p1.ready = true
	menu._check_start()
	assert_bool(started[0]).is_false()
	p2.ready = true
	menu._check_start()
	assert_bool(started[0]).is_true()
	PlayersMenu.countdown_s = 3.0
	menu.queue_free()
	await get_tree().process_frame


## Everyone ready: "Starting in 3" in the hint line, counting down, then the start. Un-readying
## or a player joining stops it (the hint says how to join again); a player leaving starts it
## again from the top for the rest.
func test_countdown_and_cancelling_it() -> void:
	Players.clear()
	Devices.test_devices = [_pad(PAD), _pad(PAD2)]
	var menu := PlayersMenu.new()
	menu.platform_id = "official.track.gt"
	add_child(menu)
	var hint: Label = menu.find_child("Hint", true, false)
	var join_text := hint.text
	assert_str(join_text).starts_with("Press any button to join.")
	var started := [0]
	menu.started.connect(func() -> void: started[0] += 1)
	var p1 := Players.join(_pad(PAD))
	await get_tree().process_frame
	# Ready on the card.
	p1.ready = true
	menu._check_start()
	assert_bool(menu.counting_down()).is_true()
	assert_str(hint.text).is_equal("Starting in 3")
	assert_int(started[0]).is_zero()
	await get_tree().create_timer(1.2).timeout
	assert_str(hint.text).is_equal("Starting in 2")
	# Un-ready: stopped.
	Players.push_action(p1.menu_target, "ui_cancel") # back on a ready card un-readies
	await get_tree().process_frame
	assert_bool(p1.ready).is_false()
	assert_bool(menu.counting_down()).is_false()
	assert_str(hint.text).is_equal(join_text)
	# Ready again, then a second player joins: stopped.
	p1.ready = true
	menu._check_start()
	assert_bool(menu.counting_down()).is_true()
	var p2 := Players.join(_pad(PAD2))
	await get_tree().process_frame
	assert_bool(menu.counting_down()).is_false()
	assert_str(hint.text).is_equal(join_text)
	# Both ready, then P2 leaves: P1 counts down again from the top, and starts.
	p2.ready = true
	menu._check_start()
	PlayersMenu.countdown_s = 0.3
	Players.leave(p2)
	await get_tree().process_frame
	assert_bool(menu.counting_down()).is_true()
	assert_str(hint.text).is_equal("Starting in 1")
	await get_tree().create_timer(0.5).timeout
	assert_int(started[0]).is_equal(1)
	assert_bool(menu.counting_down()).is_false()
	assert_str(hint.text).is_equal(join_text)
	PlayersMenu.countdown_s = 3.0
	menu.queue_free()
	await get_tree().process_frame


## The card's own focus (Godot's real focus is one per window).
func _focus(v: Viewport) -> String:
	var c := Players.focus_of(v)
	return UiKit.text_of(c as Button) if c is Button else "<none>"


static func _pad(id: int) -> Dictionary:
	return { "kind": "gamepad", "key": "pad:test#%d" % id, "name": "Test pad %d" % id, "id": id, "guid": "test%d" % id, "preset": "pad_standard" }


## Before going online (Changes.md): no car row, a Done row, back on a card returns to the Online
## menu (which stays open, though the same B reaches it raw), and empty places say how to join.
func test_online_players_screen_returns_to_online() -> void:
	Players.clear()
	Devices.test_devices = [_pad(PAD)]
	var online := OnlineMenu.new()
	add_child(online)
	await get_tree().process_frame
	var closed := [false]
	online.closed.connect(func() -> void: closed[0] = true)
	online._open_players()
	var menu: PlayersMenu = online.find_children("*", "PlayersMenu", true, false)[0]
	var p1 := Players.join(_pad(PAD))
	for i in 3:
		await get_tree().process_frame
	var rows: Array = p1.menu_target.find_children("*", "Button", true, false).map(func(b: Button) -> String: return UiKit.text_of(b))
	assert_bool(rows.any(func(t: String) -> bool: return t.begins_with("Car"))).is_false()
	assert_bool(rows.has("Done")).is_true()
	assert_bool(menu._holders[1].get_node(^"JoinHint").visible).is_true()
	assert_bool(menu._holders[0].get_node(^"JoinHint").visible).is_false()
	# B: raw into the window, and pushed into the card.
	var raw := InputEventAction.new()
	raw.action = "ui_cancel"
	raw.pressed = true
	get_tree().root.push_input(raw)
	Players.push_action(p1.menu_target, "ui_cancel")
	for i in 3:
		await get_tree().process_frame
	assert_bool(is_instance_valid(menu) and menu.is_inside_tree()).is_false()
	assert_bool(closed[0]).is_false()
	assert_int(Players.count()).is_equal(1)
	online.queue_free()
	await get_tree().process_frame
