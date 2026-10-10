class_name StockWheel
extends RefCounted
## The platform's stock wheel (docs/VEHICLE_PACKAGE.md §4, wheel_mode "stock"): a tire and a
## rim, drawn when a model's own wheels can't be used. Original, generated geometry.

const SEGMENTS := 28

static var _tire_material: StandardMaterial3D
static var _rim_material: StandardMaterial3D


## A hub node with one child that spins about +X. Centred on the wheel.
static func create(radius: float, width: float) -> Node3D:
	_make_materials()
	var hub := Node3D.new()
	var spinner := Node3D.new()
	spinner.name = "Spin"
	hub.add_child(spinner)
	spinner.add_child(_cylinder(radius, width, _tire_material))
	spinner.add_child(_cylinder(radius * 0.62, width * 1.04, _rim_material))
	# Spokes, so the spin is visible.
	for i in 5:
		var spoke := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width * 1.06, radius * 0.1, radius * 1.15)
		box.material = _rim_material
		spoke.mesh = box
		spoke.rotation.x = TAU * i / 5.0
		spinner.add_child(spoke)
	return hub


static func _cylinder(radius: float, width: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = SEGMENTS
	mesh.rings = 1
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation.z = PI / 2.0 # the cylinder's axis along +X, the axle
	return mi


static func _make_materials() -> void:
	if _tire_material:
		return
	_tire_material = StandardMaterial3D.new()
	_tire_material.albedo_color = Color(0.06, 0.06, 0.065)
	_tire_material.roughness = 0.9
	_rim_material = StandardMaterial3D.new()
	_rim_material.albedo_color = Color(0.72, 0.73, 0.75)
	_rim_material.metallic = 0.85
	_rim_material.roughness = 0.3
