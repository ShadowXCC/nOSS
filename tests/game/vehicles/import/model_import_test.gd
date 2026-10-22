extends GdUnitTestSuite
## Fitting Bay import and analysis (docs/VEHICLE_PACKAGE.md §7, PKG-02, PKG-03) on CC0 Kenney
## models (GLB with an external texture, FBX), the built-in cars and generated test cars.

const KENNEY := "res://tests/fixtures/models/kenney/"


func test_glb_with_external_texture_is_converted() -> void:
	var r := ModelImport.import_file(KENNEY + "sedan-sports.glb")
	assert_str(r.error).is_empty()
	assert_bool(r.converted).is_true()
	var check := PackageLoader.check_glb(r.glb, PackageLoader.DEFAULT_LIMITS)
	assert_str(check.error).is_empty()
	assert_float(check.texture_bytes).is_greater(0.0) # the texture made it in
	r.scene.free()


func test_clean_glb_is_kept_byte_for_byte() -> void:
	var path := "res://content/cars/noss_box/model/body.glb"
	var r := ModelImport.import_file(path)
	assert_bool(r.converted).is_false()
	assert_bool(r.glb == FileAccess.get_file_as_bytes(path)).is_true()
	r.scene.free()


func test_bad_files_are_refused() -> void:
	assert_str(ModelImport.import_file("res://README.md").error).is_equal("Pick a .glb, .gltf or .fbx file")
	assert_str(ModelImport.import_file("res://nope.glb").error).is_equal("File not found")


func test_kenney_sedan_wheels_and_scale() -> void:
	var a := _analyze(KENNEY + "sedan-sports.glb")
	assert_str(a.wheel_source).is_equal("parts")
	assert_array(a.fit.wheels.map(func(w: Dictionary) -> String: return w.id)).contains_exactly_in_any_order(["LF", "RF", "LR", "RR"])
	var lf: Dictionary = a.fit.wheels.filter(func(w: Dictionary) -> bool: return w.id == "LF")[0]
	assert_array(lf.spin_nodes).contains_exactly(["wheel-front-left"])
	assert_str(lf.pivot).is_equal("insert")
	assert_float(lf.center[2]).is_greater(0.0) # front is +Z
	assert_float(lf.center[0]).is_greater(0.0) # left is +X
	assert_float(a.fit.model_transform.scale).is_equal_approx(2.6 / 1.32, 0.01)
	assert_array(a.fit.model_transform.rotation_deg).is_equal([0.0, 0.0, 0.0])
	assert_array(JsonSchema.validate(a.fit, JsonSchema.load_schema("fit"))).is_empty()


func test_kenney_fbx_is_an_open_wheeler() -> void:
	var a := _analyze(KENNEY + "race.fbx")
	assert_str(a.wheel_source).is_equal("parts")
	assert_int(a.fit.wheels.size()).is_equal(4)
	assert_str(a.family).is_equal("open")


func test_named_hubs_are_used_as_they_are() -> void:
	var a := _analyze("res://content/cars/noss_box/model/body.glb")
	assert_str(a.wheel_source).is_equal("hubs")
	assert_str(a.family).is_equal("car")
	var lf: Dictionary = a.fit.wheels.filter(func(w: Dictionary) -> bool: return w.id == "LF")[0]
	assert_str(lf.node).is_equal("hub_LF")
	assert_str(lf.spin_node).is_equal("wheel_LF")
	assert_float(lf.radius).is_equal_approx(0.32, 0.001)
	assert_float(a.fit.model_transform.scale).is_equal(1.0)
	assert_dict(a.paint.slots).contains_keys(["primary", "secondary"])
	assert_str(a.fit.steering_wheel.node).is_equal("steering_wheel")


func test_merged_wheels_are_split_out() -> void:
	var scene := _merged_car(Basis.IDENTITY)
	var a := ModelAnalysis.analyze(scene)
	assert_str(a.wheel_source).is_equal("parts")
	assert_bool(a.scene_changed).is_true()
	assert_int(a.fit.wheels.size()).is_equal(4)
	for w: Dictionary in a.fit.wheels:
		var split: String = w.spin_nodes[0]
		assert_object(scene.find_child(split, true, false)).is_not_null()
	# The body lost the wheels' triangles.
	var body := scene.find_child("car", true, false) as MeshInstance3D
	assert_int((body.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3).is_equal(12)
	scene.free()


func test_sideways_z_up_model_is_turned() -> void:
	# Modelled with +Z up and +X forward: the analysis has to turn it.
	# Columns: where the car's left, up and forward point in the model.
	var scene := _merged_car(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)))
	var a := ModelAnalysis.analyze(scene)
	assert_int(a.fit.wheels.size()).is_equal(4)
	var r: Array = a.fit.model_transform.rotation_deg
	var turned := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
	assert_vector(turned * Vector3(0, 0, 1)).is_equal_approx(Vector3.UP, Vector3.ONE * 0.01)
	scene.free()


## A round part up on the roof (a turret ring) has the wheels' axle direction and size, but it
## isn't a wheel: the four on the ground are kept.
func test_a_round_part_on_the_roof_is_not_a_wheel() -> void:
	var scene := _merged_car(Basis.IDENTITY, true)
	var a := ModelAnalysis.analyze(scene)
	assert_array(a.fit.wheels.map(func(w: Dictionary) -> String: return w.id)).contains_exactly_in_any_order(["LF", "RF", "LR", "RR"])
	assert_array(a.notes).contains(["Ignored 1 wheel off the ground"])
	assert_float(a.fit.ground_y).is_equal_approx(0.0, 0.01)
	scene.free()


## A wheel arch liner round the right rear wheel only (the Tezeract's): bigger, chunky and a
## little tilted, it passes for round and lines up with the wheel. The wheel matches its partner
## on the left, so the liner stays on the body.
func test_an_arch_around_a_wheel_is_not_part_of_it() -> void:
	var scene := _merged_car(Basis.IDENTITY)
	var liner := MeshInstance3D.new()
	liner.name = "liner"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.46
	tube.bottom_radius = 0.46
	tube.height = 0.36
	tube.radial_segments = 24
	tube.rings = 1
	liner.mesh = tube
	liner.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(16.0)) * Basis(Vector3.BACK, PI / 2.0), Vector3(-0.85, 0.36, -1.32))
	scene.add_child(liner)
	liner.owner = scene
	var a := ModelAnalysis.analyze(scene)
	assert_array(a.fit.wheels.map(func(w: Dictionary) -> String: return w.id)).contains_exactly_in_any_order(["LF", "RF", "LR", "RR"])
	for w: Dictionary in a.fit.wheels:
		assert_float(w.radius).override_failure_message(w.id).is_equal_approx(0.32, 0.01)
		assert_array(w.spin_nodes).override_failure_message(w.id).not_contains(["liner"])
	scene.free()


## An older import's fit with a wheel on the roof: found in the model's own frame (here +Z up).
func test_floating_wheels_are_found_in_a_fit() -> void:
	var scene := _merged_car(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)))
	var fit := ModelAnalysis.analyze(scene).fit
	scene.free()
	assert_array(ModelAnalysis.floating_wheels(fit)).is_empty()
	fit.wheels.append({ "id": "C2", "axle": 2, "side": "C", "center": [0.0, 0.0, 2.0], "radius": 0.32, "width": 0.2 })
	assert_array(ModelAnalysis.floating_wheels(fit)).contains_exactly(["C2"])


func test_no_wheels_gives_stock_anchors() -> void:
	var scene := Node3D.new()
	var blob := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.3, 4.4)
	blob.mesh = box
	blob.position.y = 0.65
	scene.add_child(blob)
	var a := ModelAnalysis.analyze(scene)
	assert_str(a.wheel_source).is_empty()
	assert_str(a.fit.wheel_mode).is_equal("stock")
	assert_int(a.fit.wheels.size()).is_equal(4)
	assert_array(JsonSchema.validate(a.fit, JsonSchema.load_schema("fit"))).is_empty()
	scene.free()


func test_imported_car_packs_and_drives() -> void:
	var r := ModelImport.import_file(KENNEY + "kart-oobi.glb")
	var draft := FittingDraft.from_import(r)
	draft.id = PackageWriter.new_uuid()
	draft.edit_path = "user://tests/writer/kart.noss"
	DirAccess.make_dir_recursive_absolute("user://tests/writer")
	if FileAccess.file_exists(draft.edit_path):
		DirAccess.remove_absolute(draft.edit_path)
	var packed := draft.pack()
	assert_str(packed.error).is_empty()
	var pkg := PackageLoader.load_package(draft.edit_path)
	assert_str(pkg.error).is_empty()
	assert_int(pkg.lods.size()).is_greater(1)
	var platform := PlatformLoader.load_official("official.kart.medium")
	var vehicle := Vehicle.create(platform, pkg)
	assert_int(vehicle.visual.wheel_count()).is_equal(4)
	# The inserted pivot holds the wheel part, centred on the wheel.
	var hub := vehicle.visual.model_root.get_child(0).find_child("noss_hub_LF", true, false) as Node3D
	assert_object(hub).is_not_null()
	assert_object(hub.find_child("wheel-front-left", true, false)).is_not_null()
	vehicle.free()
	draft.free_scene()


static func _analyze(path: String) -> ModelAnalysis.Result:
	var r := ModelImport.import_file(path)
	var a := ModelAnalysis.analyze(r.scene)
	r.scene.free()
	return a


## A car body box with four cylinder wheels, all in one mesh, turned by `basis`; with
## `roof_disc`, a wheel-sized disc stands on the roof too.
static func _merged_car(basis: Basis, roof_disc := false) -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := BoxMesh.new()
	body.size = Vector3(1.7, 0.9, 4.2)
	st.append_from(body, 0, Transform3D(basis, basis * Vector3(0, 0.75, 0)))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.32
	wheel.bottom_radius = 0.32
	wheel.height = 0.24
	wheel.radial_segments = 24
	wheel.rings = 1
	for x in [0.85, -0.85]:
		for z in [1.3, -1.3]:
			var xf := Transform3D(basis * Basis(Vector3.BACK, PI / 2.0), basis * Vector3(x, 0.32, z))
			st.append_from(wheel, 0, xf)
	if roof_disc:
		st.append_from(wheel, 0, Transform3D(basis * Basis(Vector3.BACK, PI / 2.0), basis * Vector3(0.2, 1.9, 0.0)))
	var mi := MeshInstance3D.new()
	mi.name = "car"
	mi.mesh = st.commit()
	var root := Node3D.new()
	root.add_child(mi)
	mi.owner = root
	return root


## Records the phases import_file() reports, in order.
class RecordingProgress:
	extends ModelImport.Progress

	var seen: Array[String] = []
	var fractions: Array[float] = []

	func report(fraction: float, phase: String) -> void:
		super.report(fraction, phase)
		if seen.is_empty() or seen[-1] != phase:
			seen.append(phase)
		fractions.append(fraction)


func test_progress_runs_through_its_phases() -> void:
	var progress := RecordingProgress.new()
	var r := ModelImport.import_file(KENNEY + "sedan-sports.glb", PackageLoader.DEFAULT_LIMITS, progress)
	assert_str(r.error).is_empty()
	assert_array(progress.seen).is_equal([
		"Reading sedan-sports.glb", "Checking the file", "Reading the model",
		"Converting the model", "Checking the model", "Loading the model",
	])
	for i in range(1, progress.fractions.size()):
		assert_float(progress.fractions[i]).is_greater_equal(progress.fractions[i - 1])
	assert_float(progress.read().fraction).is_equal(1.0)
	r.scene.free()


func test_a_clean_glb_has_nothing_to_convert() -> void:
	var progress := RecordingProgress.new()
	var r := ModelImport.import_file("res://content/cars/noss_box/model/body.glb", PackageLoader.DEFAULT_LIMITS, progress)
	assert_str(r.error).is_empty()
	assert_bool("Converting the model" in progress.seen).is_false()
	assert_float(progress.read().fraction).is_equal(1.0)
	r.scene.free()
