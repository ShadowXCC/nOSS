extends GdUnitTestSuite
## Kart items in a session (D139-D141), on the kart fixture with four karts the test places:
## a box gives an item after the roulette, nothing to a kart already holding one, and comes
## back after 3 s; Nitro ×3 boosts three times; a Bolt bounces off walls three times, then goes,
## and can hit its shooter after a bounce; a Seeker hits the car ahead, not the one beside; the
## Leader Hunter passes the others; a Shield takes one hit; EMP reaches 18 m; a Magnet closes a
## gap; a Slick spares its dropper for a second; a Bolt and a Seeker take each other out.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"

var s: TrackSession
var items: KartItems
var a: Racer
var b: Racer
var c: Racer
var d: Racer


func before() -> void:
	Settings.use_folder("user://tests/kart_items")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	Players.clear()
	s = TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.free_drive()
	s.ai_racers = 3
	add_child(s)
	for i in 900:
		if s.racers.size() == 4 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	items = s.kart.items
	a = s.racers[0]
	b = s.racers[1]
	c = s.racers[2]
	d = s.racers[3]
	# Out of the way, at rest.
	for i in 4:
		_place(s.racers[i], -100.0 + i * 15.0, 0.0)


func after_test() -> void:
	s.queue_free()
	await get_tree().process_frame


## On the south straight: `at` m along it from its middle, `lat` m to the left.
func _place(r: Racer, at: float, lat: float, speed := 0.0) -> void:
	var x := s.track.transform_at(fposmod(at, s.track.length), lat)
	r.vehicle.reset_to(x, x.basis.z * speed)
	r.vehicle.throttle = 0.0


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _hand(r: Racer, item: String) -> void:
	items.give(r, item)
	items.slot(r).roulette = 0.0


func _spun(r: Racer) -> bool:
	return r.vehicle.kart_flags() & VehicleSim.KART_FLAG_SPUN != 0


func test_a_box_gives_an_item_after_the_roulette() -> void:
	var row: Dictionary = s.kart.layout.rows[0]
	var box: Vector3 = row.points[1]
	var proj := s.track.project(box)
	_place(a, float(proj.distance) - 12.0, float(proj.lateral), 10.0)
	await _ticks(150)
	assert_str(String(items.slot(a).item)).is_not_empty()
	assert_int(s.kart.boxes.alive[1]).is_equal(0) # the first row's second box
	# Still rolling at first; its item comes after the roulette.
	_place(b, float(proj.distance) - 12.0, float(proj.lateral) + 2.2, 10.0)
	var got := false
	for i in 150:
		await get_tree().physics_frame
		if items.slot(b).item != "":
			got = true
			assert_str(items.item_of(b)).is_empty()
			break
	assert_bool(got).is_true()
	await _ticks(int(KartItems.ROULETTE_S * 120) + 2)
	assert_str(items.item_of(b)).is_not_empty()


func test_holding_an_item_breaks_the_box_and_it_comes_back() -> void:
	var row: Dictionary = s.kart.layout.rows[0]
	var box_i := 0
	var box: Vector3 = row.points[0]
	_hand(a, "shield")
	var proj := s.track.project(box)
	_place(a, float(proj.distance) - 12.0, float(proj.lateral), 10.0)
	await _ticks(150)
	assert_int(s.kart.boxes.alive[box_i]).is_equal(0)
	assert_str(items.item_of(a)).is_equal("shield")
	await _ticks(int(KartBoxes.RESPAWN_S * 120) + 10)
	assert_int(s.kart.boxes.alive[box_i]).is_equal(1)


func test_nitro_x3_boosts_three_times() -> void:
	_place(a, 0.0, 0.0, 10.0)
	_hand(a, "nitro_x3")
	var before := int(a.vehicle.sim.get_kart_state().boosts)
	items.use(a)
	items.use(a) # too soon
	assert_int(int(a.vehicle.sim.get_kart_state().boosts)).is_equal(before + 1)
	for i in 2:
		await _ticks(40)
		items.use(a)
	assert_int(int(a.vehicle.sim.get_kart_state().boosts)).is_equal(before + 3)
	assert_str(String(items.slot(a).item)).is_empty()


## Walls across the road `near` m ahead of and `far` m behind `at` on the south straight.
func _walls(at: float, ahead: float, behind: float) -> void:
	for along in [ahead, -behind]:
		var x := s.track.transform_at(at + along)
		var body := StaticBody3D.new()
		body.collision_layer = Vehicle.LAYER_WORLD
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(30.0, 3.0, 0.5)
		cs.shape = box
		body.add_child(cs)
		s.add_child(body)
		body.global_transform = Transform3D(x.basis, x.origin + x.basis.y * 1.5)
	await get_tree().physics_frame


func test_a_bolt_bounces_three_times_and_may_hit_its_shooter() -> void:
	await _walls(0.0, 14.0, 12.0)
	_place(a, 0.0, 0.0)
	await _ticks(2)
	_hand(a, "bolt")
	items.use(a)
	var bolt: Dictionary = items.entities.list.values()[0]
	# Back off the wall it hit first, into its shooter.
	for i in 120:
		await get_tree().physics_frame
		if _spun(a):
			break
	assert_bool(_spun(a)).is_true()
	assert_bool(items.entities.list.has(bolt.id)).is_false()
	# Fired again with nobody about: three bounces, then gone at the fourth wall.
	await _ticks(200)
	_place(a, 0.0, 0.0) # facing along the road again after its spin
	await _ticks(2)
	_hand(a, "bolt")
	items.use(a)
	var second: Dictionary = items.entities.list.values()[0]
	_place(a, -80.0, 0.0) # out of its way
	var most := 0
	for i in 480: # four walls 26 m apart at 42 m/s
		await get_tree().physics_frame
		if not items.entities.list.has(second.id):
			break
		most = maxi(most, int(second.bounces))
	assert_bool(items.entities.list.has(second.id)).is_false()
	assert_int(most).is_equal(KartEntities.MAX_BOUNCES)


func test_a_seeker_hits_the_car_ahead_not_the_one_beside() -> void:
	_place(a, 70.0, 0.0)
	_place(b, 110.0, 0.0)
	_place(c, 68.0, -4.0)
	await _ticks(3)
	_hand(a, "seeker")
	items.use(a)
	for i in 240:
		await get_tree().physics_frame
		if _spun(b):
			break
	assert_bool(_spun(b)).is_true()
	assert_bool(_spun(c)).is_false()


func test_the_leader_hunter_passes_the_others() -> void:
	_place(a, 70.0, 0.0)
	_place(b, 95.0, 0.0)
	_place(c, 105.0, 1.0)
	_place(d, 150.0, 0.0)
	await _ticks(3)
	assert_object(s.race.race_order()[0]).is_equal(d)
	_hand(a, "leader_hunter")
	items.use(a)
	for i in 240:
		await get_tree().physics_frame
		if _spun(d):
			break
	assert_bool(_spun(d)).is_true()
	assert_bool(_spun(b) or _spun(c)).is_false()


func test_a_shield_takes_one_hit() -> void:
	_place(b, 0.0, 0.0)
	_hand(b, "shield")
	items.use(b)
	assert_int(b.vehicle.kart_flags() & CarState.KART_SHIELD).is_equal(0) # set on the next tick
	await _ticks(1)
	assert_int(b.vehicle.kart_flags() & CarState.KART_SHIELD).is_not_equal(0)
	items.hit_by(b, "bolt", a, Vector3(10, 0, 0))
	await _ticks(2)
	assert_bool(_spun(b)).is_false()
	assert_int(b.vehicle.kart_flags() & CarState.KART_SHIELD).is_equal(0)
	items.hit_by(b, "bolt", a, Vector3(10, 0, 0))
	await _ticks(2)
	assert_bool(_spun(b)).is_true()


func test_emp_reaches_18_m() -> void:
	_place(a, 0.0, 0.0)
	_place(b, 10.0, 0.0)
	_place(c, 30.0, 0.0)
	await _ticks(3)
	_hand(a, "emp")
	items.use(a)
	await _ticks(1)
	assert_int(b.vehicle.kart_flags() & VehicleSim.KART_FLAG_SLOWED).is_not_equal(0)
	assert_int(c.vehicle.kart_flags() & VehicleSim.KART_FLAG_SLOWED).is_equal(0)
	assert_int(a.vehicle.kart_flags() & VehicleSim.KART_FLAG_SLOWED).is_equal(0)


func _gap_after(magnet: bool) -> float:
	# On the north straight, before the loop, clear of pads and boxes.
	_place(a, 440.0, 0.0, 15.0)
	_place(b, 482.0, 0.0, 15.0) # out of its slipstream
	await _ticks(2)
	if magnet:
		_hand(a, "magnet")
		items.use(a)
	for i in 300:
		a.vehicle.throttle = 0.6
		b.vehicle.throttle = 0.6
		await get_tree().physics_frame
		if items.slot(a).magnet <= 0.0 and magnet and i > 10:
			break
	return s.field.gap(a, b)


func test_a_magnet_closes_a_gap() -> void:
	var without: float = await _gap_after(false)
	var with: float = await _gap_after(true)
	assert_float(without).is_greater(36.0)
	assert_float(with).is_less(without - 6.0)


func test_a_slick_spares_its_dropper_for_a_second() -> void:
	_place(a, 0.0, 0.0)
	await _ticks(2)
	_hand(a, "oil_slick")
	items.use(a)
	var slick: Dictionary = items.entities.list.values()[0]
	var on := Transform3D(a.vehicle.global_basis, slick.pos)
	a.vehicle.reset_to(on)
	await _ticks(30)
	assert_bool(_spun(a)).is_false()
	await _ticks(100)
	assert_bool(_spun(a)).is_true()
	assert_bool(items.entities.list.has(slick.id)).is_false()


func test_a_bolt_and_a_seeker_take_each_other_out() -> void:
	_place(a, 0.0, 0.0)
	_place(b, 60.0, 0.0)
	await _ticks(2)
	var at := s.track.transform_at(30.0)
	var bolt := items.entities.spawn("bolt", c, at.origin + at.basis.z * 10.0, -at.basis.z)
	var seeker := items.entities.spawn("seeker", d, at.origin - at.basis.z * 10.0, at.basis.z, b)
	await _ticks(60)
	assert_bool(items.entities.list.has(bolt.id)).is_false()
	assert_bool(items.entities.list.has(seeker.id)).is_false()
	assert_bool(_spun(a) or _spun(b)).is_false()
