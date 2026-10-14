class_name TrafficTypes
extends RefCounted
## Highway traffic's vehicles (data/traffic/types.json, D108): each type's model, platform, how
## common it is, its size and how it drives in the lane sim. Read once.

const PATH := "res://data/traffic/types.json"

static var _types: Array[Dictionary] = []


## The types, in file order (the lane sim's type numbers); [] if the file is broken.
static func list() -> Array[Dictionary]:
	if _types.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary and JsonSchema.validate(data, JsonSchema.load_schema("traffic_types")).is_empty():
			for t: Dictionary in data.types:
				_types.append(t)
		else:
			push_error("Invalid traffic types: " + PATH)
	return _types


static func index_of(id: String) -> int:
	var types := list()
	for i in types.size():
		if types[i].id == id:
			return i
	return -1


## The type's paint colours.
static func colors(type: int) -> Array[Color]:
	var out: Array[Color] = []
	for c: String in list()[type].get("colors", ["#c0c0c0"]):
		out.append(Color(c))
	return out


## A lane sim for `track`'s highway: its lanes, these types, `count` cars from `seed`.
## Null (with the reason pushed) if it can't be set up.
static func sim(track: TrackData, seed: int, count: int) -> NossTraffic:
	if track == null or track.highway == null:
		return null
	var traffic := NossTraffic.new()
	var err := traffic.setup(track.highway.lane_graph(), list(), seed, count, float(track.highway.settings.traffic.exit_share))
	if err:
		push_error("Traffic: " + err)
		return null
	return traffic


## Dev: --traffic-selftest[=<track>] steps a highway's traffic 20 000 ticks (1000 s) and prints the
## lane graph's hash and the sim's checksum, so two builds (Linux and Windows) can be compared.
static func selftest(ref: String) -> String:
	var path := TrackLibrary.resolve(ref) if ref and ref != "true" else ""
	if path.is_empty():
		var highways := TrackLibrary.list(true, true, "highway")
		path = highways[0].path if not highways.is_empty() else "res://tests/fixtures/tracks/highway_ring_small.json"
	var pkg := TrackLoader.load_package(path, {}, { "terrain": false })
	if not pkg.ok() or pkg.track.highway == null:
		return "TRAFFIC_SELFTEST failed: no highway at " + path
	var traffic := sim(pkg.track, int(pkg.track.highway.settings.traffic.seed), int(pkg.track.highway.settings.traffic.count))
	if traffic == null:
		return "TRAFFIC_SELFTEST failed: setup"
	var t0 := Time.get_ticks_usec()
	traffic.step_to(20000)
	return "TRAFFIC_SELFTEST %s graph=%x sum=%x active=%d away=%d %.1f us/tick" % [pkg.track.id, traffic.graph_hash(), traffic.checksum(),
		traffic.active_count(), traffic.away_count(), (Time.get_ticks_usec() - t0) / 20000.0]
