extends GdUnitTestSuite
## A circuit's pit lane (D203): it leaves the road on its side and joins it again, attached to the
## paved edge; the road's barrier opens at its mouths; the boxes sit between the limit lines; a
## car in it is in the pits; the checks catch one that's too short, crowded or under the grid; and
## flipping the track turns it round.


## A 1.4 km stadium (400 m straights, 150 m ends) turning left on 2x2 chunks of flat terrain,
## the start on the top straight.
func _oval() -> TrackDraft:
	var d := TrackDraft.blank("Pit oval", Vector2i(4, 3))
	for end in [1.0, -1.0]:
		for x in [-200.0, -100.0, 0.0, 100.0, 200.0]:
			d.add_point(d.points().size(), Vector3(x * end, 0.0, 150.0 * end))
		for deg in [30.0, 60.0, 90.0, 120.0, 150.0]:
			var a := deg_to_rad(deg)
			d.add_point(d.points().size(), Vector3((200.0 + 150.0 * sin(a)) * end, 0.0, 150.0 * cos(a) * end))
	d.set_race("start_m", 320.0)
	d.set_race("grid/slots", 8)
	return d


## A pit lane on the inside (left) of the top straight.
func _with_pit(d: TrackDraft, boxes := 12) -> TrackData:
	d.add_pit(20.0, 640.0, "left")
	d.set_pit("boxes", boxes)
	return d.track()


func test_the_lane_leaves_and_joins_the_road_on_its_side() -> void:
	var d := _oval()
	var plain_hash := d.track().layout_hash
	var t := _with_pit(d)
	assert_str(t.pit_error).is_empty()
	var pit := t.pit
	assert_object(pit).is_not_null()
	assert_str(t.layout_hash).is_not_equal(plain_hash) # a pit lane is part of the layout
	assert_float(pit.track.length).is_between(560.0, 700.0)
	# Its ends are on the road's left edge, and it starts from nothing.
	var first := pit.track.samples[0]
	var k := pit.head_main[0]
	assert_float(first.distance_to(t.paved_edge(k, 1.0))).is_less(0.1)
	assert_float(pit.track.half_l[0]).is_less(0.1)
	var last := pit.track.samples[pit.track.samples.size() - 1]
	assert_float(last.distance_to(t.paved_edge(pit.tail_main[pit.tail_main.size() - 1], 1.0))).is_less(0.1)
	# The road's barrier opens on the left at the mouths, not on the right or along the wall.
	assert_bool(pit.gap(pit.head_main[1], 1.0)).is_true()
	assert_bool(pit.gap(pit.head_main[1], -1.0)).is_false()
	assert_bool(pit.gap(t.index_at(330.0), 1.0)).is_false()
	# The wall stands on the lane's right (toward the road) between the gores.
	var mid := (pit.gore_head + pit.gore_tail) / 2
	assert_int(int(pit.track.barrier_r[mid])).is_equal(TrackFormat.BARRIER_CONCRETE)
	assert_int(int(pit.track.barrier_l[mid])).is_equal(TrackFormat.BARRIER_NONE)


func test_boxes_sit_between_the_limit_lines() -> void:
	var t := _with_pit(_oval(), 12)
	var pit := t.pit
	assert_int(pit.boxes.size()).is_equal(12)
	assert_bool(pit.crowded).is_false()
	for b in pit.box_at.size():
		assert_bool(pit.limited(pit.box_at[b])).is_true()
	# Nearest the exit first, on the lane's far half from the road.
	assert_float(pit.box_at[0]).is_greater(pit.box_at[11])
	var on := t.project(pit.boxes[0].origin)
	assert_float(float(on.lateral)).is_greater(t.half_l[int(on.index)] + PitLane.DEFAULTS.width_m / 2.0)


func test_a_car_in_the_lane_is_in_the_pits() -> void:
	var t := _with_pit(_oval())
	var pit := t.pit
	var box := pit.boxes[3].origin + Vector3.UP * 0.5
	var r := Racer.new()
	r.track = t
	r.distance = float(t.project(box).distance)
	r._update_pit(box)
	assert_bool(r.in_pit).is_true()
	assert_float(r.pit_distance).is_equal_approx(pit.box_at[3], 0.5)
	var road := t.transform_at(330.0).origin + Vector3.UP * 0.5
	r.distance = 330.0
	r._update_pit(road)
	assert_bool(r.in_pit).is_false()
	r.free()


func test_it_builds_with_its_wall_and_paint() -> void:
	var t := _with_pit(_oval())
	var root := TrackBuilder.build(t)
	var pit := root.get_node("Pit")
	assert_object(pit.get_node_or_null("Road")).is_not_null()
	assert_object(pit.get_node_or_null("RoadBody")).is_not_null()
	assert_object(pit.get_node_or_null("ConcreteWalls")).is_not_null()
	assert_object(pit.get_node_or_null("Lines")).is_not_null()
	root.free()


func test_the_checks_catch_a_bad_pit_lane() -> void:
	var d := _oval()
	_with_pit(d)
	var texts := TrackValidator.check(d).map(func(p: Dictionary) -> String: return p.text)
	for text: String in texts:
		assert_bool(text.begins_with("Pit") or text.begins_with("Grid in")).override_failure_message(text).is_false()
	d.set_pit("boxes", 40)
	assert_array(TrackValidator.errors(TrackValidator.check(d))).contains(["Pit boxes don't fit"])
	d.set_pit("boxes", 12)
	d.set_pit("to_m", 200.0)
	assert_array(TrackValidator.errors(TrackValidator.check(d))).contains(["Pit lane too short"])
	d.set_pit("to_m", 640.0)
	d.set_pit("from_m", 250.0) # the grid stands in the entry
	assert_array(TrackValidator.errors(TrackValidator.check(d))).contains(["Grid in the pit mouth"])


func test_flipping_turns_the_lane_round() -> void:
	var d := _oval()
	var t := _with_pit(d)
	var entry := t.pit.track.samples[0]
	var exit := t.pit.track.samples[t.pit.track.samples.size() - 1]
	d.flip_direction()
	var u := d.track()
	assert_str(u.pit_error).is_empty()
	assert_str(String(d.layout.pit.side)).is_equal("right")
	# Its entry is where the exit was, and the other way about.
	assert_float(u.pit.track.samples[0].distance_to(exit)).is_less(3.0)
	assert_float(u.pit.track.samples[u.pit.track.samples.size() - 1].distance_to(entry)).is_less(3.0)
