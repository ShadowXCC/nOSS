class_name TrackFormat
extends RefCounted
## The track file, noss.track/1 (docs/TRACK_EDITOR.md §5, D92): the road (control points with
## per-point overrides of the road's defaults), race setup, ground, props and environment.
## noss.track/0 files (the Proving Ground before the editor) are upgraded in memory.
##
## A point stores only what differs from road.defaults. Widths and banking blend across a
## segment (smoothstep); the other attributes hold for the segment that starts at the point.
## Distances (start, sectors, pins) are metres from point 0, in driving order.

const SCHEMA := "noss.track/1"
const LEGACY := "noss.track/0"

## Road attributes and their defaults. width_l / width_r: centreline to each edge, m.
const DEFAULTS := {
	"width_l": 6.0, "width_r": 6.0, "bank_deg": 0.0, "height": "ground",
	"lanes": 1, "lines": "edges", "surface": "asphalt",
	"curb_l": "auto", "curb_r": "auto",
	"runoff_l": "grass", "runoff_r": "grass", "runoff_l_m": 16.0, "runoff_r_m": 16.0,
	"barrier_l": "auto", "barrier_r": "auto",
}
## Blended across a segment; the rest hold for the segment.
const BLENDED := ["width_l", "width_r", "bank_deg"]
const GRID := { "slots": 20, "front_m": 12.0, "row_m": 13.0, "stagger": 0.5, "pole": "left" }
const ROLLING_BACK_M := 220.0
## The AI drives carefully on its first lap until this far; -1: decided from the track.
const CAUTION_AUTO := -1.0

## Surfaces by name, as VehicleSim reads them (docs/PHYSICS.md §4).
const SURFACES := ["asphalt", "concrete", "curb", "paint", "grass", "gravel", "dirt", "sand", "snow", "ice"]
const BARRIERS := ["none", "auto", "tyres", "armco", "concrete", "fence"]
const CURBS := ["auto", "on", "off"]
const LINES := ["none", "edges", "lanes", "all"]
const BARRIER_NONE := 0
const BARRIER_AUTO := 1
const BARRIER_TYRES := 2


## A VehicleSim surface id by name (asphalt if unknown).
static func surface_id(name: String) -> int:
	return maxi(SURFACES.find(name), 0)


static func barrier_id(name: String) -> int:
	return maxi(BARRIERS.find(name), 0)


## `key` at control point `i`: its own value, else the road's default, else DEFAULTS.
static func attr(road: Dictionary, i: int, key: String) -> Variant:
	var points: Array = road.get("points", [])
	var p: Dictionary = points[posmod(i, points.size())] if not points.is_empty() else {}
	if p.has(key):
		return p[key]
	return road.get("defaults", {}).get(key, DEFAULTS[key])


## An empty v1 track (no points yet) with every section present.
static func blank(id: String, name: String) -> Dictionary:
	return {
		"schema": SCHEMA, "id": id, "name": name, "type": "circuit", "style": StyleProfile.DEFAULT,
		"road": { "mode": "road", "defaults": DEFAULTS.duplicate(), "points": [] },
		"race": { "start_m": 0.0, "sectors_m": [], "checkpoint_spacing_m": 100.0, "grid": GRID.duplicate(),
			"rolling_back_m": ROLLING_BACK_M, "gantry": true, "ai": { "caution_until_m": CAUTION_AUTO, "pins": [] } },
		"ground": { "flat_y": -0.03, "surface": "grass" },
		"props": { "items": [], "scatter": [] },
		"environment": {},
		"scene": null,
	}


## A noss.track/0 file as noss.track/1: the same centreline (points [x, z(, y)] become set
## heights), one width, its start, sectors and checkpoints, the race grid and AI caution the
## game used then, flat grass, and its set pieces as props where they stood.
static func upgrade_v0(d: Dictionary) -> Dictionary:
	var out := blank(String(d.get("id", "")), String(d.get("name", d.get("id", ""))))
	out.style = String(d.get("style", StyleProfile.DEFAULT))
	for key in ["author", "license"]:
		if d.has(key):
			out[key] = d[key]
	var half := float(d.get("width_m", 12.0)) / 2.0
	var defaults: Dictionary = out.road.defaults
	defaults.width_l = half
	defaults.width_r = half
	defaults.height = "set"
	var points := []
	for p: Array in d.get("points", []):
		points.append({ "p": [float(p[0]), float(p[2]) if p.size() > 2 else 0.0, float(p[1])] })
	out.road.points = points
	var race: Dictionary = out.race
	race.start_m = float(d.get("start_m", 0.0))
	race.sectors_m = d.get("sectors_m", []).map(func(s: Variant) -> float: return float(s))
	race.checkpoint_spacing_m = float(d.get("checkpoint_spacing_m", 100.0))
	race.ai.caution_until_m = 1100.0 # tuned for the Proving Ground
	out.props = _v0_props(d, out)
	return out


## A noss.track/0 file's set pieces as props, where its builder put them: the skidpad, the
## grandstand and pit building beside the road, and its 1400 seeded trees (billboards).
static func _v0_props(v0: Dictionary, v1: Dictionary) -> Dictionary:
	var t := TrackData.from_dict(v1)
	var items := []
	var pad: Dictionary = v0.get("skidpad", {})
	if not pad.is_empty():
		items.append({ "prop": "skidpad", "p": [float(pad.center[0]), 0.0, float(pad.center[1])],
			"size": [float(pad.get("pad_radius_m", 72.0)), 0.0, float(pad.get("radius_m", 60.0))] })
	for key in ["grandstand", "pit_building"]:
		var g: Dictionary = v0.get(key, {})
		if g.is_empty():
			continue
		var side := 1.0 if g.get("side", "left" if key == "grandstand" else "right") == "left" else -1.0
		var x := t.transform_at(float(g.at_m))
		var away := x.basis.x * side
		var at := x.origin + away * (t.width / 2.0 + (14.0 if key == "grandstand" else 26.0))
		var length := float(g.get("length_m", 100.0 if key == "grandstand" else 120.0))
		items.append({ "prop": key, "p": [at.x, at.y, at.z], "yaw_deg": rad_to_deg(atan2(-away.z, away.x)),
			"size": [13.0 if key == "grandstand" else 12.0, 9.9 if key == "grandstand" else 9.0, length] })
	# The trees, exactly as the first builder threw them.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t.id)
	var bounds := AABB(t.samples[0], Vector3.ZERO)
	for p in t.samples:
		bounds = bounds.expand(p)
	bounds = bounds.grow(400.0)
	var pad_c := Vector3(pad.center[0], 0, pad.center[1]) if not pad.is_empty() else Vector3(INF, 0, INF)
	var pad_r: float = pad.get("pad_radius_m", 0.0) + 15.0
	var xf := []
	var tries := 0
	while xf.size() < 1400 * 4 and tries < 1400 * 20:
		tries += 1
		var p := Vector3(rng.randf_range(bounds.position.x, bounds.end.x), 0, rng.randf_range(bounds.position.z, bounds.end.z))
		if p.distance_to(pad_c) < pad_r or t.is_near_centreline(p, t.width / 2.0 + 16.0 + 12.0):
			continue
		xf.append_array([snappedf(p.x, 0.01), snappedf(p.z, 0.01), 0.0, snappedf(rng.randf_range(7.0, 13.0), 0.01)])
	return { "items": items, "scatter": [{ "prop": "tree_billboard", "xf": xf }] if not xf.is_empty() else [] }


## Schema errors for a v1 track ("" if none). Scatter arrays are checked here rather than by
## the schema (they can hold hundreds of thousands of numbers).
static func validate(d: Dictionary) -> String:
	var errors := JsonSchema.validate(d, JsonSchema.load_schema("track"))
	if not errors.is_empty():
		return errors[0]
	for group: Dictionary in d.get("props", {}).get("scatter", []):
		var xf: Array = group.xf
		if xf.size() % 4 != 0:
			return "$.props.scatter: xf must hold x, z, yaw, scale per instance"
		for v: Variant in xf:
			if not (v is float or v is int) or not is_finite(float(v)) or absf(float(v)) > 100000.0:
				return "$.props.scatter: not a number in xf"
	return ""


## A track's layout identity: its road and race setup (AI pins left out), so editing props or
## paint keeps lap records while moving a corner doesn't.
static func layout_hash(d: Dictionary) -> String:
	var race: Dictionary = d.get("race", {}).duplicate(true)
	if race.get("ai") is Dictionary:
		(race.ai as Dictionary).erase("pins")
	# Through JSON first: numbers come back as floats, as they do from a file, so a draft (16) and
	# its saved track (16.0) hash the same.
	var key := PackageWriter.canonical_json(JSON.parse_string(JSON.stringify({ "road": d.get("road", {}), "race": race })))
	return "sha256:" + PlatformLoader.sha256_hex(key.to_utf8_buffer())
