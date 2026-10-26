extends GdUnitTestSuite
## Splitscreen time trials (docs/GAMEMODES.md §1, docs/UI_FLOW.md P6): a lane per player, each
## with their own best file and their own ghost, which only their camera draws; P1 keeps the
## best from before; a kart player's ghosts are kept under their own class; and the walk from the
## main menu with two players.

const TRACK := "res://content/tracks/proving_ground"
const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"
const PAD := 7

var _requested: Array = []


func before() -> void:
	Settings.use_folder("user://tests/time_trial")


func after() -> void:
	Players.clear()
	Devices.test_devices = []
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	Settings.set_primary(Settings.get_profile("player1")) # clearing two players makes P2's profile the main one
	Devices.test_devices = []
	_remove_tree(TimeTrial.dir)
	_remove_tree(Leaderboard.dir)
	_requested.clear()


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _session(platform_id := "official.track.gt", ai_players := 1) -> TrackSession:
	var s := TrackSession.new()
	s.track_path = TRACK
	s.platform_id = platform_id
	s.event = RaceEvent.time_trial()
	s.ai_players = ai_players
	add_child(s)
	return s


func _wait_for_cars(s: TrackSession, n: int) -> void:
	for i in 600:
		if s.players.size() >= n and s.players.all(func(p: SessionPlayer) -> bool: return p.vehicle != null):
			return
		await get_tree().physics_frame


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


## A lap of `time` for `lane`, as if it had recorded it from where the car stands.
func _lap(lane: TimeTrial.Lane, time: float) -> void:
	var v := lane.player.vehicle
	for k in 4:
		lane.recording.record(k * 0.5, v.global_transform, Vector3.ZERO, 0.0)
	lane._on_lap(time, true, true)


static func _ids(choices: Array) -> Array:
	return choices.map(func(c: Array) -> String: return String(c[0]))


## Two players: two lanes on two ghost layers. Each lap goes in its player's own best file, and
## each can pick the other's best as a ghost to race.
func test_two_players_give_two_lanes_and_two_best_files() -> void:
	var s := _session()
	await _wait_for_cars(s, 2)
	assert_bool(s.solo).is_false()
	assert_bool(Players.joining).is_true()
	var tt := s.time_trial
	assert_int(tt.lanes.size()).is_equal(2)
	var a := tt.lanes[0]
	var b := tt.lanes[1]
	assert_object(a.player).is_same(s.players[0])
	assert_object(b.player).is_same(s.players[1])
	assert_int(a.layer).is_not_equal(b.layer)
	_lap(a, 62.0)
	_lap(b, 61.0)
	assert_str(a.best_path().get_file()).is_equal("best_player1.json")
	assert_str(b.best_path().get_file()).is_equal("best_ai2.json")
	assert_str(a.best_path().get_base_dir()).is_equal(b.best_path().get_base_dir())
	assert_bool(FileAccess.file_exists(a.best_path())).is_true()
	assert_bool(FileAccess.file_exists(b.best_path())).is_true()
	# A slower lap keeps the best.
	_lap(a, 63.0)
	assert_float(float(a.best().meta.time)).is_equal(62.0)
	assert_float(float(b.best().meta.time)).is_equal(61.0)
	assert_array(_ids(a.choices())).contains_exactly(["best", "best_ai2.json", "off"])
	assert_array(_ids(b.choices())).contains_exactly(["best", "best_player1.json", "off"])
	b.pick("best_player1.json")
	assert_float(float(b.ghost.meta.time)).is_equal(62.0)
	s.queue_free()
	await get_tree().process_frame


## P1's best from before splitscreen time trials (best.json) is still theirs until they beat it.
func test_p1_keeps_the_best_from_before() -> void:
	var s := _session("official.track.gt", 0)
	await _wait_for_cars(s, 1)
	var lane := s.time_trial.lanes[0]
	var old := Ghost.new()
	var v := lane.player.vehicle
	old.record(0.0, v.global_transform, Vector3.ZERO, 0.0)
	old.record(0.5, v.global_transform, Vector3.ZERO, 0.0)
	old.meta = { "time": 60.0, "driver": "Before" }
	old.save(lane.folder().path_join("best.json"))
	assert_float(float(lane.best().meta.time)).is_equal(60.0)
	assert_array(_ids(lane.choices())).contains_exactly(["best", "off"])
	_lap(lane, 61.0)
	assert_bool(FileAccess.file_exists(lane.best_path())).is_false()
	_lap(lane, 59.0)
	assert_float(float(lane.best().meta.time)).is_equal(59.0)
	assert_bool(FileAccess.file_exists(lane.best_path())).is_true()
	s.queue_free()
	await get_tree().process_frame


## Each player's ghost is on their lane's layer, which only their camera draws. A player who
## leaves takes their ghost with them; one who drops in gets the free layer.
func test_each_camera_draws_only_its_own_ghost() -> void:
	var s := _session()
	await _wait_for_cars(s, 2)
	var lanes := s.time_trial.lanes
	for lane in lanes:
		_lap(lane, 60.0)
	for i in 600:
		if lanes.all(func(l: TimeTrial.Lane) -> bool: return l.car != null):
			break
		await get_tree().process_frame
	for lane in lanes:
		assert_object(lane.car).is_not_null()
		var bit := 1 << (TimeTrial.FIRST_LAYER - 1 + lane.layer)
		var drawn := lane.car.find_children("*", "VisualInstance3D", true, false)
		assert_bool(drawn.is_empty()).is_false()
		for vi: VisualInstance3D in drawn:
			assert_int(vi.layers).is_equal(bit)
		for other in lanes:
			var sees := other.player.cameras.camera.cull_mask & bit != 0
			assert_bool(sees).override_failure_message("P%d sees P%d's ghost: %s" % [other.player.number, lane.player.number, sees]).is_equal(other == lane)
		# The world, the cars and the player's own racing line are still drawn.
		assert_int(lane.player.cameras.camera.cull_mask & 1).is_equal(1)
	var gone := lanes[1]
	var gone_layer := gone.layer
	var gone_car := gone.car
	Players.leave(Players.slots[1])
	await _frames(2)
	assert_int(s.time_trial.lanes.size()).is_equal(1)
	assert_bool(is_instance_valid(gone_car)).is_false()
	var pad := { "kind": "gamepad", "key": "pad:test#9", "name": "Test pad", "id": 9, "guid": "test9", "preset": "pad_standard" }
	Devices.test_devices = [pad]
	Players.join(pad)
	await _wait_for_cars(s, 2)
	assert_int(s.time_trial.lanes.size()).is_equal(2)
	assert_int(s.time_trial.lanes[1].layer).is_equal(gone_layer)
	assert_object(s.time_trial.lane_of(s.players[1])).is_same(s.time_trial.lanes[1])
	s.queue_free()
	await get_tree().process_frame


## A Kart time trial runs the kart rules with no items (and no item line on the HUD), and each
## player's ghosts are kept under the class they picked (D149), not the session's.
func test_a_kart_players_ghosts_are_kept_under_their_own_class() -> void:
	Settings.primary.data.kart_class = "official.kart.light"
	var s := _session("official.kart.medium", 0)
	await _wait_for_cars(s, 1)
	var lane := s.time_trial.lanes[0]
	Settings.primary.data.erase("kart_class")
	assert_object(s.kart).is_not_null()
	assert_bool(s.event.items).is_false()
	assert_str(String(lane.player.vehicle.base_platform.id)).is_equal("official.kart.light")
	assert_str(lane.folder().get_file()).is_equal("official.kart.light")
	_lap(lane, 50.0)
	assert_str(String(lane.best().meta.platform)).is_equal("official.kart.light")
	await _frames(2)
	assert_str((lane.player.hud.get_node("KartPanel") as KartPanel).item_text()).is_empty() # no "No item" line
	s.queue_free()
	await get_tree().process_frame


func _on_event(e: RaceEvent, platform_id: String) -> void:
	_requested.append([e, platform_id])


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


func _button(b: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = PAD
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await _frames()
	var up := e.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await _frames()


## From the main menu to a two-player Regular time trial: the Time Trial switch, the track, the
## class, then the Players page, where P1 joins on the keyboard and P2 on a pad and both ready.
## The session that starts has both players, each in their own lane.
func test_a_two_player_time_trial_from_the_main_menu() -> void:
	Settings.profile.event_memory = {}
	Settings.profile.last_drive = {}
	Settings.profile.last_platform = "official.track.gt"
	PlayersMenu.countdown_s = 0.0
	Game.hold_events = true
	Game.event_requested.connect(_on_event)
	Devices.test_devices = [{ "kind": "gamepad", "key": "pad:test#%d" % PAD, "name": "Test pad", "id": PAD, "guid": "test%d" % PAD, "preset": "pad_standard" }]
	var runner := scene_runner(TITLE_SCENE)
	await _frames(4)
	await _key(KEY_ENTER) # Local Drive
	await _frames(4)
	await _key(KEY_ENTER) # Racing
	await _frames(4)
	await _key(KEY_E) # Time Trial
	await _key(KEY_ENTER) # Regular
	await _frames(4)
	var stack := runner.scene().find_child("MenuStack", true, false) as MenuStack
	var settings := stack.top() as EventSettingsPage
	assert_str(settings.title).is_equal("Regular time trial")
	assert_str(settings.next_button.accessibility_description).is_equal("Pick the class")
	await _key(KEY_UP) # Back
	await _key(KEY_UP) # Next
	await _key(KEY_ENTER)
	await _frames(4)
	assert_bool(stack.top() is ClassPage).is_true()
	await _key(KEY_ENTER) # GT, last used
	await _frames(4)
	assert_bool(stack.top() is PlayersMenu).is_true()
	await _key(KEY_ENTER) # P1 joins
	await _button(JOY_BUTTON_A) # P2 joins
	await _frames(6)
	assert_int(Players.count()).is_equal(2)
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_ENTER) # P1 Ready
	assert_bool(_requested.is_empty()).is_true()
	await _button(JOY_BUTTON_DPAD_UP)
	await _button(JOY_BUTTON_DPAD_UP)
	await _button(JOY_BUTTON_A) # P2 Ready
	await _frames(4)
	Game.event_requested.disconnect(_on_event)
	Game.hold_events = false
	PlayersMenu.countdown_s = 3.0
	assert_int(_requested.size()).is_equal(1)
	var e: RaceEvent = _requested[0][0]
	assert_str(e.kind).is_equal("time_trial")
	assert_str(String(_requested[0][1])).is_equal("official.track.gt")
	var s := TrackSession.new()
	s.track_path = TRACK
	s.platform_id = _requested[0][1]
	s.event = e
	add_child(s)
	await _wait_for_cars(s, 2)
	assert_int(s.players.size()).is_equal(2)
	assert_int(s.time_trial.lanes.size()).is_equal(2)
	assert_str(s.time_trial.lanes[1].player.slot.tag()).is_equal("P2")
	s.queue_free()
	await get_tree().process_frame
