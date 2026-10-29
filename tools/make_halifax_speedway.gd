extends Node
## Writes content/tracks/halifax_speedway/: Halifax Speedway (D230), a 2.5-mile superspeedway on the
## real Daytona International Speedway layout under a name of its own, made with the track
## editor's own commands (TrackDraft) so the editor can open and change it.
##
## tools/data/halifax.json (tools/fetch_halifax.py) holds the tri-oval's line, its pit lane, the
## raceways round it and Lake Lloyd (OpenStreetMap, ODbL), and the ground (USGS NED, about 10 m,
## public domain). The map's line is smoothed and moved out so the line 15 ft (4.57 m) out from the
## racing surface's inner edge is 2.5 miles. Run counter-clockwise, the tri-oval frontstretch with
## pit road inside it.
##
## 18 m of racing surface banked by section: 31° in the turns, 18° all along the tri-oval
## frontstretch, 3° down the backstretch, eased between. It stands on its inner edge at the
## infield's grade: a level 10 m apron inside (the yellow line is its edge), a SAFER wall with its
## catch fence at the outside. The ground is the DEM, level over the venue and up to the top of the
## banking for a berm outside the wall, blending back into the real ground further out; Lake Lloyd
## is water in the infield, its bed cut down. Pit road inside the frontstretch, 20 boxes, 55 mph.
## The road course's infield and backstretch chicane are scenery roads in the infield (D212).
## Night under the lights; it suggests a rolling start, drafting, fuel at five times its use and
## tires at twice their wear, pack racing, a medium restrictor plate and the yellow line.
##   tools/godot.sh --headless res://tools/make_halifax_speedway.tscn [-- --out=<folder>]

const G := preload("res://tools/track_gen_util.gd")
const OUT := "res://content/tracks/halifax_speedway"
const DATA := "res://tools/data/halifax.json"
## Its infield road course's generator (loaded when building: it builds this one first).
const ROAD_COURSE := "res://tools/make_halifax_road_course.gd"
const CREATED := "2026-10-28"
const LICENSE := "ODbL-1.0"
const ATTRIBUTIONS := ["Layout © OpenStreetMap contributors (ODbL 1.0)",
	"Ground: U.S. Geological Survey, 3D Elevation Program (public domain)"]
const SOURCE := "OpenStreetMap ways 352070316, 11371365, 352067004, 352070311 and 352070309 (the oval), 119970289 (Lake Lloyd), USGS NED 1/3 arc-second"
## The line's resampling step and its smoothing (Gaussian sigma), m.
const RESAMPLE_M := 5.0
const SMOOTH_M := 12.0
## 2.5 miles, measured MEASURED_IN_M out from the racing surface's inner edge.
const MILES_M := 4023.4
const MEASURED_IN_M := 4.57
const HALF_M := 9.0
const APRON_M := 10.0
const INFIELD_RUNOFF_M := 6.0
## The SAFER wall's middle, out from the edge (its face 0.3 m off it, past a concrete strip).
const WALL_RUNOFF_M := 0.6
## Banking by section: TURN_DEG where the line's curvature over ±BANK_WINDOW_M is tighter than
## TURN_R_M, else TRI_OVAL_DEG along the frontstretch (the stretch pit road runs beside; its own
## gentle bend doesn't bank it more) and BACK_DEG down the backstretch.
const TURN_DEG := 31.0
const TRI_OVAL_DEG := 18.0
const BACK_DEG := 3.0
const TURN_R_M := 420.0
const BANK_WINDOW_M := 100.0
## The banking then eased along the track (Gaussian sigma, m): transitions of about 250 m.
const BANK_SMOOTH_M := 60.0
## Control points: RADIUS_SHARE of the tightest radius just ahead apart, within these (m).
const SPACING_MIN_M := 12.0
const SPACING_MAX_M := 45.0
const RADIUS_SHARE := 0.25
## The ground: this far round the line, its lowest point this far above the terrain's 0. Level
## at the infield's grade over the venue; outside the wall a berm at the top of the banking
## BERM_M wide, falling off over BERM_FALLOFF_M; then BLEND_M back into the real ground.
const TERRAIN_MARGIN_M := 220.0
const BASE_BELOW_M := 5.0
const BERM_M := 50.0
const BERM_FALLOFF_M := 40.0
const BLEND_M := 150.0
const DISTANCE_CELL_M := 10
## Lake Lloyd: its surface this far below the infield, its bed this far.
const LAKE_SURFACE_M := 0.5
const LAKE_BED_M := 3.0
## Pit road: 12 m, 55 mph, a box per grid slot, PIT_CLEAR_M off the paved edge, 120 m tapers.
const PIT_HALF_M := 6.0
const PIT_CLEAR_M := 3.0
const PIT_TAPER_M := 120.0
const PIT_SPEED_KMH := 88.5
const PIT_BOX_M := 16.0
## The start line at the tri-oval's apex, or far enough past pit road's entry for the grid to
## stand clear of its mouth. Three sectors, a grid of 20 side by side, rolling from GRID_ROLL_M
## further back.
const GRID_SLOTS := 20
const GRID_ROW_M := 12.0
const GRID_ROLL_M := 80.0
## Scenery: a light tower every LIGHT_EVERY_M behind the wall; stadium stands along the tri-oval
## STADIUM_M either side of the line; garages behind pit road; billboards in the turns' infield;
## campers and tents in the infield; palms and cypress outside the venue.
const LIGHT_EVERY_M := 60.0
const STADIUM_M := 560.0
const STADIUM_LENGTH_M := 200.0
const STADIUM_GAP_M := 30.0
const CAMPERS := 260
const TENTS := 40
const TREES := 1600
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
	print("Wrote %s: %.3f km (%.0f m at 15 ft), %d points, banking to %.1f°, start banked %.1f°, pit road %.0f m with %d boxes, %d props, layout %s, %d ms" % [
		out, t.length / 1000.0, measured_m(t), d.points().size(), steepest, absf(rad_to_deg(t.bank[t.index_at(t.start_m)])),
		t.pit.track.length if t.pit else 0.0, t.pit.boxes.size() if t.pit else 0, d.layout.props.items.size(), t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


## Halifax Speedway as a draft (the same every time).
static func build() -> TrackDraft:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var d := TrackDraft.blank("Halifax Speedway")
	d.id = "halifax_speedway"
	d.info.author = "nOSS contributors"
	d.info.license = LICENSE
	d.info.attributions = ATTRIBUTIONS.duplicate()
	var line := centreline(data)
	var lake := _lake(data)
	var grade := _ground(d, data.dem, line, lake)
	var front := frontstretch(line, data.pit_lane)
	var bank := _banking(line, front)
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
	var start := float(G.project(d, t, apex(line, front)).distance)
	var pit_from := float(G.project(d, t, Vector2(data.pit_lane[0][0], data.pit_lane[0][1])).distance)
	var clear := pit_from + PIT_TAPER_M + 12.0 + (GRID_SLOTS / 2) * GRID_ROW_M + 10.0
	if fposmod(start - pit_from, t.length) < clear - pit_from:
		start = fposmod(clear, t.length)
	start = snappedf(start, 0.1)
	d.set_race("start_m", start)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])
	d.set_race("grid/slots", GRID_SLOTS)
	d.set_race("grid/row_m", GRID_ROW_M)
	d.set_race("grid/stagger", 0.0)
	d.set_race("rolling_back_m", GRID_ROLL_M)
	_pits(d, d.track(), data.pit_lane)
	# The rest of the venue (D212): the road course's infield and its chicane.
	for road: Dictionary in load(ROAD_COURSE).infield_roads(d):
		d.add_road(road)
	d.layout.water = [{ "name": "Lake Lloyd", "y": snappedf(grade - LAKE_SURFACE_M, 0.01), "points": Array(lake).map(func(p: Vector2) -> Array: return [p.x, p.y]) }]
	d._track = null
	d.set_env("time", "night")
	d.set_env("floodlit", true)
	# What events that keep "Track's" race with (D207, D226, D227): a rolling start, drafting, five
	# times the fuel use and twice the tire wear (stops mostly for fuel), the AI in packs, a medium
	# plate and the yellow line.
	for rule: Array in [["start", "rolling"], ["draft", true], ["fuel_x", 5], ["tyre_x", 2], ["pack", true], ["plate", "medium"], ["yellow_line", true]]:
		d.set_rule(rule[0], rule[1])
	_props(d, d.track(), start, line, lake)
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


## The length of the line 4.57 m out from the inner edge (the 2.5 miles), m.
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


## The line's curvature (1/m) at each sample, averaged over ±BANK_WINDOW_M.
static func _turning(line: PackedVector2Array) -> PackedFloat32Array:
	var n := line.size()
	var step := _length(line) / n
	var turn := PackedFloat32Array()
	for i in n:
		var a := line[(i + 1) % n] - line[i]
		var b := line[i] - line[(i - 1 + n) % n]
		turn.append(absf(wrapf(atan2(a.y, a.x) - atan2(b.y, b.x), -PI, PI)) / step)
	var reach := int(BANK_WINDOW_M / step)
	var out := PackedFloat32Array()
	for i in n:
		var sum := 0.0
		for o in range(-reach, reach + 1):
			sum += turn[posmod(i + o, n)]
		out.append(sum / (2 * reach + 1))
	return out


## Which samples of `line` are the frontstretch (1) and which the backstretch (0), between the
## two turns: the stretch beside pit road is the front.
static func frontstretch(line: PackedVector2Array, pit_lane: Array) -> PackedByteArray:
	var k := _turning(line)
	var n := line.size()
	var straight := PackedByteArray()
	straight.resize(n)
	for i in n:
		straight[i] = 1 if k[i] < 1.0 / TURN_R_M else 0
	# The straight stretches, as runs of samples; the one nearest pit road's middle is the front.
	var mid: Array = pit_lane[pit_lane.size() / 2]
	var pit_mid := Vector2(mid[0], mid[1])
	var nearest := 0
	for i in n:
		if line[i].distance_squared_to(pit_mid) < line[nearest].distance_squared_to(pit_mid):
			nearest = i
	var front := PackedByteArray()
	front.resize(n)
	if not straight[nearest]:
		push_error("Halifax: pit road isn't beside a straight")
		return front
	for dir in [1, -1]:
		var i: int = nearest
		while straight[posmod(i, n)] and absi(i - nearest) < n:
			front[posmod(i, n)] = 1
			i += dir
	return front


## The tri-oval's apex: the frontstretch's point furthest out from the line between the two
## turns' tightest points (where the start line is).
static func apex(line: PackedVector2Array, front: PackedByteArray) -> Vector2:
	var k := _turning(line)
	var n := line.size()
	var a := 0
	for i in n:
		if k[i] > k[a]:
			a = i
	var b := -1
	for i in n:
		var apart := mini(posmod(i - a, n), posmod(a - i, n))
		if apart > n / 4 and (b < 0 or k[i] > k[b]):
			b = i
	var across := (line[b] - line[a]).normalized()
	var best := -1
	for i in n:
		if front[i] and (best < 0 or absf((line[i] - line[a]).cross(across)) > absf((line[best] - line[a]).cross(across))):
			best = i
	return line[best]


## Banking along `line` (degrees, - raises the outside): TURN_DEG in the turns, TRI_OVAL_DEG along
## the frontstretch, BACK_DEG down the backstretch, eased along the track (BANK_SMOOTH_M).
static func _banking(line: PackedVector2Array, front: PackedByteArray) -> PackedFloat32Array:
	var k := _turning(line)
	var n := line.size()
	var step := _length(line) / n
	var out := PackedFloat32Array()
	for i in n:
		out.append(-(TURN_DEG if k[i] >= 1.0 / TURN_R_M else (TRI_OVAL_DEG if front[i] else BACK_DEG)))
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


## Lake Lloyd's outline (x, z), counter-clockwise as the map has it or not.
static func _lake(data: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in data.lake:
		out.append(Vector2(p[0], p[1]))
	return out


## The ground: the DEM, level over the venue at the infield's grade (the mean of the ground inside
## the line), blending into the real ground BLEND_M past the berm; Lake Lloyd's bed cut LAKE_BED_M
## below the grade. Returns the grade.
static func _ground(d: TrackDraft, dem: Dictionary, line: PackedVector2Array, lake: PackedVector2Array) -> float:
	var box := Rect2(line[0], Vector2.ZERO)
	for p in line:
		box = box.expand(p)
	G.terrain(d, dem, box, TERRAIN_MARGIN_M, BASE_BELOW_M)
	var f := d.terrain.field
	var size: Vector2i = f.get_size()
	var origin: Vector2 = d.terrain.origin()
	var heights := f.region_get(Rect2i(Vector2i.ZERO, size))
	var inside := _inside(line, origin, size)
	var wet := _inside(lake, origin, size)
	var sum := 0.0
	var count := 0
	for k in inside.size():
		if inside[k] and not wet[k]:
			sum += heights[k]
			count += 1
	var grade := snappedf(sum / maxi(count, 1), TerrainData.HEIGHT_STEP)
	var n := line.size()
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
			if wet[k]:
				heights[k] = snappedf(grade - LAKE_BED_M, TerrainData.HEIGHT_STEP)
				continue
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


## The terrain cells inside the closed `outline` (x, z): row by row, between its crossings.
static func _inside(outline: PackedVector2Array, origin: Vector2, size: Vector2i) -> PackedByteArray:
	var inside := PackedByteArray()
	inside.resize(size.x * size.y)
	var n := outline.size()
	for z in size.y:
		var wz := origin.y + z
		var xs := PackedFloat32Array()
		for i in n:
			var a := outline[i]
			var b := outline[(i + 1) % n]
			if (a.y <= wz) != (b.y <= wz):
				xs.append(a.x + (wz - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(maxi(ceili(xs[k] - origin.x), 0), mini(floori(xs[k + 1] - origin.x), size.x - 1) + 1):
				inside[z * size.x + x] = 1
	return inside


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


## Pit road (the real one) inside the frontstretch, through the map's pit points between its
## tapers (kept PIT_CLEAR_M off the paved edge for its wall).
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

## Light towers, stadium stands, garages, billboards, campers and tents in the infield, palms and
## cypress beyond the venue.
static func _props(d: TrackDraft, t: TrackData, start: float, line: PackedVector2Array, lake: PackedVector2Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 230
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
	for piece in t.scenery: # and any scenery roads
		for i in range(0, piece.samples.size(), 3):
			var q := piece.samples[i]
			keep.call(Vector2(q.x, q.z), maxf(piece.half_l[i], piece.half_r[i]) + 3.0)
	for i in lake.size(): # and the lake's shore
		keep.call(lake[i], 6.0)
	var dry := func(p: Vector2, reach: float) -> bool:
		return not Geometry2D.is_point_in_polygon(p, lake) and free.call(p, reach)
	# Light towers behind the wall, the lamps facing the track.
	for k in int(t.length / LIGHT_EVERY_M):
		var m := fposmod(start + 30.0 + k * LIGHT_EVERY_M, t.length)
		var p := G.behind(t, m, -1.0, 2.5)
		keep.call(p, 1.0)
		var i := t.index_at(m)
		var to_road := Vector2(t.samples[i].x, t.samples[i].z) - p
		d.add_prop({ "prop": "light_tower", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)],
			"yaw_deg": snappedf(rad_to_deg(atan2(to_road.x, to_road.y)), 0.1), "scale": 1.0, "ground": true })
	# Stadium stands all along the tri-oval, behind the wall on the berm.
	for s in range(-int(STADIUM_M), int(STADIUM_M) + 1, int(STADIUM_LENGTH_M + STADIUM_GAP_M)):
		G.stand(d, t, fposmod(start + s, t.length), -1.0, STADIUM_LENGTH_M, free, keep_long, 8.0, "stadium_stand", 38.0, 34.0)
	# Garages behind pit road, along its boxes.
	var pit := t.pit
	var mid := (pit.gore_head + pit.gore_tail) / 2
	for s in [-1, 0, 1]:
		var at := clampf(pit.track.distances[mid] + s * 150.0, pit.track.distances[pit.gore_head], pit.track.distances[pit.gore_tail])
		var x := pit.track.transform_at(at, pit.width / 2.0 + 14.0)
		var p := Vector2(x.origin.x, x.origin.z)
		var fwd := Vector2(x.basis.z.x, x.basis.z.z).normalized()
		var off_road := func(q: Vector2) -> bool: return not t.is_near_centreline(Vector3(q.x, 0, q.y), HALF_M + APRON_M + 6.0)
		if free.call(p, 8.0) and off_road.call(p + fwd * 65.0) and off_road.call(p - fwd * 65.0):
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
		if dry.call(p, 5.0):
			keep.call(p, 5.0)
			var to_road := Vector2(t.samples[k].x, t.samples[k].z) - p
			d.add_prop({ "prop": "billboard", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)],
				"yaw_deg": snappedf(rad_to_deg(atan2(to_road.x, to_road.y)), 0.1), "scale": 1.0, "ground": true })
	# Campers and tents in the infield: clear of the road, its apron and run-off, pit road and the
	# lake, mostly in camps along the turns' infield.
	var infield := Rect2(line[0], Vector2.ZERO)
	for p in line:
		infield = infield.expand(p)
	var campers := []
	var tries := 0
	while campers.size() / 4 < CAMPERS and tries < CAMPERS * 80:
		tries += 1
		var p := Vector2(rng.randf_range(infield.position.x, infield.end.x), rng.randf_range(infield.position.y, infield.end.y))
		if not Geometry2D.is_point_in_polygon(p, line) or t.is_near_centreline(Vector3(p.x, 0, p.y), HALF_M + APRON_M + INFIELD_RUNOFF_M + 18.0) \
				or not dry.call(p, 6.0):
			continue
		keep.call(p, 6.0)
		campers.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rng.randf() * TAU, 0.001), 1.0])
	d.set_scatter_live("camper", campers)
	var tents := 0
	tries = 0
	while tents < TENTS and tries < TENTS * 80:
		tries += 1
		var p := Vector2(rng.randf_range(infield.position.x, infield.end.x), rng.randf_range(infield.position.y, infield.end.y))
		if not Geometry2D.is_point_in_polygon(p, line) or t.is_near_centreline(Vector3(p.x, 0, p.y), HALF_M + APRON_M + INFIELD_RUNOFF_M + 18.0) \
				or not dry.call(p, 6.0):
			continue
		keep.call(p, 6.0)
		tents += 1
		d.add_prop({ "prop": "tent", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)], "yaw_deg": snappedf(rng.randf() * 360.0, 0.1),
			"scale": 1.0, "ground": true })
	# Palms and cypress outside the venue, in clumps.
	var area := d.terrain.area().grow(-5.0)
	var palms := []
	var cypress := []
	tries = 0
	while (palms.size() + cypress.size()) / 4 < TREES and tries < TREES * 60:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var clump := 0.5 + 0.5 * sin(p.x / 110.0 + 0.3) * cos(p.y / 90.0 - 0.8)
		if rng.randf() > clump * clump or not free.call(p, 3.0) or Geometry2D.is_point_in_polygon(p, line) \
				or t.is_near_centreline(Vector3(p.x, 0, p.y), TREE_CLEAR_M):
			continue
		keep.call(p, 3.0)
		var xf := [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rng.randf() * TAU, 0.001), snappedf(rng.randf_range(0.8, 1.3), 0.001)]
		if rng.randf() < 0.6:
			palms.append_array(xf)
		else:
			cypress.append_array(xf)
	d.set_scatter_live("palm", palms)
	d.set_scatter_live("cypress", cypress)
