class_name CarVisual
extends Node3D
## The look of a vehicle: a package's LOD scenes mounted with its fit, with paint applied and
## hubs, wheels and the steering wheel driven by the sim (docs/ARCHITECTURE.md §4).

const PAINT_SHADER := preload("res://game/vehicles/noss_paint.gdshader")
## Finish -> [metallic, roughness, clearcoat, clearcoat roughness, pearl] (docs/VEHICLE_PACKAGE.md §5).
const FINISHES := {
	"solid": [0.0, 0.35, 1.0, 0.04, 0.0],
	"metallic": [0.75, 0.32, 1.0, 0.04, 0.0],
	"pearl": [0.45, 0.28, 1.0, 0.03, 0.6],
	"matte": [0.0, 0.75, 0.0, 0.5, 0.0],
	"chrome": [1.0, 0.06, 0.0, 0.1, 0.0],
}
const BRAKE_ON_ENERGY := 4.0
const BRAKE_OFF_ENERGY := 0.0

var package: VehiclePackage
var fitted: Fitting.Result
var model_root: Node3D

## Per fit wheel: {id, hubs: [[node, rest]], spins: [[node, rest]], up, lift, stock: [hub, rest, spinner] or []}.
## up is the steering axis and lift one metre of vehicle-frame up, in the hubs' parent space.
var _wheels: Array[Dictionary] = []
var _steering: Array[Array] = [] # [node, rest, pivot, axis]
var _paint := {} # slot -> ShaderMaterial
var _brake_materials: Array[BaseMaterial3D] = []
var _brake_on := false


## Takes ownership of the package's LOD scenes.
static func create(pkg: VehiclePackage, fit_result: Fitting.Result) -> CarVisual:
	var visual := CarVisual.new()
	visual.name = "CarVisual"
	visual.package = pkg
	visual.fitted = fit_result
	visual.model_root = Node3D.new()
	visual.model_root.name = "ModelRoot"
	visual.model_root.transform = fit_result.model_xform
	visual.add_child(visual.model_root)
	var distances: Array = pkg.fit.get("lod_distances_m", [0])
	for i in pkg.lods.size():
		var lod := pkg.lods[i]
		lod.name = "LOD%d" % i
		visual.model_root.add_child(lod)
		var begin: float = distances[i] if i < distances.size() else 0.0
		var end: float = distances[i + 1] if i + 1 < distances.size() and i + 1 < pkg.lods.size() else 0.0
		for mi: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_begin = begin
			mi.visibility_range_end = end
	visual._setup()
	return visual


## Pose one wheel. steer: rad (+ = left), spin: rad (+ = rolling forward), lift: m (+ = up).
func set_wheel(index: int, steer: float, spin: float, lift: float) -> void:
	var w: Dictionary = _wheels[index]
	var up: Vector3 = w.up
	for pair: Array in w.hubs:
		var rest: Transform3D = pair[1]
		pair[0].transform = Transform3D(Basis(up, steer) * rest.basis, rest.origin + w.lift * lift)
	for pair: Array in w.spins:
		var rest: Transform3D = pair[1]
		pair[0].transform = Transform3D(Basis(Vector3.RIGHT, spin) * rest.basis, rest.origin)
	if not w.stock.is_empty():
		var center: Vector3 = w.stock[1]
		w.stock[0].transform = Transform3D(Basis(Vector3.UP, steer), center + Vector3.UP * lift)
		w.stock[2].transform = Transform3D(Basis(Vector3.RIGHT, spin), Vector3.ZERO)


## Rotates the steering wheel node. angle: rad, + = left.
func set_steering_angle(angle: float) -> void:
	for item in _steering:
		var rest: Transform3D = item[1]
		var pivot: Vector3 = item[2]
		item[0].transform = rest * Transform3D(Basis(item[3], angle), pivot - Basis(item[3], angle) * pivot)


func set_brake_lights(on: bool) -> void:
	if on == _brake_on:
		return
	_brake_on = on
	for m in _brake_materials:
		m.emission_energy_multiplier = BRAKE_ON_ENERGY if on else BRAKE_OFF_ENERGY


func set_paint(slot: String, color: Color, finish := "") -> void:
	var m: ShaderMaterial = _paint.get(slot)
	if m == null:
		return
	m.set_shader_parameter("paint_color", color)
	if FINISHES.has(finish):
		var f: Array = FINISHES[finish]
		m.set_shader_parameter("metallic", f[0])
		m.set_shader_parameter("roughness", f[1])
		m.set_shader_parameter("clearcoat", f[2])
		m.set_shader_parameter("clearcoat_roughness", f[3])
		m.set_shader_parameter("pearl", f[4])


func wheel_count() -> int:
	return _wheels.size()


func _setup() -> void:
	var fit: Dictionary = package.fit
	for pattern: String in fit.get("hide_nodes", []):
		for node in model_root.find_children(pattern, "Node3D", true, false):
			node.visible = false
	# model: the model's wheels move; static: they're part of the body and stay put;
	# stock: they're hidden and the platform's stock wheels are drawn at the anchors.
	var mode: String = fit.wheel_mode
	var to_model := fitted.model_xform.basis.inverse()
	for i in fit.wheels.size():
		var fw: Dictionary = fit.wheels[i]
		var fitted_wheel: Dictionary = fitted.wheels[i]
		var w := { "id": fw.id, "hubs": [], "spins": [], "up": Vector3.UP, "lift": Vector3.UP, "stock": [] }
		if mode == "stock":
			for node in _find_all(fw.get("node", "")) + _find_all(fw.get("spin_node", "")):
				node.visible = false
			var hub := StockWheel.create(fitted_wheel.radius, fitted_wheel.width)
			hub.name = "StockWheel_" + String(fw.id)
			hub.position = fitted_wheel.center
			add_child(hub)
			w.stock = [hub, fitted_wheel.center, hub.get_child(0)]
		elif mode == "model":
			for node in _find_all(fw.get("node", "")):
				var rest := node.transform
				# Vehicle-frame vectors in the hub's parent space, through the model transform.
				var to_parent := _xform_to(node.get_parent()).basis.inverse() * to_model
				# Track clamping moves the wheel along the axle (Fitting, §4.1 step 3).
				rest.origin += to_parent * Vector3(fitted_wheel.shift, 0, 0)
				node.transform = rest
				w.hubs.append([node, rest])
				w.lift = to_parent * Vector3.UP
				w.up = w.lift.normalized()
			for node in _find_all(fw.get("spin_node", "")):
				w.spins.append([node, node.transform])
		_wheels.append(w)

	if fit.get("lod_materials", "own") == "shared":
		_share_lod_materials()

	var sw: Variant = fit.get("steering_wheel")
	if sw is Dictionary:
		for node in _find_all(sw.node):
			_steering.append([node, node.transform, _mesh_center(node), _column_axis(node)])

	_apply_paint()
	_find_brake_lights()
	for mi: MeshInstance3D in model_root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## Generated LODs carry plain materials (LodBuilder); they use LOD0's, matched by name.
func _share_lod_materials() -> void:
	var lods := model_root.get_children()
	if lods.size() < 2:
		return
	var by_name := {}
	for mi: MeshInstance3D in lods[0].find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.mesh.surface_get_material(s)
			if m and not by_name.has(m.resource_name):
				by_name[m.resource_name] = m
	for lod in lods.slice(1):
		for mi: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count() if mi.mesh else 0:
				var m := mi.mesh.surface_get_material(s)
				if m and by_name.has(m.resource_name):
					mi.mesh.surface_set_material(s, by_name[m.resource_name])


func _apply_paint() -> void:
	var slots: Dictionary = package.paint.get("slots", {})
	var by_material := {}
	for slot: String in slots:
		var data: Dictionary = slots[slot]
		var m := ShaderMaterial.new()
		m.shader = PAINT_SHADER
		_paint[slot] = m
		set_paint(slot, Color.html(data.color), data.finish)
		for material_name: String in data.materials:
			by_material[material_name] = slot
	if by_material.is_empty():
		return
	# Use the first matching material's textures as each slot's detail layer.
	var textured := {}
	for mi: MeshInstance3D in model_root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var original := mi.mesh.surface_get_material(s)
			if original == null or not by_material.has(original.resource_name):
				continue
			var slot: String = by_material[original.resource_name]
			var paint: ShaderMaterial = _paint[slot]
			mi.set_surface_override_material(s, paint)
			if original is BaseMaterial3D and not textured.has(slot):
				textured[slot] = true
				var base := original as BaseMaterial3D
				if base.albedo_texture:
					paint.set_shader_parameter("detail", base.albedo_texture)
				if base.normal_enabled and base.normal_texture:
					paint.set_shader_parameter("normal_map", base.normal_texture)
					paint.set_shader_parameter("use_normal_map", true)
				paint.set_shader_parameter("uv_scale", base.uv1_scale)
				paint.set_shader_parameter("uv_offset", base.uv1_offset)


func _find_brake_lights() -> void:
	var patterns: Array = package.fit.get("lights", {}).get("brake", [])
	if patterns.is_empty():
		return
	var copies := {}
	for mi: MeshInstance3D in model_root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null or not patterns.any(func(p: String) -> bool: return m.resource_name.matchn(p)):
				continue
			if not copies.has(m):
				var copy := m.duplicate() as BaseMaterial3D
				copy.emission_enabled = true
				copy.emission = Color(1.0, 0.08, 0.04)
				copy.emission_energy_multiplier = BRAKE_OFF_ENERGY
				copies[m] = copy
				_brake_materials.append(copy)
			mi.set_surface_override_material(s, copies[m])


func _find_all(node_name: String) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if node_name.is_empty():
		return found
	for lod in model_root.get_children():
		var node := lod.find_child(node_name, true, false) as Node3D
		if node:
			found.append(node)
	return found


## Transform from `node`'s space to model_root's space.
func _xform_to(node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while node and node != model_root:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return t


static func _mesh_center(node: Node3D) -> Vector3:
	var mi := node as MeshInstance3D
	return mi.mesh.get_aabb().get_center() if mi and mi.mesh else Vector3.ZERO


## Steering column axis: the normal of the wheel's disc, i.e. the direction its vertices
## spread least in, pointed back at the driver (-Z).
static func _column_axis(node: Node3D) -> Vector3:
	var fallback := Vector3(0, 0.34, -0.94).normalized()
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return fallback
	var points := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		points.append_array(mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	if points.size() < 16:
		return fallback
	var axis := Pca.smallest_axis(points)
	if axis.z > 0.0:
		axis = -axis
	return axis if absf(axis.z) > 0.5 else fallback
