class_name TrackValidator
extends RefCounted
## Checks a track before it goes to the library, a server or another player (EDT-07,
## docs/TRACK_EDITOR.md §4). Errors block those (drafts always save); warnings and notes don't.
## Each problem says where it is, so the editor's Check tool can fly there. The checks take a
## snapshot (inputs(), on the main thread) and may then run on a worker (run()).

const MIN_LENGTH_M := 200.0
## Height between two parts of the road that cross (a bridge).
const CLEARANCE_M := 4.5
## Inner edge folds when |curvature| × half width reaches this.
const FOLD := 0.95
## A height step between samples past what STEEP allows, by this much, is a gap.
const GAP_M := 0.5
const STEEP := 0.25
const STEEP_RUN_M := 10.0
const GRID_BANK_DEG := 6.0
## Two grid columns side by side need this much road each side of the centreline.
const GRID_HALF_M := 2.3
const GRID_MIN := 2
const GRID_FULL := 12
## Share of the lap the grid may take.
const GRID_SHARE := 0.4
const SECTOR_GAP_M := 100.0
## The road keeps this far from the terrain's edge.
const EDGE_M := 50.0
## The AI line: how far it may stray past its corridor, how sharply it may bend (1/m: a kink
## tighter than any corner), and how slow the reference car may have to go.
const LINE_SLACK_M := 0.05
const LINE_KINK := 1.0 / 8.0
const LINE_SLOW := 4.0
## Road a car still gets through past a prop.
const FREE_M := 3.0
## Footprint sample spacing for big props, m.
const PROP_STEP_M := 3.0
## Problems of one kind listed at most.
const MAX_EACH := 3
## The car the AI line's speeds are checked with (and the editor's "AI lap" is timed with).
const REFERENCE_PLATFORM := "official.track.gt"
const LEVELS := ["error", "warning", "info"]

var problems: Array = []
var t: TrackData
var _in := {}
var _counts := {}


## Problems with `draft` now: [{level, text, at_m (-1: none), point (Vector3 or null)}], errors
## first. `line`: the AI line, when it's solved already.
static func check(draft: TrackDraft, line: RacingLine = null) -> Array:
	return run(inputs(draft), line)


## Only the errors' texts.
static func errors(found: Array) -> Array:
	return found.filter(func(p: Dictionary) -> bool: return p.level == "error").map(func(p: Dictionary) -> String: return p.text)


## What run() reads, copied now (run() may go on a worker while the draft changes).
static func inputs(draft: TrackDraft) -> Dictionary:
	var track := draft.track()
	track.index_cells()
	return {
		"track": track,
		"race": (draft.layout.get("race", {}) as Dictionary).duplicate(true),
		"props": (draft.layout.get("props", {}) as Dictionary).duplicate(true),
		"area": draft.terrain.area() if draft.terrain else Rect2(),
		"license": String(draft.info.get("license", "")),
		"scene": draft.scene,
		"platform": PlatformLoader.load_official(REFERENCE_PLATFORM).platform,
	}


static func run(inputs_: Dictionary, line: RacingLine = null) -> Array:
	var v := TrackValidator.new()
	v._in = inputs_
	v.t = inputs_.track
	v._check(line)
	var out := v.problems
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return LEVELS.find(a.level) < LEVELS.find(b.level))
	return out


func _check(line: RacingLine) -> void:
	if _in.license == "personal-use-only":
		_add("info", "Personal-use tracks stay offline")
	var n := t.samples.size()
	if n < 3 or t.length < MIN_LENGTH_M:
		_add("error", "Track too short")
		return
	if not (_in.race as Dictionary).has("start_m"):
		_add("error", "No start line", 0.0)
	_overlaps()
	_folds()
	_heights()
	_grid()
	_sectors()
	_terrain_edge()
	_props()
	if _in.get("scene") != null:
		_scene()
	_ai_line(line if line else RacingLine.solve(t))


## The road over itself without a bridge's clearance.
func _overlaps() -> void:
	var n := t.samples.size()
	var reach := 0.0
	for i in n:
		reach = maxf(reach, maxf(t.half_l[i], t.half_r[i]))
	var skip := maxf(60.0, 4.0 * reach)
	var hits := PackedInt32Array()
	for i in range(0, n, 2):
		var a := t.samples[i]
		var room_a := maxf(t.half_l[i], t.half_r[i])
		for j in t.samples_near(a, 2.0 * reach):
			var along := absf(t.distances[j] - t.distances[i])
			if minf(along, t.length - along) < skip or absf(a.y - t.samples[j].y) >= CLEARANCE_M:
				continue
			if Vector2(a.x - t.samples[j].x, a.z - t.samples[j].z).length() < room_a + maxf(t.half_l[j], t.half_r[j]):
				hits.append(i)
				break
	_spots(hits, "error", "Road overlaps at %s")


## Corners tighter than the road is wide: the inner edge folds over itself.
func _folds() -> void:
	var hits := PackedInt32Array()
	for i in t.samples.size():
		var k := t.curvature[i]
		if absf(k) * (t.half_l[i] if k > 0.0 else t.half_r[i]) > FOLD:
			hits.append(i)
	_spots(hits, "error", "Too tight at %s")


func _heights() -> void:
	var n := t.samples.size()
	var gaps := PackedInt32Array()
	var steep := PackedInt32Array()
	var span := maxi(int(STEEP_RUN_M / TrackData.SAMPLE_M), 1)
	for i in n:
		var a := t.samples[i]
		var b := t.samples[(i + 1) % n]
		var run_m := Vector2(b.x - a.x, b.z - a.z).length()
		if absf(b.y - a.y) > GAP_M + STEEP * run_m:
			gaps.append(i)
		var c := t.samples[(i + span) % n]
		var far := Vector2(c.x - a.x, c.z - a.z).length()
		if far > 0.1 and absf(c.y - a.y) / far > STEEP:
			steep.append(i)
	_spots(gaps, "error", "Gap at %s")
	_spots(steep, "warning", "Too steep at %s")


func _grid() -> void:
	var g := t.grid
	var slots := int(g.slots)
	if slots < GRID_MIN:
		_add("error", "Grid too small", t.start_m)
		return
	if slots < GRID_FULL:
		_add("warning", "Grid too small", t.start_m)
	var last := slots - 1
	var depth := float(g.front_m) + (last / 2) * float(g.row_m) + (last % 2) * float(g.row_m) * float(g.stagger)
	if depth > GRID_SHARE * t.length:
		_add("error", "Grid too long", t.start_m - depth)
		return
	for slot in slots:
		var d := t.start_m - float(g.front_m) - (slot / 2) * float(g.row_m) - (slot % 2) * float(g.row_m) * float(g.stagger)
		var i := t.index_at(d)
		if absf(rad_to_deg(t.bank[i])) > GRID_BANK_DEG or minf(t.half_l[i], t.half_r[i]) < GRID_HALF_M:
			_add("error", "Grid off the road", d)
			return


## Split lines in driving order from the start, SECTOR_GAP_M apart and from the line.
func _sectors() -> void:
	var prev := 0.0
	for k in t.sectors_m.size():
		var d := t.sectors_m[k]
		if d - prev < SECTOR_GAP_M or t.length - d < SECTOR_GAP_M:
			_add("error", "Sector %d out of order" % (k + 1), t.start_m + d)
		prev = d


func _terrain_edge() -> void:
	var area: Rect2 = _in.area
	if not area.has_area():
		return
	var hits := PackedInt32Array()
	for i in t.samples.size():
		var p := t.samples[i]
		var room := EDGE_M + maxf(t.half_l[i], t.half_r[i])
		if not area.grow(-room).has_point(Vector2(p.x, p.z)):
			hits.append(i)
	_spots(hits, "error", "Road leaves the terrain at %s")


## A fitted scene (Track Fitting): something tagged to drive on, under the whole centreline, the
## grid and every checkpoint.
func _scene() -> void:
	var scene: SceneTrack = _in.scene
	if not scene.surfaces.any(func(s: Dictionary) -> bool: return s.tag in SceneTrack.DRIVABLE):
		_add("error", "No surfaces tagged")
		return
	var gaps := PackedInt32Array()
	var untagged := PackedInt32Array()
	for i in range(0, t.samples.size(), 2):
		match _ground_under(scene, t.samples[i]):
			"auto":
				untagged.append(i)
			"":
				gaps.append(i)
	_spots(untagged, "error", "Road surface not tagged at %s")
	_spots(gaps, "error", "Gap at %s")
	for slot in int(t.grid.slots):
		if _ground_under(scene, t.grid_slot(slot).origin) == "":
			_add("error", "Grid off the road", t.start_m)
			break
	var d := 0.0
	while d < t.length:
		if _ground_under(scene, t.point_at(t.start_m + d)) == "":
			_add("error", "Checkpoint blocked at %s" % _where(t.start_m + d), t.start_m + d)
		d += maxf(t.checkpoint_spacing, 10.0)


## What a car on the centreline at `p` stands on: a drivable tag, "auto" (untagged), or "" (no
## ground there: a gap, water, a wall).
static func _ground_under(scene: SceneTrack, p: Vector3) -> String:
	var hit := scene.ray_down(p.x, p.z, p.y + 2.0)
	if not hit.hit or absf((hit.position as Vector3).y - p.y) > 1.5:
		return ""
	var tag := String(hit.tag)
	return tag if tag in SceneTrack.DRIVABLE or tag == "auto" else ""


## Props that stand on the road: a warning, or an error when a car can't get past.
func _props() -> void:
	var props: Dictionary = _in.props
	for item: Dictionary in props.get("items", []):
		var type: Dictionary = PropLibrary.TYPES.get(item.get("prop", ""), {})
		if not type.get("collide", false) or type.get("category") == "ground":
			continue
		var p: Array = item.p
		var pos := Vector3(p[0], p[1], p[2])
		var extent := _footprint(String(item.prop), item.get("size", []), float(item.get("scale", 1.0)))
		var basis := Basis(Vector3.UP, deg_to_rad(float(item.get("yaw_deg", 0.0))))
		var lo := INF
		var hi := -INF
		var at := -1
		var steps := Vector2i(ceili(extent.x * 2.0 / PROP_STEP_M), ceili(extent.y * 2.0 / PROP_STEP_M))
		for sx in steps.x + 1:
			for sz in steps.y + 1:
				var local := Vector3(-extent.x + sx * extent.x * 2.0 / maxi(steps.x, 1), 0.0, -extent.y + sz * extent.y * 2.0 / maxi(steps.y, 1))
				var hit := _on_road(pos + basis * local, not item.get("ground", false))
				if hit.is_empty():
					continue
				at = hit.i
				lo = minf(lo, hit.lateral)
				hi = maxf(hi, hit.lateral)
		if at < 0:
			continue
		var half := PROP_STEP_M / 2.0
		var free := maxf(t.half_l[at] - (hi + half), (lo - half) + t.half_r[at])
		if free < FREE_M:
			_add("error", "Road blocked at %s" % _where(t.distances[at]), t.distances[at], pos)
		else:
			_add("warning", "Prop on the road", t.distances[at], pos)
	for group: Dictionary in props.get("scatter", []):
		if not PropLibrary.TYPES.get(group.get("prop", ""), {}).get("collide", false):
			continue
		var xf: Array = group.xf
		for k in range(0, xf.size() - 3, 4):
			var hit := _on_road(Vector3(xf[k], 0.0, xf[k + 1]), false)
			if not hit.is_empty():
				_add("warning", "Prop on the road", t.distances[hit.i], Vector3(xf[k], t.samples[hit.i].y, xf[k + 1]))


## The road sample `pos` stands on and how far left of the centreline: {i, lateral}, or {}.
## Without `use_y` (the prop's height isn't known) it can't be under a bridge.
func _on_road(pos: Vector3, use_y: bool) -> Dictionary:
	for i in t.samples_near(pos, 30.0):
		var s := t.samples[i]
		if (use_y and absf(pos.y - s.y) > 3.0) or (not use_y and t.lifted[i]):
			continue
		var d := Vector3(pos.x - s.x, 0.0, pos.z - s.z)
		if absf(d.dot(t.tangents[i])) > TrackData.SAMPLE_M * 0.75:
			continue
		var left := Vector3(t.lefts[i].x, 0.0, t.lefts[i].z).normalized()
		var lateral := d.dot(left)
		if absf(lateral) < (t.half_l[i] if lateral >= 0.0 else t.half_r[i]):
			return { "i": i, "lateral": lateral }
	return {}


## Half the solid parts' size across (x) and along (z), scaled.
static func _footprint(id: String, size: Array, scale: float) -> Vector2:
	var box := AABB()
	var first := true
	for part: Dictionary in PropLibrary.parts(id, Vector3(size[0], size[1], size[2]) if size.size() == 3 else Vector3.ZERO):
		if int(part.surface) < 0:
			continue
		for v in (part.batch as MeshBatch).verts:
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
	return Vector2(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z))) * scale


## The AI's line: inside the road, smooth, and not slower than a walk.
func _ai_line(line: RacingLine) -> void:
	var n := t.samples.size()
	var speeds := line.speed_profile(_in.platform)
	var bad := PackedInt32Array()
	for i in n:
		var c := RacingLine.limits(t, i)
		var o := line.offsets[i]
		if o > c.x + LINE_SLACK_M or o < c.y - LINE_SLACK_M or absf(line.curvature[i]) > LINE_KINK or speeds[i] < LINE_SLOW:
			bad.append(i)
	_spots(bad, "error", "AI line error at %s")


## One problem per stretch of flagged samples (`hits`, in order), MAX_EACH at most.
func _spots(hits: PackedInt32Array, level: String, text: String) -> void:
	var last := -INF
	for i in hits:
		var d := t.distances[i]
		if d - last > 50.0:
			_add(level, text % _where(d), d)
		last = d


## A problem at along-track distance `at_m` (null: nowhere in particular) or `point`.
func _add(level: String, text: String, at_m: Variant = null, point: Variant = null) -> void:
	var kind := text.get_slice(" at ", 0)
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	if _counts[kind] > MAX_EACH:
		return
	var where := -1.0
	if at_m != null and t.length > 0.0:
		where = fposmod(float(at_m), t.length)
		if point == null:
			point = t.point_at(where)
	problems.append({ "level": level, "text": text, "at_m": where, "point": point })


## A distance as drivers see it: from the start line.
func _where(d: float) -> String:
	var from := t.from_start(d)
	return "%d m" % roundi(from) if from < 1000.0 else "%.1f km" % (from / 1000.0)
