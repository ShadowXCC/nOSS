extends GdUnitTestSuite
## The endless road's window (D154): chunks join without a seam, distances stay absolute as the
## window moves on, and the world can move under it (the floating origin).

const CHUNK := 120


func _window(gen: NossRoadGen, first: int, count: int, ox := 0.0, oz := 0.0) -> RoadWindow:
	var w := RoadWindow.new()
	for k in range(first, first + count):
		w.append(RoadWindow.chunk_track(gen.chunk(k), ox, oz, k))
	return w


func test_chunks_join_into_one_strip() -> void:
	var gen := EndlessGen.make(11, 1)
	var w := _window(gen, 0, 6)
	assert_int(w.samples.size()).is_equal(6 * CHUNK + 1)
	assert_float(w.length).is_equal(2.0 * 6 * CHUNK)
	assert_float(w.offset_m).is_equal(0.0)
	assert_array(Array(w.chunks)).is_equal([0, 1, 2, 3, 4, 5])
	# Neighbouring samples 2 m apart (in plan), no seam where chunks meet.
	for i in range(1, w.samples.size()):
		var a := w.samples[i - 1]
		var b := w.samples[i]
		assert_float(Vector2(b.x - a.x, b.z - a.z).length()).is_equal_approx(2.0, 0.001)
	# The frames: left is level when the road isn't banked, and turns with the tangent.
	for i in w.samples.size():
		assert_float(w.lefts[i].dot(w.tangents[i])).is_equal_approx(0.0, 0.01)
		if w.bank[i] == 0.0:
			assert_float(w.lefts[i].y).is_equal_approx(0.0, 1e-5)
		elif w.curvature[i] > 0.004: # into a left bend the left edge is lower
			assert_float(w.lefts[i].y).is_less(0.0)


func test_distances_stay_absolute_as_the_window_moves_on() -> void:
	var gen := EndlessGen.make(11, 1)
	var w := _window(gen, 0, 6)
	var at := w.samples[300] + w.lefts[300] * 1.5
	var p := w.project(at)
	assert_float(float(p.distance)).is_equal_approx(600.0, 0.05)
	assert_float(float(p.lateral)).is_equal_approx(1.5, 0.05)
	var cut := [0]
	w.trimmed.connect(func(n: int) -> void: cut[0] = n)
	w.trim_front(2 * CHUNK)
	assert_int(cut[0]).is_equal(2 * CHUNK)
	assert_float(w.offset_m).is_equal(480.0)
	assert_int(w.first_index).is_equal(240)
	assert_array(Array(w.chunks)).is_equal([2, 3, 4, 5])
	var q := w.project(at, int(p.index) - 2 * CHUNK)
	assert_float(float(q.distance)).is_equal_approx(600.0, 0.05)
	assert_int(int(q.index)).is_equal(int(p.index) - 2 * CHUNK)
	assert_bool(w.point_at(600.0).is_equal_approx(w.samples[60])).is_true()
	assert_int(w.index_at(600.0)).is_equal(60)
	assert_int(w.index_of(100.0)).is_equal(-1) # behind the window
	# On ahead: the next chunk joins the far end.
	w.append(RoadWindow.chunk_track(gen.chunk(6), 0.0, 0.0, 6))
	assert_float(w.end_m()).is_equal(2.0 * 7 * CHUNK)
	assert_bool(w.transform_at(1000.0).origin.is_equal_approx(w.point_at(1000.0))).is_true()


func test_a_window_made_later_is_the_same_road() -> void:
	var a := _window(EndlessGen.make(5, 2), 0, 8)
	a.trim_front(4 * CHUNK)
	var b := _window(EndlessGen.make(5, 2), 4, 4)
	assert_int(b.samples.size()).is_equal(a.samples.size())
	for i in a.samples.size():
		assert_bool(a.samples[i].is_equal_approx(b.samples[i])).is_true()
	assert_float(b.offset_m).is_equal(a.offset_m)


func test_the_world_moves_under_it() -> void:
	var gen := EndlessGen.make(3, 0)
	var w := _window(gen, 0, 3)
	var before := w.project(w.samples[100])
	w.shift(Vector3(-1500.0, 0.0, 1500.0))
	var after := w.project(w.samples[100])
	assert_float(float(after.distance)).is_equal_approx(float(before.distance), 0.01)
	# The same chunks made with the origin moved there come out where the shifted ones are.
	var moved := _window(gen, 0, 3, 1500.0, -1500.0)
	assert_bool(moved.samples[200].is_equal_approx(w.samples[200])).is_true()
