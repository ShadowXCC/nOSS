class_name SumoBuilder
extends Node3D
## Builds and keeps a sumo arena (D162): one slab per tier, the pit round them and the goo at the
## bottom. The slabs are remade as they shrink, so each one holds its own mesh and collision; the
## pit and the goo are built once. Nothing here is read from a track file.

const HAZARD_SHADER := preload("res://game/world/arena/sumo_hazard.gdshader")
const WARN_SHADER := preload("res://game/world/arena/sumo_warn.gdshader")
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
## They do not all go at once -- each lump waits its turn, up to CHUNK_DELAY_S, so the ring calves
## round rather than bursting (D182).
const CHUNKS := 14
const CHUNK_LIFE_S := 4.0
const CHUNK_SPIN := 2.5
const CHUNK_DELAY_S := 0.35
## Lumps thrown by one wedge's bite. A whole ring going at once shares CHUNKS between its wedges
## instead, so the finale is a ring's worth of debris and not sixteen times one.
const WEDGE_CHUNKS := 5
const GRAVITY := 9.81
## The warning band sits this far above the floor, so it reads as light on the deck instead of
## fighting it for the same depth.
const WARN_LIFT_M := 0.06

var layout: SumoLayout
var visual := true
## Reduce flashing: the goo churns and glows less (ACC-04).
var calm := false

var _slabs: Array[Node3D] = []
## Each tier's wedge radii as its slab was last built from them.
var _built: Array[PackedFloat32Array] = []
## Lumps of a crumbled ring on their way into the goo: [{node, vel, spin, life, delay}].
var _debris: Array[Dictionary] = []
## The warning bands (D182), one mesh a tier, and what each was last built from. Nothing is made
## at all on a game with no screen, which is why this is not built until _warning says so.
var _warn: Node3D
var _warn_meshes: Array[MeshInstance3D] = []
var _warn_keys := PackedInt64Array()


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
		_built.append(PackedFloat32Array())
	_warning()
	refresh()


## The warning bands: one mesh a tier, made once and then only ever reshaped or hidden, so a
## platform marking its next ring costs no allocation. Drawn only, and only on a game with a
## screen -- a dedicated server has nothing to warn.
func _warning() -> void:
	if not visual:
		return
	_warn = Node3D.new()
	_warn.name = "Warn"
	add_child(_warn)
	var material := warn_material()
	for i in layout.count():
		var mi := MeshInstance3D.new()
		mi.name = "Warn%d" % (i + 1)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		_warn.add_child(mi)
		_warn_meshes.append(mi)
		_warn_keys.append(-1)


## Remakes any slab that has shrunk since it was last built, and clears away the ones that have
## gone. Cheap enough to call every frame; it only does work when a radius has really moved.
func refresh() -> void:
	for i in _slabs.size():
		# A platform that has gone reads as every wedge at nothing, so the last of it is thrown
		# into the goo like the rest was rather than vanishing where it stood.
		var radii := layout.wedge_radii(i)
		if not _moved(i, radii):
			continue
		# A crumbling platform throws the floor it just lost into the goo (D162).
		if visual and layout.style == "crumble":
			_calve(i, radii)
		_built[i] = radii
		_clear(_slabs[i])
		if layout.live(i):
			_slab(_slabs[i], radii, layout.floor_y_of(i))
	_warn_refresh()


## Whether any of tier `i`'s wedges has moved far enough to be worth building again.
func _moved(i: int, radii: PackedFloat32Array) -> bool:
	var was: PackedFloat32Array = _built[i]
	if was.size() != radii.size():
		return true
	for w in radii.size():
		if absf(radii[w] - was[w]) >= REBUILD_M:
			return true
	return false


## Throws into the goo whatever each wedge has lost since the slab was last built: one bite from
## one wedge most of the time, and the whole of the last ring at the end.
func _calve(i: int, radii: PackedFloat32Array) -> void:
	var was: PackedFloat32Array = _built[i]
	if was.size() != radii.size():
		return
	var losing := 0
	for w in radii.size():
		if was[w] > radii[w] + 0.01:
			losing += 1
	if losing == 0:
		return
	var lumps := WEDGE_CHUNKS if losing <= 2 else maxi(CHUNKS / losing, 1)
	var per: int = SumoLayout.SEGMENTS / SumoLayout.SECTORS
	for w in radii.size():
		if was[w] <= radii[w] + 0.01:
			continue
		_crumble(radii[w], was[w], layout.floor_y_of(i),
			TAU * (w * per) / SumoLayout.SEGMENTS, TAU * (w * per + per) / SumoLayout.SEGMENTS, lumps)


## The band over the floor that is about to go (D182). Rebuilt only when the marked floor really
## changes -- about once a ring for a stepped platform -- so calling it every frame costs nothing.
func _warn_refresh() -> void:
	for i in _warn_meshes.size():
		var mask := layout.warning(i)
		var mi := _warn_meshes[i]
		if mask == 0 or not layout.live(i):
			if _warn_keys[i] != -1:
				_warn_keys[i] = -1
				mi.visible = false
				mi.mesh = null
			continue
		var radii := layout.wedge_radii(i)
		var key := hash([mask, radii])
		if key == _warn_keys[i]:
			continue
		_warn_keys[i] = key
		var b := MeshBatch.new()
		var y := layout.floor_y_of(i) + WARN_LIFT_M
		for w in SumoLayout.SECTORS:
			if mask & (1 << w) != 0:
				_band(b, layout.next_radius(i, w), radii[w], y, w)
		mi.mesh = b.mesh() if not b.is_empty() else null
		mi.visible = mi.mesh != null


## One wedge's band of floor, `inner` out to `outer` at `y`, facing up.
func _band(b: MeshBatch, inner: float, outer: float, y: float, w: int) -> void:
	if outer <= inner + 0.01:
		return
	var per: int = SumoLayout.SEGMENTS / SumoLayout.SECTORS
	for k in per:
		var a0 := TAU * (w * per + k) / SumoLayout.SEGMENTS
		var a1 := TAU * (w * per + k + 1) / SumoLayout.SEGMENTS
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		_quad(b, [d0 * inner + Vector3.UP * y, d1 * inner + Vector3.UP * y,
			d1 * outer + Vector3.UP * y, d0 * outer + Vector3.UP * y], Vector3.UP)


## A new match: the slabs are built again from scratch, the warning bands come down, and anything
## still falling from the last match is cleared away rather than dropping through this one.
func restore() -> void:
	for d in _debris:
		if is_instance_valid(d.node):
			(d.node as Node3D).queue_free()
	_debris.clear()
	for i in _built.size():
		_built[i] = PackedFloat32Array()
	for i in _warn_meshes.size():
		_warn_keys[i] = -1
		_warn_meshes[i].visible = false
		_warn_meshes[i].mesh = null
	refresh()


func _clear(under: Node3D) -> void:
	for c in under.get_children():
		under.remove_child(c)
		c.queue_free()


## Throws the floor between `inner` and `outer`, over the arc from `a0` to `a1`, off as lumps that
## tumble into the goo. They are scenery only: the floor has already gone, so nothing drives on
## them. Each lump waits a little longer than the one before it, so the piece calves round from
## one end instead of the whole of it leaving on a single tick (D182).
func _crumble(inner: float, outer: float, y: float, a0 := 0.0, a1 := TAU, lumps := CHUNKS) -> void:
	var mid := (inner + outer) / 2.0
	var width := maxf(outer - inner, 1.0)
	var span := a1 - a0
	var material := WorldMaterials.surface(VehicleSim.SURFACE_CONCRETE)
	for i in lumps:
		var ang := a0 + span * (i + randf() * 0.6) / lumps
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var at := dir * mid + Vector3.UP * (y - THICK_M / 2.0)
		var b := MeshBatch.new()
		var basis := Basis(Vector3.UP, ang)
		b.box(Vector3.ZERO, basis, Vector3(width * randf_range(0.5, 0.9), THICK_M, span * mid / lumps * randf_range(0.5, 0.9)))
		var delay := CHUNK_DELAY_S * float(i) / maxf(float(lumps - 1), 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = b.mesh()
		mi.material_override = material
		mi.position = at
		mi.visible = is_zero_approx(delay)
		add_child(mi)
		_debris.append({
			"node": mi,
			"vel": dir * randf_range(0.5, 2.5) + Vector3.UP * randf_range(-0.5, 1.5),
			"spin": Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * CHUNK_SPIN * randf(),
			"life": CHUNK_LIFE_S,
			"delay": delay,
		})


func _process(delta: float) -> void:
	if _debris.is_empty():
		return
	var still: Array[Dictionary] = []
	for d in _debris:
		var mi: Variant = d.node
		if not is_instance_valid(mi):
			continue
		if float(d.delay) > 0.0:
			# Still attached, waiting its turn.
			d.delay = float(d.delay) - delta
			if float(d.delay) <= 0.0:
				(mi as Node3D).visible = true
			still.append(d)
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


## One tier, a wedge at a time: the floor out to each wedge's own radius at `y`, a rim sloping out
## to the lip and a side down to the underside. The lip is not playable floor; it is there to catch
## a car that lands on the edge. One mesh and one collision shape for the whole tier, as before --
## a crumbling platform is rebuilt about once a second, where a smooth one is rebuilt five times.
func _slab(under: Node3D, radii: PackedFloat32Array, y: float) -> void:
	var b := MeshBatch.new()
	var per: int = SumoLayout.SEGMENTS / SumoLayout.SECTORS
	var low := y - THICK_M
	var rim := y - LIP_DROP_M
	var mid := Vector3(0, y, 0)
	var below := Vector3(0, low, 0)
	for w in radii.size():
		var r: float = radii[w]
		if r <= 0.01:
			continue
		var lip := r + SumoLayout.LIP_M
		for k in per:
			var a0 := TAU * (w * per + k) / SumoLayout.SEGMENTS
			var a1 := TAU * (w * per + k + 1) / SumoLayout.SEGMENTS
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var t0 := d0 * r + Vector3.UP * y
			var t1 := d1 * r + Vector3.UP * y
			var e0 := d0 * lip + Vector3.UP * rim
			var e1 := d1 * lip + Vector3.UP * rim
			var u0 := d0 * lip + Vector3.UP * low
			var u1 := d1 * lip + Vector3.UP * low
			_tri(b, mid, t0, t1, Vector3.UP) # the floor
			_quad(b, [t0, t1, e1, e0], Vector3.UP) # the catch lip
			_quad(b, [e0, e1, u1, u0], (d0 + d1).normalized()) # the side
			_tri(b, below, u1, u0, Vector3.DOWN) # the underside
		_cap(b, radii, w, y, low)
	if b.is_empty():
		return
	_piece(under, "Deck", b, WorldMaterials.surface(VehicleSim.SURFACE_CONCRETE), VehicleSim.SURFACE_CONCRETE)


## The wall that closes the step where wedge `w` stands taller than the wedge beside it. Only the
## taller side of a boundary draws one, so two wedges never put a face in the same place, and it
## covers the taller wedge's whole cross-section, so nothing is ever seen through the slab.
func _cap(b: MeshBatch, radii: PackedFloat32Array, w: int, y: float, low: float) -> void:
	var r: float = radii[w]
	var per: int = SumoLayout.SEGMENTS / SumoLayout.SECTORS
	for side: int in [-1, 1]:
		var nb := (w + side + SumoLayout.SECTORS) % SumoLayout.SECTORS
		if radii[nb] >= r - 0.001:
			continue
		var ang := TAU * (w * per + (per if side > 0 else 0)) / SumoLayout.SEGMENTS
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var inner: float = maxf(radii[nb], 0.0)
		var outer := r + SumoLayout.LIP_M
		# Facing the shorter wedge, round the way the angles run.
		var towards := Vector3(-sin(ang), 0.0, cos(ang)) * (1.0 if side > 0 else -1.0)
		_quad(b, [d * inner + Vector3.UP * y, d * outer + Vector3.UP * y,
			d * outer + Vector3.UP * low, d * inner + Vector3.UP * low], towards)


## The pit the platforms hang in: a rock wall round them and a floor under the goo.
func _pit() -> void:
	var holder := Node3D.new()
	holder.name = "Pit"
	add_child(holder)
	var rock := WorldMaterials.get_material("sumo_rock", RetroTextures.rock(), 0.95, 0.1)
	var wall := MeshBatch.new()
	var bottom := layout.hazard_y - PIT_FLOOR_DROP_M
	var top := layout.floor_y_of(0) + SumoLayout.PIT_RIM_M
	_cliff(wall, layout.pit_r, bottom, top)
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


## The warning band's material (D182): the goo's own colour, so the band says what that floor is
## about to become. Steady and dimmer with reduce flashing, as the goo itself is (ACC-04).
func warn_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WARN_SHADER
	m.set_shader_parameter("tint", Color(0.49, 1.0, 0.16) if layout.hazard == "acid" else Color(1.0, 0.45, 0.08))
	m.set_shader_parameter("calm", 1.0 if calm else 0.0)
	return m


## The pit's rock face: a band round the inside of `radius` from `bottom` up to `top`. Its own
## quads rather than MeshBatch.wall's boxes, so the texture tiles up the face instead of being
## stretched once over the whole height (which reads as vertical streaks).
func _cliff(b: MeshBatch, radius: float, bottom: float, top: float) -> void:
	var n := SumoLayout.SEGMENTS
	var step := TAU * radius / n
	var rows := maxi(roundi((top - bottom) / TILE_M), 1)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var u0 := step * i / TILE_M
		var u1 := step * (i + 1) / TILE_M
		for r in rows:
			var y0 := lerpf(bottom, top, float(r) / rows)
			var y1 := lerpf(bottom, top, float(r + 1) / rows)
			# Facing inward, toward the middle.
			var inward := -(d0 + d1).normalized()
			var first := b.verts.size()
			b.vertex(d0 * radius + Vector3.UP * y0, inward, Vector2(u0, float(r)))
			b.vertex(d1 * radius + Vector3.UP * y0, inward, Vector2(u1, float(r)))
			b.vertex(d1 * radius + Vector3.UP * y1, inward, Vector2(u1, float(r + 1)))
			b.vertex(d0 * radius + Vector3.UP * y1, inward, Vector2(u0, float(r + 1)))
			# Godot's fronts are clockwise, as _tri winds them.
			b.index.append_array([first, first + 2, first + 1, first, first + 3, first + 2])


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
