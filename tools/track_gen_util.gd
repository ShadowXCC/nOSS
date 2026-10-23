extends RefCounted
## Helpers the real-world track generators share (tools/make_eifel_gp.gd, D200;
## tools/make_piedmont_speedway.gd and make_piedmont_road_course.gd, D206): a map's line resampled
## and smoothed, control points picked by the corners, a DEM laid on terrain, places along a road
## found and kept clear, and grandstands set behind it.


## `raw` (closed) resampled every ~`step_m` m, evenly: {line, step}.
static func resample(raw: PackedVector2Array, step_m: float) -> Dictionary:
	var m := raw.size()
	var total := 0.0
	for i in m:
		total += raw[i].distance_to(raw[(i + 1) % m])
	var n := int(total / step_m)
	var step := total / n
	var even := PackedVector2Array()
	var k := 0
	var acc := 0.0
	for i in n:
		var s := i * step
		var seg := raw[k].distance_to(raw[(k + 1) % m])
		while acc + seg < s:
			acc += seg
			k += 1
			seg = raw[k].distance_to(raw[(k + 1) % m])
		even.append(raw[k].lerp(raw[(k + 1) % m], (s - acc) / seg))
	return { "line": even, "step": step }


## `line` (closed) moved `by` m to its right (driving along it), every point along its normal.
static func offset(line: PackedVector2Array, by: float) -> PackedVector2Array:
	var n := line.size()
	var out := PackedVector2Array()
	for i in n:
		var fwd := (line[(i + 1) % n] - line[(i - 1 + n) % n]).normalized()
		out.append(line[i] + Vector2(-fwd.y, fwd.x) * by) # x east, z south: right of (x, z) is (-z, x)
	return out


## The furthest `t`'s centreline gets from `line` (x, z), m.
static func off_line(t: TrackData, line: PackedVector2Array) -> float:
	var worst := 0.0
	for p in line:
		var best := INF
		for j in t.samples_near(Vector3(p.x, 0, p.y), 20.0):
			var a := Vector2(t.samples[j].x, t.samples[j].z)
			var b := Vector2(t.samples[(j + 1) % t.samples.size()].x, t.samples[(j + 1) % t.samples.size()].z)
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
		worst = maxf(worst, best)
	return worst


## `line` (closed, `step` apart) smoothed by a Gaussian of `sigma` m.
static func gauss(line: PackedVector2Array, sigma: float, step: float) -> PackedVector2Array:
	var n := line.size()
	var reach := ceili(3.0 * sigma / step)
	var weights := PackedFloat32Array()
	for o in range(-reach, reach + 1):
		weights.append(exp(-0.5 * pow(o * step / sigma, 2.0)))
	var out := PackedVector2Array()
	for i in n:
		var sum := Vector2.ZERO
		var wsum := 0.0
		for o in range(-reach, reach + 1):
			sum += line[posmod(i + o, n)] * weights[o + reach]
			wsum += weights[o + reach]
		out.append(sum / wsum)
	return out


## Control points along `line` (closed, even steps): `share` of the tightest radius in the next
## `spacing_max` m apart, within `spacing_min` and `spacing_max`.
static func pick(line: PackedVector2Array, spacing_min: float, spacing_max: float, share: float) -> PackedVector2Array:
	var n := line.size()
	var step := line[0].distance_to(line[1])
	var radius := PackedFloat32Array()
	for i in n:
		radius.append(radius(line[posmod(i - 2, n)], line[i], line[(i + 2) % n]))
	var look := ceili(spacing_max / step)
	var out := PackedVector2Array()
	var i := 0
	while i < n:
		out.append(Vector2(snappedf(line[i].x, 0.01), snappedf(line[i].y, 0.01)))
		var r := INF
		for o in look:
			r = minf(r, radius[(i + o) % n])
		i += maxi(1, roundi(clampf(r * share, spacing_min, spacing_max) / step))
	if out[out.size() - 1].distance_to(out[0]) < spacing_min:
		out.remove_at(out.size() - 1)
	return out


## The radius of the circle through a, b, c (INF if they're in line).
static func radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var cross := (b - a).cross(c - b)
	if absf(cross) < 0.000001:
		return INF
	return a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * absf(cross))


## The ground: terrain over `box` plus `margin`, the DEM (smoothed over 3 by 3 cells) on it with
## its lowest point `below` m above 0, bilinear between its cells. Returns that lowering (m).
static func terrain(d: TrackDraft, dem: Dictionary, box: Rect2, margin: float, below: float) -> float:
	var dem_size := Vector2i(int(dem.size[0]), int(dem.size[1]))
	var raw: Array = dem.heights
	var smooth := PackedFloat32Array()
	smooth.resize(raw.size())
	var lowest := INF
	for z in dem_size.y:
		for x in dem_size.x:
			var sum := 0.0
			var count := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var cx := x + dx
					var cz := z + dz
					if cx >= 0 and cz >= 0 and cx < dem_size.x and cz < dem_size.y:
						sum += float(raw[cz * dem_size.x + cx])
						count += 1
			smooth[z * dem_size.x + x] = sum / count
			lowest = minf(lowest, sum / count)
	var base := floorf(lowest) - below
	d.terrain = TerrainData.around(box, margin)
	var size: Vector2i = d.terrain.field.get_size()
	var origin: Vector2 = d.terrain.origin()
	var cell := float(dem.cell_m)
	var dem_origin := Vector2(dem.origin[0], dem.origin[1])
	var cols := PackedInt32Array()
	var fx := PackedFloat32Array()
	for x in size.x:
		var u := clampf((origin.x + x - dem_origin.x) / cell, 0.0, dem_size.x - 1.001)
		cols.append(int(u))
		fx.append(u - int(u))
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	for z in size.y:
		var v := clampf((origin.y + z - dem_origin.y) / cell, 0.0, dem_size.y - 1.001)
		var row := int(v) * dem_size.x
		var fz := v - int(v)
		for x in size.x:
			var i := row + cols[x]
			var top := lerpf(smooth[i], smooth[i + 1], fx[x])
			var bottom := lerpf(smooth[i + dem_size.x], smooth[i + dem_size.x + 1], fx[x])
			heights[z * size.x + x] = snappedf(lerpf(top, bottom, fz) - base, TerrainData.HEIGHT_STEP)
	d.terrain.field.set_base(heights)
	return base


## The control points from `span.x` to `span.y` m along (wrapping).
static func points_in(d: TrackDraft, t: TrackData, span: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in d.points().size():
		if within(t, point_m(t, i), span):
			out.append(i)
	return out


static func point_m(t: TrackData, i: int) -> float:
	return t.distances[t.seg_first[i]]


## The nearest point on the road to `p` (x, z), from the ground's height there (projection
## weighs height: from 0 a lower part of the road could win).
static func project(d: TrackDraft, t: TrackData, p: Vector2) -> Dictionary:
	return t.project(Vector3(p.x, d.terrain.base_at(p.x, p.y), p.y))


static func within(t: TrackData, m: float, span: Vector2) -> bool:
	return fposmod(m - span.x, t.length) <= fposmod(span.y - span.x, t.length)


## The tightest radius over control segment `seg` (its samples and a few either side).
static func segment_radius(t: TrackData, seg: int) -> float:
	var r := t.segment_samples(seg)
	var n := t.samples.size()
	var k := 0.0
	for s in range(r.x - 5, r.y + 6):
		k = maxf(k, absf(t.curvature[posmod(s, n)]))
	return 1.0 / maxf(k, 0.000001)


## True if a part of the road more than `same_part` m along from sample `k` is within `r` of `p`.
static func near_other(t: TrackData, k: int, p: Vector3, r: float, same_part := 80.0) -> bool:
	for j in t.samples_near(p, r):
		var along := absf(t.distances[j] - t.distances[k])
		if minf(along, t.length - along) > same_part:
			return true
	return false


## Sets {point: {key: value}} as one change per key.
static func apply(d: TrackDraft, changes: Dictionary) -> void:
	var by_key := {}
	for i: int in changes:
		for key: String in changes[i]:
			var value: Variant = changes[i][key]
			var slot := "%s=%s" % [key, var_to_str(value)]
			if not by_key.has(slot):
				by_key[slot] = [key, value, []]
			(by_key[slot][2] as Array).append(i)
	var slots := by_key.keys()
	slots.sort()
	for slot: String in slots:
		d.set_attr(PackedInt32Array(by_key[slot][2]), by_key[slot][0], by_key[slot][1])


## A grandstand `length` long on `side` (+1 left) at `m`, `extra` m behind the barrier, facing the road,
## with a crowd at its foot; none if it would come near another part of the road or a prop.
static func stand(d: TrackDraft, t: TrackData, m: float, side: float, length: float, free: Callable, keep_long: Callable, extra := 6.0) -> void:
	var front := behind(t, m, side, extra)
	var x := t.transform_at(m)
	var fwd := Vector2(x.basis.z.x, x.basis.z.z).normalized()
	var away := Vector2(x.basis.x.x, x.basis.x.z).normalized() * side
	var k := t.index_at(m)
	for s in range(-int(length / 2.0), int(length / 2.0) + 1, 6):
		for depth: float in [0.0, 6.0, 13.0]:
			var p := front + fwd * s + away * depth
			if not free.call(p, 2.0) or near_other(t, k, Vector3(p.x, 0, p.y), 20.0) or t.is_near_centreline(Vector3(p.x, 0, p.y), 14.0):
				print("  no grandstand at %.0f m: no room" % m)
				return
	keep_long.call(front + away * 4.0, fwd, length, 10.0) # the crowd's ground in front too
	var yaw := snappedf(rad_to_deg(atan2(-away.y, away.x)), 0.1)
	d.add_prop({ "prop": "grandstand", "p": [snappedf(front.x, 0.01), 0.0, snappedf(front.y, 0.01)], "yaw_deg": yaw, "scale": 1.0,
		"size": [13.0, 9.9, length], "ground": true })
	var crowd := front - away * 2.0
	d.add_prop({ "prop": "crowd", "p": [snappedf(crowd.x, 0.01), 0.0, snappedf(crowd.y, 0.01)], "yaw_deg": yaw_along(fwd), "scale": 1.0,
		"size": [0.0, 0.0, length], "ground": true })


## The spot `extra` m behind the barrier (the run-off's end) on `side` (+1 left) at `m`.
static func behind(t: TrackData, m: float, side: float, extra: float) -> Vector2:
	var k := t.index_at(m)
	var reach: float = (t.half_l[k] + t.runoff_l_m[k]) if side > 0.0 else (t.half_r[k] + t.runoff_r_m[k])
	var x := t.transform_at(m, side * (reach + extra))
	return Vector2(x.origin.x, x.origin.z)


static func fwd_at(t: TrackData, m: float) -> Vector2:
	var x := t.transform_at(m)
	return Vector2(x.basis.z.x, x.basis.z.z).normalized()


## The yaw (degrees) that turns a prop's +z along `fwd` (x, z).
static func yaw_along(fwd: Vector2) -> float:
	return snappedf(rad_to_deg(atan2(fwd.x, fwd.y)), 0.1)
