extends GdUnitTestSuite
## Kart pieces and arenas in the track format (D136-D138): the sections are checked and count in
## the layout hash only when there; rows of item boxes are automatic every third of a lap unless
## placed; a wall-ride stands where the barrier was; a loop has an entry lane and an exit lane;
## an arena is a floor inside its outline with spawns and box clusters.

const KART := "res://tests/fixtures/tracks/kart_small.json"
const ARENA := "res://tests/fixtures/tracks/arena_small.json"
const PROVING_GROUND := "res://content/tracks/proving_ground/track.json"


func _data(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_tracks_without_kart_pieces_hash_as_before() -> void:
	var pg := _data(PROVING_GROUND)
	var before := TrackFormat.layout_hash(pg)
	assert_object(TrackData.from_dict(pg).kart).is_null()
	assert_object(TrackData.from_dict(pg).arena).is_null()
	# A piece changes the layout; moving it does too.
	var with := pg.duplicate(true)
	with.kart = { "stunts": [{ "id": "pad", "kind": "boost_pad", "at_m": 300.0 }] }
	assert_str(TrackFormat.validate(with)).is_empty()
	assert_str(TrackFormat.layout_hash(with)).is_not_equal(before)
	var moved := with.duplicate(true)
	moved.kart.stunts[0].at_m = 320.0
	assert_str(TrackFormat.layout_hash(moved)).is_not_equal(TrackFormat.layout_hash(with))
	# The Lumen Ring keeps its hash (D121).
	var ring: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/tracks/lumen_ring/track.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/tracks/lumen_ring/manifest.json"))
	assert_str(TrackFormat.layout_hash(ring)).is_equal(String(manifest.layout))


func test_pieces_are_checked() -> void:
	var pg := _data(PROVING_GROUND)
	var bad := pg.duplicate(true)
	bad.kart = { "stunts": [{ "id": "a", "kind": "jump", "at_m": 10.0 }, { "id": "a", "kind": "jump", "at_m": 50.0 }] }
	assert_str(TrackFormat.validate(bad)).contains("twice")
	bad.kart = { "stunts": [{ "id": "a", "kind": "jump", "p": [0, 0, 0] }] }
	assert_str(TrackFormat.validate(bad)).contains("at_m")
	bad.kart = { "stunts": [{ "id": "a", "kind": "jump", "at_m": 10.0, "radius_m": 30 }] }
	assert_str(TrackFormat.validate(bad)).is_not_empty() # out of the schema's range
	var arena := _data(ARENA)
	arena.kart.stunts.append({ "id": "loop", "kind": "loop", "p": [0, 0, 0] })
	assert_str(TrackFormat.validate(arena)).contains("needs a road")
	var not_arena := pg.duplicate(true)
	not_arena.arena = {}
	assert_str(TrackFormat.validate(not_arena)).contains("only on arena")
	var many := pg.duplicate(true)
	many.kart = { "stunts": [] }
	for i in 14:
		many.kart.stunts.append({ "id": "row_%d" % i, "kind": "item_row", "at_m": 100.0 * i, "count": 5 })
	assert_str(TrackFormat.validate(many)).contains("item boxes")


func test_automatic_rows_every_third_of_a_lap() -> void:
	var t := TrackData.load_file(PROVING_GROUND)
	var k := KartLayout.build(t, {})
	assert_int(k.rows.size()).is_equal(KartLayout.AUTO_ROWS)
	var at: Array = k.rows.map(func(r: Dictionary) -> float: return t.from_start(r.at_m))
	at.sort()
	for i in at.size():
		var want := t.length * (i + 0.5) / KartLayout.AUTO_ROWS
		assert_float(absf(float(at[i]) - want)).is_less_equal(KartLayout.ROW_SEARCH_M + 0.1)
	for r in k.rows:
		var pts: PackedVector3Array = r.points
		assert_int(pts.size()).is_between(3, 5)
		for p in pts:
			var proj := t.project(p)
			assert_float(absf(float(proj.lateral))).is_less(t.half_width(proj.distance, signf(proj.lateral)) - 1.0)
			assert_float(p.y - t.point_at(proj.distance).y).is_equal_approx(KartLayout.BOX_HEIGHT_M, 0.2)
	assert_int(k.box_points().size()).is_equal(k.rows.reduce(func(n: int, r: Dictionary) -> int: return n + r.points.size(), 0))
	assert_int(KartLayout.build(t, { "boxes": "none" }).rows.size()).is_equal(0)


func test_placed_rows_replace_automatic_ones() -> void:
	var t := TrackData.load_file(KART)
	assert_object(t.kart).is_not_null()
	assert_int(t.kart.rows.size()).is_equal(3)
	assert_float(float(t.kart.rows[0].at_m)).is_equal_approx(100.0, 0.01)


func test_a_wall_ride_stands_where_the_barrier_was() -> void:
	var t := TrackData.load_file(KART)
	var wall: Dictionary = t.kart.pieces.filter(func(p: Dictionary) -> bool: return p.kind == "wall_ride")[0]
	var mid := t.index_at(float(wall.at_m) + 40.0)
	assert_bool(t.kart.gap(mid, 1.0)).is_true() # on the left, round the outside of the corner
	assert_bool(t.kart.gap(mid, -1.0)).is_false()
	assert_bool(t.kart.gap(t.index_at(float(wall.at_m) + 200.0), 1.0)).is_false()


func test_a_loop_has_an_entry_lane_and_an_exit_lane() -> void:
	var t := TrackData.load_file(KART)
	var loop: Dictionary = t.kart.pieces.filter(func(p: Dictionary) -> bool: return p.kind == "loop")[0]
	var lanes := t.kart.loop_lanes(loop)
	assert_float(lanes.x).is_greater(float(loop.width_m) / 2.0)
	assert_float(lanes.y).is_less(-float(loop.width_m) / 2.0)
	var road := t.transform_at(float(loop.at_m))
	# Starts and ends on the road, in its lanes; the top is two radii up.
	assert_vector(t.kart.loop_point(loop, 0.0)).is_equal_approx(road.origin + road.basis.x * lanes.x, Vector3.ONE * 0.01)
	assert_vector(t.kart.loop_point(loop, 1.0)).is_equal_approx(road.origin + road.basis.x * lanes.y, Vector3.ONE * 0.01)
	assert_float(t.kart.loop_point(loop, 0.5).y - road.origin.y).is_equal_approx(2.0 * float(loop.radius_m), 0.01)
	var top := t.kart.loop_progress(t.kart.loop_point(loop, 0.5) - road.basis.y * 0.8)
	assert_float(float(top.t)).is_equal_approx(0.5, 0.02)
	assert_dict(t.kart.loop_progress(road.origin + road.basis.z * 40.0)).is_empty()
	var pins := t.kart.ai_pins()
	assert_int(pins.size()).is_equal(3)
	assert_float(float(pins[0].offset_m)).is_equal(lanes.x)
	assert_float(float(pins[2].offset_m)).is_equal(lanes.y)


func test_an_arena_has_spawns_and_box_clusters_inside() -> void:
	var t := TrackData.load_file(ARENA)
	assert_str(t.type).is_equal("arena")
	var a := t.arena
	assert_object(a).is_not_null()
	assert_float(a.area).is_between(7000.0, 8000.0)
	assert_vector(Vector2(a.centre)).is_equal_approx(Vector2.ZERO, Vector2.ONE * 0.5)
	assert_int(a.spawns.size()).is_equal(ArenaLayout.AUTO_SPAWNS)
	for s in a.spawns:
		assert_bool(a.inside(s.origin, ArenaLayout.WALL_MARGIN_M)).is_true()
		# Facing the middle.
		var to_middle := (Vector3(a.centre.x, s.origin.y, a.centre.y) - s.origin).normalized()
		assert_float(s.basis.z.dot(to_middle)).is_greater(0.99)
	assert_int(a.clusters.size()).is_equal(5)
	assert_int(t.kart.rows.size()).is_equal(5)
	for p in t.kart.box_points():
		assert_bool(a.inside(p, 1.0)).is_true()
	assert_bool(a.inside(Vector3(80, 0, 0))).is_false()
	# Its pieces stand where they're put.
	var pad: Dictionary = t.kart.pieces[0]
	assert_vector((pad.frame as Transform3D).origin).is_equal(Vector3(0, 0, -20))
