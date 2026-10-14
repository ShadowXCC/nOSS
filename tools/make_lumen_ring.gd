extends Node
## Writes content/tracks/lumen_ring/: the Lumen Ring, the first highway (D121), made with the
## track editor's own commands (TrackDraft) so the editor can open and change it.
##
## A city ring road about 8.3 km round on flat ground, 3 lanes each way: a rectangle 2.76 by
## 1.71 km with 380 m corners (the spline tightens to about 295 m where they meet the straights). Driving +1 goes round clockwise (seen with north up, -z north):
##   North side (2 km): Harbour Gate and Old Town, an exit and an entry each way to a portal.
##   NE corner: the lap line ("Ring Line"). East side: Mill and Eastgate flyovers (+1 to -1,
##   -1 to +1). SE corner: the Cathedral Tunnel (80 km/h).
##   South side: Northgate, an exit and an entry each way, then the climb onto the Riverside
##   Viaduct (9 m), round the SW corner and down.
##   West side: Canal and Foundry flyovers, between sound walls. NW corner back to the start.
## Round it: about 600 towers 60 to 400 m out, the Lumen Tower in the middle and the Harbour
## Spire, overpasses, billboards and riverside trees. Runs: Harbour sprint, Tunnel run, Viaduct
## dash; two speed traps each way.
##   tools/godot.sh --headless res://tools/make_lumen_ring.tscn [-- --out=<folder>]

const OUT := "res://content/tracks/lumen_ring"
const HALF_X := 1380.0
const HALF_Z := 855.0
const CORNER_R := 380.0
const TOWERS := 600
const TREES := 400
## Towers stand this far from the road's line, and this far from a portal's mouth.
const TOWER_NEAR_M := 60.0
const TOWER_FAR_M := 400.0
const PORTAL_CLEAR_M := 70.0
## Tower types and their share, and how far each one's footprint reaches at scale 1.
const TOWER_MIX := [["tower_slim", 0.3, 10.0], ["tower_block", 0.3, 20.0], ["tower_wide", 0.2, 28.0], ["tower_tall", 0.2, 17.0]]

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
	var err := TrackWriter.write_folder(out, d.manifest_info().merged({ "created": "2026-10-14", "tags": ["highway", "city"], "source": "nOSS" }, true), d.files())
	if err:
		print("FAIL: " + err)
		get_tree().quit(1)
		return
	var tightest := 0.0
	var lifted := 0.0
	for k in t.samples.size():
		tightest = maxf(tightest, absf(t.curvature[k]))
		if t.samples[k].y > 3.0:
			lifted += t.samples[k].distance_to(t.samples[(k + 1) % t.samples.size()])
	print("Wrote %s: %.2f km, tightest %.0f m, viaduct %.2f km, %d ramps, %d towers, layout %s, %d ms" % [out, t.length / 1000.0, 1.0 / tightest,
		lifted / 1000.0, t.highway.ramps.size(), _count(d, "tower_"), t.layout_hash, Time.get_ticks_msec() - t0])
	get_tree().quit(0)


## The Lumen Ring as a draft (the same every time).
static func build() -> TrackDraft:
	var d := TrackDraft.blank("Lumen Ring")
	d.id = "lumen_ring"
	d.info.author = "nOSS contributors"
	d.terrain = null
	d.layout.ground = { "flat_y": -0.03, "surface": "concrete" }
	d.set_type("highway")
	d.layout.road.points = TrackTemplates.rounded_rect(HALF_X, HALF_Z, CORNER_R, 333.0, 15.0).map(func(p: Vector3) -> Dictionary: return { "p": TrackDraft._vec(p) })
	d._track = null
	_viaduct(d)
	_sound_walls(d)
	var t := d.track()
	var at := func(x: float, z: float) -> float: return snappedf(float(t.project(Vector3(x, 0, z)).distance), 0.1)
	# North side (+1 heads east): two interchanges, each an exit and an entry on both carriageways.
	d.add_ramp("interchange", 1, at.call(10, -HALF_Z), "Harbour Gate")
	d.add_ramp("interchange", -1, at.call(990, -HALF_Z), "Harbour Gate")
	d.add_ramp("interchange", 1, at.call(-990, -HALF_Z), "Old Town")
	d.add_ramp("interchange", -1, at.call(-10, -HALF_Z), "Old Town")
	# East side (+1 heads south): a flyover each way.
	d.add_ramp("crossover", 1, at.call(HALF_X, -445), "Mill Flyover")
	d.add_ramp("crossover", -1, at.call(HALF_X, 445), "Eastgate Flyover")
	# South side (+1 heads west): Northgate before the viaduct.
	d.add_ramp("interchange", 1, at.call(880, HALF_Z), "Northgate")
	d.add_ramp("interchange", -1, at.call(-100, HALF_Z), "Northgate")
	# West side (+1 heads north): a flyover each way.
	d.add_ramp("crossover", 1, at.call(-HALF_X, 445), "Canal Flyover")
	d.add_ramp("crossover", -1, at.call(-HALF_X, -445), "Foundry Flyover")
	var length := t.length
	d.set_zones([{ "dir": 0, "from_m": at.call(HALF_X, 480), "to_m": at.call(940, HALF_Z), "speed_kmh": 80.0, "tunnel": true, "name": "Cathedral Tunnel" }],
		"Add tunnel")
	d.set_runs([
		{ "id": "harbour_sprint", "name": "Harbour sprint", "dir": 1, "from_m": at.call(-1000, -HALF_Z), "to_m": at.call(1000, -HALF_Z) },
		{ "id": "tunnel_run", "name": "Tunnel run", "dir": -1, "from_m": at.call(500, HALF_Z), "to_m": snappedf(fposmod(at.call(500, HALF_Z) - 1500.0, length), 0.1) },
		{ "id": "viaduct_dash", "name": "Viaduct dash", "dir": 1, "from_m": at.call(300, HALF_Z), "to_m": snappedf(fposmod(at.call(300, HALF_Z) + 1800.0, length), 0.1) },
	], "Add runs")
	d.set_traps([{ "dir": 1, "at_m": at.call(500, -HALF_Z) }, { "dir": 1, "at_m": at.call(-600, HALF_Z) },
		{ "dir": -1, "at_m": at.call(HALF_X, 0) }, { "dir": -1, "at_m": at.call(-HALF_X, 0) }], "Add speed traps")
	d.set_highway("traffic/count", 150, "Traffic")
	d.set_highway("traffic/seed", 7, "Traffic seed")
	# The lap line ("Ring Line") a little way into the NE corner.
	var corner := Vector2(HALF_X - CORNER_R, -HALF_Z + CORNER_R)
	var lap := corner + Vector2(cos(deg_to_rad(-70.0)), sin(deg_to_rad(-70.0))) * CORNER_R
	d.set_race("start_m", at.call(lap.x, lap.y), "Lap line")
	_props(d)
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


## The Riverside Viaduct's height at (x, z): up from the middle of the south side to 9 m by
## x = -650, round the SW corner and down to the ground 75° into it.
static func _viaduct_y(x: float, z: float) -> float:
	if z > HALF_Z - CORNER_R and x > -HALF_X + CORNER_R:
		return clampf((-x - 50.0) / 600.0 * 9.0, 0.0, 9.0) # the south side
	var c := Vector2(-HALF_X + CORNER_R, HALF_Z - CORNER_R)
	if x <= c.x and z >= c.y:
		var a := rad_to_deg(Vector2(x, z).direction_to(c).angle()) + 180.0 # 90 (south side) to 180 (west)
		return 9.0 * clampf((180.0 - a) / 75.0, 0.0, 1.0)
	return 0.0


## Sets the viaduct's heights on the points it lifts.
static func _viaduct(d: TrackDraft) -> void:
	for i in d.points().size():
		var p: Array = d.points()[i].p
		var y := snappedf(_viaduct_y(float(p[0]), float(p[2])), 0.1)
		if y > 0.0:
			d.set_attr(PackedInt32Array([i]), "height", "set")
			d.move_point(i, Vector3(p[0], y, p[2]))


## Sound walls along the west side and the NW corner (houses behind them).
static func _sound_walls(d: TrackDraft) -> void:
	var idx := PackedInt32Array()
	for i in d.points().size():
		var p: Array = d.points()[i].p
		if float(p[0]) < -HALF_X + CORNER_R + 1.0 and float(p[2]) < HALF_Z - CORNER_R + 1.0:
			idx.append(i)
	d.set_attr(idx, "barrier_l", "sound_wall")
	d.set_attr(idx, "barrier_r", "sound_wall")


## The city: towers, two landmarks, overpasses, billboards and riverside trees.
static func _props(d: TrackDraft) -> void:
	var t := d.track()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var portals: Array = t.highway.portals.values().map(func(p: Dictionary) -> Vector3: return p.p)
	var boxes := t.highway.ramps.map(func(r: RampData) -> Rect2:
		var box := Rect2(r.track.samples[0].x, r.track.samples[0].z, 0, 0)
		for q in r.track.samples:
			box = box.expand(Vector2(q.x, q.z))
		return box.grow(r.width + 40.0))
	var placed := {} # Vector2i (100 m cell) -> [[Vector2, reach]]
	var free := func(p: Vector2, reach: float) -> bool:
		var cell := Vector2i(floori(p.x / 100.0), floori(p.y / 100.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for other: Array in placed.get(cell + Vector2i(dx, dz), []):
					if p.distance_to(other[0]) < reach + float(other[1]) + 6.0:
						return false
		return true
	var keep := func(p: Vector2, reach: float) -> void:
		var cell := Vector2i(floori(p.x / 100.0), floori(p.y / 100.0))
		if not placed.has(cell):
			placed[cell] = []
		placed[cell].append([p, reach])
	# Landmarks first: the Lumen Tower in the middle, the Harbour Spire north of Harbour Gate.
	d.add_prop({ "prop": "landmark_tower", "p": [0.0, 0.0, -120.0], "yaw_deg": 0.0, "scale": 1.0 })
	keep.call(Vector2(0, -120), 30.0)
	d.add_prop({ "prop": "landmark_tower", "p": [620.0, 0.0, -1330.0], "yaw_deg": 45.0, "scale": 0.7 })
	keep.call(Vector2(620, -1330), 25.0)
	# Overpasses: across the road where no ramp or flyover is.
	for spot: Vector2 in [Vector2(0, -HALF_Z), Vector2(HALF_X, 0), Vector2(-HALF_X, 0), _on_corner(0, -25.0), _on_corner(3, 225.0)]:
		var x := t.transform_at(float(t.project(Vector3(spot.x, 0, spot.y)).distance))
		var yaw := rad_to_deg(atan2(x.basis.x.x, x.basis.x.z)) - 90.0
		d.add_prop({ "prop": "overpass", "p": TrackDraft._vec(x.origin), "yaw_deg": snappedf(yaw, 0.1), "scale": 1.0, "size": [72.0, 7.5, 12.0] })
	# Towers, 60 to 400 m from the road's line, clear of ramps, portals and each other.
	var groups := {}
	var tries := 0
	var count := 0
	while count < TOWERS and tries < TOWERS * 60:
		tries += 1
		var pick := rng.randf()
		var type: Array = TOWER_MIX[TOWER_MIX.size() - 1]
		for m: Array in TOWER_MIX:
			pick -= float(m[1])
			if pick < 0.0:
				type = m
				break
		var scale := rng.randf_range(0.8, 1.3)
		var reach := float(type[2]) * scale
		var along := rng.randf() * t.length
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var x := t.transform_at(along, side * rng.randf_range(TOWER_NEAR_M + reach, TOWER_FAR_M))
		var p := Vector2(x.origin.x, x.origin.z)
		if not free.call(p, reach) or not _clear(t, portals, boxes, p, reach + 8.0, TOWER_NEAR_M + reach):
			continue
		keep.call(p, reach)
		var id := String(type[0])
		if not groups.has(id):
			groups[id] = []
		groups[id].append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rng.randf() * TAU, 0.001), snappedf(scale, 0.001)])
		count += 1
	for id: String in groups:
		d.set_scatter_live(id, groups[id])
	# Riverside trees either side of the viaduct.
	var trees := []
	tries = 0
	while trees.size() / 4 < TREES and tries < TREES * 40:
		tries += 1
		var along := rng.randf_range(float(t.project(Vector3(-200, 0, HALF_Z)).distance), float(t.project(Vector3(-HALF_X, 0, 300)).distance))
		var x := t.transform_at(along, (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(26.0, 200.0))
		var p := Vector2(x.origin.x, x.origin.z)
		if not free.call(p, 3.0) or not _clear(t, portals, boxes, p, 6.0, 26.0):
			continue
		keep.call(p, 3.0)
		trees.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rng.randf() * TAU, 0.001), snappedf(rng.randf_range(0.8, 1.3), 0.001)])
	d.set_scatter_live("tree_round", trees)
	# Billboards on the corners' outsides, facing the road.
	for c in 4:
		for a: float in [20.0, 70.0]:
			var p := _on_corner(c, -90.0 + c * 90.0 + a, CORNER_R + 48.0)
			var proj := t.project(Vector3(p.x, 0, p.y))
			var to_road := (proj.point as Vector3) - Vector3(p.x, 0, p.y)
			if not free.call(p, 4.0):
				continue
			keep.call(p, 4.0)
			d.add_prop({ "prop": "billboard", "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)], "yaw_deg": snappedf(rad_to_deg(atan2(to_road.x, to_road.z)), 0.1), "scale": 1.0 })


## A point on corner `c`'s arc (0 NE, 1 SE, 2 SW, 3 NW) at `deg` round its centre, `r` out.
static func _on_corner(c: int, deg: float, r := CORNER_R) -> Vector2:
	var centres := [Vector2(HALF_X - CORNER_R, -HALF_Z + CORNER_R), Vector2(HALF_X - CORNER_R, HALF_Z - CORNER_R),
		Vector2(-HALF_X + CORNER_R, HALF_Z - CORNER_R), Vector2(-HALF_X + CORNER_R, -HALF_Z + CORNER_R)]
	return centres[c] + Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r


## True if `p` is clear of every ramp and portal by `reach`, and `road_m` from the road's line
## (anywhere on it: a corner's inside brings the far side near).
static func _clear(t: TrackData, portals: Array, boxes: Array, p: Vector2, reach: float, road_m: float) -> bool:
	for q: Vector3 in portals:
		if Vector2(q.x, q.z).distance_to(p) < PORTAL_CLEAR_M + reach:
			return false
	var main := t.project(Vector3(p.x, 0, p.y))
	if Vector2(p.x - main.point.x, p.y - main.point.z).length() < road_m:
		return false
	for k in boxes.size():
		if not (boxes[k] as Rect2).has_point(p):
			continue
		var r := t.highway.ramps[k]
		var proj := r.track.project(Vector3(p.x, 0, p.y))
		if Vector2(p.x - proj.point.x, p.y - proj.point.z).length() < r.width / 2.0 + RampData.RUNOFF_M + reach:
			return false
	return true


static func _count(d: TrackDraft, prefix: String) -> int:
	var n := 0
	for g: Dictionary in d.layout.props.scatter:
		if String(g.prop).begins_with(prefix):
			n += (g.xf as Array).size() / 4
	return n
