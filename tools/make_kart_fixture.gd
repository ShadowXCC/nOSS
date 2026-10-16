extends Node
## Writes the kart test fixtures (D136-D138):
##   tests/fixtures/tracks/kart_small.json: a 1.2 km rounded rectangle on flat ground with one of
##   every piece: a boost pad and an item row and a jump on the south straight (the start is
##   there too), a wall-ride round the outside of the south-east corner, the loop in the middle of
##   the north straight, more item rows on the north and west straights.
##   tests/fixtures/tracks/arena_small.json: a 100 x 80 m arena with rounded corners, a boost
##   pad and a jump; automatic spawns and box clusters.
##   tools/godot.sh --headless res://tools/make_kart_fixture.tscn

const KART_OUT := "res://tests/fixtures/tracks/kart_small.json"
const ARENA_OUT := "res://tests/fixtures/tracks/arena_small.json"


func _ready() -> void:
	(func() -> void: get_tree().quit(_run())).call_deferred()


func _run() -> int:
	var kart := _kart_small()
	var arena := _arena_small()
	for out: Array in [[KART_OUT, kart], [ARENA_OUT, arena]]:
		var err := TrackFormat.validate(out[1])
		if err:
			push_error("%s: %s" % [out[0], err])
			return 1
		var f := FileAccess.open(out[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(out[1], "  ", false) + "\n")
		f.close()
		print("Wrote ", out[0])
	return 0


func _kart_small() -> Dictionary:
	var d := TrackFormat.blank("kart_small", "Kart Small (test)")
	d.road.points = _points(TrackTemplates.rounded_rect(220.0, 100.0, 55.0, 60.0))
	d.ground = { "flat_y": -0.03, "surface": "grass" }
	var t := TrackData.from_dict(d)
	var at := func(p: Vector3) -> float: return snappedf(float(t.project(p).distance), 0.1)
	d.race.start_m = at.call(Vector3(60, 0, -100))
	d.race.grid.slots = 12
	d.kart = { "boxes": "auto", "stunts": [
		{ "id": "pad_1", "kind": "boost_pad", "at_m": at.call(Vector3(80, 0, -100)), "lateral_m": 0.0 },
		{ "id": "row_1", "kind": "item_row", "at_m": at.call(Vector3(100, 0, -100)) },
		{ "id": "jump_1", "kind": "jump", "at_m": at.call(Vector3(122, 0, -100)), "height_m": 1.2, "length_m": 8.0 },
		{ "id": "wall_1", "kind": "wall_ride", "at_m": at.call(Vector3(168, 0, -99)), "length_m": 90.0, "side": "left", "height_m": 5.0 },
		{ "id": "loop_1", "kind": "loop", "at_m": at.call(Vector3(0, 0, 100)), "radius_m": 9.0, "width_m": 5.0 },
		{ "id": "row_2", "kind": "item_row", "at_m": at.call(Vector3(120, 0, 100)) },
		{ "id": "row_3", "kind": "item_row", "at_m": at.call(Vector3(-220, 0, 0)) },
	] }
	return d


func _arena_small() -> Dictionary:
	var d := TrackFormat.blank("arena_small", "Arena Small (test)")
	d.type = "arena"
	d.road.points = _points(TrackTemplates.rounded_rect(50.0, 40.0, 12.0, 25.0, 30.0))
	d.ground = { "flat_y": -0.03, "surface": "grass" }
	d.race.gantry = false
	d.arena = { "floor": "asphalt", "wall": "tyres" }
	d.kart = { "stunts": [
		{ "id": "pad_1", "kind": "boost_pad", "p": [0.0, 0.0, -20.0], "yaw_deg": 90.0 },
		{ "id": "jump_1", "kind": "jump", "p": [22.0, 0.0, 6.0], "yaw_deg": 0.0, "height_m": 1.0, "length_m": 7.0, "width_m": 5.0 },
	] }
	return d


func _points(pts: Array) -> Array:
	return pts.map(func(p: Vector3) -> Dictionary: return { "p": [p.x, p.y, p.z] })
