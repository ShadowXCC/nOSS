class_name EndlessBiomes
extends RefCounted
## How the endless biomes look and sound (D156): data/endless/biomes/<id>.json, by NossRoadGen's
## order. Their roads and ground are native (D152).

const DIR := "res://data/endless/biomes/"

static var _all: Array = []


## Every biome's data, in NossRoadGen.biome_ids() order.
static func all() -> Array:
	if _all.is_empty():
		for id: String in NossRoadGen.biome_ids():
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + id + ".json"))
			_all.append(d if d is Dictionary else { "id": id, "name": id.capitalize(), "far_color": "#6f8f52", "scatter": [] })
	return _all


static func of(index: int) -> Dictionary:
	var a := all()
	return a[clampi(index, 0, a.size() - 1)]


static func index_of(id: String) -> int:
	return maxi(Array(NossRoadGen.biome_ids()).find(id), 0)


## A biome's data by id; {} for none or an unknown one (a track's setting, D221).
static func find(id: String) -> Dictionary:
	var i := Array(NossRoadGen.biome_ids()).find(id)
	return of(i) if i >= 0 else {}


static func name_of(index: int) -> String:
	return String(of(index).get("name", ""))


## [[index, name]] for menus.
static func choices() -> Array:
	var out := []
	for i in all().size():
		out.append([i, name_of(i)])
	return out
