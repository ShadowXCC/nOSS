extends GdUnitTestSuite
## Score attack's rules (docs/GAMEMODES.md §3, D114), to the point: near and close misses, lane
## splits, the speed steps (nothing below 120 km/h), the combo growing within 5 s and banking
## after 5 s with no event, contact losing what isn't banked, the wrong way pausing it; and the
## pass detector finding passes and lane splits.


func test_misses_and_speed_steps() -> void:
	var r := ScoreAttack.new()
	# Too wide, too slow past, or under 120 km/h: nothing.
	assert_int(r.near_miss(1.0, 60.0, 180.0, 0.0)).is_equal(0)
	assert_int(r.near_miss(0.8, 20.0, 180.0, 0.0)).is_equal(0)
	assert_int(r.near_miss(0.8, 60.0, 119.0, 0.0)).is_equal(0)
	assert_int(r.combo).is_equal(0)
	# Near ×1 at 120, close (double) ×1.5 at 160, ×2 at 200, ×3 at 250.
	assert_int(r.near_miss(0.8, 60.0, 120.0, 1.0)).is_equal(100)
	assert_int(r.near_miss(0.4, 60.0, 160.0, 2.0)).is_equal(300)
	assert_int(r.near_miss(0.9, 60.0, 210.0, 3.0)).is_equal(200)
	assert_int(r.near_miss(0.3, 60.0, 260.0, 4.0)).is_equal(600)
	assert_int(r.lane_split(130.0, 5.0)).is_equal(300)
	assert_int(r.chain).is_equal(1500)
	assert_int(r.combo).is_equal(5)


func test_a_combo_banks_after_five_quiet_seconds() -> void:
	var r := ScoreAttack.new()
	r.near_miss(0.8, 60.0, 130.0, 10.0)
	r.near_miss(0.8, 60.0, 130.0, 12.0)
	r.near_miss(0.8, 60.0, 130.0, 16.5) # within 5 s of the last: the chain goes on
	assert_int(r.combo).is_equal(3)
	assert_float(r.multiplier()).is_equal(1.5)
	assert_int(r.unbanked()).is_equal(450)
	r.update(21.4)
	assert_int(r.banked).is_equal(0) # not yet
	r.update(21.5)
	assert_int(r.banked).is_equal(450)
	assert_int(r.unbanked()).is_equal(0)
	assert_int(r.combo).is_equal(0)
	assert_bool(r.news.any(func(n: Dictionary) -> bool: return n.text == "Banked 450")).is_true()
	# The combo multiplier tops out.
	assert_float(ScoreAttack.combo_multiplier(100)).is_equal(ScoreAttack.COMBO_MAX)


func test_contact_loses_what_isnt_banked() -> void:
	var r := ScoreAttack.new()
	r.near_miss(0.8, 60.0, 130.0, 0.0)
	r.update(5.0)
	assert_int(r.banked).is_equal(100)
	r.near_miss(0.4, 60.0, 200.0, 6.0)
	r.near_miss(0.4, 60.0, 200.0, 7.0)
	assert_int(r.unbanked()).is_equal(1000)
	# A brush under 20 N·s isn't contact; a knock is, and the chain is gone (the bank stays).
	assert_bool(r.contact(10.0, 7.5)).is_false()
	assert_bool(r.contact(400.0, 7.6)).is_true()
	assert_int(r.unbanked()).is_equal(0)
	assert_int(r.banked).is_equal(100)
	assert_bool(r.news.any(func(n: Dictionary) -> bool: return n.text == "Lost 1000")).is_true()
	r.update(20.0)
	assert_int(r.banked).is_equal(100)


func test_the_wrong_way_scores_nothing() -> void:
	var r := ScoreAttack.new()
	r.paused = true
	assert_int(r.near_miss(0.3, 80.0, 200.0, 0.0)).is_equal(0)
	r.paused = false
	assert_int(r.near_miss(0.3, 80.0, 200.0, 1.0)).is_equal(400)


func test_the_slow_line_is_in_the_players_units() -> void:
	var units := Settings.units
	var panel: ScorePanel = auto_free(ScorePanel.new())
	Settings.units = "metric"
	panel.show_rules(ScoreAttack.new(), 100.0, 0.0)
	assert_str(panel._speed.text).is_equal("Under 120 km/h: no score")
	Settings.units = "imperial"
	panel.show_rules(ScoreAttack.new(), 100.0, 0.0)
	assert_str(panel._speed.text).is_equal("Under 75 mph: no score")
	Settings.units = units


func test_passes_are_found_when_the_car_is_behind() -> void:
	var m := NearMiss.new()
	# A car 0.6 m to the right, passed at 10 m/s: alongside from 6 m ahead to 6 m behind.
	var done := []
	for k in 30:
		var along := 7.0 - k * 0.6
		done.append_array(m.step([[5, 0.6 + absf(along) * 0.01, along, -2.4, 10.0, 4.5]], k * 0.06))
	assert_int(done.size()).is_equal(1)
	assert_int(int(done[0].id)).is_equal(5)
	assert_float(float(done[0].gap)).is_less(0.62)
	assert_float(float(done[0].relative_kmh)).is_equal_approx(36.0, 0.01)
	assert_float(float(done[0].side)).is_equal(-1.0)
	# A car that pulls away again was never passed.
	var gone := []
	for k in 10:
		gone.append_array(m.step([[6, 0.7, 2.0 + k * 1.5, 2.4, -5.0, 4.5]], 2.0 + k * 0.06))
	assert_array(gone).is_empty()


func test_two_close_passes_either_side_split_the_lanes() -> void:
	var m := NearMiss.new()
	var done := []
	for k in 30:
		var along := 7.0 - k * 0.6
		done.append_array(m.step([[1, 0.5, along, 2.0, 12.0, 4.5], [2, 0.6, along + 0.3, -2.0, 12.0, 4.5]], k * 0.06))
	assert_int(done.filter(func(d: Dictionary) -> bool: return d.has("split")).size()).is_equal(1)
	assert_int(done.filter(func(d: Dictionary) -> bool: return d.has("id")).size()).is_equal(2)
