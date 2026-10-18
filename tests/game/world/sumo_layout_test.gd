extends GdUnitTestSuite
## Sumo platforms (D162): the geometry a match's settings make, and how a platform shrinks.
## Every tier starts at its own radius, lower ones wider and further down; only an armed tier
## shrinks; smooth creeps in while stepped and crumbling come off a ring at a time; a platform
## goes altogether unless sudden death holds it at a pillar, which gives way in the end too.

func _layout(tiers := 3, style := "smooth", secs := 90, pillar := false, hazard := "lava") -> SumoLayout:
	var e := RaceEvent.sumo(tiers, hazard)
	e.sumo_shrink = style
	e.sumo_secs = secs
	e.sumo_pillar = pillar
	return SumoLayout.make(TrackData.new(), e)


func test_lower_tiers_are_wider_and_further_down() -> void:
	var a := _layout(3)
	assert_int(a.count()).is_equal(3)
	for i in 2:
		assert_float(a.radius_of(i)).override_failure_message("tier %d wider than %d" % [i, i + 1]).is_less(a.radius_of(i + 1))
		assert_float(a.floor_y_of(i + 1)).is_less(a.floor_y_of(i))
	assert_float(a.floor_y_of(0)).is_equal_approx(0.0, 0.001)
	# The goo is under the lowest one, and the pit wall stands clear of the widest.
	assert_float(a.hazard_y).is_less(a.floor_y_of(2))
	assert_float(a.pit_r).is_greater(a.radius_of(2))


func test_a_match_takes_as_many_tiers_as_it_asked_for() -> void:
	assert_int(_layout(1).count()).is_equal(1)
	assert_int(_layout(2).count()).is_equal(2)
	# Out of range is clamped, as RaceEvent does.
	var e := RaceEvent.sumo(3)
	e.sumo_tiers = 9
	assert_int(SumoLayout.make(TrackData.new(), e).count()).is_equal(SumoLayout.RADII.size())


func test_spawns_ring_the_top_platform_facing_the_middle() -> void:
	var a := _layout(2)
	assert_int(a.spawns.size()).is_equal(ArenaLayout.AUTO_SPAWNS)
	for at: Transform3D in a.spawns:
		assert_float(at.origin.y).is_equal_approx(0.0, 0.001)
		var r := Vector2(at.origin.x, at.origin.z).length()
		assert_float(r).is_less(a.radius_of(0))
		# +Z points at the middle.
		var to_middle := Vector3(-at.origin.x, 0.0, -at.origin.z).normalized()
		assert_float((at.basis.z as Vector3).normalized().dot(to_middle)).is_greater(0.99)


func test_tier_at_finds_the_platform_a_point_belongs_to() -> void:
	var a := _layout(3)
	assert_int(a.tier_at(Vector3(0, 0.5, 0))).is_equal(0)
	assert_int(a.tier_at(Vector3(0, a.floor_y_of(1) + 0.5, 0))).is_equal(1)
	assert_int(a.tier_at(Vector3(0, a.floor_y_of(2) + 0.5, 0))).is_equal(2)
	# Past the edge of the top one, but over the wider one below it.
	assert_int(a.tier_at(Vector3(a.radius_of(0) + 4.0, 0.5, 0))).is_equal(-1)
	assert_int(a.tier_at(Vector3(a.radius_of(0) + 4.0, a.floor_y_of(1) + 0.5, 0))).is_equal(1)
	# Over the goo.
	assert_int(a.tier_at(Vector3(0, a.hazard_y, 0))).is_equal(-1)


func test_standing_on_rejects_a_car_still_well_above_the_floor() -> void:
	var a := _layout(2)
	var y := a.floor_y_of(1)
	assert_int(a.standing_on(Vector3(0, y + 0.5, 0))).is_equal(1)
	# Inside the height band, but too high up to be standing on it.
	assert_int(a.tier_at(Vector3(0, y + 5.0, 0))).is_equal(1)
	assert_int(a.standing_on(Vector3(0, y + 5.0, 0))).is_equal(-1)


func test_inside_keeps_a_margin_from_the_edge() -> void:
	var a := _layout(1)
	var r := a.radius_of(0)
	assert_bool(a.inside(Vector3(0, 0.5, 0))).is_true()
	assert_bool(a.inside(Vector3(r - 0.2, 0.5, 0), 1.0)).is_false()
	assert_bool(a.inside(Vector3(r - 3.0, 0.5, 0), 1.0)).is_true()
	assert_float(a.edge_distance(Vector3(r - 3.0, 0.5, 0))).is_equal_approx(3.0, 0.01)


func test_only_an_armed_tier_shrinks() -> void:
	var a := _layout(2, "smooth", 90)
	var full := a.radius_of(0)
	a.advance(10.0)
	assert_float(a.radius_of(0)).is_equal_approx(full, 0.001)
	a.arm(0)
	a.advance(10.0)
	assert_float(a.radius_of(0)).is_less(full)
	assert_float(a.radius_of(1)).is_equal_approx(SumoLayout.RADII[1], 0.001)
	assert_bool(a.armed(1)).is_false()


func test_a_smooth_platform_creeps_in_and_then_goes() -> void:
	var a := _layout(1, "smooth", 90)
	a.arm(0)
	var start := a.radius_of(0)
	a.advance(45.0)
	assert_float(a.radius_of(0)).is_equal_approx(start / 2.0, 0.1) # half the time, half the size
	assert_bool(a.live(0)).is_true()
	var gone := a.advance(45.0)
	assert_array(gone).contains([0])
	assert_bool(a.live(0)).is_false()
	assert_float(a.radius_of(0)).is_equal_approx(0.0, 0.001)
	assert_int(a.lowest_live()).is_equal(-1)


func test_a_stepped_platform_holds_its_size_between_rings() -> void:
	var a := _layout(1, "stepped", 60)
	a.arm(0)
	var start := a.radius_of(0)
	var per := 60.0 / SumoLayout.STEPS
	a.advance(per * 0.5)
	assert_float(a.radius_of(0)).override_failure_message("held until the step").is_equal_approx(start, 0.001)
	a.advance(per * 0.6) # over the first step
	assert_float(a.radius_of(0)).is_equal_approx(start * (1.0 - 1.0 / SumoLayout.STEPS), 0.01)
	# It warns just before each step.
	var b := _layout(1, "stepped", 60)
	b.arm(0)
	b.advance(per - SumoLayout.WARN_S / 2.0)
	assert_bool(b.stepping(0)).is_true()
	var c := _layout(1, "smooth", 60)
	c.arm(0)
	c.advance(per - SumoLayout.WARN_S / 2.0)
	assert_bool(c.stepping(0)).override_failure_message("a smooth platform never steps").is_false()


func test_crumbling_shrinks_the_same_as_stepped() -> void:
	# Crumbling differs only in how it looks, so the floor underfoot matches (D162).
	var stepped := _layout(1, "stepped", 60)
	var crumble := _layout(1, "crumble", 60)
	stepped.arm(0)
	crumble.arm(0)
	for i in 20:
		stepped.advance(3.0)
		crumble.advance(3.0)
		assert_float(crumble.radius_of(0)).is_equal_approx(stepped.radius_of(0), 0.001)


func test_sudden_death_holds_the_bottom_tier_at_a_pillar_then_lets_it_go() -> void:
	var a := _layout(2, "smooth", 60, true)
	a.arm(0)
	a.arm(1)
	a.advance(60.0)
	# The top one has gone; the bottom one is holding at the pillar.
	assert_bool(a.live(0)).is_false()
	assert_bool(a.live(1)).is_true()
	assert_float(a.radius_of(1)).is_equal_approx(SumoLayout.PILLAR_R, 0.01)
	a.advance(SumoLayout.PILLAR_HOLD_S / 2.0)
	assert_float(a.radius_of(1)).override_failure_message("should still be holding").is_equal_approx(SumoLayout.PILLAR_R, 0.01)
	# It gives way in the end, so two cautious drivers cannot stall the match for ever.
	a.advance(SumoLayout.PILLAR_HOLD_S + SumoLayout.PILLAR_FADE_S)
	assert_bool(a.live(1)).is_false()


func test_without_sudden_death_nothing_holds() -> void:
	var a := _layout(1, "smooth", 60, false)
	a.arm(0)
	a.advance(61.0)
	assert_bool(a.live(0)).is_false()
	assert_float(a.floor_radius(0)).is_equal_approx(0.0, 0.001)


func test_radii_go_over_the_wire_and_come_back() -> void:
	var server := _layout(3, "smooth", 90)
	server.arm(0)
	server.advance(30.0)
	var client := _layout(3, "smooth", 90)
	client.apply_radii(server.radii())
	for i in 3:
		assert_float(client.radius_of(i)).is_equal_approx(server.radius_of(i), 0.01)
	# A client works out from the radii alone which platforms are going.
	assert_bool(client.armed(0)).is_true()
	assert_bool(client.armed(1)).is_false()
	# A tier the server says has gone is gone here too.
	var gone := PackedFloat32Array([0.0, client.radius_of(1), client.radius_of(2)])
	client.apply_radii(gone)
	assert_bool(client.live(0)).is_false()


func test_the_hazard_is_what_the_match_asked_for() -> void:
	assert_str(_layout(1, "smooth", 90, false, "acid").hazard).is_equal("acid")
	assert_str(_layout(1).hazard).is_equal("lava")
