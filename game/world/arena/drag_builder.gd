class_name DragBuilder
extends Node3D
## Builds a drag strip (D168): the asphalt deck, the sand trap at the far end, the wall round the
## lot, the markings, and the Christmas tree between the lanes. Nothing here is read from a track
## file — the strip comes from the match settings alone, as the sumo arena does.
##
## The tree's bulbs are held so DragControl can light them as the countdown runs (set_bulb); with
## Reduce flashing on they glow less and never pulse (ACC-04).

## The deck is this thick, and the markings sit this far over its top.
const DECK_M := 0.5
const PAINT_UP_M := 0.012
## Texture metres.
const TILE_M := 4.0
## Lines across the strip: the start and finish, and the 60-foot marker.
const LINE_W_M := 0.5
const SIXTY_FT_M := 18.288
## The centreline and the lane edges.
const CENTRE_W_M := 0.3
const EDGE_W_M := 0.15
## The tree stands this far to one side of the centreline, this tall, with bulbs this big and
## this far apart.
const TREE_SIDE_M := 1.1
const TREE_BASE_M := 0.6
const TREE_POST_M := 4.2
const BULB_M := 0.42
const BULB_GAP_M := 0.52
## Bulbs in a lane's column, bottom to top as they light.
enum Bulb { PRE_STAGE, STAGE, AMBER_1, AMBER_2, AMBER_3, GREEN, RED }
const BULB_COLORS := {
	Bulb.PRE_STAGE: Color(0.95, 0.95, 1.0), Bulb.STAGE: Color(0.95, 0.95, 1.0),
	Bulb.AMBER_1: Color(1.0, 0.62, 0.1), Bulb.AMBER_2: Color(1.0, 0.62, 0.1),
	Bulb.AMBER_3: Color(1.0, 0.62, 0.1),
	Bulb.GREEN: Color(0.2, 1.0, 0.35), Bulb.RED: Color(1.0, 0.2, 0.2),
}
## An unlit bulb is this dark, so the column reads as a column of lamps either way.
const BULB_OFF := Color(0.1, 0.1, 0.12)

var layout: DragLayout
var visual := true
## Reduce flashing: the bulbs glow less (ACC-04).
var calm := false

## [lane][Bulb] -> the lamp, when there are visuals.
var _bulbs: Array[Array] = [[], []]


func setup(a: DragLayout, with_visuals := true, reduce_flashing := false) -> void:
	layout = a
	visual = with_visuals
	calm = reduce_flashing
	_deck()
	_wall()
	if visual:
		_markings()
		_tree()
	reset_tree()


## Every bulb out.
func reset_tree() -> void:
	for lane in 2:
		for b: int in Bulb.values():
			set_bulb(lane, b, false)


## Lights or puts out one bulb of one lane's column.
func set_bulb(lane: int, bulb: int, on: bool) -> void:
	if lane < 0 or lane >= _bulbs.size() or bulb >= _bulbs[lane].size():
		return
	var lamp: MeshInstance3D = _bulbs[lane][bulb]
	if lamp == null or not is_instance_valid(lamp):
		return
	var color: Color = BULB_COLORS[bulb] if on else BULB_OFF
	var glow := (0.5 if calm else 1.4) if on else 0.0
	lamp.material_override = WorldMaterials.glowing("drag_bulb_%d_%s" % [bulb, "on" if on else "off"], color, glow)


## The asphalt the pass is run on, then the sand that stops anyone who never braked.
func _deck() -> void:
	var top := layout.floor_y
	_slab("Deck", layout.back_z(), layout.trap_z(), top, VehicleSim.SURFACE_ASPHALT)
	_slab("Trap", layout.trap_z(), layout.end_z(), top, VehicleSim.SURFACE_SAND)


func _slab(node_name: String, z0: float, z1: float, top: float, surface: int) -> void:
	if z1 <= z0:
		return
	var b := MeshBatch.new()
	var size := Vector3(layout.half_width * 2.0, DECK_M, z1 - z0)
	b.box(Vector3(0.0, top - DECK_M * 0.5, (z0 + z1) * 0.5), Basis.IDENTITY, size, Vector2(1.0 / TILE_M, 1.0 / TILE_M))
	_piece(node_name, b, WorldMaterials.surface(surface), surface)


## A wall round the deck, as an arena has (ArenaBuilder): it keeps a spin inside the strip.
func _wall() -> void:
	var b := MeshBatch.new()
	var path := PackedVector3Array()
	for p in layout.outline:
		path.append(Vector3(p.x, layout.floor_y, p.y))
	path.append(path[0])
	var kind := TrackFormat.barrier_id(String(layout.settings.wall))
	var dims: Array = RoadBuilder.BARRIER_SIZE.get(kind, [1.0, 0.6])
	b.wall(path, float(layout.settings.wall_m), float(dims[1]))
	_piece("Wall", b, WorldMaterials.get_material("concrete_wall", RetroTextures.concrete(), 0.85, 0.2), VehicleSim.SURFACE_CONCRETE)


## Paint: the start and finish lines, the 60-foot marker, the centreline and the lane edges.
## Visual only — paint is not a surface to drive differently on here.
func _markings() -> void:
	var b := MeshBatch.new()
	_across(b, 0.0, LINE_W_M)
	_across(b, layout.length_m, LINE_W_M)
	_across(b, SIXTY_FT_M, LINE_W_M * 0.5)
	# The centreline runs the length of the racing surface, the edges down each lane's outside.
	_along(b, 0.0, CENTRE_W_M, layout.back_z(), layout.length_m)
	for lane in 2:
		var outer := layout.lane_x(lane) + signf(layout.lane_x(lane)) * DragLayout.LANE_W * 0.5
		_along(b, outer, EDGE_W_M, layout.back_z(), layout.length_m)
	var mi := MeshInstance3D.new()
	mi.name = "Markings"
	mi.mesh = b.mesh()
	mi.material_override = WorldMaterials.get_material("drag_paint", RetroTextures.concrete(), 0.6, 0.3, false, Vector2.ONE, Color(0.92, 0.92, 0.95))
	add_child(mi)


## A band across both lanes at `z`.
func _across(b: MeshBatch, z: float, width: float) -> void:
	var x := DragLayout.LANE_W
	_paint(b, -x, x, z - width * 0.5, z + width * 0.5)


## A stripe down the strip at `x`.
func _along(b: MeshBatch, x: float, width: float, z0: float, z1: float) -> void:
	_paint(b, x - width * 0.5, x + width * 0.5, z0, z1)


func _paint(b: MeshBatch, x0: float, x1: float, z0: float, z1: float) -> void:
	var y := layout.floor_y + PAINT_UP_M
	b.quad([Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0)],
		[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])


## The tree: a post each side of the centreline just short of the line, each with a column of
## bulbs facing its own lane's driver.
func _tree() -> void:
	var post_batch := MeshBatch.new()
	for lane in 2:
		var x := TREE_SIDE_M * signf(layout.lane_x(lane))
		post_batch.box(Vector3(x, layout.floor_y + TREE_POST_M * 0.5, DragLayout.STAGE_Z),
			Basis.IDENTITY, Vector3(0.22, TREE_POST_M, 0.22))
	var posts := MeshInstance3D.new()
	posts.name = "TreePosts"
	posts.mesh = post_batch.mesh()
	posts.material_override = WorldMaterials.get_material("drag_tree", RetroTextures.concrete(), 0.5, 0.3, false, Vector2.ONE, Color(0.2, 0.2, 0.22))
	add_child(posts)
	for lane in 2:
		var x := TREE_SIDE_M * signf(layout.lane_x(lane))
		var column: Array = []
		for b: int in Bulb.values():
			var lamp := MeshInstance3D.new()
			lamp.name = "Bulb%dL%d" % [b, lane]
			var quad := QuadMesh.new()
			quad.size = Vector2(BULB_M, BULB_M)
			lamp.mesh = quad
			# Bottom to top, the red one lowest of all: it belongs with the stage lamps.
			var step := (b if b != Bulb.RED else -1)
			lamp.position = Vector3(x, layout.floor_y + TREE_BASE_M + BULB_GAP_M * (step + 1), DragLayout.STAGE_Z - 0.14)
			# Facing back down the strip, at the driver waiting on the line.
			lamp.rotation.y = PI
			add_child(lamp)
			column.append(lamp)
		_bulbs[lane] = column


func _piece(node_name: String, b: MeshBatch, material: Material, surface: int) -> void:
	if b.is_empty():
		return
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = b.mesh()
		mi.material_override = material
		add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var cs := CollisionShape3D.new()
	cs.shape = b.shape()
	body.add_child(cs)
	add_child(body)
