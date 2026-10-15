extends GdUnitTestSuite
## Item odds (D140): rolls follow each band's weights; the leader never gets the Leader Hunter,
## and the back of the field gets it only when the field is big enough, none is out and the
## cooldown has passed; battles roll by lives lost, with no Hunter; --odds=cycle deals in turn.


func test_rolls_follow_each_band() -> void:
	var odds := ItemOdds.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var places := [0.0, 0.2, 0.5, 0.9]
	for b in odds.race_bands.size():
		var want: Dictionary = odds.race_bands[b].odds
		var total := 0.0
		for k: String in want:
			total += float(want[k])
		var counts := {}
		var n := 100000
		for i in n:
			var item := odds.roll(places[b], 8, rng)
			counts[item] = int(counts.get(item, 0)) + 1
		for k: String in want:
			var expect := float(want[k]) / total
			assert_float(float(counts.get(k, 0)) / n).override_failure_message("band %d %s" % [b, k]).is_equal_approx(expect, 0.01)


func test_the_leader_hunter_only_for_the_back_of_a_big_field() -> void:
	var odds := ItemOdds.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var count := func(place: float, karts: int, hunters: int, since: float) -> int:
		var n := 0
		for i in 5000:
			n += 1 if odds.roll(place, karts, rng, hunters, since) == "leader_hunter" else 0
		return n
	assert_int(count.call(0.0, 8, 0, INF)).is_equal(0) # the leader
	assert_int(count.call(1.0, 3, 0, INF)).is_equal(0) # too few karts
	assert_int(count.call(1.0, 8, 1, INF)).is_equal(0) # one is out already
	assert_int(count.call(1.0, 8, 0, 5.0)).is_equal(0) # in its cooldown
	assert_int(count.call(1.0, 8, 0, 30.0)).is_greater(100)


func test_battles_roll_by_lives_lost_without_the_hunter() -> void:
	var odds := ItemOdds.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for lost in 3:
		for i in 3000:
			seen[odds.roll_battle(lost, rng)] = true
	assert_bool(seen.has("leader_hunter")).is_false()
	assert_bool(seen.has("magnet")).is_true() # only with two lives lost
	var fresh := {}
	for i in 3000:
		fresh[odds.roll_battle(0, rng)] = true
	assert_bool(fresh.has("magnet")).is_false()


func test_cycle_deals_every_item_in_turn() -> void:
	var odds := ItemOdds.load_default()
	odds.cycle = true
	var rng := RandomNumberGenerator.new()
	var got := []
	for i in ItemOdds.ITEMS.size():
		got.append(odds.roll(0.0, 2, rng))
	assert_array(got).is_equal(ItemOdds.ITEMS)
	assert_str(ItemOdds.item_name("nitro_x3")).is_equal("Nitro ×3")
	assert_int(ItemOdds.count_of("nitro_x3")).is_equal(3)
