class_name ArenaBuilder
extends RefCounted
## Builds an arena (D138): its floor inside the outline, a little over the ground, and a wall
## round it. Props and kart pieces are built as on any track.

const FLOOR_UP := 0.02
const TILE_M := 4.0

static func build(data: TrackData, into: Node3D, visual := true) -> void:
	var a := data.arena
	if a == null or a.outline.size() < 3:
		return
	var floor_surface := TrackFormat.surface_id(String(a.settings.floor))
	var deck := MeshBatch.new()
	var tris := Geometry2D.triangulate_polygon(a.outline)
	var y := a.floor_y + FLOOR_UP
	for i in range(0, tris.size(), 3):
		var p := [a.outline[tris[i]], a.outline[tris[i + 1]], a.outline[tris[i + 2]]]
		var v: Array[Vector3] = [Vector3(p[0].x, y, p[0].y), Vector3(p[1].x, y, p[1].y), Vector3(p[2].x, y, p[2].y)]
		if (v[1] - v[0]).cross(v[2] - v[0]).y < 0.0:
			v = [v[0], v[2], v[1]] # face up
		var first := deck.verts.size()
		for q in v:
			deck.vertex(q, Vector3.UP, Vector2(q.x, q.z) / TILE_M)
		deck.index.append_array([first, first + 2, first + 1]) # Godot's fronts are clockwise
	_piece(into, "ArenaFloor", deck, WorldMaterials.surface(floor_surface), floor_surface, visual)
	var wall := MeshBatch.new()
	var path := PackedVector3Array()
	for p in a.outline:
		path.append(Vector3(p.x, a.floor_y, p.y))
	path.append(path[0])
	var kind := TrackFormat.barrier_id(String(a.settings.wall))
	var dims: Array = RoadBuilder.BARRIER_SIZE.get(kind, [1.0, 0.6])
	wall.wall(path, float(a.settings.wall_m), float(dims[1]))
	_piece(into, "ArenaWall", wall, _wall_material(kind), VehicleSim.SURFACE_CONCRETE, visual)


static func _wall_material(kind: int) -> Material:
	match kind:
		TrackFormat.BARRIER_TYRES:
			return WorldMaterials.get_material("tyre_wall", RetroTextures.tyre_wall(), 0.9, 0.1)
		3:
			return WorldMaterials.get_material("armco", RetroTextures.concrete(), 0.35, 0.6, false, Vector2.ONE, Color(0.78, 0.8, 0.84))
	return WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2)


static func _piece(into: Node3D, node_name: String, b: MeshBatch, material: Material, surface: int, visual: bool) -> void:
	if b.is_empty():
		return
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = b.mesh()
		mi.material_override = material
		into.add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var cs := CollisionShape3D.new()
	cs.shape = b.shape()
	body.add_child(cs)
	into.add_child(body)
