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
## The steepest banking a grid slot may stand on: a superspeedway's start line is in its 18° tri-oval.
const GRID_BANK_DEG := 20.0
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
## Highways (EDT-10): the steepest a ramp should be, the shortest a run may be, and how far a
## ramp may reach into the road it isn't attached to.
const RAMP_STEEP := 0.08
const RUN_MIN_M := 500.0
const RAMP_INTO_M := 0.3
## Kart pieces and arenas (EDT-04, D137, D138): a loop's straight and road, a jump's landing,
## the shortest wall-ride, the tightest corner for a row of boxes, the narrowest kart road; an
## arena's smallest floor and fewest spawns.
const LOOP_RUN_EXTRA_M := 40.0
const LOOP_STRAIGHT := 1.0 / 400.0
const JUMP_LANDING_M := 30.0
const JUMP_LANDING_CURVE := 1.0 / 60.0
const WALL_MIN_M := 30.0
const ROW_TIGHT := 1.0 / 60.0
const KART_NARROW_M := 8.0
const ARENA_MIN_M2 := 2500.0
const ARENA_SPAWNS := 8
## A pit lane (D203) at least this long.
const PIT_MIN_M := 150.0
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
	for piece in track.scenery:
		piece.index_cells()
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
	if n < 3 or (t.length < MIN_LENGTH_M and t.arena == null): # an arena goes by its area
		_add("error", "Track too short")
		return
	if not (_in.race as Dictionary).has("start_m"):
		_add("error", "No start line", 0.0)
	if t.arena:
		_arena() # props in an arena are its obstacles (spawns keep clear of them)
		return
	_overlaps()
	_folds()
	_heights()
	if t.highway:
		_highway()
	else:
		_grid()
		_pit()
	if t.kart:
		_kart()
	_sectors()
	_terrain_edge()
	_props()
	if _in.get("scene") != null:
		_scene()
	if not t.highway: # traffic and the highway driver follow lanes, not a racing line
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
		for j in t.samples_near(a, 2.0 * reach):
			var along := absf(t.distances[j] - t.distances[i])
			if minf(along, t.length - along) < skip or absf(a.y - t.samples[j].y) >= CLEARANCE_M:
				continue
			# Each road's half on the side facing the other (two roads side by side, narrowed there).
			var b := t.samples[j]
			var room_a: float = t.half_l[i] if (b - a).dot(t.lefts[i]) > 0.0 else t.half_r[i]
			var room_b: float = t.half_l[j] if (a - b).dot(t.lefts[j]) > 0.0 else t.half_r[j]
			if Vector2(a.x - b.x, a.z - b.z).length() < room_a + room_b:
				hits.append(i)
				break
	_spots(hits, "error", "Road overlaps at %s")


## Corners tighter than the road (and its apron) is wide: the inner edge folds over itself.
func _folds() -> void:
	var hits := PackedInt32Array()
	for i in t.samples.size():
		var k := t.curvature[i]
		if absf(k) * (t.half_l[i] + t.apron(i, 1.0) if k > 0.0 else t.half_r[i] + t.apron(i, -1.0)) > FOLD:
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


## The pit lane (D203): it builds and is long enough, keeps off the road between its mouths, has
## room for its boxes, and no grid slot stands in a mouth.
func _pit() -> void:
	var data: Variant = t.raw.get("pit")
	if not data is Dictionary:
		return
	var at := float(data.get("from_m", 0.0))
	if t.pit_error:
		_add("error", t.pit_error, at)
		return
	var pit := t.pit
	if pit.track.length < PIT_MIN_M:
		_add("error", "Pit lane too short", at)
		return
	var hits := PackedInt32Array()
	for i in range(pit.gore_head, pit.gore_tail + 1, 2):
		var c := pit.track.samples[i]
		var on := t.project(c)
		if absf(c.y - (on.point as Vector3).y) < CLEARANCE_M and absf(float(on.lateral)) - pit.track.half_l[i] < t.edge_at(float(on.distance), float(on.lateral)):
			hits.append(t.index_at(float(on.distance)))
	_spots(hits, "error", "Pit lane overlaps the road at %s")
	if pit.crowded:
		_add("error", "Pit boxes don't fit", pit.exit_m)
	var g := t.grid
	for slot in int(g.slots):
		var d := t.start_m - float(g.front_m) - (slot / 2) * float(g.row_m) - (slot % 2) * float(g.row_m) * float(g.stagger)
		if pit.gap(t.index_at(d), pit.side):
			_add("error", "Grid in the pit mouth", d)
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
		if not type.get("collide", false) or type.get("category") == "ground" or type.get("over", false):
			continue
		var p: Array = item.p
		var pos := Vector3(p[0], p[1], p[2])
		var extent := _footprint(String(item.prop), item.get("size", []), float(item.get("scale", 1.0)))
		var basis := Basis(Vector3.UP, deg_to_rad(float(item.get("yaw_deg", 0.0))))
		var lo := INF
		var hi := -INF
		var at := -1
		var steps := Vector2i(ceili(extent.size.x / PROP_STEP_M), ceili(extent.size.y / PROP_STEP_M))
		for sx in steps.x + 1:
			for sz in steps.y + 1:
				var local := Vector3(extent.position.x + sx * extent.size.x / maxi(steps.x, 1), 0.0, extent.position.y + sz * extent.size.y / maxi(steps.y, 1))
				var hit := _on_road(pos + basis * local, not item.get("ground", false))
				if hit.is_empty():
					continue
				at = hit.i
				lo = minf(lo, hit.lateral)
				hi = maxf(hi, hit.lateral)
		if at < 0:
			if _on_scenery(pos, extent, basis, steps):
				_add("warning", "Prop on a scenery road", -1.0, pos)
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
			for piece in t.scenery:
				hit = _on_road(Vector3(xf[k], 0.0, xf[k + 1]), false, piece)
				if not hit.is_empty():
					_add("warning", "Prop on a scenery road", -1.0, Vector3(xf[k], piece.samples[hit.i].y, xf[k + 1]))
					break


## True if any of a prop's footprint (as _props() samples it) is on a scenery road (D212).
func _on_scenery(pos: Vector3, extent: Rect2, basis: Basis, steps: Vector2i) -> bool:
	for piece in t.scenery:
		for sx in steps.x + 1:
			for sz in steps.y + 1:
				var local := Vector3(extent.position.x + sx * extent.size.x / maxi(steps.x, 1), 0.0, extent.position.y + sz * extent.size.y / maxi(steps.y, 1))
				if not _on_road(pos + basis * local, false, piece).is_empty():
					return true
	return false


## The sample of `road` (the track's, or a scenery road) `pos` stands on and how far left of its
## centreline: {i, lateral}, or {}. Without `use_y` (the prop's height isn't known) it can't be
## under a bridge.
func _on_road(pos: Vector3, use_y: bool, road: TrackData = null) -> Dictionary:
	var r := road if road else t
	for i in r.samples_near(pos, 30.0):
		var s := r.samples[i]
		if (use_y and absf(pos.y - s.y) > 3.0) or (not use_y and r.lifted[i]):
			continue
		var d := Vector3(pos.x - s.x, 0.0, pos.z - s.z)
		if absf(d.dot(r.tangents[i])) > TrackData.SAMPLE_M * 0.75:
			continue
		var left := Vector3(r.lefts[i].x, 0.0, r.lefts[i].z).normalized()
		var lateral := d.dot(left)
		if absf(lateral) < (r.half_l[i] if lateral >= 0.0 else r.half_r[i]):
			return { "i": i, "lateral": lateral }
	return {}


## Where the solid parts stand, across (x) and along (z), scaled: a grandstand reaches back from
## its front, not either way.
static func _footprint(id: String, size: Array, scale: float) -> Rect2:
	var box := AABB()
	var first := true
	for part: Dictionary in PropLibrary.parts(id, Vector3(size[0], size[1], size[2]) if size.size() == 3 else Vector3.ZERO):
		if int(part.surface) < 0:
			continue
		for v in (part.batch as MeshBatch).verts:
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
	return Rect2(box.position.x * scale, box.position.z * scale, box.size.x * scale, box.size.z * scale)


## A highway's ramps build, aren't too tight or steep, keep off the road and each other, and
## leave the road where no other ramp does; a way back on after an exit; crossovers each way;
## runs long enough; and traffic can drive it all.
func _highway() -> void:
	var h := t.highway
	for e in h.errors:
		_add("error", e)
	var mouths := { 1: {}, -1: {} } # direction: {main sample: ramp index}
	var cells := {} # Vector2i: [[ramp index, sample]]
	var exits := { 1: [], -1: [] }
	var entries := { 1: 0, -1: 0 }
	var links := { 1: 0, -1: 0 }
	for ri in h.ramps.size():
		var r := h.ramps[ri]
		var rt := r.track
		var label := r.name if r.name else r.id
		var n := rt.samples.size()
		var tight := false
		var steep := false
		var into := false
		var span := maxi(int(STEEP_RUN_M / TrackData.SAMPLE_M), 1)
		for k in n:
			var p := rt.samples[k]
			if absf(rt.curvature[k]) * maxf(rt.half_l[k], rt.half_r[k]) > FOLD:
				tight = tight or _once("error", "Ramp too tight: " + label, p)
			if k + span < n:
				var q := rt.samples[k + span]
				var run_m := Vector2(q.x - p.x, q.z - p.z).length()
				if run_m > 0.1 and absf(q.y - p.y) / run_m > RAMP_STEEP:
					steep = steep or _once("warning", "Ramp too steep: " + label, p)
			if k < r.head_count or k >= r.tail_start:
				continue # attached: it is the road's edge there
			var proj := t.project(p)
			var mi: int = proj.index
			var edge := maxf(t.half_l[mi], t.half_r[mi])
			if absf(float(proj.lateral)) - r.width / 2.0 < edge - RAMP_INTO_M and absf(p.y - t.samples[mi].y) < CLEARANCE_M:
				into = into or _once("error", "Ramp overlaps road: " + label, p)
			var cell := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append([ri, k])
		for end: Array in [[r.from, r.head_main], [r.to, r.tail_main]]:
			var e: Dictionary = end[0]
			if not e.has("dir"):
				continue
			var taken: Dictionary = mouths[int(e.dir)]
			for k in (end[1] as PackedInt32Array):
				if taken.has(k) and taken[k] != ri:
					var o := h.ramps[taken[k]]
					_add("error", "Ramps too close: %s, %s" % [o.name if o.name else o.id, label], t.distances[k])
					break
				taken[k] = ri
		match r.kind:
			"exit":
				exits[int(r.from.dir)].append(float(r.from.at_m))
			"entry":
				entries[int(r.to.dir)] += 1
			"link":
				links[int(r.from.dir)] += 1
	_ramps_cross(cells)
	for dir: int in [1, -1]:
		if not exits[dir].is_empty() and entries[dir] == 0:
			_add("warning", "Exit with no entry back", exits[dir][0])
	if not h.ramps.is_empty() and (links[1] == 0 or links[-1] == 0):
		_add("warning", "No crossover" if links[1] + links[-1] == 0 else "Crossover one way only")
	for run: Dictionary in h.runs:
		if fposmod(int(run.dir) * (float(run.to_m) - float(run.from_m)), t.length) < RUN_MIN_M:
			_add("error", "Run too short: " + String(run.name), float(run.from_m))
	var traffic := NossTraffic.new()
	var err := traffic.setup(h.lane_graph(), TrafficTypes.list(), 1, maxi(int(h.settings.traffic.count), 1), float(h.settings.traffic.exit_share))
	if err:
		_add("error", "Traffic can't drive it: " + err)


## Two ramps (their free parts) on each other without a bridge's clearance.
func _ramps_cross(cells: Dictionary) -> void:
	var h := t.highway
	var found := {}
	for cell: Vector2i in cells:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var other: Vector2i = cell + Vector2i(dx, dz)
				if not cells.has(other):
					continue
				for a: Array in cells[cell]:
					for b: Array in cells[other]:
						if int(a[0]) >= int(b[0]) or found.has(Vector2i(a[0], b[0])):
							continue
						var ra := h.ramps[a[0]]
						var rb := h.ramps[b[0]]
						var pa := ra.track.samples[a[1]]
						var pb := rb.track.samples[b[1]]
						if Vector2(pa.x - pb.x, pa.z - pb.z).length() < (ra.width + rb.width) / 2.0 and absf(pa.y - pb.y) < CLEARANCE_M:
							found[Vector2i(a[0], b[0])] = true
							_add("error", "Ramps overlap: %s, %s" % [ra.name if ra.name else ra.id, rb.name if rb.name else rb.id], null, pa)


## Adds a problem at `point` and says so (one per ramp and kind: true stops the next).
func _once(level: String, text: String, point: Vector3) -> bool:
	_add(level, text, null, point)
	return true


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
## Kart pieces on a road (D137).
func _kart() -> void:
	var k := t.kart
	var spans := []
	var boxes := 0
	for p in k.pieces:
		if not p.has("at_m"):
			continue
		var at := float(p.at_m)
		var i := t.index_at(at)
		var width := t.half_l[i] + t.half_r[i]
		match String(p.kind):
			"boost_pad", "jump":
				var half := (float(p.width_m) if float(p.width_m) > 0.0 else 0.0) / 2.0
				var lat := float(p.get("lateral_m", 0.0))
				if lat + half > t.half_l[i] + 0.01 or lat - half < -t.half_r[i] - 0.01:
					_add("error", "Piece off the road", at)
				if p.kind == "jump":
					for d in range(0, int(JUMP_LANDING_M), 5):
						if absf(t.curvature[t.index_at(at + float(p.length_m) / 2.0 + d)]) > JUMP_LANDING_CURVE:
							_add("warning", "Jump needs 30 m of road after it", at)
							break
			"wall_ride":
				if float(p.length_m) < WALL_MIN_M:
					_add("error", "Wall-ride too short", at)
				for d in range(0, int(float(p.length_m)) + 1, 2):
					var j := t.index_at(at + d)
					if t.lifted[j] or (t.highway and t.highway.gap(j, 1.0 if p.side == "left" else -1.0)):
						_add("error", "Wall-ride over a bridge or ramp", at + d)
						break
			"loop":
				var r := float(p.radius_m)
				if width < 2.0 * float(p.width_m) + KartLayout.LOOP_GAP_M:
					_add("error", "Loop needs a road twice its width", at)
				var reach := r + LOOP_RUN_EXTRA_M / 2.0
				var y0 := t.point_at(at).y
				for d in range(-int(reach), int(reach) + 1, 4):
					var j := t.index_at(at + d)
					if absf(t.curvature[j]) > LOOP_STRAIGHT or absf(t.samples[j].y - y0) > 0.5:
						_add("error", "Loop needs a straight (%d m)" % roundi(2.0 * r + LOOP_RUN_EXTRA_M), at)
						break
			"item_row":
				if absf(t.curvature[i]) > ROW_TIGHT:
					_add("warning", "Item row on a tight corner", at)
		if p.kind != "item_row" and not p.get("auto", false):
			spans.append([at - k._extent(p) * (0.0 if p.kind == "wall_ride" else 1.0), at + k._extent(p) * (2.0 if p.kind == "wall_ride" else 1.0), p])
	for r in k.rows:
		boxes += (r.points as PackedVector3Array).size()
	if boxes > KartLayout.MAX_BOXES:
		_add("error", "More than %d item boxes" % KartLayout.MAX_BOXES)
	for a in spans.size():
		for b in range(a + 1, spans.size()):
			var x: Array = spans[a]
			var y: Array = spans[b]
			var gap := fposmod(float(y[0]) - float(x[0]) + t.length / 2.0, t.length) - t.length / 2.0
			var x_len := float(x[1]) - float(x[0])
			var y_len := float(y[1]) - float(y[0])
			if (gap >= 0.0 and gap < x_len) or (gap < 0.0 and -gap < y_len):
				_add("error", "Pieces overlap", float(x[0]))
	var narrowest := INF
	for i in range(0, t.samples.size(), 5):
		narrowest = minf(narrowest, t.half_l[i] + t.half_r[i])
	if narrowest < KART_NARROW_M:
		_add("warning", "Narrow for karts (%.0f m)" % narrowest)


## An arena (D138): an outline that doesn't cross itself, room enough, spawns and boxes inside.
func _arena() -> void:
	var a := t.arena
	var n := a.outline.size()
	var crossed := false
	for i in n:
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			if Geometry2D.segment_intersects_segment(a.outline[i], a.outline[(i + 1) % n], a.outline[j], a.outline[(j + 1) % n]) != null:
				crossed = true
				break
		if crossed:
			break
	if crossed:
		_add("error", "Arena outline crosses itself")
		return
	if a.area < ARENA_MIN_M2:
		_add("error", "Arena too small (%d m²)" % roundi(a.area))
	var clear := 0
	for s in a.spawns:
		if not a.inside(s.origin, ArenaLayout.WALL_MARGIN_M):
			_add("error", "Spawn outside the arena", null, s.origin)
		elif _free_of_props(s.origin):
			clear += 1
	if clear < ARENA_SPAWNS:
		_add("error", "Fewer than %d clear spawns" % ARENA_SPAWNS)
	for c in a.clusters:
		if not a.inside(c.p, ArenaLayout.WALL_MARGIN_M):
			_add("error", "Item boxes outside the arena", null, c.p)
	if t.kart:
		for p in t.kart.pieces:
			var at: Vector3 = (p.frame as Transform3D).origin
			if not a.inside(at, 1.0):
				_add("error", "Piece outside the arena", null, at)


## No solid prop within a kart's length of `p`.
func _free_of_props(p: Vector3) -> bool:
	for item: Dictionary in (_in.props as Dictionary).get("items", []):
		var type: Dictionary = PropLibrary.TYPES.get(item.get("prop", ""), {})
		if not type.get("collide", false) or type.get("category") == "ground":
			continue
		var at: Array = item.p
		if Vector2(p.x - float(at[0]), p.z - float(at[2])).length() < 3.0 + float(item.get("scale", 1.0)) * float(type.get("clear_m", 2.0)):
			return false
	return true


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
