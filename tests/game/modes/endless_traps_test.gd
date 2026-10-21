extends GdUnitTestSuite
## Limits and speed traps on the endless road (D193): limits by biome, lower on tight bends, the
## same everywhere; signs only where the limit changes; traps planned from the seed by their rules;
## a trap shows your speed and keeps your best by road code; reduce flashing means no flash; the
## HUD shows the limit only with traps or police on.


func before() -> void:
	Settings.use_folder("user://tests/endless_traps")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(traps := true, police := false, autodrive := true) -> TrackSession:
	Players.clear()
	var s := TrackSession.new()
	s.platform_id = "official.endless.cruiser"
	s.event = RaceEvent.endless(4242, 1)
	s.event.endless_traffic = "off"
	s.event.speed_traps = traps
	s.event.police = police
	s.autodrive = autodrive
	add_child(s)
	for i in 900:
		if not s.players.is_empty() and s.players[0].vehicle:
			break
		await get_tree().physics_frame
	return s


func test_limits_follow_the_biome_and_drop_on_bends() -> void:
	var gen := EndlessGen.make(77, EndlessBiomes.index_of("alpine"))
	var tiers := {}
	var bends := 0
	for k in 120:
		var c := gen.chunk(k)
		var t := EndlessLimits.tier_of(c)
		assert_int(EndlessLimits.tier_of(gen.chunk(k))).is_equal(t) # the same every time
		tiers[t] = true
		var slowest := INF
		for v in c.speed_up as PackedFloat32Array:
			slowest = minf(slowest, v)
		if slowest < EndlessLimits.BEND_SHARE * EndlessLimits.mps(EndlessLimits.tier_for_kmh(60)) and int(c.biome[60]) == EndlessBiomes.index_of("alpine") and int(c.biome2[60]) == int(c.biome[60]):
			assert_int(t).is_equal(EndlessLimits.tier_for_kmh(60) - EndlessLimits.BEND_DROP)
			bends += 1
	assert_bool(tiers.has(EndlessLimits.tier_for_kmh(60))).is_true()
	assert_int(bends).is_greater(0)
	# The pairs read right in either unit.
	for pair: Array in EndlessLimits.TIERS:
		assert_float(float(pair[1]) * 1.609).is_equal_approx(float(pair[0]), float(pair[0]) * 0.1)


func test_signs_only_where_the_limit_changes() -> void:
	var origin: FloatingOrigin = auto_free(FloatingOrigin.new())
	add_child(origin)
	var w: EndlessWorld = auto_free(EndlessWorld.new())
	w.gen = EndlessGen.make(77, EndlessBiomes.index_of("alpine"))
	w.origin = origin
	w.visual = false
	add_child(w)
	w._update_road(PackedFloat64Array([3000.0]))
	var changes := 0
	for k: int in w._chunk_tracks:
		var c: RoadWindow = w._chunk_tracks[k]
		var signs := w._limit_signs(c)
		if int(c.get_meta(&"tier_before")) == int(c.limit_tier[0]):
			assert_int(signs.size()).is_equal(0)
		else:
			changes += 1
			assert_int(signs.size()).is_equal(2)
			# Each on its own way's side, facing the cars coming.
			for sign: Dictionary in signs:
				var lat := float(c.project((sign.xform as Transform3D).origin).lateral)
				assert_float(absf(lat)).is_greater(c.half_l[0])
			assert_float(signf(float(c.project((signs[0].xform as Transform3D).origin).lateral))).is_equal(-1.0)
			assert_int(int(signs[0].tier)).is_equal(int(c.limit_tier[0]))
			assert_int(int(signs[1].tier)).is_equal(int(c.get_meta(&"tier_before")))
	assert_int(changes).is_greater(0)


func test_traps_are_planned_from_the_seed_by_their_rules() -> void:
	var gen := EndlessGen.make(4242, 1)
	var lanes := EndlessLanes.new()
	var traps := 0
	var cameras := 0
	for k in 900:
		var c := gen.chunk(k)
		var trap := EndlessTraps.plan(4242, k, c, lanes)
		assert_bool(trap == EndlessTraps.plan(4242, k, gen.chunk(k), lanes)).is_true()
		if trap.is_empty():
			continue
		traps += 1
		cameras += 1 if trap.kind == "camera" else 0
		assert_int(k % EndlessTraps.EVERY_CHUNKS).is_equal(0)
		assert_int(k).is_greater_equal(EndlessTraps.FIRST_CHUNK)
		var mid := (c.lifted as PackedByteArray).size() / 2
		assert_float(float(trap.at_m)).is_equal(TrackData.SAMPLE_M * (int(c.first) + mid))
		var railed := false
		for i in range(mid - EndlessTraps.CLEAR_SAMPLES, mid + EndlessTraps.CLEAR_SAMPLES + 1):
			assert_int(int(c.lifted[i])).is_equal(0)
			assert_float(absf(float(c.curvature[i]))).is_less_equal(EndlessTraps.BENDY)
			railed = railed or int(c.barrier_r[i]) != 0
		if railed:
			assert_str(String(trap.kind)).is_equal("camera")
	# About one third-chunk in four, less the bendy and lifted ones; most of them cameras.
	print("traps: %d in %d chunks (%.1f km), %d cameras" % [traps, 900, 900 * 0.24, cameras])
	assert_int(traps).is_between(20, 100)
	assert_float(float(cameras) / traps).is_between(0.5, 0.95)
	# Another seed: other places.
	var other := 0
	for k in range(9, 300, 3):
		var a := EndlessTraps.plan(4242, k, gen.chunk(k), lanes)
		var b := EndlessTraps.plan(4243, k, gen.chunk(k), lanes)
		other += 1 if a.is_empty() != b.is_empty() else 0
	assert_int(other).is_greater(0)


func test_a_trap_shows_your_speed_and_keeps_your_best() -> void:
	var s := await _session(true, false, false) # a player of their own: their profile is kept
	var t := s.endless_traps
	assert_object(t).is_not_null()
	var p := s.players[0]
	p.slot.profile.data.trap_bests = {} # from an earlier run
	var trap := { "id": 99, "at_m": 2000.0, "kind": "camera" }
	var heard := []
	t.snapped.connect(func(r: Racer, tr: Dictionary, v: float) -> void: heard.append([r, tr.id, v]))
	p.vehicle.reset_to(p.vehicle.global_transform, p.vehicle.global_basis.z * 30.0)
	await get_tree().physics_frame
	var first := absf(p.vehicle.speed())
	t._snap(p, trap)
	assert_int(heard.size()).is_equal(1)
	var bests: Dictionary = p.slot.profile.data.trap_bests
	assert_float(float(bests[t.code]["99"])).is_equal_approx(first, 0.05)
	# Slower: no new best. Faster: a new one.
	p.vehicle.reset_to(p.vehicle.global_transform, p.vehicle.global_basis.z * 10.0)
	await get_tree().physics_frame
	assert_bool(t._best(p, 99, 10.0)).is_false()
	assert_bool(t._best(p, 99, first + 5.0)).is_true()
	assert_str(t.tally_text(p)).starts_with("Traps: 1, top ")
	# Kept in the profile on disk.
	var saved := PlayerProfile.load_id(p.slot.profile.id)
	assert_float(float(saved.data.trap_bests[t.code]["99"])).is_equal_approx(first + 5.0, 0.05)
	s.queue_free()
	await get_tree().process_frame


func test_reduce_flashing_means_no_flash() -> void:
	var s := await _session()
	var t := s.endless_traps
	var p := s.players[0]
	# A camera trap ahead in the window.
	var trap := {}
	for k: int in s.endless_world.traps:
		if s.endless_world.traps[k].kind == "camera" and s.endless_world.road.index_of(float(s.endless_world.traps[k].at_m)) >= 0:
			trap = s.endless_world.traps[k]
			break
	assert_bool(trap.is_empty()).is_false()
	t._place_cameras()
	t._snap(p, trap)
	var flash := t._cameras[int(trap.id)].get_node(^"Flash") as OmniLight3D
	assert_bool(flash.visible).is_true()
	await get_tree().create_timer(0.3).timeout
	assert_bool(flash.visible).is_false()
	p.slot.profile.data.reduce_flashing = true
	t._snap(p, trap)
	assert_bool(flash.visible).is_false()
	s.queue_free()
	await get_tree().process_frame


func test_the_hud_shows_the_limit_with_traps_or_police() -> void:
	for on: Array in [[true, false], [false, true], [false, false]]:
		var s := await _session(on[0], on[1])
		var p := s.players[0]
		s.endless._show_limits()
		var want := s.endless_world.road.limit_at(p.distance) if on[0] or on[1] else 0.0
		assert_float(p.hud._limit.mps).is_equal(want)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_float(p.hud.limit()).is_equal(want)
		s.queue_free()
		await get_tree().process_frame
