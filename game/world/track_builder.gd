class_name TrackBuilder
extends RefCounted
## Builds a drivable track scene (docs/TRACK_EDITOR.md §5): the ground (flat, or a terrain), the
## road and everything along it (RoadBuilder), the start gantry and the props (PropBuilder), each
## with the surface the tire model reads (docs/PHYSICS.md §4).
##
## opts: visual (false: collision only, for the dedicated server), segmented (the editor: road
## pieces per control segment, under a "Road" node), per_item (the editor: a node per prop),
## scene (a SceneTrack: a fitted scene is the road and the ground; the spline only guides).

var track: TrackData
var terrain: TerrainData
var root: Node3D
var visual := true
var _ground_y := -0.03


static func build(data: TrackData, ground: TerrainData = null, opts := {}) -> Node3D:
	var b := _builder(data, ground, Node3D.new(), bool(opts.get("visual", true)))
	b.root.name = "Track"
	var scene: SceneTrack = opts.get("scene")
	if scene:
		scene.build(b.root, b.visual)
	else:
		b._ground()
	if data.arena:
		# An arena's outline is its wall, not a road (D138).
		var arena_root := Node3D.new()
		arena_root.name = "Road"
		b.root.add_child(arena_root)
		ArenaBuilder.build(data, arena_root, b.visual)
	else:
		var road := RoadBuilder.new(data, ground)
		road.visual = b.visual
		if opts.get("segmented", false):
			var pieces := Node3D.new()
			pieces.name = "Road"
			b.root.add_child(pieces)
			road.build_all(pieces, true)
		else:
			road.build_all(b.root)
	if data.kart:
		var stunts := Node3D.new()
		stunts.name = "Stunts"
		b.root.add_child(stunts)
		StuntBuilder.build(data, stunts, b.visual)
	if data.gantry and data.samples.size() > 2 and data.arena == null:
		b._start_gantry()
	var props := PropBuilder.new(data, ground)
	props.visual = b.visual
	props.build(b.root, bool(opts.get("per_item", false)))
	return b.root


## The ground alone, into `parent` (the editor builds the parts apart).
static func add_ground(parent: Node3D, data: TrackData, ground: TerrainData, visual := true) -> void:
	_builder(data, ground, parent, visual)._ground()


## The start line and gantry alone, into `parent`.
static func add_gantry(parent: Node3D, data: TrackData, visual := true) -> void:
	if data.gantry and data.samples.size() > 2:
		_builder(data, null, parent, visual)._start_gantry()


static func _builder(data: TrackData, ground: TerrainData, into: Node3D, visual: bool) -> TrackBuilder:
	var b := TrackBuilder.new()
	b.track = data
	b.terrain = ground
	b.visual = visual
	b._ground_y = float(data.raw.get("ground", {}).get("flat_y", -0.03))
	b.root = into
	return b


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
	var surface := TrackFormat.surface_id(String(track.raw.get("ground", {}).get("surface", "grass")))
	if visual:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(size, size)
		mesh.subdivide_width = 0
		mesh.subdivide_depth = 0
		var mi := MeshInstance3D.new()
		mi.name = "Grass"
		mi.mesh = mesh
		mi.position = Vector3(center.x, _ground_y, center.z)
		if surface == VehicleSim.SURFACE_GRASS:
			var m := WorldMaterials.get_material("grass", RetroTextures.grass(), 1.0, 0.1, true, Vector2.ONE / 5.0)
			m.set_shader_parameter("variation", 0.22)
			m.set_shader_parameter("variation_noise", RetroTextures.variation())
			mi.material_override = m
		else: # a city's ground: concrete and the like
			mi.name = "Ground"
			mi.material_override = WorldMaterials.surface(surface)
		root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GrassBody"
	body.set_meta(&"noss_surface", surface)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bounds.size.x + 1200.0, 10.0, bounds.size.z + 1200.0)
	shape.shape = box
	shape.position = Vector3(center.x, _ground_y - 5.0, center.z)
	body.add_child(shape)
	root.add_child(body)


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
	# Pillars and a banner over the road, standing upright on banked road too. Each foot is 2 m
	# past the paving (an apron's too), or on the barrier line if that's nearer (an oval's wall).
	var gantry := MeshBatch.new()
	var level := Basis(t.basis.x.slide(Vector3.UP).normalized(), Vector3.UP, t.basis.z.slide(Vector3.UP).normalized())
	var feet := []
	for side: float in [1.0, -1.0]:
		var apron: float = track.apron(i, side)
		var out := 2.0 + apron
		if int(track.barrier_l[i] if side > 0.0 else track.barrier_r[i]) > TrackFormat.BARRIER_AUTO:
			out = minf(out, (track.runoff_l_m[i] if side > 0.0 else track.runoff_r_m[i]) + apron)
		feet.append(t.origin + track.cross_point(i, side, out) - track.samples[i])
	var top := maxf(feet[0].y, feet[1].y) + 7.0
	for foot: Vector3 in feet:
		gantry.box(Vector3(foot.x, (foot.y + top) / 2.0, foot.z), level, Vector3(0.6, top - foot.y, 0.6))
	var mid := t.origin + t.basis.x * (hl - hr) / 2.0
	var span := Vector2(feet[0].x - feet[1].x, feet[0].z - feet[1].z).length()
	gantry.box(Vector3(mid.x, top + 0.3, mid.z), level, Vector3(maxf(hl + hr + 5.0, span + 1.0), 1.2, 0.5))
	_add_body("Gantry", gantry, WorldMaterials.get_material("gantry", RetroTextures.checker(), 0.6, 0.2, false, Vector2(6, 1)), VehicleSim.SURFACE_CONCRETE)


# --- helpers ------------------------------------------------------------------------------


func _bounds() -> AABB:
	if track.samples.is_empty():
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var b := AABB(track.samples[0], Vector3.ZERO)
	for p in track.samples:
		b = b.expand(p)
	return b


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
