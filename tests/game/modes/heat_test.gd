extends GdUnitTestSuite
## Police heat (docs/GAMEMODES.md §3, D115): points for what units see, the levels, busted after
## 3 s slow with a unit on you, evaded after enough time unseen and far.


func test_points_and_levels() -> void:
	var h := Heat.new()
	assert_int(h.level()).is_equal(0)
	h.seen("near")
	assert_int(h.level()).is_equal(1)
	assert_bool(h.news.any(func(n: Dictionary) -> bool: return n.text == "Heat 1")).is_true()
	h.seen("close") # 3
	h.seen("crash") # 6
	assert_int(h.level()).is_equal(2)
	h.seen("ram") # 11
	h.seen("ram") # 16
	assert_int(h.level()).is_equal(3)
	h.points = 30
	assert_int(h.level()).is_equal(4)
	h.points = 50
	assert_int(h.level()).is_equal(5)
	h.points = 500
	assert_int(h.level()).is_equal(5)


func test_speeding_counts_every_two_seconds_seen() -> void:
	var h := Heat.new()
	for i in 240: # 4 s at 15 km/h over: nothing
		h.seen_speeding(15.0, 1.0 / 60.0)
	assert_int(h.points).is_equal(0)
	for i in 245: # 4 s at 25 over: two points
		h.seen_speeding(25.0, 1.0 / 60.0)
	assert_int(h.points).is_equal(2)


func test_busted_after_three_slow_seconds_with_a_unit_on_you() -> void:
	var h := Heat.new()
	h.seen("near")
	# Slow, but no unit close: nothing; a unit close but fast: nothing.
	for i in 300:
		assert_str(h.update(1.0 / 60.0, true, 40.0, 5.0, false)).is_empty()
	for i in 300:
		assert_str(h.update(1.0 / 60.0, true, 1.0, 40.0, true)).is_empty()
	var got := ""
	for i in 179:
		got = h.update(1.0 / 60.0, true, 0.4, 5.0, true)
	assert_str(got).is_empty()
	got = h.update(2.0 / 60.0, true, 0.4, 5.0, true)
	assert_str(got).is_equal("busted")
	assert_int(h.level()).is_equal(0)


func test_evaded_when_unseen_and_far_long_enough() -> void:
	var h := Heat.new()
	h.points = 6 # level 2: 8 + 8 s
	assert_float(h.evade_s()).is_equal(16.0)
	var got := ""
	# Unseen but a unit still near: the clock doesn't run.
	for i in 60 * 20:
		got = h.update(1.0 / 60.0, false, 200.0, 120.0, false)
	assert_str(got).is_empty()
	for i in 60 * 15:
		got = h.update(1.0 / 60.0, false, 400.0, 120.0, false)
	assert_str(got).is_empty()
	assert_float(h.evading()).is_greater(0.9)
	# Seen again: back to the start.
	h.update(1.0 / 60.0, true, 400.0, 120.0, false)
	assert_float(h.evading()).is_equal(0.0)
	for i in 60 * 17:
		got = h.update(1.0 / 60.0, false, 400.0, 120.0, false)
		if got:
			break
	assert_str(got).is_equal("evaded")
	assert_int(h.level()).is_equal(0)
