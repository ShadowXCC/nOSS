extends GdUnitTestSuite
## Sumo Team Battle's draw (D234): every car on a team, the sizes within one of each other, the
## field evened out with bots inside its cap, and team colours that stay apart for every colour
## vision Palette simulates.


func test_the_draw_puts_every_car_on_a_team_evenly() -> void:
	for teams in [2, 3, 4]:
		for cars in [2, 5, 7, 8, 12]:
			var field := range(cars)
			var drawn := SumoTeams.draw(field, teams)
			assert_int(drawn.size()).is_equal(cars)
			var sizes := {}
			for car: int in field:
				var t := int(drawn[car])
				assert_int(t).is_between(0, teams - 1)
				sizes[t] = int(sizes.get(t, 0)) + 1
			assert_int(sizes.size()).is_equal(mini(teams, cars))
			var most: int = sizes.values().max()
			var least: int = sizes.values().min()
			assert_int(most - least).override_failure_message("%d cars, %d teams: %s" % [cars, teams, sizes]).is_less_equal(1)


func test_a_new_draw_shuffles() -> void:
	seed(7)
	var field := range(12)
	var first := SumoTeams.draw(field, 2)
	var differs := false
	for i in 8:
		if SumoTeams.draw(field, 2) != first:
			differs = true
	assert_bool(differs).is_true()


func test_bots_even_the_field() -> void:
	# One player and six bots in two teams: one more bot, four a side.
	assert_int(SumoTeams.even_field(1, 6, 2, 12)).is_equal(7)
	# A full field already splits.
	assert_int(SumoTeams.even_field(1, 11, 3, 12)).is_equal(11)
	assert_int(SumoTeams.even_field(2, 7, 4, 12)).is_equal(10)
	# At least one car a team.
	assert_int(SumoTeams.even_field(1, 0, 3, 12)).is_equal(2)
	# Online, 16 at most: three teams of five, a bot trimmed.
	assert_int(SumoTeams.even_field(4, 12, 3, 16)).is_equal(11)
	# Players alone past what splits within the cap: no bots, one team a car short.
	assert_int(SumoTeams.even_field(16, 0, 3, 16)).is_equal(0)
	assert_int(SumoTeams.even_field(3, 0, 2, 16)).is_equal(1)


func test_team_colours_stay_apart_for_every_colour_vision() -> void:
	var close := PackedStringArray()
	for vision: String in ["", "deuteranopia", "protanopia", "tritanopia"]:
		for a in SumoTeams.COLORS.size():
			for b in range(a + 1, SumoTeams.COLORS.size()):
				var d := Palette.difference(Palette.simulate(SumoTeams.COLORS[a], vision), Palette.simulate(SumoTeams.COLORS[b], vision))
				if d < Palette.MIN_DIFFERENCE:
					close.append("%s %s/%s %.1f" % [vision, SumoTeams.NAMES[a], SumoTeams.NAMES[b], d])
	assert_array(close).is_empty()
	assert_int(SumoTeams.COLORS.size()).is_equal(SumoTeams.NAMES.size())
