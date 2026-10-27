class_name PropBuilder
extends RefCounted
## Places a track's props (EDT-03, D100). Items are baked into the world and, in the game,
## merged per prop and part ("Grandstand", "GrandstandRoof", ...); the editor builds one node per
## item ("Item_<n>") so it can pick and move them. Scattered props are MultiMeshes per 256 m
## chunk, with simple shapes for the ones that collide.

const CHUNK := 256.0
const SCATTER_RANGE := 1500.0

var track: TrackData
var terrain: TerrainData
var visual := true
var _ground_y := -0.03
var _reach_max := -1.0


func _init(t: TrackData, ground: TerrainData = null) -> void:
	track = t
	terrain = ground
	_ground_y = float(t.raw.get("ground", {}).get("flat_y", -0.03))


## The ground under (x, z): the terrain's, or the flat ground's.
func ground_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain else _ground_y


## An item's placement: on the ground (or at its own height), turned by yaw, scaled.
func item_transform(item: Dictionary) -> Transform3D:
	var p: Array = item.p
	var pos := Vector3(p[0], p[1], p[2])
	if item.get("ground", false):
		pos.y = ground_at(pos.x, pos.z)
	var s := float(item.get("scale", 1.0))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(item.get("yaw_deg", 0.0)))).scaled(Vector3.ONE * s), pos)


func build(root: Node3D, per_item := false) -> void:
	var props: Dictionary = track.raw.get("props", {})
	var items: Array = props.get("items", [])
	if per_item:
		for i in items.size():
			var node := Node3D.new()
			node.name = "Item_%d" % i
			node.set_meta(&"item", i)
			_add_parts(node, [items[i]], i)
			root.add_child(node)
	else:
		_add_parts(root, items)
	for group: Dictionary in props.get("scatter", []):
		_scatter(root, group)


## The items' parts merged per prop and part, in world space. A flickering part gets its item's own
## colour alpha (flicker_alpha), so each lamp flickers in its own time (D221).
func _add_parts(parent: Node3D, items: Array, first := 0) -> void:
	var merged := {} # node name -> {batch, material, surface}
	for k in items.size():
		var item: Dictionary = items[k]
		var id := String(item.prop)
		if not PropLibrary.TYPES.has(id):
			continue
		var size: Array = item.get("size", [0.0, 0.0, 0.0])
		var xf := item_transform(item)
		for part: Dictionary in PropLibrary.parts(id, Vector3(size[0], size[1], size[2])):
			var node_name := String(PropLibrary.TYPES[id].name).to_pascal_case() + String(part.suffix)
			if not merged.has(node_name):
				merged[node_name] = { "batch": MeshBatch.new(), "material": part.material, "surface": part.surface }
			_append(merged[node_name].batch, part.batch, xf, flicker_alpha(first + k) if part.get("flicker", false) else -1.0)
	for node_name: String in merged:
		var m: Dictionary = merged[node_name]
		var b: MeshBatch = m.batch
		if visual:
			var mi := MeshInstance3D.new()
			mi.name = node_name
			mi.mesh = b.mesh()
			mi.material_override = PropLibrary.material(String(m.material))
			parent.add_child(mi)
		if int(m.surface) >= 0:
			var body := StaticBody3D.new()
			body.name = node_name + "Body"
			body.set_meta(&"noss_surface", int(m.surface))
			var cs := CollisionShape3D.new()
			cs.shape = b.shape()
			body.add_child(cs)
			parent.add_child(body)


## A flickering part's colour alpha for item `i`: 8 bits, neighbours far apart.
static func flicker_alpha(i: int) -> float:
	return float((i * 97) % 251 + 4) / 255.0


static func _append(to: MeshBatch, part: MeshBatch, xf: Transform3D, alpha := -1.0) -> void:
	var offset := to.verts.size()
	for k in part.verts.size():
		to.verts.append(xf * part.verts[k])
		to.normals.append((xf.basis * part.normals[k]).normalized())
	to.uvs.append_array(part.uvs)
	if alpha < 0.0:
		to.colors.append_array(part.colors)
	else:
		for c in part.colors:
			to.colors.append(Color(c.r, c.g, c.b, alpha))
	for i in part.index:
		to.index.append(i + offset)


## One scatter group ({prop, xf: [x, z, yaw, scale]*}): a MultiMesh per chunk, and a body per
## chunk holding a shape per prop that collides.
func _scatter(root: Node3D, group: Dictionary) -> void:
	var id := String(group.prop)
	if not PropLibrary.TYPES.has(id):
		return
	var xf: Array = group.xf
	var chunks := {} # Vector2i -> Array[Transform3D]
	for k in range(0, xf.size() - 3, 4):
		var x := float(xf[k])
		var z := float(xf[k + 1])
		var t := Transform3D(Basis(Vector3.UP, float(xf[k + 2])).scaled(Vector3.ONE * float(xf[k + 3])), Vector3(x, ground_at(x, z), z))
		var c := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		if not chunks.has(c):
			chunks[c] = []
		chunks[c].append(t)
	var shape := PropLibrary.scatter_shape(id)
	for c: Vector2i in chunks:
		var list: Array = chunks[c]
		if visual:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = PropLibrary.mesh(id)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Scatter_%s_%d_%d" % [id, c.x, c.y]
			mmi.multimesh = mm
			mmi.visibility_range_end = SCATTER_RANGE
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if id == "tree_billboard" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mmi)
		if not shape.is_empty():
			var body := StaticBody3D.new()
			body.name = "Scatter_%s_%d_%d_Body" % [id, c.x, c.y]
			body.set_meta(&"noss_surface", VehicleSim.SURFACE_CONCRETE)
			for t: Transform3D in list:
				var cs := CollisionShape3D.new()
				cs.shape = shape.shape
				cs.transform = t * Transform3D(Basis(), shape.offset)
				body.add_child(cs)
			root.add_child(body)


## Scatter points in a circle: dart throwing with a minimum spacing, off the road (and its
## curbs and run-off, plus a margin), not on slopes steeper than the prop takes. Deterministic
## for a seed. Returns xf numbers [x, z, yaw, scale]*.
func scatter_points(id: String, center: Vector2, radius: float, density_per_100m2: float, seed: int, scale_range := Vector2(0.8, 1.2), existing := PackedFloat32Array()) -> PackedFloat32Array:
	var t: Dictionary = PropLibrary.TYPES.get(id, {})
	var spacing := float(t.get("spacing", 3.0))
	var slope := float(t.get("slope", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var want := int(PI * radius * radius / 100.0 * density_per_100m2)
	var cell := spacing
	var grid := {} # Vector2i -> Array[Vector2]
	var add := func(p: Vector2) -> void:
		var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)
	for k in range(0, existing.size() - 3, 4):
		add.call(Vector2(existing[k], existing[k + 1]))
	var out := PackedFloat32Array()
	var tries := 0
	while out.size() / 4 < want and tries < want * 30:
		tries += 1
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		var p := center + Vector2(cos(a), sin(a)) * r
		if _near_road(p, float(t.get("clear_m", 0.0))) or _too_steep(p, slope) or _crowded(grid, p, spacing, cell):
			continue
		add.call(p)
		out.append_array([p.x, p.y, rng.randf() * TAU, rng.randf_range(scale_range.x, scale_range.y)])
	return out


func _near_road(p: Vector2, extra := 0.0) -> bool:
	if track.samples.size() < 2:
		return false
	if track.highway:
		for r in track.highway.ramps:
			var rp := r.track.project(Vector3(p.x, ground_at(p.x, p.y), p.y))
			var ri: int = rp.index
			if absf(float(rp.lateral)) < r.track.half_l[ri] + RampData.RUNOFF_M + 3.0 + extra and (Vector3(p.x, 0, p.y) - Vector3(rp.point.x, 0, rp.point.z)).length() < r.width + 4.0 + extra:
				return true
	if _reach_max < 0.0:
		for i in track.samples.size():
			_reach_max = maxf(_reach_max, maxf(track.half_l[i] + track.runoff_l_m[i], track.half_r[i] + track.runoff_r_m[i]))
		_reach_max += TrackData.CURB_WIDTH + 3.0
	if not track.is_near_centreline(Vector3(p.x, 0.0, p.y), _reach_max + extra):
		return false # the coarse grid first: most points are far from the road
	var proj := track.project(Vector3(p.x, ground_at(p.x, p.y), p.y))
	var side := signf(proj.lateral)
	var i: int = proj.index
	var reach: float = (track.half_l[i] if side >= 0.0 else track.half_r[i]) + TrackData.CURB_WIDTH + (track.runoff_l_m[i] if side >= 0.0 else track.runoff_r_m[i]) + 2.0 + extra
	return absf(proj.lateral) < reach and (Vector3(p.x, 0, p.y) - Vector3(proj.point.x, 0, proj.point.z)).length() < reach + 1.0


func _too_steep(p: Vector2, slope: float) -> bool:
	if terrain == null:
		return false
	var dx := terrain.height_at(p.x + 1.0, p.y) - terrain.height_at(p.x - 1.0, p.y)
	var dz := terrain.height_at(p.x, p.y + 1.0) - terrain.height_at(p.x, p.y - 1.0)
	return Vector2(dx, dz).length() / 2.0 > slope


static func _crowded(grid: Dictionary, p: Vector2, spacing: float, cell: float) -> bool:
	var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2 in grid.get(key + Vector2i(dx, dz), []):
				if q.distance_squared_to(p) < spacing * spacing:
					return true
	return false
