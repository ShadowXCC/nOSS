extends GdUnitTestSuite
## Text and race-number layers (docs/VEHICLE_PACKAGE.md §12): strings set as distance fields on
## the CPU (headless too), packed into one atlas per livery and shared between layers and cars.


func _layer(kind: String, extra := {}) -> Dictionary:
	var l := LiveryData.new_layer(kind, Vector3.ZERO, Vector3.UP, Vector3.LEFT, Vector2(1.0, 0.3))
	l.merge(extra, true)
	return l


func test_every_font_sets_digits() -> void:
	for f: Dictionary in LiveryData.catalog().font_list:
		var image := LiveryText.string_image("0123456789", String(f.id))
		assert_object(image).override_failure_message(String(f.id)).is_not_null()
		assert_int(image.get_format()).is_equal(Image.FORMAT_RGBA8)
		assert_float(LiveryText.aspect("0123456789", String(f.id))).override_failure_message(String(f.id)).is_greater(2.0)
		# Inside a glyph somewhere: the true distance (alpha) half a pixel past the edge (Retro is thin).
		var inside := false
		var data := image.get_data()
		for i in range(3, data.size(), 4):
			if data[i] > 128 + 255 / (2 * LiveryText.RANGE):
				inside = true
				break
		assert_bool(inside).override_failure_message(String(f.id)).is_true()


func test_longer_text_is_wider() -> void:
	assert_float(LiveryText.aspect("RACE 42", "russo_one")).is_greater(LiveryText.aspect("42", "russo_one"))
	assert_object(LiveryText.string_image("   ", "russo_one")).is_null()


func test_numbers() -> void:
	var auto := _layer("number")
	assert_str(LiveryText.layer_text(auto, "7")).is_equal("7")
	assert_str(LiveryText.layer_text(auto, "")).is_equal(LiveryText.PLACEHOLDER_NUMBER)
	auto.number = "42"
	assert_str(LiveryText.layer_text(auto, "7")).is_equal("42")


func test_atlas_per_livery() -> void:
	var l := LiveryData.new_livery("Text")
	l.layers = [_layer("text", { "text": "nOSS" }), LiveryData.new_layer("shape", Vector3.ZERO, Vector3.UP, Vector3.LEFT, Vector2.ONE),
		_layer("number"), _layer("number", { "mirror": true }), _layer("text", { "text": "Hidden", "hidden": true })]
	l = LiveryData.clean(l)
	var built := LiveryText.build(l, "12")
	var atlas: Texture2D = built[0]
	var rects: Dictionary = built[1]
	assert_object(atlas).is_not_null()
	assert_array(rects.keys()).contains_exactly_in_any_order([0, 2, 3])
	# Two layers showing the same number share its place.
	assert_object(rects[2]).is_equal(rects[3])
	for i: int in rects:
		var r: Rect2 = rects[i]
		assert_bool(Rect2(0, 0, 1, 1).encloses(r)).is_true()
	# The same livery and number again: the same atlas.
	assert_object(LiveryText.build(l, "12")[0]).is_same(atlas)
	assert_object(LiveryText.build(l, "13")[0]).is_not_same(atlas)
	# Packed for the shader: text layers carry their rect; an auto number keeps its shape.
	var packed := LiveryRenderer.pack(l, "primary", rects)
	assert_int(packed[1]).is_equal(4)
	var d: PackedVector4Array = packed[0]
	var r0: Rect2 = rects[0]
	assert_vector(Vector2(d[3].x, d[3].y)).is_equal(r0.position)
	assert_int(int(d[2].w) & LiveryRenderer.FLAG_TEXT).is_equal(LiveryRenderer.FLAG_TEXT)
	assert_int(int(d[2 * 6 + 2].w) & LiveryRenderer.FLAG_FIT).is_equal(LiveryRenderer.FLAG_FIT)
	assert_int(int(d[2].w) & LiveryRenderer.FLAG_FIT).is_equal(0)


func test_no_text_no_atlas() -> void:
	var l := LiveryData.new_livery("Shapes")
	l.layers = [LiveryData.new_layer("shape", Vector3.ZERO, Vector3.UP, Vector3.LEFT, Vector2.ONE)]
	assert_object(LiveryText.build(LiveryData.clean(l), "1")[0]).is_null()
