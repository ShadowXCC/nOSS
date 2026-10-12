class_name PropLibrary
extends RefCounted
## Track props (docs/TRACK_EDITOR.md §2, EDT-03, D100): original low-poly pieces in the retro
## style, made in code. Each prop is a few parts (a material each, solid or not) in its own
## space: x across, y up, z along, standing on y = 0. `size` stretches the props that take one
## (a grandstand's length, a skidpad's radii).

## id: name, category, collide (simple shapes), scatter (offered by the scatter brush),
## slope (steepest ground it scatters on, rise over run), spacing (m between scattered ones).
const TYPES := {
	"tree_pine": { "name": "Pine", "category": "nature", "collide": true, "scatter": true, "slope": 0.7, "spacing": 4.0 },
	"tree_round": { "name": "Tree", "category": "nature", "collide": true, "scatter": true, "slope": 0.6, "spacing": 5.0 },
	"tree_billboard": { "name": "Flat tree", "category": "nature", "collide": false, "scatter": true, "slope": 0.8, "spacing": 4.0 },
	"bush": { "name": "Bush", "category": "nature", "collide": false, "scatter": true, "slope": 0.8, "spacing": 2.0 },
	"rock": { "name": "Rock", "category": "nature", "collide": true, "scatter": true, "slope": 1.2, "spacing": 3.0 },
	"grandstand": { "name": "Grandstand", "category": "buildings", "collide": true, "size": [13.0, 9.9, 110.0] },
	"pit_building": { "name": "Pit building", "category": "buildings", "collide": true, "size": [12.0, 9.0, 120.0] },
	"tent": { "name": "Tent", "category": "buildings", "collide": true },
	"marshal_post": { "name": "Marshal post", "category": "buildings", "collide": true },
	"billboard": { "name": "Billboard", "category": "trackside", "collide": true },
	"light_pole": { "name": "Light pole", "category": "trackside", "collide": true },
	"crowd": { "name": "Crowd", "category": "trackside", "collide": false, "size": [0.0, 0.0, 12.0] },
	"cone": { "name": "Cone", "category": "trackside", "collide": false, "scatter": true, "slope": 0.3, "spacing": 2.0 },
	"tyre_stack": { "name": "Tyre stack", "category": "trackside", "collide": true },
	"skidpad": { "name": "Skidpad", "category": "ground", "collide": true, "size": [72.0, 0.0, 60.0] },
}
const CATEGORIES := ["nature", "buildings", "trackside", "ground"]

static var _meshes := {}


## The props of a category as [[id, name]] (menus); all of them without one.
static func list(category := "", scatter_only := false) -> Array:
	var out := []
	for id: String in TYPES:
		var t: Dictionary = TYPES[id]
		if (category == "" or t.category == category) and (not scatter_only or t.get("scatter", false)):
			out.append([id, t.name])
	return out


static func size_of(id: String, size := Vector3.ZERO) -> Vector3:
	if size != Vector3.ZERO:
		return size
	var d: Array = TYPES.get(id, {}).get("size", [0.0, 0.0, 0.0])
	return Vector3(d[0], d[1], d[2])


## The prop's parts: [{suffix, material, surface (-1: not solid), batch: MeshBatch}], in its own space.
static func parts(id: String, size := Vector3.ZERO) -> Array:
	var s := size_of(id, size)
	match id:
		"grandstand":
			return _grandstand(s.z)
		"pit_building":
			var b := MeshBatch.new()
			b.box(Vector3(0, 4.5, 0), Basis(), Vector3(12.0, 9.0, s.z), Vector2(s.z / 12.0, 1.0))
			return [_part("", "building", b, VehicleSim.SURFACE_CONCRETE)]
		"skidpad":
			return _skidpad(s.x, s.z)
		"tree_pine":
			return _pine()
		"tree_round":
			return _round_tree()
		"tree_billboard":
			var b := MeshBatch.new()
			b.quad([Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0), Vector3(0.25, 1, 0), Vector3(-0.25, 1, 0)], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
			return [_part("", "tree_billboard", b, -1)]
		"bush":
			var b := MeshBatch.new()
			_blob(b, Vector3(0, 0.7, 0), Vector3(1.6, 1.1, 1.6), 7)
			return [_part("", "leaves", b, -1)]
		"rock":
			var b := MeshBatch.new()
			_blob(b, Vector3(0, 0.6, 0), Vector3(2.2, 1.4, 1.8), 3)
			return [_part("", "rock", b, VehicleSim.SURFACE_CONCRETE)]
		"tent":
			var b := MeshBatch.new()
			_prism(b, Vector3(6.0, 3.0, 4.0))
			return [_part("", "canvas", b, VehicleSim.SURFACE_CONCRETE)]
		"marshal_post":
			var b := MeshBatch.new()
			b.box(Vector3(0, 1.25, 0), Basis(), Vector3(2.0, 2.5, 2.0))
			var roof := MeshBatch.new()
			roof.box(Vector3(0, 2.6, 0), Basis(), Vector3(2.4, 0.2, 2.4))
			return [_part("", "marshal", b, VehicleSim.SURFACE_CONCRETE), _part("Roof", "roof", roof, VehicleSim.SURFACE_CONCRETE)]
		"billboard":
			var posts := MeshBatch.new()
			for x: float in [-2.6, 2.6]:
				posts.box(Vector3(x, 2.0, 0), Basis(), Vector3(0.25, 4.0, 0.25))
			var panel := MeshBatch.new()
			panel.box(Vector3(0, 3.6, 0), Basis(), Vector3(6.0, 2.8, 0.2), Vector2(1, 1))
			return [_part("", "metal", posts, VehicleSim.SURFACE_CONCRETE), _part("Panel", "billboard", panel, VehicleSim.SURFACE_CONCRETE)]
		"light_pole":
			var pole := MeshBatch.new()
			_cylinder(pole, Vector3(0, 5.0, 0), 0.15, 10.0, 6)
			pole.box(Vector3(0, 10.1, 0.6), Basis(), Vector3(0.5, 0.25, 1.4))
			return [_part("", "metal", pole, VehicleSim.SURFACE_CONCRETE)]
		"crowd":
			var b := MeshBatch.new()
			var half := s.z / 2.0
			b.quad([Vector3(0, 0, -half), Vector3(0, 0, half), Vector3(0, 1.8, half), Vector3(0, 1.8, -half)], [Vector2(0, 1), Vector2(s.z / 8.0, 1), Vector2(s.z / 8.0, 0), Vector2(0, 0)])
			b.quad([Vector3(0, 0, half), Vector3(0, 0, -half), Vector3(0, 1.8, -half), Vector3(0, 1.8, half)], [Vector2(0, 1), Vector2(s.z / 8.0, 1), Vector2(s.z / 8.0, 0), Vector2(0, 0)])
			return [_part("", "crowd_cutout", b, -1)]
		"cone":
			var b := MeshBatch.new()
			_cone(b, Vector3.ZERO, 0.22, 0.7, 8)
			return [_part("", "cone", b, -1)]
		"tyre_stack":
			var b := MeshBatch.new()
			_cylinder(b, Vector3(0, 0.45, 0), 0.38, 0.9, 10)
			return [_part("", "tyre", b, VehicleSim.SURFACE_CONCRETE)]
	return []


## The prop as one mesh (a surface per part, its material set): for scatter MultiMeshes.
static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var m := ArrayMesh.new()
	for part: Dictionary in parts(id):
		var b: MeshBatch = part.batch
		var one := b.mesh()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, one.surface_get_arrays(0))
		m.surface_set_material(m.get_surface_count() - 1, material(String(part.material)))
	_meshes[id] = m
	return m


## A simple collision shape for one scattered prop at scale 1: {shape, offset} or {}.
static func scatter_shape(id: String) -> Dictionary:
	if not TYPES.get(id, {}).get("collide", false):
		return {}
	match id:
		"tree_pine", "tree_round":
			var c := CylinderShape3D.new()
			c.radius = 0.35
			c.height = 4.0
			return { "shape": c, "offset": Vector3(0, 2.0, 0) }
		"rock":
			var b := BoxShape3D.new()
			b.size = Vector3(1.9, 1.2, 1.5)
			return { "shape": b, "offset": Vector3(0, 0.6, 0) }
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	return { "shape": box, "offset": Vector3(0, 0.5, 0) }


static func material(key: String) -> Material:
	match key:
		"tree_billboard":
			var cached := WorldMaterials._cache.get("prop_tree_billboard") as Material
			if cached:
				return cached
			var m := StandardMaterial3D.new()
			m.albedo_texture = RetroTextures.tree()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			m.billboard_keep_scale = true
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			m.roughness = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			WorldMaterials._cache["prop_tree_billboard"] = m
			return m
		"crowd_cutout":
			var m := WorldMaterials.get_material("crowd_cutout", RetroTextures.crowd(), 0.9, 0.1)
			m.set_shader_parameter("alpha_scissor", true)
			return m
		"building":
			return WorldMaterials.get_material("building", RetroTextures.building(), 0.8, 0.2)
		"crowd":
			return WorldMaterials.get_material("crowd", RetroTextures.crowd(), 0.9, 0.1)
		"roof":
			return WorldMaterials.get_material("roof", null, 0.7, 0.2, false, Vector2.ONE, Color(0.35, 0.37, 0.4))
		"concrete":
			return WorldMaterials.get_material("concrete_world", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0)
		"paint":
			return WorldMaterials.get_material("paint_white", null, 0.6, 0.2, false, Vector2.ONE, Color(0.9, 0.9, 0.88))
		"bark":
			return WorldMaterials.get_material("bark", RetroTextures.dirt(), 1.0, 0.05, false, Vector2.ONE, Color(0.55, 0.42, 0.32))
		"leaves":
			return WorldMaterials.get_material("leaves", RetroTextures.grass(), 1.0, 0.05, false, Vector2(2, 2), Color(0.55, 0.75, 0.5))
		"pine":
			return WorldMaterials.get_material("pine", RetroTextures.grass(), 1.0, 0.05, false, Vector2(2, 2), Color(0.32, 0.5, 0.36))
		"rock":
			return WorldMaterials.get_material("rock", RetroTextures.rock(), 0.95, 0.1, true, Vector2.ONE / 2.0)
		"canvas":
			return WorldMaterials.get_material("canvas", null, 0.9, 0.1, false, Vector2.ONE, Color(0.92, 0.9, 0.86))
		"marshal":
			return WorldMaterials.get_material("marshal", null, 0.8, 0.2, false, Vector2.ONE, Color(0.95, 0.55, 0.12))
		"metal":
			return WorldMaterials.get_material("metal", null, 0.4, 0.6, false, Vector2.ONE, Color(0.62, 0.64, 0.68))
		"billboard":
			return WorldMaterials.get_material("billboard", RetroTextures.checker(), 0.6, 0.2, false, Vector2(6, 3))
		"cone":
			return WorldMaterials.get_material("cone", null, 0.6, 0.3, false, Vector2.ONE, Color(0.98, 0.45, 0.1))
		"tyre":
			return WorldMaterials.get_material("tyre_wall", RetroTextures.tyre_wall(), 0.9, 0.1)
	return WorldMaterials.get_material("concrete_world", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0)


# --- shapes ---------------------------------------------------------------------------------


static func _part(suffix: String, material_key: String, batch: MeshBatch, surface: int) -> Dictionary:
	return { "suffix": suffix, "material": material_key, "batch": batch, "surface": surface }


## Stepped rows rising away from the track (+x), a roof over them, as the first tracks had.
static func _grandstand(length: float) -> Array:
	var rows := MeshBatch.new()
	for row in 10:
		var rise := row * 0.8 + 0.6
		rows.box(Vector3(row * 1.2 + 0.6, rise / 2.0, 0), Basis(), Vector3(1.2, rise, length), Vector2(length / 8.0, 1.0))
	var roof := MeshBatch.new()
	roof.box(Vector3(6.0, 9.5, 0), Basis(), Vector3(13.0, 0.4, length + 4.0))
	return [_part("", "crowd", rows, VehicleSim.SURFACE_CONCRETE), _part("Roof", "roof", roof, VehicleSim.SURFACE_CONCRETE)]


## A concrete disc and its painted driving circle.
static func _skidpad(pad_radius: float, radius: float) -> Array:
	var pad := MeshBatch.new()
	for i in 72:
		var a0 := TAU * i / 72
		var a1 := TAU * (i + 1) / 72
		var first := pad.vertex(Vector3.ZERO, Vector3.UP, Vector2.ZERO)
		pad.vertex(Vector3(cos(a1), 0, sin(a1)) * pad_radius, Vector3.UP, Vector2.ZERO)
		pad.vertex(Vector3(cos(a0), 0, sin(a0)) * pad_radius, Vector3.UP, Vector2.ZERO)
		pad.index.append_array([first, first + 2, first + 1])
	var line := MeshBatch.new()
	for i in 120:
		var d0 := Vector3(cos(TAU * i / 120.0), 0, sin(TAU * i / 120.0))
		var d1 := Vector3(cos(TAU * (i + 1) / 120.0), 0, sin(TAU * (i + 1) / 120.0))
		var y := Vector3.UP * 0.01
		line.quad([d0 * (radius + 0.15) + y, d0 * (radius - 0.15) + y, d1 * (radius - 0.15) + y, d1 * (radius + 0.15) + y],
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	return [_part("", "concrete", pad, VehicleSim.SURFACE_CONCRETE), _part("Line", "paint", line, -1)]


static func _pine() -> Array:
	var trunk := MeshBatch.new()
	_cylinder(trunk, Vector3(0, 1.0, 0), 0.25, 2.0, 5)
	var crown := MeshBatch.new()
	for k in 3:
		_cone(crown, Vector3(0, 1.4 + k * 1.9, 0), 2.2 - k * 0.55, 3.2 - k * 0.4, 7)
	return [_part("", "bark", trunk, -1), _part("Crown", "pine", crown, -1)]


static func _round_tree() -> Array:
	var trunk := MeshBatch.new()
	_cylinder(trunk, Vector3(0, 1.4, 0), 0.3, 2.8, 5)
	var crown := MeshBatch.new()
	_blob(crown, Vector3(0, 4.4, 0), Vector3(4.2, 3.8, 4.2), 11)
	return [_part("", "bark", trunk, -1), _part("Crown", "leaves", crown, -1)]


static func _cylinder(b: MeshBatch, center: Vector3, radius: float, height: float, sides: int) -> void:
	var h := Vector3.UP * height / 2.0
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
		b.quad([p1 - h, p0 - h, p0 + h, p1 + h], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		var top := b.vertex(center + h, Vector3.UP, Vector2.ZERO)
		b.vertex(p0 + h, Vector3.UP, Vector2.ZERO)
		b.vertex(p1 + h, Vector3.UP, Vector2.ZERO)
		b.index.append_array([top, top + 1, top + 2])


static func _cone(b: MeshBatch, base: Vector3, radius: float, height: float, sides: int) -> void:
	var tip := base + Vector3.UP * height
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * radius
		var n := (p0 - tip).cross(p1 - tip).normalized() * -1.0
		var first := b.vertex(tip, n, Vector2(0.5, 0))
		b.vertex(p0, n, Vector2(0, 1))
		b.vertex(p1, n, Vector2(1, 1))
		b.index.append_array([first, first + 1, first + 2])


## A lumpy low-poly ball (an octahedron split once, pushed out by a seeded wobble).
static func _blob(b: MeshBatch, center: Vector3, size: Vector3, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var faces := [[2, 0, 4], [2, 4, 1], [2, 1, 5], [2, 5, 0], [3, 4, 0], [3, 1, 4], [3, 5, 1], [3, 0, 5]]
	var wobble := {}
	var at := func(d: Vector3) -> Vector3:
		var key := d.snappedf(0.001)
		if not wobble.has(key):
			wobble[key] = rng.randf_range(0.85, 1.12)
		return center + d.normalized() * float(wobble[key]) * size / 2.0
	for f: Array in faces:
		var a: Vector3 = dirs[f[0]]
		var c: Vector3 = dirs[f[1]]
		var e: Vector3 = dirs[f[2]]
		var ab := (a + c).normalized()
		var bc := (c + e).normalized()
		var ca := (e + a).normalized()
		for tri: Array in [[a, ab, ca], [ab, c, bc], [ca, bc, e], [ab, bc, ca]]:
			var p0: Vector3 = at.call(tri[0])
			var p1: Vector3 = at.call(tri[1])
			var p2: Vector3 = at.call(tri[2])
			var n := (p1 - p0).cross(p2 - p0).normalized()
			if n.dot(p0 - center) < 0.0:
				n = -n
			var first := b.vertex(p0, n, Vector2(p0.x, p0.z) / 2.0)
			b.vertex(p1, n, Vector2(p1.x, p1.z) / 2.0)
			b.vertex(p2, n, Vector2(p2.x, p2.z) / 2.0)
			# Wind so the face points out.
			if (p1 - p0).cross(p2 - p0).dot(p0 - center) > 0.0:
				b.index.append_array([first, first + 2, first + 1])
			else:
				b.index.append_array([first, first + 1, first + 2])


## A ridge tent: two sloped sides and two gable ends.
static func _prism(b: MeshBatch, size: Vector3) -> void:
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	var ridge := size.y
	var p := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(0, ridge, -hz), Vector3(0, ridge, hz)]
	b.quad([p[0], p[3], p[5], p[4]], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	b.quad([p[2], p[1], p[4], p[5]], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	for tri: Array in [[p[1], p[0], p[4]], [p[3], p[2], p[5]]]:
		var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		var first := b.vertex(tri[0], n, Vector2.ZERO)
		b.vertex(tri[1], n, Vector2.ZERO)
		b.vertex(tri[2], n, Vector2.ZERO)
		b.index.append_array([first, first + 2, first + 1])
