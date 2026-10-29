extends GdUnitTestSuite
## Garage traffic's sets (D233): the server deals them from everyone's cars in turn, with no car
## twice in a set; a swap moves every slot to the next set but the pinned ones (near a player), which
## keep theirs, so a slot is on the newest swap's set that didn't pin it; and a late joiner's state
## draws every slot from the same set as a game that saw each swap.


func _hand(n: int, name: String) -> Dictionary:
	var cars := PackedStringArray()
	for i in n:
		cars.append("%s%d" % [name, i])
	return { "cars": cars, "at": 0 }


func test_hands_take_turns_with_no_car_twice() -> void:
	# Three cars, thirty and none.
	var hands := [_hand(3, "a"), _hand(30, "b"), _hand(0, "c")]
	var first := EndlessGarage.deal(hands, 0)
	assert_int(first.size()).is_equal(EndlessGarage.ONLINE_MOST)
	# In turn from the first: a, b, a, b, a, b, then a has none left that isn't in, so b's.
	assert_array(Array(first.slice(0, 6))).is_equal(["a0", "b0", "a1", "b1", "a2", "b2"])
	assert_array(Array(first.slice(6))).is_equal(["b3", "b4", "b5", "b6", "b7", "b8"])
	# The next set starts from the next hand and carries on where each left off; a's wrap round.
	var second := EndlessGarage.deal(hands, 1)
	assert_array(Array(second.slice(0, 6))).is_equal(["b9", "a0", "b10", "a1", "b11", "a2"])
	for set: PackedStringArray in [first, second]:
		var seen := {}
		for car in set:
			assert_bool(seen.has(car)).is_false()
			seen[car] = true
	# Over a few sets every one of b's thirty comes up.
	var all := {}
	for n in 6:
		for car in EndlessGarage.deal(hands, n + 2):
			all[car] = true
	assert_int(all.keys().filter(func(c: String) -> bool: return c.begins_with("b")).size()).is_equal(30)
	# Nobody with cars: an empty set.
	assert_int(EndlessGarage.deal([_hand(0, "x")], 0).size()).is_equal(0)
	assert_int(EndlessGarage.deal([], 3).size()).is_equal(0)


func test_twelve_cars_or_fewer_make_every_set_the_same() -> void:
	var hands := [_hand(5, "a"), _hand(7, "b")]
	var sets := []
	for n in 5:
		var s := Array(EndlessGarage.deal(hands, n))
		s.sort()
		sets.append(s)
	for s: Array in sets:
		assert_array(s).is_equal(sets[0])
	assert_int((sets[0] as Array).size()).is_equal(12)
	# Two hands with cars in common: each car once.
	var shared := EndlessGarage.deal([{ "cars": PackedStringArray(["x", "y"]), "at": 0 }, { "cars": PackedStringArray(["y", "x", "z"]), "at": 0 }], 0)
	assert_int(shared.size()).is_equal(3)


## Spans join where they touch or overlap, in order.
func test_spans_merge() -> void:
	assert_array(Array(EndlessGarage.merged([[50, 60], [10, 20], [21, 30], [55, 70]]))).is_equal([10, 30, 50, 70])
	assert_int(EndlessGarage.merged([]).size()).is_equal(0)


## A slot is on the set of the newest swap that didn't pin it, else set 0: worked out directly, over
## random swaps, against the folded state.
func test_a_pinned_slot_keeps_its_set_and_the_rest_swap() -> void:
	var g := EndlessGarage.new()
	for id in 2:
		_add_set(g, id)
	# The first swap pins lane 0's slots 100-200 (the server deals the one after first).
	_add_set(g, 2)
	g.swap({ 0: PackedInt64Array([100, 200]) })
	assert_int(g.k).is_equal(1)
	assert_int(g.set_of(0, 150)).is_equal(0)
	assert_int(g.set_of(0, 99)).is_equal(1)
	assert_int(g.set_of(0, 201)).is_equal(1)
	assert_int(g.set_of(1, 150)).is_equal(1)
	# The second pins 180-300: 180-200 were on 0 and stay; 201-300 stay on 1; 100-179 go to 2.
	_add_set(g, 3)
	g.swap({ 0: PackedInt64Array([180, 300]) })
	assert_int(g.set_of(0, 190)).is_equal(0)
	assert_int(g.set_of(0, 250)).is_equal(1)
	assert_int(g.set_of(0, 150)).is_equal(2)
	assert_int(g.set_of(0, 400)).is_equal(2)
	# Sets nothing uses are let go, with their cars; the newest, the next and the kept ones stay.
	assert_array(g.sets.keys()).contains_exactly_in_any_order([0, 1, 2, 3])
	_add_set(g, 4)
	g.swap({})
	assert_array(g.sets.keys()).contains_exactly_in_any_order([3, 4])
	assert_array(g.cars.keys()).contains_exactly_in_any_order([3, 4])
	# Random swaps against the rule itself.
	var rule := EndlessGarage.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var history: Array[Dictionary] = []
	for n in 30:
		var pins := {}
		for lane in 2:
			var spans := []
			for i in rng.randi_range(0, 3):
				var lo := rng.randi_range(0, 400)
				spans.append([lo, lo + rng.randi_range(0, 120)])
			if not spans.is_empty():
				pins[lane] = EndlessGarage.merged(spans)
		history.append(pins)
		rule.swap(pins)
	for lane in 2:
		for j in range(-10, 540):
			var want := 0
			for n in range(history.size() - 1, -1, -1):
				if not _pinned(history[n], lane, j):
					want = n + 1
					break
			assert_int(rule.set_of(lane, j)).override_failure_message("lane %d slot %d" % [lane, j]).is_equal(want)


static func _add_set(g: EndlessGarage, id: int) -> void:
	g.sets[id] = PackedInt32Array([id])
	g.cars[id] = { "car": "c%d" % id, "fits": PackedStringArray(["saloon"]) }


static func _pinned(pins: Dictionary, lane: int, j: int) -> bool:
	var p: PackedInt64Array = pins.get(lane, PackedInt64Array())
	for i in range(0, p.size(), 2):
		if j >= p[i] and j <= p[i + 1]:
			return true
	return false


## A late joiner's state (to_dict, as a session sends it) draws every slot from the same set as the
## server's, and swaps after it (apply) keep them together; a swap it had already is left.
func test_a_late_joiner_draws_the_same_sets() -> void:
	var server := EndlessGarage.new()
	var early := EndlessGarage.new()
	var hashes := []
	for i in 30:
		hashes.append("sha256:%064x" % (i + 1))
	var deal := func(id: int) -> void:
		var s := PackedInt32Array()
		for i in 12:
			var c := (id * 7 + i) % 30
			s.append(c)
			server.cars[c] = { "car": hashes[c], "fits": PackedStringArray(["hatch", "saloon"]) }
		s.sort()
		server.sets[id] = s
	deal.call(0)
	deal.call(1)
	assert_bool(early.apply({})).is_false()
	early = EndlessGarage.from_dict(server.to_dict())
	assert_object(early).is_not_null()
	var late: EndlessGarage = null
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for n in 8:
		deal.call(server.k + 2)
		var pins := { 0: EndlessGarage.merged([[rng.randi_range(0, 300), rng.randi_range(300, 500)]]), 3: PackedInt64Array([-20, 40]) }
		var msg := { "k": server.k + 1, "cars": {}, "sets": {}, "pinned": pins }
		for id: int in [server.k + 1, server.k + 2]:
			msg.sets[id] = server.sets[id]
			for i: int in server.sets[id]:
				msg.cars[i] = server.cars[i]
		server.swap(pins)
		# Sent over the wire, as a client hears it.
		var heard: Dictionary = bytes_to_var(var_to_bytes(msg))
		assert_bool(early.apply(heard)).is_true()
		if late:
			assert_bool(late.apply(heard)).is_true()
		if n == 3:
			late = EndlessGarage.from_dict(bytes_to_var(var_to_bytes(server.to_dict())))
			assert_object(late).is_not_null()
			assert_bool(late.apply(heard)).is_false() # it had that one
	for g: EndlessGarage in [early, late]:
		assert_int(g.k).is_equal(server.k)
		for lane in 4:
			for j in range(-50, 600):
				assert_int(g.set_of(lane, j)).is_equal(server.set_of(lane, j))
		for id: int in server.sets:
			assert_array(Array(g.sets[id])).is_equal(Array(server.sets[id]))
	# What doesn't hold together is turned down.
	assert_object(EndlessGarage.from_dict({ "k": 0, "cars": {}, "sets": { 0: PackedInt32Array([3]) }, "kept": {} })).is_null()
	assert_object(EndlessGarage.from_dict({ "k": 0, "cars": { 0: { "car": "junk", "fits": [] } }, "sets": { 0: PackedInt32Array([0]) }, "kept": {} })).is_null()
	assert_object(EndlessGarage.from_dict({ "k": 2, "cars": {}, "sets": { 0: PackedInt32Array() }, "kept": {} })).is_null()
	var bad_kept := server.to_dict()
	bad_kept.kept = { 0: PackedInt64Array([10, 5, server.k]) }
	assert_object(EndlessGarage.from_dict(bad_kept)).is_null()
	assert_bool(late.apply({ "k": late.k + 2, "cars": {}, "sets": {}, "pinned": {} })).is_false() # no such set
	assert_bool(late.apply({ "k": late.k + 1, "cars": {}, "sets": {}, "pinned": { 9: PackedInt64Array([0, 1]) } })).is_false()
