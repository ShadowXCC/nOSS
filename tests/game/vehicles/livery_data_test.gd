extends GdUnitTestSuite
## Livery files (docs/VEHICLE_PACKAGE.md §12): clean() keeps a good livery, makes a hostile one
## safe, and changes nothing the second time, so a livery's hash holds.

const FIXTURE := "res://tests/schemas/fixtures/livery/valid_stripes.json"


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func test_a_good_livery_comes_through() -> void:
	var l := LiveryData.clean(_fixture())
	assert_str(l.id).is_equal("1f0c5a2e-8d7b-4c1e-9a3f-2b6d4e8f0a11")
	assert_str(l.name).is_equal("Twin stripes")
	assert_int(l.layers.size()).is_equal(4)
	assert_str(l.layers[0].shape).is_equal("stripes")
	assert_bool(l.layers[1].cut).is_true()
	assert_str(l.layers[2].number).is_equal("auto")
	assert_float(l.layers[2].size[1]).is_equal(-0.5) # flipped
	assert_array(l.layers[3].on).contains_exactly(["primary", "glass"])
	assert_bool(LiveryData.uses_glass(l)).is_false() # that layer is hidden
	assert_str(l.base.primary.color).is_equal("#1F4FB5")
	assert_int(l.groups.size()).is_equal(1)


func test_clean_twice_changes_nothing() -> void:
	var once := LiveryData.clean(_fixture())
	var bytes := LiveryData.to_bytes(once)
	var again := LiveryData.parse(bytes)
	assert_str(LiveryData.to_bytes(again).get_string_from_utf8()).is_equal(bytes.get_string_from_utf8())
	assert_str(LiveryData.hash_of(again)).is_equal(LiveryData.hash_of(once))
	# Awkward numbers too: axes a little off square, sizes past the snap.
	var l := _fixture()
	l.layers[0].normal = [0.3, 0.9, 0.1]
	l.layers[0].right = [0.95, 0.31, 0.02]
	l.layers[0].size = [0.123456789, 1.0 / 3.0]
	l.layers[0].at = [1.0 / 7.0, 2.0 / 3.0, -5.0 / 9.0]
	once = LiveryData.clean(l)
	assert_str(LiveryData.to_bytes(LiveryData.clean(once)).get_string_from_utf8()).is_equal(LiveryData.to_bytes(once).get_string_from_utf8())
	var n := Vector3(once.layers[0].normal[0], once.layers[0].normal[1], once.layers[0].normal[2])
	var r := Vector3(once.layers[0].right[0], once.layers[0].right[1], once.layers[0].right[2])
	assert_float(n.length()).is_equal_approx(1.0, 0.001)
	assert_float(absf(n.dot(r))).is_less(0.001)


func test_a_hostile_livery_is_made_safe() -> void:
	var layers := []
	for i in 150:
		layers.append({ "kind": "shape", "shape": "rect", "at": [1e30, -1e30, 0], "normal": [0, 0, 0], "right": [0, 0, 0], "size": [0, 1e9],
			"depth": -4, "color": "red", "opacity": 7, "finish": "glitter", "on": ["roof", "glass", "glass", 3], "cut": "yes",
			"group": 77, "script": "rm -rf", "params": [9, -9, 0.5, 0.5, 0.5] })
	layers[0] = { "kind": "image", "at": [0, 0, 0], "normal": [0, 1, 0], "right": [1, 0, 0], "size": [1, 1] }
	layers[1] = { "kind": "shape", "shape": "../../evil", "at": [0, 0, 0], "normal": [0, 1, 0], "right": [1, 0, 0], "size": [1, 1] }
	layers[2] = { "kind": "text", "text": "\u0007A very long piece of text that goes well past the limit", "font": "comic", "at": [0, 0, 0],
		"normal": [0, 1, 0], "right": [0, 1, 0], "size": [1, 1] }
	layers[3] = { "kind": "number", "number": "-12", "at": "here", "normal": [0, 1, 0], "right": [1, 0, 0], "size": [1, 1] }
	layers[4] = { "kind": "text", "text": "   ", "at": [0, 0, 0], "normal": [0, 1, 0], "right": [1, 0, 0], "size": [1, 1] }
	var d := { "schema": "noss.livery/1", "id": "../../../etc/passwd", "name": 42, "layers": layers, "evil": true,
		"groups": [{ "id": 1, "name": "x" }, { "id": 1, "name": "dup" }, "nope"], "base": { "primary": { "color": "#GGGGGG", "finish": "solid" } } }
	var l := LiveryData.clean(d)
	assert_bool(LiveryData.valid_id(l.id)).is_true()
	assert_str(l.id).is_not_equal("../../../etc/passwd")
	assert_str(l.name).is_equal("Livery")
	assert_bool(l.has("evil")).is_false()
	assert_bool(l.base.has("primary")).is_false()
	assert_int(l.layers.size()).is_equal(LiveryData.MAX_LAYERS - 3) # 100 read, image, unknown shape and blank text dropped
	var text: Dictionary = l.layers[0]
	assert_str(text.text).is_equal("A very long piece of text that g")
	assert_str(text.font).is_equal(LiveryData.DEFAULT_FONT)
	var right := Vector3(text.right[0], text.right[1], text.right[2])
	assert_float(right.length()).is_equal_approx(1.0, 0.001)
	assert_float(absf(right.dot(Vector3.UP))).is_less(0.001)
	assert_str(l.layers[1].number).is_equal("auto")
	assert_array(l.layers[1].at).is_equal([0.0, 0.0, 0.0])
	var bad: Dictionary = l.layers[2]
	assert_float(bad.at[0]).is_equal_approx(LiveryData.LIMIT, 0.01)
	assert_float(bad.at[1]).is_equal_approx(-LiveryData.LIMIT, 0.01)
	assert_array(bad.normal).is_equal([0.0, 1.0, 0.0])
	assert_float(bad.size[0]).is_equal_approx(LiveryData.MIN_SIZE, 1e-7)
	assert_float(bad.size[1]).is_equal_approx(LiveryData.LIMIT, 0.01)
	assert_float(bad.depth).is_equal_approx(LiveryData.MIN_SIZE, 1e-7)
	assert_str(bad.color).is_equal("#FFFFFF")
	assert_float(bad.opacity).is_equal(1.0)
	assert_str(bad.finish).is_equal("paint")
	assert_array(bad.on).is_equal(["glass"])
	assert_bool(bad.has("cut")).is_false()
	assert_bool(bad.has("group")).is_false()
	assert_bool(bad.has("script")).is_false()
	assert_array(bad.params).is_equal([1.0, 0.0])
	assert_int(l.groups.size()).is_equal(0) # no layer kept a group
	assert_str(LiveryData.to_bytes(LiveryData.clean(l)).get_string_from_utf8()).is_equal(LiveryData.to_bytes(l).get_string_from_utf8())


func test_not_a_livery() -> void:
	assert_dict(LiveryData.clean("hello")).is_empty()
	assert_dict(LiveryData.clean({ "schema": "noss.paint/1", "layers": [] })).is_empty()
	assert_dict(LiveryData.clean({ "schema": 5, "layers": [] })).is_empty()
	assert_dict(LiveryData.parse("not json".to_utf8_buffer())).is_empty()
	assert_dict(LiveryData.parse(LiveryData.to_bytes(LiveryData.clean(_fixture())), 64)).is_empty()


## A group's layers end up together, where its lowest layer was.
func test_groups_stay_together() -> void:
	var d := { "schema": "noss.livery/1", "id": "g", "name": "G", "groups": [{ "id": 1, "name": "A" }, { "id": 2, "name": "B" }], "layers": [] }
	for g in [1, 0, 1, 2, 0, 2]:
		var l := LiveryData.new_layer("shape", Vector3.ZERO, Vector3.UP, Vector3.RIGHT, Vector2.ONE)
		l.opacity = 0.1 * (d.layers.size() + 1)
		if g:
			l.group = g
		d.layers.append(l)
	var l := LiveryData.clean(d)
	var groups: Array = l.layers.map(func(x: Dictionary) -> int: return int(x.get("group", 0)))
	assert_array(groups).is_equal([1, 1, 0, 2, 2, 0])
	var order: Array = l.layers.map(func(x: Dictionary) -> int: return roundi(x.opacity * 10.0))
	assert_array(order).is_equal([1, 3, 2, 4, 6, 5])


func test_new_layers() -> void:
	var s := LiveryData.new_layer("shape", Vector3(0, 1, 0), Vector3.UP, Vector3.RIGHT, Vector2(0.5, 0.25), "star")
	assert_str(s.shape).is_equal("star")
	assert_array(s.params).is_equal(LiveryData.shape("star").params)
	assert_str(LiveryData.layer_name(s)).is_equal("Star")
	var t := LiveryData.new_layer("text", Vector3.ZERO, Vector3.UP, Vector3.RIGHT, Vector2.ONE)
	assert_str(LiveryData.layer_name(t)).is_equal("Text nOSS")
	var n := LiveryData.new_layer("number", Vector3.ZERO, Vector3.UP, Vector3.RIGHT, Vector2.ONE)
	assert_str(LiveryData.layer_name(n)).is_equal("Race number")
	n.number = "42"
	assert_str(LiveryData.layer_name(n)).is_equal("Number 42")


## The frame is the fit's model transform in metres, with the model's bounds there.
func test_frame_of_a_fit() -> void:
	var fit := { "model_transform": { "rotation_deg": [0, 90, 0], "scale": 0.01, "offset_m": [0, 0.1, 0] },
		"envelope": { "min": [-200, 0, -90], "max": [200, 130, 90] } }
	var f := LiveryData.frame_of(fit)
	var l := LiveryData.new_livery("Test", { "id": "car" }, f)
	var fr := LiveryData.frame(l)
	var xf: Transform3D = fr[0]
	assert_vector(xf * Vector3(100, 0, 0)).is_equal_approx(Vector3(0, 0.1, -1.0), Vector3.ONE * 0.0001)
	var box: AABB = fr[1]
	assert_vector(box.size).is_equal_approx(Vector3(1.8, 1.3, 4.0), Vector3.ONE * 0.0001)
