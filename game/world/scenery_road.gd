class_name SceneryRoad
extends RefCounted
## Scenery roads (D212): a track's `roads`, the rest of its venue round the course (an oval's
## infield road course, a road course's unused banking). Each is an open road made as the main road
## is, from its own {name, points, defaults} (widths, banking, apron, curbs, run-off, barriers), and
## built and shaped into the ground as the main road is. Where one runs onto the main road, its
## pit lane or a scenery road before it, its edge stops at theirs, the cross-section tilted to
## meet it, so the two meet without a seam and never overlap; where it's wholly on them it's cut,
## so a road may cross another.
## Cars can drive them; nothing is timed there (a car on one is off the track).

## A scenery edge counts as on another road within this of its surface's height, m.
const ON_Y_M := 1.5
## Halvings to find where a cross-section crosses another road's edge.
const SEARCH_STEPS := 10
## A sample with both edges on another road, or this close past its edge, is cut; narrower than
## MIN_WIDTH_M once fitted, too.
const ON_SLACK_M := 0.3
const MIN_WIDTH_M := 0.1
## Pieces shorter than this are left out, m.
const MIN_PIECE_M := 4.0
## Sample arrays an open road's pieces are cut from.
const FLOATS := ["half_l", "half_r", "bank", "apron_l", "apron_r", "apron_l_bank", "apron_r_bank", "runoff_l_m", "runoff_r_m", "curvature"]
const BYTES := ["curbs", "curb_l", "curb_r", "surface", "runoff_l", "runoff_r", "barrier_l", "barrier_r", "lanes", "lines", "lifted"]


## The pieces of every road in `data` ("roads") round `main`, fitted to it, to `others` (its pit
## lane's strip) and to the roads before it.
static func build_all(main: TrackData, data: Array, others: Array[TrackData], ground: Callable) -> Array[TrackData]:
	var out: Array[TrackData] = []
	for k in data.size():
		var road: Dictionary = data[k]
		if (road.get("points", []) as Array).size() < 2:
			continue
		var against: Array[TrackData] = others.duplicate()
		against.append_array(out)
		out.append_array(build(main, road, k, against, ground))
	return out


## Road `road` (the `k`th) as pieces: made, fitted to `main` and `others`, cut where wholly on them.
static func build(main: TrackData, road: Dictionary, k: int, others: Array[TrackData], ground: Callable) -> Array[TrackData]:
	var t := TrackData.open_road(main, road, ground)
	t.id = "%s:road%d" % [main.id, k]
	t.display_name = String(road.get("name", "Road %d" % (k + 1)))
	var cut := PackedByteArray()
	cut.resize(t.samples.size())
	for other: TrackData in [main] + others:
		if other != null and other.samples.size() >= 2:
			_fit(t, other, cut)
	return _pieces(t, cut)


## Moves each of `t`'s edges that lies on `other` (within its paved edge, near its surface) out to
## that edge, without curb, apron, run-off or barrier on that side; trims a curb, apron, run-off
## or barrier that reaches onto it; marks in `cut` the samples wholly on it (or within ON_SLACK_M).
static func _fit(t: TrackData, other: TrackData, cut: PackedByteArray) -> void:
	var reach := 0.0 # the other road's widest paving, centreline to edge
	for k in other.samples.size():
		reach = maxf(reach, maxf(other.edge_at(other.distances[k], 1.0), other.edge_at(other.distances[k], -1.0)))
	reach += TrackData.SAMPLE_M + ON_SLACK_M
	for i in t.samples.size():
		if cut[i]:
			continue
		var edge_l := t.samples[i] + t.lefts[i] * t.half_l[i]
		var edge_r := t.samples[i] - t.lefts[i] * t.half_r[i]
		var on_l := _on(other, edge_l, reach)
		var on_r := _on(other, edge_r, reach)
		if (on_l or _on(other, edge_l, reach, ON_SLACK_M)) and (on_r or _on(other, edge_r, reach, ON_SLACK_M)):
			cut[i] = 1
			continue
		for side: float in [1.0, -1.0]:
			if not (on_l if side > 0.0 else on_r):
				_trim_beyond(t, i, side, other, reach)
		if not on_l and not on_r:
			continue
		var side := 1.0 if on_l else -1.0
		var outer := edge_r if on_l else edge_l
		var inner := edge_l if on_l else edge_r
		# Where the cross-section crosses the other road's edge, at that edge's height.
		var lo := 0.0
		var hi := 1.0
		for s in SEARCH_STEPS:
			var mid := (lo + hi) / 2.0
			if _on(other, outer.lerp(inner, mid), reach):
				hi = mid
			else:
				lo = mid
		var at := outer.lerp(inner, lo)
		var proj := other.project(at, _nearest(other, at, reach))
		var k := int(proj.index)
		at.y = other.paved_edge(k, signf(float(proj.lateral)) if float(proj.lateral) != 0.0 else 1.0).y
		var across := (at - outer) * side # toward the left
		var w := across.length()
		if w < MIN_WIDTH_M:
			cut[i] = 1
			continue
		var left := across / w
		t.samples[i] = (outer + at) / 2.0
		t.lefts[i] = left
		t.ups[i] = t.tangents[i].cross(left).normalized()
		t.half_l[i] = w / 2.0
		t.half_r[i] = w / 2.0
		t.bank[i] = asin(clampf(left.y, -1.0, 1.0))
		_clear_side(t, i, side)


## Past `t`'s edge on `side` at sample `i`: the curb and apron stop short of `other`, and the
## run-off and barrier go if they'd stand on it.
static func _trim_beyond(t: TrackData, i: int, side: float, other: TrackData, reach: float) -> void:
	var curb := TrackData.CURB_WIDTH if (t.curb_l if side > 0.0 else t.curb_r)[i] else 0.0
	var pave := curb + t.apron(i, side)
	if pave > 0.0 and _on(other, t.cross_point(i, side, pave), reach):
		var lo := 0.0
		var hi := pave
		for s in SEARCH_STEPS:
			var mid := (lo + hi) / 2.0
			if _on(other, t.cross_point(i, side, mid), reach):
				hi = mid
			else:
				lo = mid
		if lo < curb:
			_clear_side(t, i, side)
			return
		var aprons: PackedFloat32Array = t.apron_l if side > 0.0 else t.apron_r
		aprons[i] = lo - curb
		t.set("apron_l" if side > 0.0 else "apron_r", aprons)
		pave = lo
	var runoff: float = (t.runoff_l_m if side > 0.0 else t.runoff_r_m)[i]
	if _on(other, t.cross_point(i, side, pave + runoff), reach):
		for name: String in (["runoff_l_m", "barrier_l"] if side > 0.0 else ["runoff_r_m", "barrier_r"]):
			var a: Variant = t.get(name)
			a[i] = 0
			t.set(name, a)


## No curb, apron, run-off or barrier on `side` of sample `i`.
static func _clear_side(t: TrackData, i: int, side: float) -> void:
	for name: String in (["curb_l", "apron_l", "runoff_l_m", "barrier_l"] if side > 0.0 else ["curb_r", "apron_r", "runoff_r_m", "barrier_r"]):
		var a: Variant = t.get(name)
		if i < (a as Variant).size():
			a[i] = 0
			t.set(name, a)


## True if `p` is on `other`'s paving (its road, curbs and aprons) near its surface. `reach`: the
## other's widest paving plus a sample.
static func _on(other: TrackData, p: Vector3, reach: float, slack := 0.0) -> bool:
	var hint := _nearest(other, p, reach)
	if hint < 0:
		return false
	var proj := other.project(p, hint)
	var lateral := float(proj.lateral)
	if absf(lateral) > other.edge_at(float(proj.distance), lateral) + slack:
		return false
	if not other.closed and (float(proj.distance) <= 0.0 or float(proj.distance) >= other.length):
		return false # past an open strip's ends
	# The other's surface there: across its banking, then its curb and apron.
	var k := int(proj.index)
	var side := 1.0 if lateral >= 0.0 else -1.0
	var half: float = other.half_l[k] if side > 0.0 else other.half_r[k]
	var surface_y := (proj.point as Vector3).y + other.lefts[k].y * lateral if absf(lateral) <= half \
		else other.cross_point(k, side, absf(lateral) - half).y
	return absf(p.y - surface_y) < ON_Y_M


## `other`'s sample nearest `p` within `reach` (XZ), or -1.
static func _nearest(other: TrackData, p: Vector3, reach: float) -> int:
	var best := -1
	var best_d2 := INF
	for k in other.samples_near(p, reach):
		var d2 := Vector2(other.samples[k].x - p.x, other.samples[k].z - p.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = k
	return best


## The runs of `t`'s samples not `cut`, each an open road of its own.
static func _pieces(t: TrackData, cut: PackedByteArray) -> Array[TrackData]:
	var out: Array[TrackData] = []
	var n := t.samples.size()
	var i := 0
	while i < n:
		if cut[i]:
			i += 1
			continue
		var first := i
		while i < n and not cut[i]:
			i += 1
		if i - first >= 2 and t.distances[i - 1] - t.distances[first] >= MIN_PIECE_M:
			var piece := _slice(t, first, i)
			piece.id = "%s:%d" % [t.id, out.size()]
			out.append(piece)
	return out


## Samples [from, to) of open road `t` as an open road of their own.
static func _slice(t: TrackData, from: int, to: int) -> TrackData:
	var p := TrackData.new()
	p.raw = t.raw
	p.display_name = t.display_name
	p.type = t.type
	p.kind = t.kind
	p.closed = false
	p.width = t.width
	p.samples = t.samples.slice(from, to)
	p.tangents = t.tangents.slice(from, to)
	p.lefts = t.lefts.slice(from, to)
	p.ups = t.ups.slice(from, to)
	for name: String in FLOATS + BYTES:
		p.set(name, (t.get(name) as Variant).slice(from, to))
	p.sample_seg = t.sample_seg.slice(from, to)
	var total := 0.0
	for i in p.samples.size():
		p.distances.append(total)
		if i + 1 < p.samples.size():
			total += p.samples[i].distance_to(p.samples[i + 1])
	p.length = total
	p.seg_first = PackedInt32Array([0])
	p.kill_y = t.kill_y
	return p
