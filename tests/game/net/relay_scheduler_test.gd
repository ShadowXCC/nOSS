extends GdUnitTestSuite
## The server's relay (D111): near cars go every tick, a crowd stays within the byte budget with
## every car getting its share, traffic far from a client's players isn't sent at all, and a
## client's own cars never go back to it.

const DT := 1.0 / 60.0


## A fresh state for car `id` at `pos`, stamped `t`.
func _state(id: int, pos: Vector3, t: float) -> CarState:
	var s := CarState.new()
	s.id = id
	s.time = t
	s.xform = Transform3D(Basis(), pos)
	return s


## Runs `ticks` relay ticks with every car's state new each tick; returns car id -> times sent.
func _run(relay: RelayScheduler, cars: Dictionary, near: PackedVector3Array, ticks: int, own := {}) -> Dictionary:
	var sent := {}
	for k in ticks:
		var latest := {}
		for id: int in cars:
			latest[id] = _state(id, cars[id], k * DT)
		for s in relay.pick(2, latest, near, own, {}, DT):
			sent[s.id] = int(sent.get(s.id, 0)) + 1
			assert_bool(own.has(s.id)).is_false()
	return sent


func test_near_cars_all_go_every_tick() -> void:
	var cars := {}
	for i in 15:
		cars[i + 1] = Vector3(i * 6.0, 0, 20)
	var sent := _run(RelayScheduler.new(), cars, PackedVector3Array([Vector3.ZERO]), 60)
	for id: int in cars:
		assert_int(int(sent.get(id, 0))).is_greater_equal(58)


func test_a_crowd_stays_within_the_budget() -> void:
	var cars := {}
	for i in 60:
		cars[i + 1] = Vector3(i * 4.0, 0, 30)
	var sent := _run(RelayScheduler.new(), cars, PackedVector3Array([Vector3.ZERO]), 120)
	var total := 0
	for id: int in sent:
		total += int(sent[id])
	assert_float(total * CarState.SIZE / 2.0).is_less_equal(RelayScheduler.BUDGET_BPS * 1.05) # bytes a second
	# Over twice what fits: every car gets its share, near ones (60 a second) twice the others'.
	assert_int(int(sent.get(1, 0))).is_greater_equal(40)
	for id: int in cars:
		assert_int(int(sent.get(id, 0))).is_greater_equal(15)


func test_far_traffic_and_own_cars_never_go() -> void:
	var far_traffic := NetProtocol.FIRST_TRAFFIC_ID + 5
	var near_traffic := NetProtocol.FIRST_TRAFFIC_ID + 6
	var cars := { 3: Vector3(0, 0, 2000), 4: Vector3(0, 0, 5) }
	cars[far_traffic] = Vector3(0, 0, RelayScheduler.TRAFFIC_FAR_M + 50.0)
	cars[near_traffic] = Vector3(0, 0, 100)
	var sent := _run(RelayScheduler.new(), cars, PackedVector3Array([Vector3.ZERO]), 120, { 4: true })
	assert_bool(sent.has(far_traffic)).is_false()
	assert_int(int(sent.get(near_traffic, 0))).is_greater_equal(110)
	assert_int(int(sent.get(3, 0))).is_between(5, 15) # a far player: about 5 a second
