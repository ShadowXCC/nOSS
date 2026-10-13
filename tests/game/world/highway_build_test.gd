extends GdUnitTestSuite
## Building a highway (D106, D107): its ramps, median, markings, lamps, tunnel, signs, portals and
## cushions; ramp mouths a car drives straight across (no step, no barrier); pillars never on a
## road; the server's collision-only build.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"

var _t: TrackData


func before() -> void:
	_t = TrackData.load_file(FIXTURE)


func test_every_piece_is_built() -> void:
	var t0 := Time.get_ticks_usec()
	var root := TrackBuilder.build(_t)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("highway build (%.1f km, visual): %.0f ms" % [_t.length / 1000.0, ms])
	for r in _t.highway.ramps:
		assert_object(root.get_node_or_null("Ramp_" + r.id)).override_failure_message(r.id).is_not_null()
	for node_name in ["Road", "Lines", "Median", "MedianBody", "Lamps", "LampHeads", "Tunnel", "TunnelBody", "Highway/Gantries",
			"Highway/SignBoards", "Highway/Portals", "Highway/PortalShells", "Highway/PortalFloorsBody", "Highway/CushionsBody"]:
		assert_object(root.get_node_or_null(node_name)).override_failure_message(node_name).is_not_null()
	# Two signs before each exit and crossover.
	var signs := root.get_node("Highway").find_children("Sign_*", "Label3D", false, false)
	var leaving := _t.highway.ramps.filter(func(r: RampData) -> bool: return r.from.has("dir")).size()
	assert_int(signs.size()).is_equal(2 * leaving)
	assert_str((signs[0] as Label3D).text).contains("1 km")
	root.free()


func test_the_server_builds_collision_only() -> void:
	var t0 := Time.get_ticks_usec()
	var root := TrackBuilder.build(_t, null, { "visual": false })
	print("highway build (collision only): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	assert_int(root.find_children("*", "MeshInstance3D", true, false).size()).is_equal(0)
	assert_int(root.find_children("*", "Label3D", true, false).size()).is_equal(0)
	assert_object(root.get_node_or_null("Ramp_harbour_off/RoadBody")).is_not_null()
	root.free()


func test_a_car_drives_straight_across_a_ramp_mouth() -> void:
	var root := TrackBuilder.build(_t, null, { "visual": false })
	add_child(root)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	for r in _t.highway.ramps:
		if r.head_count == 0:
			continue
		var dir := int(r.from.dir)
		# Across the taper: from the road's outer lane to the ramp's outer edge, every 0.5 m.
		for n in range(5, r.head_count, 10):
			var k := r.head_main[n]
			var from_lat := _t.highway.lane_lateral(dir, 0)
			var road_y := _t.samples[k].y
			var to_p := r.track.samples[n] + r.track.lefts[n] * (-r.track.half_r[n] + 0.2)
			var from_p := _t.samples[k] + _t.lefts[k] * from_lat
			var steps := int(from_p.distance_to(to_p) / 0.5)
			for s in steps + 1:
				var p := from_p.lerp(to_p, float(s) / maxf(steps, 1))
				var hit := _down(space, p)
				assert_bool(hit.is_empty()).override_failure_message("%s: nothing under %s" % [r.id, p]).is_false()
				assert_float(float(hit.position.y) - road_y).override_failure_message("%s: step at %s" % [r.id, p]).is_between(-0.011, 0.011)
	root.queue_free()


func test_pillars_never_stand_on_a_road() -> void:
	var root := TrackBuilder.build(_t, null, { "visual": false })
	add_child(root)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var checked := 0
	for r in _t.highway.ramps:
		for i in r.track.samples.size():
			if not r.track.lifted[i]:
				continue
			for side: float in [1.0, -1.0]:
				# Just under the deck, inside where a pillar would stand: straight down onto the main
				# road if one is below.
				var p := r.track.samples[i] + r.track.lefts[i] * side * (r.track.half_l[i] - 0.5) + Vector3.DOWN * (RoadBuilder.DECK + 0.3)
				var mp := _t.project(p)
				var k := int(mp.index)
				if absf(float(mp.lateral)) > _t.half_l[k] - 0.5:
					continue
				var hit := _down(space, p)
				assert_float(float(hit.get("position", Vector3.ZERO).y) - _t.samples[k].y).override_failure_message("%s: pillar on the road at %s" % [r.id, p]).is_less(0.5)
				checked += 1
	assert_int(checked).is_greater(10)
	root.queue_free()


func _down(space: PhysicsDirectSpaceState3D, p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 5.0)
	return space.intersect_ray(q)
