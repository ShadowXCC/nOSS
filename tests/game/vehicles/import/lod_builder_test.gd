extends GdUnitTestSuite
## Generated LODs (docs/VEHICLE_PACKAGE.md §1): fewer triangles per level, every node kept,
## no textures, and each one passes the package's GLB checks.


func test_lods_shrink_and_keep_nodes() -> void:
	var scene := _car()
	var lods := LodBuilder.build(scene, 4.4)
	assert_int(lods.size()).is_equal(LodBuilder.LEVELS.size())
	var previous: int = PackageLoader.check_glb(_glb(scene), PackageLoader.DEFAULT_LIMITS).triangles
	for bytes in lods:
		var check := PackageLoader.check_glb(bytes, PackageLoader.DEFAULT_LIMITS)
		assert_str(check.error).is_empty()
		assert_int(check.triangles).is_less(previous)
		assert_float(check.texture_bytes).is_equal(0.0)
		previous = check.triangles
		var names := _node_names(bytes)
		for n in ["hub_LF", "wheel_LF", "body", "steering_wheel"]:
			assert_array(names).contains([n])
	scene.free()


func test_tiny_parts_drop_out_from_lod2() -> void:
	var scene := _car()
	var lods := LodBuilder.build(scene, 4.4)
	assert_int(_mesh_count(lods[0])).is_equal(_mesh_count(lods[1]) + 1) # the badge is gone
	scene.free()


static func _car() -> Node3D:
	var root := Node3D.new()
	root.name = "car"
	var body := MeshInstance3D.new()
	body.name = "body"
	var sphere := SphereMesh.new()
	sphere.radial_segments = 96
	sphere.rings = 48
	sphere.radius = 0.9
	sphere.height = 1.2
	var paint := StandardMaterial3D.new()
	paint.resource_name = "Paint_Primary"
	sphere.material = paint
	body.mesh = sphere
	body.scale = Vector3(1.0, 1.0, 2.4)
	root.add_child(body)
	var hub := Node3D.new()
	hub.name = "hub_LF"
	hub.position = Vector3(0.8, 0.3, 1.3)
	root.add_child(hub)
	var wheel := MeshInstance3D.new()
	wheel.name = "wheel_LF"
	var cylinder := CylinderMesh.new()
	cylinder.radial_segments = 64
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.3
	cylinder.height = 0.22
	wheel.mesh = cylinder
	wheel.rotation.z = PI / 2.0
	hub.add_child(wheel)
	var steering := MeshInstance3D.new()
	steering.name = "steering_wheel"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.18
	steering.mesh = torus
	root.add_child(steering)
	var badge := MeshInstance3D.new()
	badge.name = "badge"
	var tiny := BoxMesh.new()
	tiny.size = Vector3(0.03, 0.02, 0.005)
	badge.mesh = tiny
	root.add_child(badge)
	return root


static func _glb(scene: Node3D) -> PackedByteArray:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(scene, state)
	return doc.generate_buffer(state)


static func _json(bytes: PackedByteArray) -> Dictionary:
	return JSON.parse_string(NossPackage.inspect_glb(bytes).json)


static func _node_names(bytes: PackedByteArray) -> Array:
	return _json(bytes).get("nodes", []).map(func(n: Dictionary) -> String: return n.get("name", ""))


static func _mesh_count(bytes: PackedByteArray) -> int:
	return _json(bytes).get("nodes", []).filter(func(n: Dictionary) -> bool: return n.has("mesh")).size()
