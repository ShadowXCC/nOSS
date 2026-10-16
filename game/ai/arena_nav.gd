class_name ArenaNav
extends RefCounted
## Ways round an arena for the battle AI (D138, D144): a grid of 2 m cells over the floor, a cell
## blocked outside the outline (with a margin from the wall) or where something solid stands on
## it (props, crates; ramps and pads are driven over, so tagged pieces don't block). Paths by
## A* (AStarGrid2D); one per session, built once the world is there.

const CELL_M := 2.0
const WALL_MARGIN_M := 1.5
## What blocks a cell: anything solid in this band over the floor.
const PROBE_FROM := 0.4
const PROBE_TO := 1.4

var arena: ArenaLayout
var grid := AStarGrid2D.new()
var origin := Vector2.ZERO # the grid's corner, world x and z

static var _cache := {}


## The session's grid (built on first use).
static func for_session(session: TrackSession) -> ArenaNav:
	var key := session.get_instance_id()
	if _cache.has(key) and is_instance_valid(session):
		return _cache[key]
	for k: int in _cache.keys():
		if not is_instance_id_valid(k):
			_cache.erase(k)
	var nav := ArenaNav.new()
	nav.build(session.track.arena, session.get_world_3d().direct_space_state)
	_cache[key] = nav
	return nav


func build(a: ArenaLayout, space: PhysicsDirectSpaceState3D) -> void:
	arena = a
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in a.outline:
		lo = lo.min(p)
		hi = hi.max(p)
	origin = lo - Vector2.ONE * CELL_M
	var size := Vector2i(ceili((hi.x - origin.x) / CELL_M) + 2, ceili((hi.y - origin.y) / CELL_M) + 2)
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2.ONE * CELL_M
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var probe := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL_M * 0.9, PROBE_TO - PROBE_FROM, CELL_M * 0.9)
	probe.shape = shape
	probe.collision_mask = Vehicle.LAYER_WORLD
	for x in size.x:
		for y in size.y:
			var c := Vector2i(x, y)
			var at := centre_of(c)
			if not a.inside(at, WALL_MARGIN_M):
				grid.set_point_solid(c)
				continue
			if space == null:
				continue
			probe.transform = Transform3D(Basis(), at + Vector3.UP * (PROBE_FROM + PROBE_TO) / 2.0)
			for hit: Dictionary in space.intersect_shape(probe, 8):
				var body: Object = hit.collider
				if body and not body.has_meta(&"noss_tag"):
					grid.set_point_solid(c)
					break


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL_M), floori((p.z - origin.y) / CELL_M))


## A cell's middle on the floor.
func centre_of(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * CELL_M, arena.floor_y, origin.y + (c.y + 0.5) * CELL_M)


func open(c: Vector2i) -> bool:
	return grid.is_in_boundsv(c) and not grid.is_point_solid(c)


## The open cell nearest `p` (itself if it's open), searching out `reach` cells.
func nearest_open(p: Vector3, reach := 6) -> Vector2i:
	var c := cell_of(p)
	if open(c):
		return c
	var best := c
	var best_d := INF
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var q := c + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length_squared()
			if d < best_d and open(q):
				best_d = d
				best = q
	return best


## Points from `from` to `to` over the floor (cell middles, the last one `to` itself), or [] if
## there's no way.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := nearest_open(from)
	var b := nearest_open(to)
	var out := PackedVector3Array()
	if not open(a) or not open(b):
		return out
	for c: Vector2i in grid.get_id_path(a, b):
		out.append(centre_of(c))
	if not out.is_empty():
		out[out.size() - 1] = Vector3(to.x, arena.floor_y, to.z)
	return out
