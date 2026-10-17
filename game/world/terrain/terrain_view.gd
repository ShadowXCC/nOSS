class_name TerrainView
extends Node3D
## Draws a terrain (D90). Each chunk shows one of four shared grids (1, 2, 4 and 8 m apart),
## picked by distance per camera (visibility ranges, so splitscreen views each get their own),
## displaced by the chunk's height texture and painted from its splat maps. A plain far ground
## carries on past the edge into the fog.

const SHADER := preload("res://game/world/terrain/noss_terrain.gdshader")
## [grid step in cells, visible from, to (0: no end)].
const LODS := [[1, 0.0, 250.0], [2, 250.0, 600.0], [4, 600.0, 1400.0], [8, 1400.0, 0.0]]
const LOD_MARGIN := 20.0
const FAR_SIZE := 8000.0

static var _grids := {} # step -> ArrayMesh

var terrain: TerrainData
var _chunks := {} # Vector2i -> {material, height: ImageTexture, splat: [ImageTexture, ImageTexture], meshes: [MeshInstance3D]}
var _far: MeshInstance3D


## With `far` off, no far ground round it (an endless tile: its neighbours and the far tiles are).
static func build(t: TerrainData, far := true) -> TerrainView:
	var v := TerrainView.new()
	v.name = "TerrainView"
	v.terrain = t
	var n := t.chunks()
	for cz in n.y:
		for cx in n.x:
			v._make_chunk(Vector2i(cx, cz))
	if far:
		v._make_far()
	return v


## Heights changed in `rect` (samples): those chunks' textures and bounds follow.
func update_rect(rect: Rect2i) -> void:
	for c in terrain.chunks_in(rect):
		if _chunks.has(c):
			_update_heights(c)


## Paint changed in `rect` (samples).
func update_paint(rect: Rect2i) -> void:
	for c in terrain.chunks_in(rect):
		if _chunks.has(c):
			_update_paint(c)


func _make_chunk(c: Vector2i) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("layers", RetroTextures.terrain_layers())
	m.set_shader_parameter("variation_noise", RetroTextures.variation())
	m.set_shader_parameter("chunk_cells", float(TerrainData.CHUNK))
	var entry := { "material": m, "height": null, "splat": [null, null], "meshes": [] }
	_chunks[c] = entry
	var at := terrain.origin() + Vector2(c) * TerrainData.CHUNK
	for lod: Array in LODS:
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d_x%d" % [c.x, c.y, lod[0]]
		mi.mesh = _grid(int(lod[0]))
		var lm := m.duplicate() as ShaderMaterial # each grid needs its own lod_step
		lm.set_shader_parameter("lod_step", float(lod[0]))
		mi.material_override = lm
		mi.position = Vector3(at.x, 0.0, at.y)
		mi.visibility_range_begin = lod[1]
		mi.visibility_range_end = lod[2]
		mi.visibility_range_begin_margin = LOD_MARGIN if lod[1] > 0.0 else 0.0
		mi.visibility_range_end_margin = LOD_MARGIN if lod[2] > 0.0 else 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod[0] <= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		entry.meshes.append(mi)
	_update_heights(c)
	_update_paint(c)


func _update_heights(c: Vector2i) -> void:
	var entry: Dictionary = _chunks[c]
	var range := terrain.field.chunk_range(c.x, c.y, TerrainData.CHUNK)
	var h_min := range.x - 1.0
	var h_range := maxf(range.y - range.x + 2.0, 1.0)
	var side := TerrainData.CHUNK + 3
	var img := Image.create_from_data(side, side, false, Image.FORMAT_R16, terrain.field.chunk_r16(c.x, c.y, TerrainData.CHUNK, h_min, h_range))
	if entry.height == null:
		entry.height = ImageTexture.create_from_image(img)
	else:
		(entry.height as ImageTexture).update(img)
	# The grid is flat until the shader lifts it: its bounds come from the heights.
	var aabb := AABB(Vector3(0.0, range.x - 2.5, 0.0), Vector3(TerrainData.CHUNK, range.y - range.x + 3.0, TerrainData.CHUNK))
	for mi: MeshInstance3D in entry.meshes:
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("height_tex", entry.height)
		m.set_shader_parameter("h_min", h_min)
		m.set_shader_parameter("h_range", h_range)
		mi.custom_aabb = aabb


func _update_paint(c: Vector2i) -> void:
	var entry: Dictionary = _chunks[c]
	var side := TerrainData.CHUNK + 1
	for image in 2:
		var img := Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, terrain.field.chunk_splat(c.x, c.y, TerrainData.CHUNK, image))
		if entry.splat[image] == null:
			entry.splat[image] = ImageTexture.create_from_image(img)
		else:
			(entry.splat[image] as ImageTexture).update(img)
	for mi: MeshInstance3D in entry.meshes:
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("splat_0", entry.splat[0])
		m.set_shader_parameter("splat_1", entry.splat[1])


## Grass on past the edge, a little below its lowest point, into the fog.
func _make_far() -> void:
	var a := terrain.area()
	var lowest := INF
	for i in 64:
		var t := float(i) / 64.0
		for p: Vector2 in [Vector2(t, 0), Vector2(t, 1), Vector2(0, t), Vector2(1, t)]:
			lowest = minf(lowest, terrain.height_at(a.position.x + p.x * a.size.x, a.position.y + p.y * a.size.y))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(FAR_SIZE, FAR_SIZE)
	_far = MeshInstance3D.new()
	_far.name = "FarGround"
	_far.mesh = mesh
	_far.position = Vector3(a.get_center().x, lowest - 1.5, a.get_center().y)
	var m := ShaderMaterial.new()
	m.shader = preload("res://game/world/noss_world.gdshader")
	m.set_shader_parameter("albedo_texture", RetroTextures.grass())
	m.set_shader_parameter("world_uv", true)
	m.set_shader_parameter("uv_scale", Vector2.ONE / 4.0)
	m.set_shader_parameter("roughness", 1.0)
	m.set_shader_parameter("specular", 0.1)
	m.set_shader_parameter("variation", 0.2)
	m.set_shader_parameter("variation_noise", RetroTextures.variation())
	_far.material_override = m
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_far)


## A chunk's grid with `step` cells between vertices, and a skirt under its edge (UV2.x = 1)
## so neighbours at other spacings never show gaps. Shared by every chunk.
static func _grid(step: int) -> ArrayMesh:
	if _grids.has(step):
		return _grids[step]
	var n := TerrainData.CHUNK / step + 1
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	for z in n:
		for x in n:
			verts.append(Vector3(x * step, 0.0, z * step))
			uv2.append(Vector2.ZERO)
			normals.append(Vector3.UP)
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			index.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# Skirt: the edge ring again, hanging down; both faces, it's only seen edge-on.
	var ring: Array[int] = []
	for x in n:
		ring.append(x)
	for z in range(1, n):
		ring.append(z * n + n - 1)
	for x in range(n - 2, -1, -1):
		ring.append((n - 1) * n + x)
	for z in range(n - 2, 0, -1):
		ring.append(z * n)
	var first := verts.size()
	for k in ring:
		verts.append(verts[k])
		uv2.append(Vector2(1.0, 0.0))
		normals.append(Vector3.UP)
	for i in ring.size():
		var j := (i + 1) % ring.size()
		var a: int = ring[i]
		var b: int = ring[j]
		var sa := first + i
		var sb := first + j
		index.append_array([a, b, sa, b, sb, sa, a, sa, b, b, sa, sb])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_grids[step] = mesh
	return mesh
