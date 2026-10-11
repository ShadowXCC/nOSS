class_name TrackBuilder
extends RefCounted
## Builds a drivable track scene from TrackData: road, curbs, terrain, barriers, buildings
## and scenery, with surface tags for the tire model (docs/PHYSICS.md §4).

const WORLD_SHADER := preload("res://game/world/noss_world.gdshader")
const ROAD_TILE_M := 8.0
const CURB_WIDTH := TrackData.CURB_WIDTH
const CURB_HEIGHT := 0.045
const GRASS_Y := -0.03
const BARRIER_CURVATURE := 1.0 / 260.0
const RUNOFF := 16.0
const TREE_COUNT := 1400

var track: TrackData
var root: Node3D
var _materials := {}


static func build(data: TrackData) -> Node3D:
	var b := TrackBuilder.new()
	b.track = data
	b.root = Node3D.new()
	b.root.name = "Track"
	b._road()
	b._curbs()
	b._terrain()
	b._skidpad()
	b._barriers()
	b._start_gantry()
	b._grandstand()
	b._pit_building()
	b._trees()
	return b.root


# --- parts ------------------------------------------------------------------------------


func _road() -> void:
	var st := _begin()
	var n := track.samples.size()
	var half := track.width / 2.0
	var tiles := maxf(roundf(track.length / ROAD_TILE_M), 1.0)
	for i in n:
		var j := (i + 1) % n
		var v0 := track.distances[i] / track.length * tiles
		var v1 := (track.distances[j] if j > 0 else track.length) / track.length * tiles
		var li := track.samples[i] + track.lefts[i] * half
		var ri := track.samples[i] - track.lefts[i] * half
		var lj := track.samples[j] + track.lefts[j] * half
		var rj := track.samples[j] - track.lefts[j] * half
		var edge := Color(0.82, 0.82, 0.82)
		_quad(st, [li, ri, rj, lj], [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)], [edge, edge, edge, edge])
	_add_body("Road", st, _material("asphalt", RetroTextures.asphalt(), 0.85, 0.3), VehicleSim.SURFACE_ASPHALT)


func _curbs() -> void:
	var n := track.samples.size()
	var st := _begin()
	var any := false
	var half := track.width / 2.0
	for side: float in [1.0, -1.0]:
		for i in n:
			var j := (i + 1) % n
			# Curbs on both edges through corners, extended a little either side.
			if not track.curbs[i]:
				continue
			any = true
			var v0 := track.distances[i] / 3.0
			var v1 := (track.distances[j] if j > 0 else track.length) / 3.0
			# Profile across: road edge (flush), crown, outer lip.
			var profile := [[0.0, 0.0], [0.35, CURB_HEIGHT], [CURB_WIDTH, CURB_HEIGHT * 0.6]]
			for p in 2:
				var a: Array = profile[p]
				var b: Array = profile[p + 1]
				var ai: Vector3 = track.samples[i] + track.lefts[i] * side * (half + a[0]) + Vector3.UP * a[1]
				var bi: Vector3 = track.samples[i] + track.lefts[i] * side * (half + b[0]) + Vector3.UP * b[1]
				var aj: Vector3 = track.samples[j] + track.lefts[j] * side * (half + a[0]) + Vector3.UP * a[1]
				var bj: Vector3 = track.samples[j] + track.lefts[j] * side * (half + b[0]) + Vector3.UP * b[1]
				var quad := [ai, bi, bj, aj] if side < 0.0 else [bi, ai, aj, bj]
				_quad(st, quad, [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)], [])
			# Outer face down to the grass.
			var o := track.lefts[i] * side * (half + CURB_WIDTH)
			var oj := track.lefts[j] * side * (half + CURB_WIDTH)
			var top_i := track.samples[i] + o + Vector3.UP * CURB_HEIGHT * 0.6
			var top_j := track.samples[j] + oj + Vector3.UP * CURB_HEIGHT * 0.6
			var low_i := track.samples[i] + o + Vector3.UP * GRASS_Y
			var low_j := track.samples[j] + oj + Vector3.UP * GRASS_Y
			var face := [low_i, top_i, top_j, low_j] if side > 0.0 else [top_i, low_i, low_j, top_j]
			_quad(st, face, [Vector2(0, v0), Vector2(0, v0), Vector2(0, v1), Vector2(0, v1)], [])
	if any:
		_add_body("Curbs", st, _material("curb", RetroTextures.curb(), 0.6, 0.3), VehicleSim.SURFACE_CURB)


func _terrain() -> void:
	var bounds := _bounds()
	var size := maxf(bounds.size.x, bounds.size.z) + 4000.0
	var center := bounds.get_center()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	mesh.subdivide_width = 0
	mesh.subdivide_depth = 0
	var mi := MeshInstance3D.new()
	mi.name = "Grass"
	mi.mesh = mesh
	mi.position = Vector3(center.x, GRASS_Y, center.z)
	var m := _material("grass", RetroTextures.grass(), 1.0, 0.1, true, Vector2.ONE / 5.0)
	m.set_shader_parameter("variation", 0.22)
	m.set_shader_parameter("variation_noise", RetroTextures.variation())
	mi.material_override = m
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GrassBody"
	body.set_meta(&"noss_surface", VehicleSim.SURFACE_GRASS)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bounds.size.x + 1200.0, 10.0, bounds.size.z + 1200.0)
	shape.shape = box
	shape.position = Vector3(center.x, GRASS_Y - 5.0, center.z)
	body.add_child(shape)
	root.add_child(body)


func _skidpad() -> void:
	var pad: Dictionary = track.raw.get("skidpad", {})
	if pad.is_empty():
		return
	var c := Vector3(pad.center[0], 0.0, pad.center[1])
	var radius: float = pad.get("pad_radius_m", 72.0)
	var st := _begin()
	var segs := 72
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * radius
		_tri(st, c, p1, p0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	var m := _material("concrete_world", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0)
	_add_body("Skidpad", st, m, VehicleSim.SURFACE_CONCRETE)
	# Painted driving circle.
	var line := _begin()
	var r: float = pad.get("radius_m", 60.0)
	for i in 120:
		var a0 := TAU * i / 120.0
		var a1 := TAU * (i + 1) / 120.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var y := Vector3.UP * 0.01
		_quad(line, [c + d0 * (r + 0.15) + y, c + d0 * (r - 0.15) + y, c + d1 * (r - 0.15) + y, c + d1 * (r + 0.15) + y], _uv4(), [])
	var lm := MeshInstance3D.new()
	lm.name = "SkidpadLine"
	lm.mesh = line.commit()
	lm.material_override = _material("paint_white", null, 0.6, 0.2, false, Vector2.ONE, Color(0.9, 0.9, 0.88))
	root.add_child(lm)


func _barriers() -> void:
	var n := track.samples.size()
	var st := _begin()
	var height := 0.9
	var thick := 1.0
	var offset := track.width / 2.0 + RUNOFF
	var run := PackedVector3Array()
	var tiles := 0.0
	for i in n + 1:
		var k := i % n
		var kappa := track.curvature[k]
		var p := track.samples[k] - track.lefts[k] * signf(kappa) * offset
		var ok := absf(kappa) > BARRIER_CURVATURE and _clear_of_track(p, track.width / 2.0 + 6.0)
		if ok and i < n:
			run.append(p)
		elif run.size() > 1:
			tiles = _wall(st, run, height, thick, tiles)
			run.clear()
		else:
			run.clear()
	# Perimeter wall around the whole site.
	var b := _bounds().grow(150.0)
	var corners := [Vector3(b.position.x, 0, b.position.z), Vector3(b.end.x, 0, b.position.z), Vector3(b.end.x, 0, b.end.z), Vector3(b.position.x, 0, b.end.z)]
	for i in 4:
		_wall(st, PackedVector3Array([corners[i], corners[(i + 1) % 4]]), 1.6, 1.0, 0.0)
	_add_body("Barriers", st, _material("tyre_wall", RetroTextures.tyre_wall(), 0.9, 0.1), VehicleSim.SURFACE_CONCRETE)


func _start_gantry() -> void:
	var t := track.transform_at(track.start_m)
	var half := track.width / 2.0
	# Chequered line on the road.
	var st := _begin()
	var f := t.basis.z * 0.7
	var l := t.basis.x * half
	var y := Vector3.UP * 0.008
	_quad(st, [t.origin + l - f + y, t.origin - l - f + y, t.origin - l + f + y, t.origin + l + f + y], [Vector2(0, 0), Vector2(8, 0), Vector2(8, 1), Vector2(0, 1)], [])
	var line := MeshInstance3D.new()
	line.name = "StartLine"
	line.mesh = st.commit()
	line.material_override = _material("checker", RetroTextures.checker(), 0.7, 0.2)
	root.add_child(line)
	# Pillars and a banner over the road.
	var gantry := _begin()
	for side: float in [1.0, -1.0]:
		_box(gantry, t.origin + t.basis.x * side * (half + 2.0) + Vector3.UP * 3.5, t.basis, Vector3(0.6, 7.0, 0.6))
	_box(gantry, t.origin + Vector3.UP * 7.3, t.basis, Vector3(track.width + 5.0, 1.2, 0.5))
	_add_body("Gantry", gantry, _material("gantry", RetroTextures.checker(), 0.6, 0.2, false, Vector2(6, 1)), VehicleSim.SURFACE_CONCRETE)


func _grandstand() -> void:
	var g: Dictionary = track.raw.get("grandstand", {})
	if g.is_empty():
		return
	var side := 1.0 if g.get("side", "left") == "left" else -1.0
	var t := track.transform_at(float(g.at_m))
	var length: float = g.get("length_m", 100.0)
	var st := _begin()
	var base := t.origin + t.basis.x * side * (track.width / 2.0 + 14.0)
	# Stepped rows rising away from the track.
	for row in 10:
		var out := t.basis.x * side * (row * 1.2 + 0.6)
		var rise := row * 0.8 + 0.6
		_box(st, base + out + Vector3.UP * rise / 2.0, t.basis, Vector3(1.2, rise, length), Vector2(length / 8.0, 1.0))
	_add_body("Grandstand", st, _material("crowd", RetroTextures.crowd(), 0.9, 0.1), VehicleSim.SURFACE_CONCRETE)
	var roof := _begin()
	_box(roof, base + t.basis.x * side * 6.0 + Vector3.UP * 9.5, t.basis, Vector3(13.0, 0.4, length + 4.0))
	_add_body("GrandstandRoof", roof, _material("roof", null, 0.7, 0.2, false, Vector2.ONE, Color(0.35, 0.37, 0.4)), VehicleSim.SURFACE_CONCRETE)


func _pit_building() -> void:
	var p: Dictionary = track.raw.get("pit_building", {})
	if p.is_empty():
		return
	var side := 1.0 if p.get("side", "right") == "left" else -1.0
	var t := track.transform_at(float(p.at_m))
	var length: float = p.get("length_m", 120.0)
	var st := _begin()
	var center := t.origin + t.basis.x * side * (track.width / 2.0 + 26.0) + Vector3.UP * 4.5
	_box(st, center, t.basis, Vector3(12.0, 9.0, length), Vector2(length / 12.0, 1.0))
	_add_body("PitBuilding", st, _material("building", RetroTextures.building(), 0.8, 0.2), VehicleSim.SURFACE_CONCRETE)


func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track.id)
	var bounds := _bounds().grow(400.0)
	var pad: Dictionary = track.raw.get("skidpad", {})
	var pad_c := Vector3(pad.center[0], 0, pad.center[1]) if not pad.is_empty() else Vector3(INF, 0, INF)
	var pad_r: float = pad.get("pad_radius_m", 0.0) + 15.0
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < TREE_COUNT and tries < TREE_COUNT * 20:
		tries += 1
		var p := Vector3(rng.randf_range(bounds.position.x, bounds.end.x), 0, rng.randf_range(bounds.position.z, bounds.end.z))
		if p.distance_to(pad_c) < pad_r or not _clear_of_track(p, track.width / 2.0 + RUNOFF + 12.0):
			continue
		var s := rng.randf_range(7.0, 13.0)
		transforms.append(Transform3D(Basis.from_scale(Vector3(s * 0.5, s, s * 0.5)), p + Vector3.UP * s * 0.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var m := StandardMaterial3D.new()
	m.albedo_texture = RetroTextures.tree()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


# --- helpers ------------------------------------------------------------------------------


func _bounds() -> AABB:
	var b := AABB(track.samples[0], Vector3.ZERO)
	for p in track.samples:
		b = b.expand(p)
	return b


func _clear_of_track(p: Vector3, min_distance: float) -> bool:
	return not track.is_near_centreline(p, min_distance)


## Extrudes a wall along a path. Returns the running texture coordinate.
func _wall(st: SurfaceTool, path: PackedVector3Array, height: float, thick: float, u: float) -> float:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var dir := (b - a)
		var len := dir.length()
		if len < 0.01:
			continue
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
		_box(st, (a + b) / 2.0 + Vector3.UP * height / 2.0, basis, Vector3(thick, height, len + thick * 0.5), Vector2(len / 4.0, 1.0), u)
		u += len / 4.0
	return u


## Oriented box. size is along the basis' x, y, z.
func _box(st: SurfaceTool, center: Vector3, basis: Basis, size: Vector3, uv_scale := Vector2.ONE, u0 := 0.0) -> void:
	var h := size / 2.0
	var c := []
	for i in 8:
		c.append(center + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var faces := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	for f: Array in faces:
		var uvs := [Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + uv_scale.x, 0), Vector2(u0 + uv_scale.x, 1)]
		_quad(st, [c[f[0]], c[f[1]], c[f[2]], c[f[3]]], uvs, [])


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Quad from counter-clockwise (outward-facing) corners.
func _quad(st: SurfaceTool, p: Array, uv: Array, colors: Array) -> void:
	var c := colors if colors.size() == 4 else [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
	_tri(st, p[0], p[1], p[2], uv[0], uv[1], uv[2], c[0], c[1], c[2])
	_tri(st, p[0], p[2], p[3], uv[0], uv[2], uv[3], c[0], c[2], c[3])


## Godot's front faces are clockwise; this takes counter-clockwise triangles.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ca := Color.WHITE, cb := Color.WHITE, cc := Color.WHITE) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v: Array in [[a, ua, ca], [c, uc, cc], [b, ub, cb]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.set_color(v[2])
		st.add_vertex(v[0])


func _uv4() -> Array:
	return [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


func _add_body(node_name: String, st: SurfaceTool, material: Material, surface: int) -> void:
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)


func _material(key: String, texture: Texture2D, roughness: float, specular: float, world_uv := false, uv_scale := Vector2.ONE, tint := Color.WHITE) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	if texture:
		m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("albedo", tint)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("specular", specular)
	m.set_shader_parameter("world_uv", world_uv)
	m.set_shader_parameter("uv_scale", uv_scale)
	_materials[key] = m
	return m
