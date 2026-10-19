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


## Crumbling (D182): the floor comes off a wedge at a time, in a shuffled order, every wedge once
## a step. The whole platform still goes in the same time a stepped one does.
func test_crumbling_comes_off_one_wedge_at_a_time() -> void:
	var a := _layout(1, "crumble", 60)
	a.arm(0)
	var start := a.radius_of(0)
	a.advance(60.0 / SumoLayout.SLOTS * 1.1) # one bite in
	var short := 0
	for w in SumoLayout.SECTORS:
		if a.wedge_radius(0, w) < start - 0.01:
			short += 1
	assert_int(short).override_failure_message("one bite should take one wedge").is_equal(1)
	# The platform still reads as its full size, because its widest wedge is untouched.
	assert_float(a.radius_of(0)).is_equal_approx(start, 0.01)
	assert_float(a.wedge_radius(0, 0)).is_greater(0.0)


func test_crumbling_never_leaves_a_wedge_more_than_one_bite_behind() -> void:
	var a := _layout(1, "crumble", 60)
	a.arm(0)
	var start := SumoLayout.RADII[0]
	var bite := start / float(SumoLayout.STEPS)
	for _i in 60 * 120:
		a.advance(1.0 / 120.0)
		if not a.live(0):
			break
		var widest := 0.0
		var narrowest := INF
		for w in SumoLayout.SECTORS:
			widest = maxf(widest, a.wedge_radius(0, w))
			narrowest = minf(narrowest, a.wedge_radius(0, w))
		# Ragged, but never out of round by more than one bite, and never cut to the middle: a
		# wedge at nothing would be a slice taken out to the centre.
		assert_float(widest - narrowest).override_failure_message("out of round by more than a bite").is_less_equal(bite + 0.01)
		assert_float(narrowest).override_failure_message("a wedge was cut to the middle").is_greater(0.0)


func test_crumbling_empties_a_platform_in_the_same_time_as_stepped() -> void:
	var stepped := _layout(1, "stepped", 60)
	var crumble := _layout(1, "crumble", 60)
	stepped.arm(0)
	crumble.arm(0)
	for _i in 20:
		var a := stepped.advance(3.0)
		var b := crumble.advance(3.0)
		assert_bool(crumble.live(0)).override_failure_message("one went before the other").is_equal(stepped.live(0))
		assert_array(b).is_equal(a)
		# How much is left agrees to within one bite the whole way down.
		assert_float(absf(crumble.shrink_of(0) - stepped.shrink_of(0))).is_less_equal(1.0 / SumoLayout.STEPS + 0.01)
	assert_bool(crumble.live(0)).is_false()


func test_the_last_ring_of_a_crumbling_platform_goes_as_one() -> void:
	var a := _layout(1, "crumble", 60)
	a.arm(0)
	a.advance(60.0 * 5.0 / 6.0 + 0.1) # into the last step, every bite taken
	var first := a.wedge_radius(0, 0)
	for w in SumoLayout.SECTORS:
		assert_float(a.wedge_radius(0, w)).override_failure_message("wedge %d is out of line" % w).is_equal_approx(first, 0.01)
	# Nothing is marked yet: the last ring has the whole of the last step to stand in.
	assert_int(a.warning(0)).is_equal(0)
	a.advance(60.0 / 6.0 - 0.1 - SumoLayout.WARN_S / 2.0)
	assert_int(a.warning(0)).override_failure_message("the last ring goes unannounced").is_equal(SumoLayout.ALL_WEDGES)
	assert_bool(a.stepping(0)).override_failure_message("a whole ring going is worth a word").is_true()
	var gone := a.advance(SumoLayout.WARN_S)
	assert_array(gone).contains([0])


func test_a_crumbling_platform_marks_the_wedge_it_will_take_next() -> void:
	var a := _layout(2, "crumble", 60)
	a.arm(0)
	a.advance(0.1)
	var mask := a.warning(0)
	# One wedge, and the one the plan says is next.
	var bits := 0
	for w in SumoLayout.SECTORS:
		bits += 1 if mask & (1 << w) != 0 else 0
	assert_int(bits).override_failure_message("exactly one wedge is next").is_equal(1)
	assert_int(mask).is_equal(1 << int((a.tiers[0].plan as PackedByteArray)[0]))
	assert_bool(a.stepping(0)).override_failure_message("one wedge is not a ring").is_false()
	assert_int(a.warning(1)).override_failure_message("a platform nobody has landed on is not going").is_equal(0)
	# It keeps marking: the band is always somewhere, not a blink before each bite.
	a.advance(60.0 / SumoLayout.SLOTS * 1.1)
	assert_int(a.warning(0)).is_not_equal(0)


func test_edge_distance_sees_the_hole_beside_a_car() -> void:
	var a := _layout(1, "crumble", 60)
	a.arm(0)
	a.advance(60.0 / SumoLayout.SLOTS * 1.1)
	# Find the wedge that was bitten, and stand just inside the wedge next to it.
	var start := SumoLayout.RADII[0]
	var bitten := -1
	for w in SumoLayout.SECTORS:
		if a.wedge_radius(0, w) < start - 0.01:
			bitten = w
	assert_int(bitten).is_greater_equal(0)
	var neighbour := (bitten + 1) % SumoLayout.SECTORS
	# Two metres in from the rim, a hand's breadth the neighbour's side of the boundary they share.
	var bound := TAU * float(neighbour) / float(SumoLayout.SECTORS)
	var r := start - 2.0
	var ang := bound + 0.2 / r
	var at := Vector3(cos(ang) * r, 0.5, sin(ang) * r)
	assert_int(a.wedge_at(at)).override_failure_message("test stood in the wrong wedge").is_equal(neighbour)
	# Well inside its own wedge, but a step from the drop beside it.
	assert_float(a.wedge_radius(0, neighbour) - r).is_greater(1.0)
	assert_float(a.edge_distance(at)).is_equal_approx(0.2, 0.05)
	assert_bool(a.inside(at, 0.5)).override_failure_message("that is not a safe place to stand").is_false()


func test_wedges_go_over_the_wire_and_come_back() -> void:
	var server := _layout(2, "crumble", 60)
	server.arm(0)
	server.advance(60.0 / SumoLayout.SLOTS * 2.5) # a couple of bites in
	var client := _layout(2, "crumble", 60)
	var warns := PackedInt32Array()
	var hits := PackedByteArray()
	for i in server.count():
		warns.append(server.warning(i))
		hits.append_array(server.hits_of(i))
	client.apply_state(server.radii(), SumoLayout.SECTORS, hits, warns)
	for w in SumoLayout.SECTORS:
		assert_float(client.wedge_radius(0, w)).override_failure_message("wedge %d" % w).is_equal_approx(server.wedge_radius(0, w), 0.01)
	# A bitten platform is a going platform, even before its widest wedge has lost anything.
	assert_bool(client.armed(0)).is_true()
	assert_bool(client.armed(1)).is_false()


func test_a_restart_gives_a_crumbled_platform_back() -> void:
	var a := _layout(1, "crumble", 60)
	a.arm(0)
	a.advance(30.0)
	a.restore()
	for w in SumoLayout.SECTORS:
		assert_float(a.wedge_radius(0, w)).is_equal_approx(SumoLayout.RADII[0], 0.01)
	assert_int(a.warning(0)).is_equal(0)
	assert_bool(a.armed(0)).is_false()
	# The order it comes off in is kept, so a restarted match is the same match again.
	assert_int((a.tiers[0].plan as PackedByteArray).size()).is_equal(SumoLayout.EVENTS)


func test_sudden_death_holds_a_crumbling_platform_at_the_pillar() -> void:
	var a := _layout(1, "crumble", 60, true)
	a.arm(0)
	a.advance(60.0)
	assert_bool(a.live(0)).is_true()
	# The pillar is a disc, not a ragged one: every wedge holds at it.
	for w in SumoLayout.SECTORS:
		assert_float(a.wedge_radius(0, w)).is_equal_approx(SumoLayout.PILLAR_R, 0.01)
	assert_int(a.warning(0)).override_failure_message("the pillar goes smoothly: nothing to mark").is_equal(0)
	a.advance(SumoLayout.PILLAR_HOLD_S + SumoLayout.PILLAR_FADE_S)
	assert_bool(a.live(0)).is_false()


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


func test_a_restart_gives_the_platforms_back() -> void:
	var a := _layout(2, "smooth", 60)
	a.arm(0)
	a.arm(1)
	a.advance(61.0)
	assert_bool(a.live(0)).is_false()
	a.restore()
	for i in 2:
		assert_float(a.radius_of(i)).is_equal_approx(SumoLayout.RADII[i], 0.01)
		assert_bool(a.live(i)).is_true()
		assert_bool(a.armed(i)).is_false()


func test_the_hazard_is_what_the_match_asked_for() -> void:
	assert_str(_layout(1, "smooth", 90, false, "acid").hazard).is_equal("acid")
	assert_str(_layout(1).hazard).is_equal("lava")
## Five platforms (D184): the stack keeps its 12 m steps and 18 m drops all the way down, and the
## pit and the goo follow the widest one rather than a fixed size.
func test_a_five_high_stack_keeps_its_steps_and_clears_the_pit() -> void:
	var a := _layout(5)
	assert_int(a.count()).is_equal(5)
	for i in 4:
		assert_float(a.radius_of(i + 1) - a.radius_of(i)).override_failure_message("step %d" % i).is_equal_approx(12.0, 0.01)
		assert_float(a.floor_y_of(i) - a.floor_y_of(i + 1)).is_equal_approx(SumoLayout.DROP_M, 0.01)
	assert_float(a.hazard_y).is_less(a.floor_y_of(4))
	assert_float(a.pit_r).is_greater(a.radius_of(4))
	# The spawns still ring the top platform, which does not grow with the stack.
	assert_float(a.radius_of(0)).is_equal_approx(SumoLayout.RADII[0], 0.01)
	for at: Transform3D in a.spawns:
		assert_float(Vector2(at.origin.x, at.origin.z).length()).is_less(a.radius_of(0))
## The warning (D183): which floor is about to go, marked on the platform rather than worked out
## from a clock, because a client has no clock to work it out from.
func test_a_stepped_platform_marks_the_whole_ring_it_is_about_to_lose() -> void:
	var a := _layout(1, "stepped", 60)
	a.arm(0)
	var per := 60.0 / SumoLayout.STEPS
	a.advance(per * 0.2)
	assert_int(a.warning(0)).override_failure_message("marked far too early").is_equal(0)
	a.advance(per * 0.8 - SumoLayout.WARN_S / 2.0)
	assert_int(a.warning(0)).is_equal(SumoLayout.ALL_WEDGES)
	assert_bool(a.stepping(0)).is_true()
	# The band covers one step's worth of floor, from where the edge is now.
	assert_float(a.next_radius(0, 0)).is_equal_approx(a.radius_of(0) - SumoLayout.RADII[0] / SumoLayout.STEPS, 0.01)


func test_a_smooth_platform_marks_nothing_and_an_unarmed_one_neither() -> void:
	var a := _layout(2, "smooth", 60)
	a.arm(0)
	a.advance(59.0)
	assert_int(a.warning(0)).override_failure_message("smooth creeps in evenly: nothing to point at").is_equal(0)
	assert_bool(a.stepping(0)).is_false()
	var b := _layout(2, "stepped", 60)
	b.arm(0)
	b.advance(60.0 / SumoLayout.STEPS - SumoLayout.WARN_S / 2.0)
	assert_int(b.warning(0)).is_equal(SumoLayout.ALL_WEDGES)
	assert_int(b.warning(1)).override_failure_message("a platform nobody has landed on is not going").is_equal(0)


func test_the_warning_goes_over_the_wire() -> void:
	var server := _layout(2, "stepped", 60)
	server.arm(0)
	server.advance(60.0 / SumoLayout.STEPS - SumoLayout.WARN_S / 2.0)
	# A client never shrinks a platform of its own, so without this it would never warn at all.
	var client := _layout(2, "stepped", 60)
	assert_bool(client.stepping(0)).is_false()
	var warns := PackedInt32Array()
	for i in server.count():
		warns.append(server.warning(i))
	client.apply_state(server.radii(), 0, PackedByteArray(), warns)
	assert_int(client.warning(0)).is_equal(server.warning(0))
	assert_bool(client.stepping(0)).is_true()
	# A marked platform is a going platform, even before it has lost anything.
	assert_bool(client.armed(0)).is_true()
	assert_bool(client.armed(1)).is_false()


func test_a_restart_takes_the_warning_down() -> void:
	var a := _layout(1, "stepped", 60)
	a.arm(0)
	a.advance(60.0 / SumoLayout.STEPS - SumoLayout.WARN_S / 2.0)
	assert_int(a.warning(0)).is_not_equal(0)
	a.restore()
	assert_int(a.warning(0)).is_equal(0)
