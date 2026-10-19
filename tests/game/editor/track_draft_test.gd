extends GdUnitTestSuite
## The track editor's draft (EDT-06, D96): commands and their undo, a terrain stroke's exact
## undo, flipping the direction, saving, and autosave with restore.

const DIR := "user://tests/track_draft"


func before() -> void:
	Settings.use_folder(DIR)
	for file in DirAccess.get_files_at(TrackLibrary.user_dir):
		DirAccess.remove_absolute(TrackLibrary.user_dir.path_join(file)) # an earlier run's
	# And its autosaves: a run that was interrupted between autosave() and delete_autosave()
	# leaves one behind, and then this suite counts it along with its own for ever after.
	for left: Dictionary in TrackDraft.autosaves():
		TrackDraft.remove_autosave(String(left.dir))


func after() -> void:
	Settings.use_folder("user://")


func _square() -> TrackDraft:
	var d := TrackDraft.blank("Square", Vector2i(2, 2))
	for p: Vector3 in [Vector3(-150, 0, -100), Vector3(150, 0, -100), Vector3(150, 0, 100), Vector3(-150, 0, 100)]:
		d.add_point(d.points().size(), p)
	d.set_race("start_m", 50.0)
	return d


func test_moves_and_attributes_undo_and_redo() -> void:
	var d := _square()
	var events := []
	d.changed.connect(func(what: StringName, info: Dictionary) -> void: events.append([what, info]))
	var length := d.track().length
	d.move_point(1, Vector3(220, 0, -100))
	assert_float(d.track().length).is_greater(length)
	assert_array(events[-1][1].segments).contains([1])
	d.set_attr(PackedInt32Array([2]), "width_l", 9.0)
	assert_float(d.track().half_l[d.track().seg_first[2]]).is_equal_approx(9.0, 0.01)
	assert_str(d.undo()).is_equal("Set width l")
	assert_bool(d.points()[2].has("width_l")).is_false()
	assert_str(d.undo()).is_equal("Move point")
	assert_float(d.track().length).is_equal_approx(length, 0.01)
	assert_str(d.redo()).is_equal("Move point")
	assert_array(d.points()[1].p).is_equal([220.0, 0.0, -100.0])
	# A drag is one action.
	for x in [230.0, 240.0, 250.0]:
		d.drag_point(3, Vector3(-150, 0, x))
	d.end_move()
	assert_str(d.undo()).is_equal("Move point")
	assert_array(d.points()[3].p).is_equal([-150.0, 0.0, 100.0])


func test_a_terrain_stroke_undoes_exactly() -> void:
	var d := _square()
	var f := d.terrain.field
	var rect := f.rect_around(Vector2(20, 30), 25.0)
	var before := f.region_get(rect)
	f.brush(0, Vector2(20, 30), 20.0, 3.0, 0.5, 0.0, 0.0, 0)
	f.brush(4, Vector2(25, 30), 20.0, 2.0, 0.5, 0.0, 0.05, 3)
	var after := f.region_get(rect)
	d.terrain_stroke(rect, before, after)
	assert_bool(f.region_get(rect) == after).is_true()
	d.undo()
	assert_bool(f.region_get(rect) == before).is_true()
	d.redo()
	assert_bool(f.region_get(rect) == after).is_true()


func test_flipping_drives_the_other_way() -> void:
	var d := _square()
	d.set_attr(PackedInt32Array([0]), "barrier_l", "armco")
	d.set_attr(PackedInt32Array([1]), "width_l", 8.0)
	d.set_race("sectors_m", [300.0, 700.0])
	d.set_race("ai/pins", [{ "at_m": 400.0, "offset_m": 2.0 }])
	var t := d.track()
	var start := t.point_at(t.start_m)
	d.flip_direction()
	var u := d.track()
	assert_float(u.length).is_equal_approx(t.length, 0.5)
	assert_float(u.point_at(u.start_m).distance_to(start)).is_less(2.5) # same place
	assert_float(u.tangents[u.index_at(u.start_m)].dot(t.tangents[t.index_at(t.start_m)])).is_less(-0.9) # facing back
	# The armco that was on the left of segment 0 is on the right of that stretch now (driven the
	# other way, it starts at the second-last point).
	var p: Dictionary = d.points()[d.points().size() - 2]
	assert_str(String(p.get("barrier_r", ""))).is_equal("armco")
	assert_float(float(d.layout.race.ai.pins[0].offset_m)).is_equal(-2.0)
	d.undo()
	assert_float(d.track().point_at(d.track().start_m).distance_to(start)).is_less(0.01)


func test_save_and_autosave_round_trip() -> void:
	var d := _square()
	d.set_info("name", "Saved Square")
	var r := d.save()
	assert_str(String(r.error)).is_empty()
	assert_bool(d.dirty()).is_false()
	assert_str(d.path).ends_with("saved_square.nosstrack")
	d.move_point(0, Vector3(-160, 0, -110))
	assert_bool(d.dirty()).is_true()
	assert_str(d.autosave()).is_empty()
	var saved := TrackDraft.autosaves()
	assert_int(saved.size()).is_equal(1)
	assert_str(String(saved[0].name)).is_equal("Saved Square")
	var back := TrackDraft.from_autosave(saved[0])
	assert_array(back.points()[0].p).is_equal([-160.0, 0.0, -110.0])
	assert_str(back.path).is_equal(d.path)
	assert_bool(back.dirty()).is_true()
	d.delete_autosave()
	assert_int(TrackDraft.autosaves().size()).is_equal(0)
	DirAccess.remove_absolute(d.path)
