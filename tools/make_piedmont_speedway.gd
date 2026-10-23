extends Node
## Writes content/tracks/piedmont_speedway/: Piedmont Speedway (D206), a 1.5-mile quad-oval on the
## real Charlotte Motor Speedway layout under a name of its own, made with the track editor's own
## commands (TrackDraft) so the editor can open and change it.
##
## tools/data/piedmont.json (tools/fetch_piedmont.py) holds the oval's line, its pit lane and the
## raceways round it (OpenStreetMap, ODbL) and the ground (USGS NED, about 10 m, public domain).
## The map's line runs along the inside of the track: it's smoothed and moved out so the line
## 15 ft (4.57 m) out from the racing surface's inner edge is 1.5 miles. Run counter-clockwise
## (seen with north up, -z north), the frontstretch with its dogleg on the west side.
##
## 18 m of racing surface, banked 24° in the turns and 5° on the straights and the dogleg (from the
## line's curvature over 200 m), standing on its inner edge at the infield's grade: a level 9 m
## apron inside, a SAFER wall with its catch fence right at the outside. The ground is the DEM,
## level over the venue (and up to the top of the banking for a berm outside the wall, where the
## grandstands stand), blending back into the real hills further out. Pit road inside the
## frontstretch, 20 boxes, 45 mph. The road course's infield and chicanes are scenery roads in the
## infield (D212). Night under the lights; it suggests a rolling start, drafting,
## fuel and tires at five times their wear, and pack racing (D207).
##   tools/godot.sh --headless res://tools/make_piedmont_speedway.tscn [-- --out=<folder>]

const G := preload("res://tools/track_gen_util.gd")
const OUT := "res://content/tracks/piedmont_speedway"
const DATA := "res://tools/data/piedmont.json"
## Its infield road course's generator (loaded when building: it builds this one first).
const ROAD_COURSE := "res://tools/make_piedmont_road_course.gd"
const CREATED := "2026-10-23"
const LICENSE := "ODbL-1.0"
const ATTRIBUTIONS := ["Layout © OpenStreetMap contributors (ODbL 1.0)",
	"Ground: U.S. Geological Survey, 3D Elevation Program (public domain)"]
const SOURCE := "OpenStreetMap ways 396483278, 116034341, 402168709, 1052107104 and 402168711 (the oval), USGS NED 1/3 arc-second"
## The line's resampling step and its smoothing (Gaussian sigma), m.
const RESAMPLE_M := 5.0
const SMOOTH_M := 12.0
## 1.5 miles, measured MEASURED_IN_M out from the racing surface's inner edge.
const MILES_M := 2414.0
const MEASURED_IN_M := 4.57
const HALF_M := 9.0
const APRON_M := 9.0
const INFIELD_RUNOFF_M := 6.0
## The SAFER wall's middle, out from the edge (its face 0.3 m off it, past a concrete strip).
const WALL_RUNOFF_M := 0.6
## Banking: TURN_DEG where the line's curvature over ±BANK_WINDOW_M is tighter than TURN_R_M,
## STRAIGHT_DEG where it's gentler than STRAIGHT_R_M, smoothstep between.
const TURN_DEG := 24.0
const STRAIGHT_DEG := 5.0
const TURN_R_M := 280.0
const STRAIGHT_R_M := 450.0
const BANK_WINDOW_M := 100.0
## The banking then eased along the track (Gaussian sigma, m): long transitions, no humps on the
## way down from the top of a straight to the bottom of a turn.
const BANK_SMOOTH_M := 45.0
## Control points: RADIUS_SHARE of the tightest radius just ahead apart, within these (m).
const SPACING_MIN_M := 12.0
const SPACING_MAX_M := 40.0
const RADIUS_SHARE := 0.25
## The ground: this far round the line, its lowest point this far above the terrain's 0. Level
## at the infield's grade over the venue; outside the wall a berm at the top of the banking
## BERM_M wide, falling off over BERM_FALLOFF_M; then BLEND_M back into the real hills.
const TERRAIN_MARGIN_M := 220.0
const BASE_BELOW_M := 5.0
const BERM_M := 40.0
const BERM_FALLOFF_M := 40.0
const BLEND_M := 150.0
## The coarse grid the venue's distances are worked out on, m.
const DISTANCE_CELL_M := 10
## Pit road: 12 m, 45 mph, a box per grid slot, PIT_CLEAR_M off the paved edge, 120 m tapers.
const PIT_HALF_M := 6.0
const PIT_CLEAR_M := 3.0
const PIT_TAPER_M := 120.0
const PIT_SPEED_KMH := 72.0
const PIT_BOX_M := 12.0
## The start line: the dogleg's apex on the map (x, z). Three sectors, a grid of 20 side by side,
## rolling from GRID_ROLL_M further back (the grid stays on the frontstretch).
const START := Vector2(-250.0, -44.0)
const GRID_SLOTS := 20
const GRID_ROW_M := 12.0
const GRID_ROLL_M := 80.0
## Scenery: a light tower every LIGHT_EVERY_M behind the wall; grandstands on the frontstretch,
## round the ends and on the backstretch; garages behind pit road; billboards in the turns'
## infield; trees outside the venue.
const LIGHT_EVERY_M := 60.0
const TREES := 1500
const TREE_CLEAR_M := 200.0

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
		print("  %s: %s%s" % [p.level, p.text, " (%.0f, %.0f)" % [p.point.x, p.point.z] if p.point is Vector3 else ""])
	if not TrackValidator.errors(found).is_empty():
		print("FAIL: validation errors")
		get_tree().quit(1)
		return
	var out := String(opts.out)
	var err := TrackWriter.write_folder(out, d.manifest_info().merged({ "created": CREATED, "tags": ["real-world", "oval"], "source": SOURCE }, true), d.files())
	if err:
		print("FAIL: " + err)
		get_tree().quit(1)
		return
	var steepest := 0.0
	for b in t.bank:
		steepest = maxf(steepest, absf(rad_to_deg(b)))
	print("Wrote %s: %.3f km (%.0f m at 15 ft), %d points, banking to %.1f°, pit road %.0f m with %d boxes, %d props, layout %s, %d ms" % [
		out, t.length / 1000.0, measured_m(t), d.points().size(), steepest, t.pit.track.length if t.pit else 0.0, t.pit.boxes.size() if t.pit else 0,
		d.layout.props.items.size(), t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


## Piedmont Speedway as a draft (the same every time).
static func build() -> TrackDraft:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var d := TrackDraft.blank("Piedmont Speedway")
	d.id = "piedmont_speedway"
	d.info.author = "nOSS contributors"
	d.info.license = LICENSE
	d.info.attributions = ATTRIBUTIONS.duplicate()
	var line := centreline(data)
	var grade := _ground(d, data.dem, line)
	var bank := _banking(line)
	var pts := G.pick(line, SPACING_MIN_M, SPACING_MAX_M, RADIUS_SHARE)
	var points := []
	for p in pts:
		var b := bank_at(line, bank, p)
		# Standing on its inner edge at the infield's grade.
		var y := grade + HALF_M * sin(deg_to_rad(absf(b)))
		points.append({ "p": [p.x, snappedf(y, 0.01), p.y], "bank_deg": snappedf(b, 0.1) })
	d.layout.road.points = points
	d.layout.road.defaults.merge({
		"width_l": HALF_M, "width_r": HALF_M, "height": "set", "curb_l": "off", "curb_r": "off",
		"apron_l_m": APRON_M, "apron_l_deg": 0.0, "runoff_l": "grass", "runoff_l_m": INFIELD_RUNOFF_M, "barrier_l": "none",
		"runoff_r": "concrete", "runoff_r_m": WALL_RUNOFF_M, "barrier_r": "safer",
	}, true)
	d._track = null
	var t := d.track()
	_berm(d, t)
	d._track = null
	t = d.track()
	var start := snappedf(float(G.project(d, t, START).distance), 0.1)
	d.set_race("start_m", start)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])
	d.set_race("grid/slots", GRID_SLOTS)
	d.set_race("grid/row_m", GRID_ROW_M)
	d.set_race("grid/stagger", 0.0)
	d.set_race("rolling_back_m", GRID_ROLL_M)
	_pits(d, d.track(), data.pit_lane)
	# The rest of the venue (D212): the road course's infield and chicanes.
	for road: Dictionary in load(ROAD_COURSE).infield_roads(d):
		d.add_road(road)
	d.set_env("time", "night")
	d.set_env("floodlit", true)
	# What events that keep "Track's" race with (D207): a rolling start, drafting, five times the
	# fuel use and tire wear (stops in a short race), the AI in packs.
	for rule: Array in [["start", "rolling"], ["draft", true], ["fuel_x", 5], ["tyre_x", 5], ["pack", true]]:
		d.set_rule(rule[0], rule[1])
	_props(d, d.track(), start, line)
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


# --- the road ------------------------------------------------------------------------------

## The map's line every RESAMPLE_M, smoothed (SMOOTH_M) and moved out so the line 4.57 m in from
## the inner edge is MILES_M round: closed, counter-clockwise.
static func centreline(data: Dictionary = {}) -> PackedVector2Array:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var raw := PackedVector2Array()
	for p: Array in data.centreline:
		raw.append(Vector2(p[0], p[1]))
	var resampled := G.resample(raw, RESAMPLE_M)
	var smooth := G.gauss(resampled.line, SMOOTH_M, resampled.step)
	# A closed line turning left grows by TAU per metre it moves out: the measured line is
	# HALF_M - MEASURED_IN_M inside the centre.
	return G.offset(smooth, (MILES_M - _length(smooth)) / TAU + HALF_M - MEASURED_IN_M)


static func _length(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in line.size():
		total += line[i].distance_to(line[(i + 1) % line.size()])
	return total


## The length of the line 4.57 m out from the inner edge (the 1.5 miles), m.
static func measured_m(t: TrackData) -> float:
	var total := 0.0
	var n := t.samples.size()
	var line := PackedVector2Array()
	for i in n:
		var p := t.samples[i] + t.lefts[i] * (t.half_l[i] - MEASURED_IN_M)
		line.append(Vector2(p.x, p.z))
	for i in n:
		total += line[i].distance_to(line[(i + 1) % n])
	return total


## Banking along `line` (degrees, - raises the outside): from its curvature over ±BANK_WINDOW_M.
static func _banking(line: PackedVector2Array) -> PackedFloat32Array:
	var n := line.size()
	var step := _length(line) / n
	var heading := PackedFloat32Array()
	for i in n:
		var d := line[(i + 1) % n] - line[i]
		heading.append(atan2(d.y, d.x))
	var turn := PackedFloat32Array()
	for i in n:
		turn.append(absf(wrapf(heading[i] - heading[(i - 1 + n) % n], -PI, PI)) / step)
	var reach := int(BANK_WINDOW_M / step)
	var out := PackedFloat32Array()
	for i in n:
		var sum := 0.0
		for o in range(-reach, reach + 1):
			sum += turn[posmod(i + o, n)]
		var k := sum / (2 * reach + 1)
		out.append(-lerpf(STRAIGHT_DEG, TURN_DEG, smoothstep(1.0 / STRAIGHT_R_M, 1.0 / TURN_R_M, k)))
	var eased := PackedFloat32Array()
	var spread := ceili(3.0 * BANK_SMOOTH_M / step)
	for i in n:
		var sum := 0.0
		var wsum := 0.0
		for o in range(-spread, spread + 1):
			var w := exp(-0.5 * pow(o * step / BANK_SMOOTH_M, 2.0))
			sum += out[posmod(i + o, n)] * w
			wsum += w
		eased.append(sum / wsum)
	return eased


## The banking at `p` (on the line): its nearest sample's.
static func bank_at(line: PackedVector2Array, bank: PackedFloat32Array, p: Vector2) -> float:
	var best := 0
	for i in line.size():
		if line[i].distance_squared_to(p) < line[best].distance_squared_to(p):
			best = i
	return bank[best]


## The ground: the DEM, level over the venue at the infield's grade (the mean of the ground inside
## the line), blending into the real hills BLEND_M past the berm. Returns the grade.
static func _ground(d: TrackDraft, dem: Dictionary, line: PackedVector2Array) -> float:
	var box := Rect2(line[0], Vector2.ZERO)
	for p in line:
		box = box.expand(p)
	G.terrain(d, dem, box, TERRAIN_MARGIN_M, BASE_BELOW_M)
	var f := d.terrain.field
	var size: Vector2i = f.get_size()
	var origin: Vector2 = d.terrain.origin()
	var heights := f.region_get(Rect2i(Vector2i.ZERO, size))
	var n := line.size()
	# Inside the line: row by row, between its crossings.
	var inside := PackedByteArray()
	inside.resize(size.x * size.y)
	var sum := 0.0
	var count := 0
	for z in size.y:
		var wz := origin.y + z
		var xs := PackedFloat32Array()
		for i in n:
			var a := line[i]
			var b := line[(i + 1) % n]
			if (a.y <= wz) != (b.y <= wz):
				xs.append(a.x + (wz - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(maxi(ceili(xs[k] - origin.x), 0), mini(floori(xs[k + 1] - origin.x), size.x - 1) + 1):
				inside[z * size.x + x] = 1
				sum += heights[z * size.x + x]
				count += 1
	var grade := snappedf(sum / maxi(count, 1), TerrainData.HEIGHT_STEP)
	# How far from the line, on a coarse grid (every other sample of it is close enough).
	var cell := DISTANCE_CELL_M
	var cw := size.x / cell + 2
	var ch := size.y / cell + 2
	var far := PackedFloat32Array()
	far.resize(cw * ch)
	for cz in ch:
		for cx in cw:
			var p := origin + Vector2(cx * cell, cz * cell)
			var best := INF
			for i in range(0, n, 2):
				best = minf(best, p.distance_squared_to(line[i]))
			far[cz * cw + cx] = sqrt(best)
	var flat := HALF_M + WALL_RUNOFF_M + BERM_M + BERM_FALLOFF_M
	for z in size.y:
		for x in size.x:
			var k := z * size.x + x
			if inside[k]:
				heights[k] = grade
				continue
			var u := float(x) / cell
			var v := float(z) / cell
			var cx := int(u)
			var cz := int(v)
			var top := lerpf(far[cz * cw + cx], far[cz * cw + cx + 1], u - cx)
			var bottom := lerpf(far[(cz + 1) * cw + cx], far[(cz + 1) * cw + cx + 1], u - cx)
			var dist := lerpf(top, bottom, v - cz)
			heights[k] = snappedf(lerpf(grade, heights[k], smoothstep(flat, flat + BLEND_M, dist)), TerrainData.HEIGHT_STEP)
	f.set_base(heights)
	return grade


## The berm: outside the wall the ground comes up level with the top of the banking for BERM_M,
## falling off over BERM_FALLOFF_M (the native road bed, with a level "apron" out there).
static func _berm(d: TrackDraft, t: TrackData) -> void:
	var road := TerrainData.road_samples(t)
	var aprons := PackedFloat32Array()
	aprons.resize(road.size() / 9 * 6)
	for i in t.samples.size():
		road[i * 9 + 7] = t.half_r[i] + WALL_RUNOFF_M + BERM_M
		aprons[i * 6] = t.half_l[i]
		aprons[i * 6 + 1] = t.half_r[i]
		aprons[i * 6 + 2] = t.apron(i, 1.0)
		aprons[i * 6 + 3] = WALL_RUNOFF_M + BERM_M
	var f := d.terrain.field
	var size: Vector2i = f.get_size()
	f.conform(Rect2i(Vector2i.ZERO, size), road, BERM_FALLOFF_M, TerrainData.BED_DEPTH_M, aprons)
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	var chunk := TerrainData.CHUNK
	for cz in d.terrain.chunks().y:
		for cx in d.terrain.chunks().x:
			var c := f.chunk_collision(cx, cz, chunk)
			for z in chunk + 1:
				for x in chunk + 1:
					heights[(cz * chunk + z) * size.x + cx * chunk + x] = snappedf(c[z * (chunk + 1) + x], TerrainData.HEIGHT_STEP)
	f.set_base(heights)


## Pit road (the real one) inside the frontstretch: it leaves the apron in turn 4 and joins it
## before turn 1, through the map's pit points between its tapers (kept PIT_CLEAR_M off the paved
## edge for its wall).
static func _pits(d: TrackDraft, t: TrackData, pit_lane: Array) -> void:
	var along := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	for p: Array in pit_lane:
		var proj := G.project(d, t, Vector2(p[0], p[1]))
		along.append(float(proj.distance))
		var k := t.index_at(float(proj.distance))
		lateral.append(maxf(float(proj.lateral), t.half_l[k] + t.apron(k, 1.0) + PIT_CLEAR_M + PIT_HALF_M))
	var from := snappedf(along[0], 0.1)
	var to := snappedf(along[along.size() - 1], 0.1)
	var points := []
	var free := Vector2(from + PIT_TAPER_M + 15.0, to - PIT_TAPER_M - 15.0)
	for j in along.size():
		if G.within(t, along[j], free):
			var at := t.transform_at(along[j], lateral[j]).origin
			points.append({ "p": [snappedf(at.x, 0.01), 0.0, snappedf(at.z, 0.01)] })
	d.add_pit(from, to, "left")
	d.set_pit("taper_m", PIT_TAPER_M)
	d.set_pit("width_m", PIT_HALF_M * 2.0)
	d.set_pit("speed_kmh", PIT_SPEED_KMH)
	d.set_pit("boxes", GRID_SLOTS)
	d.set_pit("box_m", PIT_BOX_M)
	d.set_pit("points", points)


# --- round the road ------------------------------------------------------------------------

## Light towers, grandstands and crowds, garages, billboards and trees.
static func _props(d: TrackDraft, t: TrackData, start: float, line: PackedVector2Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 206
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
	var keep_long := func(centre: Vector2, fwd: Vector2, length: float, reach: float) -> void:
		for s in range(-int(length / 2.0), int(length / 2.0) + 1, 8):
			keep.call(centre + fwd * s, reach)
	for i in range(0, t.pit.track.samples.size(), 4): # pit road stays clear
		var q := t.pit.track.samples[i]
		keep.call(Vector2(q.x, q.z), t.pit.width / 2.0 + 2.0)
	for piece in t.scenery: # and the road course's roads
		for i in range(0, piece.samples.size(), 3):
			var q := piece.samples[i]
			keep.call(Vector2(q.x, q.z), maxf(piece.half_l[i], piece.half_r[i]) + 3.0)
	# Light towers behind the wall, the lamps facing the track.
	for k in int(t.length / LIGHT_EVERY_M):
		var m := fposmod(start + 30.0 + k * LIGHT_EVERY_M, t.length)
		var p := G.behind(t, m, -1.0, 2.5)
		keep.call(p, 1.0)
		var i := t.index_at(m)
		var to_road := Vector2(t.samples[i].x, t.samples[i].z) - p
		d.add_prop({ "prop": "light_tower", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)],
			"yaw_deg": snappedf(rad_to_deg(atan2(to_road.x, to_road.y)), 0.1), "scale": 1.0, "ground": true })
	# Grandstands outside: the frontstretch round the line, the ends, the backstretch.
	var stands := []
	for s in range(-2, 3):
		stands.append([start + s * 110.0, 100.0])
	for at: float in [start - 400.0, start - 480.0, start + 400.0, start + 480.0]:
		stands.append([at, 60.0])
	for at: float in [start + t.length / 2.0 - 70.0, start + t.length / 2.0 + 70.0]:
		stands.append([at, 120.0])
	for s: Array in stands:
		G.stand(d, t, fposmod(float(s[0]), t.length), -1.0, float(s[1]), free, keep_long, 8.0)
	# Garages behind pit road, along its boxes.
	var pit := t.pit
	var mid := (pit.gore_head + pit.gore_tail) / 2
	for s in [-1, 0, 1]:
		var at := clampf(pit.track.distances[mid] + s * 150.0, pit.track.distances[pit.gore_head], pit.track.distances[pit.gore_tail])
		var x := pit.track.transform_at(at, pit.width / 2.0 + 14.0)
		var p := Vector2(x.origin.x, x.origin.z)
		var fwd := Vector2(x.basis.z.x, x.basis.z.z).normalized()
		if free.call(p, 8.0):
			keep_long.call(p, fwd, 130.0, 10.0)
			d.add_prop({ "prop": "pit_building", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)], "yaw_deg": G.yaw_along(fwd),
				"scale": 1.0, "size": [12.0, 7.0, 130.0], "ground": true })
	# Billboards in the turns' infield, past the apron, facing the track.
	var n := t.samples.size()
	for k in range(0, n, 40):
		if absf(rad_to_deg(t.bank[k])) < TURN_DEG - 1.0:
			continue
		var x := t.transform_at(t.distances[k], t.half_l[k] + t.apron(k, 1.0) + INFIELD_RUNOFF_M + 6.0)
		var p := Vector2(x.origin.x, x.origin.z)
		if free.call(p, 5.0):
			keep.call(p, 5.0)
			var to_road := Vector2(t.samples[k].x, t.samples[k].z) - p
			d.add_prop({ "prop": "billboard", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)],
				"yaw_deg": snappedf(rad_to_deg(atan2(to_road.x, to_road.y)), 0.1), "scale": 1.0, "ground": true })
	# Trees outside the venue, in clumps.
	var area := d.terrain.area().grow(-5.0)
	var pines := []
	var broad := []
	var tries := 0
	while (pines.size() + broad.size()) / 4 < TREES and tries < TREES * 60:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var clump := 0.5 + 0.5 * sin(p.x / 120.0 + 0.7) * cos(p.y / 95.0 - 1.1)
		if rng.randf() > clump * clump or not free.call(p, 3.0) or Geometry2D.is_point_in_polygon(p, line) \
				or t.is_near_centreline(Vector3(p.x, 0, p.y), TREE_CLEAR_M):
			continue
		keep.call(p, 3.0)
		var xf := [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rng.randf() * TAU, 0.001), snappedf(rng.randf_range(0.8, 1.3), 0.001)]
		if rng.randf() < 0.55:
			pines.append_array(xf)
		else:
			broad.append_array(xf)
	d.set_scatter_live("tree_pine", pines)
	d.set_scatter_live("tree_round", broad)
