class_name TrackTemplates
extends RefCounted
## Tracks to start from (docs/TRACK_EDITOR.md §2): an empty field, or a road ready to change,
## each on terrain sized round it, with its start, grid and sectors set; or a highway loop on
## flat ground with its ramps (EDT-10).

## [[id, name]] for menus.
static func list() -> Array:
	return [["empty", "Empty"], ["oval", "Oval (1.2 km)"], ["circuit", "Circuit (2.5 km)"], ["figure8", "Figure 8 with a bridge"],
		["highway", "Highway loop (4 km)"]]


static func make(id: String) -> TrackDraft:
	match id:
		"oval":
			var pts := []
			for k in 12:
				var a := TAU * k / 12.0
				pts.append(Vector3(250.0 * cos(a), 0.0, 110.0 * sin(a)))
			return _make("Oval", pts, 120.0)
		"circuit":
			var pts := [Vector3(-420, 0, -40), Vector3(-120, 0, -60), Vector3(180, 0, -40), Vector3(360, 0, -90),
				Vector3(460, 0, -10), Vector3(430, 0, 110), Vector3(300, 0, 150), Vector3(220, 0, 250),
				Vector3(80, 0, 290), Vector3(-30, 0, 200), Vector3(-130, 0, 260), Vector3(-280, 0, 300),
				Vector3(-420, 0, 230), Vector3(-470, 0, 90)]
			return _make("Circuit", pts, 150.0)
		"figure8":
			# Along x through the middle on the ground, back over it along z on a bridge 8 m up.
			var pts := [Vector3(-300, 0, 0), Vector3(0, 0, 0), Vector3(300, 0, 0), Vector3(300, 4, 300),
				Vector3(0, 8, 300), Vector3(0, 8, 0), Vector3(0, 8, -300), Vector3(-300, 4, -300)]
			var d := _make("Figure 8", pts, 60.0)
			for i in [3, 4, 5, 6, 7]:
				d.points()[i].height = "set"
			d.saved_version = d.history.version() # nothing to save yet
			return d
		"highway":
			return highway_loop()
	return TrackDraft.blank()


## A highway loop about 4.4 km round on flat concrete, 3 lanes each way (D106, D122): an exit and
## an entry each way on the south straight, a crossover each way on the north one, the lap line
## on the east straight. Made with the editor's own commands, then nothing to undo.
static func highway_loop() -> TrackDraft:
	var d := TrackDraft.blank("Highway loop")
	d.terrain = null
	d.layout.erase("ground")
	d.layout.ground = { "flat_y": -0.03, "surface": "concrete" }
	d.set_type("highway")
	d.layout.road.points = rounded_rect(800.0, 400.0, 220.0).map(func(p: Vector3) -> Dictionary: return { "p": TrackDraft._vec(p) })
	d._track = null
	var t := d.track()
	var at := func(p: Vector3) -> float: return float(t.project(p).distance)
	var south: float = at.call(Vector3(0, 0, -400))
	var north: float = at.call(Vector3(0, 0, 400))
	d.add_ramp("interchange", 1, south - 490.0, "Harbour")
	d.add_ramp("interchange", -1, south + 490.0, "Park")
	d.add_ramp("crossover", 1, north - 520.0, "Mill Flyover")
	d.add_ramp("crossover", -1, north + 520.0, "Canal Flyover")
	d.set_race("start_m", snappedf(at.call(Vector3(800, 0, 0)), 0.1))
	d.history = EditHistory.new()
	d.saved_version = d.history.version()
	return d


## A rectangle `half_x` by `half_z` with corners of radius `r`, anticlockwise seen from above:
## points every ~`step` m on the straights and every 15° round the corners, from the middle of
## the south side heading +x.
static func rounded_rect(half_x: float, half_z: float, r: float, step := 150.0, corner_deg := 15.0) -> Array:
	var pts: Array[Vector2] = [Vector2(0, -half_z)]
	var corners := [Vector2(half_x - r, -half_z + r), Vector2(half_x - r, half_z - r), Vector2(-half_x + r, half_z - r), Vector2(-half_x + r, -half_z + r)]
	var corner_steps := maxi(roundi(90.0 / corner_deg), 1)
	for c in 4:
		var a0 := -PI / 2.0 + c * PI / 2.0
		_straight(pts, pts[pts.size() - 1], corners[c] + Vector2(cos(a0), sin(a0)) * r, step)
		for k in range(1, corner_steps + 1):
			var a := a0 + PI / 2.0 * k / corner_steps
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * r)
	_straight(pts, pts[pts.size() - 1], Vector2(0, -half_z), step)
	pts.pop_back() # the last point is the first
	return pts.map(func(p: Vector2) -> Vector3: return Vector3(snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)))


static func _straight(pts: Array[Vector2], from: Vector2, to: Vector2, step: float) -> void:
	var steps := maxi(1, roundi(from.distance_to(to) / step))
	for k in range(1, steps + 1):
		pts.append(from.lerp(to, float(k) / steps))


## A draft with `points` (ground-following), its terrain round them, start at `start_m` and
## three even sectors.
static func _make(track_name: String, points: Array, start_m: float) -> TrackDraft:
	var box := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p: Vector3 in points:
		box = box.expand(Vector2(p.x, p.z))
	var d := TrackDraft.blank(track_name)
	d.terrain = TerrainData.around(box, 350.0)
	d.layout.road.points = points.map(func(p: Vector3) -> Dictionary: return { "p": TrackDraft._vec(p) })
	d.layout.race.start_m = start_m
	var length := d.track().length
	d.layout.race.sectors_m = [fposmod(start_m + length / 3.0, length), fposmod(start_m + length * 2.0 / 3.0, length)]
	d._track = null
	d.saved_version = d.history.version()
	return d
