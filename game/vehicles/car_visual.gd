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
## Paint for AI cars whose package has no presets (D128): [colour, finish], common car colours.
const STOCK_COLORS := [
	["#E8E8E6", "solid"], ["#111214", "metallic"], ["#9EA2A6", "metallic"], ["#55595E", "metallic"],
	["#B3141B", "solid"], ["#1F3E8C", "metallic"], ["#2C7BD6", "pearl"], ["#1E5A3A", "metallic"],
	["#F2C12E", "solid"], ["#E8721C", "solid"], ["#5A1E2E", "pearl"], ["#C9B98F", "metallic"],
]
## A paint choice names at most this many slots.
const CHOICE_SLOTS := 4
const BRAKE_ON_ENERGY := 4.0
const BRAKE_OFF_ENERGY := 0.0
## Tail lights while the headlights are on.
const TAIL_ENERGY := 1.2
## Light groups the game switches (fit.json "lights"): their glow colour and energy when on.
const LIGHTS := {
	"brake": [Color(1.0, 0.08, 0.04), BRAKE_ON_ENERGY],
	"head": [Color(1.0, 0.96, 0.85), 1.2],
	"indicator_L": [Color(1.0, 0.55, 0.05), 3.0],
	"indicator_R": [Color(1.0, 0.55, 0.05), 3.0],
}

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
var _tail_on := false
## Group -> its materials (copies per car), and how bright each group is now (0..1, head up to 2).
var _light_materials := {}
var _light_level := {}
var _lod_distances: Array = []

## Car LOD distances are multiplied by this (splitscreen lowers it, docs/ARCHITECTURE.md §6).
static var lod_scale := 1.0
## A package without a model (only its data has arrived online) shows as a box the size of its
## envelope in this colour, on stock wheels (D80).
var placeholder_color := Color(0.6, 0.6, 0.62)


## Takes ownership of the package's LOD scenes.
static func create(pkg: VehiclePackage, fit_result: Fitting.Result, placeholder := Color(0.6, 0.6, 0.62)) -> CarVisual:
	var visual := CarVisual.new()
	visual.name = "CarVisual"
	visual.package = pkg
	visual.fitted = fit_result
	visual.placeholder_color = placeholder
	visual.model_root = Node3D.new()
	visual.model_root.name = "ModelRoot"
	visual.model_root.transform = fit_result.model_xform
	visual.add_child(visual.model_root)
	visual._lod_distances = pkg.fit.get("lod_distances_m", [0])
	for i in pkg.lods.size():
		var lod := pkg.lods[i]
		lod.name = "LOD%d" % i
		visual.model_root.add_child(lod)
	visual.apply_lod_scale()
	if pkg.lods.is_empty():
		visual._add_placeholder_body()
	visual._setup()
	return visual


func _add_placeholder_body() -> void:
	var e := fitted.envelope
	var bottom := fitted.ground_y + 0.25
	var box := BoxMesh.new()
	box.size = Vector3(e.size.x * 0.96, maxf(e.end.y - bottom, 0.3), e.size.z * 0.96)
	var m := StandardMaterial3D.new()
	m.albedo_color = placeholder_color
	m.roughness = 0.5
	box.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	mi.mesh = box
	mi.position = Vector3(e.get_center().x, bottom + box.size.y / 2.0, e.get_center().z)
	add_child(mi)


## Sets each LOD's distance range from the package's, times lod_scale.
func apply_lod_scale() -> void:
	var lods := package.lods.size()
	for i in lods:
		var begin: float = float(_lod_distances[i]) * lod_scale if i < _lod_distances.size() else 0.0
		var end: float = float(_lod_distances[i + 1]) * lod_scale if i + 1 < _lod_distances.size() and i + 1 < lods else 0.0
		for mi: MeshInstance3D in package.lods[i].find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_begin = begin
			mi.visibility_range_end = end


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
	_apply_tail()


## With the headlights on, the tail lights glow dimly too (D153).
func set_tail_lights(on: bool) -> void:
	if on == _tail_on:
		return
	_tail_on = on
	_apply_tail()


func _apply_tail() -> void:
	var e := BRAKE_ON_ENERGY if _brake_on else TAIL_ENERGY if _tail_on else BRAKE_OFF_ENERGY
	for m in _brake_materials:
		m.emission_energy_multiplier = e


## Indicators showing now (the caller blinks them).
func set_indicators(left: bool, right: bool) -> void:
	set_light("indicator_L", 1.0 if left else 0.0)
	set_light("indicator_R", 1.0 if right else 0.0)


## A light group at `level` of its full glow (head lights: 1 on, 2 flashed).
func set_light(group: String, level: float) -> void:
	if is_equal_approx(float(_light_level.get(group, 0.0)), level) or not _light_materials.has(group):
		return
	_light_level[group] = level
	var energy: float = LIGHTS[group][1] * level
	for m: BaseMaterial3D in _light_materials[group]:
		m.emission_energy_multiplier = energy


func light_level(group: String) -> float:
	return float(_light_level.get(group, 0.0))


## A paint job for an AI car (D128): one of the package's presets or its own paint, at random;
## with no presets, a stock colour. Keys as a preset's (paint.json): slot -> "#RRGGBB", and
## "finish" for the primary; {} is the car's own paint.
static func random_paint(paint: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var presets: Array = (paint.get("presets", []) as Array).filter(func(p: Variant) -> bool: return p is Dictionary)
	var roll := func(n: int) -> int: return (rng.randi() if rng else randi()) % n
	if presets.is_empty():
		var c: Array = STOCK_COLORS[roll.call(STOCK_COLORS.size())]
		return { "primary": c[0], "finish": c[1] }
	var i: int = roll.call(presets.size() + 1)
	return clean_paint(presets[i]) if i < presets.size() else {}


## A paint choice as it may come from a file or a server: "#RRGGBB" colours for at most
## CHOICE_SLOTS slots and a known finish; anything else is dropped.
static func clean_paint(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	var colours := 0
	for key: Variant in d:
		var v: Variant = d[key]
		if key is String and key == "finish":
			if v is String and FINISHES.has(v):
				out["finish"] = v
		elif key is String and key != "name" and String(key).length() <= 32 and v is String and String(v).length() <= 9 \
				and Color.html_is_valid(v) and colours < CHOICE_SLOTS:
			out[key] = v
			colours += 1
	return out


## Puts a paint choice (random_paint) on: its colours on their slots, its finish on the primary.
func apply_choice(choice: Dictionary) -> void:
	for slot: String in _paint:
		var m: ShaderMaterial = _paint[slot]
		var color: Color = Color.html(choice[slot]) if choice.has(slot) else m.get_shader_parameter("paint_color")
		set_paint(slot, color, String(choice.get("finish", "")) if slot == "primary" else "")


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
	for fw: Dictionary in fit.wheels:
		if fw.get("pivot", "node") == "insert":
			_insert_pivots(fw)

	# model: the model's wheels move; static: they're part of the body and stay put;
	# stock: they're hidden and the platform's stock wheels are drawn at the anchors.
	var mode: String = fit.wheel_mode if not package.lods.is_empty() else "stock"
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
				# Track clamping moves the wheel along the axle (Fitting, §4.1 step 3), and ride
				# height down from the body.
				rest.origin += to_parent * Vector3(fitted_wheel.shift, -fitted_wheel.drop, 0)
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
	for group: String in ["head", "indicator_L", "indicator_R"]:
		_find_lights(group)
	for mi: MeshInstance3D in model_root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## A detected wheel (pivot "insert"): makes hub and spin nodes at the wheel's centre in each LOD,
## with the hub's X along the car's axle, and moves the wheel's parts under them.
func _insert_pivots(fw: Dictionary) -> void:
	var to_model := fitted.model_xform.basis.inverse()
	var axle := (to_model * Vector3.RIGHT).normalized()
	var up := (to_model * Vector3.UP).normalized()
	var basis := Basis(axle, up, axle.cross(up).normalized())
	var center := Vector3(fw.center[0], fw.center[1], fw.center[2])
	for lod in model_root.get_children():
		var hub := Node3D.new()
		hub.name = fw.node
		hub.transform = Transform3D(basis, center)
		lod.add_child(hub)
		var spin := Node3D.new()
		spin.name = fw.spin_node
		hub.add_child(spin)
		for list: Array in [[fw.get("spin_nodes", []), spin], [fw.get("fixed_nodes", []), hub]]:
			for node_name: String in list[0]:
				var part := lod.find_child(node_name, true, false) as Node3D
				if part == null or part == hub:
					continue
				var in_lod := _xform_to_node(part, lod)
				part.owner = null
				part.get_parent().remove_child(part)
				list[1].add_child(part)
				part.transform = _xform_to_node(list[1], lod).affine_inverse() * in_lod


## `node`'s transform relative to its ancestor `root`.
static func _xform_to_node(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while node and node != root:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return t


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


## The materials of light group `group` (fit.json "lights"), copied per car, glowing at 0 to start.
func _find_lights(group: String) -> void:
	var patterns: Array = package.fit.get("lights", {}).get(group, [])
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
				copy.emission = LIGHTS[group][0]
				copy.emission_energy_multiplier = 0.0
				copies[m] = copy
			mi.set_surface_override_material(s, copies[m])
	_light_materials[group] = copies.values()


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
