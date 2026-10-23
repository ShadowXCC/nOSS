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

const G := preload("res://tools/track_gen_util.gd")
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
## The pit lane (D203): 8 m wide (the map's line sits 12-19 m off the road's), kept PIT_CLEAR_M
## clear of the road's edge for its wall, attached for PIT_TAPER_M at each end; 80 km/h, a box
## for each grid slot.
const PIT_LANE_HALF_M := 4.0
const PIT_CLEAR_M := 2.0
const PIT_TAPER_M := 90.0
const PIT_SPEED_KMH := 80.0
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
	var pts := G.pick(line, SPACING_MIN_M, SPACING_MAX_M, RADIUS_SHARE)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	G.terrain(d, data.dem, box, TERRAIN_MARGIN_M, BASE_BELOW_M)
	d.layout.road.points = Array(pts).map(func(p: Vector2) -> Dictionary: return { "p": TrackDraft._vec(Vector3(p.x, 0.0, p.y)) })
	d._track = null
	d.set_default("width_l", HALF_WIDTH_M)
	d.set_default("width_r", HALF_WIDTH_M)
	var t := d.track()
	var at := func(p: Vector2) -> float: return snappedf(float(G.project(d, t, p).distance), 0.1)
	var straight := Vector2(at.call(STRAIGHT_FROM), at.call(STRAIGHT_TO))
	var wide := G.points_in(d, t, straight)
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
	var resampled := G.resample(raw, RESAMPLE_M)
	var even: PackedVector2Array = resampled.line
	var step: float = resampled.step
	var n := even.size()
	var out := G.gauss(even, SMOOTH_M, step)
	# Corners tighter than TIGHT_R_M opened a little: smoothed more within TIGHT_REACH_M, blended out.
	var wider := G.gauss(even, TIGHT_SMOOTH_M, step)
	var tight := PackedInt32Array()
	for i in n:
		if G.radius(out[posmod(i - 2, n)], out[i], out[(i + 2) % n]) < TIGHT_R_M:
			tight.append(i)
	var blended := out.duplicate()
	for i in n:
		var near := INF
		for j in tight:
			var along := absi(i - j)
			near = minf(near, mini(along, n - along) * step)
		blended[i] = out[i].lerp(wider[i], 1.0 - smoothstep(TIGHT_REACH_M * 0.4, TIGHT_REACH_M, near))
	return blended


## How far out from the edge on `side` (+1 left) at sample `k` is clear of other parts of the
## road (their edges) by `clear`, up to `want`.
static func _room(t: TrackData, k: int, side: float, want: float, clear: float) -> float:
	var half: float = t.half_l[k] if side > 0.0 else t.half_r[k]
	var out := 0.0
	while out < want:
		var p := t.samples[k] + t.lefts[k] * side * (half + out + 2.0)
		if G.near_other(t, k, p, clear + HALF_WIDTH_M + 2.0):
			break
		out += 2.0
	return minf(out, want)


## Gravel outside corners tighter than GRAVEL_R_M (paved in the first-corner complex, `arena`),
## as far as other parts of the road allow.
static func _runoff(d: TrackDraft, t: TrackData, arena: Vector2) -> void:
	var changes := {}
	for i in d.points().size():
		if G.segment_radius(t, i) >= GRAVEL_R_M:
			continue
		var r := t.segment_samples(i)
		var mid := posmod((r.x + r.y) / 2, t.samples.size())
		# Turning left (curvature > 0): the outside is on the right.
		var side := "r" if t.curvature[mid] > 0.0 else "l"
		var paved := G.within(t, t.distances[mid], arena)
		var want := PAVED_M if paved else GRAVEL_M
		var room := want
		for s in range(r.x, r.y + 1):
			room = minf(room, _room(t, posmod(s, t.samples.size()), 1.0 if side == "l" else -1.0, want, RUNOFF_CLEAR_M))
		if room <= TrackFormat.DEFAULTS.runoff_l_m:
			continue
		changes[i] = { "runoff_" + side: "asphalt" if paved else "gravel", "runoff_%s_m" % side: snappedf(room, 0.5) }
	G.apply(d, changes)


## The pit lane (the real one, D203) on the right: it leaves the road in the last chicane and
## joins it before the first corner. Between its tapers it follows the map's pit points, pushed
## out where they come within PIT_CLEAR_M of the road; paved run-off out to its wall. Returns its
## lateral at the start line (m, + left).
static func _pits(d: TrackDraft, t: TrackData, pit_lane: Array, straight: Vector2, start: float) -> float:
	var along := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	for p: Array in pit_lane:
		var proj := G.project(d, t, Vector2(p[0], p[1]))
		along.append(float(proj.distance))
		var k := t.index_at(float(proj.distance))
		lateral.append(minf(float(proj.lateral), -(t.half_r[k] + PIT_CLEAR_M + PIT_LANE_HALF_M)))
	var from := snappedf(along[0], 0.1)
	var to := snappedf(along[along.size() - 1], 0.1)
	var points := []
	var free := Vector2(from + PIT_TAPER_M + 15.0, to - PIT_TAPER_M - 15.0)
	for j in along.size():
		if G.within(t, along[j], free):
			var at := t.transform_at(along[j], lateral[j]).origin
			points.append({ "p": [snappedf(at.x, 0.01), 0.0, snappedf(at.z, 0.01)] })
	d.add_pit(from, to, "right")
	d.set_pit("taper_m", PIT_TAPER_M)
	d.set_pit("width_m", PIT_LANE_HALF_M * 2.0)
	d.set_pit("speed_kmh", PIT_SPEED_KMH)
	d.set_pit("boxes", int(d.layout.race.grid.slots))
	d.set_pit("points", points)
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
	for i in G.points_in(d, t, straight):
		var lat: float = lat_at.call(G.point_m(t, i))
		var k := t.index_at(G.point_m(t, i))
		var out := -lat - PIT_LANE_HALF_M - t.half_r[k] - 1.0 # up to the wall
		if lat >= 0.0 or out < 0.5 or out > 40.0:
			continue
		changes[i] = { "runoff_r": "asphalt", "runoff_r_m": snappedf(out, 0.5), "barrier_r": "none" }
	G.apply(d, changes)
	return lat_at.call(start)


## Armco on segments straighter than ARMCO_R_M whose barrier line keeps ARMCO_CLEAR_M from
## other parts of the road; auto (tyre walls outside corners) elsewhere.
static func _barriers(d: TrackDraft, t: TrackData) -> void:
	var changes := {}
	var n := t.samples.size()
	for i in d.points().size():
		if G.segment_radius(t, i) < ARMCO_R_M:
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
				if G.near_other(t, k, t.samples[k] + t.lefts[k] * side * reach, ARMCO_CLEAR_M + HALF_WIDTH_M):
					clear = false
					break
			if clear:
				if not changes.has(i):
					changes[i] = {}
				changes[i][key] = "armco"
	G.apply(d, changes)


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
	var pit_c := o + left * (pit_lat - PIT_LANE_HALF_M - 9.0)
	d.add_prop({ "prop": "pit_building", "p": [snappedf(pit_c.x, 0.01), 0.0, snappedf(pit_c.y, 0.01)], "yaw_deg": G.yaw_along(fwd),
		"scale": 1.0, "size": [12.0, 9.0, 300.0], "ground": true })
	keep_long.call(pit_c, fwd, 300.0, 40.0) # the paddock behind it stays clear
	for i in range(0, t.pit.track.samples.size(), 4): # and so does the pit lane
		var q := t.pit.track.samples[i]
		keep.call(Vector2(q.x, q.z), t.pit.width / 2.0 + 2.0)
	# Grandstands (each with its crowd at the fence): opposite the pits, on the outside of the
	# first corner's braking (the complex's way out hems in the corner itself), outside the
	# hairpin and the chicane's first part.
	var t1 := float(G.project(d, t, T1).distance)
	var stands := [[start - 20.0, 1.0, 240.0], [t1 - 110.0, -signf(t.curvature[t.index_at(t1)]), 120.0]]
	for spot: Vector2 in [HAIRPIN, CHICANE]:
		var m := float(G.project(d, t, spot).distance)
		stands.append([m, -signf(t.curvature[t.index_at(m)]), 100.0])
	for s: Array in stands:
		G.stand(d, t, float(s[0]), float(s[1]), float(s[2]), free, keep_long)
	# Marshal posts about every MARSHAL_EVERY_M, behind the barrier on whichever side is clear.
	for k in int(t.length / MARSHAL_EVERY_M):
		var m := fposmod(start + 150.0 + k * MARSHAL_EVERY_M, t.length)
		for side: float in [1.0, -1.0]:
			var p := G.behind(t, m, side, 3.0)
			if free.call(p, 3.0) and not G.near_other(t, t.index_at(m), Vector3(p.x, 0, p.y), 20.0):
				keep.call(p, 3.0)
				d.add_prop({ "prop": "marshal_post", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)], "yaw_deg": G.yaw_along(G.fwd_at(t, m)),
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
		var p := G.behind(t, t.distances[apex], side, 8.0)
		if free.call(p, 4.0) and not G.near_other(t, apex, Vector3(p.x, 0, p.y), 20.0):
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


## The furthest the road's centreline `t` gets from the real one (smoothed), m.
static func off_line(t: TrackData) -> float:
	return G.off_line(t, _centreline())
