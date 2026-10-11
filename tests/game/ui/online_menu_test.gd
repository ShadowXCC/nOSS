extends GdUnitTestSuite
## Online menus by keyboard alone (MP-01, ACC-03): title -> Online -> Host -> lobby -> Leave,
## every control named, chat from the lobby.

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"


func before() -> void:
	Settings.use_folder("user://tests/online_menu")


func after() -> void:
	Net.leave()
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	var cfg := ServerConfig.defaults()
	cfg.port = 47950 + randi() % 40
	cfg.lan = false
	cfg.upnp = false # no router discovery in tests
	Settings.net_host = cfg.to_dict()


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await _frames()
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _frames()


func _focused(runner: GdUnitSceneRunner) -> String:
	var c := runner.scene().get_viewport().gui_get_focus_owner()
	return String(c.accessibility_name) if c else "<none>"


func _find(root: Node, cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls:
			return n
	return null


## Every control that can take focus has a name.
func _assert_named(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c.get_path()).is_not_empty()


func test_host_a_game_and_leave_by_keys() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Free Drive")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Online")
	await _key(KEY_ENTER)
	await _frames(4)
	var online: OnlineMenu = _find(runner.scene(), "OnlineMenu")
	assert_object(online).is_not_null()
	_assert_named(online)
	assert_str(_focused(runner)).is_equal("Players")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Host")
	await _key(KEY_ENTER)
	await _frames(4)
	var host: HostMenu = _find(runner.scene(), "HostMenu")
	assert_object(host).is_not_null()
	_assert_named(host)
	assert_str(_focused(runner)).is_equal("Name")
	await _key(KEY_UP) # wraps to Back
	await _key(KEY_UP)
	assert_str(_focused(runner)).is_equal("Start hosting")
	await _key(KEY_ENTER)
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	var lobby: LobbyMenu = _find(runner.scene(), "LobbyMenu")
	assert_object(lobby).is_not_null()
	_assert_named(lobby)
	assert_int(Net.roster.size()).is_equal(1)
	assert_str(_focused(runner)).starts_with("Player 1")
	# The player's row says which car they start with.
	assert_str(_focused(runner)).contains("nOSS")
	# Chat from the lobby.
	Net.say("hello")
	await _frames(2)
	assert_bool(Net.chat_log.any(func(l: Dictionary) -> bool: return l.text == "hello")).is_true()
	# Esc leaves and closes the server; the Online menu is back.
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(Net.online()).is_false()
	assert_bool(online.visible).is_true()
	assert_object(_find(runner.scene(), "LobbyMenu")).is_null()


func test_bad_address_and_no_server() -> void:
	var menu: OnlineMenu = auto_free(OnlineMenu.new())
	add_child(menu)
	await _frames(2)
	menu._join("", "")
	assert_str(menu._status.text).is_equal("Enter an address")
	menu._join("127.0.0.1:47999", "")
	assert_str(menu._status.text).starts_with("Joining")
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and menu._status.text.begins_with("Joining"):
		await _frames(1)
	assert_str(menu._status.text).is_equal("Server not found")
