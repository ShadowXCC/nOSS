extends GdUnitTestSuite
## The Players screen (LOC-04, docs/INPUT.md §3): each card has its own focus, driven only by its
## player; when everyone is ready the drive starts.

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
	p1.ready = true
	menu._check_start()
	assert_bool(started[0]).is_false()
	p2.ready = true
	menu._check_start()
	assert_bool(started[0]).is_true()
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
