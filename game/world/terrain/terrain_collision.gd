class_name TerrainCollision
extends Node3D
## A terrain's collision (D90): a static body with a HeightMapShape3D per 256 m chunk, centred on
## it. Wheels read what's painted under them through the shared surface map (D91).

var terrain: TerrainData
var _bodies := {} # Vector2i -> {body: StaticBody3D, shape: HeightMapShape3D}


static func build(t: TerrainData) -> TerrainCollision:
	var c := TerrainCollision.new()
	c.name = "TerrainCollision"
	c.terrain = t
	var n := t.chunks()
	var map := t.surface_map()
	for cz in n.y:
		for cx in n.x:
			c._make(Vector2i(cx, cz), map)
	return c


## Heights changed in `rect` (samples): those chunks' shapes follow.
func update_rect(rect: Rect2i) -> void:
	for c in terrain.chunks_in(rect):
		if _bodies.has(c):
			(_bodies[c].shape as HeightMapShape3D).map_data = terrain.field.chunk_collision(c.x, c.y, TerrainData.CHUNK)


## Paint changed: wheels read the new surfaces.
func update_surfaces() -> void:
	var map := terrain.surface_map(true)
	for c: Vector2i in _bodies:
		(_bodies[c].body as StaticBody3D).set_meta(&"noss_surface_map", map)


func _make(c: Vector2i, map: NossSurfaceMap) -> void:
	var body := StaticBody3D.new()
	body.name = "Chunk_%d_%d" % [c.x, c.y]
	body.set_meta(&"noss_surface", VehicleSim.SURFACE_GRASS) # off the map (never, in practice)
	body.set_meta(&"noss_surface_map", map)
	var shape := HeightMapShape3D.new()
	shape.map_width = TerrainData.CHUNK + 1
	shape.map_depth = TerrainData.CHUNK + 1
	shape.map_data = terrain.field.chunk_collision(c.x, c.y, TerrainData.CHUNK)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var centre := terrain.origin() + (Vector2(c) + Vector2(0.5, 0.5)) * TerrainData.CHUNK
	body.position = Vector3(centre.x, 0.0, centre.y)
	add_child(body)
	_bodies[c] = { "body": body, "shape": shape }
