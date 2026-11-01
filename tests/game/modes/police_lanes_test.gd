extends GdUnitTestSuite
## Which lanes roadblocks and spike strips close (PoliceLanes, D248): 1 or 2 at heat 3 and 4, 2 or
## 3 at heat 5, never more than the road has; any set of lanes alike; the same pattern twice
## running only now and then; runs of lanes side by side for the strips.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_counts_by_heat() -> void:
	var rng := _rng(1)
	for level: int in [3, 4, 5]:
		var counts := {}
		for i in 2000:
			var n := PoliceLanes.count(level, 3, rng)
			counts[n] = int(counts.get(n, 0)) + 1
		var odds: Array = PoliceLanes.COUNTS[level]
		for n in [1, 2, 3]:
			assert_float(float(counts.get(n, 0)) / 2000.0).is_equal_approx(float(odds[n - 1]), 0.04)
	# Heat 3: mostly one lane.
	assert_float(float(PoliceLanes.COUNTS[3][0])).is_equal(0.7)


func test_never_more_than_the_road_has() -> void:
	var rng := _rng(2)
	for i in 200:
		assert_int(PoliceLanes.count(5, 2, rng)).is_between(1, 2)
		assert_int(PoliceLanes.count(5, 1, rng)).is_equal(1)
		var picked := PoliceLanes.pick(5, 2, rng)
		assert_int(picked.size()).is_between(1, 2)
		for s in picked:
			assert_int(s).is_between(0, 1)


func test_every_set_of_lanes_comes_up() -> void:
	var rng := _rng(3)
	var seen := {}
	for i in 3000:
		var picked := PoliceLanes.pick(5 if i % 2 else 4, 3, rng)
		seen[str(picked)] = true
		# Ascending, no repeats.
		for k in range(1, picked.size()):
			assert_int(picked[k]).is_greater(picked[k - 1])
	# Of three lanes: three singles, three pairs (the middle open is one) and all three.
	for want: String in ["[0]", "[1]", "[2]", "[0, 1]", "[0, 2]", "[1, 2]", "[0, 1, 2]"]:
		assert_bool(seen.has(want)).override_failure_message("never %s" % want).is_true()
	# Four lanes (the endless road's), at most three at once.
	for i in 500:
		assert_int(PoliceLanes.pick(5, 4, rng).size()).is_between(2, 3)


func test_the_same_pattern_twice_running_is_rare() -> void:
	var rng := _rng(4)
	var last: Array = []
	var repeats := 0
	for i in 1000:
		var picked := PoliceLanes.pick(4, 3, rng, last)
		if str(picked) == str(last):
			repeats += 1
		last = picked
	# One draw would repeat about one time in five here; drawn again, about one in twenty-five.
	assert_int(repeats).is_less(80)


func test_runs_split_at_gaps() -> void:
	assert_array(PoliceLanes.runs([0, 2])).is_equal([Vector2i(0, 0), Vector2i(2, 2)])
	assert_array(PoliceLanes.runs([0, 1, 2])).is_equal([Vector2i(0, 2)])
	assert_array(PoliceLanes.runs([1, 2])).is_equal([Vector2i(1, 2)])
	assert_array(PoliceLanes.runs([0, 1, 3])).is_equal([Vector2i(0, 1), Vector2i(3, 3)])
	assert_array(PoliceLanes.runs([])).is_empty()
