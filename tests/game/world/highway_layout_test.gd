extends GdUnitTestSuite
## Highway tracks (D106, D107): carriageways and lanes, ramps that share the road's edge, ramp
## mouths, finding which road a car is on, the lane graph, and the format's checks.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"

var _t: TrackData


func before() -> void:
	_t = TrackData.load_file(FIXTURE)


func test_fixture_loads_as_a_highway() -> void:
	assert_object(_t).is_not_null()
	assert_str(_t.type).is_equal("highway")
	assert_object(_t.highway).is_not_null()
	assert_array(_t.highway.errors).is_empty()
	assert_int(_t.highway.ramps.size()).is_equal(6)
	assert_float(_t.length).is_between(4300.0, 4500.0)
	assert_float(_t.highway.half).is_equal_approx(15.8, 0.001)


func test_lanes_count_from_the_outside() -> void:
	var h := _t.highway
	# Direction 1 drives on the road's right (negative lateral); lane 0 by the outer shoulder.
	assert_float(h.lane_lateral(1, 0)).is_equal_approx(-11.0, 0.001)
	assert_float(h.lane_lateral(1, 2)).is_equal_approx(-3.8, 0.001)
	assert_float(h.lane_lateral(-1, 0)).is_equal_approx(11.0, 0.001)
	assert_int(h.lane_at(-11.0)).is_equal(0)
	assert_int(h.lane_at(3.0)).is_equal(2)
	assert_int(HighwayLayout.carriageway_at(-5.0)).is_equal(1)
	assert_int(HighwayLayout.carriageway_at(5.0)).is_equal(-1)


func test_a_ramp_starts_on_the_road_edge_and_widens() -> void:
	for r in _t.highway.ramps:
		var ends := []
		if not r.head_main.is_empty():
			ends.append([r.head_main, int(r.from.dir), 0])
		if not r.tail_main.is_empty():
			ends.append([r.tail_main, int(r.to.dir), r.track.samples.size() - r.tail_main.size()])
		for e: Array in ends:
			var ks: PackedInt32Array = e[0]
			var dir: int = e[1]
			for n in ks.size():
				var k := ks[n]
				var i: int = e[2] + n
				var inner := r.track.samples[i] + r.track.lefts[i] * r.track.half_l[i]
				var edge: float = _t.half_r[k] if dir > 0 else _t.half_l[k]
				var road_edge := _t.samples[k] + _t.lefts[k] * (-dir * edge)
				assert_float(inner.distance_to(road_edge)).override_failure_message("%s sample %d" % [r.id, i]).is_less(0.001)
		# Fully out once the taper ends.
		if not r.head_main.is_empty():
			assert_float(r.track.half_l[r.head_main.size() - 1] * 2.0).is_equal_approx(r.width, 0.01)
			assert_float(r.track.half_l[0]).is_equal_approx(RampData.MIN_WIDTH / 2.0, 0.001)


func test_no_ramp_cuts_into_the_road() -> void:
	for r in _t.highway.ramps:
		for i in r.track.samples.size():
			if r.track.lifted[i]:
				continue
			for side: float in [1.0, -1.0]:
				var p := r.track.samples[i] + r.track.lefts[i] * side * r.track.half_l[i]
				var proj := _t.project(p)
				var k := int(proj.index)
				if absf(p.y - _t.samples[k].y) > TrackData.LIFTED_M:
					continue
				var edge: float = _t.half_l[k] if float(proj.lateral) >= 0.0 else _t.half_r[k]
				assert_float(absf(float(proj.lateral))).override_failure_message("%s sample %d inside the road" % [r.id, i]).is_greater(edge - 0.01)


func test_mouths_open_the_road_edge_where_ramps_meet_it() -> void:
	var h := _t.highway
	for r in h.ramps:
		if not r.head_main.is_empty():
			for k in r.head_main:
				assert_bool(h.gap(k, -float(r.from.dir))).is_true()
		if not r.tail_main.is_empty():
			for k in r.tail_main:
				assert_bool(h.gap(k, -float(r.to.dir))).is_true()
	# Away from every ramp the edges are whole: halfway round from the first exit.
	var far := posmod(h.ramps[0].head_main[0] + _t.samples.size() / 4, _t.samples.size())
	assert_bool(h.gap(far, 1.0) or h.gap(far, -1.0)).is_false()


func test_locate_keeps_the_flyover_and_the_road_under_it_apart() -> void:
	var h := _t.highway
	var link := h.ramp("mill")
	var top := 0
	for i in link.track.samples.size():
		if link.track.samples[i].y > link.track.samples[top].y:
			top = i
	var above := link.track.samples[top] + Vector3.UP * 0.5
	var on_ramp := h.locate(above)
	assert_bool(on_ramp.on_road).is_true()
	assert_int(on_ramp.road).is_equal(h.ramps.find(link))
	var below := Vector3(above.x, _t.samples[_t.project(above).index].y + 0.5, above.z)
	var on_main := h.locate(below)
	assert_int(on_main.road).is_equal(-1)
	assert_bool(on_main.on_road).is_true()


func test_locate_finds_the_carriageway_and_lane() -> void:
	var h := _t.highway
	var spot := h.spawn_spot(-1, 1000.0, 1)
	var at := h.locate(spot.origin + Vector3.UP * 0.5)
	assert_int(at.road).is_equal(-1)
	assert_int(at.dir).is_equal(-1)
	assert_int(at.lane).is_equal(1)
	# Facing the way direction -1 drives: against the road's tangent.
	assert_float(spot.basis.z.dot(_t.tangents[_t.index_at(1000.0)])).is_less(-0.99)


func test_open_strips_clamp_at_their_ends() -> void:
	var strip := _t.highway.ramps[0].track
	assert_bool(strip.closed).is_false()
	var end := strip.samples[strip.samples.size() - 1]
	var beyond := end + strip.tangents[strip.samples.size() - 1] * 50.0
	var proj := strip.project(beyond)
	assert_float(float(proj.distance)).is_equal_approx(strip.length, 0.01)
	assert_float(strip.point_at(strip.length + 100.0).distance_to(end)).is_less(0.001)
	assert_float(strip.point_at(-5.0).distance_to(strip.samples[0])).is_less(0.001)


func test_lane_graph_connects_ramps_to_the_outer_lanes() -> void:
	var h := _t.highway
	var g := h.lane_graph()
	var traffic_ramps := h.ramps.filter(func(r: RampData) -> bool: return r.traffic).size()
	assert_int(traffic_ramps).is_equal(4)
	assert_int(g.lanes.size()).is_equal(6 + traffic_ramps)
	assert_int(g.adjacent.size()).is_equal(2 * 4)
	assert_int(g.branches.size()).is_equal(3 * 2)
	assert_int(g.merges.size()).is_equal(3 * 2)
	assert_int(g.attaches.size()).is_equal(5 * 2)
	for k in range(0, g.branches.size(), 3):
		var from_pts: PackedVector3Array = g.lanes[g.branches[k]].points
		var ramp_pts: PackedVector3Array = g.lanes[g.branches[k + 2]].points
		assert_float(from_pts[g.branches[k + 1]].distance_to(ramp_pts[0])).is_less(0.01)
	for k in range(0, g.merges.size(), 3):
		var ramp_pts: PackedVector3Array = g.lanes[g.merges[k]].points
		var into_pts: PackedVector3Array = g.lanes[g.merges[k + 1]].points
		assert_float(ramp_pts[ramp_pts.size() - 1].distance_to(into_pts[g.merges[k + 2]])).is_less(0.01)
	# Direction -1's lanes run against the road: their first step goes the other way.
	var lane: PackedVector3Array = g.lanes[h.main_lane(-1, 0)].points
	assert_float((lane[1] - lane[0]).dot(_t.tangents[0])).is_less(0.0)
	assert_int(g.portal_in.size()).is_equal(2 * 2)
	assert_int(g.portal_out.size()).is_equal(2 * 2)
	# The tunnel's 80 km/h shows in the limits.
	var limits: PackedInt32Array = g.lanes[0].limits
	assert_int(Array(limits).min()).is_equal(roundi(80.0 / 3.6 * 1000.0))


func test_native_traffic_runs_on_the_lane_graph() -> void:
	var traffic := NossTraffic.new()
	var types := [{ "length_m": 4.5, "width_m": 1.8, "speed_factor": [0.9, 1.1], "weight": 8 },
		{ "length_m": 9.0, "width_m": 2.5, "speed_factor": [0.8, 0.88], "accel": 0.7, "lanes_max": 2, "weight": 2 }]
	assert_str(traffic.setup(_t.highway.lane_graph(), types, 5, 150, 0.15)).is_empty()
	assert_int(traffic.get_count()).is_equal(150)
	traffic.step_to(20 * 60)
	assert_int(traffic.get_tick()).is_equal(1200)
	assert_int(traffic.active_count() + traffic.away_count()).is_equal(150)
	var poses := traffic.poses(0.5)
	assert_int(poses.size()).is_equal(150 * 8)
	# A car is on the road it's said to be on.
	for i in 150:
		if int(poses[i * 8 + 5]) & 1:
			var at := Vector3(poses[i * 8], poses[i * 8 + 1] + 0.5, poses[i * 8 + 2])
			assert_bool(_t.highway.locate(at).on_road).override_failure_message("car %d at %s" % [i, at]).is_true()
	# Same seed, same graph: same traffic.
	var again := NossTraffic.new()
	again.setup(_t.highway.lane_graph(), types, 5, 150, 0.15)
	again.step_to(1200)
	assert_int(again.checksum()).is_equal(traffic.checksum())
	assert_int(again.graph_hash()).is_equal(traffic.graph_hash())
	# Events round-trip through bytes.
	var e := NossTraffic.pack_event(1, 7, 1300, 12, 3, 2, 1234.5, 25.0, -1, 0, 0, 0)
	assert_int(e.size()).is_equal(24)
	var back: Dictionary = NossTraffic.unpack_events(e)[0]
	assert_int(back.car).is_equal(12)
	assert_float(back.s).is_equal_approx(1234.5, 0.001)
	assert_float(back.v).is_equal_approx(25.0, 0.01)


func test_speed_limits_and_tunnels_come_from_zones() -> void:
	var h := _t.highway
	var z: Dictionary = h.zones[0]
	var mid := fposmod((z.from_m + z.to_m) / 2.0, _t.length)
	assert_float(h.speed_at(1, mid) * 3.6).is_equal_approx(80.0, 0.01)
	assert_bool(h.in_tunnel(mid)).is_true()
	assert_float(h.speed_at(1, fposmod(mid + 1000.0, _t.length)) * 3.6).is_equal_approx(110.0, 0.01)
	assert_bool(h.in_tunnel(fposmod(mid + 1000.0, _t.length))).is_false()


func test_layout_hash_counts_ramps_but_not_traffic() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var base := TrackFormat.layout_hash(d)
	var busier := d.duplicate(true)
	busier.highway.traffic = { "count": 400 }
	assert_str(TrackFormat.layout_hash(busier)).is_equal(base)
	var moved := d.duplicate(true)
	moved.highway.ramps[0].from.at_m = float(moved.highway.ramps[0].from.at_m) + 20.0
	assert_str(TrackFormat.layout_hash(moved)).is_not_equal(base)


func test_format_checks_ramp_ends() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_str(TrackFormat.validate(d)).is_empty()
	var bad := d.duplicate(true)
	bad.highway.ramps[0].to = { "portal": "nowhere" }
	assert_str(TrackFormat.validate(bad)).contains("no portal nowhere")
	bad = d.duplicate(true)
	bad.highway.ramps[0].kind = "entry"
	assert_str(TrackFormat.validate(bad)).contains("an entry goes from a portal to the road")
	bad = d.duplicate(true)
	bad.highway.ramps[1].id = bad.highway.ramps[0].id
	assert_str(TrackFormat.validate(bad)).contains("twice")
	bad = d.duplicate(true)
	bad.highway.ramps[1].from = bad.highway.ramps[0].to.duplicate()
	assert_str(TrackFormat.validate(bad)).contains("serves two ramps")
	var circuit := TrackFormat.blank("c", "C")
	circuit.highway = {}
	assert_str(TrackFormat.validate_highway(circuit)).contains("only on highway tracks")


func test_highway_settings_fill_defaults() -> void:
	var d := TrackFormat.blank("h", "H")
	d.type = "highway"
	d.highway = { "lanes": 4, "ramps": [{ "id": "a", "kind": "exit", "from": { "dir": 1, "at_m": 10 }, "to": { "portal": "p" } }], "traffic": { "count": 60 } }
	var h := TrackFormat.highway_settings(d)
	assert_int(h.lanes).is_equal(4)
	assert_float(h.lane_m).is_equal(3.6)
	assert_int(h.traffic.count).is_equal(60)
	assert_float(h.traffic.exit_share).is_equal(0.15)
	assert_float(h.ramps[0].taper_m).is_equal(200.0)
	assert_float(TrackFormat.highway_half(h)).is_equal_approx(1.2 + 0.8 + 14.4 + 3.0, 0.001)
	assert_dict(TrackFormat.highway_settings(TrackFormat.blank("c", "C"))).is_empty()
