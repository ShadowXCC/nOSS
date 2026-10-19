extends GdUnitTestSuite
## The built sumo arena (D162, D182): the slab's collision follows each wedge's own radius, so the
## floor a crumbling platform has lost is really gone and the floor beside it is really there; the
## step between two wedges is closed, so nothing is seen or driven through the slab; and the
## warning band is drawn only, with no collision of its own and none at all on a server.


func _arena(style := "crumble", visual := true) -> SumoBuilder:
	var e := RaceEvent.sumo(1, "lava")
	e.sumo_shrink = style
	e.sumo_secs = 60
	var layout := SumoLayout.make(TrackData.new(), e)
	var builder: SumoBuilder = auto_free(SumoBuilder.new())
	builder.layout = layout
	add_child(builder)
	builder.setup(layout, visual, false)
	await get_tree().physics_frame
	return builder


## Straight down through `p`: {position, collider} or {}.
func _down(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 6.0)
	return get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)


## A point `r` out, in the middle of wedge `w`.
func _at(w: int, r: float) -> Vector3:
	var ang := TAU * (float(w) + 0.5) / float(SumoLayout.SECTORS)
	return Vector3(cos(ang) * r, 0.0, sin(ang) * r)


## Takes bites until one wedge has lost some floor, and says which.
func _bitten(builder: SumoBuilder) -> int:
	var layout := builder.layout
	layout.arm(0)
	layout.advance(60.0 / SumoLayout.SLOTS * 1.1)
	builder.refresh()
	await get_tree().physics_frame
	for w in SumoLayout.SECTORS:
		if layout.wedge_radius(0, w) < SumoLayout.RADII[0] - 0.01:
			return w
	return -1


func test_a_bitten_wedge_loses_its_floor_and_its_neighbour_keeps_hers() -> void:
	var builder := await _arena()
	var w: int = await _bitten(builder)
	assert_int(w).override_failure_message("no wedge was bitten").is_greater_equal(0)
	var layout := builder.layout
	var r: float = layout.wedge_radius(0, w)
	# Just past where that wedge's rim and catch lip now end there is nothing at all.
	var past := r + SumoLayout.LIP_M + 1.0
	assert_bool(_down(_at(w, past)).is_empty()).override_failure_message("the bitten floor is still there").is_true()
	# The same distance out, one wedge over, is still floor at the floor's own height.
	var next := (w + 1) % SumoLayout.SECTORS
	var hit := _down(_at(next, past))
	assert_bool(hit.is_empty()).override_failure_message("the neighbour's floor has gone too").is_false()
	assert_float((hit.position as Vector3).y).is_equal_approx(layout.floor_y_of(0), 0.1)
	# Over the bitten wedge, what is left out there is the catch lip, which sits below the floor
	# and is not floor to drive on; the floor itself is further in.
	var lip := _down(_at(w, r + SumoLayout.LIP_M / 2.0))
	assert_bool(lip.is_empty()).is_false()
	assert_float((lip.position as Vector3).y).is_less(layout.floor_y_of(0) - 0.1)
	var inside := _down(_at(w, r - 2.0))
	assert_bool(inside.is_empty()).is_false()
	assert_float((inside.position as Vector3).y).is_equal_approx(layout.floor_y_of(0), 0.1)


func test_the_step_between_two_wedges_is_closed() -> void:
	var builder := await _arena()
	var w: int = await _bitten(builder)
	assert_int(w).is_greater_equal(0)
	var layout := builder.layout
	var r: float = (layout.wedge_radius(0, w) + SumoLayout.RADII[0]) / 2.0
	# Out of the gap the bite left, across the boundary, at a height the deck occupies: the taller
	# wedge closes its side with a wall, so nothing drives in under the floor beside it. The wall
	# faces the gap, which is the side a car comes from.
	var bound := TAU * float(w) / float(SumoLayout.SECTORS)
	var y := layout.floor_y_of(0) - 0.4
	var from := Vector3(cos(bound + 0.25) * r, y, sin(bound + 0.25) * r)
	var to := Vector3(cos(bound - 0.25) * r, y, sin(bound - 0.25) * r)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)
	assert_bool(hit.is_empty()).override_failure_message("the step between wedges is open").is_false()
	# It is the wall at that boundary that stopped it, not something further round.
	var where: Vector3 = hit.position
	assert_float(absf(angle_difference(atan2(where.z, where.x), bound))).is_less(0.1)


func test_a_whole_platform_still_has_floor_everywhere_before_it_shrinks() -> void:
	var builder := await _arena("smooth")
	for w in SumoLayout.SECTORS:
		var hit := _down(_at(w, SumoLayout.RADII[0] - 1.0))
		assert_bool(hit.is_empty()).override_failure_message("wedge %d has no floor" % w).is_false()
		assert_float((hit.position as Vector3).y).is_equal_approx(builder.layout.floor_y_of(0), 0.1)


func test_the_warning_band_is_drawn_and_never_driven_on() -> void:
	var builder := await _arena("stepped")
	var layout := builder.layout
	layout.arm(0)
	layout.advance(60.0 / SumoLayout.STEPS - SumoLayout.WARN_S / 2.0)
	builder.refresh()
	await get_tree().physics_frame
	var band := builder.get_node_or_null("Warn/Warn1") as MeshInstance3D
	assert_object(band).override_failure_message("no band for the ring about to go").is_not_null()
	assert_bool(band.visible).is_true()
	assert_object(band.mesh).is_not_null()
	for child in band.get_children():
		assert_bool(child is StaticBody3D).override_failure_message("the band has collision").is_false()
	# The floor under the band is the floor, not the band: the band sits above it and is not solid.
	var hit := _down(_at(0, layout.radius_of(0) - 1.0))
	assert_float((hit.position as Vector3).y).is_equal_approx(layout.floor_y_of(0), 0.1)


func test_a_server_builds_the_collision_and_none_of_the_show() -> void:
	var builder := await _arena("crumble", false)
	assert_object(builder.get_node_or_null("Warn")).override_failure_message("a server built a band").is_null()
	assert_object(builder.get_node_or_null("Goo")).is_null()
	# The floor is still there to rule on, which is what a dedicated server needs.
	assert_bool(_down(_at(0, SumoLayout.RADII[0] - 1.0)).is_empty()).is_false()
