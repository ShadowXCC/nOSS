extends GdUnitTestSuite
## Watching a pass you are not in (D176-D177). A waiting car is hidden, frozen and 600 m below the
## strip (D170), and the camera rig is bolted to it, so without this the players between passes
## were shown an empty sky. The camera goes on the cars that are running instead; the car itself
## is left exactly where the pass put it. The card that locks a driver in is here too.

var s: TrackSession
var drag: DragControl
var p: SessionPlayer
var bots: Array[Racer] = []


func before() -> void:
	Settings.use_folder("user://tests/drag_watch")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
	await get_tree().process_frame


## A match of four with the player drawn out of the first pass, so they are watching it.
func _start() -> void:
	Players.clear()
	s = TrackSession.new()
	s.platform_id = "official.drag.street"
	s.event = RaceEvent.drag(201, 1)
	s.event.ai_count = 3
	s.event.ai_cars = "builtin"
	s.drag_seed = 11
	add_child(s)
	for i in 900:
		if s.racers.size() == 4 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	drag = s.drag
	drag.ready_gate = false
	p = s.racers[0] as SessionPlayer
	bots.assign([s.racers[1], s.racers[2], s.racers[3]])
	assert_object(s.drag_watch).override_failure_message("no DragWatch in this session").is_not_null()
	await _pass_of([bots[1], bots[2]])


## Sets the ladder to run `pair` next and waits for the pass to be up and the views to follow.
func _pass_of(pair: Array) -> void:
	drag.reset()
	drag.ladder.pairs = [pair]
	drag.ladder.pair_index = 0
	for i in 120 * 6:
		if s.race.phase == RaceControl.Phase.RUNNING and not drag.cars.is_empty():
			break
		await get_tree().physics_frame
	for i in 4:
		await get_tree().process_frame


func _lead_z() -> float:
	var lead := -INF
	for r in drag.cars:
		lead = maxf(lead, r.vehicle.global_position.z)
	return lead


func test_a_waiting_player_is_shown_the_pass_and_not_the_sky() -> void:
	await _start()
	assert_bool(p.parked).is_true()
	# Their own car is still out of play where the pass put it.
	assert_bool(p.vehicle.visible).is_false()
	assert_float(p.vehicle.global_position.y).is_less(DragControl.PARK_Y + 1.0)
	# The camera is not: it is above the deck, behind the cars, looking down the strip.
	assert_bool(p.cameras.watching).is_true()
	var at := p.cameras.camera.global_position
	assert_float(at.y).is_greater(drag.layout.floor_y + 1.0)
	assert_float(at.z).is_less(_lead_z())
	assert_float(at.z).is_greater(_lead_z() - 60.0)
	assert_float(absf(at.x)).override_failure_message("the pass view sits over the centreline").is_less(1.0)
	# And the cars are really in frame: both of them, with the deck they are on, inside the
	# camera's own frustum. (A screenshot cannot stand in for this: a windowed run draws no
	# frames at all while the monitors are asleep.)
	for r: Racer in drag.cars:
		assert_bool(p.cameras.camera.is_position_in_frustum(r.vehicle.global_position)) \
			.override_failure_message("%s is not in frame" % r.display_name).is_true()
	assert_bool(p.cameras.camera.is_position_in_frustum(Vector3(0.0, drag.layout.floor_y, _lead_z() + 5.0))) \
		.override_failure_message("the strip ahead of the cars is not in frame").is_true()


func test_the_camera_button_cycles_the_cars_in_the_pass() -> void:
	await _start()
	var driving_with := String(p.slot.profile.data.get("camera", "chase_near"))
	p.controller.camera_next_requested.emit()
	for i in 3:
		await get_tree().process_frame
	# The first car of the pass, through this player's own camera.
	assert_bool(p.cameras.watching).is_false()
	assert_object(p.cameras.vehicle).is_equal(drag.cars[0].vehicle)
	# A camera picked to watch with is not the one they drive with, so nothing is saved over it.
	assert_str(String(p.slot.profile.data.get("camera", "chase_near"))).is_equal(driving_with)
	p.controller.camera_next_requested.emit()
	for i in 3:
		await get_tree().process_frame
	assert_object(p.cameras.vehicle).is_equal(drag.cars[1].vehicle)
	# Round again to the pass itself.
	p.controller.camera_next_requested.emit()
	for i in 3:
		await get_tree().process_frame
	assert_bool(p.cameras.watching).is_true()


func test_their_own_pass_gives_them_their_own_camera_back() -> void:
	await _start()
	assert_bool(p.cameras.watching).is_true()
	await _pass_of([p, bots[0]])
	assert_bool(p.parked).is_false()
	assert_bool(p.cameras.watching).is_false()
	assert_object(p.cameras.vehicle).is_equal(p.vehicle)


func test_the_card_holds_the_pass_until_the_driver_locks_in() -> void:
	await _start()
	drag.ready_gate = true
	drag.reset()
	drag.ladder.pairs = [[p, bots[0]]]
	drag.ladder.pair_index = 0
	for i in 240:
		if p.overlay != null:
			break
		await get_tree().physics_frame
		await get_tree().process_frame
	# The card names whose turn it is and what they are holding, and nothing has set off yet.
	var card := p.overlay as DragReadyCard
	assert_object(card).override_failure_message("no card came up for the player's pass").is_not_null()
	assert_str(String(card.accessibility_name)).contains(p.display_name)
	assert_str(String(card.accessibility_name)).contains(p.slot.devices_text())
	assert_array(drag.cars).is_empty()
	card.locked_in.emit()
	for i in 60:
		if not drag.cars.is_empty():
			break
		await get_tree().physics_frame
		await get_tree().process_frame
	assert_bool(p in drag.cars).is_true()
	assert_object(p.overlay).override_failure_message("the card stayed up").is_null()
