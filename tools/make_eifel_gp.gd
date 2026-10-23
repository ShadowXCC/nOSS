extends Node
## Writes content/tracks/eifel_gp/: the Eifel GP (D200), the first real-world track: the
## Nürburgring GP circuit's layout and hills under a name of its own, made with the track
## editor's own commands (TrackDraft) so the editor can open and change it.
##
## tools/data/eifel_gp.json (tools/fetch_eifel_gp.py) holds the real centreline (OpenStreetMap,
## ODbL) and the ground round it (EU-DEM, 25 m). The centreline is smoothed of mapping jitter
## and its points go closer in the corners; the ground is the DEM smoothed (it has the
## treetops) and lowered by its lowest point less BASE_BELOW_M (terrain heights stop at 555 m).
##
## 5.1 km clockwise, 13 m wide (16 m down the start straight), about 55 m of climb (seen with
## north up, -z north): the start straight runs south-west past the pits to the first-corner
## complex (paved run-off), then down to the low hairpin, up through the fast S, the long rights,
## the chicane and the last corner. Gravel outside the slow corners; armco where the road runs
## straight and clear, tyre walls through the corners. Round it: the pits, grandstands on the
## straight, at the first corner, the hairpin and the chicane, marshal posts, billboards and
## the Eifel forest.
##   tools/godot.sh --headless res://tools/make_eifel_gp.tscn [-- --out=<folder>]

const OUT := "res://content/tracks/eifel_gp"
const DATA := "res://tools/data/eifel_gp.json"
const CREATED := "2026-10-22"
const LICENSE := "ODbL-1.0"
const ATTRIBUTIONS := ["Layout © OpenStreetMap contributors (ODbL 1.0)",
	"Ground: EU-DEM v1.1, produced using Copernicus data and information funded by the European Union"]
const SOURCE := "OpenStreetMap relation 38567, EU-DEM v1.1"
## The centreline's resampling step and the smoothing (Gaussian sigma) that takes out jitter, m.
const RESAMPLE_M := 5.0
const SMOOTH_M := 8.0
## Corners tighter than TIGHT_R_M (the first corner) are smoothed by TIGHT_SMOOTH_M within
## TIGHT_REACH_M, so the AI's line round them stays gentler than the checks' 8 m.
const TIGHT_R_M := 16.0
const TIGHT_SMOOTH_M := 14.0
const TIGHT_REACH_M := 40.0
## Control points: RADIUS_SHARE of the tightest radius just ahead apart, within these (m).
const SPACING_MIN_M := 8.0
const SPACING_MAX_M := 40.0
const RADIUS_SHARE := 0.35
## The ground: this far round the road, and its lowest point this far above the terrain's 0.
const TERRAIN_MARGIN_M := 200.0
const BASE_BELOW_M := 5.0
const HALF_WIDTH_M := 6.5
const STRAIGHT_HALF_WIDTH_M := 8.0
## Places on the real layout (x, z): the start straight's ends, the start line, the first-corner
## complex (from 50 m before T1 to T4), the first corner, the hairpin and the chicane.
const STRAIGHT_FROM := Vector2(539, -668)
const STRAIGHT_TO := Vector2(-44, -108)
const START := Vector2(200, -322)
const ARENA_FROM := Vector2(-8, -143)
const ARENA_TO := Vector2(-151, -125)
const T1 := Vector2(-77, -114)
const HAIRPIN := Vector2(-547, 757)
const CHICANE := Vector2(308, -662)
## Run-off: gravel outside corners tighter than GRAVEL_R_M (paved in the first-corner complex),
## never closer than RUNOFF_CLEAR_M to another part of the road.
const GRAVEL_R_M := 60.0
const GRAVEL_M := 30.0
const PAVED_M := 25.0
const RUNOFF_CLEAR_M := 8.0
## Armco where the road is straighter than ARMCO_R_M and its line keeps ARMCO_CLEAR_M from any
## other part of the road; the rest stays auto (tyre walls outside the corners).
const ARMCO_R_M := 260.0
const ARMCO_CLEAR_M := 15.0
## Along-track distance inside which road counts as the same part (m).
const SAME_PART_M := 80.0
const PIT_LANE_HALF_M := 6.0
const TREES := 3000
const TREE_ROAD_M := 48.0
const MARSHAL_EVERY_M := 400.0

var opts := { "out": OUT }


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_write.call_deferred()


func _write() -> void:
	var t0 := Time.get_ticks_msec()
	var d := build()
	var t := d.track()
	var found := TrackValidator.check(d)
	for p: Dictionary in found:
		print("  %s: %s" % [p.level, p.text])
	if not TrackValidator.errors(found).is_empty():
		print("FAIL: validation errors")
		get_tree().quit(1)
		return
	var out := String(opts.out)
	var err := TrackWriter.write_folder(out, d.manifest_info().merged({ "created": CREATED, "tags": ["real-world"], "source": SOURCE }, true), d.files())
	if err:
		print("FAIL: " + err)
		get_tree().quit(1)
		return
	var low := INF
	var high := -INF
	var tightest := 0.0
	for k in t.samples.size():
		low = minf(low, t.samples[k].y)
		high = maxf(high, t.samples[k].y)
		tightest = maxf(tightest, absf(t.curvature[k]))
	var trees := 0
	for g: Dictionary in d.layout.props.scatter:
		trees += (g.xf as Array).size() / 4
	print("Wrote %s: %.2f km, %d points, climb %.1f m, tightest %.1f m, off the real line by %.2f m at most, %d props, %d trees, layout %s, %d ms" % [
		out, t.length / 1000.0, d.points().size(), high - low, 1.0 / tightest, off_line(t), d.layout.props.items.size(), trees,
		t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


## The Eifel GP as a draft (the same every time).
static func build() -> TrackDraft:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var d := TrackDraft.blank("Eifel GP")
	d.id = "eifel_gp"
	d.info.author = "nOSS contributors"
	d.info.license = LICENSE
	d.info.attributions = ATTRIBUTIONS.duplicate()
	var line := _centreline(data)
	var pts := _pick(line)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	_terrain(d, data.dem, box)
	d.layout.road.points = Array(pts).map(func(p: Vector2) -> Dictionary: return { "p": TrackDraft._vec(Vector3(p.x, 0.0, p.y)) })
	d._track = null
	d.set_default("width_l", HALF_WIDTH_M)
	d.set_default("width_r", HALF_WIDTH_M)
	var t := d.track()
	var at := func(p: Vector2) -> float: return snappedf(float(_project(d, t, p).distance), 0.1)
	var straight := Vector2(at.call(STRAIGHT_FROM), at.call(STRAIGHT_TO))
	var wide := _points_in(d, t, straight)
	d.set_attr(wide, "width_l", STRAIGHT_HALF_WIDTH_M)
	d.set_attr(wide, "width_r", STRAIGHT_HALF_WIDTH_M)
	t = d.track()
	_runoff(d, t, Vector2(at.call(ARENA_FROM), at.call(ARENA_TO)))
	var pit := _pits(d, d.track(), data.pit_lane, straight, at.call(START))
	t = d.track()
	_barriers(d, t)
	t = d.track()
	var start: float = at.call(START)
	d.set_race("start_m", start)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])
	_props(d, d.track(), start, pit)
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


# --- the road ------------------------------------------------------------------------------

## The real centreline every RESAMPLE_M, smoothed (Gaussian, SMOOTH_M): closed.
static func _centreline(data: Dictionary = {}) -> PackedVector2Array:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var raw := PackedVector2Array()
	for p: Array in data.centreline:
		raw.append(Vector2(p[0], p[1]))
	var m := raw.size()
	var total := 0.0
	for i in m:
		total += raw[i].distance_to(raw[(i + 1) % m])
	var n := int(total / RESAMPLE_M)
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
	var out := _gauss(even, SMOOTH_M, step)
	# Corners tighter than TIGHT_R_M opened a little: smoothed more within TIGHT_REACH_M, blended out.
	var wider := _gauss(even, TIGHT_SMOOTH_M, step)
	var tight := PackedInt32Array()
	for i in n:
		if _radius(out[posmod(i - 2, n)], out[i], out[(i + 2) % n]) < TIGHT_R_M:
			tight.append(i)
	var blended := out.duplicate()
	for i in n:
		var near := INF
		for j in tight:
			var along := absi(i - j)
			near = minf(near, mini(along, n - along) * step)
		blended[i] = out[i].lerp(wider[i], 1.0 - smoothstep(TIGHT_REACH_M * 0.4, TIGHT_REACH_M, near))
	return blended


## `line` (closed, `step` apart) smoothed by a Gaussian of `sigma` m.
static func _gauss(line: PackedVector2Array, sigma: float, step: float) -> PackedVector2Array:
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


## Control points along `line` (closed, even steps): RADIUS_SHARE of the tightest radius in the
## next SPACING_MAX_M apart.
static func _pick(line: PackedVector2Array) -> PackedVector2Array:
	var n := line.size()
	var step := line[0].distance_to(line[1])
	var radius := PackedFloat32Array()
	for i in n:
		radius.append(_radius(line[posmod(i - 2, n)], line[i], line[(i + 2) % n]))
	var look := ceili(SPACING_MAX_M / step)
	var out := PackedVector2Array()
	var i := 0
	while i < n:
		out.append(Vector2(snappedf(line[i].x, 0.01), snappedf(line[i].y, 0.01)))
		var r := INF
		for o in look:
			r = minf(r, radius[(i + o) % n])
		i += maxi(1, roundi(clampf(r * RADIUS_SHARE, SPACING_MIN_M, SPACING_MAX_M) / step))
	if out[out.size() - 1].distance_to(out[0]) < SPACING_MIN_M:
		out.remove_at(out.size() - 1)
	return out


## The radius of the circle through a, b, c (INF if they're in line).
static func _radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var cross := (b - a).cross(c - b)
	if absf(cross) < 0.000001:
		return INF
	return a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * absf(cross))


## The ground: the DEM (smoothed over 3 by 3 cells) under the road and BASE_BELOW_M below
## its lowest point at 0, bilinear between its cells.
static func _terrain(d: TrackDraft, dem: Dictionary, box: Rect2) -> void:
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
	var base := floorf(lowest) - BASE_BELOW_M
	d.terrain = TerrainData.around(box, TERRAIN_MARGIN_M)
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


## The control points from `span.x` to `span.y` m along (wrapping).
static func _points_in(d: TrackDraft, t: TrackData, span: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in d.points().size():
		if _within(t, _point_m(t, i), span):
			out.append(i)
	return out


static func _point_m(t: TrackData, i: int) -> float:
	return t.distances[t.seg_first[i]]


## The nearest point on the road to `p` (x, z), from the ground's height there (projection
## weighs height: from 0 a lower part of the road could win).
static func _project(d: TrackDraft, t: TrackData, p: Vector2) -> Dictionary:
	return t.project(Vector3(p.x, d.terrain.base_at(p.x, p.y), p.y))


static func _within(t: TrackData, m: float, span: Vector2) -> bool:
	return fposmod(m - span.x, t.length) <= fposmod(span.y - span.x, t.length)


## The tightest radius over control segment `seg` (its samples and a few either side).
static func _segment_radius(t: TrackData, seg: int) -> float:
	var r := t.segment_samples(seg)
	var n := t.samples.size()
	var k := 0.0
	for s in range(r.x - 5, r.y + 6):
		k = maxf(k, absf(t.curvature[posmod(s, n)]))
	return 1.0 / maxf(k, 0.000001)


## How far out from the edge on `side` (+1 left) at sample `k` is clear of other parts of the
## road (their edges) by `clear`, up to `want`.
static func _room(t: TrackData, k: int, side: float, want: float, clear: float) -> float:
	var half: float = t.half_l[k] if side > 0.0 else t.half_r[k]
	var out := 0.0
	while out < want:
		var p := t.samples[k] + t.lefts[k] * side * (half + out + 2.0)
		if _near_other(t, k, p, clear + HALF_WIDTH_M + 2.0):
			break
		out += 2.0
	return minf(out, want)


## True if a part of the road more than SAME_PART_M along from sample `k` is within `r` of `p`.
static func _near_other(t: TrackData, k: int, p: Vector3, r: float) -> bool:
	for j in t.samples_near(p, r):
		var along := absf(t.distances[j] - t.distances[k])
		if minf(along, t.length - along) > SAME_PART_M:
			return true
	return false


## Gravel outside corners tighter than GRAVEL_R_M (paved in the first-corner complex, `arena`),
## as far as other parts of the road allow.
static func _runoff(d: TrackDraft, t: TrackData, arena: Vector2) -> void:
	var changes := {}
	for i in d.points().size():
		if _segment_radius(t, i) >= GRAVEL_R_M:
			continue
		var r := t.segment_samples(i)
		var mid := posmod((r.x + r.y) / 2, t.samples.size())
		# Turning left (curvature > 0): the outside is on the right.
		var side := "r" if t.curvature[mid] > 0.0 else "l"
		var paved := _within(t, t.distances[mid], arena)
		var want := PAVED_M if paved else GRAVEL_M
		var room := want
		for s in range(r.x, r.y + 1):
			room = minf(room, _room(t, posmod(s, t.samples.size()), 1.0 if side == "l" else -1.0, want, RUNOFF_CLEAR_M))
		if room <= TrackFormat.DEFAULTS.runoff_l_m:
			continue
		changes[i] = { "runoff_" + side: "asphalt" if paved else "gravel", "runoff_%s_m" % side: snappedf(room, 0.5) }
	_apply(d, changes)


## The pit lane (the real one) along the right of the start straight: paved run-off out to it,
## no barrier (the pit building stands behind it). Its lateral at the start line (m, + left).
static func _pits(d: TrackDraft, t: TrackData, pit_lane: Array, straight: Vector2, start: float) -> float:
	var along := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	for p: Array in pit_lane:
		var proj := _project(d, t, Vector2(p[0], p[1]))
		along.append(float(proj.distance))
		lateral.append(float(proj.lateral))
	var lat_at := func(m: float) -> float:
		var best := INF
		var lat := 0.0
		for j in along.size():
			var gap := absf(along[j] - m)
			if gap < best:
				best = gap
				lat = lateral[j]
		return lat if best < 40.0 else 0.0
	var changes := {}
	for i in _points_in(d, t, straight):
		var lat: float = lat_at.call(_point_m(t, i))
		var k := t.index_at(_point_m(t, i))
		var out := -lat + PIT_LANE_HALF_M - t.half_r[k]
		if lat >= 0.0 or out < 6.0 or out > 40.0:
			continue
		changes[i] = { "runoff_r": "asphalt", "runoff_r_m": snappedf(out, 0.5), "barrier_r": "none" }
	_apply(d, changes)
	return lat_at.call(start)


## Armco on segments straighter than ARMCO_R_M whose barrier line keeps ARMCO_CLEAR_M from
## other parts of the road; auto (tyre walls outside corners) elsewhere.
static func _barriers(d: TrackDraft, t: TrackData) -> void:
	var changes := {}
	var n := t.samples.size()
	for i in d.points().size():
		if _segment_radius(t, i) < ARMCO_R_M:
			continue
		var r := t.segment_samples(i)
		for side: float in [1.0, -1.0]:
			var key := "barrier_l" if side > 0.0 else "barrier_r"
			if TrackFormat.attr(d.layout.road, i, key) != "auto":
				continue
			var clear := true
			for s in range(r.x, r.y + 1, 2):
				var k := posmod(s, n)
				var reach: float = (t.half_l[k] + t.runoff_l_m[k]) if side > 0.0 else (t.half_r[k] + t.runoff_r_m[k])
				if _near_other(t, k, t.samples[k] + t.lefts[k] * side * reach, ARMCO_CLEAR_M + HALF_WIDTH_M):
					clear = false
					break
			if clear:
				if not changes.has(i):
					changes[i] = {}
				changes[i][key] = "armco"
	_apply(d, changes)


## Sets {point: {key: value}} as one change per key.
static func _apply(d: TrackDraft, changes: Dictionary) -> void:
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


# --- round the road ------------------------------------------------------------------------

## The pits, grandstands, crowds, marshal posts, billboards and the forest.
static func _props(d: TrackDraft, t: TrackData, start: float, pit_lat: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 200
	var placed := {} # Vector2i (50 m cell) -> [[Vector2, reach]]
	var free := func(p: Vector2, reach: float) -> bool:
		var cell := Vector2i(floori(p.x / 50.0), floori(p.y / 50.0))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for other: Array in placed.get(cell + Vector2i(dx, dz), []):
					if p.distance_to(other[0]) < reach + float(other[1]):
						return false
		return true
	var keep := func(p: Vector2, reach: float) -> void:
		var cell := Vector2i(floori(p.x / 50.0), floori(p.y / 50.0))
		if not placed.has(cell):
			placed[cell] = []
		placed[cell].append([p, reach])
	# A long prop along `fwd` from `centre`: kept as circles every 8 m.
	var keep_long := func(centre: Vector2, fwd: Vector2, length: float, reach: float) -> void:
		for s in range(-int(length / 2.0), int(length / 2.0) + 1, 8):
			keep.call(centre + fwd * s, reach)
	# The pits: the building behind the pit lane, along the straight round the start line.
	var x := t.transform_at(start)
	var fwd := Vector2(x.basis.z.x, x.basis.z.z).normalized()
	var left := Vector2(x.basis.x.x, x.basis.x.z).normalized()
	var o := Vector2(x.origin.x, x.origin.z)
	if pit_lat >= 0.0:
		push_error("The pit lane isn't right of the start line")
	var pit_c := o + left * (pit_lat - PIT_LANE_HALF_M - 7.0)
	d.add_prop({ "prop": "pit_building", "p": [snappedf(pit_c.x, 0.01), 0.0, snappedf(pit_c.y, 0.01)], "yaw_deg": _yaw_along(fwd),
		"scale": 1.0, "size": [12.0, 9.0, 300.0], "ground": true })
	keep_long.call(pit_c, fwd, 300.0, 40.0) # the paddock behind it stays clear
	# Grandstands (each with its crowd at the fence): opposite the pits, on the outside of the
	# first corner's braking (the complex's way out hems in the corner itself), outside the
	# hairpin and the chicane's first part.
	var t1 := float(_project(d, t, T1).distance)
	var stands := [[start - 20.0, 1.0, 240.0], [t1 - 110.0, -signf(t.curvature[t.index_at(t1)]), 120.0]]
	for spot: Vector2 in [HAIRPIN, CHICANE]:
		var m := float(_project(d, t, spot).distance)
		stands.append([m, -signf(t.curvature[t.index_at(m)]), 100.0])
	for s: Array in stands:
		_stand(d, t, float(s[0]), float(s[1]), float(s[2]), free, keep_long)
	# Marshal posts about every MARSHAL_EVERY_M, behind the barrier on whichever side is clear.
	for k in int(t.length / MARSHAL_EVERY_M):
		var m := fposmod(start + 150.0 + k * MARSHAL_EVERY_M, t.length)
		for side: float in [1.0, -1.0]:
			var p := _behind(t, m, side, 3.0)
			if free.call(p, 3.0) and not _near_other(t, t.index_at(m), Vector3(p.x, 0, p.y), 20.0):
				keep.call(p, 3.0)
				d.add_prop({ "prop": "marshal_post", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)], "yaw_deg": _yaw_along(_fwd_at(t, m)),
					"scale": 1.0, "ground": true })
				break
	# Billboards outside each corner tighter than 120 m, at its tightest, facing the road.
	var n := t.samples.size()
	var k := 0
	while k < n:
		if absf(t.curvature[k]) < 1.0 / 120.0:
			k += 1
			continue
		var apex := k
		while k < n and absf(t.curvature[k]) >= 1.0 / 120.0:
			if absf(t.curvature[k]) > absf(t.curvature[apex]):
				apex = k
			k += 1
		var side := -signf(t.curvature[apex])
		var p := _behind(t, t.distances[apex], side, 8.0)
		if free.call(p, 4.0) and not _near_other(t, apex, Vector3(p.x, 0, p.y), 20.0):
			keep.call(p, 4.0)
			var to_road := Vector2(t.samples[apex].x, t.samples[apex].z) - p
			d.add_prop({ "prop": "billboard", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)],
				"yaw_deg": snappedf(rad_to_deg(atan2(to_road.x, to_road.y)), 0.1), "scale": 1.0, "ground": true })
	# The forest: clumps of pines and broadleaves, TREE_ROAD_M clear of the road.
	var area := d.terrain.area().grow(-5.0)
	var pines := []
	var broad := []
	var tries := 0
	while (pines.size() + broad.size()) / 4 < TREES and tries < TREES * 60:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var clump := 0.5 + 0.5 * sin(p.x / 140.0 + 1.3) * cos(p.y / 110.0 - 0.4)
		if rng.randf() > clump * clump or not free.call(p, 3.0) or t.is_near_centreline(Vector3(p.x, 0, p.y), TREE_ROAD_M):
			continue
		keep.call(p, 3.0)
		var xf := [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rng.randf() * TAU, 0.001), snappedf(rng.randf_range(0.8, 1.3), 0.001)]
		if rng.randf() < 0.7:
			pines.append_array(xf)
		else:
			broad.append_array(xf)
	d.set_scatter_live("tree_pine", pines)
	d.set_scatter_live("tree_round", broad)


## A grandstand `length` long on `side` (+1 left) at `m`, behind the barrier, facing the road,
## with a crowd at its foot; none if it would come near another part of the road or a prop.
static func _stand(d: TrackDraft, t: TrackData, m: float, side: float, length: float, free: Callable, keep_long: Callable) -> void:
	var front := _behind(t, m, side, 6.0)
	var x := t.transform_at(m)
	var fwd := Vector2(x.basis.z.x, x.basis.z.z).normalized()
	var away := Vector2(x.basis.x.x, x.basis.x.z).normalized() * side
	var k := t.index_at(m)
	for s in range(-int(length / 2.0), int(length / 2.0) + 1, 6):
		for depth: float in [0.0, 6.0, 13.0]:
			var p := front + fwd * s + away * depth
			if not free.call(p, 2.0) or _near_other(t, k, Vector3(p.x, 0, p.y), 20.0) or t.is_near_centreline(Vector3(p.x, 0, p.y), 14.0):
				print("  no grandstand at %.0f m: no room" % m)
				return
	keep_long.call(front + away * 4.0, fwd, length, 10.0) # the crowd's ground in front too
	var yaw := snappedf(rad_to_deg(atan2(-away.y, away.x)), 0.1)
	d.add_prop({ "prop": "grandstand", "p": [snappedf(front.x, 0.01), 0.0, snappedf(front.y, 0.01)], "yaw_deg": yaw, "scale": 1.0,
		"size": [13.0, 9.9, length], "ground": true })
	var crowd := front - away * 2.0
	d.add_prop({ "prop": "crowd", "p": [snappedf(crowd.x, 0.01), 0.0, snappedf(crowd.y, 0.01)], "yaw_deg": _yaw_along(fwd), "scale": 1.0,
		"size": [0.0, 0.0, length], "ground": true })


## The spot `extra` m behind the barrier (the run-off's end) on `side` (+1 left) at `m`.
static func _behind(t: TrackData, m: float, side: float, extra: float) -> Vector2:
	var k := t.index_at(m)
	var reach: float = (t.half_l[k] + t.runoff_l_m[k]) if side > 0.0 else (t.half_r[k] + t.runoff_r_m[k])
	var x := t.transform_at(m, side * (reach + extra))
	return Vector2(x.origin.x, x.origin.z)


static func _fwd_at(t: TrackData, m: float) -> Vector2:
	var x := t.transform_at(m)
	return Vector2(x.basis.z.x, x.basis.z.z).normalized()


## The yaw (degrees) that turns a prop's +z along `fwd` (x, z).
static func _yaw_along(fwd: Vector2) -> float:
	return snappedf(rad_to_deg(atan2(fwd.x, fwd.y)), 0.1)


## The furthest the road's centreline `t` gets from the real one (smoothed), m.
static func off_line(t: TrackData) -> float:
	var worst := 0.0
	for p in _centreline():
		var best := INF
		for j in t.samples_near(Vector3(p.x, 0, p.y), 20.0):
			var a := Vector2(t.samples[j].x, t.samples[j].z)
			var b := Vector2(t.samples[(j + 1) % t.samples.size()].x, t.samples[(j + 1) % t.samples.size()].z)
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
		worst = maxf(worst, best)
	return worst
