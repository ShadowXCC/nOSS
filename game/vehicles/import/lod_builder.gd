class_name LodBuilder
extends RefCounted
## Generates a model's lower LODs when a package is saved (docs/VEHICLE_PACKAGE.md §1, §7).
## Each level simplifies every mesh with meshoptimizer (NossMesh), drops tiny parts from LOD2
## on, and keeps every node, so hubs, wheels and lights are found in each LOD. LODs carry no
## textures: fit.json's "lod_materials": "shared" makes the loader reuse LOD0's materials by
## name, so they add no texture memory and paint and lights still work.

## [share of triangles, max error as a share of the car's length, sloppy, drop parts smaller
## than this share of the length]
const LEVELS := [
	[0.5, 0.002, false, 0.0],
	[0.25, 0.006, false, 0.01],
	[0.1, 0.015, false, 0.02],
	[0.04, 0.04, true, 0.03],
]
## Start distance per LOD, LOD0 first.
const DISTANCES := [0, 12, 30, 70, 150]


## GLB bytes of LOD1..N for `scene`, which isn't changed. `length` is the car's length in the
## scene's units.
static func build(scene: Node3D, length: float, levels := LEVELS) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var cache := {}
	var materials := {}
	for li in levels.size():
		var level: Array = levels[li]
		var copy := scene.duplicate() as Node3D
		for node in [copy] + copy.find_children("*", "Node3D", true, false):
			(node as Node3D).visible = true # a hidden node would make the exporter require KHR_node_visibility
		for mi: MeshInstance3D in copy.find_children("*", "MeshInstance3D", true, false):
			if is_instance_valid(mi):
				_simplify(mi, copy, level, length, cache, li, materials)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_scene(copy, state)
		var bytes := doc.generate_buffer(state) if err == OK else PackedByteArray()
		copy.free()
		out.append(bytes)
	return out


static func _simplify(mi: MeshInstance3D, root: Node3D, level: Array, length: float, cache: Dictionary, li: int, materials: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	var xf := _to_root(mi, root)
	if (xf * mesh.get_aabb()).size.length() < float(level[3]) * length:
		# Too small to see at this distance: an empty node keeps its name and children.
		var empty := Node3D.new()
		empty.name = mi.name
		empty.transform = mi.transform
		mi.replace_by(empty)
		mi.free()
		return
	var key := [mesh.get_instance_id(), li]
	if not cache.has(key):
		var scale := maxf(absf(xf.basis.get_scale().x + xf.basis.get_scale().y + xf.basis.get_scale().z) / 3.0, 1e-9)
		cache[key] = _simplified_mesh(mesh, float(level[0]), float(level[1]) * length / scale, level[2], materials)
	mi.mesh = cache[key]
	for s in mi.get_surface_override_material_count():
		mi.set_surface_override_material(s, null)
	mi.material_override = null


static func _simplified_mesh(mesh: Mesh, ratio: float, error: float, sloppy: bool, materials: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = mesh.resource_name
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var primitive := Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			primitive = (mesh as ArrayMesh).surface_get_primitive_type(s)
		if primitive == Mesh.PRIMITIVE_TRIANGLES:
			arrays = NossMesh.simplify_surface(arrays, ratio, error, sloppy)
			if arrays.is_empty() or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				continue
		out.add_surface_from_arrays(primitive, arrays)
		var original := mesh.surface_get_material(s)
		if original and not materials.has(original):
			materials[original] = _plain(original)
		out.surface_set_material(out.get_surface_count() - 1, materials.get(original))
	return out


## The material without textures, under the same name.
static func _plain(material: Material) -> Material:
	if material == null:
		return null
	var plain := StandardMaterial3D.new()
	plain.resource_name = material.resource_name
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		plain.albedo_color = base.albedo_color
		plain.metallic = base.metallic
		plain.roughness = base.roughness
		plain.transparency = base.transparency
		plain.cull_mode = base.cull_mode
	return plain


## `node`'s transform relative to `root`.
static func _to_root(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while node and node != root:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return t
