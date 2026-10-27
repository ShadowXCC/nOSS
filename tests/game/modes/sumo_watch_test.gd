extends GdUnitTestSuite
## Watching the rest of the match from the goo (D185). A sumo match has no respawns, so going in
## ends your match but not the match: the car is left frozen three metres under the surface, and
## without this the camera stayed bolted to it. The camera goes on the arena instead, the Camera
## button cycles the cars still in, and a new match gives the player their own car back.

var s: TrackSession
var sumo: SumoControl
var p: SessionPlayer
var bots: Array[Racer] = []


func before() -> void:
	Settings.use_folder("user://tests/sumo_watch")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
	await get_tree().process_frame
	Engine.time_scale = 1.0 # a failed fast-forward test mustn't hurry the rest


## A match of four on one platform, with the player in the goo and three bots still fighting.
func _start() -> void:
	Players.clear()
	s = TrackSession.new()
	s.platform_id = "official.sumo.standard"
	s.event = RaceEvent.sumo(1, "lava")
	s.event.ai_count = 3
	s.event.ai_cars = "builtin"
	add_child(s)
	for i in 900:
		if s.racers.size() == 4 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	sumo = s.sumo
	p = s.racers[0] as SessionPlayer
	bots.assign([s.racers[1], s.racers[2], s.racers[3]])
	assert_object(s.sumo_watch).override_failure_message("no SumoWatch in this session").is_not_null()
	for i in 120 * 6:
		if s.race.phase == RaceControl.Phase.RUNNING:
			break
		await get_tree().physics_frame


## Drops `r` into the goo, as being shoved off would.
func _goo(r: Racer) -> void:
	r.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, sumo.layout.hazard_y - 1.0, 0.0)))
	sumo._check_goo()
	for i in 4:
		await get_tree().process_frame


func test_a_player_in_the_goo_is_shown_the_arena_and_not_the_goo() -> void:
	await _start()
	await _goo(p)
	assert_bool(p.out).is_true()
	# Their own car is left where the goo took it, under the surface and frozen.
	assert_float(p.vehicle.global_position.y).is_less(sumo.layout.hazard_y)
	assert_bool(p.vehicle.freeze).is_true()
	# The camera is not: it is up above the platform, looking down at the fight.
	assert_bool(p.cameras.watching).is_true()
	var at := p.cameras.camera.global_position
	assert_float(at.y).override_failure_message("the view is still down in the goo").is_greater(sumo.layout.floor_y_of(0))
	# And the cars still in are really in frame, with the platform they are on. (A screenshot
	# cannot stand in for this: a windowed run draws no frames while the monitors are asleep.)
	for r in bots:
		assert_bool(p.cameras.camera.is_position_in_frustum(r.vehicle.global_position)) \
			.override_failure_message("%s is not in frame" % r.display_name).is_true()
	assert_bool(p.cameras.camera.is_position_in_frustum(Vector3(0.0, sumo.layout.floor_y_of(0), 0.0))) \
		.override_failure_message("the middle of the platform is not in frame").is_true()


func test_the_camera_button_cycles_the_cars_still_in() -> void:
	await _start()
	await _goo(p)
	var driving_with := String(p.slot.profile.data.get("camera", "chase_near"))
	p.controller.camera_next_requested.emit()
	for i in 3:
		await get_tree().process_frame
	# The first car still in, through this player's own camera.
	assert_bool(p.cameras.watching).is_false()
	assert_object(p.cameras.vehicle).is_equal(sumo.standing()[0].vehicle)
	assert_str(String(p.hud.get_node("SumoPanel").tier_text())).contains(sumo.standing()[0].display_name)
	# A camera picked to watch with is not the one they drive with, so nothing is saved over it.
	assert_str(String(p.slot.profile.data.get("camera", "chase_near"))).is_equal(driving_with)
	# Round the rest of the field and back to the arena.
	for i in sumo.standing().size():
		p.controller.camera_next_requested.emit()
		for k in 3:
			await get_tree().process_frame
	assert_bool(p.cameras.watching).is_true()


func test_a_car_being_watched_going_in_puts_the_arena_back_up() -> void:
	await _start()
	await _goo(p)
	p.controller.camera_next_requested.emit()
	for i in 3:
		await get_tree().process_frame
	var seen: Racer = sumo.standing()[0]
	assert_object(p.cameras.vehicle).is_equal(seen.vehicle)
	# The last car still in is watched at index 1 once the others have gone, so put the rest in
	# and the view has nobody left to follow.
	for r in bots:
		if r != seen:
			await _goo(r)
	await _goo(seen)
	assert_bool(p.cameras.watching).override_failure_message("still watching a car in the goo").is_true()


func test_a_player_still_driving_keeps_their_own_camera() -> void:
	await _start()
	assert_bool(p.out).is_false()
	assert_bool(p.cameras.watching).is_false()
	assert_object(p.cameras.vehicle).is_equal(p.vehicle)
	# The camera button is theirs: it changes the camera they drive with, as always.
	var was := p.cameras.mode
	p.controller.camera_next_requested.emit()
	for i in 3:
		await get_tree().process_frame
	assert_str(p.cameras.mode).is_not_equal(was)


func test_a_new_match_gives_them_their_own_car_back() -> void:
	await _start()
	await _goo(p)
	assert_bool(p.cameras.watching).is_true()
	sumo.reset()
	for i in 4:
		await get_tree().process_frame
	assert_bool(p.out).is_false()
	assert_bool(p.cameras.watching).is_false()
	assert_object(p.cameras.vehicle).is_equal(p.vehicle)


## The Ram button, pressed by `who` this tick (what PlayerInput.poll would have seen).
func _press_ram(who: SessionPlayer) -> void:
	who.slot.input._edges["ram"] = true
	s.sumo_watch._fast_forward(who, sumo)
	who.slot.input._edges["ram"] = false
	for i in 3:
		await get_tree().process_frame


## Fast-forward (D220): only once every player is out, only offline, and not after the end.
func test_fast_forward_waits_for_every_player_to_be_out() -> void:
	await _start()
	assert_bool(sumo.can_fast_forward()).override_failure_message("a player is still in").is_false()
	sumo.fast_forward_on(true)
	assert_bool(sumo.fast_forward).is_false()
	await _goo(p)
	assert_bool(sumo.can_fast_forward()).is_true()
	s.online = { "test": true }
	var online := sumo.can_fast_forward()
	s.online = {}
	assert_bool(online).override_failure_message("online the clock is the server's").is_false()
	sumo.ended = true
	assert_bool(sumo.can_fast_forward()).override_failure_message("after the end").is_false()


## Out, Ram runs the match at 4x and back, and the ram line says so with the key to press.
func test_ram_runs_the_match_on_at_4x_and_back() -> void:
	await _start()
	await _goo(p)
	var panel: SumoPanel = p.hud.get_node("SumoPanel")
	assert_str(panel.ram_text()).starts_with("Fast forward")
	await _press_ram(p)
	assert_bool(sumo.fast_forward).is_true()
	assert_float(Engine.time_scale).is_equal_approx(SumoControl.FF_SPEED, 0.001)
	assert_float(float(Engine.physics_ticks_per_second)).is_equal(float(TrackSession.PHYSICS_HZ))
	assert_str(panel.ram_text()).starts_with("4x")
	assert_str(panel.accessibility_name).contains(panel.ram_text())
	await _press_ram(p)
	assert_bool(sumo.fast_forward).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)


## The results and the cool-down run at 1x: the end of the match turns it off, and so does a restart.
func test_fast_forward_stops_at_the_end_and_on_a_restart() -> void:
	await _start()
	await _goo(p)
	sumo.fast_forward_on(true)
	await _goo(bots[0])
	await _goo(bots[1])
	for i in 4:
		await get_tree().physics_frame
	assert_bool(sumo.ended).is_true()
	assert_bool(sumo.fast_forward).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)
	# And a restarted match, if it was on when the match restarted (the pause menu's Restart).
	sumo.fast_forward = true
	s.apply_game_speed()
	assert_float(Engine.time_scale).is_equal_approx(SumoControl.FF_SPEED, 0.001)
	s.race.restart_session()
	for i in 4:
		await get_tree().physics_frame
	assert_bool(sumo.fast_forward).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)
