extends GdUnitTestSuite
## Writing .noss packages (docs/VEHICLE_PACKAGE.md §1-2, PKG-04): they load back, keep their id,
## bump their version only when something changed, and a bad car never lands in the garage.

const BOX := "res://content/cars/noss_box"
const DIR := "user://tests/writer/"
const INFO := { "name": "Test Box", "author": "tests", "license": "CC0-1.0", "family": "car", "tags": ["test"] }


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)


func test_written_package_loads() -> void:
	var files := PackageWriter.read_folder(BOX)
	assert_array(files.keys()).contains(["fit.json", "paint.json", "model/body.glb", "sound/profile.json"])
	var r := PackageWriter.write(DIR + "box.noss", INFO, files)
	assert_str(r.error).is_empty()
	assert_bool(r.ok).is_true()
	var pkg := PackageLoader.load_package(DIR + "box.noss")
	assert_str(pkg.error).is_empty()
	assert_str(pkg.display_name()).is_equal("Test Box")
	assert_int(int(pkg.manifest.version)).is_equal(1)
	var uuid4 := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	assert_bool(uuid4.search(pkg.manifest.id) != null).is_true()
	# The manifest is the zip's first entry.
	var zip := ZIPReader.new()
	zip.open(DIR + "box.noss")
	assert_str(zip.get_files()[0]).is_equal("manifest.json")
	zip.close()
	pkg.free_scenes()


func test_resave_bumps_version_only_on_change() -> void:
	var files := PackageWriter.read_folder(BOX)
	var info := INFO.merged({ "id": PackageWriter.new_uuid() })
	assert_bool(PackageWriter.write(DIR + "box.noss", info, files).ok).is_true()
	var again := PackageWriter.write(DIR + "box.noss", info, files)
	assert_bool(again.unchanged).is_true()
	var paint: Dictionary = JSON.parse_string(files["paint.json"].get_string_from_utf8())
	paint.slots.primary.color = "#FF0000"
	files["paint.json"] = PackageWriter.canonical_json(paint).to_utf8_buffer()
	var changed := PackageWriter.write(DIR + "box.noss", info, files)
	assert_bool(changed.ok).is_true()
	assert_int(int(changed.manifest.version)).is_equal(2)
	# Another car can't take over the file.
	var other := PackageWriter.write(DIR + "box.noss", INFO.merged({ "id": PackageWriter.new_uuid() }), files)
	assert_str(other.error).is_equal("Another car uses that file")


func test_bad_content_never_replaces_a_car() -> void:
	var files := PackageWriter.read_folder(BOX)
	var info := INFO.merged({ "id": PackageWriter.new_uuid() })
	PackageWriter.write(DIR + "box.noss", info, files)
	var before := FileAccess.get_file_as_bytes(DIR + "box.noss")
	var broken := files.duplicate()
	broken["model/body.glb"] = "not a glb".to_utf8_buffer()
	var r := PackageWriter.write(DIR + "box.noss", info, broken)
	assert_bool(r.ok).is_false()
	assert_str(r.error).starts_with("Saved car doesn't load")
	assert_bool(FileAccess.get_file_as_bytes(DIR + "box.noss") == before).is_true()
	assert_bool(FileAccess.file_exists(DIR + "box.noss.tmp")).is_false()
	var bad_fit := files.duplicate()
	bad_fit["fit.json"] = "{}".to_utf8_buffer()
	assert_str(PackageWriter.write(DIR + "x.noss", info, bad_fit).error).starts_with("fit.json:")


func test_unpack_round_trip() -> void:
	PackageWriter.write(DIR + "box.noss", INFO, PackageWriter.read_folder(BOX))
	var dir := DIR + "unpacked"
	assert_str(PackageWriter.unpack(DIR + "box.noss", dir)).is_empty()
	var pkg := PackageLoader.load_package(dir)
	assert_str(pkg.error).is_empty()
	pkg.free_scenes()


func test_garage_path() -> void:
	assert_str(PackageWriter.garage_path("1997 Acura NSX!", "x")).is_equal(PackageLoader.GARAGE_DIR + "1997_acura_nsx.noss")
	assert_str(PackageWriter.garage_path("???", "x")).is_equal(PackageLoader.GARAGE_DIR + "car.noss")
