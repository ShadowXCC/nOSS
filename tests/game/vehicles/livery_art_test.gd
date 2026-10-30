extends GdUnitTestSuite
## The livery art (docs/VEHICLE_PACKAGE.md §12, tools/make_livery_art.gd): every shape in the
## catalog has its picture (the shader's code, or cells of the atlas), and every font loads.


func test_catalog_shapes() -> void:
	var cat := LiveryData.catalog()
	var procs := 0
	var used := {}
	var ids := {}
	for s: Dictionary in cat.shape_list:
		assert_bool(ids.has(s.id)).override_failure_message(String(s.id)).is_false()
		ids[s.id] = true
		assert_str(String(s.name)).is_not_empty()
		assert_bool(s.category in ["basic", "racing", "graphics", "plates", "sponsors"]).is_true()
		assert_int((s.params as Array).size()).is_equal((s.param_names as Array).size())
		if s.kind == "proc":
			assert_int(int(s.index)).is_equal(procs) # the shader's codes, in order
			procs += 1
			continue
		assert_str(String(s.kind)).is_equal("atlas")
		var cell := int(s.index)
		var span := int(s.get("span", 1))
		assert_int(cell % 16 + span).override_failure_message(String(s.id)).is_less_equal(16) # never wraps a row
		for k in span:
			assert_bool(used.has(cell + k)).override_failure_message(String(s.id)).is_false()
			used[cell + k] = true
	assert_int(procs).is_equal(16)
	assert_int(used.size()).is_greater(20)


## Each atlas shape has its picture in its cells, inside the cells (it doesn't reach their edges).
func test_atlas_pictures() -> void:
	var tex: Texture2D = LiveryRenderer.shapes_atlas()
	assert_object(tex).is_not_null()
	var image := tex.get_image()
	assert_vector(Vector2(image.get_size())).is_equal(Vector2(2048, 2048))
	if image.is_compressed():
		image.decompress()
	for s: Dictionary in LiveryData.catalog().shape_list:
		if s.kind != "atlas":
			continue
		var cell := int(s.index)
		var r := Rect2i(Vector2i(cell % 16, cell / 16) * 128, Vector2i(128 * int(s.get("span", 1)), 128))
		var inside := 0
		var edge := 0.0
		for y in range(r.position.y, r.end.y, 2):
			for x in range(r.position.x, r.end.x, 2):
				var v := image.get_pixel(x, y).r
				if v > 0.5:
					inside += 1
				if x == r.position.x or y == r.position.y or x >= r.end.x - 2 or y >= r.end.y - 2:
					edge = maxf(edge, v)
		assert_int(inside).override_failure_message(String(s.id)).is_greater(100)
		assert_float(edge).override_failure_message(String(s.id)).is_less(0.5)


func test_fonts_load() -> void:
	for f: Dictionary in LiveryData.catalog().font_list:
		assert_bool(ResourceLoader.exists(String(f.file))).override_failure_message(String(f.file)).is_true()
		assert_object(LiveryText.font(String(f.id))).is_not_null()
		assert_bool(FileAccess.file_exists(String(f.file).get_base_dir().path_join("OFL.txt"))).is_true()


## A layer of each shape cleans and packs (an atlas shape's code carries its cell and width).
func test_every_shape_packs() -> void:
	var l := LiveryData.new_livery("All")
	for s: Dictionary in LiveryData.catalog().shape_list:
		l.layers.append(LiveryData.new_layer("shape", Vector3.ZERO, Vector3.UP, Vector3.LEFT, Vector2.ONE, String(s.id)))
	l = LiveryData.clean(l)
	assert_int(l.layers.size()).is_equal(LiveryData.catalog().shape_list.size())
	var packed := LiveryRenderer.pack(l, "primary")
	var d: PackedVector4Array = packed[0]
	for i in l.layers.size():
		var s := LiveryData.shape(l.layers[i].shape)
		var code := int(d[i * 6 + 1].w)
		if s.kind == "proc":
			assert_int(code).is_equal(int(s.index))
		else:
			assert_int((code - 100) % 256).is_equal(int(s.index))
			assert_int(1 + (code - 100) / 256).is_equal(int(s.get("span", 1)))
