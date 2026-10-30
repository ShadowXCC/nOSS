extends GdUnitTestSuite
## Liveries drawn live by the paint shader (docs/VEHICLE_PACKAGE.md §12): layers packed per
## surface, slots switch shader only while they carry layers, linked colours follow the paint,
## the glass takes layers only when they reach it, and every mesh knows its place in the model.

const BOX := "res://content/cars/noss_box"

var _visual: CarVisual


func before_test() -> void:
	var pkg := PackageLoader.load_package(BOX)
	assert_str(pkg.error).is_empty()
	pkg.paint = pkg.paint.duplicate(true)
	pkg.paint.glass = ["Glass"]
	var platform := PlatformLoader.load_official("official.track.gt")
	_visual = CarVisual.create(pkg, Fitting.fit(platform.platform, pkg.fit))
	add_child(_visual)


func after_test() -> void:
	_visual.free()


func _layer(shape: String, on := ["primary"], extra := {}) -> Dictionary:
	var l := LiveryData.new_layer("shape", Vector3(0, 1.2, 0), Vector3.UP, Vector3.LEFT, Vector2(0.6, 1.2), shape)
	l.on = on
	l.merge(extra, true)
	return l


func _livery(layers: Array, extra := {}) -> Dictionary:
	var d := LiveryData.new_livery("Test")
	d.layers = layers
	d.merge(extra, true)
	return LiveryData.clean(d)


func _paint(slot: String) -> ShaderMaterial:
	return _visual._paint[slot]


func test_pack_by_surface() -> void:
	var l := _livery([
		_layer("rect", ["primary", "secondary"], { "color": "#FF0000", "opacity": 0.5, "finish": "chrome" }),
		_layer("star", ["secondary"], { "color": "secondary", "hidden": true }),
		_layer("chevrons", ["primary"], { "color": "contrast", "mirror": true, "size": [-0.6, 1.2] }),
	])
	var primary := LiveryRenderer.pack(l, "primary")
	assert_int(primary[1]).is_equal(2)
	var d: PackedVector4Array = primary[0]
	assert_int(d.size()).is_equal(LiveryRenderer.MAX_VEC4)
	# The rect: red (linear), half opacity, chrome, its own colour.
	assert_float(d[4].x).is_equal_approx(1.0, 0.001)
	assert_float(d[4].w).is_equal_approx(0.5, 0.001)
	assert_float(d[5].x).is_equal(0.0)
	assert_float(d[5].y).is_equal(float(LiveryRenderer.FINISH_CODES.chrome))
	# Right axis over the width: u runs -0.5..0.5 across it.
	assert_float(Vector3(d[1].x, d[1].y, d[1].z).length()).is_equal_approx(1.0 / 0.6, 0.001)
	# The chevrons: flipped (the normal reverses), mirrored, the contrast colour.
	var flags := int(d[8].w)
	assert_int(flags & LiveryRenderer.FLAG_FLIP).is_equal(LiveryRenderer.FLAG_FLIP)
	assert_int(flags & LiveryRenderer.FLAG_MIRROR).is_equal(LiveryRenderer.FLAG_MIRROR)
	assert_float(d[11].x).is_equal(float(LiveryRenderer.SOURCE_CODES.contrast))
	assert_float(d[7].w).is_equal(LiveryData.shape("chevrons").index)
	# The star is hidden: the secondary slot has only the rect.
	assert_int(LiveryRenderer.pack(l, "secondary")[1]).is_equal(1)
	assert_int(LiveryRenderer.pack(l, "glass")[1]).is_equal(0)


## A cut-out reaches down to its group's first layer as packed for that surface.
func test_cut_reaches_its_group() -> void:
	var l := _livery([
		_layer("rect"),
		_layer("rect", ["secondary"], { "group": 1 }),
		_layer("stripes", ["primary"], { "group": 1 }),
		_layer("rect", ["primary"], { "group": 1, "cut": true }),
		_layer("rect", ["primary"], { "cut": true }),
	], { "groups": [{ "id": 1, "name": "G" }] })
	var packed := LiveryRenderer.pack(l, "primary")
	var d: PackedVector4Array = packed[0]
	assert_int(packed[1]).is_equal(4)
	# On the primary: rect 0, stripes 1, the group's cut 2 (down to 1), the ungrouped cut 3 (down to 0).
	assert_int(int(d[2 * 6 + 2].w) & LiveryRenderer.FLAG_CUT).is_equal(LiveryRenderer.FLAG_CUT)
	assert_float(d[2 * 6 + 5].z).is_equal(1.0)
	assert_float(d[3 * 6 + 5].z).is_equal(0.0)


func test_slots_switch_shader_only_with_layers() -> void:
	assert_object(_paint("primary").shader).is_equal(CarVisual.PAINT_SHADER)
	var before: Color = _paint("primary").get_shader_parameter("paint_color")
	var detail := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	_paint("primary").set_shader_parameter("detail", detail)
	_visual.apply_livery(_livery([_layer("rect")]))
	assert_object(_paint("primary").shader).is_equal(CarVisual.LIVERY_SHADER)
	assert_object(_paint("secondary").shader).is_equal(CarVisual.PAINT_SHADER)
	assert_int(_paint("primary").get_shader_parameter("livery_count")).is_equal(1)
	# The paint came through the swap.
	assert_object(_paint("primary").get_shader_parameter("paint_color")).is_equal(before)
	assert_object(_paint("primary").get_shader_parameter("detail")).is_same(detail)
	_visual.set_livery_shown(false)
	assert_object(_paint("primary").shader).is_equal(CarVisual.PAINT_SHADER)
	_visual.set_livery_shown(true)
	assert_object(_paint("primary").shader).is_equal(CarVisual.LIVERY_SHADER)
	_visual.apply_livery({})
	assert_object(_paint("primary").shader).is_equal(CarVisual.PAINT_SHADER)


func test_base_paint_and_linked_colours() -> void:
	var l := _livery([_layer("rect", ["primary"], { "color": "secondary" })],
		{ "base": { "primary": { "color": "#102030", "finish": "matte" } } })
	_visual.apply_livery(l)
	assert_str((_paint("primary").get_shader_parameter("paint_color") as Color).to_html(false)).is_equal("102030")
	assert_float(_paint("primary").get_shader_parameter("roughness")).is_equal(CarVisual.FINISHES.matte[1])
	# AI or team paint later: the linked colours follow.
	_visual.set_paint("secondary", Color.RED)
	var slots: PackedVector4Array = _paint("primary").get_shader_parameter("livery_slots")
	assert_float(slots[1].x).is_equal_approx(1.0, 0.001)
	assert_float(slots[1].y).is_equal_approx(0.0, 0.001)
	# Dark primary: the contrast colour is light.
	assert_float(slots[3].x).is_greater(0.8)


func test_glass_only_when_layers_reach_it() -> void:
	_visual.apply_livery(_livery([_layer("rect")]))
	assert_int(_glass_overrides()).is_equal(0)
	_visual.apply_livery(_livery([_layer("rect", ["primary", "glass"])]))
	assert_int(_glass_overrides()).is_greater(0)
	_visual.apply_livery(_livery([_layer("rect")]))
	assert_int(_glass_overrides()).is_equal(0)


## Every mesh is told where it sits in the model, so layers stay on their part.
func test_meshes_know_their_place() -> void:
	_visual.apply_livery(_livery([_layer("rect")]))
	for mi: MeshInstance3D in _visual.model_root.find_children("*", "MeshInstance3D", true, false):
		var xf := _visual._xform_to(mi)
		var r0: Vector4 = mi.get_instance_shader_parameter("livery_r0")
		assert_float(r0.w).is_equal_approx(xf.origin.x, 0.0001)
		assert_float(r0.x).is_equal_approx(xf.basis.x.x, 0.0001)


## The mirror plane is the car's middle in model space, however the model is turned and scaled.
func test_mirror_plane() -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * 0.01), Vector3(0.2, 0.0, 0.0))
	var bounds := AABB(Vector3(-0.7, 0.0, -2.0), Vector3(1.8, 1.3, 4.0)) # middle at x 0.2
	var plane := LiveryRenderer.mirror_plane(xf, bounds)
	var n := Vector3(plane.x, plane.y, plane.z)
	# A point 0.5 m left of the middle reflects to 0.5 m right of it.
	var inverse := xf.affine_inverse()
	var p := inverse * Vector3(0.7, 0.5, 1.0)
	var reflected := p - 2.0 * (p.dot(n) - plane.w) * n
	assert_vector(xf * reflected).is_equal_approx(Vector3(-0.3, 0.5, 1.0), Vector3.ONE * 0.0001)


## Cars without a livery keep the plain shader, which knows nothing of liveries.
func test_plain_shader_stays_plain() -> void:
	assert_str(CarVisual.PAINT_SHADER.code).not_contains("livery_layers")


func _glass_overrides() -> int:
	var n := 0
	for mi: MeshInstance3D in _visual.model_root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m and m.shader == CarVisual.GLASS_SHADER:
				n += 1
	return n
