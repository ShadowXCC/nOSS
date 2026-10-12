class_name TrackDraft
extends RefCounted
## The track being edited (EDT-01…EDT-07): its layout (track.json), terrain, name and license, and
## its undo history. Every change goes through a command here, so the editor's tools, undo and
## the headless checks share one path. `changed` tells the preview what to rebuild:
##   road (info.segments: the control segments touched; none: all), race, props, scatter,
##   terrain (info.rect, samples), paint (info.rect), info, all.

signal changed(what: StringName, info: Dictionary)

## Left and right swap places when the track is driven the other way.
const SIDES := { "width_l": "width_r", "width_r": "width_l", "curb_l": "curb_r", "curb_r": "curb_l", "runoff_l": "runoff_r",
	"runoff_r": "runoff_l", "runoff_l_m": "runoff_r_m", "runoff_r_m": "runoff_l_m", "barrier_l": "barrier_r", "barrier_r": "barrier_l" }
const LICENSES := [["CC-BY-SA-4.0", "CC BY-SA 4.0"], ["CC-BY-4.0", "CC BY 4.0"], ["CC0-1.0", "CC0 (public domain)"], ["personal-use-only", "Personal use only"]]
const AUTOSAVE := ".autosave"

var id := ""
## name, author, license, attributions (the manifest's).
var info := {}
var layout := {}
var terrain: TerrainData
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
	points()[i].p = _vec(p)
	_changed(&"road", { "segments": _around(i), "live": true })


## Records a drag (drag_point) as one move.
func end_move(name := "Move point") -> void:
	if not _dragging.has("road"):
		return
	var before := { "road": _dragging.road }
	_dragging.erase("road")
	var after := { "road": layout.road.duplicate(true) }
	history.act(name, _set_section.bind("road", after, &"road"), _set_section.bind("road", before, &"road"), false)
	_changed(&"road", {})


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
			for pair: Array in [["width_l", "width_r"]]:
				var a: Variant = pts[i].get(pair[0])
				var b: Variant = pts[i].get(pair[1])
				pts[i].erase(pair[0])
				pts[i].erase(pair[1])
				if b != null:
					pts[i][pair[0]] = b
				if a != null:
					pts[i][pair[1]] = a
			if pts[i].has("bank_deg"):
				pts[i].bank_deg = -float(pts[i].bank_deg)
		var d: Dictionary = layout.road.defaults
		var swapped := {}
		for k: String in d:
			swapped[String(SIDES.get(k, k))] = d[k]
		layout.road.defaults = swapped
		var race: Dictionary = layout.race
		race.start_m = mirror.call(float(race.get("start_m", 0.0)))
		race.sectors_m = (race.get("sectors_m", []) as Array).map(func(s: float) -> float: return mirror.call(s))
		race.sectors_m.sort()
		for pin: Dictionary in race.get("ai", {}).get("pins", []):
			pin.at_m = mirror.call(float(pin.at_m))
			pin.offset_m = -float(pin.offset_m)
		var grid: Dictionary = race.get("grid", {})
		grid.pole = "right" if grid.get("pole", "left") == "left" else "left", &"all")


## Race setup: `key` in layout.race (a "/"-separated path for nested ones, like "grid/slots").
func set_race(key: String, value: Variant) -> void:
	_edit("Set " + key.get_file().replace("_", " "), "race", func() -> void:
		var at: Dictionary = layout.race
		var parts := key.split("/")
		for k in parts.slice(0, -1):
			if not at.has(k):
				at[k] = {}
			at = at[k]
		at[parts[-1]] = value, &"race")


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


func set_env(key: String, value: Variant) -> void:
	_edit("Set " + key.replace("_", " "), "environment", func() -> void: layout.environment[key] = value, &"all")


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
		if on_done.is_valid():
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
	return snap


static func _write_snapshot(dir: String, snap: Dictionary) -> String:
	var files := { "track.json": snap["track.json"] }
	files.merge(snap.images)
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


# --- internals ----------------------------------------------------------------------------


var _dragging := {}


## Runs `change` on layout[section] and records it (the whole section before and after).
func _edit(name: String, section: String, change: Callable, what: StringName, change_info := {}) -> void:
	var before := _section(section)
	change.call()
	var after := _section(section)
	history.act(name, _set_section.bind(section, after, what), _set_section.bind(section, before, what), false)
	_changed(what, change_info)


func _section(section: String) -> Dictionary:
	if section == "all":
		return { "road": layout.road.duplicate(true), "race": layout.race.duplicate(true) }
	return { section: (layout[section] as Dictionary).duplicate(true) }


func _set_section(section: String, value: Dictionary, what: StringName) -> void:
	for key: String in value:
		layout[key] = (value[key] as Dictionary).duplicate(true)
	_changed(what, {})


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
	if what in [&"road", &"race", &"terrain", &"all"]:
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
