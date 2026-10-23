class_name TrackDraft
extends RefCounted
## The track being edited (EDT-01…EDT-07): its layout (track.json), terrain, name and license, and
## its undo history. Every change goes through a command here, so the editor's tools, undo and
## the headless checks share one path. `changed` tells the preview what to rebuild:
##   road (info.segments: the control segments touched; none: all), race, props, scatter,
##   terrain (info.rect, samples), paint (info.rect), scene (its tags), info, all, and highway
##   (info.ramps: the ramps' ids touched; none: all).

signal changed(what: StringName, info: Dictionary)

## Left and right swap places when the track is driven the other way.
const SIDES := { "width_l": "width_r", "width_r": "width_l", "curb_l": "curb_r", "curb_r": "curb_l", "runoff_l": "runoff_r",
	"runoff_r": "runoff_l", "runoff_l_m": "runoff_r_m", "runoff_r_m": "runoff_l_m", "barrier_l": "barrier_r", "barrier_r": "barrier_l",
	"apron_l_m": "apron_r_m", "apron_r_m": "apron_l_m", "apron_l_deg": "apron_r_deg", "apron_r_deg": "apron_l_deg" }
## Slopes that change sign when the road is driven the other way (+ raises the left).
const SLOPES := ["bank_deg", "apron_l_deg", "apron_r_deg"]
## ODbL: tracks made from OpenStreetMap data (the Eifel GP, D200) and copies of them.
const LICENSES := [["CC-BY-SA-4.0", "CC BY-SA 4.0"], ["CC-BY-4.0", "CC BY 4.0"], ["CC0-1.0", "CC0 (public domain)"], ["ODbL-1.0", "ODbL 1.0 (map data)"],
	["personal-use-only", "Personal use only"]]
const AUTOSAVE := ".autosave"

var id := ""
## name, author, license, attributions (the manifest's).
var info := {}
var layout := {}
var terrain: TerrainData
## A track made from a 3D scene (Track Fitting): the scene is the road and the ground.
var scene: SceneTrack
## The library file it was opened from or saved to ("" until its first save).
var path := ""
var history := EditHistory.new()
## The editor's state while it's away (a test drive): camera, tool, selection.
var view := {}
## Rendered by the editor when it saves: thumb.png, minimap.png.
var images := {}
var saved_version := 0
var _track: TrackData


## A new, empty track on flat ground, `chunks` × 256 m of terrain around the origin.
static func blank(track_name := "New track", chunks := Vector2i(4, 4)) -> TrackDraft:
	var d := TrackDraft.new()
	d.id = PackageWriter.new_uuid()
	d.info = { "name": track_name, "author": _author(), "license": "CC-BY-SA-4.0", "attributions": [] }
	d.layout = TrackFormat.blank(d.id, track_name)
	d.layout.ground = { "terrain": "terrain/meta.json" }
	d.terrain = TerrainData.create(-Vector2(chunks) * TerrainData.CHUNK / 2.0, chunks)
	d.saved_version = d.history.version()
	return d


## An editable copy of a loaded track. A built-in track becomes a copy of its own.
static func from_package(pkg: TrackPackage) -> TrackDraft:
	var d := TrackDraft.new()
	d.layout = pkg.layout.duplicate(true)
	d.terrain = pkg.terrain
	d.scene = pkg.scene
	var m := pkg.manifest
	if pkg.builtin() or m.is_empty():
		d.id = PackageWriter.new_uuid()
		d.info = { "name": "%s copy" % pkg.display_name(), "author": _author(), "license": String(m.get("license", "CC-BY-SA-4.0")), "attributions": m.get("attributions", []).duplicate() }
	else:
		d.id = String(m.id)
		d.info = { "name": String(m.name), "author": String(m.author), "license": String(m.license), "attributions": m.get("attributions", []).duplicate() }
		d.path = pkg.path if pkg.path.ends_with(".nosstrack") else ""
	d.layout.id = d.id
	d.layout.name = d.info.name
	for image: Array in [["thumb.png", pkg.thumb], ["minimap.png", pkg.minimap]]:
		if not (image[1] as PackedByteArray).is_empty():
			d.images[image[0]] = image[1]
	d.saved_version = d.history.version()
	return d


## A new track on an imported scene (ModelImport with SceneTrack.LIMITS, then SceneTrack): no
## road yet. Its points go on the scene's road ("centreline" mode). `source`: the file it came from.
static func from_import(scene_track: SceneTrack, source: String, track_name := "") -> TrackDraft:
	var d := TrackDraft.new()
	d.scene = scene_track
	d.id = PackageWriter.new_uuid()
	var name := track_name if track_name else source.get_file().get_basename().capitalize()
	d.info = { "name": name, "author": _author(), "license": "CC-BY-SA-4.0", "attributions": [] }
	d.layout = TrackFormat.blank(d.id, name)
	d.layout.road.mode = "centreline"
	d.layout.road.defaults.merge({ "height": "set", "curb_l": "off", "curb_r": "off", "barrier_l": "none", "barrier_r": "none",
		"runoff_l_m": 0.0, "runoff_r_m": 0.0, "lines": "none" }, true)
	d.layout.ground = { "flat_y": snappedf(d.scene.bounds.position.y - 1.0, 0.01), "surface": "grass" }
	d.layout.race.gantry = false
	d.layout.scene = { "glb": "scene/scene.glb", "tags": "scene/tags.json" }
	d.saved_version = d.history.version()
	return d


static func _author() -> String:
	var name := String(Settings.profile.get("name", "")) if Settings.profile else ""
	return name if name else "Unknown"


## The track as driven now (resampled after changes to the road, race setup or ground).
func track() -> TrackData:
	if _track == null:
		_track = TrackData.from_dict(layout, terrain.ground_height() if terrain else Callable())
	return _track


## Unsaved changes.
func dirty() -> bool:
	return history.version() != saved_version


func points() -> Array:
	return layout.road.points


# --- commands -----------------------------------------------------------------------------


## Puts a point at `index` (it becomes that point; the rest move up). `attrs` are its overrides.
func add_point(index: int, p: Vector3, attrs := {}) -> void:
	_edit("Add point", "road", func() -> void:
		var point := attrs.duplicate(true)
		point.p = _vec(p)
		points().insert(clampi(index, 0, points().size()), point), &"road")


func move_point(i: int, p: Vector3) -> void:
	if i < 0 or i >= points().size():
		return
	_edit("Move point", "road", func() -> void: points()[i].p = _vec(p), &"road", { "segments": _around(i) })


## Moves without recording (while dragging); commit with end_move().
func drag_point(i: int, p: Vector3) -> void:
	if i < 0 or i >= points().size():
		return
	if not _dragging.has("road"):
		_dragging.road = layout.road.duplicate(true)
		_dragging.segments = PackedInt32Array()
	points()[i].p = _vec(p)
	var touched: PackedInt32Array = _dragging.segments
	for s in _around(i):
		if s not in touched:
			touched.append(s)
	_dragging.segments = touched
	_changed(&"road", { "segments": _around(i), "live": true })


## Records a drag (drag_point) as one move.
func end_move(name := "Move point") -> void:
	if not _dragging.has("road"):
		return
	var before := { "road": _dragging.road }
	var segments: PackedInt32Array = _dragging.get("segments", PackedInt32Array())
	_dragging.erase("road")
	_dragging.erase("segments")
	var after := { "road": layout.road.duplicate(true) }
	history.act(name, _set_section.bind("road", after, &"road"), _set_section.bind("road", before, &"road"), false)
	_changed(&"road", { "segments": segments } if not segments.is_empty() else {})


func delete_point(i: int) -> void:
	if i < 0 or i >= points().size():
		return
	_edit("Delete point", "road", func() -> void: points().remove_at(i), &"road")


## Sets `key` on `indices` (null: back to the road's default).
func set_attr(indices: PackedInt32Array, key: String, value: Variant) -> void:
	_edit("Set " + key.replace("_", " "), "road", func() -> void:
		for i in indices:
			if i < 0 or i >= points().size():
				continue
			if value == null:
				(points()[i] as Dictionary).erase(key)
			else:
				points()[i][key] = value, &"road")


## The road's default for `key`, which every point without its own value follows.
func set_default(key: String, value: Variant) -> void:
	_edit("Set " + key.replace("_", " "), "road", func() -> void: layout.road.defaults[key] = value, &"road")


## Copies point `from`'s value of `key` to every point (they all follow the default after).
func copy_to_all(key: String, value: Variant) -> void:
	_edit("Copy to all points", "road", func() -> void:
		layout.road.defaults[key] = value
		for p: Dictionary in points():
			p.erase(key), &"road")


## Every point takes `values` ({key: value}): they become the road's defaults, points' own go.
func use_everywhere(values: Dictionary) -> void:
	_edit("Use these everywhere", "road", func() -> void:
		for key: String in values:
			layout.road.defaults[key] = values[key]
			for p: Dictionary in points():
				p.erase(key), &"road")


## Drives the other way round: points reversed, start, sectors and pins mirrored.
func flip_direction() -> void:
	var t := track()
	var length := t.length
	# Distances run from point 0; reversed, they run back from the last point.
	var last_at := t.distances[t.seg_first[t.seg_first.size() - 1]] if t.seg_first.size() > 0 else 0.0
	var mirror := func(d: float) -> float: return fposmod(last_at - d, length) if length > 0.0 else d
	_edit("Flip direction", "all", func() -> void:
		var pts := points()
		pts.reverse()
		# The segment attributes belong to the segment's start point: after the turn round they
		# go with the point that now starts that segment.
		var keys := ["surface", "lanes", "lines", "curb_l", "curb_r", "runoff_l", "runoff_r", "runoff_l_m", "runoff_r_m", "barrier_l", "barrier_r"]
		var held := pts.map(func(p: Dictionary) -> Dictionary:
			var o := {}
			for k: String in keys:
				if p.has(k):
					o[k] = p[k]
					p.erase(k)
			return o)
		for i in pts.size():
			var from: Dictionary = held[(i + 1) % pts.size()]
			for k: String in from:
				pts[i][String(SIDES.get(k, k))] = from[k] # left is right now
			for pair: Array in [["width_l", "width_r"], ["apron_l_m", "apron_r_m"], ["apron_l_deg", "apron_r_deg"]]:
				var a: Variant = pts[i].get(pair[0])
				var b: Variant = pts[i].get(pair[1])
				pts[i].erase(pair[0])
				pts[i].erase(pair[1])
				if b != null:
					pts[i][pair[0]] = b
				if a != null:
					pts[i][pair[1]] = a
			for k: String in SLOPES:
				if pts[i].has(k):
					pts[i][k] = -float(pts[i][k])
		var d: Dictionary = layout.road.defaults
		var swapped := {}
		for k: String in d:
			swapped[String(SIDES.get(k, k))] = d[k]
		for k: String in SLOPES:
			if float(swapped.get(k, 0.0)) != 0.0:
				swapped[k] = -float(swapped[k])
		layout.road.defaults = swapped
		var race: Dictionary = layout.race
		race.start_m = mirror.call(float(race.get("start_m", 0.0)))
		race.sectors_m = (race.get("sectors_m", []) as Array).map(func(s: float) -> float: return mirror.call(s))
		race.sectors_m.sort()
		for pin: Dictionary in race.get("ai", {}).get("pins", []):
			pin.at_m = mirror.call(float(pin.at_m))
			pin.offset_m = -float(pin.offset_m)
		var grid: Dictionary = race.get("grid", {})
		grid.pole = "right" if grid.get("pole", "left") == "left" else "left"
		if layout.has("highway"):
			_flip_highway(layout.highway, mirror)
		if layout.has("kart") and layout.get("type", "circuit") != "arena":
			_flip_kart(layout.kart, mirror), &"all")


## Race setup: `key` in layout.race (a "/"-separated path for nested ones, like "grid/slots").
func set_race(key: String, value: Variant, name := "") -> void:
	_edit(name if name else "Set " + key.get_file().replace("_", " "), "race", func() -> void: _race_at(key)[key.get_file()] = value, &"race")


## Race setup without recording (while dragging an AI pin); end_race_live() records it.
func set_race_live(key: String, value: Variant) -> void:
	if not _dragging.has("race"):
		_dragging.race = layout.race.duplicate(true)
	_race_at(key)[key.get_file()] = value
	_changed(&"race", { "live": true })


func end_race_live(name: String) -> void:
	if not _dragging.has("race"):
		return
	var before := { "race": _dragging.race }
	_dragging.erase("race")
	history.act(name, _set_section.bind("race", { "race": layout.race.duplicate(true) }, &"race"), _set_section.bind("race", before, &"race"), false)
	_changed(&"race", {})


## The dictionary holding `key` (a "/" path in layout.race), made as needed.
func _race_at(key: String) -> Dictionary:
	var at: Dictionary = layout.race
	for k in key.split("/").slice(0, -1):
		if not at.has(k):
			at[k] = {}
		at = at[k]
	return at


func set_info(key: String, value: Variant) -> void:
	var before := info.duplicate(true)
	info[key] = value
	if key == "name":
		layout.name = value
	history.act("Set " + key, _set_info.bind(info.duplicate(true)), _set_info.bind(before), false)
	_changed(&"info", {})


## A terrain stroke that was applied as it went (heights in `rect` went from `before` to
## `after`), recorded as one action.
func terrain_stroke(rect: Rect2i, before: PackedFloat32Array, after: PackedFloat32Array) -> void:
	history.act("Shape ground", _set_heights.bind(rect, after), _set_heights.bind(rect, before), false)
	_track = null
	_changed(&"terrain", { "rect": rect })


## Replaces the terrain (refitted to the track), as one action.
func set_terrain(t: TerrainData, name := "Change terrain") -> void:
	history.act(name, _swap_terrain.bind(t), _swap_terrain.bind(terrain))


func _swap_terrain(t: TerrainData) -> void:
	terrain = t
	_changed(&"all", {})


func paint_stroke(rect: Rect2i, before: PackedByteArray, after: PackedByteArray) -> void:
	history.act("Paint ground", _set_paint.bind(rect, after), _set_paint.bind(rect, before), false)
	_changed(&"paint", { "rect": rect })


func add_prop(item: Dictionary) -> void:
	_edit("Place " + String(PropLibrary.TYPES.get(item.prop, {}).get("name", "prop")).to_lower(), "props", func() -> void:
		layout.props.items.append(item.duplicate(true)), &"props")


func set_prop(i: int, item: Dictionary, name := "Move prop") -> void:
	if i < 0 or i >= layout.props.items.size():
		return
	_edit(name, "props", func() -> void: layout.props.items[i] = item.duplicate(true), &"props")


## Moves a prop without recording (while dragging); end_prop_move() records it.
func set_prop_live(i: int, item: Dictionary) -> void:
	if i < 0 or i >= layout.props.items.size():
		return
	if not _dragging.has("props"):
		_dragging.props = layout.props.duplicate(true)
	layout.props.items[i] = item.duplicate(true)
	_changed(&"props", { "live": true })


func end_prop_move() -> void:
	if not _dragging.has("props"):
		return
	var before := { "props": _dragging.props }
	_dragging.erase("props")
	history.act("Move prop", _set_section.bind("props", { "props": layout.props.duplicate(true) }, &"props"), _set_section.bind("props", before, &"props"), false)
	_changed(&"props", {})


func delete_prop(i: int) -> void:
	if i < 0 or i >= layout.props.items.size():
		return
	_edit("Delete prop", "props", func() -> void: layout.props.items.remove_at(i), &"props")


## A scatter stroke: the group of `prop` from `before` to `after` (xf numbers).
func scatter_stroke(prop: String, before: Array, after: Array, name := "Scatter") -> void:
	history.act(name, _set_scatter.bind(prop, after), _set_scatter.bind(prop, before), false)
	_changed(&"scatter", {})


## A prop's scatter numbers (empty if none).
func scatter_of(prop: String) -> Array:
	for g: Dictionary in layout.props.scatter:
		if g.prop == prop:
			return g.xf
	return []


func set_scatter_live(prop: String, xf: Array) -> void:
	_set_scatter(prop, xf, false)


## The scene's tags (scene/tags.json), as one action.
func set_scene_tags(tag_data: Dictionary, name := "Change surfaces") -> void:
	if scene == null:
		return
	var before := scene.tags.duplicate(true)
	history.act(name, _set_tags.bind(tag_data.duplicate(true)), _set_tags.bind(before), true)


func _set_tags(tag_data: Dictionary) -> void:
	scene.set_tags(tag_data)
	_changed(&"scene", {})


## Several points' attributes at once, as one action: {point index: {key: value}}.
func set_point_attrs(changes: Dictionary, name: String) -> void:
	_edit(name, "road", func() -> void:
		for i: int in changes:
			if i >= 0 and i < points().size():
				(points()[i] as Dictionary).merge(changes[i], true), &"road")


func set_env(key: String, value: Variant) -> void:
	_edit("Set " + key.replace("_", " "), "environment", func() -> void:
		if value == null or (value is String and value.is_empty()):
			layout.environment.erase(key) # back to the default
		else:
			layout.environment[key] = value, &"all")


# --- highways (EDT-10) ----------------------------------------------------------------------


## A highway (D106): a carriageway each way either side of the road's line, with ramps.
func is_highway() -> bool:
	return layout.get("type", "circuit") == "highway"


## The highway's settings, every default filled in ({} on a circuit).
func highway() -> Dictionary:
	return TrackFormat.highway_settings(layout)


## Makes the track a highway, or a circuit again. A highway's road takes its widths, lines and
## barriers from its lanes; a circuit loses its ramps, portals and runs.
func set_type(type: String) -> void:
	var was := String(layout.get("type", "circuit"))
	if type == was or type not in TrackFormat.TYPES:
		return
	_edit("Make an " + type if type == "arena" else "Make a " + type, "type", func() -> void:
		layout.type = type
		if type == "highway":
			layout.highway = TrackFormat.HIGHWAY_DEFAULTS.duplicate(true)
			layout.road.defaults = TrackFormat.highway_road_defaults(highway(), layout.road.defaults)
			layout.erase("kart")
		else:
			layout.erase("highway")
			if was == "highway":
				layout.road.defaults = TrackFormat.base_defaults()
		# An arena (D138): its own section; its pieces sit anywhere, so a circuit's along the road go.
		if type == "arena":
			layout.arena = {}
			layout.race.gantry = false
			layout.erase("kart")
		else:
			layout.erase("arena"), &"road")


## A highway setting: lanes, lane_m, median_m, shoulder_in_m, shoulder_out_m, median_barrier,
## speed_kmh, "traffic/count" or "traffic/exit_share". The road's widths follow the lanes.
func set_highway(key: String, value: Variant, name := "") -> void:
	if not is_highway():
		return
	var shape := key in ["lanes", "lane_m", "median_m", "shoulder_in_m", "shoulder_out_m", "median_barrier"]
	_edit(name if name else "Set " + key.get_file().replace("_", " "), "highway", func() -> void:
		var at: Dictionary = layout.highway
		for k in key.split("/").slice(0, -1):
			if not at.has(k):
				at[k] = {}
			at = at[k]
		at[key.get_file()] = value
		if shape:
			layout.road.defaults = TrackFormat.highway_road_defaults(highway(), layout.road.defaults), &"road" if shape else &"highway")


## The ramps' templates (RampTemplates) as [[id, name]], for menus.
const RAMP_TEMPLATES := [["interchange", "Exit and entry"], ["exit", "Exit"], ["entry", "Entry"], ["crossover", "Crossover"]]
const _RAMP_WORDS := { "interchange": "Junction", "exit": "Exit", "entry": "Entry", "crossover": "Flyover" }


## Ramps from `template` (RAMP_TEMPLATES) on direction `dir`'s carriageway at main-road distance
## `at_m`, with the portals they need. Returns the new ramps' ids.
func add_ramp(template: String, dir: int, at_m: float, ramp_name := "") -> PackedStringArray:
	var t := track()
	if not is_highway() or t.samples.size() < 3 or not _RAMP_WORDS.has(template):
		return PackedStringArray()
	var h := highway()
	var n := _free_ramp_number(template)
	var base := "%s_%d" % [template, n]
	var label := ramp_name if ramp_name else "%s %d" % [_RAMP_WORDS[template], n]
	var made := { "ramps": [], "portals": [] }
	match template:
		"interchange":
			made = RampTemplates.interchange(t, h, dir, at_m, base, label)
		"exit":
			var e := RampTemplates.exit(t, h, dir, at_m, base, base + "_out", label)
			made = { "ramps": [e.ramp], "portals": [e.portal] }
		"entry":
			var e := RampTemplates.entry(t, h, dir, at_m, base, base + "_in", label)
			made = { "ramps": [e.ramp], "portals": [e.portal] }
		"crossover":
			made.ramps = [RampTemplates.crossover(t, h, dir, at_m, base, label).ramp]
	var ids := PackedStringArray()
	for r: Dictionary in made.ramps:
		ids.append(String(r.id))
	_edit("Add " + String(_RAMP_WORDS[template]).to_lower(), "highway", func() -> void:
		var hw: Dictionary = layout.highway
		hw.ramps = hw.get("ramps", []) + made.ramps
		hw.portals = hw.get("portals", []) + made.portals, &"highway", { "ramps": ids })
	return ids


## The ramp `id` as stored (null if none).
func ramp(id: String) -> Variant:
	for r: Dictionary in layout.get("highway", {}).get("ramps", []):
		if r.id == id:
			return r
	return null


## Sets `key` of ramp `id`: name, lanes, lane_m, speed_kmh, taper_m or traffic.
func set_ramp(id: String, key: String, value: Variant) -> void:
	if ramp(id) == null:
		return
	_edit("Set ramp " + key.replace("_", " "), "highway", func() -> void: ramp(id)[key] = value, &"highway", { "ramps": [id] })


## Moves ramp `id`'s point `i` without recording (while dragging); end_ramp_move() records it.
func drag_ramp_point(id: String, i: int, p: Vector3) -> void:
	var r: Variant = ramp(id)
	if r == null or i < 0 or i >= (r.points as Array).size():
		return
	if not _dragging.has("highway"):
		_dragging.highway = _section("highway")
	_dragging.ramp = id
	r.points[i] = _ramp_point(p)
	_changed(&"highway", { "ramps": [id], "live": true })


## Records a ramp point's drag (drag_ramp_point) as one move.
func end_ramp_move(name := "Move ramp point") -> void:
	if not _dragging.has("highway"):
		return
	var before: Dictionary = _dragging.highway
	var info := { "ramps": [String(_dragging.get("ramp", ""))] }
	_dragging.erase("highway")
	_dragging.erase("ramp")
	history.act(name, _set_section.bind("highway", _section("highway"), &"highway", info), _set_section.bind("highway", before, &"highway", info), false)
	_changed(&"highway", info)


## Puts a point at `index` of ramp `id` (it becomes that point; the rest move up).
func add_ramp_point(id: String, index: int, p: Vector3) -> void:
	if ramp(id) == null:
		return
	_edit("Add ramp point", "highway", func() -> void:
		var pts: Array = ramp(id).points
		pts.insert(clampi(index, 0, pts.size()), _ramp_point(p)), &"highway", { "ramps": [id] })


## Removes point `i` of ramp `id` (a ramp keeps one at least).
func delete_ramp_point(id: String, i: int) -> void:
	var r: Variant = ramp(id)
	if r == null or i < 0 or i >= (r.points as Array).size() or (r.points as Array).size() <= 1:
		return
	_edit("Delete ramp point", "highway", func() -> void: (ramp(id).points as Array).remove_at(i), &"highway", { "ramps": [id] })


## Moves ramp `id` `by_m` along the road (the way its carriageway drives): its ends, its points
## (each keeps its place across the road and its height over it) and its portal.
func move_ramp(id: String, by_m: float) -> void:
	var r: Variant = ramp(id)
	var t := track()
	if r == null or t.samples.size() < 3:
		return
	var dir := int(r.from.get("dir", r.to.get("dir", 1)))
	var shift := dir * by_m
	# What moves a spot `by_m` on: from the road's frame at its nearest place to the frame there.
	var move := func(p: Vector3) -> Transform3D:
		var proj := t.project(p)
		var from := t.transform_at(float(proj.distance), float(proj.lateral))
		return t.transform_at(float(proj.distance) + shift, float(proj.lateral)) * from.affine_inverse()
	_edit("Move ramp", "highway", func() -> void:
		var rr: Dictionary = ramp(id)
		for end: Dictionary in [rr.from, rr.to]:
			if end.has("at_m"):
				end.at_m = snappedf(fposmod(float(end.at_m) + shift, t.length), 0.1)
				continue
			for portal: Dictionary in layout.highway.get("portals", []):
				if portal.id == end.get("portal"):
					var at := Vector3(portal.p[0], portal.p[1], portal.p[2])
					var m: Transform3D = move.call(at)
					var yaw := deg_to_rad(float(portal.yaw_deg))
					var facing := m.basis * Vector3(sin(yaw), 0.0, cos(yaw))
					portal.p = _vec(Vector3((m * at).x, at.y, (m * at).z))
					portal.yaw_deg = snappedf(rad_to_deg(atan2(facing.x, facing.z)), 0.1)
		for pt: Dictionary in rr.points:
			var q := Vector3(pt.p[0], pt.p[1], pt.p[2])
			pt.p = _vec((move.call(q) as Transform3D) * q), &"highway", { "ramps": [id] })


## Removes ramp `id` and the portal it has.
func delete_ramp(id: String) -> void:
	var r: Variant = ramp(id)
	if r == null:
		return
	var portals := []
	for end: Dictionary in [r.from, r.to]:
		if end.has("portal"):
			portals.append(end.portal)
	_edit("Delete ramp", "highway", func() -> void:
		var hw: Dictionary = layout.highway
		hw.ramps = (hw.ramps as Array).filter(func(x: Dictionary) -> bool: return x.id != id)
		hw.portals = (hw.get("portals", []) as Array).filter(func(x: Dictionary) -> bool: return x.id not in portals), &"highway", { "ramps": [id] })


## Sets `key` of portal `id`: name, p ([x, y, z]) or yaw_deg.
func set_portal(id: String, key: String, value: Variant) -> void:
	var ids := []
	for r: Dictionary in layout.get("highway", {}).get("ramps", []):
		if r.from.get("portal") == id or r.to.get("portal") == id:
			ids.append(r.id)
	_edit("Set portal " + key.replace("_", " "), "highway", func() -> void:
		for portal: Dictionary in layout.highway.get("portals", []):
			if portal.id == id:
				portal[key] = value, &"highway", { "ramps": ids })


## The runs (stretches raced from a rolling start): [{id, name, dir, from_m, to_m}].
func set_runs(runs: Array, name := "Change runs") -> void:
	_edit(name, "highway", func() -> void: layout.highway.runs = runs.duplicate(true), &"highway", { "ramps": [] })


## The speed traps: [{dir, at_m}].
func set_traps(traps: Array, name := "Change speed traps") -> void:
	_edit(name, "highway", func() -> void: layout.highway.traps = traps.duplicate(true), &"highway", { "ramps": [] })


## Speed limits and tunnels: [{dir (0: both), from_m, to_m, speed_kmh, tunnel, name}]. Tunnels
## are built, so the road comes again.
func set_zones(zones: Array, name := "Change zones") -> void:
	_edit(name, "highway", func() -> void: layout.highway.zones = zones.duplicate(true), &"road")


func _free_ramp_number(template: String) -> int:
	var used := {}
	var hw: Dictionary = layout.get("highway", {})
	for list: Array in [hw.get("ramps", []), hw.get("portals", [])]:
		for x: Dictionary in list:
			used[String(x.id)] = true
	var n := 1
	while used.keys().any(func(k: String) -> bool: return k == "%s_%d" % [template, n] or k.begins_with("%s_%d_" % [template, n])):
		n += 1
	return n


static func _ramp_point(p: Vector3) -> Dictionary:
	var out := { "p": _vec(p) }
	if absf(p.y) > 0.01:
		out.height = "set"
	return out


## A highway turned round with its road: each carriageway is the other direction now, at the
## mirrored distance (`mirror`); ramps and portals stay where they are.
static func _flip_highway(h: Dictionary, mirror: Callable) -> void:
	var m := func(d: Variant) -> float: return snappedf(float(mirror.call(float(d))), 0.1)
	for r: Dictionary in h.get("ramps", []):
		for end: Dictionary in [r.from, r.to]:
			if end.has("dir"):
				end.dir = -int(end.dir)
				end.at_m = m.call(end.at_m)
	for run: Dictionary in h.get("runs", []):
		run.dir = -int(run.dir)
		run.from_m = m.call(run.from_m)
		run.to_m = m.call(run.to_m)
	for trap: Dictionary in h.get("traps", []):
		trap.dir = -int(trap.dir)
		trap.at_m = m.call(trap.at_m)
	for z: Dictionary in h.get("zones", []):
		var from: float = m.call(z.to_m)
		z.to_m = m.call(z.from_m)
		z.from_m = from
		z.dir = -int(z.get("dir", 0))


func undo() -> String:
	var name := history.undo_last()
	return name


func redo() -> String:
	return history.redo_next()


# --- files --------------------------------------------------------------------------------


## The package's files (without the manifest).
func files() -> Dictionary:
	var out := {}
	layout.id = id
	layout.name = info.name
	out["track.json"] = PackageWriter.canonical_json(layout).to_utf8_buffer()
	if terrain:
		out.merge(terrain.to_files())
	if scene:
		out["scene/scene.glb"] = scene.glb
		out["scene/tags.json"] = scene.tags_bytes()
	out.merge(images)
	return out


func manifest_info() -> Dictionary:
	return { "id": id, "name": info.name, "author": info.author, "license": info.license, "attributions": info.get("attributions", []) }


## The track as it stands, loaded (test drives): ground shaped round the road.
func to_package() -> TrackPackage:
	var pkg := TrackPackage.new()
	layout.id = id
	layout.name = info.name
	pkg.layout = layout.duplicate(true)
	pkg.terrain = terrain
	pkg.scene = scene
	pkg.track = track()
	pkg.path = path
	pkg.manifest = TrackWriter.manifest_for(manifest_info(), {}, layout)
	if terrain:
		terrain.conform(pkg.track)
	return pkg


## Saves to the track library. Returns TrackWriter.write()'s result.
func save(to := "") -> Dictionary:
	var target := to if to else path if path else TrackWriter.library_path(String(info.name), id)
	var r := TrackWriter.write(target, manifest_info(), files())
	if r.ok:
		path = target
		saved_version = history.version()
	return r


static func autosave_dir() -> String:
	return TrackLibrary.user_dir.path_join(AUTOSAVE)


## Writes the draft to the autosave folder, its images encoded on a worker. `on_done` (error).
func autosave_async(owner: Node, on_done := Callable()) -> void:
	var dir := autosave_dir().path_join(id)
	var snapshot := _snapshot()
	WorkerJob.start(owner, func() -> String: return _write_snapshot(dir, snapshot), func(err: String) -> void:
		if WorkerJob.alive(on_done):
			on_done.call(err), 60.0, func() -> String: return "Autosave timed out")


## The same, now (tests, quitting).
func autosave() -> String:
	return _write_snapshot(autosave_dir().path_join(id), _snapshot())


func delete_autosave() -> void:
	remove_autosave(autosave_dir().path_join(id))


## Removes an autosave folder and its note.
static func remove_autosave(dir: String) -> void:
	DirAccess.remove_absolute(dir + ".json")
	if DirAccess.dir_exists_absolute(dir):
		for rel in PackageWriter.read_folder(dir).keys() + ["manifest.json"]:
			DirAccess.remove_absolute(dir.path_join(rel))
		for sub in ["terrain", "scene", ""]:
			DirAccess.remove_absolute(dir.path_join(sub))


## Drafts that were autosaved and not saved since: [{dir, id, name, time, path}], newest first.
static func autosaves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := autosave_dir()
	if not DirAccess.dir_exists_absolute(root):
		return out
	for sub in DirAccess.get_directories_at(root):
		var note := root.path_join(sub) + ".json"
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(note)) if FileAccess.file_exists(note) else null
		if meta is Dictionary:
			out.append({ "dir": root.path_join(sub), "id": sub, "name": String(meta.get("name", sub)), "time": int(meta.get("time", 0)), "path": String(meta.get("path", "")) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time > b.time)
	return out


## A draft back from its autosave.
static func from_autosave(entry: Dictionary) -> TrackDraft:
	var pkg := TrackLoader.load_package(String(entry.dir))
	if not pkg.ok():
		return null
	var d := from_package(pkg)
	d.path = String(entry.path)
	d.saved_version = -1 # unsaved until saved
	return d


func _snapshot() -> Dictionary:
	layout.id = id
	layout.name = info.name
	var snap := { "track.json": PackageWriter.canonical_json(layout).to_utf8_buffer(), "images": images.duplicate(),
		"info": manifest_info(), "draft": { "name": info.name, "path": path, "time": int(Time.get_unix_time_from_system()) } }
	if terrain:
		var size := terrain.field.get_size()
		snap.terrain = { "meta": PackageWriter.canonical_json(terrain.meta).to_utf8_buffer(), "size": size,
			"height": terrain.field.get_base_u16(float(terrain.meta.height_min), float(terrain.meta.height_step)),
			"splat": [terrain.field.get_splat_rgba(0), terrain.field.get_splat_rgba(1)] }
	if scene:
		snap.scene = { "scene/scene.glb": scene.glb, "scene/tags.json": scene.tags_bytes() }
	return snap


static func _write_snapshot(dir: String, snap: Dictionary) -> String:
	var files := { "track.json": snap["track.json"] }
	files.merge(snap.images)
	files.merge(snap.get("scene", {}))
	if snap.has("terrain"):
		var t: Dictionary = snap.terrain
		var size: Vector2i = t.size
		files["terrain/meta.json"] = t.meta
		files["terrain/height.png"] = NossTerrain.png16_encode(t.height, size.x, size.y)
		for image in 2:
			files["terrain/splat_%d.png" % image] = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, t.splat[image]).save_png_to_buffer()
	var err := TrackWriter.write_folder(dir, snap.info, files)
	if err:
		return err
	# The note sits beside the package folder (the folder holds only what its manifest lists).
	var f := FileAccess.open(dir + ".json", FileAccess.WRITE)
	if f == null:
		return "Can't write the draft"
	f.store_string(JSON.stringify(snap.draft))
	f.close()
	return ""


# --- kart pieces and arenas (EDT-04, D136-D138) --------------------------------------------


func is_arena() -> bool:
	return layout.get("type", "circuit") == "arena"


## The kart section as stored ({} if there is none).
func kart() -> Dictionary:
	return layout.get("kart", {})


## Adds a `kind` piece (KartLayout.KINDS) at `at`: a distance along the road (circuits), or a
## point (Vector3, arenas), with `params` over its defaults. Returns its id ("" if it can't go).
func add_stunt(kind: String, at: Variant, params := {}) -> String:
	if kind not in KartLayout.KINDS or (is_arena() and kind not in KartLayout.ARENA_KINDS) or is_highway():
		return ""
	var n := 1
	while stunt("%s_%d" % [kind, n]) != null:
		n += 1
	var id := "%s_%d" % [kind, n]
	var piece := { "id": id, "kind": kind }
	if at is Vector3:
		piece.p = _vec(at)
	else:
		piece.at_m = snappedf(fposmod(float(at), maxf(track().length, 1.0)), 0.1)
	piece.merge(params, true)
	_edit("Add " + kind.replace("_", " "), "kart", func() -> void:
		if not layout.has("kart"):
			layout.kart = { "boxes": "auto", "stunts": [] }
		var stunts: Array = layout.kart.get("stunts", [])
		stunts.append(piece)
		layout.kart.stunts = stunts, &"kart", { "stunts": [id] })
	return id


## The piece `id` as stored (null if none).
func stunt(id: String) -> Variant:
	for p: Dictionary in kart().get("stunts", []):
		if p.id == id:
			return p
	return null


## Sets `key` of piece `id` (lateral_m, length_m, width_m, height_m, count, side, radius_m,
## yaw_deg).
func set_stunt(id: String, key: String, value: Variant) -> void:
	if stunt(id) == null:
		return
	_edit("Set " + key.trim_suffix("_m").trim_suffix("_deg").replace("_", " "), "kart", func() -> void: stunt(id)[key] = value, &"kart", { "stunts": [id] })


## Moves piece `id` to `at` (a distance, or a point in an arena) without recording, while
## dragging; end_stunt_move() records it.
func drag_stunt(id: String, at: Variant, lateral := NAN) -> void:
	var p: Variant = stunt(id)
	if p == null:
		return
	if not _dragging.has("kart"):
		_dragging.kart = _section("kart")
	_dragging.stunt = id
	if at is Vector3:
		p.p = _vec(at)
	else:
		p.at_m = snappedf(fposmod(float(at), maxf(track().length, 1.0)), 0.1)
		if not is_nan(lateral) and p.has("lateral_m"):
			p.lateral_m = snappedf(lateral, 0.05)
	_changed(&"kart", { "stunts": [id], "live": true })


func end_stunt_move(name := "Move piece") -> void:
	if not _dragging.has("kart"):
		return
	var before: Dictionary = _dragging.kart
	var info := { "stunts": [String(_dragging.get("stunt", ""))] }
	_dragging.erase("kart")
	_dragging.erase("stunt")
	history.act(name, _set_section.bind("kart", _section("kart"), &"kart", info), _set_section.bind("kart", before, &"kart", info), false)
	_changed(&"kart", info)


func delete_stunt(id: String) -> void:
	if stunt(id) == null:
		return
	_edit("Delete piece", "kart", func() -> void:
		layout.kart.stunts = (layout.kart.stunts as Array).filter(func(p: Dictionary) -> bool: return p.id != id), &"kart", { "stunts": [id] })


## Item boxes: "auto" (rows every third of a lap unless rows are placed), "placed" or "none".
func set_boxes(mode: String) -> void:
	if mode not in ["auto", "placed", "none"] or is_highway():
		return
	_edit("Item boxes " + mode, "kart", func() -> void:
		if not layout.has("kart"):
			layout.kart = { "stunts": [] }
		layout.kart.boxes = mode, &"kart")


## An arena setting: floor (a surface), wall (a barrier), wall_m.
func set_arena(key: String, value: Variant) -> void:
	if not is_arena():
		return
	_edit("Set " + key.trim_suffix("_m"), "arena", func() -> void: layout.arena[key] = value, &"road")


func add_spawn(p: Vector3, yaw_deg: float) -> void:
	if not is_arena():
		return
	_edit("Add spawn", "arena", func() -> void:
		var spawns: Array = layout.arena.get("spawns", [])
		spawns.append({ "p": _vec(p), "yaw_deg": snappedf(yaw_deg, 1.0) })
		layout.arena.spawns = spawns, &"road")


func move_spawn(i: int, p: Vector3, yaw_deg := NAN) -> void:
	var spawns: Array = layout.get("arena", {}).get("spawns", [])
	if i < 0 or i >= spawns.size():
		return
	_edit("Move spawn", "arena", func() -> void:
		layout.arena.spawns[i].p = _vec(p)
		if not is_nan(yaw_deg):
			layout.arena.spawns[i].yaw_deg = snappedf(yaw_deg, 1.0), &"road")


func delete_spawn(i: int) -> void:
	var spawns: Array = layout.get("arena", {}).get("spawns", [])
	if i < 0 or i >= spawns.size():
		return
	_edit("Delete spawn", "arena", func() -> void: (layout.arena.spawns as Array).remove_at(i), &"road")


func add_box_cluster(p: Vector3, count := ArenaLayout.CLUSTER_BOXES) -> void:
	if not is_arena():
		return
	_edit("Add item boxes", "arena", func() -> void:
		var boxes: Array = layout.arena.get("boxes", [])
		boxes.append({ "p": _vec(p), "count": count })
		layout.arena.boxes = boxes, &"road")


func delete_box_cluster(i: int) -> void:
	var boxes: Array = layout.get("arena", {}).get("boxes", [])
	if i < 0 or i >= boxes.size():
		return
	_edit("Delete item boxes", "arena", func() -> void: (layout.arena.boxes as Array).remove_at(i), &"road")


## Pieces after the track turns round: along the other way, the other side.
static func _flip_kart(k: Dictionary, mirror: Callable) -> void:
	for p: Dictionary in k.get("stunts", []):
		if not p.has("at_m"):
			continue
		if p.kind == "wall_ride":
			# Its stretch runs forward from at_m: turned round, it starts at the other end.
			p.at_m = snappedf(mirror.call(float(p.at_m) + float(p.get("length_m", KartLayout.STUNT_DEFAULTS.wall_ride.length_m))), 0.1)
			p.side = "right" if p.get("side", "left") == "left" else "left"
		else:
			p.at_m = snappedf(mirror.call(float(p.at_m)), 0.1)
		if p.has("lateral_m"):
			p.lateral_m = -float(p.lateral_m)


# --- internals ----------------------------------------------------------------------------


var _dragging := {}


## Runs `change` on layout[section] and records it (the whole section before and after).
## "highway" is the highway section, the track's type and the road (its widths follow the lanes).
func _edit(name: String, section: String, change: Callable, what: StringName, change_info := {}) -> void:
	var before := _section(section)
	change.call()
	var after := _section(section)
	# Undo and redo tell the preview what the change did (which ramps), never that it's live.
	var info := change_info.duplicate()
	info.erase("live")
	history.act(name, _set_section.bind(section, after, what, info), _set_section.bind(section, before, what, info), false)
	_changed(what, change_info)


func _section(section: String) -> Dictionary:
	match section:
		"all":
			var out := { "road": layout.road.duplicate(true), "race": layout.race.duplicate(true) }
			for key in ["highway", "kart"]:
				if layout.has(key):
					out[key] = (layout[key] as Dictionary).duplicate(true)
			return out
		"highway":
			return { "type": layout.get("type", "circuit"), "road": layout.road.duplicate(true),
				"highway": (layout.highway as Dictionary).duplicate(true) if layout.has("highway") else null }
		"type":
			var out := { "type": layout.get("type", "circuit"), "road": layout.road.duplicate(true), "race": layout.race.duplicate(true) }
			for key in ["highway", "kart", "arena"]:
				out[key] = (layout[key] as Dictionary).duplicate(true) if layout.has(key) else null
			return out
	if not layout.has(section):
		return { section: null }
	return { section: (layout[section] as Dictionary).duplicate(true) }


## Puts a section back (null: the key goes).
func _set_section(section: String, value: Dictionary, what: StringName, change_info := {}) -> void:
	for key: String in value:
		var v: Variant = value[key]
		if v == null:
			layout.erase(key)
		else:
			layout[key] = v.duplicate(true) if v is Dictionary or v is Array else v
	_changed(what, change_info)


func _set_info(value: Dictionary) -> void:
	info = value.duplicate(true)
	layout.name = info.name
	_changed(&"info", {})


func _set_heights(rect: Rect2i, heights: PackedFloat32Array) -> void:
	terrain.field.region_set(rect, heights)
	_track = null
	_changed(&"terrain", { "rect": rect })


func _set_paint(rect: Rect2i, weights: PackedByteArray) -> void:
	terrain.field.splat_region_set(rect, weights)
	_changed(&"paint", { "rect": rect })


func _set_scatter(prop: String, xf: Array, notify := true) -> void:
	var groups: Array = layout.props.scatter
	var found := false
	for g: Dictionary in groups:
		if g.prop == prop:
			g.xf = xf.duplicate()
			found = true
	if not found and not xf.is_empty():
		groups.append({ "prop": prop, "xf": xf.duplicate() })
	layout.props.scatter = groups.filter(func(g: Dictionary) -> bool: return not (g.xf as Array).is_empty())
	if notify:
		_changed(&"scatter", {})


func _changed(what: StringName, change_info: Dictionary) -> void:
	if what in [&"race", &"highway", &"kart"] and _track:
		_track = _track.with_race(layout) # the road is the same: no resampling
	elif what in [&"road", &"race", &"terrain", &"all"]:
		_track = null
	changed.emit(what, change_info)


## Control segments a point's move reaches (Catmull-Rom: two either side).
func _around(i: int) -> PackedInt32Array:
	var n := points().size()
	var out := PackedInt32Array()
	if n < 3:
		return out
	for k in range(i - 2, i + 2):
		var s := posmod(k, n)
		if s not in out:
			out.append(s)
	return out


static func _vec(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
