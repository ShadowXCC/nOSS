class_name RoadBuilder
extends RefCounted
## Builds a track's road from its samples (docs/TRACK_EDITOR.md §2): the road surface, its lines,
## curbs, run-off strips, barriers, and decks and pillars where it stands on supports, each piece
## with the surface the tires read (docs/PHYSICS.md §4).
##
## In the game every kind is one piece for the whole track ("Road", "Curbs", "Barriers", ...);
## the editor builds a node per control segment, so a drag rebuilds only the segments it moved.

const RUNOFF_OVER_GROUND := 0.02 # m, run-off over flat ground
const CURB_WIDTH := TrackData.CURB_WIDTH
const CURB_HEIGHT := 0.045
## Across the curb, from the road's edge: [out, up].
const CURB_PROFILE := [[0.0, 0.0], [0.35, CURB_HEIGHT], [CURB_WIDTH, CURB_HEIGHT * 0.6]]
const LINE_WIDTH := 0.25
const LINE_INSET := 0.3
const LINE_UP := 0.01
const DASH_ON := 3.0
const DASH_OFF := 9.0
## Auto barriers: tyre walls on the outside of corners tighter than this radius.
const BARRIER_CURVATURE := 1.0 / 260.0
## Barrier sizes by type id (TrackFormat.BARRIERS): [height, thickness].
const BARRIER_SIZE := { 2: [0.9, 1.0], 3: [0.75, 0.3], 4: [1.0, 0.6], 5: [2.5, 0.12], 6: [4.5, 0.25], 7: [1.2, 0.6] }
## A SAFER wall's catch fence (D202): on the wall's top, [height, thickness]; a post every POST_M.
const CATCH_FENCE := [3.8, 0.06]
const POST_M := 6.0
const POST := 0.12
const SKIRT := 0.3
const DECK := 0.6
const PILLAR_EVERY_M := 20.0
const PILLAR := 0.8
const PARAPET := [1.0, 0.5]
## A flat-ground track's site wall, this far out around the road.
const SITE_WALL_M := 150.0

var track: TrackData
var terrain: TerrainData
## Without visuals (the dedicated server): collision only.
var visual := true
var _ground_y := -0.03
## The endless road's markings (null elsewhere).
var markings: EndlessMarkings
## A highway's markings, median, mouths and extras (null on circuits).
var _hw: HighwayBuilder
## An open strip whose first and last samples are shared with strips built apart (an endless
## chunk's): walls at its ends run on into theirs (D218).
var joined_ends := false


func _init(t: TrackData, ground: TerrainData = null) -> void:
	track = t
	terrain = ground
	_ground_y = float(t.raw.get("ground", {}).get("flat_y", -0.03))
	if t.highway:
		_hw = HighwayBuilder.new(self, t.highway)


## Every piece into `root`: one node per kind, or one per segment ("Seg_<n>") if `segmented`.
func build_all(root: Node3D, segmented := false) -> void:
	if track.samples.size() < 3 or track.kind != "road":
		return
	if segmented:
		for s in track.seg_first.size():
			root.add_child(build_segment(s))
	else:
		_add_batches(root, _batches(0, track.samples.size()))
	_add_batches(root, { "barrier:perimeter": _perimeter() })
	if _hw:
		for r in track.highway.ramps:
			root.add_child(build_ramp(r))
		root.add_child(_hw.extras())
	if track.pit:
		root.add_child(build_pit())
	if not track.scenery.is_empty():
		root.add_child(build_scenery())


## A circuit's pit lane (D203) as one node, "Pit": its road and lines, the limit lines, the box
## outlines and the pit wall.
func build_pit() -> Node3D:
	var pit := track.pit
	var rb := RoadBuilder.new(pit.track, terrain)
	rb.visual = visual
	var node := Node3D.new()
	node.name = "Pit"
	var pieces := rb._batches(0, pit.track.samples.size() - 1)
	if visual:
		rb._pit_paint(rb._batch(pieces, "lines"), pit)
	rb._add_batches(node, pieces)
	return node


## Replaces the pit lane's node under `root` (the editor, after the road moved).
func rebuild_pit(root: Node3D) -> void:
	var old := root.get_node_or_null(^"Pit")
	if old:
		root.remove_child(old)
		old.queue_free()
	if track.pit:
		root.add_child(build_pit())


## The track's scenery roads (D212) as one node, "Scenery", a "Piece_<n>" in it for each piece.
func build_scenery() -> Node3D:
	var node := Node3D.new()
	node.name = "Scenery"
	for k in track.scenery.size():
		var piece := track.scenery[k]
		var rb := RoadBuilder.new(piece, terrain)
		rb.visual = visual
		rb._ground_y = _ground_y
		var part := Node3D.new()
		part.name = "Piece_%d" % k
		rb._add_batches(part, rb._batches(0, piece.samples.size() - 1))
		node.add_child(part)
	return node


## Replaces the scenery roads' node under `root` (the editor, after the road moved: they're fitted
## to it).
func rebuild_scenery(root: Node3D) -> void:
	var old := root.get_node_or_null(^"Scenery")
	if old:
		root.remove_child(old)
		old.queue_free()
	if not track.scenery.is_empty():
		root.add_child(build_scenery())


## A highway ramp's road as one node, "Ramp_<id>".
func build_ramp(r: RampData) -> Node3D:
	var rb := RoadBuilder.new(r.track, terrain)
	rb.visual = visual
	rb._hw = HighwayBuilder.new(rb, track.highway, r)
	var node := Node3D.new()
	node.name = "Ramp_" + r.id
	rb._add_batches(node, rb._batches(0, r.track.samples.size() - 1))
	return node


## Rebuilds a highway's ramps and its extras (signs, portals, cushions) under `root`.
func rebuild_highway(root: Node3D) -> void:
	if not _hw:
		return
	for child in root.get_children():
		if String(child.name).begins_with("Ramp_") or child.name == &"Highway":
			root.remove_child(child)
			child.queue_free()
	for r in track.highway.ramps:
		root.add_child(build_ramp(r))
	root.add_child(_hw.extras())


## Replaces ramp `id`'s node under `root` (none if the ramp is gone or doesn't build).
func rebuild_ramp(root: Node3D, id: String) -> void:
	var old := root.get_node_or_null(NodePath("Ramp_" + id))
	if old:
		root.remove_child(old)
		old.queue_free()
	var r := track.highway.ramp(id) if _hw else null
	if r:
		root.add_child(build_ramp(r))


## Replaces the highway's signs, portals and cushions under `root`.
func rebuild_extras(root: Node3D) -> void:
	if not _hw:
		return
	var old := root.get_node_or_null(^"Highway")
	if old:
		root.remove_child(old)
		old.queue_free()
	root.add_child(_hw.extras())


## Segment `s`'s pieces as one node, "Seg_<s>".
func build_segment(s: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Seg_%d" % s
	var span := track.segment_samples(s)
	_add_batches(node, _batches(span.x, span.y))
	return node


## Replaces the nodes of `segments` under `root` (built segmented).
func rebuild_segments(root: Node3D, segments: PackedInt32Array) -> void:
	if track.kind != "road":
		return
	for s in segments:
		var old := root.get_node_or_null("Seg_%d" % s)
		if old:
			root.remove_child(old)
			old.queue_free()
		if s >= 0 and s < track.seg_first.size():
			root.add_child(build_segment(s))


# --- pieces ---------------------------------------------------------------------------------


## The pieces of samples [first, end) (end may pass the last sample: it wraps). Keyed by kind.
func _batches(first: int, end: int) -> Dictionary:
	var out := {}
	var n := track.samples.size()
	for i in range(first, end):
		var k := i % n
		var j := (i + 1) % n
		var surface := int(track.surface[k])
		# A highway's tunnels keep the weather off their road (D153).
		var dry := _hw != null and _hw.sheltered(k, j)
		_road_quad(_batch(out, ("road_dry:%d" if dry else "road:%d") % surface), k, j)
		for side: float in [1.0, -1.0]:
			if track.apron(k, side) > 0.0 or track.apron(j, side) > 0.0:
				_apron(_batch(out, ("road_dry:%d" if dry else "road:%d") % surface), k, j, side)
		if visual:
			if _hw:
				_hw.lines(_batch(out, "lines_dry" if dry else "lines"), k, j)
			elif markings:
				markings.lines(_batch(out, "lines"), _batch(out, "lines_yellow"), k, j)
			else:
				_lines(_batch(out, "lines"), k, j)
		for side: float in [1.0, -1.0]:
			if (track.curb_l if side > 0.0 else track.curb_r)[k] and not _gapped(k, side):
				_curb(_batch(out, "curbs"), k, j, side)
			var runoff := int((track.runoff_l if side > 0.0 else track.runoff_r)[k])
			if runoff != _ground_surface() and (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[k] > 0.1 and not _gapped(k, side) and not _gapped(j, side):
				_runoff(_batch(out, "runoff:%d" % runoff), k, j, side)
		if track.lifted[k] or track.lifted[j]:
			_deck(_batch(out, "bridge"), k, j)
	_barriers(out, first, end)
	_pillars(out, first, end)
	if _hw and _hw.ramp == null:
		_hw.main_pieces(out, first, end)
	return out


## True where `side` of sample `k` opens onto another road (a highway's ramp mouths, a pit lane's).
func _gapped(k: int, side: float) -> bool:
	return (_hw != null and _hw.gapped(k, side)) or (track.kart != null and track.kart.gap(k, side)) or (track.pit != null and track.pit.gap(k, side))


func _batch(out: Dictionary, key: String) -> MeshBatch:
	if not out.has(key):
		out[key] = MeshBatch.new()
	return out[key]


func _ground_surface() -> int:
	return TrackFormat.surface_id(String(track.raw.get("ground", {}).get("surface", "grass"))) if terrain == null else VehicleSim.SURFACE_GRASS


func _edge(i: int, side: float, out := 0.0, up := 0.0) -> Vector3:
	var half: float = track.half_l[i] if side > 0.0 else track.half_r[i]
	return track.samples[i] + track.lefts[i] * side * (half + out) + track.ups[i] * up


func _road_quad(b: MeshBatch, i: int, j: int) -> void:
	var c := Color(0.82, 0.82, 0.82)
	var li := _edge(i, 1.0)
	var ri := _edge(i, -1.0)
	var lj := _edge(j, 1.0)
	var rj := _edge(j, -1.0)
	b.quad([li, ri, rj, lj], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], c)
	if terrain:
		# Skirts down the edges hide the ground's 5 cm step under the road (past an apron).
		for side: float in [1.0, -1.0]:
			var ti := _paved(i, side)
			var tj := _paved(j, side)
			var down := Vector3.DOWN * SKIRT
			var face := [ti + down, ti, tj, tj + down] if side > 0.0 else [ti, ti + down, tj + down, tj]
			b.quad(face, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], c)


## A pit lane's paint on its own road (this builder's): the limit lines across it and each box's
## outline.
func _pit_paint(b: MeshBatch, pit: PitLane) -> void:
	var half := pit.width / 2.0
	for d: float in [pit.limit_in_m, pit.limit_out_m]:
		var here := track.half_width(d, 1.0) # narrower in the tapers
		_strip_quad(b, d - 0.3, d + 0.3, here - LINE_INSET, -here + LINE_INSET)
	var inner := pit.side * LINE_INSET # the box lane: from the middle out to the edge
	var outer := pit.side * (half - LINE_INSET)
	for d in pit.box_at:
		var a := d - pit.box_m / 2.0
		var z := d + pit.box_m / 2.0
		_strip_quad(b, a, a + LINE_WIDTH, maxf(inner, outer), minf(inner, outer))
		_strip_quad(b, z - LINE_WIDTH, z, maxf(inner, outer), minf(inner, outer))
		_strip_quad(b, a, z, maxf(inner, inner + pit.side * LINE_WIDTH), minf(inner, inner + pit.side * LINE_WIDTH))


## A painted quad on this road from `d0` to `d1` along it, `l0` to `l1` across (l0 left of l1).
func _strip_quad(b: MeshBatch, d0: float, d1: float, l0: float, l1: float) -> void:
	var at := func(d: float, l: float) -> Vector3:
		var x := track.transform_at(d, l)
		return x.origin + x.basis.y * LINE_UP * 1.5
	b.quad([at.call(d0, l0), at.call(d0, l1), at.call(d1, l1), at.call(d1, l0)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## The paved edge on `side`: the road's own edge, or past its apron (and the curb before it).
func _paved(i: int, side: float) -> Vector3:
	var apron: float = track.apron(i, side)
	return _edge(i, side) if apron <= 0.0 else track.paved_edge(i, side)


## A point `out` past the road's edge across the cross-section (TrackData.cross_point), `up` over it.
func _cross(i: int, side: float, out: float, up := 0.0) -> Vector3:
	return track.cross_point(i, side, out) + track.ups[i] * up


## The apron (D202): paved road past the edge and its curb, at its own slope.
func _apron(b: MeshBatch, i: int, j: int, side: float) -> void:
	var c := Color(0.82, 0.82, 0.82)
	var from_i := CURB_WIDTH if (track.curb_l if side > 0.0 else track.curb_r)[i] else 0.0
	var from_j := CURB_WIDTH if (track.curb_l if side > 0.0 else track.curb_r)[j] else 0.0
	var to_i: float = from_i + track.apron(i, side)
	var to_j: float = from_j + track.apron(j, side)
	var q := [_cross(i, side, from_i), _cross(i, side, to_i), _cross(j, side, to_j), _cross(j, side, from_j)]
	b.quad(q if side < 0.0 else [q[1], q[0], q[3], q[2]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], c)


## Edge lines and dashed lane lines (TrackFormat.LINES: none, edges, lanes, all).
func _lines(b: MeshBatch, i: int, j: int) -> void:
	var style := int(track.lines[i])
	if style == 1 or style == 3:
		for side: float in [1.0, -1.0]:
			var outer := -LINE_INSET
			var inner := -LINE_INSET - LINE_WIDTH
			var q := [_edge(i, side, inner, LINE_UP), _edge(i, side, outer, LINE_UP), _edge(j, side, outer, LINE_UP), _edge(j, side, inner, LINE_UP)]
			b.quad(q if side < 0.0 else [q[1], q[0], q[3], q[2]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var lanes := int(track.lanes[i])
	if (style == 2 or style == 3) and lanes > 1:
		var d := track.distances[i]
		if fmod(d, DASH_ON + DASH_OFF) > DASH_ON:
			return
		for lane in range(1, lanes):
			var at := func(k: int) -> float: return lerpf(-track.half_r[k], track.half_l[k], float(lane) / lanes)
			var pi := track.samples[i] + track.ups[i] * LINE_UP
			var pj := track.samples[j] + track.ups[j] * LINE_UP
			var w := LINE_WIDTH / 2.0
			b.quad([pi + track.lefts[i] * (at.call(i) + w), pi + track.lefts[i] * (at.call(i) - w), pj + track.lefts[j] * (at.call(j) - w), pj + track.lefts[j] * (at.call(j) + w)],
				[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## The curb's profile from the road's edge out, then its outer face down to the ground.
func _curb(b: MeshBatch, i: int, j: int, side: float) -> void:
	var v0 := track.distances[i] / 3.0
	var v1 := (track.distances[j] if j > 0 else track.length) / 3.0
	for p in 2:
		var a: Array = CURB_PROFILE[p]
		var c: Array = CURB_PROFILE[p + 1]
		var ai: Vector3 = _edge(i, side, a[0]) + Vector3.UP * a[1]
		var bi: Vector3 = _edge(i, side, c[0]) + Vector3.UP * c[1]
		var aj: Vector3 = _edge(j, side, a[0]) + Vector3.UP * a[1]
		var bj: Vector3 = _edge(j, side, c[0]) + Vector3.UP * c[1]
		var q := [ai, bi, bj, aj] if side < 0.0 else [bi, ai, aj, bj]
		b.quad(q, [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)])
	var top_i := _edge(i, side, CURB_WIDTH) + Vector3.UP * CURB_HEIGHT * 0.6
	var top_j := _edge(j, side, CURB_WIDTH) + Vector3.UP * CURB_HEIGHT * 0.6
	var low_i := Vector3(top_i.x, _low(i), top_i.z)
	var low_j := Vector3(top_j.x, _low(j), top_j.z)
	var face := [low_i, top_i, top_j, low_j] if side > 0.0 else [top_i, low_i, low_j, top_j]
	b.quad(face, [Vector2(0, v0), Vector2(0, v0), Vector2(0, v1), Vector2(0, v1)])


## How low a piece's outer face goes: to flat ground, or a little into the terrain.
func _low(i: int) -> float:
	return _ground_y if terrain == null else track.samples[i].y - SKIRT


## Run-off from the curb (or past the apron) out to its width, which an apron moves out.
func _runoff(b: MeshBatch, i: int, j: int, side: float) -> void:
	var apron_i: float = track.apron(i, side)
	var apron_j: float = track.apron(j, side)
	var start_i := (CURB_WIDTH if (track.curb_l if side > 0.0 else track.curb_r)[i] else 0.0) + apron_i
	var start_j := (CURB_WIDTH if (track.curb_l if side > 0.0 else track.curb_r)[j] else 0.0) + apron_j
	var end_i: float = (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[i] + apron_i
	var end_j: float = (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[j] + apron_j
	# On flat ground, a little over it (the same height flickered through it), still under the road.
	var drop := Vector3.UP * (_ground_y + RUNOFF_OVER_GROUND if terrain == null else -0.03)
	var q := [_cross(i, side, start_i) + drop, _cross(i, side, end_i) + drop, _cross(j, side, end_j) + drop, _cross(j, side, start_j) + drop]
	b.quad(q if side < 0.0 else [q[1], q[0], q[3], q[2]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## A deck under the road where it stands on supports, and a concrete parapet each side.
func _deck(b: MeshBatch, i: int, j: int) -> void:
	for side: float in [1.0, -1.0]:
		if _gapped(i, side) or _gapped(j, side):
			continue
		var oi := _edge(i, side, PARAPET[1])
		var oj := _edge(j, side, PARAPET[1])
		var ii := _edge(i, side)
		var ij := _edge(j, side)
		var down := Vector3.DOWN * DECK
		var face := [oi + down, oi, oj, oj + down] if side > 0.0 else [oi, oi + down, oj + down, oj]
		b.quad(face, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		var top := [ii, oi, oj, ij] if side < 0.0 else [oi, ii, ij, oj]
		b.quad(top, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var li := _edge(i, 1.0, PARAPET[1]) + Vector3.DOWN * DECK
	var ri := _edge(i, -1.0, PARAPET[1]) + Vector3.DOWN * DECK
	var lj := _edge(j, 1.0, PARAPET[1]) + Vector3.DOWN * DECK
	var rj := _edge(j, -1.0, PARAPET[1]) + Vector3.DOWN * DECK
	b.quad([li, lj, rj, ri], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## Barrier runs, per side and type: auto ones are tyre walls on the outside of tight corners
## where the track isn't close by; lifted road gets concrete parapets. Runs take in the next
## segment's first sample, so pieces built apart still meet, and where a run carries on into
## another piece its end runs on into that one's (D218).
func _barriers(out: Dictionary, first: int, end: int) -> void:
	for side: float in [1.0, -1.0]:
		var barrier := func(k: int) -> int: return _barrier_at(k, side)
		var parapet := func(k: int) -> int: return 4 if track.lifted[k] and not _gapped(k, side) else 0
		var u := 0.0
		for run: Dictionary in _runs(first, end, barrier, func(k: int) -> Vector3: return _barrier_point(k, side)):
			u = _wall(out, run.path, run.kind, u, [], run.start and _runs_on(first, -1, barrier, run.kind), run.end and _runs_on(end, 1, barrier, run.kind))
		for run: Dictionary in _runs(first, end, parapet, func(k: int) -> Vector3: return _edge(k, side, PARAPET[1] / 2.0)):
			_wall(out, run.path, 4, 0.0, PARAPET, run.start and _runs_on(first, -1, parapet, 4), run.end and _runs_on(end, 1, parapet, 4))


## The runs of wall over samples [first, end], `kind_at` a sample's kind (0: none) and `point_at`
## where it stands: [{kind, path, start, end}], `start` and `end` true where the piece's range
## stops it rather than the wall ending. Round a whole closed track, the run into its first sample
## and the run from it are one.
func _runs(first: int, end: int, kind_at: Callable, point_at: Callable) -> Array:
	var n := track.samples.size()
	var runs := []
	var run := {}
	for s in range(end - first + 1):
		var k := (first + s) % n
		var kind: int = kind_at.call(k)
		if not run.is_empty() and kind != run.kind:
			runs.append(run)
			run = {}
		if kind > 0:
			if run.is_empty():
				run = { "kind": kind, "path": PackedVector3Array(), "start": s == 0, "end": false }
			run.path.append(point_at.call(k))
	if not run.is_empty():
		run.end = true
		runs.append(run)
	if track.closed and end - first >= n and runs.size() > 1 and runs[0].start and runs[-1].end and runs[0].kind == runs[-1].kind:
		var last: Dictionary = runs.pop_back()
		last.path.append_array(runs[0].path.slice(1))
		last.end = runs[0].end
		runs[0] = last
	return runs


## Whether a wall of `kind` carries on past sample `k`, a piece's end (`dir` -1: before it, +1:
## after it), into another piece: on a closed track if the sample there has it too; on an open
## one, the same inside it, and past its ends only if they join another strip (`joined_ends`).
func _runs_on(k: int, dir: int, kind_at: Callable, kind: int) -> bool:
	var n := track.samples.size()
	var next := k + dir
	if track.closed:
		next = posmod(next, n)
	elif next < 0 or next >= n:
		return joined_ends
	return int(kind_at.call(next)) == kind


func _wall(out: Dictionary, path: PackedVector3Array, kind: int, u: float, size: Array = [], run_on_start := false, run_on_end := false) -> float:
	if kind <= 0 or path.size() < 2:
		return u
	var dims: Array = size if not size.is_empty() else BARRIER_SIZE[kind]
	if kind == TrackFormat.BARRIER_SAFER:
		_catch_fence(out, path, dims[0], u, run_on_start, run_on_end)
	return _batch(out, "barrier:%d" % kind).wall(path, dims[0], dims[1], u, 4.0, run_on_start, run_on_end)


## The chain-link fence on a SAFER wall's top, with posts.
func _catch_fence(out: Dictionary, path: PackedVector3Array, on: float, u: float, run_on_start: bool, run_on_end: bool) -> void:
	var top := PackedVector3Array()
	for p in path:
		top.append(p + Vector3.UP * on)
	_batch(out, "catch_fence").wall(top, CATCH_FENCE[0], CATCH_FENCE[1], u, 4.0, run_on_start, run_on_end)
	var posts := _batch(out, "barrier:posts")
	var along := 0.0
	for k in top.size() - 1:
		var step := top[k].distance_to(top[k + 1])
		while along <= step:
			var p := top[k].lerp(top[k + 1], along / maxf(step, 0.001))
			posts.box(p + Vector3.UP * CATCH_FENCE[0] / 2.0, Basis(), Vector3(POST, CATCH_FENCE[0], POST))
			along += POST_M
		along -= step


## The barrier type on `side` at sample `k` (0: none).
func _barrier_at(k: int, side: float) -> int:
	if track.lifted[k] or _gapped(k, side):
		return 0
	var kind := int((track.barrier_l if side > 0.0 else track.barrier_r)[k])
	if kind != TrackFormat.BARRIER_AUTO:
		return kind
	var kappa := track.curvature[k]
	# Outside of the corner: turning left (κ > 0), the right side.
	if absf(kappa) <= BARRIER_CURVATURE or signf(kappa) == side:
		return 0
	var p := _barrier_point(k, side)
	var reach := maxf(track.half_l[k], track.half_r[k]) + 6.0
	return TrackFormat.BARRIER_TYRES if not track.is_near_centreline(p, reach) else 0


## Where a barrier stands: past the run-off (and an apron).
func _barrier_point(k: int, side: float) -> Vector3:
	var runoff: float = track.runoff_l_m[k] if side > 0.0 else track.runoff_r_m[k]
	var p := track.cross_point(k, side, runoff + track.apron(k, side))
	if terrain:
		p.y = terrain.edge_ground(p)
	return p


## Pillars every PILLAR_EVERY_M under lifted road, a little in from each edge, down to the ground.
func _pillars(out: Dictionary, first: int, end: int) -> void:
	var n := track.samples.size()
	var next := -1.0
	for i in range(first, end):
		var k := i % n
		if not track.lifted[k]:
			next = -1.0
			continue
		var d := track.distances[k]
		if next >= 0.0 and d < next:
			continue
		next = d + PILLAR_EVERY_M
		for side: float in [1.0, -1.0]:
			var top := _edge(k, side, -0.5) + Vector3.DOWN * DECK
			if _hw and _hw.highway.road_below(top):
				continue
			var ground := terrain.height_at(top.x, top.z) - 0.5 if terrain else _ground_y
			var h := top.y - ground
			if h > 0.5:
				_batch(out, "bridge").box(Vector3(top.x, ground + h / 2.0, top.z), Basis(), Vector3(PILLAR, h, PILLAR))


## Flat ground: a wall round the whole site (as the first tracks had). Terrain: a wall just
## inside its edge, following the ground.
func _perimeter() -> MeshBatch:
	var b := MeshBatch.new()
	if terrain == null:
		var box := AABB(track.samples[0], Vector3.ZERO)
		for p in track.samples:
			box = box.expand(p)
		box = box.grow(SITE_WALL_M)
		var corners := [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z)]
		b.wall(PackedVector3Array(corners + [corners[0]]), 1.6, 1.0) # one closed loop: no ends
		return b
	var a := terrain.area().grow(-2.0)
	var corners := [a.position, Vector2(a.end.x, a.position.y), a.end, Vector2(a.position.x, a.end.y)]
	var path := PackedVector3Array()
	for i in 4:
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[(i + 1) % 4]
		var steps := maxi(1, int(from.distance_to(to) / 16.0))
		for s in range(0 if i == 0 else 1, steps + 1):
			var p := from.lerp(to, float(s) / steps)
			path.append(Vector3(p.x, terrain.height_at(p.x, p.y) - 1.0, p.y))
	b.wall(path, 4.0, 1.0)
	return b


# --- nodes ----------------------------------------------------------------------------------


const NAMES := { "catch_fence": "CatchFences", "lines": "Lines", "lines_dry": "LinesSheltered", "lines_yellow": "LinesYellow", "curbs": "Curbs", "bridge": "Bridge", "lamps": "Lamps", "lamp_heads": "LampHeads",
	"tunnel": "Tunnel", "tunnel_lights": "TunnelLights", "gantry": "Gantries", "sign_board": "SignBoards", "cushion": "Cushions",
	"portal": "Portals", "portal_dark": "PortalShells", "portal_floor": "PortalFloors" }


## The batches' meshes and collision faces, made ahead (on a worker: no nodes, no shapes) for
## add_built(): {key: {mesh, faces}}. Headless, the meshes wait for add_built (MeshBatch.threaded).
func prebuild(batches: Dictionary) -> Dictionary:
	var out := {}
	for key: String in batches:
		var b: MeshBatch = batches[key]
		if not b.is_empty():
			out[key] = { "mesh": b.mesh() if visual and MeshBatch.threaded() else null, "faces": b.faces() }
	return out


## Nodes for batches made ahead by prebuild() (on the main thread).
func add_built(parent: Node3D, batches: Dictionary, built: Dictionary) -> void:
	_add_batches(parent, batches, built)


func _add_batches(parent: Node3D, batches: Dictionary, built := {}) -> void:
	for key: String in batches:
		var b: MeshBatch = batches[key]
		if b.is_empty():
			continue
		var parts := key.split(":")
		var node_name := String(NAMES.get(key, key))
		var material: Material
		var surface := -1
		match parts[0]:
			"road", "road_dry":
				surface = int(parts[1])
				node_name = "Road" if surface == VehicleSim.SURFACE_ASPHALT else "Road_" + TrackFormat.SURFACES[surface].capitalize()
				material = WorldMaterials.surface(surface)
				if parts[0] == "road_dry":
					node_name += "Sheltered"
					material = WorldMaterials.sheltered(material)
			"catch_fence":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.see_through("catch_fence", RetroTextures.chain_link(), Vector2(8.0, 8.0), Color(0.72, 0.74, 0.76))
			"lines":
				material = WorldMaterials.paint("paint_white", Color(0.9, 0.9, 0.88))
			"lines_dry":
				material = WorldMaterials.sheltered(WorldMaterials.paint("paint_white", Color(0.9, 0.9, 0.88)))
			"lines_yellow":
				material = WorldMaterials.paint("paint_yellow", Color(0.93, 0.72, 0.12))
			"curbs":
				surface = VehicleSim.SURFACE_CURB
				material = WorldMaterials.surface(surface)
			"runoff":
				surface = int(parts[1])
				node_name = "Runoff_" + TrackFormat.SURFACES[surface].capitalize()
				material = WorldMaterials.surface(surface)
			"barrier":
				surface = VehicleSim.SURFACE_CONCRETE
				match parts[1]:
					"perimeter":
						node_name = "Perimeter"
						material = WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)
					"2":
						node_name = "Barriers"
						material = WorldMaterials.get_material("tyre_wall", RetroTextures.tyre_wall(), 0.9, 0.1)
					"3":
						node_name = "Armco"
						material = WorldMaterials.get_material("armco", RetroTextures.concrete(), 0.35, 0.6, false, Vector2.ONE, Color(0.78, 0.8, 0.84))
					"4":
						node_name = "ConcreteWalls"
						material = WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)
					"5":
						node_name = "Fences"
						material = WorldMaterials.get_material("fence", RetroTextures.concrete(), 0.6, 0.3, false, Vector2.ONE, Color(0.45, 0.5, 0.45))
					"7":
						node_name = "SaferWalls"
						material = WorldMaterials.get_material("safer_wall", RetroTextures.concrete(), 0.6, 0.3, false, Vector2.ONE, Color(0.97, 0.97, 0.95))
					"posts":
						node_name = "FencePosts"
						material = WorldMaterials.get_material("gantry_steel", null, 0.45, 0.6, false, Vector2.ONE, Color(0.6, 0.62, 0.66))
			"bridge", "tunnel", "portal":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("concrete_world_uv", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0)
			"median":
				surface = VehicleSim.SURFACE_CONCRETE
				node_name = "Median"
				material = WorldMaterials.get_material("armco", RetroTextures.concrete(), 0.35, 0.6, false, Vector2.ONE, Color(0.78, 0.8, 0.84)) if parts[1] == "armco" \
					else WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)
			"lamps":
				material = WorldMaterials.get_material("lamp_pole", null, 0.5, 0.5, false, Vector2.ONE, Color(0.55, 0.57, 0.6))
			"lamp_heads":
				material = WorldMaterials.glowing("lamp_head", Color(1.0, 0.86, 0.6), 1.6, true)
			"tunnel_lights":
				material = WorldMaterials.glowing("tunnel_light", Color(1.0, 0.92, 0.75), 2.0)
			"gantry":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("gantry_steel", null, 0.45, 0.6, false, Vector2.ONE, Color(0.6, 0.62, 0.66))
			"sign_board":
				material = WorldMaterials.get_material("sign_green", null, 0.6, 0.2, false, Vector2.ONE, Color(0.06, 0.36, 0.2))
			"cushion":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("cushion", RetroTextures.checker(), 0.6, 0.2, false, Vector2(1, 2), Color(1.0, 0.82, 0.1))
			"portal_dark":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("portal_dark", null, 1.0, 0.0, false, Vector2.ONE, Color(0.03, 0.03, 0.035))
			"portal_floor":
				surface = VehicleSim.SURFACE_ASPHALT
				material = WorldMaterials.sheltered(WorldMaterials.surface(VehicleSim.SURFACE_ASPHALT))
			"prop":
				# Prop parts by material ("prop:<material>:<surface>"): the endless road's signs.
				node_name = "Props_" + parts[1].capitalize()
				material = PropLibrary.material(parts[1])
				surface = int(parts[2]) if parts.size() > 2 else -1
		_add_piece(parent, node_name, b, material, surface, built.get(key, {}))


## A piece: its mesh (unless visuals are off) and, if it's solid, a static body with its surface.
## `built`: its mesh and faces made ahead ({} : made here).
func _add_piece(parent: Node3D, node_name: String, b: MeshBatch, material: Material, surface: int, built := {}) -> void:
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = built.mesh if built.get("mesh") != null else b.mesh()
		mi.material_override = material
		parent.add_child(mi)
	if surface < 0:
		return
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var cs := CollisionShape3D.new()
	if built.has("faces"):
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(built.faces)
		cs.shape = shape
	else:
		cs.shape = b.shape()
	body.add_child(cs)
	parent.add_child(body)
