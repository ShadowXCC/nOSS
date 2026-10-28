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

## Road attributes and their defaults. width_l / width_r: centreline to each edge, m. An apron
## (D202) is paved road past the edge (and its curb) at its own slope: an oval's flat inside.
const DEFAULTS := {
	"width_l": 6.0, "width_r": 6.0, "bank_deg": 0.0, "height": "ground",
	"lanes": 1, "lines": "edges", "surface": "asphalt",
	"curb_l": "auto", "curb_r": "auto",
	"runoff_l": "grass", "runoff_r": "grass", "runoff_l_m": 16.0, "runoff_r_m": 16.0,
	"barrier_l": "auto", "barrier_r": "auto",
	"apron_l_m": 0.0, "apron_r_m": 0.0, "apron_l_deg": 0.0, "apron_r_deg": 0.0,
}
## Keys new tracks leave out of their defaults until they're used, so older layouts hash the same.
const APRON_KEYS := ["apron_l_m", "apron_r_m", "apron_l_deg", "apron_r_deg"]
## Blended across a segment; the rest hold for the segment.
const BLENDED := ["width_l", "width_r", "bank_deg", "apron_l_m", "apron_r_m", "apron_l_deg", "apron_r_deg"]
const GRID := { "slots": 20, "front_m": 12.0, "row_m": 13.0, "stagger": 0.5, "pole": "left" }
const ROLLING_BACK_M := 220.0
## The AI drives carefully on its first lap until this far; -1: decided from the track.
const CAUTION_AUTO := -1.0

## Surfaces by name, as VehicleSim reads them (docs/PHYSICS.md §4).
const SURFACES := ["asphalt", "concrete", "curb", "paint", "grass", "gravel", "dirt", "sand", "snow", "ice"]
const BARRIERS := ["none", "auto", "tyres", "armco", "concrete", "fence", "sound_wall", "safer"]
const CURBS := ["auto", "on", "off"]
const LINES := ["none", "edges", "lanes", "all"]
const BARRIER_NONE := 0
const BARRIER_AUTO := 1
const BARRIER_TYRES := 2
const BARRIER_CONCRETE := 4
const BARRIER_SOUND_WALL := 6
## An oval's energy-absorbing wall with a catch fence on top (D202).
const BARRIER_SAFER := 7
const TYPES := ["circuit", "highway", "arena"]

## A highway's carriageways and traffic (type "highway", D106): lanes each way, counted from the
## outside; the median between the two directions; shoulders inside and out; the speed limit.
const HIGHWAY_DEFAULTS := {
	"drive": "right", "lanes": 3, "lane_m": 3.6, "median_m": 2.4, "shoulder_in_m": 0.8, "shoulder_out_m": 3.0,
	"median_barrier": "concrete", "speed_kmh": 110.0,
	"zones": [], "ramps": [], "portals": [], "runs": [], "traps": [],
	"traffic": { "count": 150, "exit_share": 0.15, "seed": 1 },
}
const RAMP_DEFAULTS := { "name": "", "lanes": 1, "lane_m": 3.6, "taper_m": 200.0, "speed_kmh": 70.0, "traffic": true, "points": [] }
## The road's own run-off on a highway: a concrete strip to the barrier.
const HIGHWAY_RUNOFF_M := 0.6


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


## The road defaults a new track starts with: DEFAULTS without the apron.
static func base_defaults() -> Dictionary:
	var d := DEFAULTS.duplicate()
	for key: String in APRON_KEYS:
		d.erase(key)
	return d


## An empty v1 track (no points yet) with every section present.
static func blank(id: String, name: String) -> Dictionary:
	return {
		"schema": SCHEMA, "id": id, "name": name, "type": "circuit", "style": StyleProfile.DEFAULT,
		"road": { "mode": "road", "defaults": base_defaults(), "points": [] },
		"race": { "start_m": 0.0, "sectors_m": [], "checkpoint_spacing_m": 100.0, "grid": GRID.duplicate(),
			"rolling_back_m": ROLLING_BACK_M, "gantry": true, "ai": { "caution_until_m": CAUTION_AUTO, "pins": [] } },
		"ground": { "flat_y": -0.03, "surface": "grass" },
		"props": { "items": [], "scatter": [] },
		"environment": {},
		"scene": null,
	}


## A track's highway section with every default filled in ({} if it isn't a highway).
static func highway_settings(d: Dictionary) -> Dictionary:
	if d.get("type", "circuit") != "highway":
		return {}
	var h: Dictionary = HIGHWAY_DEFAULTS.duplicate(true)
	var own: Dictionary = d.get("highway", {})
	for key: String in own:
		h[key] = own[key].duplicate(true) if own[key] is Dictionary or own[key] is Array else own[key]
	var traffic: Dictionary = HIGHWAY_DEFAULTS.traffic.duplicate()
	traffic.merge(own.get("traffic", {}), true)
	h.traffic = traffic
	var ramps := []
	for r: Dictionary in h.ramps:
		var full: Dictionary = RAMP_DEFAULTS.duplicate(true)
		full.merge(r, true)
		ramps.append(full)
	h.ramps = ramps
	return h


## Centreline to each outer edge of a highway: half the median, the inner shoulder, the lanes,
## the outer shoulder.
static func highway_half(h: Dictionary) -> float:
	return float(h.median_m) / 2.0 + float(h.shoulder_in_m) + int(h.lanes) * float(h.lane_m) + float(h.shoulder_out_m)


## The road defaults a highway's carriageways need: both widths to the outer edge, no curbs, a
## concrete strip to a concrete barrier; the highway draws its own lines.
static func highway_road_defaults(h: Dictionary, defaults := {}) -> Dictionary:
	var out: Dictionary = base_defaults()
	out.merge(defaults, true)
	var half := highway_half(h)
	out.width_l = half
	out.width_r = half
	out.bank_deg = 0.0
	out.lanes = int(h.lanes)
	out.lines = "none"
	out.curb_l = "off"
	out.curb_r = "off"
	for side in ["l", "r"]:
		out["runoff_" + side] = "concrete"
		out["runoff_%s_m" % side] = HIGHWAY_RUNOFF_M
		if out["barrier_" + side] in ["auto", "tyres", "none"]:
			out["barrier_" + side] = "concrete"
	return out


## Problems the schema can't see in a highway section ("" if none): ramp ends that don't fit
## their kind, unknown or duplicate portals and ids.
static func validate_highway(d: Dictionary) -> String:
	if d.get("type", "circuit") != "highway":
		return "" if not d.has("highway") else "$.highway: only on highway tracks"
	var h: Dictionary = d.get("highway", {})
	var portals := {}
	for p: Dictionary in h.get("portals", []):
		if portals.has(p.id):
			return "$.highway.portals: %s twice" % p.id
		portals[p.id] = true
	var ids := {}
	var used := {}
	for r: Dictionary in h.get("ramps", []):
		if ids.has(r.id):
			return "$.highway.ramps: %s twice" % r.id
		ids[r.id] = true
		for e: Dictionary in [r.from, r.to]:
			if e.has("portal"):
				if used.has(e.portal):
					return "$.highway.portals: %s serves two ramps" % e.portal
				used[e.portal] = true
		var ends := { "from": r.from, "to": r.to }
		for key: String in ends:
			var e: Dictionary = ends[key]
			var on_road := e.has("dir") and e.has("at_m")
			if on_road == e.has("portal"):
				return "$.highway.ramps.%s.%s: a road end (dir, at_m) or a portal" % [r.id, key]
			if e.has("portal") and not portals.has(e.portal):
				return "$.highway.ramps.%s.%s: no portal %s" % [r.id, key, e.portal]
		var want: Array = { "exit": [true, false], "entry": [false, true], "link": [true, true] }[r.kind]
		if [r.from.has("dir"), r.to.has("dir")] != want:
			return "$.highway.ramps.%s: an %s goes %s" % [r.id, r.kind, { "exit": "from the road to a portal", "entry": "from a portal to the road", "link": "from the road to the road" }[r.kind]]
	var runs := {}
	for run: Dictionary in h.get("runs", []):
		if runs.has(run.id):
			return "$.highway.runs: %s twice" % run.id
		runs[run.id] = true
	return ""


## Problems the schema can't see in the kart and arena sections ("" if none, D136-D138): stunts
## along the road on circuits and anywhere in arenas, kinds that fit, unique ids, at most
## KartLayout.MAX_BOXES item boxes.
static func validate_kart(d: Dictionary) -> String:
	var type := String(d.get("type", "circuit"))
	if d.has("arena") and type != "arena":
		return "$.arena: only on arena tracks"
	if d.has("kart") and type == "highway":
		return "$.kart: not on highways"
	var ids := {}
	var boxes := 0
	for p: Dictionary in d.get("kart", {}).get("stunts", []):
		var where := "$.kart.stunts.%s" % p.id
		if ids.has(p.id):
			return where + ": twice"
		ids[p.id] = true
		if type == "arena":
			if not p.has("p") or p.has("at_m"):
				return where + ": in an arena a piece has p, not at_m"
			if not p.kind in KartLayout.ARENA_KINDS:
				return where + ": a %s needs a road" % p.kind
		elif not p.has("at_m") or p.has("p"):
			return where + ": on a road a piece has at_m, not p"
		if p.kind == "item_row":
			boxes += int(p.count) if int(p.get("count", 0)) > 0 else 5
	for b: Dictionary in d.get("arena", {}).get("boxes", []):
		boxes += int(b.get("count", ArenaLayout.CLUSTER_BOXES))
	if boxes > KartLayout.MAX_BOXES:
		return "$.kart: more than %d item boxes" % KartLayout.MAX_BOXES
	return ""


## Problems the schema can't see in a pit lane ("" if none, D203): circuits only, and its ends
## apart.
static func validate_pit(d: Dictionary) -> String:
	if not d.has("pit"):
		return ""
	if d.get("type", "circuit") != "circuit":
		return "$.pit: only on circuits"
	var pit: Dictionary = d.pit
	if is_equal_approx(float(pit.from_m), float(pit.to_m)):
		return "$.pit: from_m and to_m are the same place"
	return ""


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
	var highway := validate_highway(d)
	if highway:
		return highway
	var kart := validate_kart(d)
	if kart:
		return kart
	var pit := validate_pit(d)
	if pit:
		return pit
	for group: Dictionary in d.get("props", {}).get("scatter", []):
		var xf: Array = group.xf
		if xf.size() % 4 != 0:
			return "$.props.scatter: xf must hold x, z, yaw, scale per instance"
		for v: Variant in xf:
			if not (v is float or v is int) or not is_finite(float(v)) or absf(float(v)) > 100000.0:
				return "$.props.scatter: not a number in xf"
	return ""


## A track's layout identity: its road and race setup (AI pins left out), so editing props or
## paint keeps lap records while moving a corner doesn't. A highway's carriageways and ramps
## count too (its traffic doesn't), and so do kart pieces, an arena, a pit lane, scenery roads
## (cars can drive them) and water (it sends cars back, D224); tracks without them hash as they
## always did.
static func layout_hash(d: Dictionary) -> String:
	var race: Dictionary = d.get("race", {}).duplicate(true)
	if race.get("ai") is Dictionary:
		(race.ai as Dictionary).erase("pins")
	var layout := { "road": d.get("road", {}), "race": race }
	if d.get("highway") is Dictionary:
		var h: Dictionary = (d.highway as Dictionary).duplicate(true)
		h.erase("traffic")
		layout.highway = h
	for key in ["kart", "arena", "pit"]:
		if d.get(key) is Dictionary:
			layout[key] = d[key]
	if d.get("roads") is Array and not (d.roads as Array).is_empty():
		layout.roads = d.roads
	if d.get("water") is Array and not (d.water as Array).is_empty():
		layout.water = d.water
	if d.get("type") == "arena":
		layout.type = "arena"
	# Through JSON first: numbers come back as floats, as they do from a file, so a draft (16) and
	# its saved track (16.0) hash the same.
	var key := PackageWriter.canonical_json(JSON.parse_string(JSON.stringify(layout)))
	return "sha256:" + PlatformLoader.sha256_hex(key.to_utf8_buffer())
