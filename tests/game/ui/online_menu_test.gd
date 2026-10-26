extends GdUnitTestSuite
## Drive Online (docs/UI_FLOW.md §7, MP-01, ACC-03): main menu -> Drive Online -> Host -> the
## event pages -> the lobby -> Leave by keyboard alone, every control named; Sumo, Drag, Stock Car,
## a kart cup, a highway run and a time trial hosted through the pages; Join's recent servers and favourites, the password
## page for a locked server, the Official tab that's off; the lobby's event line. The lobby page
## itself has its own suite (lobby_page_test).

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
	Settings.net_recent = []
	Settings.net_favourites = []
	Settings.profile.event_memory = {}
	Settings.race_event = {} # no old Race menu setup to fall back to
	Settings.profile.last_platform = "official.track.gt"


func after_test() -> void:
	Net.leave()


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


func _action(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		get_viewport().push_input(e)


func _focused(runner: GdUnitSceneRunner) -> String:
	var c := runner.scene().get_viewport().gui_get_focus_owner()
	return String(c.accessibility_name) if c else "<none>"


func _find(root: Node, cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls and not n.is_queued_for_deletion():
			return n
	return null


## Every control that can take focus has a name.
func _assert_named(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).override_failure_message("Unnamed %s" % c.get_path()).is_not_empty()


func _control(root: Node, accessible: String) -> Control:
	for c: Control in root.find_children("*", "Control", true, false):
		if String(c.accessibility_name).get_slice(":", 0) == accessible and c.is_inside_tree() and not c.is_queued_for_deletion():
			return c
	return null


## The step row's "Step 2 of 5".
func _step(page: MenuPage) -> String:
	return page.step_text()


## Host -> the event pages -> Regular -> its class -> the lobby, by keys; Leave comes back to Drive
## Online.
func test_host_a_race_by_keys() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	assert_str(_focused(runner)).is_equal("Local Drive")
	await _key(KEY_DOWN)
	assert_str(_focused(runner)).is_equal("Drive Online")
	await _key(KEY_ENTER)
	await _frames(4)
	var online: DriveOnlinePage = _find(runner.scene(), "DriveOnlinePage")
	assert_object(online).is_not_null()
	_assert_named(online)
	assert_array(Array(online.crumbs)).contains_exactly(["Drive Online"])
	assert_str(_focused(runner)).is_equal("Host")
	await _key(KEY_ENTER)
	await _frames(4)
	var host: HostOptionsPage = _find(runner.scene(), "HostOptionsPage")
	assert_object(host).is_not_null()
	_assert_named(host)
	assert_bool(online.visible).is_false() # one page at a time
	assert_str(_step(host)).is_equal("Step 1 of 5")
	for row in ["Name", "Password", "Players", "Port", "LAN discovery", "Open port", "Next", "Back"]:
		assert_object(_control(host, row)).override_failure_message("No " + row).is_not_null()
	assert_str(_focused(runner)).is_equal("Name")
	await _key(KEY_UP) # wraps to Back, then Next beside it
	await _key(KEY_UP)
	assert_str(_focused(runner)).is_equal("Next")
	await _key(KEY_ENTER)
	await _frames(4)
	var event: LocalDrivePage = _find(runner.scene(), "LocalDrivePage")
	assert_object(event).is_not_null()
	assert_str(event.title).is_equal("Event")
	assert_array(Array(event.crumbs)).contains_exactly(["Drive Online", "Host", "Event"])
	assert_str(_step(event)).is_equal("Step 2 of 5")
	assert_object(_control(event, "Drive again")).is_null()
	assert_str(_focused(runner)).is_equal("Racing")
	await _key(KEY_ENTER)
	await _frames(4)
	var racing: RacingPage = _find(runner.scene(), "RacingPage")
	assert_object(racing.switch).is_not_null() # time trials host too (P10)
	assert_bool(racing.tt).is_false()
	assert_str(_focused(runner)).is_equal("Regular")
	await _key(KEY_ENTER)
	await _frames(4)
	var settings: EventSettingsPage = _find(runner.scene(), "EventSettingsPage")
	assert_str(settings.title).is_equal("Regular race")
	assert_array(Array(settings.crumbs)).contains_exactly(["Drive Online", "Host", "Racing", "Regular", "Settings"])
	assert_str(_step(settings)).is_equal("Step 3 of 5")
	assert_str(UiKit.text_of(settings.next_button)).is_equal("Next")
	_assert_named(settings)
	await _key(KEY_UP) # wraps to Back, then Next beside it
	await _key(KEY_UP)
	assert_str(_focused(runner)).is_equal("Next")
	await _key(KEY_ENTER)
	await _frames(4)
	var classes: ClassPage = _find(runner.scene(), "ClassPage")
	assert_str(_step(classes)).is_equal("Step 4 of 5")
	assert_str(_focused(runner)).starts_with("Track GT")
	await _key(KEY_ENTER)
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	assert_str(Net.host_logic.event().kind).is_equal("race")
	assert_str(Net.host_logic.platform_id()).is_equal("official.track.gt")
	assert_int(Net.host_logic.config.port).is_equal(int(Settings.net_host.port))
	var lobby: LobbyPage = _find(runner.scene(), "LobbyPage")
	assert_object(lobby).is_not_null()
	_assert_named(lobby)
	assert_array(Array(lobby.crumbs)).contains_exactly(["Drive Online", "Lobby"])
	assert_str(_step(lobby)).is_equal("Step 5 of 5")
	for row in ["Change event", "Playlist", "Force start", "Profile", "Car", "Controls", "Driving Settings", "Ready", "Leave"]:
		assert_object(_control(lobby, row)).override_failure_message("No " + row).is_not_null()
	# The lobby took the place of the pages on the way.
	for gone in ["HostOptionsPage", "LocalDrivePage", "RacingPage", "EventSettingsPage", "ClassPage"]:
		assert_object(_find(runner.scene(), gone)).override_failure_message(gone + " still up").is_null()
	assert_str(lobby.event_label.text).starts_with("Race, ")
	assert_int(Net.roster.size()).is_equal(1)
	assert_str(_focused(runner)).starts_with("Player 1")
	# Chat from the lobby.
	Net.say("hello")
	await _frames(2)
	assert_bool(Net.chat_log.any(func(l: Dictionary) -> bool: return l.text == "hello")).is_true()
	# Esc leaves and closes the server; Drive Online is back, on Host.
	await _key(KEY_ESCAPE)
	await _frames(4)
	assert_bool(Net.online()).is_false()
	assert_bool(online.visible).is_true()
	assert_object(_find(runner.scene(), "LobbyPage")).is_null()
	assert_str(_focused(runner)).is_equal("Host")


## The Event page's `type` (and on Racing or Mini Games, `variant`) to its Settings page.
func _settings(runner: GdUnitSceneRunner, type: String, variant := "") -> EventSettingsPage:
	var online: DriveOnlinePage = _find(runner.scene(), "DriveOnlinePage")
	var event := online.open_host().open_event()
	await _frames(2)
	if type == "racing":
		event.open_racing()._pick(variant)
	elif type == "mini":
		event.open_mini_games()._pick(variant)
	else:
		event._pick(type)
	await _frames(3)
	return _find(runner.scene(), "EventSettingsPage")


func _open_online(runner: GdUnitSceneRunner) -> void:
	await _frames(4)
	(runner.scene() as Node).call("_open_online")
	await _frames(2)


## Sumo has no Class step: its Next hosts. Its ground is made from the settings: the lobby shows no
## track.
func test_hosting_sumo() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var settings := await _settings(runner, "mini", "sumo")
	assert_array(Array(settings.crumbs)).contains_exactly(["Drive Online", "Host", "Mini Games", "Sumo Wrestling", "Settings"])
	assert_array(Array(settings.steps)).contains_exactly(["Host", "Event", "Settings", "Lobby"])
	assert_str(UiKit.text_of(settings.next_button)).is_equal("Start hosting")
	assert_str(settings.next_button.accessibility_description).is_equal("Start the server and open the lobby")
	settings.go_on()
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	assert_str(Net.host_logic.event().kind).is_equal("sumo")
	assert_str(Net.host_logic.platform_id()).is_equal(EventFlow.SUMO)
	var lobby: LobbyPage = _find(runner.scene(), "LobbyPage")
	assert_str(lobby.event_label.text).starts_with("Sumo Wrestling   Sumo")
	assert_str(lobby.event_label.text).not_contains("Proving Ground")
	assert_str(_step(lobby)).is_equal("Step 4 of 4") # no Class step
	# Remembered for hosting, apart from Local Drive's.
	assert_bool((Settings.profile.event_memory as Dictionary).has("online/mini/sumo")).is_true()
	assert_bool((Settings.profile.event_memory as Dictionary).has("mini/sumo")).is_false()


## Drag picks its class on the Class page, whose confirm hosts.
func test_hosting_drag() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var settings := await _settings(runner, "mini", "drag")
	assert_str(UiKit.text_of(settings.next_button)).is_equal("Next")
	settings.go_on()
	await _frames(3)
	var classes: ClassPage = _find(runner.scene(), "ClassPage")
	assert_array(Array(classes.crumbs)).contains_exactly(["Drive Online", "Host", "Mini Games", "Drag Strip", "Class"])
	classes._pick("official.drag.pro")
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	assert_str(Net.host_logic.event().kind).is_equal("drag")
	assert_str(Net.host_logic.platform_id()).is_equal("official.drag.pro")
	assert_str((_find(runner.scene(), "LobbyPage") as LobbyPage).event_label.text).starts_with("Drag Strip, ")


## Stock Car: only ovals, its own class, no Class step.
func test_hosting_stock_car() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var settings := await _settings(runner, "racing", "stock_car")
	assert_bool(settings.flow.tracks().all(func(e: Dictionary) -> bool: return "oval" in e.get("tags", []))).is_true()
	assert_str(UiKit.text_of(settings.next_button)).is_equal("Start hosting")
	settings.go_on()
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	assert_str(Net.host_logic.event().kind).is_equal("race")
	assert_str(Net.host_logic.platform_id()).is_equal(EventFlow.STOCK_CAR)
	assert_str(Net.host_logic.track_info().id).is_equal("piedmont_speedway")
	assert_str((_find(runner.scene(), "LobbyPage") as LobbyPage).event_label.text).starts_with("Stock Car race, 10 laps")


## Kart: a race or a cup (P10). A cup's races are the playlist, each marked as the cup's; the
## lobby names the race up ("Spark Cup, race 1 of 4"). Each kart's class is on its card.
func test_hosting_a_kart_cup() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var kart := await _settings(runner, "racing", "kart")
	assert_object(kart.row_named("Play")).is_not_null()
	assert_object(kart.row_named("Laps")).is_not_null()
	kart.flow.cup = "res://data/cups/spark_cup.cup.json"
	kart.rebuild("Play")
	await _frames(2)
	assert_object(kart.row_named("Cup")).is_not_null()
	assert_object(kart.row_named("Laps")).is_null()
	assert_str(UiKit.text_of(kart.next_button)).is_equal("Start hosting")
	kart.go_on()
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	var rotation := Net.host_logic.config.rotation
	assert_int(rotation.size()).is_equal(4)
	for i in 4:
		assert_dict(Net.host_logic.config.cup_of(i)).is_equal({ "id": "spark_cup", "name": "Spark Cup", "race": i, "races": 4 })
		assert_str(String(rotation[i].name)).is_equal("Spark Cup, race %d of 4" % (i + 1))
	assert_str(Net.host_logic.config.event(1).grid).is_equal("reverse") # later races: the standings reversed
	assert_str(Net.host_logic.platform_id()).is_equal(EventFlow.KART)
	assert_str((_find(runner.scene(), "LobbyPage") as LobbyPage).event_label.text).starts_with("Spark Cup, race 1 of 4, 2 laps")


## Highway: every mode (P10), each with its own rows: a run picks its run.
func test_hosting_highway_modes() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var highway := await _settings(runner, "highway")
	assert_object(highway.row_named("Mode")).is_not_null()
	assert_object(highway.row_named("Way round")).is_not_null()
	highway.flow.event.sub = "run"
	highway.rebuild("Mode")
	await _frames(2)
	assert_object(highway.row_named("Run")).is_not_null()
	assert_object(highway.row_named("Way round")).is_null()
	highway.go_on()
	await _frames(3)
	(_find(runner.scene(), "ClassPage") as ClassPage)._pick("official.highway.street")
	await _frames(6)
	assert_str(Net.host_logic.event().kind).is_equal("highway")
	assert_str(Net.host_logic.event().sub).is_equal("run")
	assert_array(Array(Net.host_logic.event().sessions())).contains_exactly(["run"])
	assert_bool(Net.host_logic.takes_joiners()).is_false() # a run under way waits for the next
	assert_str((_find(runner.scene(), "LobbyPage") as LobbyPage).event_label.text).starts_with("Highway run")


## Time trials online (P10): the Race | Time Trial switch on the host's Racing page; the session is
## timed (Minutes, 10 to start); the lobby says so.
func test_hosting_a_time_trial() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var online: DriveOnlinePage = _find(runner.scene(), "DriveOnlinePage")
	var racing := online.open_host().open_event().open_racing()
	await _frames(3)
	assert_object(racing.switch).is_not_null()
	racing.switch._pick(1, false) # as Q or E would
	await _frames(2)
	assert_bool(racing.tt).is_true()
	racing._pick("regular")
	await _frames(3)
	var settings: EventSettingsPage = _find(runner.scene(), "EventSettingsPage")
	assert_array(Array(settings.crumbs)).contains_exactly(["Drive Online", "Host", "Racing", "Regular Time Trial", "Settings"])
	var minutes := settings.row_named("Minutes")
	assert_object(minutes).is_not_null()
	assert_str(UiKit.text_of(minutes)).contains("10 min")
	settings.go_on()
	await _frames(3)
	(_find(runner.scene(), "ClassPage") as ClassPage)._pick("official.track.gt")
	await _frames(6)
	assert_bool(Net.is_server()).is_true()
	assert_str(Net.host_logic.event().kind).is_equal("time_trial")
	assert_int(Net.host_logic.event().tt_min).is_equal(10)
	assert_bool(Net.host_logic.takes_joiners()).is_true() # drop in to hot-lap
	assert_str((_find(runner.scene(), "LobbyPage") as LobbyPage).event_label.text).starts_with("Time trial, 10 min")


## Hosting lists only tracks that can go online; Free Drive there has no AI rows.
func test_hosting_free_drive() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await _open_online(runner)
	var free := await _settings(runner, "free")
	assert_bool(free.flow.tracks().all(func(e: Dictionary) -> bool: return ContentIndex.shareable(TrackLoader.read_manifest(e.path)))).is_true()
	assert_object(free.row_named("AI cars")).is_null()
	assert_object(free.row_named("Collisions")).is_not_null()


func _join_page() -> JoinPage:
	var page: JoinPage = auto_free(JoinPage.new())
	add_child(page)
	await _frames(2)
	return page


func test_bad_address_and_no_server() -> void:
	var page := await _join_page()
	page.join("", "")
	assert_str(page.status.text).is_equal("Enter an address")
	page.join("127.0.0.1:47999", "")
	assert_str(page.status.text).starts_with("Joining")
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and page.status.text.begins_with("Joining"):
		await _frames(1)
	assert_str(page.status.text).is_equal("Server not found")


## The Official tab shows, off ("Coming soon"); the tab keys skip it.
func test_official_tab_is_off() -> void:
	var page := await _join_page()
	assert_array(Array(page.tabs)).contains_exactly(["On your network", "Direct", "Official"])
	var official := page.tab_row.button(2)
	assert_bool(official.disabled).is_true()
	assert_str(official.accessibility_name).is_equal("Official")
	assert_str(official.accessibility_description).is_equal("Coming soon")
	assert_str(UiKit.text_of(official)).is_equal("Official · Coming soon")
	page.show_tab(1)
	await _frames(2) # the Address field it focused stops taking typing a frame later
	_action("ui_tab_next")
	await _frames(2)
	assert_str(page.tab_name()).is_equal("On your network")
	_action("ui_tab_prev")
	await _frames(2)
	assert_str(page.tab_name()).is_equal("Direct")
	_assert_named(page)


## Joined servers go first in Recent (8 at most, each once); Save makes one a favourite, named
## after the server, listed above; Edit renames it, and Remove takes it off.
func test_recent_servers_and_favourites() -> void:
	for i in 10:
		JoinPage.remember_recent("Server %d" % i, "10.0.0.%d:47800" % i)
	JoinPage.remember_recent("Server 3 again", "10.0.0.3:47800")
	var recent := JoinPage.recent()
	assert_int(recent.size()).is_equal(JoinPage.RECENT_MAX)
	assert_str(recent[0].name).is_equal("Server 3 again")
	assert_int(recent.filter(func(r: Dictionary) -> bool: return r.address == "10.0.0.3:47800").size()).is_equal(1)
	# A join that went through: named by the server (or its address, with none).
	var page := await _join_page()
	page._joining = { "address": "192.168.1.20:47801", "name": "" }
	page._on_joined()
	assert_dict(JoinPage.recent()[0]).is_equal({ "name": "192.168.1.20:47801", "address": "192.168.1.20:47801" })
	page.show_tab(1)
	await _frames(2)
	assert_object(_control(page, "Favourites")).is_null()
	var save := _side(page, "192.168.1.20:47801")
	assert_str(save.accessibility_name).is_equal("Save")
	save.pressed.emit()
	await _frames(2)
	assert_array(JoinPage.favourites()).contains_exactly([{ "name": "192.168.1.20:47801", "address": "192.168.1.20:47801" }])
	# Favourites first; the recent one's Save is off now.
	var rows := page.body.get_children().filter(func(c: Node) -> bool: return c is HBoxContainer and c.get_child(0) is Button)
	assert_str(String((rows[0].get_child(0) as Button).accessibility_name)).is_equal("192.168.1.20:47801, 192.168.1.20:47801")
	assert_str(String((rows[0].get_child(1) as Button).accessibility_name)).is_equal("Edit")
	assert_bool((rows[1].get_child(1) as Button).disabled).is_true()
	_assert_named(page)
	# Right from a row reaches its Edit, left goes back.
	var row_button := rows[0].get_child(0) as Button
	assert_object(row_button.get_node(row_button.focus_neighbor_right)).is_same(rows[0].get_child(1))
	# Edit: renamed as typed, kept on Back.
	(rows[0].get_child(1) as Button).pressed.emit()
	await _frames(2)
	var edit := _over(page)
	assert_str(edit.title).is_equal("192.168.1.20:47801")
	var name_field := _control(edit, "Name") as LineEdit
	name_field.text = "Ana's PC"
	name_field.text_changed.emit("Ana's PC")
	edit.closed.emit()
	await _frames(2)
	assert_str(JoinPage.favourites()[0].name).is_equal("Ana's PC")
	# Remove.
	rows = page.body.get_children().filter(func(c: Node) -> bool: return c is HBoxContainer and c.get_child(0) is Button)
	(rows[0].get_child(1) as Button).pressed.emit()
	await _frames(2)
	edit = _over(page)
	(_control(edit, "Remove") as Button).pressed.emit()
	await _frames(2)
	assert_array(JoinPage.favourites()).is_empty()


## The page opened over `page` (in its place: it's not on a stack).
func _over(page: MenuPage) -> MenuPage:
	for n: Node in page.find_children("*", "", true, false):
		if n is MenuPage and not n.is_queued_for_deletion():
			return n
	return null


## The Save or Edit beside the server row at `address`.
func _side(page: JoinPage, address: String) -> Button:
	for c: Node in page.body.get_children():
		if c is HBoxContainer and c.get_child(0).get_meta(&"address", "") == address:
			return c.get_child(1) as Button
	return null


## A locked server on the network asks for its password before joining; a join that needs one asks
## too; a wrong one keeps the page up.
func test_a_locked_server_asks_for_its_password() -> void:
	var page := await _join_page()
	page._scanner.servers["test"] = { "name": "Locked", "ip": "127.0.0.1", "port": 47999, "players": 1, "max": 8, "password": true,
		"class": "GT", "track": "Proving Ground", "state": "lobby", "version": NetProtocol.game_version(), "fp": "", "seen": 1e9 }
	page.refresh_lan()
	await _frames(2)
	var row := _control(page, "Locked, 1 of 8 players, GT, Proving Ground, password") as Button
	assert_object(row).is_not_null()
	row.pressed.emit()
	await _frames(2)
	var ask: PasswordPage = _find(page, "PasswordPage")
	assert_object(ask).is_not_null()
	assert_str(ask.title).is_equal("Password")
	assert_array(Array(ask.crumbs)).contains_exactly(["Drive Online", "Join", "Password"])
	assert_bool(ask.body.get_children().any(func(c: Node) -> bool: return c is Label and c.text == "Locked needs a password.")).is_true()
	assert_bool((_control(ask, "Password") as LineEdit).secret).is_true()
	_assert_named(ask)
	assert_bool(Net.online()).is_false() # nothing tried yet
	(_control(ask, "Join") as Button).pressed.emit()
	assert_str(ask.status.text).is_equal("Type the password")
	# A wrong password: said on the page, which stays.
	page._joining = { "address": "127.0.0.1:47999", "name": "Locked" }
	page._on_failed("Wrong password")
	assert_str(ask.status.text).is_equal("Wrong password")
	assert_bool(is_instance_valid(ask) and ask.is_inside_tree()).is_true()
	ask.closed.emit()
	await _frames(2)
	# A direct join that turns out to need one asks, then goes again.
	page._joining = { "address": "127.0.0.1:47998", "name": "" }
	page._on_failed("Password needed")
	await _frames(2)
	ask = _find(page, "PasswordPage")
	assert_object(ask).is_not_null()
	assert_bool(ask.body.get_children().any(func(c: Node) -> bool: return c is Label and c.text == "127.0.0.1:47998 needs a password.")).is_true()
	ask._submit("secret")
	assert_str(ask.status.text).starts_with("Joining 127.0.0.1:47998")
	Net.leave()
	page._joining = {}


func test_lobby_event_text() -> void:
	var race := RaceEvent.new()
	race.kind = "race"
	race.race_laps = 10
	assert_str(LobbyPage.event_text(race, EventFlow.STOCK_CAR)).is_equal("Stock Car race, 10 laps")
	assert_str(LobbyPage.event_text(race, "official.kart.medium")).is_equal("Kart race, 10 laps")
	assert_str(LobbyPage.event_text(race, "official.track.gt")).is_equal("Race, 10 laps")
	assert_str(LobbyPage.event_text(RaceEvent.battle("hits"), EventFlow.KART)).is_equal("Kart Battle, most hits")
	assert_str(LobbyPage.event_text(RaceEvent.highway("cruise"), "official.highway.street")).is_equal("Highway cruise")
	assert_str(LobbyPage.event_text(RaceEvent.sumo(), EventFlow.SUMO)).is_equal("Sumo Wrestling")
	assert_str(LobbyPage.event_text(RaceEvent.free_drive(), "official.track.gt")).is_equal("Free Drive")
	assert_str(LobbyPage.event_text(RaceEvent.endless(), "official.endless.cruiser")).is_empty()
	var tt := RaceEvent.time_trial()
	tt.tt_min = 15
	assert_str(LobbyPage.event_text(tt, "official.track.gt")).is_equal("Time trial, 15 min")
	assert_str(LobbyPage.event_text(tt, "official.kart.light")).is_equal("Kart time trial, 15 min")
	assert_str(LobbyPage.event_text(RaceEvent.highway("score"), "official.highway.street")).is_equal("Highway score attack")
	# A kart cup's race, and its standings so far, then once it's over.
	var cup := { "name": "Spark Cup", "race": 2, "races": 4, "cup": "Spark Cup", "run": 1, "of": 4,
		"standings": [{ "name": "Ana", "points": 15, "wins": 1 }, { "name": "Bo", "points": 12, "wins": 0 }] }
	race.race_laps = 3
	assert_str(LobbyPage.cup_race_text(cup, race)).is_equal("Spark Cup, race 2 of 4, 3 laps")
	assert_str(LobbyPage.standings_text(cup)).is_equal("After race 1 of 4: Ana 15, Bo 12")
	cup.run = 4
	assert_str(LobbyPage.standings_text(cup)).is_equal("Spark Cup final: 1st Ana 15, 2nd Bo 12")
	assert_str(LobbyPage.standings_text({})).is_empty()
