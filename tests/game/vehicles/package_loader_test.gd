extends GdUnitTestSuite
## Package loading and the safety checks in docs/VEHICLE_PACKAGE.md §9 (PKG-01, PKG-08).

const BOX := "res://content/cars/noss_box"
const TMP := "user://tests/packages/"


func before() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)


func after() -> void:
	for file in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP + file)


func test_official_box_loads() -> void:
	var pkg := PackageLoader.load_package(BOX)
	assert_str(pkg.error).is_empty()
	assert_str(pkg.display_name()).is_equal("nOSS Box")
	assert_str(pkg.hash).starts_with("sha256:")
	assert_int(pkg.lods.size()).is_equal(1)
	assert_int(pkg.triangles).is_greater(500)
	assert_object(pkg.lods[0].find_child("hub_LF", true, false)).is_not_null()
	pkg.free_scenes()


func test_zipped_package_loads_and_hash_is_stable() -> void:
	var path := _zip("good.noss", _box_files())
	var a := PackageLoader.load_package(path)
	var b := PackageLoader.load_package(BOX)
	assert_str(a.error).is_empty()
	assert_str(a.hash).is_equal(b.hash)
	a.free_scenes()
	b.free_scenes()


func test_tampered_file_is_rejected() -> void:
	var files := _box_files()
	files["paint.json"] = files["paint.json"].get_string_from_utf8().replace("E8B71A", "000000").to_utf8_buffer()
	assert_str(PackageLoader.load_package(_zip("tampered.noss", files)).error).starts_with("Hash mismatch")


func test_unlisted_file_is_rejected() -> void:
	var files := _box_files()
	files["extra.json"] = "{}".to_utf8_buffer()
	assert_str(PackageLoader.load_package(_zip("unlisted.noss", files)).error).starts_with("File not in manifest")


func test_missing_manifest_is_rejected() -> void:
	var files := _box_files()
	files.erase("manifest.json")
	assert_str(PackageLoader.load_package(_zip("nomanifest.noss", files)).error).is_equal("No manifest.json")


func test_disallowed_file_type_is_rejected() -> void:
	var files := _box_files()
	files["evil.tscn"] = "[gd_scene]".to_utf8_buffer()
	assert_str(PackageLoader.load_package(_zip("tscn.noss", files)).error).contains("not allowed")


func test_not_a_zip_is_rejected() -> void:
	var f := FileAccess.open(TMP + "junk.noss", FileAccess.WRITE)
	f.store_string("hello, not a zip")
	f.close()
	assert_str(PackageLoader.load_package(TMP + "junk.noss").error).is_equal("not a zip")


func test_limits_can_only_be_lowered() -> void:
	var pkg := PackageLoader.load_package(BOX, { "max_lod0_triangles": 100 })
	assert_str(pkg.error).starts_with("Too many triangles")
	pkg = PackageLoader.load_package(BOX, { "max_lod0_triangles": 10_000_000 })
	assert_str(pkg.error).is_empty()
	pkg.free_scenes()


func test_glb_checks() -> void:
	var glb := FileAccess.get_file_as_bytes(BOX + "/model/body.glb")
	var check := PackageLoader.check_glb(glb, PackageLoader.DEFAULT_LIMITS)
	assert_str(check.error).is_empty()
	var lim := PackageLoader.DEFAULT_LIMITS.duplicate()
	lim.max_materials = 3
	assert_str(PackageLoader.check_glb(glb, lim).error).is_equal("too many materials")
	assert_str(PackageLoader.check_glb(glb.slice(0, 100), lim).error).is_not_empty()


func test_lists_official_content() -> void:
	assert_array(PackageLoader.list_available()).contains([BOX])


func test_async_load_reports_on_main_thread() -> void:
	var result := []
	PackageLoader.load_async(BOX, func(pkg: VehiclePackage) -> void: result.append(pkg))
	await await_millis(10)
	var waited := 0
	while result.is_empty() and waited < 5000:
		await await_millis(20)
		waited += 20
	assert_int(result.size()).is_equal(1)
	assert_str(result[0].error).is_empty()
	result[0].free_scenes()


func _box_files() -> Dictionary:
	var files := {}
	for rel in ["manifest.json", "fit.json", "paint.json", "sound/profile.json", "model/body.glb"]:
		files[rel] = FileAccess.get_file_as_bytes(BOX + "/" + rel)
	return files


func _zip(file_name: String, files: Dictionary) -> String:
	var zip := ZIPPacker.new()
	zip.open(TMP + file_name)
	for rel: String in files:
		zip.start_file(rel)
		zip.write_file(files[rel])
		zip.close_file()
	zip.close()
	return TMP + file_name


## Leaving a screen while its car loads: the result is dropped, not delivered to a freed node.
func test_a_load_for_a_freed_node_is_dropped() -> void:
	var asker := Asker.new()
	add_child(asker)
	var got := []
	asker.ask(got)
	asker.free()
	for i in 120:
		await get_tree().process_frame
	assert_array(got).is_empty()


class Asker:
	extends Node

	func ask(got: Array) -> void:
		PackageLoader.load_async("res://content/cars/noss_box", func(pkg: VehiclePackage) -> void:
			got.append(name)
			pkg.free_scenes())
