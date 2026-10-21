class_name RoadBuilder
extends RefCounted
## Builds a track's road from its samples (docs/TRACK_EDITOR.md §2): the road surface, its lines,
## curbs, run-off strips, barriers, and decks and pillars where it stands on supports, each piece
## with the surface the tires read (docs/PHYSICS.md §4).
##
## In the game every kind is one piece for the whole track ("Road", "Curbs", "Barriers", ...);
## the editor builds a node per control segment, so a drag rebuilds only the segments it moved.

const RUNOFF_OVER_GROUND := 0.02 # m, run-off over flat ground
const CURB_WIDTH := TrackData.CURB_WIDTH
const CURB_HEIGHT := 0.045
## Across the curb, from the road's edge: [out, up].
const CURB_PROFILE := [[0.0, 0.0], [0.35, CURB_HEIGHT], [CURB_WIDTH, CURB_HEIGHT * 0.6]]
const LINE_WIDTH := 0.25
const LINE_INSET := 0.3
const LINE_UP := 0.01
const DASH_ON := 3.0
const DASH_OFF := 9.0
## Auto barriers: tyre walls on the outside of corners tighter than this radius.
const BARRIER_CURVATURE := 1.0 / 260.0
## Barrier sizes by type id (TrackFormat.BARRIERS): [height, thickness].
const BARRIER_SIZE := { 2: [0.9, 1.0], 3: [0.75, 0.3], 4: [1.0, 0.6], 5: [2.5, 0.12], 6: [4.5, 0.25] }
const SKIRT := 0.3
const DECK := 0.6
const PILLAR_EVERY_M := 20.0
const PILLAR := 0.8
const PARAPET := [1.0, 0.5]
## A flat-ground track's site wall, this far out around the road.
const SITE_WALL_M := 150.0

var track: TrackData
var terrain: TerrainData
## Without visuals (the dedicated server): collision only.
var visual := true
var _ground_y := -0.03
## A highway's markings, median, mouths and extras (null on circuits).
var _hw: HighwayBuilder


func _init(t: TrackData, ground: TerrainData = null) -> void:
	track = t
	terrain = ground
	_ground_y = float(t.raw.get("ground", {}).get("flat_y", -0.03))
	if t.highway:
		_hw = HighwayBuilder.new(self, t.highway)


## Every piece into `root`: one node per kind, or one per segment ("Seg_<n>") if `segmented`.
func build_all(root: Node3D, segmented := false) -> void:
	if track.samples.size() < 3 or track.kind != "road":
		return
	if segmented:
		for s in track.seg_first.size():
			root.add_child(build_segment(s))
	else:
		_add_batches(root, _batches(0, track.samples.size()))
	_add_batches(root, { "barrier:perimeter": _perimeter() })
	if _hw:
		for r in track.highway.ramps:
			root.add_child(build_ramp(r))
		root.add_child(_hw.extras())


## A highway ramp's road as one node, "Ramp_<id>".
func build_ramp(r: RampData) -> Node3D:
	var rb := RoadBuilder.new(r.track, terrain)
	rb.visual = visual
	rb._hw = HighwayBuilder.new(rb, track.highway, r)
	var node := Node3D.new()
	node.name = "Ramp_" + r.id
	rb._add_batches(node, rb._batches(0, r.track.samples.size() - 1))
	return node


## Rebuilds a highway's ramps and its extras (signs, portals, cushions) under `root`.
func rebuild_highway(root: Node3D) -> void:
	if not _hw:
		return
	for child in root.get_children():
		if String(child.name).begins_with("Ramp_") or child.name == &"Highway":
			root.remove_child(child)
			child.queue_free()
	for r in track.highway.ramps:
		root.add_child(build_ramp(r))
	root.add_child(_hw.extras())


## Replaces ramp `id`'s node under `root` (none if the ramp is gone or doesn't build).
func rebuild_ramp(root: Node3D, id: String) -> void:
	var old := root.get_node_or_null(NodePath("Ramp_" + id))
	if old:
		root.remove_child(old)
		old.queue_free()
	var r := track.highway.ramp(id) if _hw else null
	if r:
		root.add_child(build_ramp(r))


## Replaces the highway's signs, portals and cushions under `root`.
func rebuild_extras(root: Node3D) -> void:
	if not _hw:
		return
	var old := root.get_node_or_null(^"Highway")
	if old:
		root.remove_child(old)
		old.queue_free()
	root.add_child(_hw.extras())


## Segment `s`'s pieces as one node, "Seg_<s>".
func build_segment(s: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Seg_%d" % s
	var span := track.segment_samples(s)
	_add_batches(node, _batches(span.x, span.y))
	return node


## Replaces the nodes of `segments` under `root` (built segmented).
func rebuild_segments(root: Node3D, segments: PackedInt32Array) -> void:
	if track.kind != "road":
		return
	for s in segments:
		var old := root.get_node_or_null("Seg_%d" % s)
		if old:
			root.remove_child(old)
			old.queue_free()
		if s >= 0 and s < track.seg_first.size():
			root.add_child(build_segment(s))


# --- pieces ---------------------------------------------------------------------------------


## The pieces of samples [first, end) (end may pass the last sample: it wraps). Keyed by kind.
func _batches(first: int, end: int) -> Dictionary:
	var out := {}
	var n := track.samples.size()
	for i in range(first, end):
		var k := i % n
		var j := (i + 1) % n
		var surface := int(track.surface[k])
		_road_quad(_batch(out, "road:%d" % surface), k, j)
		if visual:
			if _hw:
				_hw.lines(_batch(out, "lines"), k, j)
			else:
				_lines(_batch(out, "lines"), k, j)
		for side: float in [1.0, -1.0]:
			if (track.curb_l if side > 0.0 else track.curb_r)[k] and not _gapped(k, side):
				_curb(_batch(out, "curbs"), k, j, side)
			var runoff := int((track.runoff_l if side > 0.0 else track.runoff_r)[k])
			if runoff != _ground_surface() and (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[k] > 0.1 and not _gapped(k, side) and not _gapped(j, side):
				_runoff(_batch(out, "runoff:%d" % runoff), k, j, side)
		if track.lifted[k] or track.lifted[j]:
			_deck(_batch(out, "bridge"), k, j)
	_barriers(out, first, end)
	_pillars(out, first, end)
	if _hw and _hw.ramp == null:
		_hw.main_pieces(out, first, end)
	return out


## True where `side` of sample `k` opens onto another road (a highway's ramp mouths).
func _gapped(k: int, side: float) -> bool:
	return (_hw != null and _hw.gapped(k, side)) or (track.kart != null and track.kart.gap(k, side))


func _batch(out: Dictionary, key: String) -> MeshBatch:
	if not out.has(key):
		out[key] = MeshBatch.new()
	return out[key]


func _ground_surface() -> int:
	return TrackFormat.surface_id(String(track.raw.get("ground", {}).get("surface", "grass"))) if terrain == null else VehicleSim.SURFACE_GRASS


func _edge(i: int, side: float, out := 0.0, up := 0.0) -> Vector3:
	var half: float = track.half_l[i] if side > 0.0 else track.half_r[i]
	return track.samples[i] + track.lefts[i] * side * (half + out) + track.ups[i] * up


func _road_quad(b: MeshBatch, i: int, j: int) -> void:
	var c := Color(0.82, 0.82, 0.82)
	var li := _edge(i, 1.0)
	var ri := _edge(i, -1.0)
	var lj := _edge(j, 1.0)
	var rj := _edge(j, -1.0)
	b.quad([li, ri, rj, lj], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], c)
	if terrain:
		# Skirts down the edges hide the ground's 5 cm step under the road.
		for side: float in [1.0, -1.0]:
			var ti := _edge(i, side)
			var tj := _edge(j, side)
			var down := Vector3.DOWN * SKIRT
			var face := [ti + down, ti, tj, tj + down] if side > 0.0 else [ti, ti + down, tj + down, tj]
			b.quad(face, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], c)


## Edge lines and dashed lane lines (TrackFormat.LINES: none, edges, lanes, all).
func _lines(b: MeshBatch, i: int, j: int) -> void:
	var style := int(track.lines[i])
	if style == 1 or style == 3:
		for side: float in [1.0, -1.0]:
			var outer := -LINE_INSET
			var inner := -LINE_INSET - LINE_WIDTH
			var q := [_edge(i, side, inner, LINE_UP), _edge(i, side, outer, LINE_UP), _edge(j, side, outer, LINE_UP), _edge(j, side, inner, LINE_UP)]
			b.quad(q if side < 0.0 else [q[1], q[0], q[3], q[2]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var lanes := int(track.lanes[i])
	if (style == 2 or style == 3) and lanes > 1:
		var d := track.distances[i]
		if fmod(d, DASH_ON + DASH_OFF) > DASH_ON:
			return
		for lane in range(1, lanes):
			var at := func(k: int) -> float: return lerpf(-track.half_r[k], track.half_l[k], float(lane) / lanes)
			var pi := track.samples[i] + track.ups[i] * LINE_UP
			var pj := track.samples[j] + track.ups[j] * LINE_UP
			var w := LINE_WIDTH / 2.0
			b.quad([pi + track.lefts[i] * (at.call(i) + w), pi + track.lefts[i] * (at.call(i) - w), pj + track.lefts[j] * (at.call(j) - w), pj + track.lefts[j] * (at.call(j) + w)],
				[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## The curb's profile from the road's edge out, then its outer face down to the ground.
func _curb(b: MeshBatch, i: int, j: int, side: float) -> void:
	var v0 := track.distances[i] / 3.0
	var v1 := (track.distances[j] if j > 0 else track.length) / 3.0
	for p in 2:
		var a: Array = CURB_PROFILE[p]
		var c: Array = CURB_PROFILE[p + 1]
		var ai: Vector3 = _edge(i, side, a[0]) + Vector3.UP * a[1]
		var bi: Vector3 = _edge(i, side, c[0]) + Vector3.UP * c[1]
		var aj: Vector3 = _edge(j, side, a[0]) + Vector3.UP * a[1]
		var bj: Vector3 = _edge(j, side, c[0]) + Vector3.UP * c[1]
		var q := [ai, bi, bj, aj] if side < 0.0 else [bi, ai, aj, bj]
		b.quad(q, [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)])
	var top_i := _edge(i, side, CURB_WIDTH) + Vector3.UP * CURB_HEIGHT * 0.6
	var top_j := _edge(j, side, CURB_WIDTH) + Vector3.UP * CURB_HEIGHT * 0.6
	var low_i := Vector3(top_i.x, _low(i), top_i.z)
	var low_j := Vector3(top_j.x, _low(j), top_j.z)
	var face := [low_i, top_i, top_j, low_j] if side > 0.0 else [top_i, low_i, low_j, top_j]
	b.quad(face, [Vector2(0, v0), Vector2(0, v0), Vector2(0, v1), Vector2(0, v1)])


## How low a piece's outer face goes: to flat ground, or a little into the terrain.
func _low(i: int) -> float:
	return _ground_y if terrain == null else track.samples[i].y - SKIRT


func _runoff(b: MeshBatch, i: int, j: int, side: float) -> void:
	var start_i := CURB_WIDTH if (track.curb_l if side > 0.0 else track.curb_r)[i] else 0.0
	var start_j := CURB_WIDTH if (track.curb_l if side > 0.0 else track.curb_r)[j] else 0.0
	var end_i: float = (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[i]
	var end_j: float = (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[j]
	# On flat ground, a little over it (the same height flickered through it), still under the road.
	var drop := Vector3.UP * (_ground_y + RUNOFF_OVER_GROUND if terrain == null else -0.03)
	var q := [_edge(i, side, start_i) + drop, _edge(i, side, end_i) + drop, _edge(j, side, end_j) + drop, _edge(j, side, start_j) + drop]
	b.quad(q if side < 0.0 else [q[1], q[0], q[3], q[2]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## A deck under the road where it stands on supports, and a concrete parapet each side.
func _deck(b: MeshBatch, i: int, j: int) -> void:
	for side: float in [1.0, -1.0]:
		if _gapped(i, side) or _gapped(j, side):
			continue
		var oi := _edge(i, side, PARAPET[1])
		var oj := _edge(j, side, PARAPET[1])
		var ii := _edge(i, side)
		var ij := _edge(j, side)
		var down := Vector3.DOWN * DECK
		var face := [oi + down, oi, oj, oj + down] if side > 0.0 else [oi, oi + down, oj + down, oj]
		b.quad(face, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		var top := [ii, oi, oj, ij] if side < 0.0 else [oi, ii, ij, oj]
		b.quad(top, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var li := _edge(i, 1.0, PARAPET[1]) + Vector3.DOWN * DECK
	var ri := _edge(i, -1.0, PARAPET[1]) + Vector3.DOWN * DECK
	var lj := _edge(j, 1.0, PARAPET[1]) + Vector3.DOWN * DECK
	var rj := _edge(j, -1.0, PARAPET[1]) + Vector3.DOWN * DECK
	b.quad([li, lj, rj, ri], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## Barrier runs, per side and type: auto ones are tyre walls on the outside of tight corners
## where the track isn't close by; lifted road gets concrete parapets. Runs take in the next
## segment's first sample, so pieces built apart still meet.
func _barriers(out: Dictionary, first: int, end: int) -> void:
	var n := track.samples.size()
	for side: float in [1.0, -1.0]:
		var run := PackedVector3Array()
		var run_type := 0
		var u := 0.0
		var parapet := PackedVector3Array()
		for s in range(end - first + 1):
			var k := (first + s) % n
			var kind := _barrier_at(k, side)
			if kind != run_type or kind == 0:
				u = _wall(out, run, run_type, u)
				run.clear()
				run_type = kind
			if kind > 0:
				run.append(_barrier_point(k, side))
			if track.lifted[k] and not _gapped(k, side):
				parapet.append(_edge(k, side, PARAPET[1] / 2.0))
			else:
				_wall(out, parapet, 4, 0.0, PARAPET)
				parapet.clear()
		_wall(out, run, run_type, u)
		_wall(out, parapet, 4, 0.0, PARAPET)


func _wall(out: Dictionary, path: PackedVector3Array, kind: int, u: float, size: Array = []) -> float:
	if kind <= 0 or path.size() < 2:
		return u
	var dims: Array = size if not size.is_empty() else BARRIER_SIZE[kind]
	return _batch(out, "barrier:%d" % kind).wall(path, dims[0], dims[1], u)


## The barrier type on `side` at sample `k` (0: none).
func _barrier_at(k: int, side: float) -> int:
	if track.lifted[k] or _gapped(k, side):
		return 0
	var kind := int((track.barrier_l if side > 0.0 else track.barrier_r)[k])
	if kind != TrackFormat.BARRIER_AUTO:
		return kind
	var kappa := track.curvature[k]
	# Outside of the corner: turning left (κ > 0), the right side.
	if absf(kappa) <= BARRIER_CURVATURE or signf(kappa) == side:
		return 0
	var p := _barrier_point(k, side)
	var reach := maxf(track.half_l[k], track.half_r[k]) + 6.0
	return TrackFormat.BARRIER_TYRES if not track.is_near_centreline(p, reach) else 0


func _barrier_point(k: int, side: float) -> Vector3:
	var half: float = track.half_l[k] if side > 0.0 else track.half_r[k]
	var runoff: float = track.runoff_l_m[k] if side > 0.0 else track.runoff_r_m[k]
	var p := track.samples[k] + track.lefts[k] * side * (half + runoff)
	if terrain:
		p.y = terrain.edge_ground(p)
	return p


## Pillars every PILLAR_EVERY_M under lifted road, a little in from each edge, down to the ground.
func _pillars(out: Dictionary, first: int, end: int) -> void:
	var n := track.samples.size()
	var next := -1.0
	for i in range(first, end):
		var k := i % n
		if not track.lifted[k]:
			next = -1.0
			continue
		var d := track.distances[k]
		if next >= 0.0 and d < next:
			continue
		next = d + PILLAR_EVERY_M
		for side: float in [1.0, -1.0]:
			var top := _edge(k, side, -0.5) + Vector3.DOWN * DECK
			if _hw and _hw.highway.road_below(top):
				continue
			var ground := terrain.height_at(top.x, top.z) - 0.5 if terrain else _ground_y
			var h := top.y - ground
			if h > 0.5:
				_batch(out, "bridge").box(Vector3(top.x, ground + h / 2.0, top.z), Basis(), Vector3(PILLAR, h, PILLAR))


## Flat ground: a wall round the whole site (as the first tracks had). Terrain: a wall just
## inside its edge, following the ground.
func _perimeter() -> MeshBatch:
	var b := MeshBatch.new()
	if terrain == null:
		var box := AABB(track.samples[0], Vector3.ZERO)
		for p in track.samples:
			box = box.expand(p)
		box = box.grow(SITE_WALL_M)
		var corners := [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z)]
		for i in 4:
			b.wall(PackedVector3Array([corners[i], corners[(i + 1) % 4]]), 1.6, 1.0)
		return b
	var a := terrain.area().grow(-2.0)
	var corners := [a.position, Vector2(a.end.x, a.position.y), a.end, Vector2(a.position.x, a.end.y)]
	for i in 4:
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[(i + 1) % 4]
		var steps := maxi(1, int(from.distance_to(to) / 16.0))
		var path := PackedVector3Array()
		for s in steps + 1:
			var p := from.lerp(to, float(s) / steps)
			path.append(Vector3(p.x, terrain.height_at(p.x, p.y) - 1.0, p.y))
		b.wall(path, 4.0, 1.0)
	return b


# --- nodes ----------------------------------------------------------------------------------


const NAMES := { "lines": "Lines", "curbs": "Curbs", "bridge": "Bridge", "lamps": "Lamps", "lamp_heads": "LampHeads",
	"tunnel": "Tunnel", "tunnel_lights": "TunnelLights", "gantry": "Gantries", "sign_board": "SignBoards", "cushion": "Cushions",
	"portal": "Portals", "portal_dark": "PortalShells", "portal_floor": "PortalFloors" }


## The batches' meshes and collision faces, made ahead (on a worker: no nodes, no shapes) for
## add_built(): {key: {mesh, faces}}. Headless, the meshes wait for add_built (MeshBatch.threaded).
func prebuild(batches: Dictionary) -> Dictionary:
	var out := {}
	for key: String in batches:
		var b: MeshBatch = batches[key]
		if not b.is_empty():
			out[key] = { "mesh": b.mesh() if visual and MeshBatch.threaded() else null, "faces": b.faces() }
	return out


## Nodes for batches made ahead by prebuild() (on the main thread).
func add_built(parent: Node3D, batches: Dictionary, built: Dictionary) -> void:
	_add_batches(parent, batches, built)


func _add_batches(parent: Node3D, batches: Dictionary, built := {}) -> void:
	for key: String in batches:
		var b: MeshBatch = batches[key]
		if b.is_empty():
			continue
		var parts := key.split(":")
		var node_name := String(NAMES.get(key, key))
		var material: Material
		var surface := -1
		match parts[0]:
			"road":
				surface = int(parts[1])
				node_name = "Road" if surface == VehicleSim.SURFACE_ASPHALT else "Road_" + TrackFormat.SURFACES[surface].capitalize()
				material = WorldMaterials.surface(surface)
			"lines":
				material = WorldMaterials.get_material("paint_white", null, 0.6, 0.2, false, Vector2.ONE, Color(0.9, 0.9, 0.88))
			"curbs":
				surface = VehicleSim.SURFACE_CURB
				material = WorldMaterials.surface(surface)
			"runoff":
				surface = int(parts[1])
				node_name = "Runoff_" + TrackFormat.SURFACES[surface].capitalize()
				material = WorldMaterials.surface(surface)
			"barrier":
				surface = VehicleSim.SURFACE_CONCRETE
				match parts[1]:
					"perimeter":
						node_name = "Perimeter"
						material = WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)
					"2":
						node_name = "Barriers"
						material = WorldMaterials.get_material("tyre_wall", RetroTextures.tyre_wall(), 0.9, 0.1)
					"3":
						node_name = "Armco"
						material = WorldMaterials.get_material("armco", RetroTextures.concrete(), 0.35, 0.6, false, Vector2.ONE, Color(0.78, 0.8, 0.84))
					"4":
						node_name = "ConcreteWalls"
						material = WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)
					"5":
						node_name = "Fences"
						material = WorldMaterials.get_material("fence", RetroTextures.concrete(), 0.6, 0.3, false, Vector2.ONE, Color(0.45, 0.5, 0.45))
			"bridge", "tunnel", "portal":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("concrete_world_uv", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0)
			"median":
				surface = VehicleSim.SURFACE_CONCRETE
				node_name = "Median"
				material = WorldMaterials.get_material("armco", RetroTextures.concrete(), 0.35, 0.6, false, Vector2.ONE, Color(0.78, 0.8, 0.84)) if parts[1] == "armco" \
					else WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)
			"lamps":
				material = WorldMaterials.get_material("lamp_pole", null, 0.5, 0.5, false, Vector2.ONE, Color(0.55, 0.57, 0.6))
			"lamp_heads":
				material = WorldMaterials.glowing("lamp_head", Color(1.0, 0.86, 0.6), 1.6, true)
			"tunnel_lights":
				material = WorldMaterials.glowing("tunnel_light", Color(1.0, 0.92, 0.75), 2.0)
			"gantry":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("gantry_steel", null, 0.45, 0.6, false, Vector2.ONE, Color(0.6, 0.62, 0.66))
			"sign_board":
				material = WorldMaterials.get_material("sign_green", null, 0.6, 0.2, false, Vector2.ONE, Color(0.06, 0.36, 0.2))
			"cushion":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("cushion", RetroTextures.checker(), 0.6, 0.2, false, Vector2(1, 2), Color(1.0, 0.82, 0.1))
			"portal_dark":
				surface = VehicleSim.SURFACE_CONCRETE
				material = WorldMaterials.get_material("portal_dark", null, 1.0, 0.0, false, Vector2.ONE, Color(0.03, 0.03, 0.035))
			"portal_floor":
				surface = VehicleSim.SURFACE_ASPHALT
				material = WorldMaterials.surface(VehicleSim.SURFACE_ASPHALT)
		_add_piece(parent, node_name, b, material, surface, built.get(key, {}))


## A piece: its mesh (unless visuals are off) and, if it's solid, a static body with its surface.
## `built`: its mesh and faces made ahead ({} : made here).
func _add_piece(parent: Node3D, node_name: String, b: MeshBatch, material: Material, surface: int, built := {}) -> void:
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = built.mesh if built.get("mesh") != null else b.mesh()
		mi.material_override = material
		parent.add_child(mi)
	if surface < 0:
		return
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var cs := CollisionShape3D.new()
	if built.has("faces"):
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(built.faces)
		cs.shape = shape
	else:
		cs.shape = b.shape()
	body.add_child(cs)
	parent.add_child(body)
