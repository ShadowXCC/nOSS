class_name TrafficModels
extends RefCounted
## What distant traffic is drawn with (D108): each type's LOD1 merged into one mesh, one surface
## per material, on the traffic shader (paint from each instance's colour, lights from its custom
## data). Made once per type and shared. A garage car in the endless traffic (D191) gets its own,
## from its smallest LOD.

const SHADER := preload("res://game/modes/highway/traffic.gdshader")
## Light bits in an instance's custom data.
const BRAKE := 1
const LEFT := 2
const RIGHT := 4
const HEAD := 8
const LIGHTS := {
	"tail_light": [BRAKE, Color(1.0, 0.08, 0.04), 4.0],
	"indicator_L": [LEFT, Color(1.0, 0.55, 0.05), 3.0],
	"indicator_R": [RIGHT, Color(1.0, 0.55, 0.05), 3.0],
	"head_light": [HEAD, Color(1.0, 0.95, 0.85), 1.5],
}

static var _meshes := {}


## The merged far mesh of traffic type `type` (TrafficTypes index), its origin at the vehicle's
## middle on the ground; null if its package won't load.
static func far_mesh(type: int) -> ArrayMesh:
	if _meshes.has(type):
		return _meshes[type]
	var t: Dictionary = TrafficTypes.list()[type]
	var pkg := PackageLoader.load_package("res://content/traffic/" + String(t.model))
	if not pkg.ok() or pkg.lods.is_empty():
		push_error("Traffic model %s: %s" % [t.model, pkg.error])
		return null
	var lod: Node3D = pkg.lods[mini(1, pkg.lods.size() - 1)]
	var groups := {} # material name -> SurfaceTool
	for mi: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xform := _to_root(mi, lod)
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var key := m.resource_name if m else "trim"
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = st
			(groups[key] as SurfaceTool).append_from(mi.mesh, s, xform)
	var mesh := ArrayMesh.new()
	for key: String in groups:
		var st: SurfaceTool = groups[key]
		mesh = st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
	pkg.free_scenes()
	_meshes[type] = mesh
	return mesh


## A garage car's far mesh (D191): its smallest LOD as fitted to `platform`, its wheels on the
## ground, merged one surface per material. Its own materials stay, but its main paint takes each
## instance's colour. Null over `most` triangles (then it's drawn as a stock car in its paint).
static func far_mesh_of(pkg: VehiclePackage, platform: Dictionary, most := 15000) -> ArrayMesh:
	if pkg == null or not pkg.ok() or pkg.lods.is_empty():
		return null
	var fitted := Fitting.fit(platform, pkg.fit)
	# Its wheels are part of the mesh: they stand on the ground, whatever its ride height.
	var place := Transform3D(Basis(), Vector3(0.0, -fitted.ground_y - fitted.body_lift, 0.0)) * fitted.model_xform
	var paint: Array = pkg.paint.get("slots", {}).get("primary", {}).get("materials", [])
	var lod: Node3D = pkg.lods[pkg.lods.size() - 1]
	var groups := {} # material name -> SurfaceTool
	var materials := {} # material name -> its material
	var triangles := 0
	for mi: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xform := place * _to_root(mi, lod)
		for s in mi.mesh.get_surface_count():
			var n: int = mi.mesh.surface_get_array_index_len(s)
			triangles += (n if n > 0 else mi.mesh.surface_get_array_len(s)) / 3
			if triangles > most:
				return null
			var m := mi.get_active_material(s)
			var key := m.resource_name if m and m.resource_name else "surface_%d" % materials.size()
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = st
				materials[key] = _material("Paint_Primary") if key in paint else m
			(groups[key] as SurfaceTool).append_from(mi.mesh, s, xform)
	var mesh := ArrayMesh.new()
	for key: String in groups:
		mesh = (groups[key] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
	return mesh


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	if key == "Paint_Primary":
		m.set_shader_parameter("kind", 0)
		m.set_shader_parameter("roughness", 0.35)
		m.set_shader_parameter("metallic", 0.4)
	elif LIGHTS.has(key):
		var l: Array = LIGHTS[key]
		m.set_shader_parameter("kind", 2)
		m.set_shader_parameter("light_bit", l[0])
		m.set_shader_parameter("glow", l[1])
		m.set_shader_parameter("glow_energy", l[2])
		m.set_shader_parameter("albedo", Color(l[1]).darkened(0.6))
	else:
		var colors := { "Glass": Color(0.07, 0.09, 0.11), "Paint_Secondary": Color(0.95, 0.95, 0.95), "box_white": Color(0.9, 0.9, 0.88),
			"rim": Color(0.7, 0.72, 0.74), "lightbar_red": Color(0.6, 0.05, 0.05), "lightbar_blue": Color(0.05, 0.12, 0.6) }
		m.set_shader_parameter("kind", 1)
		m.set_shader_parameter("albedo", colors.get(key, Color(0.05, 0.05, 0.055)))
		m.set_shader_parameter("roughness", 0.1 if key == "Glass" else 0.7)
	return m
