class_name TrackBuilder
extends RefCounted
## Builds a drivable track scene (docs/TRACK_EDITOR.md §5): the ground (flat, or a terrain), the
## road and everything along it (RoadBuilder), the start gantry, and a noss.track/0 file's set
## pieces, each with the surface the tire model reads (docs/PHYSICS.md §4).
##
## opts: visual (false: collision only, for the dedicated server), segmented (the editor: road
## pieces per control segment, under a "Road" node).

const TREE_COUNT := 1400

var track: TrackData
var terrain: TerrainData
var root: Node3D
var visual := true
var _ground_y := -0.03


static func build(data: TrackData, ground: TerrainData = null, opts := {}) -> Node3D:
	var b := TrackBuilder.new()
	b.track = data
	b.terrain = ground
	b.visual = bool(opts.get("visual", true))
	b._ground_y = float(data.raw.get("ground", {}).get("flat_y", -0.03))
	b.root = Node3D.new()
	b.root.name = "Track"
	b._ground()
	var road := RoadBuilder.new(data, ground)
	road.visual = b.visual
	if opts.get("segmented", false):
		var pieces := Node3D.new()
		pieces.name = "Road"
		b.root.add_child(pieces)
		road.build_all(pieces, true)
	else:
		road.build_all(b.root)
	if data.gantry and data.samples.size() > 2:
		b._start_gantry()
	b._skidpad()
	b._grandstand()
	b._pit_building()
	if data.legacy.get("trees", false) and b.visual:
		b._trees()
	return b.root


# --- parts ------------------------------------------------------------------------------


func _ground() -> void:
	if terrain:
		if visual:
			root.add_child(TerrainView.build(terrain))
		root.add_child(TerrainCollision.build(terrain))
		return
	var bounds := _bounds()
	var size := maxf(bounds.size.x, bounds.size.z) + 4000.0
	var center := bounds.get_center()
	if visual:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(size, size)
		mesh.subdivide_width = 0
		mesh.subdivide_depth = 0
		var mi := MeshInstance3D.new()
		mi.name = "Grass"
		mi.mesh = mesh
		mi.position = Vector3(center.x, _ground_y, center.z)
		var m := WorldMaterials.get_material("grass", RetroTextures.grass(), 1.0, 0.1, true, Vector2.ONE / 5.0)
		m.set_shader_parameter("variation", 0.22)
		m.set_shader_parameter("variation_noise", RetroTextures.variation())
		mi.material_override = m
		root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GrassBody"
	body.set_meta(&"noss_surface", TrackFormat.surface_id(String(track.raw.get("ground", {}).get("surface", "grass"))))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bounds.size.x + 1200.0, 10.0, bounds.size.z + 1200.0)
	shape.shape = box
	shape.position = Vector3(center.x, _ground_y - 5.0, center.z)
	body.add_child(shape)
	root.add_child(body)


func _skidpad() -> void:
	var pad: Dictionary = track.legacy.get("skidpad", {})
	if pad.is_empty():
		return
	var c := Vector3(pad.center[0], 0.0, pad.center[1])
	var radius: float = pad.get("pad_radius_m", 72.0)
	var st := MeshBatch.new()
	var segs := 72
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * radius
		var first := st.vertex(c, Vector3.UP, Vector2.ZERO)
		st.vertex(p1, Vector3.UP, Vector2.ZERO)
		st.vertex(p0, Vector3.UP, Vector2.ZERO)
		st.index.append_array([first, first + 2, first + 1])
	var m := WorldMaterials.get_material("concrete_world", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0)
	_add_body("Skidpad", st, m, VehicleSim.SURFACE_CONCRETE)
	# Painted driving circle.
	var line := MeshBatch.new()
	var r: float = pad.get("radius_m", 60.0)
	for i in 120:
		var a0 := TAU * i / 120.0
		var a1 := TAU * (i + 1) / 120.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var y := Vector3.UP * 0.01
		line.quad([c + d0 * (r + 0.15) + y, c + d0 * (r - 0.15) + y, c + d1 * (r - 0.15) + y, c + d1 * (r + 0.15) + y], _uv4())
	if visual:
		var lm := MeshInstance3D.new()
		lm.name = "SkidpadLine"
		lm.mesh = line.mesh()
		lm.material_override = WorldMaterials.get_material("paint_white", null, 0.6, 0.2, false, Vector2.ONE, Color(0.9, 0.9, 0.88))
		root.add_child(lm)


func _start_gantry() -> void:
	var t := track.transform_at(track.start_m)
	var i := track.index_at(track.start_m)
	var hl := track.half_l[i]
	var hr := track.half_r[i]
	# Chequered line on the road.
	var st := MeshBatch.new()
	var f := t.basis.z * 0.7
	var y := t.basis.y * 0.008
	st.quad([t.origin + t.basis.x * hl - f + y, t.origin - t.basis.x * hr - f + y, t.origin - t.basis.x * hr + f + y, t.origin + t.basis.x * hl + f + y],
		[Vector2(0, 0), Vector2(8, 0), Vector2(8, 1), Vector2(0, 1)])
	if visual:
		var line := MeshInstance3D.new()
		line.name = "StartLine"
		line.mesh = st.mesh()
		line.material_override = WorldMaterials.get_material("checker", RetroTextures.checker(), 0.7, 0.2)
		root.add_child(line)
	# Pillars and a banner over the road, standing upright on banked road too.
	var gantry := MeshBatch.new()
	var level := Basis(t.basis.x.slide(Vector3.UP).normalized(), Vector3.UP, t.basis.z.slide(Vector3.UP).normalized())
	for side: float in [1.0, -1.0]:
		var foot := t.origin + t.basis.x * side * ((hl if side > 0.0 else hr) + 2.0)
		gantry.box(foot + Vector3.UP * 3.5, level, Vector3(0.6, 7.0, 0.6))
	var mid := t.origin + t.basis.x * (hl - hr) / 2.0
	gantry.box(mid + Vector3.UP * 7.3, level, Vector3(hl + hr + 5.0, 1.2, 0.5))
	_add_body("Gantry", gantry, WorldMaterials.get_material("gantry", RetroTextures.checker(), 0.6, 0.2, false, Vector2(6, 1)), VehicleSim.SURFACE_CONCRETE)


func _grandstand() -> void:
	var g: Dictionary = track.legacy.get("grandstand", {})
	if g.is_empty():
		return
	var side := 1.0 if g.get("side", "left") == "left" else -1.0
	var t := track.transform_at(float(g.at_m))
	var length: float = g.get("length_m", 100.0)
	var st := MeshBatch.new()
	var base := t.origin + t.basis.x * side * (track.width / 2.0 + 14.0)
	# Stepped rows rising away from the track.
	for row in 10:
		var out := t.basis.x * side * (row * 1.2 + 0.6)
		var rise := row * 0.8 + 0.6
		st.box(base + out + Vector3.UP * rise / 2.0, t.basis, Vector3(1.2, rise, length), Vector2(length / 8.0, 1.0))
	_add_body("Grandstand", st, WorldMaterials.get_material("crowd", RetroTextures.crowd(), 0.9, 0.1), VehicleSim.SURFACE_CONCRETE)
	var roof := MeshBatch.new()
	roof.box(base + t.basis.x * side * 6.0 + Vector3.UP * 9.5, t.basis, Vector3(13.0, 0.4, length + 4.0))
	_add_body("GrandstandRoof", roof, WorldMaterials.get_material("roof", null, 0.7, 0.2, false, Vector2.ONE, Color(0.35, 0.37, 0.4)), VehicleSim.SURFACE_CONCRETE)


func _pit_building() -> void:
	var p: Dictionary = track.legacy.get("pit_building", {})
	if p.is_empty():
		return
	var side := 1.0 if p.get("side", "right") == "left" else -1.0
	var t := track.transform_at(float(p.at_m))
	var length: float = p.get("length_m", 120.0)
	var st := MeshBatch.new()
	var center := t.origin + t.basis.x * side * (track.width / 2.0 + 26.0) + Vector3.UP * 4.5
	st.box(center, t.basis, Vector3(12.0, 9.0, length), Vector2(length / 12.0, 1.0))
	_add_body("PitBuilding", st, WorldMaterials.get_material("building", RetroTextures.building(), 0.8, 0.2), VehicleSim.SURFACE_CONCRETE)


func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track.id)
	var bounds := _bounds().grow(400.0)
	var pad: Dictionary = track.legacy.get("skidpad", {})
	var pad_c := Vector3(pad.center[0], 0, pad.center[1]) if not pad.is_empty() else Vector3(INF, 0, INF)
	var pad_r: float = pad.get("pad_radius_m", 0.0) + 15.0
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < TREE_COUNT and tries < TREE_COUNT * 20:
		tries += 1
		var p := Vector3(rng.randf_range(bounds.position.x, bounds.end.x), 0, rng.randf_range(bounds.position.z, bounds.end.z))
		if p.distance_to(pad_c) < pad_r or track.is_near_centreline(p, track.width / 2.0 + 16.0 + 12.0):
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
	if track.samples.is_empty():
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var b := AABB(track.samples[0], Vector3.ZERO)
	for p in track.samples:
		b = b.expand(p)
	return b


func _uv4() -> Array:
	return [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


func _add_body(node_name: String, st: MeshBatch, material: Material, surface: int) -> void:
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = st.mesh()
		mi.material_override = material
		root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	body.set_meta(&"noss_surface", surface)
	var shape := CollisionShape3D.new()
	shape.shape = st.shape()
	body.add_child(shape)
	root.add_child(body)
