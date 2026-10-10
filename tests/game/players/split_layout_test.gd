extends GdUnitTestSuite
## Splitscreen layouts and monitors (LOC-02, LOC-03, docs/ARCHITECTURE.md §6).


func test_one_to_four_players_cover_the_window() -> void:
	for n in range(1, 5):
		var area := 0.0
		for r in SplitLayout.rects(n):
			area += r.get_area()
		assert_float(area).override_failure_message("%d players" % n).is_equal_approx(1.0, 0.0001)


func test_two_players_stacked_or_side_by_side() -> void:
	var stacked := SplitLayout.rects(2, "stacked")
	assert_that(stacked[0]).is_equal(Rect2(0, 0, 1, 0.5))
	assert_that(stacked[1]).is_equal(Rect2(0, 0.5, 1, 0.5))
	var side := SplitLayout.rects(2, "side")
	assert_that(side[0]).is_equal(Rect2(0, 0, 0.5, 1))
	assert_that(side[1]).is_equal(Rect2(0.5, 0, 0.5, 1))


func test_three_players_wide_top_or_map_quarter() -> void:
	var wide := SplitLayout.rects(3, "stacked", "wide")
	assert_that(wide[0]).is_equal(Rect2(0, 0, 1, 0.5))
	assert_that(SplitLayout.spare(3, "wide")).is_equal(Rect2())
	var with_map := SplitLayout.rects(3, "stacked", "map")
	assert_int(with_map.size()).is_equal(3)
	assert_that(SplitLayout.spare(3, "map")).is_equal(Rect2(0.5, 0.5, 0.5, 0.5))
	for r in with_map:
		assert_bool(r.intersects(SplitLayout.spare(3, "map"))).is_false()


func test_views_never_overlap() -> void:
	for n in range(2, 5):
		for two in ["stacked", "side"]:
			for three in ["wide", "map"]:
				var rs := SplitLayout.rects(n, two, three)
				for i in rs.size():
					for j in range(i + 1, rs.size()):
						assert_bool(rs[i].intersects(rs[j])).is_false()


func test_two_monitors_two_plus_two_and_one_plus_three() -> void:
	var two_two := SplitLayout.by_screen([0, 0, 1, 1], 0, 2)
	assert_array(two_two[0]).is_equal([0, 1])
	assert_array(two_two[1]).is_equal([2, 3])
	var one_three := SplitLayout.by_screen([0, 1, 1, 1], 0, 2)
	assert_array(one_three[0]).is_equal([0])
	assert_array(one_three[1]).is_equal([1, 2, 3])


func test_unset_or_missing_monitor_means_the_main_window() -> void:
	var g := SplitLayout.by_screen([-1, 5, 1], 1, 2)
	assert_array(g[1]).is_equal([0, 1, 2])
