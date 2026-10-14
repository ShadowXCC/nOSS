extends GdUnitTestSuite
## Props (EDT-03, D100): every prop builds, the Proving Ground's set pieces and trees came over
## where they stood, scatter keeps off the road and repeats for a seed, and only solid props
## collide.


func test_every_prop_builds() -> void:
	for id: String in PropLibrary.TYPES:
		var parts := PropLibrary.parts(id)
		assert_array(parts).override_failure_message(id).is_not_empty()
		for part: Dictionary in parts:
			assert_bool((part.batch as MeshBatch).is_empty()).override_failure_message(id).is_false()
			assert_object(PropLibrary.material(String(part.material))).is_not_null()
		assert_int(PropLibrary.mesh(id).get_surface_count()).is_equal(parts.size())
		var shape := PropLibrary.scatter_shape(id)
		assert_bool(shape.is_empty()).override_failure_message(id).is_equal(not PropLibrary.TYPES[id].collide)
	assert_array(PropLibrary.list("nature").map(func(p: Array) -> String: return p[0])).contains(["tree_pine", "rock"])
	assert_array(PropLibrary.list("", true).map(func(p: Array) -> String: return p[0])).not_contains(["grandstand"])


func test_the_proving_grounds_set_pieces_came_over() -> void:
	var v0: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tracks/proving_ground_v0.json"))
	var v1 := TrackFormat.upgrade_v0(v0)
	var items: Array = v1.props.items
	assert_array(items.map(func(i: Dictionary) -> String: return i.prop)).is_equal(["skidpad", "grandstand", "pit_building"])
	var xf: Array = v1.props.scatter[0].xf
	assert_int(xf.size()).is_equal(1400 * 4)
	# The first builder's seeded trees, in its order.
	assert_float(xf[0]).is_equal_approx(0.2779, 0.006) # to the centimetre
	assert_float(xf[1]).is_equal_approx(638.7887, 0.006)
	assert_float(xf[3]).is_equal_approx(7.3227, 0.006)
	assert_float(xf[xf.size() - 4]).is_equal_approx(-117.6013, 0.006)
	assert_str(TrackFormat.validate(v1)).is_empty()


func _square(extra_props := {}) -> TrackData:
	var d := TrackFormat.blank("props", "Props")
	d.road.points = [{ "p": [0, 0, 0] }, { "p": [400, 0, 0] }, { "p": [400, 0, 300] }, { "p": [0, 0, 300] }]
	d.road.defaults.height = "set"
	d.props.merge(extra_props, true)
	return TrackData.from_dict(d)


func test_scatter_keeps_off_the_road_and_repeats() -> void:
	var t := _square()
	var b := PropBuilder.new(t)
	var a := b.scatter_points("tree_pine", Vector2(200, 150), 260.0, 1.0, 42)
	var again := b.scatter_points("tree_pine", Vector2(200, 150), 260.0, 1.0, 42)
	assert_bool(a == again).is_true()
	assert_int(a.size() / 4).is_greater(200)
	for k in range(0, a.size(), 4):
		var p := Vector3(a[k], 0, a[k + 1])
		var proj := t.project(p)
		var reach := 6.0 + 16.0 + 1.1 + 2.0
		assert_bool(absf(proj.lateral) >= reach or p.distance_to(Vector3(proj.point.x, 0, proj.point.z)) >= reach).is_true()
		# Spacing kept.
		for m in range(k + 4, mini(k + 40, a.size()), 4):
			assert_float(Vector2(a[k], a[k + 1]).distance_to(Vector2(a[m], a[m + 1]))).is_greater_equal(4.0 - 0.001)


func test_only_solid_props_collide() -> void:
	var t := _square()
	var b := PropBuilder.new(t)
	var pines := b.scatter_points("tree_pine", Vector2(200, 150), 80.0, 1.0, 1)
	var bushes := b.scatter_points("bush", Vector2(200, 150), 80.0, 1.0, 2)
	var t2 := _square({ "scatter": [{ "prop": "tree_pine", "xf": Array(pines) }, { "prop": "bush", "xf": Array(bushes) }],
		"items": [{ "prop": "tent", "p": [200, 0, 150], "ground": true }, { "prop": "cone", "p": [210, 0, 150], "ground": true }] })
	var root := TrackBuilder.build(t2)
	var bodies := root.find_children("*", "StaticBody3D", false, false).map(func(n: Node) -> String: return n.name)
	assert_bool(bodies.any(func(n: String) -> bool: return n.begins_with("Scatter_tree_pine"))).is_true()
	assert_bool(bodies.any(func(n: String) -> bool: return n.begins_with("Scatter_bush"))).is_false()
	assert_bool(bodies.has("TentBody")).is_true()
	assert_bool(bodies.has("ConeBody")).is_false()
	assert_object(root.get_node_or_null("Cone")).is_not_null()
	root.free()
	# The editor's build: a node per item.
	var edit := TrackBuilder.build(t2, null, { "per_item": true })
	assert_object(edit.get_node_or_null("Item_0/Tent")).is_not_null()
	assert_object(edit.get_node_or_null("Item_1/Cone")).is_not_null()
	edit.free()


func test_city_props_keep_their_footprint_off_the_road_and_bridges_stand_over_it() -> void:
	var t := _square()
	var b := PropBuilder.new(t)
	var towers := b.scatter_points("tower_block", Vector2(200, 150), 300.0, 0.05, 7)
	assert_int(towers.size() / 4).is_greater(10)
	var shape: Dictionary = PropLibrary.scatter_shape("tower_block")
	assert_float((shape.shape as BoxShape3D).size.y).is_greater(30.0)
	for k in range(0, towers.size(), 4):
		var p := Vector3(towers[k], 0, towers[k + 1])
		var proj := t.project(p)
		# The block's half diagonal (about 20 m at most scale) stays off the road and its run-off.
		assert_bool(absf(proj.lateral) >= 6.0 + 16.0 + 1.1 + 2.0 + 20.0 or p.distance_to(Vector3(proj.point.x, 0, proj.point.z)) >= 45.0).is_true()
	# An overpass across the road is not a blockage; an office block on it is.
	var d := TrackTemplates.make("highway")
	var on := d.track().transform_at(400.0)
	d.add_prop({ "prop": "overpass", "p": TrackDraft._vec(on.origin), "yaw_deg": rad_to_deg(atan2(on.basis.x.x, on.basis.x.z)) - 90.0, "scale": 1.0 })
	assert_array(TrackValidator.errors(TrackValidator.check(d))).is_empty()
	d.add_prop({ "prop": "tower_block", "p": TrackDraft._vec(on.origin), "yaw_deg": 0.0, "scale": 1.0 })
	assert_bool(TrackValidator.errors(TrackValidator.check(d)).any(func(e: String) -> bool: return e.begins_with("Road blocked"))).is_true()
