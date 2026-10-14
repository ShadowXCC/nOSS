extends GdUnitTestSuite
## Editing highways (EDT-10, D122): the highway template, ramps from templates, their points,
## moving and deleting them, lanes setting the road's widths, and turning the loop round. Every
## change undoes and redoes as one step.


func _ramp_ids(d: TrackDraft) -> Array:
	return (d.layout.highway.get("ramps", []) as Array).map(func(r: Dictionary) -> String: return r.id)


func test_the_highway_template_is_a_valid_highway() -> void:
	var d := TrackTemplates.make("highway")
	assert_bool(d.is_highway()).is_true()
	assert_object(d.terrain).is_null()
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	var t := d.track()
	assert_float(t.length).is_between(4000.0, 5000.0)
	assert_object(t.highway).is_not_null()
	assert_array(Array(t.highway.errors)).is_empty()
	assert_int(t.highway.ramps.size()).is_equal(6)
	assert_int((d.layout.highway.portals as Array).size()).is_equal(4)
	# Nothing to undo or save yet.
	assert_bool(d.history.can_undo()).is_false()
	assert_bool(d.dirty()).is_false()


func test_ramps_from_templates_undo_and_redo() -> void:
	var d := TrackTemplates.make("highway")
	var t := d.track()
	var east := float(t.project(Vector3(800, 0, 0)).distance)
	var before := _ramp_ids(d)
	var hash_before := t.layout_hash
	var ids := d.add_ramp("exit", -1, east + 100.0)
	assert_int(ids.size()).is_equal(1)
	assert_str(ids[0]).is_equal("exit_1")
	assert_int(_ramp_ids(d).size()).is_equal(before.size() + 1)
	assert_object(d.track().highway.ramp("exit_1")).is_not_null()
	assert_str(d.track().highway.ramp("exit_1").error).is_empty()
	assert_str(d.track().layout_hash).is_not_equal(hash_before)
	assert_bool((d.layout.highway.portals as Array).any(func(p: Dictionary) -> bool: return p.id == "exit_1_out")).is_true()
	assert_str(d.undo()).is_equal("Add exit")
	assert_array(_ramp_ids(d)).is_equal(before)
	assert_object(d.track().highway.ramp("exit_1")).is_null()
	assert_str(d.track().layout_hash).is_equal(hash_before)
	d.redo()
	assert_object(d.track().highway.ramp("exit_1")).is_not_null()
	# A second exit gets the next number; an interchange two ramps and two portals.
	assert_str(d.add_ramp("exit", -1, east + 400.0)[0]).is_equal("exit_2")
	var two := d.add_ramp("interchange", 1, east - 300.0, "Docks")
	assert_int(two.size()).is_equal(2)
	assert_str(String(d.ramp(two[0]).name)).is_equal("Docks")


func test_ramp_settings_and_points() -> void:
	var d := TrackTemplates.make("highway")
	var id := "interchange_1_off"
	assert_object(d.ramp(id)).is_not_null()
	d.set_ramp(id, "lanes", 2)
	assert_int(d.track().highway.ramp(id).lanes).is_equal(2)
	d.undo()
	assert_int(d.track().highway.ramp(id).lanes).is_equal(1)
	# A drag is one step, however many moves.
	var pts: Array = d.ramp(id).points
	var n := pts.size()
	var p0 := Vector3(pts[0].p[0], pts[0].p[1], pts[0].p[2])
	for k in 5:
		d.drag_ramp_point(id, 0, p0 + Vector3(0, 0, -2.0 * (k + 1)))
	d.end_ramp_move()
	assert_float(float(d.ramp(id).points[0].p[2])).is_equal_approx(p0.z - 10.0, 0.01)
	d.undo()
	assert_float(float(d.ramp(id).points[0].p[2])).is_equal_approx(p0.z, 0.01)
	d.add_ramp_point(id, 1, p0 + Vector3(30, 0, -8))
	assert_int((d.ramp(id).points as Array).size()).is_equal(n + 1)
	d.delete_ramp_point(id, 1)
	assert_int((d.ramp(id).points as Array).size()).is_equal(n)
	# A ramp keeps one point.
	for k in n + 2:
		d.delete_ramp_point(id, 0)
	assert_int((d.ramp(id).points as Array).size()).is_equal(1)


func test_moving_a_ramp_along_the_road() -> void:
	var d := TrackTemplates.make("highway")
	var id := "interchange_1_off"
	var t := d.track()
	var head := t.highway.ramp(id).track.samples[0]
	var at := float(d.ramp(id).from.at_m)
	var p0: Array = d.ramp(id).points[0].p
	d.move_ramp(id, 50.0)
	assert_float(float(d.ramp(id).from.at_m)).is_equal_approx(fposmod(at + 50.0, t.length), 0.11)
	# On the straight it's moved 50 m along (+x there), nothing across.
	var p1: Array = d.ramp(id).points[0].p
	assert_float(float(p1[0]) - float(p0[0])).is_equal_approx(50.0, 0.1)
	assert_float(float(p1[2]) - float(p0[2])).is_equal_approx(0.0, 0.1)
	assert_float(d.track().highway.ramp(id).track.samples[0].distance_to(head)).is_equal_approx(50.0, 2.5)
	assert_str(d.track().highway.ramp(id).error).is_empty()
	d.undo()
	assert_float(float(d.ramp(id).from.at_m)).is_equal_approx(at, 0.01)


func test_deleting_a_ramp_takes_its_portal() -> void:
	var d := TrackTemplates.make("highway")
	var portals := (d.layout.highway.portals as Array).size()
	d.delete_ramp("interchange_1_off")
	assert_object(d.ramp("interchange_1_off")).is_null()
	assert_int((d.layout.highway.portals as Array).size()).is_equal(portals - 1)
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	d.undo()
	assert_object(d.ramp("interchange_1_off")).is_not_null()
	assert_int((d.layout.highway.portals as Array).size()).is_equal(portals)


func test_lanes_set_the_road_widths() -> void:
	var d := TrackTemplates.make("highway")
	var half := d.track().half_l[0]
	d.set_highway("lanes", 4)
	assert_float(d.track().half_l[0]).is_equal_approx(half + 3.6, 0.01)
	assert_float(float(d.layout.road.defaults.width_r)).is_equal_approx(half + 3.6, 0.01)
	assert_int(d.track().highway.lanes).is_equal(4)
	d.undo()
	assert_float(d.track().half_l[0]).is_equal_approx(half, 0.01)
	# Traffic settings don't touch the layout (or records).
	var hash_before := d.track().layout_hash
	d.set_highway("traffic/count", 250)
	assert_int(int(d.highway().traffic.count)).is_equal(250)
	assert_str(d.track().layout_hash).is_equal(hash_before)


func test_turning_the_loop_round_keeps_the_ramps_in_place() -> void:
	var d := TrackTemplates.make("highway")
	d.set_runs([{ "id": "sprint", "name": "Sprint", "dir": 1, "from_m": 100.0, "to_m": 900.0 }])
	d.set_traps([{ "dir": -1, "at_m": 300.0 }])
	var heads := {}
	var dirs := {}
	for r in d.track().highway.ramps:
		heads[r.id] = r.track.samples[0]
		dirs[r.id] = int(r.from.get("dir", 0))
	var run_from := d.track().point_at(100.0)
	d.flip_direction()
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	var t := d.track()
	assert_array(Array(t.highway.errors)).is_empty()
	# Where they leave the road may shift by a sample: ends snap to the sample before them.
	for r in t.highway.ramps:
		assert_float(r.track.samples[0].distance_to(heads[r.id])).override_failure_message(r.id).is_less(TrackData.SAMPLE_M + 0.5)
		assert_int(int(r.from.get("dir", 0))).is_equal(-int(dirs[r.id]))
	var run: Dictionary = d.layout.highway.runs[0]
	assert_int(int(run.dir)).is_equal(-1)
	assert_float(t.point_at(float(run.from_m)).distance_to(run_from)).is_less(0.5)
	assert_int(int(d.layout.highway.traps[0].dir)).is_equal(1)
	d.undo()
	assert_int(int(d.layout.highway.runs[0].dir)).is_equal(1)


func test_a_circuit_becomes_a_highway_and_back() -> void:
	var d := TrackTemplates.make("oval")
	d.set_type("highway")
	assert_bool(d.is_highway()).is_true()
	assert_float(float(d.layout.road.defaults.width_l)).is_equal_approx(TrackFormat.highway_half(d.highway()), 0.01)
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	d.undo()
	assert_bool(d.is_highway()).is_false()
	assert_bool(d.layout.has("highway")).is_false()
	assert_str(TrackFormat.validate(d.layout)).is_empty()
	d.redo()
	d.set_type("circuit")
	assert_bool(d.layout.has("highway")).is_false()
	assert_str(TrackFormat.validate(d.layout)).is_empty()
