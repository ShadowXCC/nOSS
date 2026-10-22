extends GdUnitTestSuite
## Hand edits to a draft's wheels (WheelEdit, docs/VEHICLE_PACKAGE.md §7 step 3) on a generated
## car: a body box and four wheels in one mesh, a block by the left front wheel in that mesh too,
## and a wheel arch liner round the right rear one as a mesh of its own.

var _draft: FittingDraft
var _edit: WheelEdit


func before_test() -> void:
	_draft = FittingDraft.new()
	_draft.scene = _car()
	var a := ModelAnalysis.analyze(_draft.scene)
	_draft.fit = a.fit
	_edit = WheelEdit.new(_draft)


func after_test() -> void:
	_draft.free_scene()


func test_the_finder_leaves_the_liner_out() -> void:
	assert_array(Array(_edit.ids())).contains_exactly_in_any_order(["LF", "RF", "LR", "RR"])
	assert_str(_edit.part_of("liner")).is_empty()
	assert_float(_edit.values("RR").radius).is_equal_approx(0.32 * _scale(), 0.01)


## Adding a part measures the wheel from its parts (the liner is the biggest round one), and
## dropping it measures it again from the rest.
func test_adding_and_dropping_a_part() -> void:
	var liner := _draft.scene.find_child("liner", true, false) as MeshInstance3D
	assert_str(_edit.toggle("RR", _edit._whole(liner))).is_equal("Added to RR")
	assert_array(_edit.wheel("RR").spin_nodes).contains(["liner"])
	assert_float(float(_edit.wheel("RR").radius)).is_equal_approx(0.46, 0.01)
	assert_str(_edit.toggle("RR", _edit._whole(liner))).is_equal("Dropped from RR")
	assert_array(_edit.wheel("RR").spin_nodes).not_contains(["liner"])
	assert_float(float(_edit.wheel("RR").radius)).is_equal_approx(0.32, 0.01)


## The block next to the left front wheel is part of the body mesh: it's offered, and taking it
## splits it out into a mesh of its own.
func test_a_part_of_the_body_is_split_out() -> void:
	var near := _edit.nearby("LF").filter(func(p: Dictionary) -> bool: return p.surface >= 0 and p.triangles.size() == 48)
	assert_int(near.size()).is_equal(1)
	if near.is_empty():
		return
	var body := _draft.scene.find_child("car", true, false) as MeshInstance3D
	var before := (body.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_draft.scene_changed = false
	_edit.toggle("LF", near[0])
	assert_bool(_draft.scene_changed).is_true()
	var split: String = _edit.wheel("LF").spin_nodes[-1]
	assert_str(split).starts_with("noss_split_LF_")
	assert_object(_draft.scene.find_child(split, true, false)).is_not_null()
	assert_int((body.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3).is_equal(before - 48)
	# Not round, so the wheel keeps its size.
	assert_float(float(_edit.wheel("LF").radius)).is_equal_approx(0.32, 0.01)


func test_mirror_moves_the_partner() -> void:
	var rr: Dictionary = _edit.values("RR")
	var lr: Dictionary = _edit.values("LR")
	_edit.move("LR", "along", lr.along - 0.1)
	_edit.move("LR", "across", lr.across + 0.05)
	assert_float(_edit.values("RR").along).is_equal_approx(rr.along - 0.1, 0.001)
	assert_float(_edit.values("RR").across).is_equal_approx(rr.across - 0.05, 0.001)
	_edit.move("LR", "radius", 0.5, false)
	assert_float(_edit.values("LR").radius).is_equal_approx(0.5, 0.001)
	assert_float(_edit.values("RR").radius).is_equal_approx(rr.radius, 0.001)


func test_a_wheel_comes_out_but_not_an_axle() -> void:
	assert_str(_edit.remove("LF")).is_equal("LF removed")
	assert_str(_edit.remove("RF")).is_equal("Need wheels front and back")
	assert_array(Array(_edit.ids())).contains_exactly_in_any_order(["RF", "LR", "RR"])


## A wheel taken out can be made again from its part, and gets its id back.
func test_a_new_wheel_from_a_part() -> void:
	var part: String = _edit.wheel("LF").spin_nodes[0]
	_edit.remove("LF")
	var id := _edit.add(_edit._whole(_draft.scene.find_child(part, true, false) as MeshInstance3D))
	assert_str(id).is_equal("LF")
	assert_array(Array(_edit.ids())).contains_exactly_in_any_order(["LF", "RF", "LR", "RR"])
	assert_float(_edit.values("LF").along).is_greater(0.0)
	assert_array(JsonSchema.validate(_draft.fit, JsonSchema.load_schema("fit"))).is_empty()


## An older import whose right rear wheel took the liner in: the finder, run again, puts it right.
func test_find_again_fixes_an_older_fit() -> void:
	var liner := _draft.scene.find_child("liner", true, false) as MeshInstance3D
	_edit.toggle("RR", _edit._whole(liner))
	assert_int(_edit.find_again()).is_equal(4)
	assert_str(_edit.part_of("liner")).is_empty()
	assert_float(float(_edit.wheel("RR").radius)).is_equal_approx(0.32, 0.01)
	assert_array(JsonSchema.validate(_draft.fit, JsonSchema.load_schema("fit"))).is_empty()


func test_parts_are_listed_by_name_or_number() -> void:
	assert_str(WheelEdit.label({ "node": "wheel_rr", "surface": -1, "size": 0.58 }, 2)).is_equal("wheel_rr · 0.58 m")
	assert_str(WheelEdit.label({ "node": "noss_split_RR_0", "surface": -1, "size": 0.46 }, 2)).is_equal("Part 2 · 0.46 m")
	assert_str(WheelEdit.label({ "node": "car", "surface": 0, "size": 0.2 }, 3)).is_equal("Part 3 · 0.20 m")


func _scale() -> float:
	return float(_draft.fit.model_transform.scale)


## The car: a 4.2 m body box and four 0.32 m wheels in one mesh, a block beside the left front
## wheel in that mesh, and a liner round the right rear wheel (bigger, a little tilted).
static func _car() -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := BoxMesh.new()
	body.size = Vector3(1.7, 0.9, 4.2)
	st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.32
	wheel.bottom_radius = 0.32
	wheel.height = 0.24
	wheel.radial_segments = 24
	wheel.rings = 1
	for x in [0.85, -0.85]:
		for z in [1.3, -1.3]:
			st.append_from(wheel, 0, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(x, 0.32, z)))
	var block := BoxMesh.new()
	block.size = Vector3(0.06, 0.12, 0.08)
	block.subdivide_width = 1
	block.subdivide_height = 1
	block.subdivide_depth = 1 # 48 triangles: enough to be offered
	st.append_from(block, 0, Transform3D(Basis.IDENTITY, Vector3(0.62, 0.45, 1.3)))
	var car := MeshInstance3D.new()
	car.name = "car"
	car.mesh = st.commit()
	var root := Node3D.new()
	root.add_child(car)
	car.owner = root
	var tube := CylinderMesh.new()
	tube.top_radius = 0.46
	tube.bottom_radius = 0.46
	tube.height = 0.36
	tube.radial_segments = 24
	tube.rings = 1
	var liner_st := SurfaceTool.new()
	liner_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	liner_st.append_from(tube, 0, Transform3D.IDENTITY)
	var liner := MeshInstance3D.new()
	liner.name = "liner"
	liner.mesh = liner_st.commit()
	liner.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(16.0)) * Basis(Vector3.BACK, PI / 2.0), Vector3(-0.85, 0.36, -1.32))
	root.add_child(liner)
	liner.owner = root
	return root
