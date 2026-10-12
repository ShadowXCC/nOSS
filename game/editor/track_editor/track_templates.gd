class_name TrackTemplates
extends RefCounted
## Tracks to start from (docs/TRACK_EDITOR.md §2): an empty field, or a road ready to change,
## each on terrain sized round it, with its start, grid and sectors set.

## [[id, name]] for menus.
static func list() -> Array:
	return [["empty", "Empty"], ["oval", "Oval (1.2 km)"], ["circuit", "Circuit (2.5 km)"], ["figure8", "Figure 8 with a bridge"]]


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
	return TrackDraft.blank()


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
