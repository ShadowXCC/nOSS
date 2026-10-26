extends GdUnitTestSuite
## Kart items on the wire (D141, D142): a car state carries the kart word; an event record keeps
## what it says (kind, use number, time, ids, item, position, the way it points); the server's
## snapshot of how things stand reads back on a client: boxes, slots, items out where they are.
## The whole of it online is tools/net_check.py --event kart|battle.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"

var s: TrackSession


func before() -> void:
	Settings.use_folder("user://tests/kart_net")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
		await get_tree().process_frame


func test_a_car_state_carries_the_kart_word() -> void:
	var st := CarState.new()
	st.id = 7
	st.kart = CarState.KART_SHIELD | CarState.KART_OUT | VehicleSim.KART_FLAG_BOOST
	var bytes := PackedByteArray()
	bytes.resize(CarState.SIZE)
	st.encode(bytes, 0)
	assert_int(CarState.SIZE).is_equal(48)
	var back := CarState.decode(bytes, 0)
	assert_int(back.kart).is_equal(st.kart)
	assert_int(NetProtocol.VERSION).is_equal(13)


func test_a_record_keeps_what_it_says() -> void:
	var kn := KartNet.new() # no session: its own clock
	var t := kn.now()
	var dir := Vector3(0.6, 0.0, 0.8)
	var rec := kn._record(KartNet.Ev.SPAWN, 513, 40123, 201, 3, KartNet._item_code("bolt"), 1, Vector3(-120.25, 3.5, 88.125), dir, t)
	assert_int(rec.size()).is_equal(KartNet.RECORD)
	var back := KartNet.read(rec, 0, t)
	assert_int(int(back.kind)).is_equal(KartNet.Ev.SPAWN)
	assert_int(int(back.seq)).is_equal(513)
	assert_int(int(back.entity)).is_equal(40123)
	assert_int(int(back.car)).is_equal(201)
	assert_int(int(back.other)).is_equal(3)
	assert_str(KartNet._item_of(int(back.item))).is_equal("bolt")
	assert_int(int(back.extra)).is_equal(1)
	assert_float(float(back.time)).is_equal_approx(t, 0.002)
	assert_vector(back.pos).is_equal_approx(Vector3(-120.25, 3.5, 88.125), Vector3.ONE * 0.001)
	assert_vector(back.dir).is_equal_approx(dir, Vector3.ONE * 0.001)
	assert_str(KartNet._item_of(0)).is_equal("")
	kn.free()


func test_the_snapshot_reads_back_on_a_client() -> void:
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
	var a: Racer = s.racers[0]
	var b: Racer = s.racers[1]
	a.net_id = 1
	b.net_id = 200
	s.net = NetSession.new()
	s.net.racers = { 1: a, 200: b }
	var kn := KartNet.new()
	kn.session = s
	kn.kart = s.kart
	var items := s.kart.items
	# As the server has it: a box gone, b holding a Shield, a Bolt out.
	s.kart.boxes.take(1)
	items.give(b, "shield")
	var at := s.track.transform_at(40.0)
	var bolt := s.kart.entities.spawn("bolt", a, at.origin + Vector3.UP * 0.45, at.basis.z, null, 77)
	bolt.age = 0.5
	var snap := kn.pack_state()
	# Then on a client that missed all of it (b another game's car): the box back, nothing held,
	# nothing out.
	b.vehicle.remote = true
	s.kart.boxes.set_alive(1, true)
	items.slot(b).item = ""
	s.kart.entities.remove(77)
	kn._on_state(snap)
	assert_bool(bool(s.kart.boxes.alive[1])).is_false()
	assert_str(String(items.slot(b).item)).is_equal("shield")
	b.vehicle.remote = false
	var e: Dictionary = s.kart.entities.list.get(77, {})
	assert_bool(e.is_empty()).is_false()
	assert_vector(e.pos).is_equal_approx(bolt.pos, Vector3.ONE * 1.0)
	# Gone on the server: gone here too.
	s.kart.entities.remove(77)
	var empty := kn.pack_state()
	s.kart.entities.spawn("bolt", a, at.origin, at.basis.z, null, 78)
	kn._on_state(empty)
	assert_bool(s.kart.entities.list.has(78)).is_false()
	s.net.free()
	s.net = null
	kn.free()
