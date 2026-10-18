class_name SumoBuilder
extends Node3D
## Builds and keeps a sumo arena (D162): one slab per tier, the pit round them and the goo at the
## bottom. The slabs are remade as they shrink, so each one holds its own mesh and collision; the
## pit and the goo are built once. Nothing here is read from a track file.

const HAZARD_SHADER := preload("res://game/world/arena/sumo_hazard.gdshader")
## A slab is this thick, and its rim drops this far over the lip.
const THICK_M := 1.6
const LIP_DROP_M := 0.7
## Texture metres.
const TILE_M := 4.0
## A slab is remade when its radius has moved this far: at 90 s over 24 m that is about 5 Hz.
const REBUILD_M := 0.05
## Out cars rest here, under the goo and out of sight.
const PIT_FLOOR_DROP_M := 3.0
## Crumbling: chunks broken off a lost ring, how long they fall for, and how fast they tumble.
const CHUNKS := 14
const CHUNK_LIFE_S := 4.0
const CHUNK_SPIN := 2.5
const GRAVITY := 9.81

var layout: SumoLayout
var visual := true
## Reduce flashing: the goo churns and glows less (ACC-04).
var calm := false

var _slabs: Array[Node3D] = []
var _built_r := PackedFloat32Array()
## Lumps of a crumbled ring on their way into the goo: [{node, vel, spin, life}].
var _debris: Array[Dictionary] = []


func setup(a: SumoLayout, with_visuals := true, reduce_flashing := false) -> void:
	layout = a
	visual = with_visuals
	calm = reduce_flashing
	_pit()
	_goo()
	for i in layout.count():
		var slab := Node3D.new()
		slab.name = "Tier%d" % (i + 1)
		add_child(slab)
		_slabs.append(slab)
		_built_r.append(-1.0)
	refresh()


## Remakes any slab that has shrunk since it was last built, and clears away the ones that have
## gone. Cheap enough to call every frame; it only does work when a radius has really moved.
func refresh() -> void:
	for i in _slabs.size():
		var r := layout.radius_of(i)
		if not layout.live(i):
			if _built_r[i] != 0.0:
				_clear(_slabs[i])
				_built_r[i] = 0.0
			continue
		if absf(r - _built_r[i]) < REBUILD_M:
			continue
		# A crumbling platform throws the ring it just lost into the goo (D162).
		if visual and layout.style == "crumble" and _built_r[i] > r + SumoLayout.LIP_M:
			_crumble(r, _built_r[i], layout.floor_y_of(i))
		_built_r[i] = r
		_clear(_slabs[i])
		_slab(_slabs[i], r, layout.floor_y_of(i))


func _clear(under: Node3D) -> void:
	for c in under.get_children():
		under.remove_child(c)
		c.queue_free()


## Throws the ring between `inner` and `outer` off as lumps that tumble into the goo. They are
## scenery only: the floor has already gone, so nothing drives on them.
func _crumble(inner: float, outer: float, y: float) -> void:
	var mid := (inner + outer) / 2.0
	var width := maxf(outer - inner, 1.0)
	var material := WorldMaterials.surface(VehicleSim.SURFACE_CONCRETE)
	for i in CHUNKS:
		var ang := TAU * (i + randf() * 0.6) / CHUNKS
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var at := dir * mid + Vector3.UP * (y - THICK_M / 2.0)
		var b := MeshBatch.new()
		var basis := Basis(Vector3.UP, ang)
		b.box(Vector3.ZERO, basis, Vector3(width * randf_range(0.5, 0.9), THICK_M, TAU * mid / CHUNKS * randf_range(0.5, 0.9)))
		var mi := MeshInstance3D.new()
		mi.mesh = b.mesh()
		mi.material_override = material
		mi.position = at
		add_child(mi)
		_debris.append({
			"node": mi,
			"vel": dir * randf_range(0.5, 2.5) + Vector3.UP * randf_range(-0.5, 1.5),
			"spin": Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * CHUNK_SPIN * randf(),
			"life": CHUNK_LIFE_S,
		})


func _process(delta: float) -> void:
	if _debris.is_empty():
		return
	var still: Array[Dictionary] = []
	for d in _debris:
		var mi: Variant = d.node
		if not is_instance_valid(mi):
			continue
		d.life = float(d.life) - delta
		# Gone once it has had its time, or once the goo has swallowed it.
		if float(d.life) <= 0.0 or (mi as Node3D).position.y < layout.hazard_y - 2.0:
			(mi as Node3D).queue_free()
			continue
		d.vel = (d.vel as Vector3) + Vector3.DOWN * GRAVITY * delta
		var node := mi as Node3D
		node.position += (d.vel as Vector3) * delta
		node.rotate_x(float((d.spin as Vector3).x) * delta)
		node.rotate_y(float((d.spin as Vector3).y) * delta)
		node.rotate_z(float((d.spin as Vector3).z) * delta)
		still.append(d)
	_debris = still


## One tier: a disc of `radius` at `y`, with a rim sloping out to the lip and a side down to the
## underside. The lip is not playable floor; it is there to catch a car that lands on the edge.
func _slab(under: Node3D, radius: float, y: float) -> void:
	if radius <= 0.01:
		return
	var b := MeshBatch.new()
	var n := SumoLayout.SEGMENTS
	var lip := radius + SumoLayout.LIP_M
	var low := y - THICK_M
	var rim := y - LIP_DROP_M
	var top := PackedVector3Array()
	var edge := PackedVector3Array()
	var under_ring := PackedVector3Array()
	for i in n:
		var ang := TAU * i / n
		var d := Vector3(cos(ang), 0.0, sin(ang))
		top.append(d * radius + Vector3.UP * y)
		edge.append(d * lip + Vector3.UP * rim)
		under_ring.append(d * lip + Vector3.UP * low)
	var mid := Vector3(0, y, 0)
	var below := Vector3(0, low, 0)
	for i in n:
		var j := (i + 1) % n
		_tri(b, mid, top[i], top[j], Vector3.UP) # the floor
		_quad(b, [top[i], top[j], edge[j], edge[i]], Vector3.UP) # the catch lip
		_quad(b, [edge[i], edge[j], under_ring[j], under_ring[i]], edge[i].normalized()) # the side
		_tri(b, below, under_ring[j], under_ring[i], Vector3.DOWN) # the underside
	_piece(under, "Deck", b, WorldMaterials.surface(VehicleSim.SURFACE_CONCRETE), VehicleSim.SURFACE_CONCRETE)


## The pit the platforms hang in: a rock wall round them and a floor under the goo.
func _pit() -> void:
	var holder := Node3D.new()
	holder.name = "Pit"
	add_child(holder)
	var rock := WorldMaterials.get_material("sumo_rock", RetroTextures.rock(), 0.95, 0.1, true, Vector2.ONE / 8.0)
	var wall := MeshBatch.new()
	var path := PackedVector3Array()
	for p in SumoLayout.ring(layout.pit_r):
		path.append(Vector3(p.x, layout.hazard_y - PIT_FLOOR_DROP_M, p.y))
	path.append(path[0])
	var high := layout.floor_y_of(0) + SumoLayout.PIT_RIM_M - layout.hazard_y + PIT_FLOOR_DROP_M
	wall.wall(path, high, 6.0)
	_piece(holder, "PitWall", wall, rock, VehicleSim.SURFACE_CONCRETE)
	var floor_batch := MeshBatch.new()
	_disc(floor_batch, layout.pit_r, layout.hazard_y - PIT_FLOOR_DROP_M)
	_piece(holder, "PitFloor", floor_batch, rock, VehicleSim.SURFACE_CONCRETE)


## The goo: a glowing surface, drawn only. Whether a car is in it is a height test in
## SumoControl, so a dedicated server rules the same way without any physics contact.
func _goo() -> void:
	if not visual:
		return
	var b := MeshBatch.new()
	_disc(b, layout.pit_r, layout.hazard_y)
	var mi := MeshInstance3D.new()
	mi.name = "Goo"
	mi.mesh = b.mesh()
	mi.material_override = material()
	mi.set_meta(&"noss_hazard", layout.hazard)
	add_child(mi)


## The goo's material: lava, or acid in the same shader.
func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HAZARD_SHADER
	if layout.hazard == "acid":
		m.set_shader_parameter("deep", Color(0.05, 0.22, 0.04))
		m.set_shader_parameter("glow", Color(0.49, 1.0, 0.16))
		m.set_shader_parameter("crust", Color(0.06, 0.13, 0.05))
		m.set_shader_parameter("emit", 1.6)
	m.set_shader_parameter("calm", 1.0 if calm else 0.0)
	return m


## A flat disc facing up at `y`.
func _disc(b: MeshBatch, radius: float, y: float) -> void:
	var n := SumoLayout.SEGMENTS
	var mid := Vector3(0, y, 0)
	var pts := PackedVector3Array()
	for i in n:
		var ang := TAU * i / n
		pts.append(Vector3(cos(ang), 0.0, sin(ang)) * radius + Vector3.UP * y)
	for i in n:
		_tri(b, mid, pts[i], pts[(i + 1) % n], Vector3.UP)


## A triangle wound so that it faces `towards` (Godot's fronts are clockwise).
func _tri(b: MeshBatch, a: Vector3, c: Vector3, d: Vector3, towards: Vector3) -> void:
	var n := (c - a).cross(d - a)
	var up := n.normalized() if n.length() > 1e-6 else towards
	var flip := up.dot(towards) < 0.0
	if flip:
		up = -up
	var first := b.verts.size()
	for q in ([a, d, c] if flip else [a, c, d]):
		b.vertex(q, up, Vector2(q.x, q.z) / TILE_M)
	b.index.append_array([first, first + 2, first + 1])


## A quad from four corners round its edge, wound so that it faces `towards`.
func _quad(b: MeshBatch, p: Array, towards: Vector3) -> void:
	_tri(b, p[0], p[1], p[2], towards)
	_tri(b, p[0], p[2], p[3], towards)


## A mesh piece and its collision, as every other world piece is made (ArenaBuilder._piece).
func _piece(under: Node3D, piece_name: String, b: MeshBatch, material_for: Material, surface: int) -> void:
	if b.is_empty():
		return
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = piece_name
		mi.mesh = b.mesh()
		mi.material_override = material_for
		under.add_child(mi)
	var body := StaticBody3D.new()
	body.name = piece_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var cs := CollisionShape3D.new()
	cs.shape = b.shape()
	body.add_child(cs)
	under.add_child(body)
