extends GdUnitTestSuite
## Ghosts (MODE-02 time trial): a recorded lap replays where the car was, survives a save and
## load, and files from elsewhere are checked.


func before() -> void:
	Settings.use_folder("user://tests/ghost_suite")


func after() -> void:
	Settings.use_folder("user://")


## A car going round a 100 m circle at 20 m/s for one lap, sampled at 30 Hz.
func _circle_lap() -> Ghost:
	var g := Ghost.new()
	var r := 100.0
	var speed := 20.0
	var lap := TAU * r / speed
	var t := 0.0
	while t <= lap:
		var a := speed * t / r
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var vel := Vector3(-sin(a), 0.0, cos(a)) * speed
		var basis := Basis.looking_at(-vel.normalized(), Vector3.UP) # +Z along the velocity
		g.record(t, Transform3D(basis, pos), vel, 0.1)
		t += 1.0 / Ghost.RATE
	g.meta = { "time": lap, "driver": "Test" }
	return g


func test_replay_follows_the_recorded_path_between_samples() -> void:
	var g := _circle_lap()
	for t: float in [0.5, 3.33, 10.017, 20.0, 31.0]:
		var s := g.sample_at(t)
		var a := 20.0 * t / 100.0
		var expected := Vector3(cos(a) * 100.0, 0.0, sin(a) * 100.0)
		# Hermite stays on the circle between samples (linear would cut inside by ~4 cm).
		assert_float((s.xform.origin as Vector3).distance_to(expected)).is_less(0.005)
		assert_float(float(s.speed)).is_equal_approx(20.0, 0.01)


func test_save_load_round_trip() -> void:
	var g := _circle_lap()
	var path := TimeTrial.dir.path_join("test/best.json")
	assert_int(g.save(path)).is_equal(OK)
	var back := Ghost.load_file(path)
	assert_object(back).is_not_null()
	assert_int(back.sample_count()).is_equal(g.sample_count())
	assert_str(String(back.meta.driver)).is_equal("Test")
	assert_vector((back.sample_at(7.0).xform as Transform3D).origin).is_equal_approx((g.sample_at(7.0).xform as Transform3D).origin, Vector3.ONE * 0.001)
	DirAccess.remove_absolute(path)


func test_bad_files_are_refused() -> void:
	var good := _circle_lap().to_dict()
	assert_object(Ghost.from_dict(good)).is_not_null()
	var wrong_schema := good.duplicate()
	wrong_schema.schema = "noss.ghost/9"
	assert_object(Ghost.from_dict(wrong_schema)).is_null()
	var garbage := good.duplicate()
	garbage.samples = Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))
	assert_object(Ghost.from_dict(garbage)).is_null()
	# Time going backwards.
	var g := _circle_lap()
	g.data[Ghost.STRIDE * 5] = -1.0
	assert_object(Ghost.from_dict(g.to_dict())).is_null()


func test_leaderboard_keeps_official_full_speed_laps_in_order() -> void:
	DirAccess.remove_absolute(Leaderboard.path_for("test_track"))
	var base := { "name": "A", "platform": "official.track.gt", "game_speed": 1.0 }
	var e1 := base.duplicate()
	e1.time = 70.0
	var e2 := base.duplicate()
	e2.time = 69.0
	assert_int(Leaderboard.submit("test_track", e1)).is_equal(1)
	assert_int(Leaderboard.submit("test_track", e2)).is_equal(1)
	var slow := base.duplicate()
	slow.time = 60.0
	slow.game_speed = 0.7
	assert_int(Leaderboard.submit("test_track", slow)).is_equal(0)
	var custom := base.duplicate()
	custom.time = 60.0
	custom.platform = "someone.fast"
	assert_int(Leaderboard.submit("test_track", custom)).is_equal(0)
	var list := Leaderboard.entries("test_track", "official.track.gt")
	assert_array(list.map(func(e: Dictionary) -> float: return float(e.time))).is_equal([69.0, 70.0])
	DirAccess.remove_absolute(Leaderboard.path_for("test_track"))
