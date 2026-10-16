extends GdUnitTestSuite
## When the AI and the item assist use items (D143), one situation each: Nitro on a straight;
## a Bolt with a kart lined up ahead, or thrown back at one close behind; a Seeker with someone
## ahead; a Shield when a Seeker comes; a Slick and an EMP with karts close; a Magnet with a kart a
## little way ahead; and nothing is held for ever.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"

var s: TrackSession
var me: Racer
var other: Racer
var policy: ItemPolicy


func before() -> void:
	Settings.use_folder("user://tests/item_policy")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	s = TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.free_drive()
	s.ai_racers = 1
	add_child(s)
	for i in 900:
		if s.racers.size() == 2 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	me = s.racers[0]
	other = s.racers[1]
	policy = ItemPolicy.new()
	policy.racer = me
	policy.skill = 100.0
	_place(other, -100.0, 0.0)


func after_test() -> void:
	s.queue_free()
	await get_tree().process_frame


func _place(r: Racer, at: float, lat: float, speed := 0.0) -> void:
	var x := s.track.transform_at(fposmod(at, s.track.length), lat)
	r.vehicle.reset_to(x, x.basis.z * speed)


## What the policy does with `item` over the next `seconds` (null: kept it).
func _decide(item: String, seconds := 2.0) -> Variant:
	s.kart.items.give(me, item)
	s.kart.items.slot(me).roulette = 0.0
	for i in int(seconds * 120.0):
		await get_tree().physics_frame
		var back: Variant = policy.think(1.0 / 120.0)
		if back != null:
			return back
	return null


func test_nitro_on_a_straight() -> void:
	_place(me, 30.0, 0.0, 15.0) # the south straight
	assert_bool(await _decide("nitro") == false).is_true()


func test_a_bolt_lined_up_ahead_or_back_at_a_pursuer() -> void:
	_place(me, 60.0, 0.0)
	_place(other, 85.0, 0.0)
	assert_bool(await _decide("bolt") == false).is_true()
	_place(other, 50.0, 0.0)
	assert_bool(await _decide("bolt") == true).is_true()
	# Nobody near: kept a while.
	_place(other, -100.0, 0.0)
	assert_object(await _decide("bolt", 1.0)).is_null()


func test_a_seeker_with_someone_ahead() -> void:
	_place(me, 60.0, 0.0)
	_place(other, 120.0, 0.0)
	await get_tree().physics_frame
	assert_bool(await _decide("seeker") == false).is_true()


func test_a_shield_when_a_seeker_comes() -> void:
	_place(me, 60.0, 0.0)
	assert_object(await _decide("shield", 1.0)).is_null()
	var at := s.track.transform_at(30.0)
	s.kart.entities.spawn("seeker", other, at.origin + at.basis.y * 0.6, at.basis.z, me)
	assert_bool(await _decide("shield", 0.5) == false).is_true()


func test_a_slick_and_an_emp_with_karts_close() -> void:
	_place(me, 60.0, 0.0)
	_place(other, 45.0, 0.0)
	assert_bool(await _decide("oil_slick") == false).is_true()
	_place(other, 70.0, 2.0)
	assert_bool(await _decide("emp") == false).is_true()


func test_a_magnet_with_a_kart_a_little_ahead() -> void:
	_place(me, 40.0, 0.0)
	_place(other, 75.0, 0.0)
	await get_tree().physics_frame
	assert_bool(await _decide("magnet") == false).is_true()


func test_nothing_is_held_for_ever() -> void:
	_place(me, 60.0, 0.0)
	assert_bool(await _decide("emp", ItemPolicy.HOLD_MAX.emp + 1.0) == false).is_true()
