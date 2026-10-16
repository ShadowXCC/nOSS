extends GdUnitTestSuite
## The battle AI (D144) on the arena fixture: with nothing in hand it drives to the item boxes;
## with a Bolt it hunts the other kart and fires once it's lined up; stuck against the wall it
## backs out.

const ARENA := "res://tests/fixtures/tracks/arena_small.json"

var s: TrackSession
var me: Racer
var ai: BattleAI
var other: Racer


func before() -> void:
	Settings.use_folder("user://tests/battle_ai")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	s = TrackSession.new()
	s.track_path = ARENA
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.battle()
	s.event.ai_count = 1
	s.event.ai_skill = 90.0
	s.event.ai_cars = "builtin"
	add_child(s)
	for i in 120 * 8:
		if s.racers.size() == 2 and s.race.phase == RaceControl.Phase.RUNNING and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	other = s.racers[0]
	other.driver.process_mode = Node.PROCESS_MODE_DISABLED
	me = s.racers[1]
	ai = me.driver as BattleAI


func after_test() -> void:
	s.queue_free()
	await get_tree().process_frame


func _place(r: Racer, at: Vector3, yaw_deg: float) -> void:
	r.vehicle.reset_to(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at + Vector3.UP * 0.05))


func _nearest_box(p: Vector3) -> float:
	var boxes := s.kart.boxes
	var best := INF
	for i in boxes.count():
		if boxes.alive[i]:
			best = minf(best, Vector2(p.x, p.z).distance_to(Vector2(boxes.points[i].x, boxes.points[i].z)))
	return best


func test_drives_to_the_boxes_with_nothing_in_hand() -> void:
	assert_object(ai).is_not_null()
	_place(other, Vector3(-40, 0, 25), 0.0)
	_place(me, Vector3(-30, 0, -25), 90.0)
	var start := _nearest_box(me.com())
	var got := [] # (lambdas capture locals by value)
	s.kart.items.got.connect(func(r: Racer, _item: String) -> void: got.append(r))
	for i in 120 * 8:
		await get_tree().physics_frame
		if me in got:
			break
	assert_bool(me in got).override_failure_message("never got to a box (it was %.0f m away)" % start).is_true()


func test_hunts_and_fires_a_bolt_when_lined_up() -> void:
	_place(other, Vector3(20, 0, -10), 0.0)
	_place(me, Vector3(-20, 0, -10), 90.0) # +Z turned to face +X
	s.kart.items.give(me, "bolt")
	s.kart.items.slot(me).roulette = 0.0
	var fired := []
	s.kart.items.used.connect(func(r: Racer, item: String) -> void:
		if r == me and item == "bolt":
			fired.append(item))
	for i in 120 * 6:
		await get_tree().physics_frame
		if not fired.is_empty():
			break
	assert_bool(fired.is_empty()).is_false()
	assert_str(ai.intent).is_equal("hunt")


func test_backs_out_of_the_wall() -> void:
	_place(other, Vector3(-40, 0, 25), 0.0)
	# Nose to the wall at the arena's east end, the boxes behind it.
	var east := s.track.arena.centre + Vector2.RIGHT * (s.track.arena.reach(Vector2.RIGHT) - 2.0)
	_place(me, Vector3(east.x, 0, east.y), 90.0)
	var from := me.com()
	for i in 120 * 6:
		await get_tree().physics_frame
	assert_float(me.com().distance_to(from)).is_greater(5.0)
	assert_bool(me.towed).is_false()
