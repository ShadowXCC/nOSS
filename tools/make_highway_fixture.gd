extends SceneTree
## Writes tests/fixtures/tracks/highway_ring_small.json: a small highway loop for tests (D106,
## D107). A rounded rectangle about 4.4 km round on flat ground, 3 lanes each way; an interchange
## on each carriageway (an exit and an entry, each with its tunnel mouth, both on the south straight: direction
## 1 drives eastwards there on the loop's inside, -1 westwards on its outside), a crossover each way
## on the north straight, a tunnel on the east straight, a run and a speed trap each way.
##   tools/godot.sh --headless -s res://tools/make_highway_fixture.gd

const OUT := "res://tests/fixtures/tracks/highway_ring_small.json"
const HALF_X := 800.0
const HALF_Z := 400.0
const CORNER_R := 220.0

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_run())
	return false


func _run() -> int:
	var d := TrackFormat.blank("highway_ring_small", "Highway Ring (test)")
	d.type = "highway"
	var h: Dictionary = TrackFormat.HIGHWAY_DEFAULTS.duplicate(true)
	h.erase("zones")
	h.erase("ramps")
	h.erase("portals")
	h.erase("runs")
	h.erase("traps")
	d.highway = h
	d.road.defaults = TrackFormat.highway_road_defaults(TrackFormat.highway_settings(d))
	d.road.points = _ring()
	d.race.start_m = 0.0
	d.race.sectors_m = []
	d.ground = { "flat_y": -0.03, "surface": "concrete" }
	var t := TrackData.from_dict(d)
	var hs := TrackFormat.highway_settings(d)
	var south := _s_at(t, Vector3(0, 0, -HALF_Z))
	var north := _s_at(t, Vector3(0, 0, HALF_Z))
	var east := _s_at(t, Vector3(HALF_X, 0, 0))
	var west := _s_at(t, Vector3(-HALF_X, 0, 0))
	var ramps := []
	var portals := []
	# An interchange each way on the south straight (about 980 m of road each).
	for x: Array in [[1, south - 490.0, "harbour", "Harbour"], [-1, south + 490.0, "park", "Park"]]:
		var e := RampTemplates.interchange(t, hs, x[0], x[1], x[2], x[3])
		ramps.append_array(e.ramps)
		portals.append_array(e.portals)
	# Crossovers on the north straight (direction 1 drives westwards there, s growing).
	ramps.append(RampTemplates.crossover(t, hs, 1, north - 520.0, "mill", "Mill Flyover").ramp)
	ramps.append(RampTemplates.crossover(t, hs, -1, north + 520.0, "canal", "Canal Flyover").ramp)
	d.highway.ramps = ramps
	d.highway.portals = portals
	d.highway.zones = [{ "dir": 0, "from_m": snappedf(east - 120.0, 0.1), "to_m": snappedf(east + 120.0, 0.1), "speed_kmh": 80, "tunnel": true, "name": "East Tunnel" }]
	d.highway.runs = [
		{ "id": "south_sprint", "name": "South sprint", "dir": 1, "from_m": snappedf(fposmod(south - 300.0, t.length), 0.1), "to_m": snappedf(fposmod(east + 300.0, t.length), 0.1) },
		{ "id": "north_sprint", "name": "North sprint", "dir": -1, "from_m": snappedf(fposmod(west - 100.0, t.length), 0.1), "to_m": snappedf(fposmod(north - 300.0, t.length), 0.1) },
	]
	d.highway.traps = [{ "dir": 1, "at_m": snappedf(east, 0.1) }, { "dir": -1, "at_m": snappedf(fposmod(south + 200.0, t.length), 0.1) }]
	var err := TrackFormat.validate(d)
	if err:
		print("FAIL: " + err)
		return 1
	var check := TrackData.from_dict(d)
	if not check.highway.errors.is_empty():
		print("FAIL: " + ", ".join(check.highway.errors))
		return 1
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	print("Wrote %s: %.0f m, %d ramps" % [OUT, check.length, check.highway.ramps.size()])
	return 0


## A rounded rectangle, anticlockwise seen from above (+Y): straights every ~150 m, corners every 15°.
func _ring() -> Array:
	var pts := []
	var corners := [Vector2(HALF_X - CORNER_R, -HALF_Z + CORNER_R), Vector2(HALF_X - CORNER_R, HALF_Z - CORNER_R),
		Vector2(-HALF_X + CORNER_R, HALF_Z - CORNER_R), Vector2(-HALF_X + CORNER_R, -HALF_Z + CORNER_R)]
	var start_angles := [-PI / 2.0, 0.0, PI / 2.0, PI]
	# South straight from its middle (x = 0) eastwards, then each corner and the next straight.
	pts.append(Vector2(0, -HALF_Z))
	for c in 4:
		var from: Vector2 = pts[pts.size() - 1]
		var a0: float = start_angles[c]
		var corner_start: Vector2 = corners[c] + Vector2(cos(a0), sin(a0)) * CORNER_R
		_straight(pts, from, corner_start)
		for step in range(1, 6):
			var a := a0 + PI / 2.0 * step / 6.0
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * CORNER_R)
		var a1 := a0 + PI / 2.0
		pts.append(corners[c] + Vector2(cos(a1), sin(a1)) * CORNER_R)
	_straight(pts, pts[pts.size() - 1], Vector2(0, -HALF_Z))
	pts.pop_back() # the last point is the first
	return pts.map(func(p: Vector2) -> Dictionary: return { "p": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)] })


func _straight(pts: Array, from: Vector2, to: Vector2) -> void:
	var steps := maxi(1, roundi(from.distance_to(to) / 150.0))
	for s in range(1, steps + 1):
		pts.append(from.lerp(to, float(s) / steps))


func _s_at(t: TrackData, p: Vector3) -> float:
	return float(t.project(p).distance)
